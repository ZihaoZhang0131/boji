const {chromium}=require('playwright-core'),assert=require('node:assert/strict'),fs=require('node:fs');
require('./verify-review-data.cjs');
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'chrome'}),errors=[];
 fs.mkdirSync('review-screenshots',{recursive:true});
 for(const width of [393,320])for(const dark of [false,true]){
  const context=await browser.newContext({viewport:{width,height:852},timezoneId:'America/Los_Angeles',reducedMotion:'reduce'}),p=await context.newPage();
  p.on('pageerror',e=>errors.push(e.message));await p.goto(process.env.BASE_URL||'http://127.0.0.1:8766');
  if(dark)await p.evaluate(()=>document.querySelector('#phone').classList.add('dark'));
  const original=await p.evaluate(()=>JSON.stringify(state));
  await p.click('[data-tab="review"]');
  assert.equal(await p.locator('[data-review-mode]').count(),2);
  assert.equal(await p.locator('.review-day,.review-summary,.home-record,.review-cells button,[data-review-date],[data-energy-day]').count(),0);
  assert.equal(await p.locator('.review-heatmap').count(),2);assert.equal(await p.locator('.review-cell').count(),182);
  assert.equal(await p.locator('.review-cell.future').count(),4);
  assert.equal(await p.locator('[data-record-type="meal"][data-record-day="2026-10-09"]').getAttribute('class'),'review-cell recorded');
  assert.equal(await p.locator('[data-record-type="workout"][data-record-day="2026-10-08"]').getAttribute('class'),'review-cell ');
  assert(await p.locator('[data-review-page="1"]').isDisabled());assert(await p.locator('[data-review-page="-1"]').isDisabled());
  const shot=async name=>{assert(await p.evaluate(()=>{const el=document.querySelector('.review-scroll');return document.documentElement.scrollWidth<=innerWidth&&el.scrollWidth<=el.clientWidth}));await p.screenshot({path:`review-screenshots/${name}-${width}${dark?'-dark':''}.png`})};
  await shot('calendar');
  const targets=await p.locator('.review-scroll button').evaluateAll(es=>es.map(e=>({w:e.getBoundingClientRect().width,h:e.getBoundingClientRect().height})));
  assert(targets.every(t=>t.w>=44&&t.h>=44));
  await p.click('[data-review-mode="热量"]');assert.equal(await p.locator('.review-curve').count(),2);assert.equal(await p.locator('[data-day-count="7"]').count(),2);
  assert.equal(await p.locator('[data-curve="intake"] [data-point-day="2026-10-09"]').getAttribute('data-value'),'1850');
  assert.equal(await p.locator('[data-curve="active"] [data-point-day="2026-10-09"]').getAttribute('data-value'),'184');
  assert.equal(await p.locator('[data-curve="active"] .review-curve-line').count(),0); // Rest/unlogged days split all three workouts.
  assert.match(await p.locator('[data-curve="intake"] .review-curve-line').getAttribute('d'),/C/);
  assert(!/\d,\d/.test(await p.locator('.review-scroll').innerText()));await shot('trend');
  await p.click('[data-energy-range="30"]');assert.equal(await p.locator('[data-day-count="30"]').count(),2);await shot('trend-30');
  assert.equal(await p.evaluate(()=>JSON.stringify(state)),original);
  if(width===393&&!dark){
   // Browsing historical periods stays independent of home and of the other review tab.
   await p.evaluate(()=>{state.meals.push({...structuredClone(state.meals[0]),id:'older',date:'2025-12-31',energy:null});render()});
   await p.click('[data-review-page="-1"]');const trendEnd=await p.evaluate(()=>reviewTrendEnd);assert.equal(trendEnd,'2026-09-09');
   await p.click('[data-review-mode="日历"]');await p.click('[data-review-page="-1"]');
   const period=await p.locator('[data-review-period]').innerText();assert.match(period,/4\/13 — 7\/12/);
   await p.click('[data-review-mode="热量"]');assert.equal(await p.evaluate(()=>reviewTrendEnd),trendEnd);
   await p.click('[data-energy-range="7"]');assert.equal(await p.evaluate(()=>reviewTrendEnd),trendEnd);
   await p.click('[data-review-mode="日历"]');assert.equal(await p.locator('[data-review-period]').innerText(),period);
   assert.equal(await p.evaluate(()=>selectedDate),'2026-10-09');
   for(let i=0;i<8&&!(await p.locator('[data-review-page="-1"]').isDisabled());i++)await p.click('[data-review-page="-1"]');
   assert(await p.locator('[data-review-page="-1"]').isDisabled());assert.equal(await p.locator('[data-record-day="2025-12-31"][data-record-type="meal"]').getAttribute('class'),'review-cell recorded');
   // A pending record counts as recorded; only known values enter the curve.
   await p.evaluate(()=>{reviewCalendarOffset=0;reviewOpenTrend();state.meals.push({...structuredClone(state.meals.find(m=>m.date===homeToday)),id:'pending-review',energy:null});render()});
   assert.equal(await p.locator('[data-curve="intake"] h3').innerText(),'已知摄入');assert.equal(await p.locator('[data-curve="intake"] [data-point-day="2026-10-09"]').getAttribute('data-value'),'1850');
   await p.evaluate(()=>{for(const m of state.meals.filter(m=>m.date===homeToday))m.energy=null;for(const w of state.workouts.filter(w=>w.date===homeToday))w.energy=null;render()});
   assert.equal(await p.locator('[data-point-day="2026-10-09"]').count(),0);
   await p.click('[data-review-mode="日历"]');assert.equal(await p.locator('[data-record-day="2026-10-09"].recorded').count(),2);
   // In-memory edits/deletions immediately update both views; actual storage remains untouched.
   await p.evaluate(()=>{state.meals=state.meals.filter(m=>m.date!==homeToday);render()});assert.equal(await p.locator('[data-record-day="2026-10-09"].recorded').count(),1);
   await p.evaluate(()=>{state.meals=[{...structuredClone(state.meals[0]),id:'zero',date:homeToday,energy:{status:'manual',source:'manual',kcal:0}}];state.workouts=[];reviewOpenTrend()});
   assert.equal(await p.locator('[data-curve="intake"] [data-point-day]').getAttribute('data-value'),'0');assert.equal(await p.locator('.review-curve-line').count(),0);
   await p.evaluate(()=>{preview='empty';render()});assert.equal(await p.locator('.review-empty').count(),2);
   await p.click('[data-review-mode="日历"]');assert.equal(await p.locator('.review-cell.recorded').count(),0);assert(await p.locator('[data-review-page="-1"]').isDisabled());
   await p.reload();await p.click('[data-tab="review"]');assert.equal(await p.evaluate(()=>JSON.stringify(state)),original);
  }
  await context.close();
 }
 assert.deepEqual(errors,[]);await browser.close();console.log(JSON.stringify({passed:true,checks:['13-week calendars and independent presence','future blanks and paging bounds','7/30-day curves','missing days split curves; real zero retained','known-only totals','independent browsing state','record updates and unchanged persistence','320/393 light/dark and 44px controls'],consoleErrors:errors}));
})().catch(e=>{console.error(e);process.exit(1)});
