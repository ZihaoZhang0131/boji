const {chromium}=require('playwright-core');
const assert=require('node:assert/strict');
const fs=require('node:fs');
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'chrome'}),errors=[];
 const base=process.env.BASE_URL||'http://127.0.0.1:8766';
 fs.mkdirSync('editor-screenshots',{recursive:true});
 for(const width of [393,320])for(const dark of [false,true]){
  const context=await browser.newContext({viewport:{width,height:852},reducedMotion:'reduce'}),p=await context.newPage();p.on('pageerror',e=>errors.push(e.message));
  await p.goto(base);if(dark)await p.evaluate(()=>document.querySelector('#phone').classList.add('dark'));
  const shot=async name=>{
   await p.evaluate(()=>{clearTimeout(toastTimer);document.querySelector('#toast').classList.remove('show');document.activeElement.blur()});
   assert(await p.evaluate(()=>{const body=document.querySelector('.sheet-body');return body.scrollWidth<=body.clientWidth&&document.documentElement.scrollWidth<=innerWidth}));
   const editingMeal=await p.locator('.meal-editor.is-editing').count();
   assert.equal(await p.locator('#close-sheet').innerText(),editingMeal?'返回':'放弃');
   assert.deepEqual(await p.locator('.sheet-foot button').allTextContents(),editingMeal?['保存','删除','返回']:['保存']);
   if(editingMeal){
    assert.equal(await p.locator('.sheet-head button').count(),0);
    const rects=await p.locator('.sheet-foot button').evaluateAll(es=>es.map(e=>{const r=e.getBoundingClientRect();return {y:r.y,w:r.width,h:r.height}}));
    assert(rects.every(r=>r.y===rects[0].y&&Math.abs(r.w-rects[0].w)<1&&r.h>=44));
   }
   assert.equal(await p.locator('.record-editor details,.workout-progress,#batch-entry,[data-tag],#demo-recognize').count(),0);
   const save=await p.locator('.sheet-foot button').first().boundingBox();assert(save.height>=44&&save.y+save.height<=852);
   await p.screenshot({path:`editor-screenshots/${name}-${width}${dark?'-dark':''}.png`});
  };
  await p.click('[data-new-meal]');await p.fill('#meal-note','米饭、鸡肉和蔬菜');await p.setInputFiles('#photo-file','assets/breakfast.jpg');await p.locator('.photo-thumb img').waitFor();await p.click('[data-slot="午餐"]');
  await shot('new-meal');await p.click('#save-meal');
  const mealId=await p.evaluate(()=>state.meals.at(-1).id);
  await p.click(`[data-meal="${mealId}"]`);await shot('edit-meal');
  assert.equal(await p.locator('#sheet-title').innerText(),'编辑饮食');
  assert.equal(await p.locator('#edit-meal').count(),0);
  await p.fill('#meal-note','这段修改会放弃');await p.keyboard.press('Escape');
  assert.equal(await p.evaluate(()=>document.activeElement.dataset.meal),mealId);
  assert.equal(await p.evaluate(id=>state.meals.find(m=>m.id===id).note,mealId),'米饭、鸡肉和蔬菜');
  const original=await p.evaluate(id=>JSON.stringify(state.meals.find(m=>m.id===id)),mealId);
  await p.click(`[data-meal="${mealId}"]`);await p.fill('#meal-note','删除前未保存的输入');await p.click('[data-remove-photo]');
  await p.evaluate(()=>{window.realPersist=persist;persist=()=>false});await p.click('#delete-meal');
  assert.match(await p.locator('#meal-error').innerText(),/删除失败/);
  assert.equal(await p.locator('#meal-note').inputValue(),'删除前未保存的输入');
  assert.equal(await p.evaluate(id=>JSON.stringify(state.meals.find(m=>m.id===id)),mealId),original);
  await p.evaluate(()=>persist=window.realPersist);await p.click('#delete-meal');await p.click('#undo-delete');
  assert.equal(await p.evaluate(id=>JSON.stringify(state.meals.find(m=>m.id===id)),mealId),original);

  await p.click('[data-new-workout]');await p.fill('#workout-name','上肢训练');await p.click('#add-exercise');await p.click('[data-exercise="杠铃卧推"]');
  await p.fill('[data-set="0,0,weight"]','50');await p.fill('[data-set="0,0,reps"]','8');await p.click('[data-add-set="0"]');await p.click('[data-add-set="0"]');await p.fill('#workout-duration','45');
  await shot('new-workout');await p.click('#save-workout');const workoutId=await p.evaluate(()=>state.workouts.at(-1).id);
  await p.click(`[data-view-workout="${workoutId}"]`);await shot('edit-workout');
  await p.fill('#workout-duration','50');await p.click('#close-sheet');assert.equal(await p.evaluate(id=>state.workouts.find(w=>w.id===id).duration,workoutId),45);
  await p.click('[data-view-workout="w1009"]');await p.evaluate(()=>document.querySelector('.record-editor').style.fontSize='24px');
  assert(await p.evaluate(()=>document.querySelector('.sheet-body').scrollWidth<=document.querySelector('.sheet-body').clientWidth));
  await context.close();
 }
 assert.deepEqual(errors,[]);await browser.close();console.log(JSON.stringify({passed:true,checks:['four recording forms','320 and 393px','light and dark','one divider and no redundant controls','44px save targets','photo and text saved','discard leaves saved meal and workout unchanged'],consoleErrors:errors}));
})().catch(error=>{console.error(error);process.exit(1)});
