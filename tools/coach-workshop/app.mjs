import * as THREE from 'three';
import { FBXLoader } from 'three/addons/loaders/FBXLoader.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { DEFAULTS, animationLabel, boneKey, chooseBase, isCharacterFile, modelLabel, normalizeFBXBuffer, sanitizeSettings, validateCue, clockLabel } from './core.mjs';
import { canonicalBones, captureRestPose, restoreBindPose, retargetMotion } from './rig.mjs';
import { ReactionDirector, RESPONSE_EXAMPLES, findClip } from './reaction-policy.mjs';

const director=new ReactionDirector();
let lastResponse=null;
const $ = id => document.getElementById(id);
const stage = $('stage');
let settings;
try { settings = sanitizeSettings(JSON.parse(localStorage.getItem('kochi.character-lab.v1') || '{}')); }
catch { settings = {...DEFAULTS}; }
// This workshop always opens at the requested bust crop.
settings.frame = 'bust';
const state = {
  model:null, wrapper:new THREE.Group(), mixer:null, clips:new Map(), current:null,
  actions:new Map(), bones:new Map(), seen:new Map(), playing:true, importing:false,
  idle:null, once:false, pose:false, baseline:new Map(), sources:new Map(), models:new Map(), targetRest:new Map(), modelFile:null, switching:false, gaze:[0,0], pointer:[0,0],
};
const scene = new THREE.Scene();
scene.add(state.wrapper);
scene.add(new THREE.HemisphereLight(0xffffff,0x777777,2.2));
const key = new THREE.DirectionalLight(0xffffff,2.4); key.position.set(-3,5,5); scene.add(key);
const rim = new THREE.DirectionalLight(0xffffff,1.3); rim.position.set(3,3,-2); scene.add(rim);
const camera = new THREE.OrthographicCamera(-1,1,1,-1,0.01,100);
camera.position.set(0,1.76,6); camera.lookAt(0,1.76,0);
let renderer;
try {
  renderer = new THREE.WebGLRenderer({alpha:true,antialias:false,preserveDrawingBuffer:true});
} catch (error) {
  $('loading-detail').textContent = 'WebGL is unavailable. Open this page in a browser with hardware acceleration enabled.';
  throw error;
}
renderer.setPixelRatio(1);
renderer.setClearColor(0x000000,0);
renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
stage.prepend(renderer.domElement);
renderer.domElement.setAttribute('aria-label','Live Mixamo character');
const target = new THREE.WebGLRenderTarget(360,225,{minFilter:THREE.NearestFilter,magFilter:THREE.NearestFilter});
const screenScene = new THREE.Scene();
const screenCamera = new THREE.OrthographicCamera(-1,1,1,-1,0,1);
const finish = new THREE.ShaderMaterial({
  depthTest:false,depthWrite:false,
  uniforms:{image:{value:target.texture},pixel:{value:true},tones:{value:10}},
  vertexShader:'varying vec2 uvImage; void main(){ uvImage=uv; gl_Position=vec4(position.xy,0.0,1.0); }',
  fragmentShader:`
    uniform sampler2D image; uniform bool pixel; uniform float tones; varying vec2 uvImage;
    void main(){
      vec4 source=texture2D(image,uvImage);
      vec3 color=mix(source.rgb*12.92,1.055*pow(max(source.rgb,vec3(0.0)),vec3(1.0/2.4))-0.055,step(vec3(0.0031308),source.rgb));
      color=clamp(color,0.0,1.0);
      if(pixel){float gray=dot(color,vec3(0.2126,0.7152,0.0722));color=vec3(floor(gray*(tones-1.0)+0.5)/(tones-1.0));}
      gl_FragColor=vec4(color,source.a);
    }`,
});
screenScene.add(new THREE.Mesh(new THREE.PlaneGeometry(2,2),finish));
let helper;
let lastTime;
let frameCount = 0;
const fbxLoader = new FBXLoader();
const gltfLoader = new GLTFLoader();

function notice(text,error=false) { $('notice').textContent=text; $('notice').classList.toggle('error',error); }
function persist() { localStorage.setItem('kochi.character-lab.v1',JSON.stringify(settings)); }

