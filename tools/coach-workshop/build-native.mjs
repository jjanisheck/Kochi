// Compile the workshop's mannequin, authored clips, and shared response policy
// into a self-contained app resource. No server, network, or FBX parsing on iOS.
import { readFile, readdir, mkdir, writeFile, copyFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import * as THREE from 'three';
import { FBXLoader } from 'three/addons/loaders/FBXLoader.js';
import { GLTFExporter } from 'three/addons/exporters/GLTFExporter.js';
import { mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';
import { build } from 'esbuild';
import { captureRestPose, retargetMotion } from './rig.mjs';
import { animationLabel, isCharacterFile, normalizeFBXBuffer } from './core.mjs';

const root=dirname(fileURLToPath(import.meta.url));
const output=resolve(root,'../../app/KochiApp/Resources/CoachMannequin');
await mkdir(output,{recursive:true});
// GLTFExporter only needs these two browser FileReader operations for this
// texture-free mannequin. Keep authoring and conversion reproducible in Node.
globalThis.FileReader=class {
  readAsArrayBuffer(blob) { blob.arrayBuffer().then(result=>{this.result=result;this.onloadend?.();}); }
  readAsDataURL(blob) { blob.arrayBuffer().then(result=>{this.result=`data:${blob.type};base64,${Buffer.from(result).toString('base64')}`;this.onloadend?.();}); }
};
const loader=new FBXLoader();
async function parse(name) {
  const data=await readFile(resolve(root,'imports',name));
  return loader.parse(normalizeFBXBuffer(data.buffer.slice(data.byteOffset,data.byteOffset+data.byteLength)),'');
}
const mannequin=await parse('Breathing Idle.fbx');
const rest=captureRestPose(mannequin);
const sourceNames=(await readdir(resolve(root,'imports'))).filter(name=>/\.fbx$/i.test(name) && !isCharacterFile(name)).sort();
const animations=[],sources=[];
for (const name of sourceNames) {
  const source=name==='Breathing Idle.fbx'?mannequin:await parse(name);
  const sourceRest=name==='Breathing Idle.fbx'?rest:captureRestPose(source);
  const motions=source.animations.filter(clip=>clip.duration>0 && clip.tracks.length);
  for (const [index,raw] of motions.entries()) {
    const label=motions.length===1?animationLabel(name):`${animationLabel(name)} · ${raw.name || index+1}`;
    animations.push(retargetMotion(raw,label,sourceRest,rest).optimize());
  }
  sources.push({file:name,sha256:createHash('sha256').update(await readFile(resolve(root,'imports',name))).digest('hex')});
}
if (!animations.some(clip=>clip.name==='Breathing Idle')) throw new Error('Missing breathing idle.');
const materials={};
mannequin.traverse(node=>{
  if (!node.isMesh) return;
  node.frustumCulled=false;
  node.geometry=mergeVertices(node.geometry,1e-6);
  const convert=material=>{
    if (material.map) throw new Error('Native mannequin unexpectedly requires an external texture.');
    materials[material.name]=material.toJSON();
    return new THREE.MeshStandardMaterial({name:material.name,color:material.color,roughness:0.7});
  };
  node.material=Array.isArray(node.material)?node.material.map(convert):convert(node.material);
});
const binary=await new GLTFExporter().parseAsync(mannequin,{binary:true,animations,onlyVisible:true});
// A classic script avoids file-origin ES-module/fetch restrictions in WKWebView.
// Binary glTF preserves the skinned rig and compact float animation tracks.
await writeFile(resolve(output,'mannequin-data.js'),`window.kochiMannequinData=${JSON.stringify({binary:Buffer.from(binary).toString('base64'),materials})};\n`);
await build({entryPoints:[resolve(root,'native-player.mjs')],bundle:true,minify:true,format:'iife',target:['safari16'],outfile:resolve(output,'player.js'),legalComments:'eof'});
await copyFile(resolve(root,'native-player.html'),resolve(output,'index.html'));
await copyFile(resolve(root,'../../app/KochiApp/Resources/Themes/default/avatar/arm-background.png'),resolve(output,'background.png'));
await copyFile(resolve(root,'node_modules/three/LICENSE'),resolve(output,'THREE-LICENSE.txt'));
await writeFile(resolve(output,'manifest.json'),JSON.stringify({version:1,model:'Original mannequin',three:THREE.REVISION,binaryBytes:binary.byteLength,animations:animations.map(clip=>({name:clip.name,duration:clip.duration})),sources},null,2)+'\n');
console.log(`Bundled mannequin + ${animations.length} clips (${(binary.byteLength/1048576).toFixed(2)} MB binary) → ${output}`);
