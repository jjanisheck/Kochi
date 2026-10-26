import * as THREE from 'three';
import { boneKey } from './core.mjs';

const bindFrames=new WeakMap();

export function restoreBindPose(root) {
  root.updateMatrixWorld(true);
  if (!bindFrames.has(root)) {
    const locals=new Map();
    root.traverse(node=>{if(node.isBone)locals.set(node,{position:node.position.clone(),quaternion:node.quaternion.clone(),scale:node.scale.clone()});});
    bindFrames.set(root,{rootWorld:root.matrixWorld.clone(),locals});
  }
  const frame=bindFrames.get(root);
  const placement=root.matrixWorld.clone().multiply(frame.rootWorld.clone().invert());
  const skeletons = new Set();
  root.traverse(node => { if (node.isSkinnedMesh) skeletons.add(node.skeleton); });
  const worlds=new Map();
  for (const skeleton of skeletons) for (let i=0;i<skeleton.bones.length;i++) {
    const bone=skeleton.bones[i];
    if (!worlds.has(bone)) worlds.set(bone,placement.clone().multiply(skeleton.boneInverses[i].clone().invert()));
  }
  // Skeleton.pose() assumes a root bone's non-bone parent is identity. FBX
  // armatures can rotate -90° and scale 100×. Reconstruct local transforms
  // against the actual parent, including the workshop's model placement.
  root.traverse(node=>{
    if (node.isBone) {
      const world=worlds.get(node);
      if (world) {
        const local=node.parent ? node.parent.matrixWorld.clone().invert().multiply(world) : world;
        local.decompose(node.position,node.quaternion,node.scale);
      } else {
        const local=frame.locals.get(node);
        if (local) { node.position.copy(local.position); node.quaternion.copy(local.quaternion); node.scale.copy(local.scale); }
      }
    }
    node.updateWorldMatrix(false,false);
  });
  root.updateMatrixWorld(true);
}

export function canonicalBones(root) {
  const bones = new Map();
  root.traverse(node => {
    // Match PropertyBinding's first node when FBXLoader nests duplicate bones.
    if (node.isBone && !bones.has(boneKey(node.name))) bones.set(boneKey(node.name),node);
  });
  return bones;
}

export function captureRestPose(root) {
  restoreBindPose(root);
  return new Map([...canonicalBones(root)].map(([role,bone]) => [role,{
    name:bone.name,
    position:bone.position.clone(),
    parentRole:bone.parent?.isBone ? boneKey(bone.parent.name) : null,
    world:bone.getWorldQuaternion(new THREE.Quaternion()),
    parent:bone.parent?.getWorldQuaternion(new THREE.Quaternion()) || new THREE.Quaternion(),
  }]));
}

const primaryChild={hips:'spine',spine:'spine1',spine1:'spine2',spine2:'neck',neck:'head',head:'headtopend'};
for (const side of ['left','right']) {
  Object.assign(primaryChild,{
    [side+'shoulder']:side+'arm',[side+'arm']:side+'forearm',[side+'forearm']:side+'hand',[side+'hand']:side+'handmiddle1',
    [side+'upleg']:side+'leg',[side+'leg']:side+'foot',[side+'foot']:side+'toebase',
  });
  for (const finger of ['thumb','index','middle','ring','pinky']) for (let i=1;i<4;i++) primaryChild[`${side}hand${finger}${i}`]=`${side}hand${finger}${i+1}`;
}

function anatomicalAxes(sourceRest,targetRest) {
  let differentPose=false;
  const axes=new Map();
  for (const role of targetRest.keys()) {
    const source=sourceRest.get(primaryChild[role]), target=targetRest.get(primaryChild[role]);
    const axis=new THREE.Quaternion();
    if (source && target && source.position.length()>0.0001 && target.position.length()>0.0001) {
      const from=target.position.clone().normalize(), to=source.position.clone().normalize();
      axis.setFromUnitVectors(from,to);
      if (['leftarm','rightarm'].includes(role)) {
        const sourceDirection=to.applyQuaternion(sourceRest.get(role).world);
        const targetDirection=from.applyQuaternion(targetRest.get(role).world);
        if (sourceDirection.angleTo(targetDirection)>0.35) differentPose=true;
      }
    }
    axes.set(role,axis);
  }
  return {differentPose,axes};
}

export function retargetMotion(raw,label,sourceRest,targetRest) {
  const tracks = [];
  let matched = 0, expected = 0;
  const {differentPose,axes}=anatomicalAxes(sourceRest,targetRest);
  for (const track of raw.tracks) {
    const parsed = THREE.PropertyBinding.parseTrackName(track.name);
    const role = boneKey(parsed.objectName === 'bones' ? parsed.objectIndex : parsed.nodeName);
    const target = targetRest.get(role), source = sourceRest.get(role);
    if (parsed.propertyName === 'quaternion') expected++;
    if (!target || !source) continue;
    const copy = track.clone();
    copy.name = `${target.name}.${parsed.propertyName}`;
    if (parsed.propertyName === 'quaternion') {
      // Convert between bind orientations instead of only renaming tracks.
      let left = target.parent.clone().invert().multiply(source.parent);
      let right = source.world.clone().invert().multiply(target.world);
      if (differentPose) {
        // A source T-pose and a target A/posed bind frame cannot share a
        // world-rest delta: that adds the target's bent arms to every motion.
        // Map anatomical bone directions instead; preserve target bone lengths.
        if (source.parentRole && source.parentRole===target.parentRole) left=(axes.get(target.parentRole) || new THREE.Quaternion()).clone().invert();
        right=axes.get(role) || new THREE.Quaternion();
      }
      const rotation = new THREE.Quaternion();
      for (let i = 0; i < copy.values.length; i += 4) {
        rotation.fromArray(copy.values,i).premultiply(left).multiply(right).normalize().toArray(copy.values,i);
      }
      matched++;
    } else if (parsed.propertyName === 'position') {
      if (!['hips','root'].includes(role)) continue;
      // Use this character's proportions and root height, including seated clips.
      for (let i = 0; i < copy.values.length; i += 3) target.position.toArray(copy.values,i);
    } else if (parsed.propertyName !== 'scale') continue;
    tracks.push(copy);
  }
  if (!matched || matched / Math.max(1,expected) < 0.9) {
    throw new Error(`${label}: only ${matched}/${expected} animated bones match this character. Use a Mixamo humanoid rig.`);
  }
  return new THREE.AnimationClip(label,raw.duration,tracks);
}
