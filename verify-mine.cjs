const {chromium}=require('playwright-core');
const assert=require('node:assert/strict');
const fs=require('node:fs');
(async()=>{
  const base=process.env.BASE_URL||'http://127.0.0.1:8765';
  const browser=await chromium.launch({headless:true,channel:'chrome'});
  const context=await browser.newContext({viewport:{width:393,height:852},timezoneId:'Asia/Shanghai',reducedMotion:'reduce'});
  const p=await context.newPage(), errors=[];p.on('pageerror',e=>errors.push(e.message));
  await p.clock.setFixedTime(new Date('2026-10-25T04:00:00Z'));await p.goto(base);
  await p.evaluate(()=>{state.profile=null;state.profileHistory=[];page='library';render()});
  assert.match(await p.locator('[data-profile]').innerText(),/待填写/);
  assert.match(await p.locator('[data-ai-settings]').innerText(),/演示/);
  assert.equal(await p.locator('[data-management] small').count(),0);
  await p.click('[data-profile]');await p.click('#save-profile');assert.match(await p.locator('#profile-error').innerText(),/有效信息/);
  const errorBounds=await p.locator('#profile-error').boundingBox(), saveBounds=await p.locator('#save-profile').boundingBox();
  assert(errorBounds.y>=0&&errorBounds.y+errorBounds.height<=saveBounds.y);
  await p.click('#profile-example');await p.fill('#profile-target','');await p.click('#save-profile');
  assert.match(await p.locator('[data-profile]').innerText(),/已填写/);
  assert(await p.locator('[data-profile]').evaluate(e=>e===document.activeElement));
  await p.evaluate(()=>{selectedDate='2020-01-01';render()});assert.match(await p.locator('[data-profile]').innerText(),/已填写/);
  await p.evaluate(()=>{state.profileHistory[0].effectiveDate='2026-10-26';render()});assert.match(await p.locator('[data-profile]').innerText(),/待填写/);
  await p.evaluate(()=>{state.profileHistory[0].effectiveDate='2026-10-25';persist();render()});
  const snapshot=await p.evaluate(()=>JSON.stringify(state));
  await p.click('[data-profile]');await p.fill('#profile-weight','81');await p.keyboard.press('Escape');
  assert.equal(await p.evaluate(()=>JSON.stringify(state)),snapshot);
  assert(await p.locator('[data-profile]').evaluate(e=>e===document.activeElement));
  await p.click('[data-ai-settings]');const enabled=await p.locator('#auto-estimate').isChecked();await p.locator('#auto-estimate').setChecked(!enabled);
  await p.click('#close-sheet');assert(await p.locator('[data-ai-settings]').evaluate(e=>e===document.activeElement));
  await p.reload();await p.click('[data-tab="library"]');await p.click('[data-ai-settings]');assert.equal(await p.locator('#auto-estimate').isChecked(),!enabled);
  await p.click('#ai-settings-save');assert(await p.locator('[data-ai-settings]').evaluate(e=>e===document.activeElement));
  await p.click('[data-management]');assert.match(await p.locator('.sheet-body').innerText(),/自动备份.*iPhone/);await p.click('[data-export-open]');await p.keyboard.press('Escape');
  assert(await p.locator('[data-export-open]').evaluate(e=>e===document.activeElement));await p.keyboard.press('Escape');
  assert(await p.locator('[data-management]').evaluate(e=>e===document.activeElement));
  // A failed image read leaves the export action and source records intact.
  await p.evaluate(()=>{state.meals[0].photos=['/mine-missing-fixture.jpg']});
  const recordsBefore=await p.evaluate(()=>JSON.stringify(state));
  await p.route('**/mine-missing-fixture.jpg',route=>route.fulfill({status:404,body:''}));
  await p.click('[data-management]');await p.click('[data-export-open]');await p.click('#download-json');
  await p.locator('#export-error').filter({hasText:'无法读取'}).waitFor();assert(await p.locator('#download-json').isEnabled());
  assert.equal(await p.evaluate(()=>JSON.stringify(state)),recordsBefore);
  await p.unroute('**/mine-missing-fixture.jpg');
  await p.route('**/mine-missing-fixture.jpg',route=>route.fulfill({status:200,contentType:'image/png',path:'assets/breakfast.jpg'}));
  const download=p.waitForEvent('download');await p.click('#download-json');const file=await download;
  const data=JSON.parse(fs.readFileSync(await file.path(),'utf8'));assert.equal(data.schema_version,1);assert.match(data.meals[0].photos[0],/^data:/);
  assert(await p.locator('[data-management]').evaluate(e=>e===document.activeElement));
  fs.mkdirSync('mine-screenshots',{recursive:true});
  for(const width of [393,320,196])for(const colorScheme of ['light','dark']){
    await p.setViewportSize({width,height:852});await p.emulateMedia({colorScheme});await p.evaluate(dark=>$('#phone').classList.toggle('dark',dark),colorScheme==='dark');
    await p.evaluate(()=>{clearTimeout(toastTimer);$('#toast').classList.remove('show');page='library';render()});
    async function capture(name){
      assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
      assert(await p.evaluate(()=>!$('.sheet-body')||$('.sheet-body').scrollWidth<=$('.sheet-body').clientWidth));
      if(width!==196)await p.screenshot({path:`mine-screenshots/${name}-${width}-${colorScheme}.png`});
    }
    await capture('home');
    for(const row of await p.locator('.mine-row').all())assert((await row.boundingBox()).height>=64);
    await p.click('[data-profile]');await capture('profile');
    for(const input of await p.locator('.mine-field input,.mine-field select').all())assert((await input.boundingBox()).height>=44);
    await p.locator('#close-sheet').focus();await p.keyboard.press('Shift+Tab');assert(await p.locator('#save-profile').evaluate(e=>e===document.activeElement));
    await p.keyboard.press('Tab');assert(await p.locator('#close-sheet').evaluate(e=>e===document.activeElement));await p.keyboard.press('Escape');
    await p.click('[data-ai-settings]');await capture('ai');await p.keyboard.press('Escape');
    await p.click('[data-management]');await capture('data');await p.click('[data-export-open]');await capture('export');await p.keyboard.press('Escape');await p.keyboard.press('Escape');
  }
  assert.deepEqual(errors,[]);await browser.close();
  console.log('Mine passed: current-date status, save/cancel, persisted toggle, export error/retry, nested focus, keyboard trap, 320/393px light/dark and 200% reflow.');
})().catch(error=>{console.error(error);process.exit(1)});