function setCamera() {
  const ratio = Math.max(1,stage.clientWidth) / Math.max(1,stage.clientHeight);
  const height = settings.frame === 'bust' ? 0.64 : 2.42;
  const center = settings.frame === 'bust' ? 1.76 : 1.05;
  camera.left=-height*ratio/2; camera.right=height*ratio/2;
  camera.top=height/2; camera.bottom=-height/2;
  camera.position.set(0,center,6); camera.lookAt(0,center,0); camera.zoom=1;
  camera.updateProjectionMatrix();
  $('frame-caption').textContent=settings.frame === 'bust' ? 'MID-CHEST ↑' : 'FULL BODY';
}

function resize() {
  const width=Math.max(1,stage.clientWidth), height=Math.max(1,stage.clientHeight);
  renderer.setSize(width,height,false);
  const internalWidth=settings.style === 'pixel' ? Math.round(settings.resolution) : Math.round(width);
  target.setSize(internalWidth,Math.round(internalWidth*height/width));
  finish.uniforms.pixel.value=settings.style === 'pixel';
  finish.uniforms.tones.value=settings.tones;
  setCamera();
}
new ResizeObserver(resize).observe(stage);

function restoreLayers() {
  for (const [bone,pose] of state.baseline) {
    bone.quaternion.copy(pose.quaternion); bone.scale.copy(pose.scale);
  }
  state.baseline.clear();
}

function applyLayers() {
  const bones=[state.bones.get('head'),state.bones.get('lefthand'),state.bones.get('righthand')].filter(Boolean);
  for (const bone of bones) state.baseline.set(bone,{quaternion:bone.quaternion.clone(),scale:bone.scale.clone()});
  const head=state.bones.get('head');
  if (head) {
    const gaze=settings.follow ? state.pointer : state.gaze;
    head.rotateY(THREE.MathUtils.degToRad(settings.headYaw+gaze[0]*20));
    head.rotateX(THREE.MathUtils.degToRad(settings.headPitch+gaze[1]*12));
  }
  for (const role of ['lefthand','righthand']) state.bones.get(role)?.scale.multiplyScalar(settings.handScale);
  state.wrapper.rotation.y=THREE.MathUtils.degToRad(settings.turn);
  if (helper) helper.visible=settings.skeleton;
}

function render(time) {
  requestAnimationFrame(render);
  const dt=Math.min(0.05,Math.max(0,(time-(lastTime ?? time))/1000)); lastTime=time;
  restoreLayers();
  if (state.mixer) state.mixer.update(state.playing && !state.pose ? dt*settings.speed : 0);
  applyLayers();
  scene.updateMatrixWorld(true);
  renderer.setRenderTarget(target); renderer.clear(); renderer.render(scene,camera);
  renderer.setRenderTarget(null); renderer.clear(); renderer.render(screenScene,screenCamera);
  frameCount++;
  if (state.current && !state.pose) {
    const action=state.actions.get(state.current), duration=state.clips.get(state.current).duration;
    $('timeline').value=action.time;
    $('current-time').textContent=clockLabel(action.time);
    $('duration').textContent=clockLabel(duration);
  }
}
requestAnimationFrame(render);

function disposeImported(root) {
  const textures=new Set(), materials=new Set(), geometries=new Set(), urls=new Set();
  root.traverse(node => {
    if (node.geometry) geometries.add(node.geometry);
    for (const material of Array.isArray(node.material) ? node.material : node.material ? [node.material] : []) {
      materials.add(material);
      for (const value of Object.values(material)) if (value?.isTexture) {
        textures.add(value);
        const url=value.image?.currentSrc || value.image?.src;
        if (url?.startsWith('blob:')) urls.add(url);
      }
    }
  });
  for (const item of [...geometries,...materials,...textures]) item.dispose();
  for (const url of urls) URL.revokeObjectURL(url);
}

