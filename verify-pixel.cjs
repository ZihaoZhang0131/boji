const {chromium}=require('playwright-core');
const assert=require('node:assert/strict');
(async()=>{
 const base=process.env.BASE_URL||'http://127.0.0.1:8765';
 const browser=await chromium.launch({headless:true,channel:'chrome'});
 const errors=[];
 for(const width of [393,320]){
  const context=await browser.newContext({viewport:{width,height:852},reducedMotion:'reduce'});
  const p=await context.newPage();p.on('pageerror',e=>errors.push(e.message));
  await p.goto(`${base}/?v=0.6`);await p.evaluate(()=>document.fonts.ready);
  const fonts=await p.evaluate(()=>({loaded:document.fonts.check('12px "Fusion Pixel"','薄记饮食训练0123456789'),families:['h2','.record-data','.energy-number','.primary'].map(s=>getComputedStyle(document.querySelector(s)).fontFamily)}));
  assert(fonts.loaded);assert(fonts.families.every(f=>f.includes('Fusion Pixel')));
  assert.equal(await p.locator('.food-img.pixel-art').count(),0);
  assert.equal(await p.evaluate(()=>state.meals[0].photos[0]),'assets/meal-yogurt-real.jpg');
  assert.equal(await p.locator('.tabbar .pixel-icon').count(),3);
  const fits=()=>p.evaluate(()=>{const e=document.querySelector('.sheet-body')||document.querySelector('#app .scroll');return document.documentElement.scrollWidth<=innerWidth&&e.scrollWidth<=e.clientWidth});
  const cards=await p.locator('.record-card').evaluateAll(els=>els.map(el=>({width:el.getBoundingClientRect().width,height:el.getBoundingClientRect().height,x:el.getBoundingClientRect().x,y:el.getBoundingClientRect().y})));
  assert.equal(cards.length,4);assert(cards.every(c=>Math.abs(c.width-cards[0].width)<1&&Math.abs(c.height-cards[0].height)<1));assert(Math.abs(cards[0].height/cards[0].width-1)<.01);assert.equal(cards[0].y,cards[1].y);assert(cards[1].x>cards[0].x);
  assert.equal(await p.locator('.feed .entry-heading,.feed time,.record-card h3,.record-card p').count(),0);
  assert.equal(await p.locator('[data-workout-symbol="upper-body"] .pixel-icon').count(),1);
  assert(!/运动净消耗|分钟|上肢力量|AI 估算|示例|个动作|组/.test((await p.locator('.record-card').allTextContents()).join('')));
  assert(await fits());await p.screenshot({path:`pixel-today-${width}.png`});
  await p.click('[data-tab="review"]');await p.click('#toggle-energy-sample');assert(await fits());
  assert.equal(await p.locator('.energy-chart circle').count(),0);
  await p.screenshot({path:`pixel-review-${width}.png`});
  await p.click('[data-energy-range="30"]');assert.equal(await p.locator('#energy-day-picker option').count(),30);assert(await fits());await p.screenshot({path:`pixel-month-${width}.png`});
  await p.click('[data-tab="library"]');await p.click('[data-profile]');await p.click('#profile-example');await p.click('#save-profile');
  await p.click('[data-tab="today"]');await p.click('[data-new-meal]');await p.click('#demo-recognize');await p.locator('#adjust-energy').waitFor();
  await p.evaluate(()=>{clearTimeout(toastTimer);document.querySelector('#toast').classList.remove('show')});assert(await fits());await p.screenshot({path:`pixel-meal-${width}.png`});
  await p.click('#close-sheet');await p.click('[data-new-workout]');await p.click('#copy-workout');await p.fill('#workout-duration','45');await p.click('[data-done="0,0"]');
  assert(await fits());assert.equal(await p.locator('[data-done="0,0"] .pixel-icon').count(),1);await p.screenshot({path:`pixel-workout-${width}.png`});
  await p.click('#close-sheet');await p.click('[data-new-meal]');await p.setInputFiles('#photo-file','assets/breakfast.jpg');await p.locator('.photo-thumb img').waitFor();
  assert(!(await p.locator('.photo-thumb img').getAttribute('class')||'').includes('pixel-art'));
  assert((await p.locator('.photo-thumb img').getAttribute('src')).startsWith('data:image/'));
  await context.close();
 }
 assert.deepEqual(errors,[]);console.log(JSON.stringify({passed:true,checks:['pixel Chinese, Latin, numeric and control fonts loaded','original pixel icons','fixture-only image mapping','stored photo references unchanged','7/30-day charts','393/320px fit','pixel checkboxes','real uploaded photos not transformed'],consoleErrors:errors},null,2));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
