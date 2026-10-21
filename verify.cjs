const {chromium}=require('playwright-core');
const fs=require('fs');
const assert=require('assert');
(async()=>{
 const base=process.env.BASE_URL||'http://127.0.0.1:8765';
 const browser=await chromium.launch({headless:true,channel:'chrome'});
 const context=await browser.newContext({viewport:{width:1440,height:1020},deviceScaleFactor:1,reducedMotion:'reduce'});
 const page=await context.newPage(); const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(base);await page.locator('.food-img').first().waitFor();await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode().catch(()=>{}))));
 await page.screenshot({path:'overview.png',fullPage:true});await page.locator('#phone').screenshot({path:'today.png'});
 await page.click('[data-scene="meal"]');await page.locator('.sheet').waitFor();await page.locator('#phone').screenshot({path:'meal.png'});
 await page.click('#save-meal');await page.locator('#meal-error').filter({hasText:'加一张照片'}).waitFor();
 await page.fill('#meal-note','下午一杯拿铁，少糖');
 assert.equal(await page.locator('.meal-details').getAttribute('open'),null);
 await page.click('.meal-details summary');await page.fill('#meal-time','');await page.click('.meal-details summary');await page.click('#save-meal');assert.notEqual(await page.locator('.meal-details').getAttribute('open'),null);assert.equal(await page.locator('#meal-error').innerText(),'请选择进食时间。');await page.fill('#meal-time','2026-10-09T17:55');await page.click('[data-slot="饮品"]');
 await page.click('#save-meal');await page.getByRole('button',{name:'查看饮食：下午一杯拿铁，少糖',exact:true}).waitFor();
 assert.equal(await page.evaluate(()=>JSON.parse(localStorage.getItem('shilian.design.v1')).meals.at(-1).time),'17:55');
 await page.reload();assert(await page.getByRole('button',{name:'查看饮食：下午一杯拿铁，少糖',exact:true}).count());
 await page.getByRole('button',{name:'查看饮食：下午一杯拿铁，少糖',exact:true}).click();await page.click('#edit-meal');await page.fill('#meal-note','下午一杯拿铁，无糖');await page.click('#save-meal');await page.getByRole('button',{name:'查看饮食：下午一杯拿铁，无糖',exact:true}).click();await page.click('#delete-meal');await page.click('#undo-delete');assert(await page.getByRole('button',{name:'查看饮食：下午一杯拿铁，无糖',exact:true}).count());
 await page.click('[data-scene="meal"]');await page.setInputFiles('#photo-file','assets/breakfast.jpg');await page.waitForFunction(()=>document.querySelectorAll('.photo-thumb').length===1);await page.click('#save-meal');
 await page.click('[data-scene="workout"]');await page.click('#copy-workout');assert.equal(await page.locator('[data-done][aria-pressed="true"]').count(),0);
 await page.click('[data-done="0,0"]');await page.fill('[data-set="0,1,reps"]','7');await page.click('[data-done="0,1"]');await page.click('#close-sheet');await page.reload();assert.equal(await page.locator('.continue-row').count(),0);const draftId=await page.evaluate(()=>state.draft.id);await page.click(`[data-view-workout="${draftId}"]`);assert.equal(await page.locator('#done-count').innerText(),'2');await page.click('#finish-workout');
 assert.equal(await page.evaluate(()=>JSON.parse(localStorage.getItem('shilian.design.v1')).workouts.at(-1).exercises[0].sets.filter(s=>s.done).length),2);
 // A saved card opens the editor directly and updates the same record.
 const savedId=await page.evaluate(()=>state.workouts.at(-1).id),workoutCount=await page.evaluate(()=>state.workouts.length);
 await page.click(`[data-view-workout="${savedId}"]`);assert.equal(await page.locator('#sheet-title').innerText(),'编辑训练');
 await page.fill('[data-set="0,0,reps"]','9');await page.click('[data-add-set="0"]');await page.click('[data-done="0,2"]');
 await page.click('#add-exercise');await page.locator('[data-exercise]').first().click();await page.click('[data-done="1,0"]');
 await page.click('#close-sheet');await page.reload();assert.equal(await page.locator(`[data-view-workout="${savedId}"]`).count(),1);
 await page.click(`[data-view-workout="${savedId}"]`);assert.equal(await page.locator('[data-set="0,0,reps"]').inputValue(),'9');await page.click('#finish-workout');
 assert.equal(await page.evaluate(()=>state.workouts.length),workoutCount);
 assert.equal(await page.evaluate(id=>countSets(state.workouts.find(w=>w.id===id)),savedId),4);
 assert.equal(await page.evaluate(id=>state.workouts.find(w=>w.id===id).exercises.length,savedId),2);
 await page.click('[data-scene="workout"]');await page.click('#quick-workout');await page.fill('#batch-sets','4');await page.click('#save-batch');assert.equal(await page.locator('#done-count').innerText(),'4');await page.click('#finish-workout');
 await page.click('[data-scene="review"]');await page.click('[data-review-mode="照片"]');await page.fill('#search','绝无匹配字样');await page.getByText('没有找到匹配的记录。').waitFor();await page.fill('#search','');
 await page.click('[data-scene="library"]');await page.click('[data-open-plan]');await page.click('[data-goal="稳步增肌"]');await page.click('#save-plan');assert.equal(await page.evaluate(()=>JSON.parse(localStorage.getItem('shilian.design.v1')).planHistory.length),1);
 await page.click('[data-export-open]');const dlPromise=page.waitForEvent('download');await page.click('#download-json');const dl=await dlPromise;const payload=JSON.parse(fs.readFileSync(await dl.path(),'utf8'));assert(payload.prototype);assert(payload.meals.some(m=>m.photos.some(p=>p.startsWith('data:image/'))));assert.equal(payload.workouts.length,5);
 await page.evaluate(()=>localStorage.removeItem('shilian.design.v1'));await page.reload();
 await page.click('[data-scene="workout"]');await page.click('#copy-workout');await page.locator('#phone').screenshot({path:'workout.png'});await page.click('#close-sheet');await page.evaluate(()=>localStorage.removeItem('shilian.design.v1'));await page.reload();
 for(const scene of ['review','library']){await page.click(`[data-scene="${scene}"]`);await page.locator('#phone').screenshot({path:`${scene}.png`})}
 await page.click('[data-scene="today"]');await page.click('[data-theme="dark"]');await page.locator('#phone').screenshot({path:'dark.png'});await page.click('[data-theme="light"]');await page.click('[data-state="empty"]');await page.locator('#phone').screenshot({path:'empty.png'});await page.click('[data-state="offline"]');await page.locator('#phone').screenshot({path:'offline.png'});await page.click('[data-state="normal"]');
 for(const width of [393,320]){await page.setViewportSize({width,height:852});await page.reload();assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:`mobile-${width}.png`});await page.click('[data-new-meal]');await page.fill('#meal-note','窄屏测试');assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.click('#close-sheet');await page.click('[data-new-workout]');await page.click('#copy-workout');assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:`training-${width}.png`});await page.click('#close-sheet');await page.evaluate(()=>localStorage.removeItem('shilian.design.v1'))}
 await page.setViewportSize({width:1440,height:1020});await page.goto(`${base}/design-spec.html`);assert.equal(await page.locator('img').evaluateAll(els=>els.filter(i=>!i.complete||i.naturalWidth===0).length),0);
 assert.deepEqual(errors,[]);console.log(JSON.stringify({passed:true,checks:['text creation and persistence','collapsed metadata expands and saves time/category','validation','edit/delete/undo','photo upload','training reference groups','draft recovery','completed-only statistics','batch entry','search empty state','goal history','download embeds photos','393px and 320px layouts','spec screenshots'],screenshots:12,consoleErrors:errors},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