function rebuildModelPicker() {
  const select=$('model-select');
  select.replaceChildren();
  for (const file of [...state.models.values()].sort((a,b) => (a.name==='Breathing Idle.fbx'?-1:b.name==='Breathing Idle.fbx'?1:a.name.localeCompare(b.name)))) {
    const option=document.createElement('option'); option.value=file.name;
    option.textContent=modelLabel(file.name);
    select.append(option);
  }
  if (state.modelFile) select.value=state.modelFile;
  select.disabled=state.switching || state.importing || !state.models.size;
  $('model-status').textContent=state.switching ? 'Loading character…' : `${state.models.size} characters · animations stay loaded when you switch`;
}

function registerModel(file) {
  state.models.set(file.name,file);
  rebuildModelPicker();
}

function mountModel(root,filename,rest) {
  let skin;
  root.traverse(node => { if (node.isSkinnedMesh && !skin) skin=node; });
  if (!skin) throw new Error(`${filename} contains animation only. Choose a rigged model downloaded “With Skin”.`);
  root.updateMatrixWorld(true);
  const box=new THREE.Box3().setFromObject(root);
  const height=box.max.y-box.min.y;
  if (!Number.isFinite(height) || height<=0) throw new Error('This model has no usable body bounds.');
  const center=box.getCenter(new THREE.Vector3());
  root.position.add(new THREE.Vector3(-center.x,-box.min.y,-center.z));
  state.model=root; state.modelFile=filename; state.targetRest=rest;
  state.wrapper.add(root); state.wrapper.scale.setScalar(2/height);
  state.bones=canonicalBones(root);
  root.traverse(node => {
    if (node.isMesh) node.frustumCulled=false;
    // Character FBXs may also include the authoring scene's lights/cameras.
    // Use the workshop lighting and fixed camera for every character.
    if (node.isLight || node.isCamera) node.visible=false;
  });
  state.mixer=new THREE.AnimationMixer(root);
  state.mixer.addEventListener('finished',event => {
    if (state.once && state.current && event.action===state.actions.get(state.current)) {
      state.once=false;
      if (state.idle && state.current!==state.idle) play(state.idle,{once:false,forceLoop:true,fromResponse:true});
    }
  });
  helper=new THREE.SkeletonHelper(root); helper.material.depthTest=false;
  helper.material.transparent=true; helper.material.opacity=0.7; scene.add(helper);
  $('rig-info').textContent=`${state.bones.size} bones · fixed root`;
  $('stage-label').textContent=modelLabel(filename).toUpperCase();
  setCamera(); rebuildModelPicker();
}

function releaseModel() {
  restoreLayers();
  state.mixer?.stopAllAction();
  if (state.model) {
    state.mixer?.uncacheRoot(state.model);
    state.wrapper.remove(state.model); disposeImported(state.model);
  }
  if (helper) { scene.remove(helper); helper.dispose(); helper=null; }
  state.model=null; state.mixer=null; state.current=null; state.pose=false;
  state.clips.clear(); state.actions.clear(); state.bones=new Map(); state.targetRest=new Map();
}

async function switchModel(name) {
  if (state.switching || state.importing) return;
  const file=state.models.get(name);
  if (!file) throw new Error('That character file is not available.');
  if (state.modelFile===name) return;
  state.switching=true; rebuildModelPicker(); connectCoachEvents();
  document.querySelector('.model-picker').setAttribute('aria-busy','true');
  $('loading').hidden=false;
  $('loading').querySelector('strong').textContent='Loading character';
  $('loading-detail').textContent=`${modelLabel(name)} · ${(file.size/1048576).toFixed(0)} MB`;
  let parsed;
  try {
    // Validate and retarget before releasing the current model, so a bad file
    // leaves the working character and motions intact.
    parsed=await parseFile(file);
    let hasSkin=false; parsed.root.traverse(node => { if (node.isSkinnedMesh) hasSkin=true; });
    if (!hasSkin) throw new Error('This file contains no skinned character. Download the T-pose model With Skin.');
    const rest=captureRestPose(parsed.root);
    const adapted=new Map();
    for (const [label,source] of state.sources) adapted.set(label,retargetMotion(source.raw,label,source.rest,rest));
    const previous={name:state.current,time:state.current ? state.actions.get(state.current).time : 0,playing:state.playing,pose:state.pose};
    releaseModel(); mountModel(parsed.root,name,rest);
    for (const [label,clip] of adapted) {
      state.clips.set(label,clip); state.actions.set(label,state.mixer.clipAction(clip));
    }
    const resume=state.clips.has(previous.name) ? previous.name : state.idle || state.clips.keys().next().value;
    if (resume) {
      play(resume,{immediate:true});
      seek(previous.time);
      if (previous.playing && !previous.pose) $('play').click();
      if (previous.pose) showRestPose();
    } else showRestPose();
    settings.model=name; persist(); rebuildLibrary();
    notice(`${modelLabel(name)} selected. ${state.clips.size} animations ready; camera stays fixed.`);
  } catch (error) {
    if (parsed && parsed.root!==state.model) disposeImported(parsed.root);
    notice(error.message,true);
  } finally {
    state.switching=false; $('loading').hidden=true;
    document.querySelector('.model-picker').setAttribute('aria-busy','false'); rebuildModelPicker(); connectCoachEvents();
  }
}

