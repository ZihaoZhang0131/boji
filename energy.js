/* v0.5 prototype. Real equations, local records, explicitly simulated AI.
 * No provider calls, credentials, image uploads or health data leave this page.
 */
const energyVersion = '0.5';
const sampleFoods = [
  {name:'蔬菜',grams:180,kcal:45},
  {name:'鸡胸肉',grams:100,kcal:165},
  {name:'牛油果',grams:60,kcal:96},
  {name:'沙拉酱',grams:25,kcal:114}
];
const sampleProfile = {sex:'male',age:28,height:175,weight:70,activity:1.2,target:null};
state.profile ??= null;
state.profileHistory ??= [];
state.energySettings ??= {autoEstimate:true,consent:false};
let energyRange=7, energySample=false, energyDay=selectedDate;
reviewMode='热量';

function mealSignature(m) {return JSON.stringify([m.note,m.photos]);}
function estimateMeal(kcal,items=[]) {
  return {status:'ready',source:'demo-ai',kcal,items:structuredClone(items),low:Math.round(kcal*.8),high:Math.round(kcal*1.2),model:'演示数据 · 非模型推理',version:energyVersion};
}
// Only annotate untouched, recognisable fixture records; never infer user photos.
const fixtureEnergy={m1:['一碗清爽的蔬菜沙拉',420,sampleFoods],m2:['鸡蛋、牛油果和吐司',385,[{name:'鸡蛋',grams:50,kcal:75},{name:'牛油果',grams:70,kcal:112},{name:'吐司',grams:75,kcal:198}]],m3:['蔬菜沙拉',560,[]],m4:['水果麦片',360,[]]};
for(const m of state.meals) {
  const f=fixtureEnergy[m.id];
  if(f && m.title===f[0] && m.photos.every(p=>p.startsWith('assets/')) && !m.energy) {
    m.energy=estimateMeal(f[1],f[2]);m.energy.signature=mealSignature(m);
  }
}

const num=n=>n==null?'—':Math.round(n).toLocaleString('en-US');
const kcalText=n=>n==null?'待估算':`约 ${num(n)} kcal`;
function mealKcal(m) {return ['ready','manual'].includes(m.energy?.status)&&Number.isFinite(m.energy.kcal)?m.energy.kcal:null;}
function profileValid(p) {return !!p&&['male','female'].includes(p.sex)&&Number.isInteger(p.age)&&p.age>=18&&p.age<=59&&p.height>=100&&p.height<=230&&p.weight>=30&&p.weight<=250&&[1.2,1.35,1.5].includes(p.activity);}
function restingKcal(p) {return profileValid(p)?Math.round(10*p.weight+6.25*p.height-5*p.age+(p.sex==='male'?5:-161)):null;}
function profileAt(date) {return state.profileHistory.filter(p=>p.effectiveDate<=date).sort((a,b)=>a.effectiveDate.localeCompare(b.effectiveDate)).at(-1)||null;}
function workoutEstimate(w) {
  const weight=Number(w.energyWeight),minutes=Number(w.duration),met=Number(w.met);
  if(!(weight>=30&&weight<=250&&minutes>0&&minutes<=360&&[3.5,5,6].includes(met)))return null;
  return {activeKcal:Math.round((met-1)*3.5*weight/200*minutes),grossKcal:Math.round(met*3.5*weight/200*minutes),weight,minutes,met,method:'MET-net-v1',version:energyVersion};
}
function workoutKcal(w) {return countSets(w)>0?(w.energy?.activeKcal??null):null;}
function dayEnergy(date) {
  const meals=preview==='empty'?[]:state.meals.filter(m=>m.date===date),workouts=preview==='empty'?[]:state.workouts.filter(w=>w.date===date);
  const known=meals.filter(m=>mealKcal(m)!=null),knownWorkouts=workouts.filter(w=>workoutKcal(w)!=null);
  const p=profileAt(date),bmr=restingKcal(p),base=bmr==null?null:Math.round(bmr*p.activity);
  const intake=known.length?known.reduce((n,m)=>n+mealKcal(m),0):null;
  const active=knownWorkouts.length?knownWorkouts.reduce((n,w)=>n+workoutKcal(w),0):null;
  const unknown=meals.length-known.length,unknownWorkouts=workouts.length-knownWorkouts.length;
  const recordedAll=preview!=='empty'&&state.complete.includes(date);
  const complete=recordedAll&&meals.length>0&&!unknown&&!unknownWorkouts;
  const burn=base==null||unknownWorkouts?null:base+(active??0);
  return {date,intake,active,bmr,base,burn,target:p?.target??null,unknown,unknownWorkouts,complete,recordedAll,meals:meals.length,workouts:workouts.length,balance:complete&&burn!=null&&intake!=null?intake-burn:null};
}
function energyBadge(m) {
  const e=m.energy,k=mealKcal(m);
  const status=e?.status==='loading'?'识别中':e?.status==='failed'?'识别未完成':e?.status==='stale'?'已改记录 · 待重估':e?.status==='queued'?'联网后估算':'待估算';
  return `<div class="meal-kcal">${k!=null?`<b>≈ ${num(k)} <small>kcal</small></b><small>${e.source==='manual'?'手动修正':'AI 估算 · 示例'}</small>`:`<small>${status}</small>`}</div>`;
}
const mealCardBeforeEnergy=mealCard;
mealCard=function(m,compact=false){return mealCardBeforeEnergy(m,compact).replace('</div></button>',`${energyBadge(m)}</div></button>`)};
const workoutCardBeforeEnergy=workoutCard;
workoutCard=function(w){return workoutCardBeforeEnergy(w).replace('</div></button>',`<div class="meal-kcal"><b>${workoutKcal(w)==null?'—':`≈ ${num(workoutKcal(w))}`} <small>kcal</small></b><small>运动净消耗${w.duration?` · ${w.duration} 分钟`:''}</small></div></div></button>`)};

