const { chromium } = require('/tmp/baseball-browser-tools/node_modules/playwright');
const assert = require('node:assert/strict');

(async () => {
  const browser = await chromium.launch({headless:true,executablePath:'/Users/joeyjanisheck/Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell'});
  const page = await browser.newPage({viewport:{width:1480,height:1100},deviceScaleFactor:1});
  const errors=[];
  page.on('pageerror',error => errors.push(error.message));
  page.on('console',message => { if (message.type()==='error') { errors.push(message.text()); console.log('BROWSER ERROR',message.text()); } });
  await page.goto('http://127.0.0.1:4173');
  if (process.argv.includes('--inspect')) {
    await page.waitForTimeout(3000);
    console.log('inspection', await page.evaluate(() => ({notice:document.getElementById('notice')?.textContent,loading:document.getElementById('loading-detail')?.textContent,snapshot:window.coach?.snapshot()})));
    await page.screenshot({path:'/tmp/kochi-web-workshop.png',fullPage:true});
    await page.getByRole('button',{name:'Full body',exact:true}).click(); await page.waitForTimeout(200);
    await page.screenshot({path:'/tmp/kochi-web-full.png',fullPage:true});
    await browser.close(); return;
  }
  await page.waitForFunction(() => window.coach?.snapshot().animations.length===35 && !window.coach.snapshot().importing,{},{timeout:90000}).catch(async error => { console.log('LOAD FAILED',await page.locator('body').innerText()); throw error; });
  await page.waitForTimeout(600);
  if (process.argv.includes('--responses')) {
    assert.equal((await page.evaluate(()=>window.coach.snapshot().animations)).length,35);
    const baseline=await page.evaluate(()=>window.coach.snapshot().camera);
    const cases=[['Acknowledge','acknowledging'],['Agree','head nod yes'],['Consider','Thinking'],['Refocus','Pointing'],['Encourage','happy hand gesture'],['Breathe','relieved sigh'],['Uncertain','Shrugging'],['Celebrate','Salute'],['Wrap up','Waving']];
    for (const [button,animation] of cases) {
      await page.getByRole('button',{name:button,exact:true}).click();
      await page.waitForTimeout(100);
      const snapshot=await page.evaluate(()=>window.coach.snapshot());
      assert.equal(snapshot.current,animation,`${button} chose the wrong animation`);
      assert.equal(snapshot.response.animation,animation);
      assert.deepEqual(snapshot.camera,baseline);
      assert.ok((await page.evaluate(()=>window.coach.debug())).visible>1500);
    }
    // Raw filenames remain usable for asset inspection; structured responses
    // use the pacing policy and captions instead of keyword matching.
    await page.getByRole('button',{name:'Breathe',exact:true}).click();
    await page.waitForFunction(()=>window.coach.snapshot().current==='Breathing Idle',{},{timeout:12000});
    await page.waitForTimeout(1200);
    const {promisify}=require('node:util'), {execFile}=require('node:child_process');
    const native=await promisify(execFile)('/Volumes/CODYRHODES/XCODEBUILDS/Debug/Kochi.app/Contents/MacOS/Kochi',['--selftest-avatar','--verify-workshop-bridge'],{timeout:30000,maxBuffer:100000});
    console.log('NATIVE BRIDGE',native.stdout.trim());
    await page.waitForFunction(()=>window.coach.snapshot().response?.caption==='Workshop connection verified.');
    let nativeCue=await page.evaluate(()=>window.coach.snapshot().response);
    assert.equal(nativeCue.source,'app'); assert.equal(nativeCue.animation,'acknowledging'); assert.equal(nativeCue.played,true);
    const identity=nativeCue.eventId;
    await page.getByLabel('Live coach',{exact:true}).uncheck();
    await page.request.post('http://127.0.0.1:4173/api/react',{data:{intent:'focus',gesture:'point',caption:'Disabled live cue',source:'app'}});
    await page.waitForTimeout(150);
    assert.equal(await page.evaluate(()=>window.coach.snapshot().response.eventId),identity);
    await page.getByRole('button',{name:'Reset',exact:true}).click();
    assert.equal(await page.getByLabel('Live coach',{exact:true}).isChecked(),true);
    await page.waitForFunction(async()=> (await fetch('/api/coach-status').then(r=>r.json())).live===true);
    await page.screenshot({path:'/tmp/kochi-context-responses.png',fullPage:true});
    console.log('errors',JSON.stringify(errors)); assert.deepEqual(errors,[]);
    console.log('PASS: 35 imported clips, nine contextual mappings, actual native response bridge, live toggle, fixed camera.');
    await browser.close();return;
  }
  if (process.argv.includes('--avatar')) {
    for (const label of ['Powerpuff','Soldier','Sauron','Elf','My Avatar']) assert.equal(await page.getByRole('option',{name:label,exact:true}).count(),1);
    await page.route('**/imports/my-avatar/textures/**',route=>route.abort());
    await page.getByRole('combobox',{name:'Character model',exact:true}).selectOption('My Avatar.fbx');
    await page.waitForFunction(()=>window.coach.snapshot().model==='My Avatar.fbx' && !window.coach.snapshot().switching,{},{timeout:60000});
    const camera=await page.evaluate(()=>window.coach.snapshot().camera);
    assert.equal((await page.evaluate(()=>window.coach.snapshot().animations)).length,35);
    for(const clip of ['Breathing Idle','Salute','Thinking','Waving','Sitting Fist Pump','Shaking Head No','acknowledging','head nod yes','thoughtful head shake','relieved sigh','angry gesture','being cocky']) {
      await page.evaluate(clip=>{window.coach.play(clip,{immediate:true});window.coach.seek(0.8);},clip);
      await page.waitForTimeout(100);
      const joints=(await page.evaluate(()=>window.coach.snapshot())).joints;
      assert.ok(joints.head[1]>1.3 && joints.head[1]<2.1 && Math.abs(joints.head[2])<0.6,`${clip} has an incorrectly oriented avatar`);
      if(clip==='Salute')await page.screenshot({path:'/tmp/kochi-my-avatar-salute.png',fullPage:true});
      assert.deepEqual(await page.evaluate(()=>window.coach.snapshot().camera),camera);
      assert.ok((await page.evaluate(()=>window.coach.debug())).visible>1500,`${clip} lost the avatar`);
    }
    await page.evaluate(()=>{window.coach.play('Breathing Idle',{immediate:true});window.coach.seek(0.6);});
    await page.getByRole('button',{name:'Clean 3D',exact:true}).click();
    await page.waitForTimeout(250);
    await page.screenshot({path:'/tmp/kochi-my-avatar-clean.png',fullPage:true});
    await page.getByRole('button',{name:'Pixel',exact:true}).click();
    await page.waitForTimeout(150);
    await page.screenshot({path:'/tmp/kochi-my-avatar-pixel.png',fullPage:true});
    await page.getByRole('button',{name:'Show rest pose',exact:true}).click();
    assert.equal(await page.evaluate(()=>window.coach.snapshot().restPose),true);
    assert.deepEqual(await page.evaluate(()=>window.coach.snapshot().camera),camera);
    await page.getByRole('button',{name:'Return to animation',exact:true}).click();
    console.log('avatar',JSON.stringify(await page.evaluate(()=>window.coach.snapshot())));
    console.log('errors',JSON.stringify(errors)); assert.deepEqual(errors,[]);
    await browser.close(); console.log('PASS: friendly labels, portable embedded avatar, 35 motions, 12 played, T-pose, fixed bust camera.'); return;
  }
  console.log('initial',JSON.stringify(await page.evaluate(() => window.coach.snapshot())));
  await page.screenshot({path:'/tmp/kochi-web-workshop.png',fullPage:true});
  assert.ok((await page.evaluate(() => window.coach.debug())).visible>5000,'Loaded model is not visibly rendered in the bust crop');
  const camera=await page.evaluate(() => window.coach.snapshot().camera);
  const clips=await page.evaluate(() => window.coach.snapshot().animations);
  for (const name of clips) {
    await page.evaluate(name => window.coach.play(name,{immediate:true}),name);
    await page.waitForTimeout(150);
    await page.evaluate(() => window.coach.seek(0.8));
    await page.waitForTimeout(80);
    const snapshot=await page.evaluate(() => window.coach.snapshot());
    const debug=await page.evaluate(() => window.coach.debug());
    const surface=debug.materials.find(mesh=>mesh.name==='Beta_Surface');
    const joints=debug.materials.find(mesh=>mesh.name==='Beta_Joints');
    assert.ok(joints.bounds.max.y<=surface.bounds.max.y+8,`${name} has floating joint geometry`);
    assert.deepEqual(snapshot.camera,camera,`${name} moved the camera`);
    assert.equal(snapshot.frame,'bust');
    assert.ok((await page.evaluate(() => window.coach.debug())).visible>2500,`${name} moved the model outside the bust crop`);
  }
  await page.evaluate(() => { window.coach.play('Salute',{immediate:true}); window.coach.seek(0.8); });
  await page.waitForTimeout(150);
  await page.screenshot({path:'/tmp/kochi-web-salute.png',fullPage:true});
  await page.getByRole('slider',{name:/^Hand size/}).fill('1.2');
  await page.waitForTimeout(300);
  const handsA=await page.evaluate(() => window.coach.snapshot().hands);
  await page.waitForTimeout(300);
  assert.deepEqual(await page.evaluate(() => window.coach.snapshot().hands),handsA,'Hand resizing accumulated over frames');
  await page.getByRole('button',{name:'Reset',exact:true}).click();
  await page.getByRole('button',{name:'Clean 3D',exact:true}).click();
  await page.waitForTimeout(200);
  await page.screenshot({path:'/tmp/kochi-web-clean.png',fullPage:true});
  await page.getByRole('button',{name:'Pixel',exact:true}).click();
  await page.evaluate(() => window.coach.play('Breathing Idle',{immediate:true}));
  await page.getByRole('button',{name:'Celebrate',exact:true}).click();
  await page.waitForTimeout(150);
  assert.equal(await page.evaluate(() => window.coach.snapshot().current),'Salute');
  await page.waitForFunction(() => window.coach.snapshot().current==='Breathing Idle',{},{timeout:6000});
  const cueResponse=await page.request.post('http://127.0.0.1:4173/api/react',{data:{animation:'Hard Head Nod',once:true,gaze:[0.2,0]}});
  assert.equal(cueResponse.status(),200);
  await page.waitForFunction(() => window.coach.snapshot().current==='Hard Head Nod');
  assert.deepEqual(await page.evaluate(() => window.coach.snapshot().camera),camera,'Agent cue moved the camera');
  assert.equal((await page.evaluate(() => window.coach.snapshot().models)).length,6);
  const modelNames=(await page.evaluate(() => window.coach.snapshot().models)).filter(name=>/^Ch/.test(name));
  for (const name of modelNames) {
    await page.getByRole('combobox',{name:'Character model',exact:true}).selectOption(name);
    await page.waitForFunction(name => !window.coach.snapshot().switching && window.coach.snapshot().model===name,name,{timeout:120000});
    assert.equal((await page.evaluate(() => window.coach.snapshot().animations)).length,35,`${name} lost animations`);
    const modelCamera=await page.evaluate(() => window.coach.snapshot().camera);
    for (const clip of ['Breathing Idle','Salute','Thinking','Shrugging','Sitting Fist Pump','Waving']) {
      await page.evaluate(clip => {window.coach.play(clip,{immediate:true});window.coach.seek(0.8);},clip);
      await page.waitForTimeout(80);
      const snapshot=await page.evaluate(() => window.coach.snapshot());
      assert.deepEqual(snapshot.camera,modelCamera,`${name}/${clip} moved the camera`);
      for (const point of Object.values(snapshot.joints)) assert.ok(point.every(Number.isFinite),`${name}/${clip} has invalid joints`);
      assert.ok((await page.evaluate(() => window.coach.debug())).visible>1000,`${name}/${clip} is outside the bust crop`);
    }
    await page.evaluate(()=>{window.coach.play('Salute',{immediate:true});window.coach.seek(0.8);});
    await page.waitForTimeout(100);
    await page.screenshot({path:`/tmp/kochi-model-${name.replace('.fbx','')}.png`,fullPage:true});
    await page.getByRole('button',{name:'Show rest pose',exact:true}).click();
    assert.equal(await page.evaluate(()=>window.coach.snapshot().restPose),true);
    assert.deepEqual(await page.evaluate(()=>window.coach.snapshot().camera),modelCamera,'T-pose moved the camera');
    await page.getByRole('button',{name:'Return to animation',exact:true}).click();
    console.log('MODEL PASS',name);
  }
  // Model choice survives reload; an animation embedded in an FBX is not
  // mistaken for an extra character selection.
  await page.getByRole('combobox',{name:'Character model',exact:true}).selectOption('Ch03_nonPBR.fbx');
  await page.waitForFunction(()=>window.coach.snapshot().model==='Ch03_nonPBR.fbx' && !window.coach.snapshot().switching,{},{timeout:120000});
  await page.reload();
  await page.waitForFunction(()=>window.coach?.snapshot().model==='Ch03_nonPBR.fbx' && !window.coach.snapshot().switching && !window.coach.snapshot().importing,{},{timeout:120000});
  assert.equal(await page.getByRole('combobox',{name:'Character model',exact:true}).inputValue(),'Ch03_nonPBR.fbx');
  await page.setViewportSize({width:390,height:844});
  await page.waitForTimeout(200);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth<=innerWidth),true,'Mobile layout overflows');
  await page.screenshot({path:'/tmp/kochi-web-mobile.png',fullPage:true});
  console.log('errors',JSON.stringify(errors));
  assert.deepEqual(errors,[]);
  console.log('PASS: 35 clips, six character choices, four model swaps with six motions each, T-pose, persistence, fixed camera, hand sizing, agent cues, mobile layout.');
  await browser.close();
})().catch(error => { console.error(error); process.exit(1); });
