import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parseBinaryFBX, encodeBinaryFBX, stringProperty, text } from '../fbx-binary.mjs';

test('FBX reassembly preserves source geometry and both binary header variants',async context => {
  for (const relative of ['Breathing Idle.fbx','my-avatar/source/Silly Dancing.fbx']) {
    let bytes;
    try { bytes=await readFile(new URL(`../imports/${relative}`,import.meta.url)); }
    catch (error) { if (error.code==='ENOENT') { context.skip('Local FBX fixture is not installed.'); return; } throw error; }
    const document=parseBinaryFBX(bytes);
    assert.ok(encodeBinaryFBX(document).equals(bytes));
    const objects=document.nodes.find(node=>node.name==='Objects');
    assert.ok(objects.children.some(node=>node.name==='Geometry'));
    // Change a string length to exercise absolute offsets and footer alignment.
    const video=objects.children.find(node=>node.name==='Video');
    if (video) {
      const path=video.children.find(node=>node.name==='RelativeFilename');
      path.properties=[stringProperty('textures/a-different-portable-name.jpeg')];
      const modified=encodeBinaryFBX(document), reparsed=parseBinaryFBX(modified);
      assert.ok(encodeBinaryFBX(reparsed).equals(modified));
    }
  }
});

test('assembled avatar embeds the current supplied texture files',async context => {
  let bytes;
  try { bytes=await readFile(new URL('../imports/My Avatar.fbx',import.meta.url)); }
  catch (error) { if (error.code==='ENOENT') { context.skip('Local avatar is not assembled.'); return; } throw error; }
  const document=parseBinaryFBX(bytes);
  const videos=document.nodes.find(node=>node.name==='Objects').children.filter(node=>node.name==='Video');
  assert.equal(videos.length,13);
  for (const video of videos) {
    const relative=text(video,'RelativeFilename');
    assert.ok(relative.startsWith('textures/'));
    const supplied=await readFile(new URL(`../imports/my-avatar/${relative}`,import.meta.url));
    assert.ok(text(video,'Content').equals(supplied));
  }
});