async function parseFile(file) {
  const bytes=file.bytes || await (await fetch(file.url)).arrayBuffer();
  if (/\.fbx$/i.test(file.name)) {
    const root=fbxLoader.parse(normalizeFBXBuffer(bytes),'/imports/');
    const images=new Set(); root.traverse(node=>{for(const material of Array.isArray(node.material)?node.material:node.material?[node.material]:[]){for(const value of Object.values(material))if(value?.isTexture && value.image?.decode)images.add(value.image);}});
    await Promise.all([...images].map(image=>image.decode().catch(()=>{})));
    return {root,animations:root.animations};
  }
  const gltf=await gltfLoader.parseAsync(bytes,'/imports/');
  return {root:gltf.scene,animations:gltf.animations};
}

async function loadFile(file) {
  const parsed=await parseFile(file);
  const rest=captureRestPose(parsed.root);
  const animations=parsed.animations.filter(clip => clip.duration>0 && clip.tracks.length>0);
  if (!animations.length) {
    let hasSkin=false; parsed.root.traverse(node => { if (node.isSkinnedMesh) hasSkin=true; });
    disposeImported(parsed.root);
    if (hasSkin) { registerModel(file); return; }
    throw new Error(`${file.name} contains neither a character nor a playable animation.`);
  }
  const isBase=!state.model;
  if (isBase) { registerModel(file); mountModel(parsed.root,file.name,rest); }
  const label=animationLabel(file.name);
  try {
    for (const [index,raw] of animations.entries()) {
      const name=animations.length===1 ? label : `${label} · ${raw.name || index+1}`;
      const clip=retargetMotion(raw,name,rest,state.targetRest);
      state.sources.set(name,{raw:raw.clone(),rest});
      if (state.clips.has(name)) { state.actions.get(name)?.stop(); state.mixer.uncacheClip(state.clips.get(name)); }
      state.clips.set(name,clip); state.actions.set(name,state.mixer.clipAction(clip));
      if (/breathing.*idle/i.test(name) || !state.idle && /idle/i.test(name)) state.idle=name;
    }
  } finally { if (!isBase) disposeImported(parsed.root); }
  rebuildLibrary();
  if (isBase) { play(state.idle || state.clips.keys().next().value,{fromResponse:true}); $('loading').hidden=true; }
}

function play(name,{once=false,immediate=false,forceLoop=false,fromResponse=false}={}) {
  name=findClip(state.clips.keys(),[name]);
  if (!name) throw new Error('That animation is not loaded.');
  if (!fromResponse) director.manual(performance.now()/1000,state.clips.get(name).duration);
  restoreLayers();
  const previous=state.current ? state.actions.get(state.current) : null;
  const next=state.actions.get(name);
  if (state.pose) { state.mixer.stopAllAction(); state.pose=false; }
  const canFade=previous && previous!==next && !immediate && settings.blend>0;
  // Interrupted blends must not leave old clips contributing forever.
  for (const action of state.actions.values()) if (action!==previous && action!==next) action.stop();
  next.reset().setEffectiveTimeScale(1).setEffectiveWeight(1);
  const loop=forceLoop || settings.loop;
  next.clampWhenFinished=once || !loop;
  next.setLoop(once || !loop ? THREE.LoopOnce : THREE.LoopRepeat,Infinity);
  next.play();
  if (canFade) { previous.fadeOut(settings.blend); next.fadeIn(settings.blend); }
  else { if (previous && previous!==next) previous.stop(); }
  state.current=name; state.playing=true; state.once=once;
  $('motion-title').textContent=name; $('timeline').max=state.clips.get(name).duration;
  $('play').textContent='Ⅱ'; $('play').setAttribute('aria-label','Pause animation');
  $('rest-pose').textContent='Show rest pose';
  updateSelection();
}

