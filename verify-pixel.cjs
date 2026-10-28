const { selectReviewRange } = require('./review-test-helpers.cjs');
const {chromium}=require('playwright-core');
const assert=require('node:assert/strict');
(async()=>{
 const base=process.env.BASE_URL||'http://127.0.0.1:8765';
 const browser=await chromium.launch({headless:true,channel:'chrome'});
 const errors=[];
 for(const width of [393,320]){
  const context=await browser.newContext({viewport:{width,height:852},reducedMotion:'reduce'});
  const p=await context.newPage();p.on('pageerror',e=>errors.push(e.message));
  await p.clock.setFixedTime(new Date('2026-10-09T12:00:00Z'));await p.goto(`${base}/?v=0.6`);await p.evaluate(()=>document.fonts.ready);
  const fonts=await p.evaluate(()=>({loaded:document.fonts.check('12px "Fusion Pixel"','薄记饮食训练0123456789'),families:['h2','.home-record','.home-value','.primary'].map(s=>getComputedStyle(document.querySelector(s)).fontFamily)}));
  assert(fonts.families.every(f=>f.includes('apple-system')));
  assert.equal(await p.locator('.food-img.pixel-art').count(),0);
  assert.equal(await p.evaluate(()=>state.meals[0].photos[0]),'assets/meal-yogurt-real.jpg');
  assert.equal(await p.locator('.tabbar .pixel-icon').count(),0);
  const monochrome=async()=>{
   const colored=await p.locator('#app,#overlay').evaluateAll(roots=>roots.flatMap(root=>[root,...root.querySelectorAll('*')]).filter(el=>el.getBoundingClientRect().width&&el.getBoundingClientRect().height).flatMap(el=>{
    const style=getComputedStyle(el);
    return ['color','backgroundColor','borderTopColor','outlineColor','fill','stroke'].flatMap(key=>{
     const value=style[key], m=value?.match(/^rgba?\((\d+), (\d+), (\d+)(?:, ([\d.]+))?\)$/);
     return m && m[4]!=='0' && (m[1]!==m[2]||m[2]!==m[3]) ? [`${el.className.baseVal??el.className}:${key}:${value}`] : [];
    });
   }));assert.deepEqual([...new Set(colored)],[]);
  };
  const fits=()=>p.evaluate(()=>{const e=document.querySelector('.sheet-body')||document.querySelector('#app .scroll');return document.documentElement.scrollWidth<=innerWidth&&e.scrollWidth<=e.clientWidth});
  const cards=await p.locator('.home-record').evaluateAll(els=>els.map(el=>({width:el.getBoundingClientRect().width,height:el.getBoundingClientRect().height,x:el.getBoundingClientRect().x,y:el.getBoundingClientRect().y})));
  assert.equal(cards.length,4);assert(cards.every(c=>Math.abs(c.width-cards[0].width)<1&&c.height>=76));
  assert(cards.every((c,i)=>c.x===cards[0].x&&(i===0||c.y>cards[i-1].y)));
  assert.equal(await p.locator('.home-record img').count(),0);assert.equal(await p.locator('.home-record time').count(),4);
  assert.equal(await p.locator('.home-record-icon .pixel-icon').count(),4);
  assert(!/上肢力量|组完成|,/.test((await p.locator('.home-record').allTextContents()).join('')));
  assert(await fits());await monochrome();await p.screenshot({path:`pixel-today-${width}.png`});
  await p.click('[data-tab="review"]');
  assert.equal(await p.locator('.review-heatmap').count(),2);
  assert(await fits());await monochrome();await p.screenshot({path:`minimal-calendar-${width}.png`});
  assert.equal(await p.locator('[data-record-day="2026-10-09"].recorded').count(),2);
  await p.click('[data-review-mode="热量"]');assert(await fits());await monochrome();
  assert.equal(await p.locator('[data-day-count="7"]').count(),2);
  await p.screenshot({path:`pixel-review-${width}.png`});
  await selectReviewRange(p,'2026-09-10','2026-10-09');assert.equal(await p.locator('[data-day-count="30"]').count(),2);assert(await fits());await monochrome();await p.screenshot({path:`pixel-month-${width}.png`});
  await p.click('[data-tab="library"]');
  assert.equal(await p.locator('.mine-row').count(),3);assert.equal(await p.locator('.mine-icon').count(),0);
  assert(await fits());await monochrome();await p.screenshot({path:`pixel-mine-${width}.png`});await p.click('[data-profile]');await p.click('#profile-example');await p.click('#save-profile');
  await p.click('[data-tab="today"]');await p.evaluate(()=>{openMeal();runDemoRecognition()});await p.locator('#adjust-energy').waitFor();
  await p.evaluate(()=>{clearTimeout(toastTimer);document.querySelector('#toast').classList.remove('show')});assert(await fits());await monochrome();await p.screenshot({path:`pixel-meal-${width}.png`});
  await p.keyboard.press('Escape');await p.click('[data-view-workout="w1009"]');
  assert(await fits());await monochrome();assert.equal(await p.locator('[data-done],.workout-progress').count(),0);await p.screenshot({path:`pixel-workout-${width}.png`});
  await p.keyboard.press('Escape');await p.click('[data-new-meal]');await p.setInputFiles('#photo-file','assets/breakfast.jpg');await p.locator('.photo-thumb img').waitFor();
  assert(!(await p.locator('.photo-thumb img').getAttribute('class')||'').includes('pixel-art'));
  assert((await p.locator('.photo-thumb img').getAttribute('src')).startsWith('data:image/'));
  await p.keyboard.press('Escape');await p.click('[data-tab="library"]');
  await p.evaluate(()=>{document.querySelector('#phone').classList.add('dark');clearTimeout(toastTimer);document.querySelector('#toast').classList.remove('show')});
  await monochrome();await p.screenshot({path:`minimal-mine-dark-${width}.png`});
  await p.click('[data-tab="review"]');await p.click('[data-review-mode="日历"]');
  await monochrome();await p.screenshot({path:`minimal-calendar-dark-${width}.png`});
  await context.close();
 }
 assert.deepEqual(errors,[]);console.log(JSON.stringify({passed:true,checks:['readable system UI font','text-only navigation','fixture-only image mapping','stored photo references unchanged','7/30-day charts','393/320px fit','no workout completion controls','real uploaded photos not transformed'],consoleErrors:errors},null,2));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
