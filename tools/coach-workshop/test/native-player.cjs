// Verify the exact offline files copied into the app, including file-origin
// loading, skinning after conversion, policy integration, and fixed framing.
const {chromium}=require('/tmp/baseball-browser-tools/node_modules/playwright');
const assert=require('node:assert/strict');
const {resolve}=require('node:path');
const {pathToFileURL}=require('node:url');

(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:'/Users/joeyjanisheck/Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell'});
  try {
    const page=await browser.newPage({viewport:{width:800,height:500}}),errors=[],external=[];
    page.on('pageerror',error=>errors.push(error.message));
    page.on('console',message=>{if(message.type()==='error')errors.push(message.text());});
    page.on('request',request=>{if(/^https?:/.test(request.url()))external.push(request.url());});
    await page.addInitScript(()=>{window.webkit={messageHandlers:{coach:{postMessage(message){(window.nativeMessages??=[]).push(message);}}}};});
    const folder=resolve(__dirname,'../../../app/KochiApp/Resources/CoachMannequin');
    await page.goto(pathToFileURL(resolve(folder,'index.html')).href);
    await page.waitForFunction(()=>window.kochiCoach?.snapshot().frames>2,{},{timeout:30000});
    const initial=await page.evaluate(()=>window.kochiCoach.snapshot());
    assert.equal(initial.animations.length,35);
    assert.equal(initial.current,'Breathing Idle');
    await page.waitForTimeout(700);
    assert.notEqual((await page.evaluate(()=>window.kochiCoach.snapshot())).time,initial.time);
    await page.evaluate(()=>window.kochiCoach.configure({paused:true}));
    await page.screenshot({path:resolve(folder,'poster.png')});
    await page.evaluate(()=>window.kochiCoach.configure({paused:false}));
    for(const animation of initial.animations){
      await page.evaluate(animation=>window.kochiCoach.receive({animation},{preview:true}),animation);
      await page.waitForTimeout(650);
      const state=await page.evaluate(()=>({snapshot:window.kochiCoach.snapshot(),inspection:window.kochiCoach.inspect()}));
      assert.equal(state.snapshot.current,animation);
      assert.deepEqual(state.snapshot.camera,initial.camera,`${animation}: camera moved`);
      assert.ok(state.inspection.visiblePixels>2000,`${animation}: missing or out of frame`);
      if(animation==='Salute')await page.screenshot({path:'/tmp/kochi-native-salute.png'});
    }
    await page.evaluate(()=>window.kochiCoach.receive({intent:'steady',gesture:'acknowledge'},{preview:true}));
    assert.equal((await page.evaluate(()=>window.kochiCoach.snapshot())).current,'acknowledging');
    await page.waitForFunction(()=>window.kochiCoach.snapshot().current==='Breathing Idle',{},{timeout:5000});
    await page.evaluate(()=>window.kochiCoach.configure({reduceMotion:true}));
    await page.waitForTimeout(100);
    const still=await page.evaluate(()=>window.kochiCoach.snapshot());
    await page.evaluate(()=>window.kochiCoach.receive({intent:'goal',verifiedGoal:true,intensity:1}));
    await page.waitForTimeout(400);
    assert.equal((await page.evaluate(()=>window.kochiCoach.snapshot())).time,still.time);
    assert.equal((await page.evaluate(()=>window.kochiCoach.snapshot())).current,'Breathing Idle');
    await page.setViewportSize({width:400,height:280});
    await page.waitForTimeout(200);
    assert.ok((await page.evaluate(()=>window.kochiCoach.inspect())).visiblePixels>2000,'Reduced Motion resize lost the model');
    assert.deepEqual(errors,[]);assert.deepEqual(external,[]);
    console.log('PASS: offline file loading, all 35 converted clips visible, fixed camera, contextual acknowledgment, return to breathing, Reduced Motion, no network.');
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