function seek(time) {
  if (!state.current) return;
  restoreLayers(); state.mixer.stopAllAction(); state.pose=false;
  const action=state.actions.get(state.current);
  action.reset().setEffectiveWeight(1).play();
  action.setLoop(THREE.LoopOnce,1); action.clampWhenFinished=true;
  action.time=Math.max(0,Math.min(time,state.clips.get(state.current).duration));
  state.mixer.update(0); state.playing=false; state.once=false;
  $('play').textContent='▶'; $('play').setAttribute('aria-label','Play animation');
}

function rebuildLibrary() {
  const clips=[...state.clips].sort(([a],[b]) => {
    if (/breathing.*idle/i.test(a)) return -1; if (/breathing.*idle/i.test(b)) return 1;
    return a.localeCompare(b);
  });
  $('clips').replaceChildren();
  for (const [index,[name,clip]] of clips.entries()) {
    const button=document.createElement('button'); button.className='clip-button'; button.dataset.clip=name;
    const number=document.createElement('span'); number.className='clip-number'; number.textContent=String(index+1).padStart(2,'0');
    const content=document.createElement('span'), title=document.createElement('span'), meta=document.createElement('span');
    title.className='clip-name'; title.textContent=name;
    meta.className='clip-meta'; meta.textContent=`${clockLabel(clip.duration)} · ${clip.tracks.length} tracks`;
    content.append(title,meta); button.append(number,content);
    button.addEventListener('click',() => { play(name); notice(`${name} · original Mixamo motion. Camera stays fixed.`); });
    $('clips').append(button);
  }
  $('clip-count').textContent=String(clips.length);
  $('cue-buttons').replaceChildren();
  for (const example of RESPONSE_EXAMPLES) {
    const button=document.createElement('button'); button.textContent=example.label;
    button.addEventListener('click',()=>{
      $('cue-json').value=JSON.stringify(Object.fromEntries(Object.entries(example).filter(([key])=>key!=='label')),null,2);
      routeResponse(example,{preview:true});
    });
    $('cue-buttons').append(button);
  }
  updateSelection();
}

function updateSelection() {
  document.querySelectorAll('[data-clip]').forEach(button => button.setAttribute('aria-pressed',String(button.dataset.clip===state.current)));
}

function routeResponse(input,{preview=false}={}) {
  const cue=validateCue(input), now=performance.now()/1000;
  if (!state.mixer) throw new Error('Wait for the character to finish loading.');
  let result=director.decide(cue,state.clips.keys(),now,{preview});
  if (!preview && (!state.playing || state.pose) && !cue.animation && cue.intent!=='idle') result={...result,play:false,reason:'The animation is paused for manual inspection.'};
  if (result.ignored) return {ok:true,played:false,reason:result.reason};
  lastResponse={...cue,animation:result.animation,rule:result.id,played:result.play,reason:result.reason};
  if (cue.gaze) state.gaze=cue.gaze;
  $('response-caption').textContent=cue.caption || cue.animation || 'Listening and breathing.';
  $('reaction-reason').textContent=`${preview?'Rehearsal':'Live response'} · ${result.animation || 'Idle'} · ${result.reason}`;
  if (result.play) {
    const sameIdle=!result.once && state.current===result.animation && state.playing;
    if (!sameIdle) play(result.animation,{once:result.once,forceLoop:!result.once,fromResponse:true});
    if (preview) director.manual(now,state.clips.get(result.animation).duration);
    else director.commit(result,now,state.clips.get(result.animation).duration/Math.max(0.1,settings.speed));
  }
  return {ok:true,played:result.play,animation:result.animation,reason:result.reason};
}