const todayBeforeEnergy=renderToday;
renderToday=function(){
  const d=dayEnergy(selectedDate);
  const summary=`<div class="energy-summary"><button data-energy-review><small>已记录摄入${d.unknown?' · 有待估算':''}</small><span class="energy-number">${num(d.intake)}<i>kcal</i></span></button><button data-energy-review><small>运动净消耗${d.unknownWorkouts?' · 有待估算':''}</small><span class="energy-number">${num(d.active)}<i>kcal</i></span></button></div>`;
  return todayBeforeEnergy().replace('<div class="feed">',`${summary}<div class="feed">`);
};

const libraryBeforeEnergy=renderLibrary;
renderLibrary=function(){
  const profileRow=`<div class="group"><button class="setting-row" data-profile><span class="row-content"><b>个人信息与代谢</b><small>${state.profile?`基础代谢约 ${num(restingKcal(state.profile))} kcal / 天`:'填写身高、体重与年龄'}</small></span>${icon('arrow')}</button><button class="setting-row" data-ai-settings><span class="row-content"><b>食物 AI 估算</b><small>接口未连接 · 可体验示例</small></span>${icon('arrow')}</button></div>`;
  return libraryBeforeEnergy().replace('<div class="group">',`${profileRow}<div class="group">`);
};

const commonBeforeEnergy=bindCommon;
bindCommon=function(root){
  commonBeforeEnergy(root);
  root.querySelectorAll('[data-profile]').forEach(b=>b.onclick=()=>openProfile());
  root.querySelectorAll('[data-ai-settings]').forEach(b=>b.onclick=()=>openAISettings());
  root.querySelectorAll('[data-energy-review]').forEach(b=>b.onclick=()=>{page='review';reviewMode='热量';energyDay=selectedDate;render()});
};
const sceneBeforeEnergy=setScene;
setScene=function(s){
  sceneBeforeEnergy(s);
  const notes={today:['随手记。<br>心里有数。','一餐的摄入，一次训练的消耗。都只是估算，不是分数。','点热量看趋势；点一餐查看或修正估算。'],meal:['这一餐，<br>大概多少？','照片与文字一起估算。份量、酱汁和剩余量，都可以补充。','点「体验示例识别」查看结果、调整份量。原型不发送图片。'],workout:['练过的，<br>轻轻记下。','时长、体重与训练类型，共同决定运动消耗估算。','补充本次时长；组数仍按实际完成记录。'],review:['看趋势。<br>不盯一餐。','摄入与消耗放在一起看。没记全的日子，先留白。','切换 7 / 30 天；点击日期查看当天热量。'],profile:['从自己，<br>开始算起。','基础代谢只是静息估算，不等于一天该吃多少。','填写信息实时计算，或使用示例资料体验。']};
  if(notes[s]){const n=notes[s];$('#note-title').innerHTML=n[0];$('#note-description').textContent=n[1];$('#try-copy').textContent=n[2]}
};

