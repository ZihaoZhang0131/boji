const {chromium}=require('playwright-core');
const assert=require('node:assert/strict');
const fs=require('node:fs');
(async()=>{
 const base=process.env.BASE_URL||'http://127.0.0.1:8765';
 const browser=await chromium.launch({headless:true,channel:'chrome'});
 const context=await browser.newContext({viewport:{width:1440,height:1020},reducedMotion:'reduce'});
 const p=await context.newPage(),errors=[],external=[];
 p.on('pageerror',e=>errors.push(e.message));p.on('request',r=>{if(!r.url().startsWith(base)&&!r.url().startsWith('data:'))external.push(r.url())});
 await p.goto(`${base}/?v=0.5`);
 assert.deepEqual(await p.evaluate(()=>({age:state.profile.age,height:state.profile.height,weight:state.profile.weight,demo:state.profile.demo})),{age:29,height:176,weight:72.4,demo:true});
 assert.equal(await p.evaluate(()=>dayEnergy(selectedDate).intake),1850);
 assert.equal(await p.evaluate(()=>dayEnergy(selectedDate).balance),null);
 await p.click('[data-scene="profile"]');await p.fill('#profile-age','10');await p.click('#save-profile');assert.match(await p.locator('#profile-error').innerText(),/有效信息/);
 await p.click('#profile-example');assert.match(await p.locator('#profile-result').innerText(),/1,659/);
 await p.click('#save-profile');assert.equal(await p.evaluate(()=>dayEnergy(selectedDate).base),1991);
 assert.equal(await p.evaluate(()=>dayEnergy('2026-10-08').bmr),1684);
 await p.reload();assert.equal(await p.evaluate(()=>state.profile.weight),70);
 // A reference workout is not a completed one, nor does its tonnage imply kcal.
 await p.click('[data-scene="workout"]');await p.click('#copy-workout');
 assert.match(await p.locator('#workout-kcal').innerText(),/—/);
 await p.fill('#workout-duration','45');assert.match(await p.locator('#workout-kcal').innerText(),/138/);
 assert.equal(await p.evaluate(()=>state.workouts.length),3);
 await p.fill('#workout-duration','999');assert.match(await p.locator('#workout-kcal').innerText(),/—/);await p.fill('#workout-duration','45');
 await p.click('[data-done="0,0"]');await p.click('#finish-workout');
 assert.equal(await p.evaluate(()=>state.workouts.at(-1).energy.activeKcal),138);
 assert.equal(await p.evaluate(()=>dayEnergy(selectedDate).active),322);
 assert.equal(await p.evaluate(()=>dayEnergy(selectedDate).burn),2313);
 await p.click('[data-scene="workout"]');await p.click('#copy-workout');assert.equal(await p.locator('#workout-duration').inputValue(),'');
 assert.equal(await p.evaluate(()=>countSets(currentWorkout)),0);await p.click('#close-sheet');
 // Simulated recognition states; there are no real API requests.
 await p.click('[data-ai-demo="failed"]');await p.locator('#meal-energy').getByText('这次没有识别出来').waitFor();
 await p.click('#demo-recognize');await p.locator('#adjust-energy').waitFor();
 await p.click('#adjust-energy');await p.fill('[data-food-grams="1"]','150');
 assert.match(await p.locator('#adjusted-total').innerText(),/503/);
 await p.click('#save-energy-adjustment');await p.click('#save-meal');
 assert.equal(await p.evaluate(()=>state.meals.at(-1).energy.kcal),503);
 assert.equal(await p.evaluate(()=>state.meals.at(-1).energy.source),'manual');
 assert.equal(await p.evaluate(()=>dayEnergy(selectedDate).intake),2353);
 assert.equal(await p.evaluate(()=>dayEnergy(selectedDate).balance),null);
 await p.click('[data-complete]');assert.equal(await p.evaluate(()=>dayEnergy(selectedDate).balance),40);
 // Editing an analysed record invalidates its estimate until explicitly corrected.
 const mealId=await p.evaluate(()=>state.meals.at(-1).id);
 await p.click(`[data-meal="${mealId}"]`);await p.click('#edit-meal');await p.fill('#meal-note','只吃了一半');
 assert.match(await p.locator('#meal-energy').innerText(),/重新估算/);await p.click('#save-meal');
 assert.equal(await p.evaluate(()=>dayEnergy(selectedDate).unknown),1);assert.equal(await p.evaluate(()=>dayEnergy(selectedDate).balance),null);
 // Real uploads are never given fabricated model estimates.
 await p.click('[data-scene="meal"]');await p.setInputFiles('#photo-file','assets/breakfast.jpg');await p.locator('.photo-thumb').waitFor();
 assert.match(await p.locator('#meal-energy').innerText(),/待连接模型/);assert.equal(await p.evaluate(()=>mealKcal(mealDraft)),null);await p.click('#close-sheet');
 await p.click('[data-scene="review"]');assert.equal(await p.locator('.energy-chart').count(),2);
 await p.click('#toggle-energy-sample');const recordsBefore=await p.evaluate(()=>state.meals.length);
 await p.click('[data-energy-range="30"]');assert.equal(await p.locator('#energy-day-picker option').count(),30);
 await p.selectOption('#energy-day-picker','2026-10-01');assert.match(await p.locator('.chart-selected').innerText(),/10 月 1 日/);
 await p.click('#toggle-energy-sample');assert.equal(await p.evaluate(()=>state.meals.length),recordsBefore);
 await p.click('[data-energy-range="7"]');await p.click('[data-energy-day="2026-10-08"]');
 assert.match(await p.locator('.chart-selected').innerText(),/差值 -213/);
 // Persisted profile changes must not re-price completed workout snapshots.
 await p.click('[data-scene="profile"]');await p.fill('#profile-weight','80');await p.click('#save-profile');
 assert.equal(await p.evaluate(()=>state.workouts.at(-1).energy.activeKcal),138);
 await p.click('[data-scene="library"]');await p.click('[data-export-open]');
 const downloading=p.waitForEvent('download');await p.click('#download-json');const dl=await downloading;
 const payload=JSON.parse(fs.readFileSync(await dl.path(),'utf8'));
 assert.equal(payload.profile.weight,80);assert(payload.workouts.some(w=>w.energy?.method==='MET-net-v1'));assert(payload.meals.some(m=>m.energy?.source==='manual'));
 assert(!JSON.stringify(payload).includes('api_key'));
 for(const width of [393,320]){
  await p.setViewportSize({width,height:852});
  await p.evaluate(()=>{state.draft=null;persist();page='today';render()});
  await p.evaluate(()=>{clearTimeout(toastTimer);document.querySelector('#toast').classList.remove('show')});
  assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await p.click('[data-tab="review"]');await p.click('[data-review-mode="热量"]');
  assert(await p.evaluate(()=>document.querySelector('#app .scroll').scrollWidth<=document.querySelector('#app .scroll').clientWidth));
  await p.screenshot({path:`energy-review-${width}.png`});
  await p.click('[data-tab="library"]');await p.click('[data-profile]');
  assert(await p.evaluate(()=>document.querySelector('.sheet-body').scrollWidth<=document.querySelector('.sheet-body').clientWidth));
  await p.screenshot({path:`energy-profile-${width}.png`});await p.click('#close-sheet');
 }
 assert.deepEqual(errors,[]);assert.deepEqual(external,[]);
 console.log(JSON.stringify({passed:true,checks:['profile validation and REE calculation','local persistence','historical profile baseline','MET net energy and duration bounds','drafts excluded','copied workout clears duration','AI failure and retry simulation','portion correction and totals','incomplete data excludes balance','input change invalidates estimate','real photos do not get fake estimates','7/30 day charts and per-day selection','sample charts do not mutate records','workout bodyweight snapshot','export preserves provenance','393/320px layouts','no external network requests'],consoleErrors:errors},null,2));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
