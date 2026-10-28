const { selectReviewRange, checkChartGeometry } = require('./review-test-helpers.cjs');
const {chromium}=require('playwright-core'),assert=require('node:assert/strict'),fs=require('node:fs');
require('./verify-review-data.cjs');
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'chrome'}),errors=[];
 fs.mkdirSync('review-screenshots',{recursive:true});
 for(const width of [393,320])for(const dark of [false,true]){
  const context=await browser.newContext({viewport:{width,height:852},timezoneId:'America/Los_Angeles',reducedMotion:'reduce'}),p=await context.newPage();
  p.on('pageerror',e=>errors.push(e.message));await p.clock.setFixedTime(new Date('2026-10-09T12:00:00Z'));await p.goto(process.env.BASE_URL||'http://127.0.0.1:8766');
  if(dark)await p.evaluate(()=>document.querySelector('#phone').classList.add('dark'));
  const original=await p.evaluate(()=>JSON.stringify(state));
  await p.click('[data-tab="review"]');
  assert.equal(await p.locator('[data-review-mode]').count(),2);
  assert.equal(await p.locator('.review-day,.review-summary,.home-record,.review-cells button,[data-review-date],[data-energy-day]').count(),0);
  assert.equal(await p.locator('.review-heatmap').count(),2);assert.equal(await p.locator('.review-cell').count(),182);
  assert.equal(await p.locator('.review-cell.future').count(),4);
  assert.equal(await p.locator('[data-record-type="meal"][data-record-day="2026-10-09"]').getAttribute('class'),'review-cell recorded');
  assert.equal(await p.locator('[data-record-type="workout"][data-record-day="2026-10-08"]').getAttribute('class'),'review-cell ');
  assert.equal(await p.locator('.review-cell.recorded .review-cell-icon').count(),await p.locator('.review-cell.recorded').count());
  assert.equal(await p.locator('.review-cell:not(.recorded) svg,.review-cell.future svg').count(),0);
  const mealIcon=await p.locator('[data-record-type="meal"].recorded svg path').first().getAttribute('d');
  const workoutIcon=await p.locator('[data-record-type="workout"].recorded svg path').first().getAttribute('d');
  assert.notEqual(mealIcon,workoutIcon);
  assert(await p.locator('.review-cell-icon').evaluateAll(es=>es.every(e=>{const a=e.getBoundingClientRect(),b=e.parentElement.getBoundingClientRect();return a.width>9&&a.width<b.width&&a.height<b.height&&e.getAttribute('aria-hidden')==='true'})));
  assert(await p.locator('[data-review-page="1"]').isDisabled());assert(await p.locator('[data-review-page="-1"]').isDisabled());
  const shot=async name=>{assert(await p.evaluate(()=>{const el=document.querySelector('.review-scroll');return document.documentElement.scrollWidth<=innerWidth&&el.scrollWidth<=el.clientWidth}));await checkChartGeometry(p);await p.screenshot({path:`review-screenshots/${name}-${width}${dark?'-dark':''}.png`})};
  await shot('calendar');
  const targets=await p.locator('.review-scroll button').evaluateAll(es=>es.map(e=>({w:e.getBoundingClientRect().width,h:e.getBoundingClientRect().height})));
  assert(targets.every(t=>t.w>=44&&t.h>=44));
  await p.click('[data-review-mode="热量"]');assert.equal(await p.locator('.review-curve').count(),2);assert.equal(await p.locator('[data-day-count="7"]').count(),2);
  const checkWeek=async()=>{
   for(const key of ['intake','active']){
    assert.equal(await p.locator(`[data-curve="${key}"] .review-x-axis span`).count(),7);
    const geometry=await p.locator(`[data-curve="${key}"]`).evaluate(section=>{
     const labels=[...section.querySelectorAll('.review-x-axis span')],svg=section.querySelector('.review-plot svg'),plot=svg.getBoundingClientRect();
     return labels.map((e,i)=>{const range=document.createRange();range.selectNodeContents(e);const text=range.getBoundingClientRect(),box=e.getBoundingClientRect();return {left:text.left,right:text.right,center:box.x+box.width/2,expected:plot.x+plot.width*(i+.5)/7,plotLeft:plot.left,plotRight:plot.right}});
    });
    geometry.forEach((r,i)=>{assert(Math.abs(r.center-r.expected)<1);assert(r.left>=r.plotLeft-1&&r.right<=r.plotRight+1);if(i)assert(r.left>=geometry[i-1].right)});
   }
  };
  await checkWeek();
  assert.equal(await p.locator('[data-energy-range],[data-review-page]').count(),0);
  await p.click('[data-review-range]');
  assert.equal(await p.inputValue('#review-start'),'2026-10-03');
  assert.equal(await p.inputValue('#review-end'),'2026-10-09');
  const panel=await p.locator('#review-range-panel').boundingBox();
  assert(panel.x>=0&&panel.x+panel.width<=width&&panel.y>=0&&panel.y+panel.height<=852);
  await p.screenshot({path:`review-screenshots/range-panel-${width}${dark?'-dark':''}.png`});
  await p.fill('#review-start','2026-10-01');
  assert.equal(await p.locator('[data-day-count="7"]').count(),2);
  await p.keyboard.press('Escape');await p.locator('#review-range-panel').waitFor({state:'detached'});
  assert(await p.locator('[data-review-range]').evaluate(e=>e===document.activeElement));
  await p.click('[data-review-range]');assert.equal(await p.inputValue('#review-start'),'2026-10-03');
  for(const [start,end,message] of [['','2026-10-09','有效'],['2026-10-09','2026-10-01','起始'],['2026-10-03','2026-10-10','今天'],['2026-07-11','2026-10-09','90']]){
   await p.fill('#review-start',start);await p.fill('#review-end',end);
   assert(await p.locator('[data-review-apply]').isDisabled());
   assert((await p.locator('#review-range-message').innerText()).includes(message));
  }
  await p.click('[data-review-cancel]');await p.locator('#review-range-panel').waitFor({state:'detached'});
  await p.click('[data-review-range]');await p.fill('#review-start','2026-10-01');
  await p.mouse.click(width-8,120);await p.locator('#review-range-panel').waitFor({state:'detached'});
  assert.equal(await p.locator('[data-day-count="7"]').count(),2);
  for(const [start,count,labels] of [['2026-10-09',1,1],['2026-10-08',2,2],['2026-10-04',6,6],['2026-10-02',8,3],['2026-07-12',90,3]]){
   await selectReviewRange(p,start,'2026-10-09');
   assert.equal(await p.locator(`[data-day-count="${count}"]`).count(),2);
   assert.equal(await p.locator('[data-curve="intake"] [data-label-day]').count(),labels);
   await shot(`trend-${count}`);
  }
  await selectReviewRange(p,'2026-10-03','2026-10-09');

  assert.deepEqual(await p.locator('[data-curve="intake"] [data-label-day]').allTextContents(),['10/3','10/4','10/5','10/6','10/7','10/8','10/9']);
  assert.equal(await p.locator('[data-curve="intake"] [data-point-day="2026-10-09"]').getAttribute('data-value'),'1850');
  assert.equal(await p.locator('[data-curve="active"] [data-point-day="2026-10-09"]').getAttribute('data-value'),'184');
  assert.equal(await p.locator('[data-curve="active"] .review-curve-line,[data-curve="active"] circle').count(),0);
  assert.equal(await p.locator('[data-curve="active"] .review-bar').count(),3);
  assert.match(await p.locator('[data-curve="intake"] .review-curve-line').getAttribute('d'),/C/);
  assert(!/\d,\d/.test(await p.locator('.review-scroll').innerText()));await shot('trend');
  await selectReviewRange(p,'2026-09-10','2026-10-09');assert.equal(await p.locator('[data-day-count="30"]').count(),2);
  assert.equal(await p.locator('.review-x-axis span').count(),6);assert.equal(await p.locator('.review-bar').count(),3);await shot('trend-30');
  assert.equal(await p.evaluate(()=>JSON.stringify(state)),original);
  if(width===393&&!dark){
   // Browsing historical periods stays independent of home and of the other review tab.
   await p.evaluate(()=>{state.meals.push({...structuredClone(state.meals[0]),id:'older',date:'2025-12-31',energy:null});render()});
   await selectReviewRange(p,'2026-08-11','2026-09-09');const trendEnd=await p.evaluate(()=>reviewRange().end);assert.equal(trendEnd,'2026-09-09');
   await p.click('[data-review-mode="日历"]');await p.click('[data-review-page="-1"]');
   const period=await p.locator('[data-review-period]').innerText();assert.match(period,/4\/13 — 7\/12/);
   await p.click('[data-review-mode="热量"]');assert.equal(await p.evaluate(()=>reviewRange().end),trendEnd);
   await selectReviewRange(p,'2026-09-03','2026-09-09');assert.equal(await p.evaluate(()=>reviewRange().end),trendEnd);
   await p.click('[data-review-mode="日历"]');assert.equal(await p.locator('[data-review-period]').innerText(),period);
   assert.equal(await p.evaluate(()=>selectedDate),'2026-10-09');
   for(let i=0;i<8&&!(await p.locator('[data-review-page="-1"]').isDisabled());i++)await p.click('[data-review-page="-1"]');
   assert(await p.locator('[data-review-page="-1"]').isDisabled());assert.equal(await p.locator('[data-record-day="2025-12-31"][data-record-type="meal"]').getAttribute('class'),'review-cell recorded');
   // A pending record counts as recorded; only known values enter the curve.
   await p.evaluate(()=>{reviewCalendarOffset=0;reviewOpenTrend();state.meals.push({...structuredClone(state.meals.find(m=>m.date===homeToday)),id:'pending-review',energy:null});render()});
   assert.equal(await p.locator('[data-curve="intake"] h3').innerText(),'已知摄入');assert.equal(await p.locator('[data-curve="intake"] [data-point-day="2026-10-09"]').getAttribute('data-value'),'1850');
   await p.evaluate(()=>{for(const m of state.meals.filter(m=>m.date===homeToday))m.energy=null;for(const w of state.workouts.filter(w=>w.date===homeToday))w.energy=null;render()});
   assert.equal(await p.locator('[data-point-day="2026-10-09"]').count(),0);
   await p.click('[data-review-mode="日历"]');assert.equal(await p.locator('[data-record-day="2026-10-09"].recorded .review-cell-icon').count(),2);
   // In-memory edits/deletions immediately update both views; actual storage remains untouched.
   await p.evaluate(()=>{state.meals=state.meals.filter(m=>m.date!==homeToday);render()});assert.equal(await p.locator('[data-record-day="2026-10-09"].recorded').count(),1);
   await p.evaluate(()=>{state.meals=[{...structuredClone(state.meals[0]),id:'zero',date:homeToday,energy:{status:'manual',source:'manual',kcal:0}}];state.workouts=[];reviewOpenTrend()});
   assert.equal(await p.locator('[data-curve="intake"] [data-point-day]').getAttribute('data-value'),'0');assert.equal(await p.locator('.review-curve-line').count(),0);
   await p.evaluate(()=>{preview='empty';render()});assert.equal(await p.locator('.review-empty').count(),2);
   await p.click('[data-review-mode="日历"]');assert.equal(await p.locator('.review-cell.recorded').count(),0);assert(await p.locator('[data-review-page="-1"]').isDisabled());
   await p.reload();await p.click('[data-tab="review"]');assert.equal(await p.evaluate(()=>JSON.stringify(state)),original);
  }
  // Explicit cross-year fixtures cover consecutive workouts, missing energy and a real zero.
  await p.evaluate(()=>{
   preview='';page='review';reviewMode='热量';reviewAppliedRange={start:'2025-12-28',end:'2026-01-03'};const fixtureEnd=reviewAppliedRange.end;
   const meal=structuredClone(state.meals[0]),workout=structuredClone(state.workouts[0]);
   state.meals=Array.from({length:7},(_,i)=>({...meal,id:'meal-fixture-'+i,date:ReviewData.shift(fixtureEnd,i-6),energy:{status:'manual',source:'manual',kcal:1800+i*50}}));
   state.workouts=[300,0,null,200,400,null,180].map((kcal,i)=>({...workout,id:'workout-fixture-'+i,date:ReviewData.shift(fixtureEnd,i-6),energy:kcal===null?null:{...workout.energy,activeKcal:kcal}}));render();
  });
  await checkWeek();
  assert.deepEqual(await p.locator('[data-curve="active"] [data-label-day]').allTextContents(),['12/28','12/29','12/30','12/31','1/1','1/2','1/3']);
  assert.equal(await p.locator('.review-bar').count(),4);assert.equal(await p.locator('.review-zero').count(),1);
  assert.equal(await p.locator('[data-curve="active"] [data-point-day="2025-12-30"]').count(),0);
  assert.equal(await p.locator('.review-zero').getAttribute('data-value'),'0');
  assert.equal(await p.locator('[data-curve="active"] h3').innerText(),'已知训练消耗');
  assert.equal(await p.locator('[data-curve="active"] .review-curve-line').count(),0);
  await shot('trend-fixture');
  await p.locator('[data-curve="active"]').screenshot({path:`review-screenshots/training-fixture-${width}${dark?'-dark':''}.png`});
  await selectReviewRange(p,'2025-12-05','2026-01-03');assert.equal(await p.locator('.review-bar').count(),4);assert.equal(await p.locator('.review-zero').count(),1);
  await checkChartGeometry(p);
  await selectReviewRange(p,'2025-12-28','2026-01-03');
  await p.evaluate(()=>{
   state.meals[0].energy.kcal=3456;state.meals[2].energy=null;
   for(let i=0;i<12;i++)state.meals.push({...structuredClone(state.meals[0]),id:'wide-'+i,energy:{status:'manual',source:'manual',kcal:10000}});
   render();
  });
  assert.equal(await p.locator('[data-curve="intake"] [data-point-day="2025-12-28"]').getAttribute('data-value'),'123456');
  await shot('trend-wide-values');
  assert.equal(await p.locator('[data-curve="intake"] [data-point-day="2025-12-30"]').count(),0);
  await p.evaluate(()=>{preview='empty';render()});await shot('trend-empty');
  await context.close();
 }
 // Real local clock, historical entry points, midnight and reload behavior.
 for(const zone of ['Asia/Shanghai','America/Los_Angeles']){
  const context=await browser.newContext({viewport:{width:393,height:852},timezoneId:zone}),p=await context.newPage();
  p.on('pageerror',e=>errors.push(e.message));
  await p.goto(process.env.BASE_URL||'http://127.0.0.1:8766');
  assert.equal(await p.evaluate(()=>homeToday),await p.evaluate(()=>currentLocalDay()));
  await p.clock.setFixedTime(new Date('2026-10-25T00:30:00Z'));await p.reload();
  const today=zone==='Asia/Shanghai'?'2026-10-25':'2026-10-24';
  assert.equal(await p.evaluate(()=>homeToday),today);assert.equal(await p.evaluate(()=>selectedDate),today);
  const original=await p.evaluate(()=>JSON.stringify(state));
  await p.locator('[data-home-date="2026-10-23"]').click();await p.locator('.home-energy').click();
  assert.equal(await p.evaluate(()=>reviewRange().end),today);assert.equal(await p.locator('[data-day-count="7"]').count(),2);
  assert.equal(await p.locator('.review-empty').count(),2);
  await selectReviewRange(p,'2026-10-03','2026-10-09');
  await p.clock.setFixedTime(new Date('2026-10-26T12:00:00Z'));await p.evaluate(()=>window.dispatchEvent(new Event('focus')));
  assert.deepEqual(await p.evaluate(()=>reviewRange()),{start:'2026-10-03',end:'2026-10-09'});
  await p.click('[data-tab="today"]');await p.click('[data-tab="review"]');
  assert.equal(await p.evaluate(()=>reviewRange().end),'2026-10-09');
  await p.click('[data-tab="today"]');await p.locator('.home-energy').click();
  assert.deepEqual(await p.evaluate(()=>reviewRange()),{start:'2026-10-20',end:'2026-10-26'});
  await p.clock.setFixedTime(new Date('2026-10-27T12:00:00Z'));await p.evaluate(()=>window.dispatchEvent(new Event('focus')));
  assert.deepEqual(await p.evaluate(()=>reviewRange()),{start:'2026-10-21',end:'2026-10-27'});
  await selectReviewRange(p,'2026-10-01','2026-10-09');await p.reload();await p.locator('.home-energy').click();
  assert.deepEqual(await p.evaluate(()=>reviewRange()),{start:'2026-10-21',end:'2026-10-27'});
  assert.equal(await p.evaluate(()=>JSON.stringify(state)),original);await context.close();
 }
 assert.deepEqual(errors,[]);await browser.close();console.log(JSON.stringify({passed:true,checks:['13-week calendars with distinct recorded-only icons','future blanks and paging bounds','intake curve and 1–90-day training bars','atomic date range apply, cancel, validation and focus; aligned daily labels','cross-year dates, gaps and visible real zero','known-only totals','independent browsing state','record updates and unchanged persistence','320/393 light/dark and 44px controls'],consoleErrors:errors}));
})().catch(e=>{console.error(e);process.exit(1)});