function openProfile(onDone=null) {
  const p=state.profile?structuredClone(state.profile):{sex:'',age:'',height:'',weight:'',activity:1.2,target:null};
  sheet('个人信息',`<div class="profile-top"><span>仅保存在本机</span><button id="profile-example">填入示例</button></div>
  <div class="energy-form-grid"><div><label for="profile-sex">公式性别参数</label><select id="profile-sex"><option value="">请选择</option><option value="male">男性公式</option><option value="female">女性公式</option></select></div><div><label for="profile-age">年龄 / 岁</label><input id="profile-age" type="number" inputmode="numeric" min="18" max="59" value="${p.age}"></div><div><label for="profile-height">身高 / cm</label><input id="profile-height" type="number" inputmode="decimal" min="100" max="230" step="0.1" value="${p.height}"></div><div><label for="profile-weight">体重 / kg</label><input id="profile-weight" type="number" inputmode="decimal" min="30" max="250" step="0.1" value="${p.weight}"></div></div>
  <div class="energy-field"><label for="profile-activity">日常活动 · 不含另外记录的训练</label><select id="profile-activity"><option value="1.2">多数时间坐着</option><option value="1.35">常有站立或步行</option><option value="1.5">日常走动较多</option></select></div>
  <div class="profile-result" id="profile-result" aria-live="polite"></div>
  <div class="energy-field"><label for="profile-target">每日摄入目标 / kcal · 可不填</label><input id="profile-target" type="number" inputmode="numeric" min="1" max="10000" placeholder="自己的计划，不自动扣减" value="${p.target??''}"></div>
  <p class="energy-help">适用于 18–59 岁普通成年人。孕哺期、疾病及特殊体成分需另行评估。公式估算不替代测量或专业建议。</p><p id="profile-error" class="field-error" role="alert"></p>`,
  '<button class="primary" id="save-profile">保存信息</button>',true,'返回',()=>{closeSheet();if(onDone)onDone()});
  setScene('profile');$('#profile-sex').value=p.sex;$('#profile-activity').value=String(p.activity);
  const read=()=>({sex:$('#profile-sex').value,age:Number($('#profile-age').value),height:Number($('#profile-height').value),weight:Number($('#profile-weight').value),activity:Number($('#profile-activity').value),target:$('#profile-target').value===''?null:Number($('#profile-target').value)});
  const update=()=>{const v=read(),b=restingKcal(v);$('#profile-result').innerHTML=`<span class="energy-caption">基础代谢 · 公式估算</span><span class="energy-number">${num(b)}<i>kcal / 天</i></span><div class="energy-line"><span>日常消耗，不含训练</span><b>${b==null?'—':num(b*v.activity)}</b></div><p class="energy-help">Mifflin–St Jeor 静息代谢公式<br>日常消耗 = 静息估算 × 活动系数；训练另计净消耗。</p>`};
  $$('#overlay input, #overlay select').forEach(el=>el.addEventListener('input',update));
  $('#profile-example').onclick=()=>{for(const k of ['sex','age','height','weight','activity'])$('#profile-'+k).value=sampleProfile[k];update();toast('已填入示例资料，不代表你的真实信息。')};
  $('#save-profile').onclick=()=>{const v=read();if(!profileValid(v)||v.target!=null&&(!Number.isFinite(v.target)||v.target<1||v.target>10000)){ $('#profile-error').textContent='请填写有效信息：年龄 18–59，身高 100–230 cm，体重 30–250 kg。';return }
    state.profile={...v,updatedAt:new Date().toISOString()};state.profileHistory.push({...state.profile,effectiveDate:selectedDate});persist();closeSheet();render();if(onDone)onDone();toast('已保存；历史日期的代谢快照不变。')};
  update();
}

