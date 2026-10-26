import test from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import { captureRestPose, canonicalBones, retargetMotion, restoreBindPose } from '../rig.mjs';
import { isCharacterFile, modelLabel, sanitizeSettings } from '../core.mjs';

test('character names are friendly while stored filenames stay stable',() => {
  for (const [file,label] of Object.entries({
    'Ch03_nonPBR.fbx':'Powerpuff','Ch15_nonPBR.fbx':'Soldier',
    'Ch25_nonPBR.fbx':'Sauron','Ch34_nonPBR.fbx':'Elf','My Avatar.fbx':'My Avatar',
  })) assert.equal(modelLabel(file),label);
  assert.equal(isCharacterFile('My Avatar.fbx'),true);
});

test('standalone T-pose files are characters rather than motions',() => {
  for (const name of ['Ch03_nonPBR.fbx','Ch15_nonPBR.fbx','General T-Pose.fbx','avatar.glb']) assert.equal(isCharacterFile(name),true);
  for (const name of ['Salute.fbx','Breathing Idle.fbx','Hard Head Nod.fbx']) assert.equal(isCharacterFile(name),false);
  assert.equal(sanitizeSettings({model:'Ch25_nonPBR.fbx'}).model,'Ch25_nonPBR.fbx');
  assert.equal(sanitizeSettings({model:'../../model.fbx'}).model,'Breathing Idle.fbx');
});

test('multi-mesh duplicates resolve to the animated parent bone',() => {
  const root=new THREE.Group(), parent=new THREE.Bone(), duplicate=new THREE.Bone();
  parent.name=duplicate.name='mixamorigHead'; parent.add(duplicate); root.add(parent);
  assert.equal(canonicalBones(root).get('head'),parent);
});

test('bind pose respects rotated/scaled FBX armatures and later viewer placement',() => {
  const root=new THREE.Group(), armature=new THREE.Group(), hips=new THREE.Bone(), head=new THREE.Bone();
  root.add(armature); armature.rotation.x=-Math.PI/2; armature.scale.setScalar(100);
  hips.name='Hips'; hips.position.z=1; armature.add(hips);
  head.name='Head'; head.position.z=0.7; hips.add(head); root.updateMatrixWorld(true);
  const skin=new THREE.SkinnedMesh(new THREE.BufferGeometry(),new THREE.MeshBasicMaterial());
  root.add(skin); skin.bind(new THREE.Skeleton([hips,head]));
  restoreBindPose(root);
  assert.ok(hips.position.distanceTo(new THREE.Vector3(0,0,1))<0.0001);
  const placement=new THREE.Group(); placement.scale.setScalar(0.01); placement.add(root);
  root.position.x=5; hips.position.set(15,40,90); head.rotation.x=0.8;
  restoreBindPose(root);
  assert.ok(hips.position.distanceTo(new THREE.Vector3(0,0,1))<0.0001);
  assert.ok(head.getWorldPosition(new THREE.Vector3()).distanceTo(new THREE.Vector3(0.05,1.7,0))<0.0001);
});

test('retargeting converts different bone axes and preserves the target rest pose',() => {
  const source=new THREE.Group(), target=new THREE.Group();
  source.rotation.y=0.4; target.rotation.z=-0.3;
  const a=new THREE.Bone(), b=new THREE.Bone();
  a.name='mixamorigHead'; b.name='mixamorig:Head';
  a.rotation.x=0.2; b.rotation.z=0.7;
  source.add(a); target.add(b);
  const sourceRest=captureRestPose(source), targetRest=captureRestPose(target);
  const raw=new THREE.AnimationClip('Head',1,[new THREE.QuaternionKeyframeTrack(`${a.name}.quaternion`,[0,1],[...a.quaternion.toArray(),...a.quaternion.toArray()])]);
  const clip=retargetMotion(raw,'Head',sourceRest,targetRest);
  const converted=new THREE.Quaternion().fromArray(clip.tracks[0].values);
  assert.ok(converted.angleTo(b.quaternion)<0.001);
  assert.equal(clip.tracks[0].name,'mixamorig:Head.quaternion');
});

test('motion keeps the selected character’s root height and bone lengths',() => {
  const source=new THREE.Group(), target=new THREE.Group();
  const a=new THREE.Bone(), b=new THREE.Bone(); a.name=b.name='mixamorigHips';
  a.position.y=100; b.position.y=125; source.add(a); target.add(b);
  const raw=new THREE.AnimationClip('Seated',1,[
    new THREE.VectorKeyframeTrack('mixamorigHips.position',[0,1],[0,60,0,0,55,3]),
    new THREE.QuaternionKeyframeTrack('mixamorigHips.quaternion',[0,1],[0,0,0,1,0,0,0,1]),
  ]);
  const clip=retargetMotion(raw,'Seated',captureRestPose(source),captureRestPose(target));
  assert.deepEqual([...clip.tracks[0].values],[0,125,0,0,125,0]);
  assert.deepEqual([...raw.tracks[0].values],[0,60,0,0,55,3]);
});

test('a posed avatar bind frame does not add its bent arm to every motion',() => {
  function rig(angle) {
    const root=new THREE.Group(), arm=new THREE.Bone(), forearm=new THREE.Bone();
    arm.name='LeftArm'; forearm.name='LeftForeArm'; arm.rotation.z=angle;
    forearm.position.y=0.3; root.add(arm); arm.add(forearm); root.updateMatrixWorld(true);
    return {root,arm,forearm};
  }
  const source=rig(-Math.PI/2), target=rig(-Math.PI*0.8);
  const raw=new THREE.AnimationClip('T arm',1,[new THREE.QuaternionKeyframeTrack('LeftArm.quaternion',[0,1],[...source.arm.quaternion.toArray(),...source.arm.quaternion.toArray()])]);
  const clip=retargetMotion(raw,'T arm',captureRestPose(source.root),captureRestPose(target.root));
  target.arm.quaternion.fromArray(clip.tracks[0].values); target.root.updateMatrixWorld(true);
  assert.ok(target.forearm.getWorldPosition(new THREE.Vector3()).distanceTo(new THREE.Vector3(0.3,0,0))<0.0001);
});
