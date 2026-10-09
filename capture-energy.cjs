const {chromium}=require('playwright-core');
(async()=>{
 const b=await chromium.launch({headless:true,channel:'chrome'});
 const profile=async p=>{await p.click('[data-scene="profile"]');await p.click('#profile-example');await p.click('#save-profile')};
 const workout=async p=>{await p.click('[data-scene="workout"]');await p.click('#copy-workout');await p.fill('#workout-duration','45');for(const id of ['0,0','0,1','0,2'])await p.click(`[data-done="${id}"]`)};
 for(const scene of ['today','meal','workout','review','profile','library','failed','loading','dark','empty','offline']){
  const c=await b.newContext({viewport:{width:1440,height:1020},reducedMotion:'reduce'}),p=await c.newPage();
  await p.goto('http://127.0.0.1:8765/?v=0.6');await p.evaluate(()=>document.fonts.ready);
  if(['today','workout','library'].includes(scene)){await profile(p);await workout(p);if(scene!=='workout')await p.click('#finish-workout')}
  if(scene==='meal'){await p.click('[data-ai-demo="ready"]');await p.locator('#adjust-energy').waitFor()}
  if(scene==='failed'){await p.click('[data-ai-demo="failed"]');await p.locator('#meal-energy').getByText('这次没有识别出来').waitFor()}
  if(scene==='loading'){await p.click('[data-ai-demo="ready"]')}
  if(scene==='profile'){await p.click('[data-scene="profile"]');await p.click('#profile-example')}
  if(scene==='library')await p.click('[data-scene="library"]');
  if(['review','dark'].includes(scene)){await p.click('[data-scene="review"]');await p.click('#toggle-energy-sample')}
  if(scene==='dark')await p.click('[data-theme="dark"]');
  if(['empty','offline'].includes(scene))await p.click(`[data-state="${scene}"]`);
  await p.evaluate(()=>{document.querySelector('#phone').scrollTop=0;window.scrollTo(0,0);clearTimeout(toastTimer);document.querySelector('#toast').classList.remove('show')});
  await p.locator('#phone').screenshot({path:`energy-${scene}.png`});
  if(scene==='today')await p.screenshot({path:'energy-desktop.png',fullPage:true});
  if(['today','meal','workout','review','profile','library'].includes(scene))await p.locator('#phone').screenshot({path:`${scene}.png`});
  if(scene==='review'){await p.locator('#app .scroll').evaluate(el=>el.scrollTop=el.scrollHeight);await p.locator('#phone').screenshot({path:'energy-review-detail.png'})}
  await c.close();
 }
 const p=await b.newPage({viewport:{width:2000,height:1160},reducedMotion:'reduce'});await p.goto('http://127.0.0.1:8765/gallery.html');await p.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await p.screenshot({path:'energy-overview.png',fullPage:true});await p.screenshot({path:'screens-overview.png',fullPage:true});await b.close();console.log('Energy UI screenshots captured in isolated contexts.');
})().catch(e=>{console.error(e);process.exit(1)});