function openAISettings(onBack=null) {
  sheet('食物 AI 估算',`<div class="energy-line"><h3>多模态模型接口</h3><span class="energy-badge">未连接</span></div><p class="energy-help">当前为设计演示，不会向外发送图片，也不会产生 API 费用。</p>
  <div class="energy-section"><label class="energy-line" for="auto-estimate"><span>添加照片后自动估算</span><input id="auto-estimate" type="checkbox" ${state.energySettings.autoEstimate?'checked':''}></label></div>
  <div class="energy-integration"><strong>正式版的工作方式</strong><ol><li>首次使用先确认图片与备注会发送给所选模型服务。</li><li>模型识别食物、份量和烹饪方式，返回逐项热量与不确定性。</li><li>可以调整份量、补充酱汁或手动改热量；结果随记录保存。</li></ol><p>API 密钥不放在页面或导出资料中。生产环境通过安全后端调用；模型供应商、保留政策和费用在连接时说明。</p></div>
  <p class="energy-help">自动估算开关仅控制本原型的状态预览。连接、授权、撤回及离线重试的完整约定见设计说明。</p>`,
  '<button class="primary" id="ai-settings-save">完成</button>',true,'返回',()=>{closeSheet();if(onBack)onBack()});
  $('#auto-estimate').onchange=e=>{state.energySettings.autoEstimate=e.target.checked;persist()};
  $('#ai-settings-save').onclick=()=>{closeSheet();if(onBack)onBack()};
}