function react(input) {
  const cue=validateCue(input);
  if (!cue.animation) return routeResponse(cue);
  if (cue.gaze) state.gaze=cue.gaze;
  const name=findClip(state.clips.keys(),[cue.animation]);
  if (!name) throw new Error(`Animation “${cue.animation}” is not loaded.`);
  play(name,{once:cue.once});
  notice(`Reaction: ${name}${cue.once ? ' → breathing idle' : ''}.`);
  return {ok:true,animation:name};
}

async function importFiles(files) {
  if (state.importing || state.switching) return;
  state.importing=true;
  try {
    const failures=[];
    for (const file of files.filter(file => isCharacterFile(file.name))) {
      registerModel(file); state.seen.set(file.name,file.modified ?? file.size);
    }
    const ordered=files.filter(file => !isCharacterFile(file.name));
    if (!state.model && ordered.length) { const base=chooseBase(ordered); ordered.splice(ordered.indexOf(base),1); ordered.unshift(base); }
    for (const [index,file] of ordered.entries()) {
      const version=file.modified ?? file.size;
      if (state.seen.get(file.name)===version) continue;
      $('loading-detail').textContent=`${file.name} · ${index+1} of ${ordered.length}`;
      $('import-status').textContent=`Loading ${file.name}…`;
      try {
        await loadFile(file); state.seen.set(file.name,version);
      } catch (error) {
        state.seen.set(file.name,version); failures.push(error.message); notice(error.message,true);
        if (!state.model) { $('loading-detail').textContent=error.message; throw error; }
      }
      await new Promise(resolve => setTimeout(resolve,0));
    }
    $('import-status').textContent=`${state.clips.size} animations · your files stay on this machine`;
    if (failures.length) notice(failures.join(' '),true);
    else if (state.model) notice(`${state.clips.size} Mixamo animations loaded. Same rig, same background, fixed bust camera.`);
  } finally { state.importing=false; rebuildModelPicker(); connectCoachEvents(); }
  if (state.modelFile!==settings.model && state.models.has(settings.model)) await switchModel(settings.model);
}

async function refreshImports() {
  if (state.importing || state.switching) return;
  try {
    const response=await fetch('/api/imports');
    if (!response.ok) throw new Error('Could not read the imports folder.');
    const {files}=await response.json();
    const fresh=files.filter(file => state.seen.get(file.name)!==file.modified);
    if (fresh.length) await importFiles(fresh);
    else if (!files.length && !state.model) $('loading-detail').textContent='Drop an FBX with skin here, or save your Mixamo files in tools/coach-workshop/imports.';
  } catch (error) { notice(error.message,true); }
}

function updateControls() {
  for (const key of ['resolution','tones','handScale','headYaw','headPitch','turn','blend']) {
    $(key).value=settings[key];
    $(key+'-value').textContent=key==='resolution' ? `${settings[key]} px` : key==='tones' ? `${settings[key]} tones` : key==='handScale' ? `${settings[key].toFixed(2)}×` : key==='blend' ? `${settings[key].toFixed(2)}s` : `${settings[key]}°`;
  }
  for (const key of ['loop','skeleton','follow','liveCoach']) $(key).checked=settings[key];
  $('speed').value=settings.speed;
  document.querySelectorAll('[data-style]').forEach(button => button.setAttribute('aria-pressed',String(button.dataset.style===settings.style)));
  document.querySelectorAll('[data-frame]').forEach(button => button.setAttribute('aria-pressed',String(button.dataset.frame===settings.frame)));
}

