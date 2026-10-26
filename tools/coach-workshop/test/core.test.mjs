import test from 'node:test';
import assert from 'node:assert/strict';
import { animationLabel, boneKey, chooseBase, normalizeFBXBuffer, sanitizeSettings, validateCue, DEFAULTS } from '../core.mjs';

test('find the breathing model regardless of directory or drop order',() => {
  const files=[{name:'Salute.fbx'},{name:'Happy Idle.fbx'},{name:'Breathing Idle.fbx'}];
  assert.equal(chooseBase(files).name,'Breathing Idle.fbx');
  assert.equal(files[0].name,'Salute.fbx');
});

test('Mixamo namespace variations resolve to the same bone role',() => {
  for (const name of ['mixamorigHead','mixamorig:Head','Armature|mixamorigHead','mixamorig1Head']) assert.equal(boneKey(name),'head');
  assert.equal(boneKey('mixamorigRightHandIndex1'),'righthandindex1');
});

test('animation names come from filenames, without losing meaningful words',() => {
  assert.equal(animationLabel('Sitting Thumbs Up.fbx'),'Sitting Thumbs Up');
});

test('invalid setup values cannot break camera, scaling or render resolution',() => {
  const settings=sanitizeSettings({handScale:Infinity,resolution:0,tones:900,speed:-10,headYaw:NaN,frame:'automatic',loop:'yes'});
  assert.equal(settings.handScale,DEFAULTS.handScale);
  assert.equal(settings.resolution,120);
  assert.equal(settings.tones,32);
  assert.equal(settings.speed,0.1);
  assert.equal(settings.headYaw,0);
  assert.equal(settings.frame,'bust');
  assert.equal(settings.loop,true);
});

test('agent reactions are structured data with bounded gaze',() => {
  assert.deepEqual(validateCue({animation:' Salute ',gaze:[-4,2]}),{animation:'Salute',once:true,gaze:[-1,1]});
  assert.deepEqual(validateCue({animation:'Breathing Idle',once:false}),{animation:'Breathing Idle',once:false});
  for (const bad of [null,[],{}, {animation:8},{animation:''},{animation:'Salute',gaze:[NaN,0]},{animation:'Salute',gaze:[0]}]) assert.throws(() => validateCue(bad));
});

test('only the extra newline after the exact FBX closing magic is removed',()=>{
  const footer=[0xf8,0x5a,0x8c,0x6a,0xde,0xf5,0xd9,0x7e,0xec,0xe9,0x0c,0xe3,0x75,0x8f,0x29,0x0b];
  const download=new Uint8Array([7,8,9,...footer,10]).buffer;
  assert.deepEqual([...new Uint8Array(normalizeFBXBuffer(download))],[7,8,9,...footer]);
  const other=new Uint8Array([1,2,3,10]).buffer;
  assert.equal(normalizeFBXBuffer(other),other);
  const valid=new Uint8Array([1,2,3,...footer]).buffer;
  assert.equal(normalizeFBXBuffer(valid),valid);
});