function mealEnergyPanel(m) {
  const e=m.energy,k=mealKcal(m);
  if(k!=null)return `<div class="energy-line"><span>这一餐 · ${e.source==='manual'?'已手动修正':'AI 估算'}</span><span class="energy-badge">${e.source==='manual'?'可调整':'示例结果'}</span></div><div class="energy-line"><span class="energy-number">≈ ${num(k)}<i>kcal</i></span><button class="text-button" id="adjust-energy">调整</button></div>${e.items?.length?`<div class="energy-items">${e.items.map(i=>`<div class="energy-item"><span>${esc(i.name)}</span><small>${num(i.grams)} g</small><span>${num(i.kcal)}</span></div>`).join('')}</div>`:''}<p class="energy-help">${e.source==='manual'?'按你修正后的数据汇总。':`示例范围 ${num(e.low)}–${num(e.high)} kcal · 不是统计置信区间。<br>份量、油和酱汁可能影响结果。`}</p>`;
  if(e?.status==='loading')return '<span class="energy-pending"></span>正在识别这餐…<p class="energy-help">演示状态 · 图片未发送。可以先保存记录。</p>';
  const message=e?.status==='stale'?'记录已变更，需要重新估算':e?.status==='failed'?'这次没有识别出来':e?.status==='queued'?'离线，等待联网':!state.energySettings.autoEstimate?'自动估算已关闭':m.photos.length?'照片已记录 · 待连接模型':'拍下来，热量也一起记';
  return `<div class="energy-line"><span>${message}</span><span class="energy-badge">AI 估算</span></div><p class="energy-help">${e?.status==='failed'?'照片可能不够清晰，也可以补充文字或手动填写。':'原型尚未连接接口，上传的真实照片不会生成虚构热量。'}</p><div class="energy-actions"><button id="demo-recognize">${e?.status==='failed'?'重试示例':'体验示例识别'}</button><button id="manual-energy">手动填写</button><button id="meal-connect">连接说明</button></div>`;
}
function updateMealPanel() {
  if(!$('#meal-energy'))return;
  $('#meal-energy').innerHTML=mealEnergyPanel(mealDraft);
  $('#adjust-energy')?.addEventListener('click',()=>openMealEnergyEditor());
  $('#manual-energy')?.addEventListener('click',()=>openMealEnergyEditor());
  $('#demo-recognize')?.addEventListener('click',()=>runDemoRecognition());
  $('#meal-connect')?.addEventListener('click',()=>openAISettings(renderMeal));
}
const mealBeforeEnergy=renderMeal;
renderMeal=function(){
  const m=mealDraft;
  if(m.energy&&m.energy.signature!==mealSignature(m)&&['ready','manual'].includes(m.energy.status))m.energy.status='stale';
  if(!m.energy&&m.photos.length)m.energy={status:preview==='offline'?'queued':'unconfigured'};
  mealBeforeEnergy();
  const panel=document.createElement('section');panel.id='meal-energy';panel.className='energy-panel';panel.setAttribute('aria-live','polite');$('#meal-note').after(panel);
  $('#meal-note').addEventListener('input',()=>{if(m.energy&&['ready','manual'].includes(m.energy.status)){m.energy.status='stale';updateMealPanel()}});
  updateMealPanel();
};
function runDemoRecognition(fail=false) {
  const m=mealDraft;
  if(!m.photos.length&&!m.note.trim()) {m.photos=['assets/bowl-line.svg'];m.note='蔬菜、鸡胸肉、牛油果，酱汁另外放。';m.slot='午餐'}
  const signature=mealSignature(m);m.energy={status:'loading',signature};renderMeal();
  setTimeout(()=>{
    if(mealSignature(m)!==signature){m.energy.status='stale'}
    else if(fail)m.energy={status:'failed',signature};
    else {m.energy=estimateMeal(420,sampleFoods);m.energy.signature=signature}
    // A delayed result cannot overwrite a different edit or deleted record.
    const saved=state.meals.find(x=>x.id===m.id);
    if(saved===m){persist();render()}
    if(mealDraft===m&&$('#meal-energy'))updateMealPanel();
  },900);
}
function openMealEnergyEditor() {
  const m=mealDraft,rows=structuredClone(m.energy?.items?.length?m.energy.items:[{name:'整餐',grams:null,kcal:mealKcal(m)??0}]);
  const original=structuredClone(m.energy||{});
  sheet('调整这一餐',`<p class="energy-help">修改份量会按比例更新热量，也可以直接修改 kcal。这里只调整热量，不改原始照片。</p><div class="energy-item energy-item-head"><span>食物</span><span>克数</span><span>kcal</span></div>${rows.map((r,i)=>`<div class="energy-item"><input class="energy-item-name" data-food-name="${i}" aria-label="第${i+1}项食物" value="${esc(r.name)}"><input data-food-grams="${i}" aria-label="${esc(r.name)}克数" type="number" inputmode="decimal" min="0" step="0.1" value="${r.grams??''}" placeholder="—"><input data-food-kcal="${i}" aria-label="${esc(r.name)}热量" type="number" inputmode="decimal" min="0" max="10000" value="${r.kcal}"></div>`).join('')}<div class="profile-result"><span class="energy-caption">调整后合计</span><span class="energy-number" id="adjusted-total">${num(rows.reduce((n,r)=>n+r.kcal,0))}<i>kcal</i></span></div><p id="adjust-error" class="field-error" role="alert"></p>`,
  '<button class="primary" id="save-energy-adjustment">确认调整</button>',false,'返回',renderMeal);
  const total=()=>{$('#adjusted-total').innerHTML=`${num(rows.reduce((n,r)=>n+r.kcal,0))}<i>kcal</i>`};
  $$('[data-food-grams]').forEach(input=>input.oninput=()=>{const i=+input.dataset.foodGrams,old=rows[i].grams,n=Number(input.value);if(old>0&&n>=0){rows[i].kcal=Math.round(rows[i].kcal*n/old);$(`[data-food-kcal="${i}"]`).value=rows[i].kcal}rows[i].grams=input.value===''?null:n;total()});
  $$('[data-food-kcal]').forEach(input=>input.oninput=()=>{rows[+input.dataset.foodKcal].kcal=input.value===''?NaN:Number(input.value);total()});
  $$('[data-food-name]').forEach(input=>input.oninput=()=>{rows[+input.dataset.foodName].name=input.value.trim()});
  $('#save-energy-adjustment').onclick=()=>{const sum=rows.reduce((n,r)=>n+r.kcal,0);if(rows.some(r=>!r.name||!Number.isFinite(r.kcal)||r.kcal<0||r.grams!=null&&(!Number.isFinite(r.grams)||r.grams<0))||sum>10000){$('#adjust-error').textContent='请填写食物名称和有效热量；整餐合计不超过 10,000 kcal。';return}
    m.energy={status:'manual',source:'manual',kcal:sum,items:rows,originalEstimate:original.originalEstimate||original,signature:mealSignature(m),updatedAt:new Date().toISOString()};renderMeal()};
}
const mealDetailBeforeEnergy=openMealDetail;
openMealDetail=function(id){mealDetailBeforeEnergy(id);const m=state.meals.find(m=>m.id===id);if(!m)return;const section=document.createElement('section');section.className='energy-panel';section.innerHTML=`<div class="energy-line"><span>这一餐的热量</span><span class="energy-badge">${m.energy?.source==='manual'?'手动修正':'估算'}</span></div>${energyBadge(m)}<p class="energy-help">${m.energy?.source==='demo-ai'?'演示估算数据，不代表实际模型识别。':'照片无法精确反映份量、用油和剩余量。'}</p>`;$('.sheet-body h3').after(section)};

const exportBeforeEnergy=openExport;
openExport=function(){exportBeforeEnergy();$('.sheet-body .helper').textContent='导出包含照片、个人身体信息、热量估算与修正记录。分享前请确认接收方；模型密钥不会写入资料包。'};

