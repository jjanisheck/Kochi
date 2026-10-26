import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { ReactionDirector } from './reaction-policy.mjs';

const notify=(type,detail={})=>window.webkit?.messageHandlers.coach?.postMessage({type,...detail});
window.addEventListener('error',event=>notify('error',{message:event.message}));
window.addEventListener('unhandledrejection',event=>notify('error',{message:String(event.reason)}));

async function initialize() {
  const asset=window.kochiMannequinData;
  const bytes=Uint8Array.from(atob(asset.binary),c=>c.charCodeAt(0));
  delete window.kochiMannequinData;
  const gltf=await new GLTFLoader().parseAsync(bytes.buffer,'');
  const model=gltf.scene;
  const wrapper=new THREE.Group();wrapper.add(model);
  model.updateMatrixWorld(true);
  const box=new THREE.Box3().setFromObject(model),center=box.getCenter(new THREE.Vector3());
  model.position.add(new THREE.Vector3(-center.x,-box.min.y,-center.z));
  wrapper.scale.setScalar(2/(box.max.y-box.min.y));
  let tint='#ec5000'; // The default primary button's deeper orange.
  const orangeMaterials=[];
  function applyTint(color) {
    tint=color.toLowerCase();
    for(const material of orangeMaterials) {
      material.color.set(tint);
      if(material.userData.joint)material.color.multiplyScalar(.55);
    }
  }
  model.traverse(node=>{
    if (node.isMesh) {
      node.frustumCulled=false;
      const glossy=source=>{
        const material=new THREE.MeshPhysicalMaterial({name:source.name,color:tint,
          metalness:.25,roughness:.18,clearcoat:1,clearcoatRoughness:.06,envMapIntensity:.85});
        material.userData.joint=/joints/i.test(node.name);
        orangeMaterials.push(material);
        return material;
      };
      node.material=Array.isArray(node.material)?node.material.map(glossy):glossy(node.material);
    }
    if (node.isLight || node.isCamera) node.visible=false;
  });
  applyTint(tint);
  const scene=new THREE.Scene();scene.add(wrapper);
  scene.add(new THREE.HemisphereLight(0xffffff,0x777777,.45));
  const key=new THREE.DirectionalLight(0xffffff,2);key.position.set(-3,5,5);scene.add(key);
  const rim=new THREE.DirectionalLight(0xffffff,1.3);rim.position.set(3,3,-2);scene.add(rim);
  // Tight head-and-shoulders portrait, with a little headroom for gestures.
  // Keep this framing constant across idle and every reaction.
  const portraitHalfHeight=.26,portraitCenterY=1.79;
  const camera=new THREE.OrthographicCamera(-1,1,portraitHalfHeight,-portraitHalfHeight,0.01,100);
  camera.position.set(0,portraitCenterY,6);camera.lookAt(0,portraitCenterY,0);
  const renderer=new THREE.WebGLRenderer({alpha:true,antialias:false,powerPreference:'low-power'});
  renderer.setPixelRatio(1);renderer.setClearColor(0x000000,0);renderer.outputColorSpace=THREE.LinearSRGBColorSpace;
  // Bake studio reflections locally; the glossy coat needs broad reflected
  // panels as well as direct highlights. No image download or HDR asset.
  const studio=new RoomEnvironment(),prefilter=new THREE.PMREMGenerator(renderer);
  const reflections=prefilter.fromScene(studio,.04);
  scene.environment=reflections.texture;
  studio.dispose();prefilter.dispose();
  document.body.prepend(renderer.domElement);
  const target=new THREE.WebGLRenderTarget(360,225,{minFilter:THREE.NearestFilter,magFilter:THREE.NearestFilter});
  const screen=new THREE.Scene(),screenCamera=new THREE.OrthographicCamera(-1,1,1,-1,0,1);
  screen.add(new THREE.Mesh(new THREE.PlaneGeometry(2,2),new THREE.ShaderMaterial({
    depthTest:false,depthWrite:false,uniforms:{image:{value:target.texture}},
    vertexShader:'varying vec2 uvImage;void main(){uvImage=uv;gl_Position=vec4(position.xy,0.,1.);}',
    fragmentShader:`uniform sampler2D image;varying vec2 uvImage;void main(){
      vec4 source=texture2D(image,uvImage);
      vec3 color=mix(source.rgb*12.92,1.055*pow(max(source.rgb,vec3(0.0)),vec3(1.0/2.4))-0.055,step(vec3(0.0031308),source.rgb));
      gl_FragColor=vec4(clamp(color,0.,1.),source.a);}`,
  })));
  function resize() {
    const width=Math.max(1,innerWidth),height=Math.max(1,innerHeight),ratio=width/height;
    renderer.setSize(width,height,false);target.setSize(360,Math.max(1,Math.round(360/ratio)));
    camera.left=-portraitHalfHeight*ratio;camera.right=portraitHalfHeight*ratio;camera.updateProjectionMatrix();
  }
  new ResizeObserver(()=>{resize();redraw();}).observe(document.body);resize();
  const mixer=new THREE.AnimationMixer(model),director=new ReactionDirector();
  const clips=new Map(gltf.animations.map(clip=>[clip.name,clip])),actions=new Map(gltf.animations.map(clip=>[clip.name,mixer.clipAction(clip)]));
  const idle='Breathing Idle';
  let current=null,once=false,paused=false,reduceMotion=false,lastCue=null,frame=0,request=0,disposed=false,contextLost=false;
  let frames=0;
  function play(name,oneShot=false) {
    const next=actions.get(name);if(!next)return;
    const previous=actions.get(current);
    for(const action of actions.values())if(action!==previous && action!==next)action.stop();
    next.reset().setEffectiveTimeScale(1).setEffectiveWeight(1);
    next.setLoop(oneShot?THREE.LoopOnce:THREE.LoopRepeat,Infinity);next.clampWhenFinished=oneShot;next.play();
    if(previous && previous!==next && !reduceMotion){previous.fadeOut(.4);next.fadeIn(.4);}else if(previous && previous!==next)previous.stop();
    current=name;once=oneShot;
  }
  mixer.addEventListener('finished',event=>{if(once && event.action===actions.get(current))play(idle);});
  function render(time) {
    request=0;
    if(disposed || paused || document.hidden || contextLost)return;
    // Cap at 30fps. Reduced Motion keeps a still breathing pose and no gestures.
    if(!reduceMotion && time-frame<1000/30-1){request=requestAnimationFrame(render);return;}
    if(!reduceMotion)mixer.update(frame?Math.min(.05,Math.max(0,(time-frame)/1000)):0);
    frame=time;scene.updateMatrixWorld(true);
    renderer.setRenderTarget(target);renderer.clear();renderer.render(scene,camera);
    renderer.setRenderTarget(null);renderer.clear();renderer.render(screen,screenCamera);frames++;
    if(!reduceMotion)request=requestAnimationFrame(render);
  }
  function redraw(){frame=0;if(!request && !disposed)request=requestAnimationFrame(render);}
  const snapshot=()=>({ready:true,current,time:actions.get(current)?.time,animations:[...clips.keys()],frames,paused,reduceMotion,contextLost,appearance:{tint,finish:'glossy',clearcoat:1},camera:{position:camera.position.toArray(),left:camera.left,right:camera.right,top:camera.top,bottom:camera.bottom},response:lastCue});
  const receive=(cue,{preview=false}={})=>{
    const now=performance.now()/1000,result=director.decide(cue,clips.keys(),now,{preview});
    if(result.ignored)return result;
    lastCue={...cue,animation:result.animation,played:result.play,reason:result.reason};
    if(reduceMotion){if(current!==idle)play(idle);redraw();return result;}
    if(result.play && (result.once || current!==result.animation)){
      play(result.animation,result.once);director.commit(result,now,clips.get(result.animation).duration);redraw();
    }
    return result;
  };
  window.kochiCoach={
    receive,snapshot,
    inspect(){
      const pixels=new Uint8Array(target.width*target.height*4);renderer.readRenderTargetPixels(target,0,0,target.width,target.height,pixels);
      let visiblePixels=0;for(let i=3;i<pixels.length;i+=4)if(pixels[i]>0)visiblePixels++;
      return {visiblePixels,width:target.width,height:target.height,triangles:renderer.info.render.triangles};
    },
    configure(value){
      if(typeof value.tint==='string' && /^#[\da-f]{6}$/i.test(value.tint))applyTint(value.tint);
      paused=value.paused===true;const wasReduced=reduceMotion;reduceMotion=value.reduceMotion===true;
      if(reduceMotion && !wasReduced){play(idle);mixer.update(.6);}
      if(paused && request){cancelAnimationFrame(request);request=0;}
      if(!paused)redraw();
    },
    dispose(){disposed=true;cancelAnimationFrame(request);mixer.stopAllAction();reflections.dispose();target.dispose();renderer.dispose();},
  };
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)redraw();});
  renderer.domElement.addEventListener('webglcontextlost',event=>{event.preventDefault();contextLost=true;notify('contextLost');});
  renderer.domElement.addEventListener('webglcontextrestored',()=>{contextLost=false;redraw();notify('contextRestored');});
  play(idle);mixer.update(.6);redraw();
  // Ready means a frame has actually reached the canvas, not just parsed assets.
  requestAnimationFrame(()=>requestAnimationFrame(()=>notify('ready',snapshot())));
}
initialize().catch(error=>notify('error',{message:String(error)}));
