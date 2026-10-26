import test from 'node:test';
import assert from 'node:assert/strict';
import { validateCue } from '../core.mjs';
import { resolveResponse, ReactionDirector, findClip } from '../reaction-policy.mjs';

const available=['Breathing Idle','Thinking','Talking','Salute','Pointing','Waving','Shrugging','Clapping','Cheering','Sitting Fist Pump','Sitting Thumbs Up','Laughing','Surprised','Hard Head Nod','Lengthy Head Nod','acknowledging','angry gesture','annoyed head shake','being cocky','dismissing gesture','happy hand gesture','head nod yes','look away gesture','relieved sigh','sarcastic head nod','thoughtful head shake','weight shift'];
const cue=(overrides={})=>({intent:'steady',expression:'attentive',gesture:'acknowledge',caption:'Good question.',...overrides});
const selected=overrides=>resolveResponse(cue(overrides),available).animation;

test('native structured response validation preserves context and ordering',()=>{
  const result=validateCue({...cue(),intensity:3,verifiedGoal:false,source:'app',sequence:2,sessionId:'session',eventId:'session:2'});
  assert.equal(result.intensity,1); assert.equal(result.source,'app'); assert.equal(result.eventId,'session:2');
  assert.throws(()=>validateCue(cue({expression:'invented'})));
  assert.throws(()=>validateCue(cue({intent:'invented'})));
  assert.throws(()=>validateCue(cue({sequence:-2})));
});

test('routine responses use the new subtle acknowledgment and nod clips',()=>{
  assert.equal(selected({gesture:'acknowledge'}),'acknowledging');
  assert.equal(selected({gesture:'agree',intensity:0.3}),'head nod yes');
  assert.equal(selected({gesture:'nod',intensity:0.4}),'head nod yes');
  assert.equal(selected({gesture:'agree',intensity:0.8}),'Hard Head Nod');
  assert.equal(selected({gesture:'none'}),'Breathing Idle');
});

test('reflective, relieved, uncertain, explanatory and positive responses have distinct motions',()=>{
  assert.equal(selected({intent:'thinking',gesture:'none'}),'Thinking');
  assert.equal(selected({intent:'check',expression:'concerned',gesture:'none'}),'thoughtful head shake');
  assert.equal(selected({intent:'pause',expression:'relieved',gesture:'sigh'}),'relieved sigh');
  assert.equal(selected({expression:'uncertain',gesture:'shrug'}),'Shrugging');
  assert.equal(selected({intent:'prompt',gesture:'talk'}),'Talking');
  assert.equal(selected({expression:'pleased',gesture:'celebrate'}),'happy hand gesture');
  assert.equal(selected({intent:'focus',gesture:'point'}),'Pointing');
  assert.equal(selected({intent:'wrap',gesture:'wave'}),'Waving');
  assert.equal(selected({intent:'listen',gesture:'weightShift'}),'weight shift');
});

test('strong attitudes require explicit expressions, never transcript/caption keywords',()=>{
  for(const [expression,animation] of Object.entries({angry:'angry gesture',annoyed:'annoyed head shake',sarcastic:'sarcastic head nod',cocky:'being cocky',dismissive:'dismissing gesture'})) assert.equal(selected({expression}),animation);
  assert.equal(selected({caption:'Do not become angry or sarcastic here.'}),'acknowledging');
  assert.equal(selected({intent:'listen',expression:'angry',gesture:'none'}),'Breathing Idle');
});

test('verified achievements have priority and ordinary praise cannot invent one',()=>{
  assert.equal(selected({intent:'goal',verifiedGoal:true,intensity:0.75}),'Salute');
  assert.equal(selected({intent:'goal',verifiedGoal:true,intensity:0.9}),'Cheering');
  assert.equal(selected({intent:'goal',verifiedGoal:false}),'acknowledging');
  assert.equal(selected({gesture:'salute',verifiedGoal:false}),'acknowledging');
});

test('case variants resolve to actual loaded clips, with graceful missing-asset fallback',()=>{
  assert.equal(findClip(['acknowledging','hard head nod'],['Acknowledging']),'acknowledging');
  assert.equal(findClip(['hard head nod'],['Hard Head Nod']),'hard head nod');
  assert.equal(resolveResponse(cue({expression:'relieved'}),['Breathing Idle']).animation,'Breathing Idle');
  assert.equal(new ReactionDirector().decide(cue(),[],0).play,false);
});

test('cooldowns and priorities prevent twitchy or overlapping response gestures',()=>{
  const director=new ReactionDirector();
  const first=director.decide(cue(),available,0); assert.equal(first.play,true); director.commit(first,0,1);
  assert.equal(director.decide(cue({gesture:'agree'}),available,2).play,false);
  const redirect=director.decide(cue({intent:'focus',gesture:'point'}),available,7); assert.equal(redirect.play,true); director.commit(redirect,7,3);
  assert.equal(director.decide(cue(),available,8).play,false);
  const goal=director.decide(cue({intent:'goal',verifiedGoal:true}),available,8); assert.equal(goal.play,true); director.commit(goal,8,3);
  assert.equal(director.decide(cue({intent:'focus',gesture:'point'}),available,9).play,false);
});

test('a firm redirect can interrupt an incompatible lower-priority reaction',()=>{
  const director=new ReactionDirector();
  const laughter=director.decide(cue({expression:'amused'}),available,0); director.commit(laughter,0,10);
  assert.equal(director.decide(cue({intent:'focus',gesture:'point'}),available,1).play,true);
});

test('duplicates and out-of-order responses cannot change the current caption or animation',()=>{
  const director=new ReactionDirector();
  director.decide(cue({sessionId:'a',sequence:4,eventId:'a:4'}),available,0);
  assert.equal(director.decide(cue({eventId:'a:4'}),available,10).ignored,true);
  assert.equal(director.decide(cue({sessionId:'a',sequence:3}),available,10).ignored,true);
});

test('manual previews are protected; rehearsal bypasses pacing without changing live history',()=>{
  const director=new ReactionDirector(); director.manual(0,5);
  assert.equal(director.decide(cue(),available,1).play,false);
  assert.equal(director.decide(cue(),available,1,{preview:true}).play,true);
  assert.equal(director.decide(cue({intent:'idle',gesture:'none'}),available,2).play,true);
  const thinking=director.decide(cue({intent:'thinking',gesture:'none'}),available,3); director.commit(thinking,3,5);
  assert.equal(director.decide(cue(),available,3.2).play,true,'Ready advice should replace the low-priority thinking pose');
});
