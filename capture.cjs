const {chromium}=require('playwright-core');
(async()=>{
const browser=await chromium.launch({headless:true,channel:'chrome'});
for(const scene of ['today','meal','workout','review','library','dark','empty','offline']){
 const context=await browser.newContext({viewport:{width:1440,height:1020},reducedMotion:'reduce'});const page=await context.newPage();
 await page.goto('http://127.0.0.1:8765');await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode().catch(()=>{}))));
 if(['meal','review','library'].includes(scene))await page.click(`[data-scene="${scene}"]`);
 if(scene==='workout'){await page.click('[data-scene="workout"]');await page.click('#copy-workout')}
 if(scene==='dark')await page.click('[data-theme="dark"]');
 if(['empty','offline'].includes(scene))await page.click(`[data-state="${scene}"]`);
 await page.evaluate(()=>{document.getElementById('phone').scrollTop=0;window.scrollTo(0,0)});
 await page.locator('#phone').screenshot({path:`${scene}.png`});
 if(scene==='today')await page.screenshot({path:'overview.png',fullPage:true});
 await context.close();
}
const page=await browser.newPage({viewport:{width:2000,height:1160},reducedMotion:'reduce'});await page.goto('http://127.0.0.1:8765/gallery.html');await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:'screens-overview.png',fullPage:true});await browser.close();console.log('All final screenshots rendered in clean contexts.');
})();