const saveDraftBeforeEnergy=saveDraft;
saveDraft=function(){
  if(currentWorkout){
    if(currentWorkout.energySession!==currentWorkout.id){currentWorkout.energySession=currentWorkout.id;currentWorkout.duration=null;currentWorkout.met=3.5;currentWorkout.energyWeight=state.profile?.weight??null;currentWorkout.energy=null}
    currentWorkout.energy=workoutEstimate(currentWorkout);
  }
  saveDraftBeforeEnergy();
};
const workoutBeforeEnergy=openWorkout;
openWorkout=function(){
  workoutBeforeEnergy();const w=currentWorkout;
  const panel=document.createElement('section');panel.className='workout-energy';panel.innerHTML=`<div class="energy-line"><span class="energy-caption">本次运动净消耗 · 估算</span><span class="energy-number" id="workout-kcal">${num(w.energy?.activeKcal)}<i>kcal</i></span></div><div class="energy-form-grid"><div><label for="workout-duration">实际时长 / 分钟</label><input id="workout-duration" type="number" inputmode="numeric" min="1" max="360" value="${w.duration??''}" placeholder="含组间休息"></div><div><label for="workout-met">训练类型</label><select id="workout-met"><option value="3.5">常规力量</option><option value="5">深蹲 / 硬拉为主</option><option value="6">高强度力量</option></select></div></div><p class="energy-help" id="workout-energy-note"></p>`;
  $('.workout-progress').before(panel);$('#workout-met').value=String(w.met);
  const update=()=>{w.duration=$('#workout-duration').value===''?null:Number($('#workout-duration').value);w.met=Number($('#workout-met').value);saveDraft();$('#workout-kcal').innerHTML=`${num(w.energy?.activeKcal)}<i>kcal</i>`;$('#workout-energy-note').innerHTML=w.energyWeight?`按 ${w.energyWeight} kg · ${w.met} MET，扣除同时段静息消耗。<br>不以重量 × 次数直接换算；完成训练后计入回顾。`:'补充体重后即可估算。<button class="text-button" id="workout-profile">填写个人信息</button>';$('#workout-profile')?.addEventListener('click',()=>openProfile(()=>{w.energyWeight=state.profile?.weight??null;openWorkout()}))};
  $('#workout-duration').oninput=update;$('#workout-met').onchange=update;update();
};
const workoutDetailBeforeEnergy=openWorkoutDetail;
openWorkoutDetail=function(id){workoutDetailBeforeEnergy(id);const w=state.workouts.find(w=>w.id===id);if(!w)return;const p=document.createElement('section');p.className='energy-panel';p.innerHTML=`<span class="energy-caption">运动净消耗 · 估算</span><span class="energy-number">${num(workoutKcal(w))}<i>kcal</i></span><p class="energy-help">${w.energy?`${w.energy.minutes} 分钟 · ${w.energy.weight} kg · ${w.energy.met} MET<br>已扣除同一时段静息消耗；采用训练时的体重快照。`:'缺少时长或体重，未换算热量。'}</p>`;$('.workout-sub').after(p)};

