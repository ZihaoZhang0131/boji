const {chromium}=require('playwright-core');
const assert=require('node:assert/strict');
(async()=>{
 const base=process.env.BASE_URL||'http://127.0.0.1:8765';
 const browser=await chromium.launch({headless:true,channel:'chrome'});
 const errors=[];
 for(const width of [393,320]) {
  const context=await browser.newContext({viewport:{width,height:852},timezoneId:'America/Los_Angeles',reducedMotion:'reduce'});
  const p=await context.newPage();p.on('pageerror',e=>errors.push(e.message));
  await p.goto(base);
  const days=p.locator('[data-home-date]');assert.equal(await days.count(),31);
  assert.equal(await days.first().getAttribute('data-home-date'),'2026-09-24');assert.equal(await days.last().getAttribute('data-home-date'),'2026-10-24');
  const bounds=await p.locator('.home-date.selected').evaluate(el=>{const a=el.getBoundingClientRect(),b=el.parentElement.getBoundingClientRect();return {center:a.x+a.width/2,strip:b.x+b.width/2,width:a.width,height:a.height}});
  assert(Math.abs(bounds.center-bounds.strip)<2);assert(bounds.width>=44&&bounds.height>=44);
  assert.equal(bounds.width,bounds.height);
  assert.equal(await p.locator('.home-date.selected').evaluate(el=>getComputedStyle(el).borderRadius),'50%');
  assert.equal(await p.locator('.home-date.selected').innerText(),'9');
  assert.equal(await p.locator('.home-date-heading').innerText(),'2026年10月9日，周五');
  assert.equal(await p.locator('.home-scroll .page-head, [data-complete]').count(),0);
  assert.equal(await p.locator('.home-date small').count(),0);
  const surfaces=await p.evaluate(()=>['.home-date-strip','.home-energy','.home-record'].map(selector=>getComputedStyle(document.querySelector(selector)).backgroundColor));
  assert.equal(new Set(surfaces).size,3);
  assert.equal((await p.locator('[data-home-intake]').innerText()).replace(/\s/g,''),'1850kcal');
  const stripBox=await p.locator('.home-date-strip').boundingBox();
  const initialLeft=await p.locator('.home-date-strip').evaluate(el=>el.scrollLeft);
  await p.mouse.move(stripBox.x+stripBox.width*.7,stripBox.y+stripBox.height/2);await p.mouse.down();
  await p.mouse.move(stripBox.x+stripBox.width*.3,stripBox.y+stripBox.height/2,{steps:8});await p.mouse.up();
  assert((await p.locator('.home-date-strip').evaluate(el=>el.scrollLeft))>initialLeft+30);
  assert.equal(await p.locator('.home-date.selected').getAttribute('data-home-date'),'2026-10-09');
  await p.locator('.home-date-strip').evaluate((el,left)=>el.scrollLeft=left,initialLeft);

  const offset=await p.locator('.home-date-strip').evaluate(el=>el.scrollLeft);
  await p.click('[data-home-date="2026-10-08"]');
  assert.equal(await p.locator('.home-date-strip').evaluate(el=>el.scrollLeft),offset);
  assert.equal(await p.locator('.home-date.selected').getAttribute('data-home-date'),'2026-10-08');
  assert.equal(await p.locator('.home-record').count(),3);
  await days.first().click();assert.equal(await p.locator('.home-date-heading').innerText(),'2026年9月24日，周四');
  assert.equal((await p.locator('[data-home-intake]').innerText()).replace(/\s/g,''),'—kcal');
  await p.click('[data-home-date="2026-10-09"]');
  await p.locator('.home-energy').click();assert.equal(await p.locator('[data-review-mode="热量"]').getAttribute('class'),'active');
  await p.click('[data-review-mode="日历"]');
  assert.equal(await p.locator('.review-heatmap').count(),2);assert.equal(await p.locator('.home-record,.record-card').count(),0);
  await p.click('[data-tab="today"]');
  assert.deepEqual(await p.evaluate(()=>({
   dst:homeDays('2026-03-08'),leap:homeDays('2024-02-29'),
   categories:[homeMealCategory('下午茶'),homeMealCategory(null),homeWorkoutRegion({name:'核心训练',exercises:[{name:'深蹲'}]}),homeWorkoutRegion({name:'混合力量',exercises:[{name:'卧推'},{name:'深蹲'}]}),homeWorkoutRegion({name:'腿部',exercises:[]}),homeWorkoutRegion({name:'自由训练',exercises:[]}),homeWorkoutRegion({name:'Leg press',exercises:[]}),homeWorkoutRegion({name:'Tomorrow session',exercises:[]}),homeWorkoutRegion({name:'Hardcore session',exercises:[]})]
  })).then(v=>({count:new Set(v.dst).size,start:v.dst[0],end:v.dst[30],leap:v.leap[15],categories:v.categories})),{count:31,start:'2026-02-21',end:'2026-03-23',leap:'2024-02-29',categories:['加餐','饮食','core','full-body','lower-body','dumbbell','lower-body','dumbbell','dumbbell']});
  // Discarding edits keeps saved calories and restores the original form values.
  const totals=await p.evaluate(()=>dayEnergy(selectedDate));
  const savedRow=await p.locator('.home-record[data-view-workout]').innerText();
  await p.click('[data-view-workout]');const savedMinutes=await p.locator('#workout-duration').inputValue();await p.fill('#workout-duration','90');await p.click('#close-sheet');
  assert.equal(await p.locator('.home-record[data-view-workout]').innerText(),savedRow);
  assert.equal(await p.evaluate(()=>dayEnergy(selectedDate).active),totals.active);
  await p.click('[data-home-date="2026-10-08"]');await p.click('[data-home-date="2026-10-09"]');await p.reload();
  assert.equal(await p.locator('.home-record[data-view-workout]').innerText(),savedRow);
  await p.click('[data-view-workout]');assert.equal(await p.locator('#workout-duration').inputValue(),savedMinutes);await p.click('#close-sheet');
  await p.evaluate(()=>{selectedDate='2025-01-01';render()});assert.equal(await p.locator('.home-date.selected').getAttribute('data-home-date'),'2026-10-09');
  // Screenshots use untouched fixtures, and cover the actual light/dark home.
  await p.evaluate(()=>localStorage.removeItem('shilian.design.v1'));await p.reload();
  await p.screenshot({path:`home-list-${width}.png`});
  await p.evaluate(()=>document.querySelector('#phone').classList.add('dark'));
  await p.screenshot({path:`home-list-dark-${width}.png`});
  assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth&&document.querySelector('.home-scroll').scrollWidth<=document.querySelector('.home-scroll').clientWidth));
  await context.close();
 }
 assert.deepEqual(errors,[]);await browser.close();console.log(JSON.stringify({passed:true,checks:['31-day local calendar across DST and leap day','centered date and stable scroll after selection','date-driven records and totals','home and review record rows','classification and unknown fallbacks','discarded edits leave saved records and totals unchanged','393/320px light and dark'],consoleErrors:errors},null,2));
})().catch(e=>{console.error(e);process.exit(1)});
