import { readFile, readdir, writeFile, rename } from 'node:fs/promises';
import { dirname, resolve, basename, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import { parseBinaryFBX, encodeBinaryFBX, stringProperty, binaryProperty, child, text } from './fbx-binary.mjs';

const root=dirname(fileURLToPath(import.meta.url));
const sourcePath=resolve(root,'imports/my-avatar/source/Silly Dancing.fbx');
const textureFolder=resolve(root,'imports/my-avatar/textures');
const outputPath=resolve(root,'imports/My Avatar.fbx');
const input=await readFile(sourcePath);
const document=parseBinaryFBX(input);
assert.ok(encodeBinaryFBX(document).equals(input),'FBX reader/writer must round-trip the original exactly.');
const objects=document.nodes.find(node=>node.name==='Objects');
const videos=objects.children.filter(node=>node.name==='Video');
const filenames=(await readdir(textureFolder)).filter(name=>/\.(png|jpe?g)$/i.test(name));
const key=name=>basename(name.replaceAll('\\','/')).replace(/\.(jpe?g|png)$/i,'').toLowerCase();
const files=new Map();
for (const name of filenames) {
  if (files.has(key(name))) throw new Error(`Ambiguous texture filename: ${name}`);
  files.set(key(name),{name,bytes:await readFile(resolve(textureFolder,name))});
}

function fingerprint(node,hash=createHash('sha256')) {
  hash.update(node.name);
  for (const property of node.properties) hash.update(property.raw);
  for (const item of node.children) fingerprint(item,hash);
  return hash;
}
const protectedNodes=objects.children.filter(node=>!['Texture','Video'].includes(node.name));
const protectedHashes=protectedNodes.map(node=>fingerprint(node).digest('hex'));
const manifest=[];
const replacements=new Map();
for (const video of videos) {
  const previous=text(video,'RelativeFilename') || text(video,'Filename');
  const file=files.get(key(previous));
  if (!file) throw new Error(`No supplied texture matches ${previous}`);
  const portable=`textures/${file.name}`;
  replacements.set(key(previous),portable);
  const existing=child(video,'Content');
  const content={name:'Content',properties:[binaryProperty(file.bytes)],children:[],terminator:false};
  if (existing) video.children[video.children.indexOf(existing)]=content;
  else video.children.push(content);
  video.terminator=true;
  manifest.push({slot:key(previous),file:file.name,bytes:file.bytes.length,sha256:createHash('sha256').update(file.bytes).digest('hex')});
}
assert.equal(manifest.length,filenames.length,'Every supplied texture must be connected to a material.');

function rewritePaths(node) {
  for (let i=0;i<node.properties.length;i++) {
    const property=node.properties[i];
    if (property.type!=='S' || !/\.(png|jpe?g)$/i.test(property.value)) continue;
    const replacement=replacements.get(key(property.value));
    if (replacement) node.properties[i]=stringProperty(replacement);
  }
  for (const nested of node.children) rewritePaths(nested);
}
for (const node of objects.children.filter(node=>['Video','Texture'].includes(node.name))) rewritePaths(node);

const output=encodeBinaryFBX(document);
const verified=parseBinaryFBX(output);
assert.ok(encodeBinaryFBX(verified).equals(output),'Reassembled FBX must retain valid offsets and footer alignment.');
const verifiedObjects=verified.nodes.find(node=>node.name==='Objects');
assert.deepEqual(verifiedObjects.children.filter(node=>!['Texture','Video'].includes(node.name)).map(node=>fingerprint(node).digest('hex')),protectedHashes,
  'Geometry, materials, bones, skin weights, and animation must remain byte-identical.');
for (const video of verifiedObjects.children.filter(node=>node.name==='Video')) {
  const path=text(video,'RelativeFilename');
  assert.ok(path.startsWith('textures/'));
  assert.ok(text(video,'Content').equals(files.get(key(path)).bytes),'Embedded pixels must match the supplied texture exactly.');
}
await writeFile(outputPath+'.tmp',output);
await rename(outputPath+'.tmp',outputPath);
await writeFile(resolve(root,'imports/my-avatar/assembly.json'),JSON.stringify({source:'source/Silly Dancing.fbx',output:'../My Avatar.fbx',version:document.version,embeddedTextures:manifest,verifiedGeometryAndRig:true},null,2)+'\n');
console.log(`Assembled ${outputPath}`);
console.log(`${(output.length/1048576).toFixed(2)} MB · ${manifest.length} embedded textures · original geometry, rig, materials, and animation preserved`);
for (const texture of manifest) console.log(`  ${texture.file}`);
