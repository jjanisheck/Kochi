import { validateCue } from './core.mjs';

export const clipKey=name=>name.toLowerCase().replace(/[^a-z0-9]/g,'');
export function findClip(available,names) {
  const clips=[...available];
  for (const name of names) {
    const exact=clips.find(clip=>clip===name);
    if (exact) return exact;
    const match=clips.find(clip=>clipKey(clip)===clipKey(name));
    if (match) return match;
  }
  return null;
}

const rule=(id,candidates,reason,priority=2)=>({id,candidates,reason,priority});
const idle=()=>rule('listen',['Breathing Idle','weight shift','Happy Idle'],'Quiet listening and breathing.',0);

export function responseRule(input) {
  const cue=validateCue(input);
  if (cue.animation) return rule('explicit',[cue.animation],'Explicit animation preview.',3);
  if (cue.intent==='idle') return {...idle(),id:'idle',reason:'Session idle: return to breathing.'};
  if (cue.intent==='listen' && cue.gesture!=='weightShift') return idle();
  if (cue.intent==='goal') {
    if (cue.verifiedGoal) return rule('achievement',cue.intensity>=0.85?['Cheering','Sitting Fist Pump','Clapping','Salute']:cue.intensity>=0.65?['Salute','Clapping','Sitting Fist Pump']:['Clapping','Sitting Thumbs Up','acknowledging'],'A verified goal was completed.',4);
    return rule('encouragement',['acknowledging','head nod yes','Sitting Thumbs Up'],'Positive advice without a verified goal uses restrained encouragement.');
  }
  // These are explicit attitudes of the coach response. Conversation keywords
  // or a participant's inferred mood never activate them.
  const attitudes={
    angry:rule('angry',['angry gesture','annoyed head shake','Shaking Head No'],'Explicit angry coach expression.',3),
    annoyed:rule('annoyed',['annoyed head shake','thoughtful head shake'],'Explicit annoyed coach expression.',3),
    sarcastic:rule('sarcastic',['sarcastic head nod','head nod yes'],'Explicit sarcastic coach expression.'),
    cocky:rule('cocky',['being cocky','happy hand gesture'],'Explicit cocky coach expression.'),
    dismissive:rule('dismissive',['dismissing gesture','look away gesture'],'Explicit dismissive coach expression.'),
    relieved:rule('relieved',['relieved sigh','Breathing Idle'],'The coach expresses relief; release the tension.'),
    amused:rule('amused',['Laughing','Happy Idle'],'The coach is explicitly amused.'),
    surprised:rule('surprised',['Surprised','acknowledging'],'The response explicitly marks surprise.'),
    uncertain:rule('uncertain',['Shrugging','Thinking'],'The coach expresses uncertainty.'),
  };
  if (attitudes[cue.expression]) return attitudes[cue.expression];
  if (cue.intent==='thinking') return rule('thinking',['Thinking','thoughtful head shake'],'Considering the conversation before responding.',1);
  if (cue.intent==='wrap') return rule('wrap',['Waving','relieved sigh','acknowledging'],'The session is wrapping up.',3);
  const gestures={
    acknowledge:rule('acknowledge',['acknowledging','head nod yes','Lengthy Head Nod'],'Brief acknowledgment of the response.'),
    agree:rule('agree',cue.intensity>=0.75?['Hard Head Nod','head nod yes']:['head nod yes','acknowledging','Lengthy Head Nod'],'The response explicitly agrees.'),
    disagree:rule('disagree',['thoughtful head shake','Shaking Head No'],'A considered correction, rather than irritation.'),
    shrug:rule('uncertain',['Shrugging','Thinking'],'The coach asks for more information or expresses uncertainty.'),
    sigh:rule('relieved',['relieved sigh','Breathing Idle'],'An explicit release-of-tension cue.'),
    lookAway:rule('look-away',['look away gesture','Breathing Idle'],'An explicitly requested glance away.'),
    weightShift:rule('idle-variation',['weight shift','Breathing Idle'],'A subtle idle variation.',0),
    wave:rule('greeting',['Waving','acknowledging'],'A greeting or sign-off.'),
    point:rule('focus',['Pointing','Talking'],'Direct attention to a concrete coaching prompt.',3),
    openHand:rule('explain',['Talking','happy hand gesture','acknowledging'],'Invite a contribution with an open-hand explanation.'),
    talk:rule('explain',['Talking','acknowledging'],'Explain a suggestion conversationally.'),
    checkWatch:rule('timing',['Checking Watch','Pointing','Talking'],'A time or pacing reminder.',3),
    tilt:rule('reflect',['Thinking','thoughtful head shake'],'A reflective cue, not a negative judgment.'),
    nod:rule('acknowledge',cue.intensity>=0.75?['Hard Head Nod','head nod yes']:['head nod yes','acknowledging','Lengthy Head Nod'],'A restrained nod matches routine feedback.'),
    breathe:idle(),
    salute:rule('acknowledge',['acknowledging','head nod yes'],'Salutes are reserved for verified goal events.'),
    celebrate:rule('encouragement',['happy hand gesture','Sitting Thumbs Up','acknowledging'],'Encouragement without inventing a goal completion.'),
    clap:rule('encouragement',['happy hand gesture','Sitting Thumbs Up','acknowledging'],'Save goal applause for verified achievements.'),
  };
  if (gestures[cue.gesture]) return gestures[cue.gesture];
  if (cue.gesture==='none' && cue.intent==='steady') return idle();
  if (cue.intent==='listen' || cue.intent==='pause' || cue.gesture==='none' && cue.expression==='neutral') return idle();
  if (cue.intent==='timing') return rule('timing',['Pointing','Talking'],'A time or pacing reminder.',3);
  if (cue.intent==='mute') return rule('concise',['Talking','acknowledging'],'Invite a shorter contribution.',3);
  if (cue.intent==='focus') return rule('focus',['Pointing','Talking'],'Refocus attention on the coaching prompt.',3);
  if (cue.expression==='firm' || cue.expression==='concerned') return rule('reflect',['thoughtful head shake','Thinking'],'A considered coaching correction.',3);
  if (cue.intent==='check' || cue.expression==='thoughtful') return rule('reflect',['Thinking','thoughtful head shake'],'Reflect on progress or consider a question.');
  if (cue.expression==='pleased') return rule('pleased',['happy hand gesture','Sitting Thumbs Up','Happy Idle'],'Positive feedback without a major celebration.');
  if (cue.expression==='encouraging') return rule('encouragement',['acknowledging','head nod yes','Sitting Thumbs Up'],'Encourage progress with a small gesture.');
  if (cue.intent==='prompt') return rule('explain',['Talking','acknowledging'],'Invite a question or explain a suggestion.');
  return idle();
}