for (const key of ['resolution','tones','handScale','headYaw','headPitch','turn','blend']) $(key).addEventListener('input',event => {
  settings[key]=Number(event.target.value); updateControls(); persist();
  if (key==='resolution' || key==='tones') resize();
});
for (const key of ['loop','skeleton','follow','liveCoach']) $(key).addEventListener('change',event => {
  settings[key]=event.target.checked; persist();
  if (key==='liveCoach') connectCoachEvents();
  if (key==='loop' && state.current && !state.pose) {
    const action=state.actions.get(state.current); action.setLoop(settings.loop ? THREE.LoopRepeat : THREE.LoopOnce,Infinity); action.clampWhenFinished=!settings.loop;
  }
});
$('speed').addEventListener('change',event => { settings.speed=Number(event.target.value); persist(); });
document.querySelectorAll('[data-style]').forEach(button => button.addEventListener('click',() => { settings.style=button.dataset.style; updateControls(); persist(); resize(); }));
document.querySelectorAll('[data-frame]').forEach(button => button.addEventListener('click',() => { settings.frame=button.dataset.frame; updateControls(); persist(); setCamera(); }));
$('play').addEventListener('click',() => {
  if (!state.current) return;
  if (state.pose) return play(state.current);
  state.playing=!state.playing;
  const action=state.actions.get(state.current);
  if (state.playing) {
    action.paused=false;
    action.setLoop(settings.loop ? THREE.LoopRepeat : THREE.LoopOnce,Infinity);
    if (action.time>=state.clips.get(state.current).duration) action.reset().play();
  }
  $('play').textContent=state.playing ? 'Ⅱ' : '▶'; $('play').setAttribute('aria-label',state.playing ? 'Pause animation' : 'Play animation');
});
$('restart').addEventListener('click',() => { if (state.current) play(state.current,{immediate:true}); });
$('timeline').addEventListener('input',event => seek(Number(event.target.value)));
function showRestPose() {
  if (!state.model) return;
  restoreLayers(); state.mixer.stopAllAction(); restoreBindPose(state.model);
  state.pose=true; state.playing=false;
  $('motion-title').textContent='T-pose / rest pose'; $('rest-pose').textContent='Return to animation'; $('play').textContent='▶';
  $('play').setAttribute('aria-label','Play animation');
  notice('The selected character’s original bind pose. No animation is deforming the skeleton.');
}
$('rest-pose').addEventListener('click',() => {
  if (!state.model) return;
  if (state.pose && state.current) return play(state.current,{immediate:true});
  showRestPose();
});
$('model-select').addEventListener('change',event => { switchModel(event.target.value).catch(error => notice(error.message,true)); });
stage.addEventListener('pointermove',event => {
  const bounds=stage.getBoundingClientRect();
  state.pointer=[(event.clientX-bounds.left)/bounds.width*2-1,(event.clientY-bounds.top)/bounds.height*2-1];
});
stage.addEventListener('pointerleave',() => { state.pointer=[0,0]; });

function download(blob,name) {
  const url=URL.createObjectURL(blob), link=document.createElement('a'); link.href=url; link.download=name; link.click(); setTimeout(() => URL.revokeObjectURL(url),1000);
}
$('save-preset').addEventListener('click',() => download(new Blob([JSON.stringify({version:1,settings,animation:state.current},null,2)],{type:'application/json'}),'kochi-character-setup.json'));
$('preset').addEventListener('change',async event => {
  try { const value=JSON.parse(await event.target.files[0].text()); settings=sanitizeSettings(value.settings || value); if (state.models.has(settings.model)) await switchModel(settings.model); updateControls(); persist(); resize(); connectCoachEvents(); if (state.clips.has(value.animation)) play(value.animation); notice('Saved setup loaded.'); }
  catch (error) { notice(`Could not load this setup: ${error.message}`,true); }
});
$('reset').addEventListener('click',() => { settings={...DEFAULTS,model:state.modelFile || DEFAULTS.model}; state.gaze=[0,0]; updateControls(); persist(); resize(); connectCoachEvents(); notice('Default proportions and fixed bust framing restored.'); });
$('capture').addEventListener('click',async () => {
  const image=new Image(); image.src='/reference/background.png'; await image.decode();
  const canvas=document.createElement('canvas'); canvas.width=renderer.domElement.width; canvas.height=renderer.domElement.height;
  const context=canvas.getContext('2d');
  const width=canvas.width*1.1, height=width*image.height/image.width;
  context.drawImage(image,(canvas.width-width)/2,(canvas.height-height)/2,width,height);
  context.drawImage(renderer.domElement,0,0);
  canvas.toBlob(blob => download(blob,`kochi-${(state.current || 'preview').toLowerCase().replaceAll(' ','-')}.png`));
});
$('reference-toggle').addEventListener('click',() => {
  const video=$('reference-video'), image=document.querySelector('.reference-media img');
  video.hidden=!video.hidden; image.hidden=!video.hidden;
  $('reference-toggle').textContent=video.hidden ? 'Compare with original video' : 'Return to original artwork';
  if (video.hidden) video.pause(); else video.play().catch(() => {});
});
$('send-cue').addEventListener('click',() => { try { const value=JSON.parse($('cue-json').value); if(value.animation)react(value); else routeResponse(value,{preview:true}); } catch (error) { notice(error.message,true); } });