function dateShift(date,n) {const d=new Date(date+'T12:00:00');d.setDate(d.getDate()+n);return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`}
function chartDays() {
  const demoIntake=[1850,2040,null,1970,2120,1860,805],demoActive=[160,0,null,230,180,0,138];
  return Array.from({length:energyRange},(_,i)=>{const date=dateShift(selectedDate,i-energyRange+1);if(!energySample)return dayEnergy(date);const k=(i+7-energyRange%7)%7,missing=demoIntake[k]==null,complete=!missing&&i!==energyRange-1;const base=1991,active=demoActive[k],intake=demoIntake[k];return {date,intake,active,bmr:1659,base,burn:missing?null:base+(active??0),balance:complete?intake-base-(active??0):null,complete,unknown:0,unknownWorkouts:0,meals:missing?0:i===energyRange-1?2:3,workouts:active?1:0,target:null}});
}
function energyChart(days,balance=false) {
  const W=320,H=balance?128:186,left=30,right=8,top=16,bottom=23,plotW=W-left-right,plotH=H-top-bottom,step=plotW/days.length;
  const max=balance?Math.max(500,...days.map(d=>Math.abs(d.balance??0))):Math.max(2500,...days.flatMap(d=>[d.intake??0,d.burn??0]));
  const limit=Math.ceil(max/500)*500,y=v=>balance?top+plotH/2-v/limit*(plotH/2):top+plotH-v/limit*plotH;
  const x=i=>left+step*(i+.5),ticks=balance?[limit,0,-limit]:[limit,Math.round(limit/2),0];
  let grid=ticks.map(t=>`<line x1="${left}" x2="${W-right}" y1="${y(t)}" y2="${y(t)}" stroke="var(--line)" ${t===0?'':'stroke-dasharray="2 4"'}/><text x="${left-6}" y="${y(t)+4}" text-anchor="end">${t}</text>`).join('');
  const bars=days.map((d,i)=>{const val=balance?d.balance:d.intake;if(val==null)return `<text x="${x(i)}" y="${balance?y(0)+4:top+plotH-3}" text-anchor="middle">·</text>`;const yy=balance?Math.min(y(0),y(val)):y(val),h=Math.max(1,balance?Math.abs(y(val)-y(0)):top+plotH-y(val));return `<rect x="${x(i)-Math.max(2,step*.32)}" y="${yy}" width="${Math.max(4,step*.64)}" height="${h}" rx="2" fill="${d.complete||balance?'var(--ink)':'url(#energy-hatch-intake)'}" stroke="var(--ink)" stroke-width=".6"><title>${d.date} ${balance?'摄入减消耗':'已记录摄入'} ${num(val)} kcal${d.complete?'':'，未记全'}</title></rect>`}).join('');
  let line='';if(!balance){let connected=false;for(let i=0;i<days.length;i++){const d=days[i];if(d.burn==null){connected=false;continue}line+=`${connected?'L':'M'}${x(i)},${y(d.burn)} `;connected=true}}
  return `<svg class="energy-chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="${balance?'每日摄入减估算消耗；仅显示记全日期':'每日摄入柱形图与估算消耗虚线；斜线柱代表未记全'}"><defs><pattern id="energy-hatch-${balance?'balance':'intake'}" width="5" height="5" patternUnits="userSpaceOnUse"><path d="M-1 1L1-1M0 5L5 0M4 6L6 4" stroke="var(--ink)" stroke-width=".65"/></pattern></defs>${grid}${bars}${line?`<path d="${line}" fill="none" stroke="var(--ink)" stroke-width="1.5" stroke-dasharray="4 4"/>`:''}${!balance?days.map((d,i)=>d.burn==null?'':`<circle cx="${x(i)}" cy="${y(d.burn)}" r="2.5" fill="var(--bg)" stroke="var(--ink)"/>`).join(''):''}${energyRange===30?days.filter((_,i)=>[0,7,14,21,29].includes(i)).map(d=>`<text x="${x(days.indexOf(d))}" y="${H-4}" text-anchor="middle">${Number(d.date.slice(8))}</text>`).join(''):''}</svg>`;
}
function energyReviewContent() {
  const days=chartDays(),completed=days.filter(d=>d.complete&&d.intake!=null),avg=completed.length?completed.reduce((n,d)=>n+d.intake,0)/completed.length:null;
  const activeDays=days.filter(d=>d.active!=null),sum=activeDays.length?activeDays.reduce((n,d)=>n+d.active,0):null;
  const current=days.find(d=>d.date===energyDay)||days.at(-1);energyDay=current.date;
  return `<div class="energy-sample-row"><span>${energySample?'示例数据 · 不计入你的记录':'来自已保存的记录'}</span><button id="toggle-energy-sample">${energySample?'看我的记录':'看完整示例'}</button></div>
  <div class="energy-period"><span>${days[0].date.slice(5).replace('-','/')} — ${days.at(-1).date.slice(5).replace('-','/')}</span><div class="energy-toggle">${[7,30].map(n=>`<button data-energy-range="${n}" class="${energyRange===n?'active':''}" aria-pressed="${energyRange===n}">${n} 天</button>`).join('')}</div></div>
  <div class="energy-review-top"><div><small>日均摄入 · ${completed.length} 天记全</small><span class="energy-number">${num(avg)}<i>kcal</i></span></div><div><small>累计运动净消耗</small><span class="energy-number">${num(sum)}<i>kcal</i></span></div></div>
  <div class="chart-heading"><span>吃进来，消耗掉</span><small>kcal / 天</small></div><div class="chart-legend"><span><i class="legend-fill"></i>摄入</span><span><i class="legend-dash"></i>估算总消耗</span><span>斜线 = 未记全</span></div>${energyChart(days)}
  ${energyRange===7?`<div class="chart-day-buttons" style="grid-template-columns:repeat(7,1fr)">${days.map(d=>`<button data-energy-day="${d.date}" class="${current.date===d.date?'active':''}" aria-label="查看${d.date}热量">${Number(d.date.slice(8))}</button>`).join('')}</div>`:`<div class="energy-field"><label for="energy-day-picker">查看某一天</label><select id="energy-day-picker">${days.map(d=>`<option value="${d.date}" ${current.date===d.date?'selected':''}>${shortDate(d.date)}</option>`).join('')}</select></div>`}
  <div class="chart-selected"><div class="energy-line"><span>${shortDate(current.date)} · ${current.complete?'已记全':current.recordedAll?'待补估算':'未记全'}</span><strong>${current.intake==null?'—':num(current.intake)} <small>kcal 摄入</small></strong></div><p>${current.unknown?`${current.unknown} 餐待估算 · `:''}${current.unknownWorkouts?`${current.unknownWorkouts} 次训练待估算 · `:''}${current.burn==null?'补全个人信息和训练时长后显示消耗':`估算总消耗 ${num(current.burn)} kcal`}${current.balance==null?' · 暂不判断热量盈亏':` · 差值 ${current.balance>0?'+':''}${num(current.balance)} kcal`}</p></div>
  <div class="chart-heading"><span>热量差值</span><small>摄入 − 总消耗</small></div>${energyChart(days,true)}<p class="energy-help">负值为估算缺口，正值为估算盈余。只显示记全且估算完整的日期；空点不是 0。</p>
  <div class="energy-breakdown"><div class="energy-line"><span>${shortDate(current.date)} · 静息代谢估算</span><b>${num(current.bmr)}</b></div><div class="energy-line"><span>日常活动增量</span><b>${current.base==null?'—':num(current.base-current.bmr)}</b></div><div class="energy-line"><span>已记录运动净消耗</span><b>${num(current.active)}</b></div><div class="energy-line total"><span>估算总消耗 / kcal</span><b>${num(current.burn)}</b></div></div>
  <details class="energy-table-details"><summary>查看逐日数值</summary><table class="energy-accessible-table"><thead><tr><th>日期</th><th>摄入</th><th>消耗</th><th>差值</th></tr></thead><tbody>${days.map(d=>`<tr><td>${d.date.slice(5)}${d.complete?'':' *'}</td><td>${num(d.intake)}</td><td>${num(d.burn)}</td><td>${num(d.balance)}</td></tr>`).join('')}</tbody></table><p class="energy-help">单位 kcal；* 表示未记全。消耗为模型估算，不是测量值。</p></details>`;
}
const reviewBeforeEnergy=renderReview;
renderReview=function(){
  if(reviewMode!=='热量')return reviewBeforeEnergy().replace('<div class="review-tabs">','<div class="review-tabs"><button data-review-mode="热量">热量</button>');
  return `<div class="scroll">${header('回顾')}${banner()}<div class="review-tabs">${['热量','日历','照片','训练'].map(t=>`<button data-review-mode="${t}" class="${reviewMode===t?'active':''}">${t}</button>`).join('')}</div>${energyReviewContent()}</div>${tabbar()}`;
};
const bindBeforeEnergy=bindMain;
bindMain=function(){
  bindBeforeEnergy();
  $('#toggle-energy-sample')?.addEventListener('click',()=>{energySample=!energySample;render()});
  $$('[data-energy-range]').forEach(b=>b.onclick=()=>{energyRange=Number(b.dataset.energyRange);render()});
  $$('[data-energy-day]').forEach(b=>b.onclick=()=>{const y=$('#app .scroll').scrollTop;energyDay=b.dataset.energyDay;render();$('#app .scroll').scrollTop=y});
  $('#energy-day-picker')?.addEventListener('change',e=>{const y=$('#app .scroll').scrollTop;energyDay=e.target.value;render();$('#app .scroll').scrollTop=y});
};

// Override studio routing so the additional scene never falls through to Library.
$$('[data-scene]').forEach(b=>b.onclick=()=>{closeSheet();preview='normal';const s=b.dataset.scene;if(s==='meal')openMeal();else if(s==='workout')openWorkoutStart();else if(s==='profile')openProfile();else{page=s;if(s==='review')reviewMode='热量';render()}setScene(s)});
$$('[data-ai-demo]').forEach(b=>b.onclick=()=>{openMeal();runDemoRecognition(b.dataset.aiDemo==='failed')});
persist();
render();