export function resolveResponse(cue,available) {
  const selected=responseRule(cue);
  const animation=findClip(available,selected.candidates) || findClip(available,['Breathing Idle','Happy Idle']);
  return {...selected,animation,once:selected.id!=='idle' && selected.id!=='listen'};
}

export class ReactionDirector {
  constructor() { this.lastGesture=-Infinity; this.lastByRule=new Map(); this.current=null; this.until=0; this.manualUntil=0; this.seen=new Set(); this.sessions=new Map(); }
  manual(now,duration=4) { this.manualUntil=now+Math.min(12,Math.max(2,duration)); }
  decide(input,available,now,{preview=false}={}) {
    const cue=validateCue(input), result=resolveResponse(cue,available);
    const blocked=reason=>({...result,play:false,reason});
    if (!result.animation) return blocked('No compatible animation is loaded.');
    if (preview) return {...result,play:true};
    if (cue.eventId) {
      if (this.seen.has(cue.eventId)) return {...blocked('Duplicate coach response.'),ignored:true};
      this.seen.add(cue.eventId); if (this.seen.size>128) this.seen.delete(this.seen.values().next().value);
    }
    if (cue.sessionId && cue.sequence!==undefined) {
      if (cue.sequence<=(this.sessions.get(cue.sessionId) ?? -1)) return {...blocked('An older coach response arrived late.'),ignored:true};
      this.sessions.set(cue.sessionId,cue.sequence);
      if (this.sessions.size>16) this.sessions.delete(this.sessions.keys().next().value);
    }
    if (result.id==='idle') { this.current=null; this.until=0; this.manualUntil=0; return {...result,play:true}; }
    if (now<this.manualUntil) return blocked('Manual animation preview is in progress.');
    if (this.current && now<this.until && this.current.priority>=result.priority) return blocked('Let the current reaction finish.');
    const interruptsLowerPriority=this.current && result.priority>this.current.priority;
    if (result.priority<4 && result.priority>0 && now-this.lastGesture<6 && this.current?.id!=='thinking' && !interruptsLowerPriority) return blocked('Keep a quiet pause between gestures.');
    if (now-(this.lastByRule.get(result.id) ?? -Infinity)<(result.priority===4?4:18)) return blocked('Avoid repeating the same reaction.');
    return {...result,play:true};
  }
  commit(result,now,duration) {
    this.current=result; this.until=now+duration;
    this.lastByRule.set(result.id,now);
    if (result.priority>1) this.lastGesture=now;
  }
}

export const RESPONSE_EXAMPLES=[
  {label:'Acknowledge',intent:'steady',expression:'attentive',gesture:'acknowledge',caption:'Good point. Give them a moment to respond.'},
  {label:'Agree',intent:'steady',expression:'encouraging',gesture:'agree',caption:'That question helped clarify what matters.'},
  {label:'Consider',intent:'check',expression:'thoughtful',gesture:'tilt',caption:'Check whether that answers the question they asked.'},
  {label:'Refocus',intent:'focus',expression:'firm',gesture:'point',caption:'Bring the discussion back to the decision you need.'},
  {label:'Encourage',intent:'steady',expression:'pleased',gesture:'celebrate',caption:'You made space for a useful contribution.'},
  {label:'Breathe',intent:'pause',expression:'relieved',gesture:'sigh',caption:'Take a breath. You have a clear next step.'},
  {label:'Uncertain',intent:'check',expression:'uncertain',gesture:'shrug',caption:'Ask what they mean before drawing a conclusion.'},
  {label:'Celebrate',intent:'goal',expression:'pleased',gesture:'salute',intensity:0.75,verifiedGoal:true,caption:'Goal achieved. You asked the follow-up question.'},
  {label:'Wrap up',intent:'wrap',expression:'pleased',gesture:'wave',caption:'Summarize the decision and confirm who owns the next step.'},
];