async function readDropped(files) {
  const readable=[];
  for (const file of files) if (/\.(fbx|glb)$/i.test(file.name)) readable.push({name:file.name,size:file.size,modified:file.lastModified,bytes:await file.arrayBuffer()});
  if (!readable.length) return notice('Choose an FBX or GLB file.',true);
  await importFiles(readable);
}
$('files').addEventListener('change',event => readDropped(event.target.files).catch(error => notice(error.message,true)));
document.addEventListener('dragover',event => { event.preventDefault(); stage.classList.add('dragging'); });
document.addEventListener('dragleave',event => { if (!event.relatedTarget) stage.classList.remove('dragging'); });
document.addEventListener('drop',event => { event.preventDefault(); stage.classList.remove('dragging'); readDropped(event.dataTransfer.files).catch(error => notice(error.message,true)); });

let events;
function connectCoachEvents() {
  events?.close();
  events=new EventSource(`/api/events?coach=${settings.liveCoach && state.mixer && !state.importing && !state.switching?'1':'0'}`);
  events.onmessage=event=>{
    try {
      const value=JSON.parse(event.data);
      if (value.source==='app' && !settings.liveCoach) return;
      react(value);
    } catch(error) { notice(error.message,true); }
  };
}
connectCoachEvents();
window.coach={
  debug:() => {
    const pixels=new Uint8Array(target.width*target.height*4); renderer.readRenderTargetPixels(target,0,0,target.width,target.height,pixels);
    let visible=0; for(let i=3;i<pixels.length;i+=4) if(pixels[i]>0) visible++;
    return {visible, bounds:new THREE.Box3().setFromObject(state.wrapper),wrapperScale:state.wrapper.scale.toArray(),rootPosition:state.model?.position.toArray(),
      head:state.bones.get('head')?.getWorldPosition(new THREE.Vector3()).toArray(),hips:state.bones.get('hips')?.position.toArray(),
      materials:state.model ? (()=>{const m=[];state.model.traverse(n=>{if(n.isSkinnedMesh)n.computeBoundingBox();if(n.isMesh)m.push({name:n.name,bounds:n.boundingBox,visible:n.visible,material:Array.isArray(n.material)?n.material.map(m=>({type:m.type,opacity:m.opacity,color:m.color})): {type:n.material.type,opacity:n.material.opacity,color:n.material.color}})});return m})():null};
  },
  react,
  rehearse:input=>routeResponse(input,{preview:true}),
  switchModel,
  play:(name,options) => play(name,options),
  seek,
  snapshot:() => ({
    response:lastResponse,
    models:[...state.models.keys()],model:state.modelFile,switching:state.switching,importing:state.importing,restPose:state.pose,
    animations:[...state.clips.keys()],current:state.current,time:state.current ? state.actions.get(state.current).time : 0,
    playing:state.playing,frame:settings.frame,bones:state.bones.size,renderedFrames:frameCount,
    camera:{position:camera.position.toArray(),quaternion:camera.quaternion.toArray(),projection:camera.projectionMatrix.toArray()},
    settings:{...settings},
    hands:['lefthand','righthand'].map(role => state.bones.get(role)?.scale.toArray()),
    joints:Object.fromEntries(['head','lefthand','righthand'].map(role => [role,state.bones.get(role)?.getWorldPosition(new THREE.Vector3()).toArray()])),
  }),
};
updateControls(); resize(); refreshImports(); setInterval(refreshImports,4000);
