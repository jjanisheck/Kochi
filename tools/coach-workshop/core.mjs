export const DEFAULTS = Object.freeze({
  style: 'pixel', resolution: 360, tones: 10, handScale: 1,
  headYaw: 0, headPitch: 0, turn: 0, speed: 1, blend: 0.4,
  loop: true, skeleton: false, follow: false, frame: 'bust',
  model: 'Breathing Idle.fbx',
  liveCoach: true,
});

export function isCharacterFile(name) {
  return /^ch\d+[_-]/i.test(name) || /(?:^|[\s_-])(?:t[\s_-]?pose|character|model|avatar)(?:[\s_.-]|$)/i.test(name);
}

export function modelLabel(name) {
  const names = { ch03:'Powerpuff', ch15:'Soldier', ch25:'Sauron', ch34:'Elf' };
  const id = name.match(/^(ch\d+)(?:[_\-.]|$)/i)?.[1].toLowerCase();
  if (names[id]) return names[id];
  if (name === 'Breathing Idle.fbx') return 'Original mannequin';
  return animationLabel(name).replace(/ nonPBR$/i,'');
}

export function boneKey(name) {
  return name.replace(/^.*[|:]/, '').replace(/^mixamorig\d*/i, '').replace(/[^a-z0-9]/gi, '').toLowerCase();
}

export function animationLabel(filename) {
  return filename.replace(/\.(fbx|glb|gltf)$/i, '').replace(/[_-]+/g, ' ').trim();
}

export function normalizeFBXBuffer(buffer) {
  const bytes=new Uint8Array(buffer);
  const footer=[0xf8,0x5a,0x8c,0x6a,0xde,0xf5,0xd9,0x7e,0xec,0xe9,0x0c,0xe3,0x75,0x8f,0x29,0x0b];
  // Some downloaded FBXs append LF after the binary footer. At one alignment,
  // FBXLoader tries to parse that footer as another node. Remove only this
  // exact suffix, never an arbitrary trailing byte from animation/image data.
  if (bytes.length>=17 && bytes.at(-1)===10 && footer.every((value,index)=>bytes[bytes.length-17+index]===value)) return bytes.slice(0,-1).buffer;
  return buffer;
}

export function chooseBase(files) {
  return [...files].sort((a,b) => {
    const rank = f => /breathing.?idle/i.test(f.name) ? 0 : /idle/i.test(f.name) ? 1 : 2;
    return rank(a) - rank(b) || a.name.localeCompare(b.name);
  })[0];
}

export function sanitizeSettings(input = {}) {
  const out = { ...DEFAULTS };
  const ranges = { resolution:[120,720], tones:[3,32], handScale:[0.6,1.6], headYaw:[-45,45], headPitch:[-25,25], turn:[-180,180], speed:[0.1,2], blend:[0,1.5] };
  for (const [key,[min,max]] of Object.entries(ranges)) {
    if (typeof input[key] === 'number' && Number.isFinite(input[key])) out[key] = Math.max(min,Math.min(max,input[key]));
  }
  for (const key of ['loop','skeleton','follow','liveCoach']) if (typeof input[key] === 'boolean') out[key] = input[key];
  if (['pixel','clean'].includes(input.style)) out.style = input.style;
  if (['bust','full'].includes(input.frame)) out.frame = input.frame;
  if (typeof input.model === 'string' && input.model.length < 256 && !/[\\/]/.test(input.model) && /\.(fbx|glb)$/i.test(input.model)) out.model = input.model;
  return out;
}

export function validateCue(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Send a JSON object.');
  let cue;
  if (value.animation !== undefined) {
    if (typeof value.animation !== 'string' || !value.animation.trim() || value.animation.length > 160) throw new Error('Choose an animation name.');
    cue = { animation: value.animation.trim(), once: value.once !== false };
  } else {
    const intents=['idle','listen','thinking','prompt','goal','focus','pause','timing','mute','check','steady','wrap'];
    const expressions=['neutral','attentive','thoughtful','encouraging','pleased','concerned','relieved','amused','surprised','uncertain','firm','annoyed','angry','sarcastic','cocky','dismissive'];
    const gestures=['none','nod','tilt','salute','openHand','checkWatch','breathe','wave','point','acknowledge','agree','disagree','shrug','talk','sigh','lookAway','clap','celebrate','weightShift'];
    if (!intents.includes(value.intent)) throw new Error('Provide a coaching intent or an animation name.');
    if (value.expression!==undefined && !expressions.includes(value.expression)) throw new Error('Unknown coach expression.');
    if (value.gesture!==undefined && !gestures.includes(value.gesture)) throw new Error('Unknown coach gesture.');
    if (value.caption!==undefined && (typeof value.caption!=='string' || value.caption.length>1000)) throw new Error('Coach caption must be at most 1,000 characters.');
    if (value.intensity!==undefined && (typeof value.intensity!=='number' || !Number.isFinite(value.intensity))) throw new Error('Intensity must be numeric.');
    cue={intent:value.intent,expression:value.expression || 'attentive',gesture:value.gesture || 'none',intensity:Math.min(1,Math.max(0,value.intensity ?? 0.4)),caption:(value.caption || '').trim(),verifiedGoal:value.verifiedGoal===true,once:true};
  }
  if (value.gaze !== undefined) {
    if (!Array.isArray(value.gaze) || value.gaze.length !== 2 || !value.gaze.every(n => typeof n === 'number' && Number.isFinite(n))) throw new Error('Gaze must be [horizontal, vertical], each between -1 and 1.');
    cue.gaze = value.gaze.map(n => Math.max(-1,Math.min(1,n)));
  }
  for (const key of ['eventId','sessionId']) {
    if (value[key]!==undefined) {
      if (typeof value[key]!=='string' || value[key].length>160) throw new Error(`Invalid ${key}.`);
      cue[key]=value[key];
    }
  }
  if (value.sequence!==undefined) {
    if (!Number.isSafeInteger(value.sequence) || value.sequence<0) throw new Error('Invalid response sequence.');
    cue.sequence=value.sequence;
  }
  if (value.source!==undefined) {
    if (!['app','agent','preview'].includes(value.source)) throw new Error('Invalid response source.');
    cue.source=value.source;
  }
  return cue;
}

export function clockLabel(seconds) {
  return `${Math.max(0,seconds).toFixed(2)}s`;
}
