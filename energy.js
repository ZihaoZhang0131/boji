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
reviewMode='日历';

function mealSignature(m) {return JSON.stringify([m.note,m.photos]);}
function estimateMeal(kcal,items=[]) {
  return {status:'ready',source:'demo-ai',kcal,items:structuredClone(items),low:Math.round(kcal*.8),high:Math.round(kcal*1.2),model:'演示数据 · 非模型推理',version:energyVersion};
}
// Only annotate untouched, recognisable fixture records; never infer user photos.
const fixtureEnergy=Object.fromEntries(Object.entries(demoMealEnergy).map(([id,m])=>[id,[m.title,m.kcal,[]]]));
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
function recordCalories(kcal){return `<div class="meal-kcal"><b>${kcal==null?'—':`≈ ${num(kcal)}`} <small>kcal</small></b></div>`;}
mealCard=function(m,compact=false){return mealCardBeforeEnergy(m,compact).replace('<div class="record-data"></div>',`<div class="record-data">${recordCalories(mealKcal(m))}</div>`)};
const workoutCardBeforeEnergy=workoutCard;
workoutCard=function(w){return workoutCardBeforeEnergy(w).replace('<div class="record-data"></div>',`<div class="record-data">${recordCalories(workoutKcal(w))}</div>`)};

const todayBeforeEnergy=renderToday;
renderToday=function(){
  const d=dayEnergy(selectedDate);
  const summary=`<div class="energy-summary"><button data-energy-review><small>已记录摄入${d.unknown?' · 有待估算':''}</small><span class="energy-number">${num(d.intake)}<i>kcal</i></span></button><button data-energy-review><small>运动净消耗${d.unknownWorkouts?' · 有待估算':''}</small><span class="energy-number">${num(d.active)}<i>kcal</i></span></button></div>`;
  return todayBeforeEnergy().replace('<div class="feed">',`${summary}<div class="feed">`);
};

const commonBeforeEnergy=bindCommon;
bindCommon=function(root){
  commonBeforeEnergy(root);
  root.querySelectorAll('[data-profile]').forEach(b=>b.onclick=()=>openProfile());
  root.querySelectorAll('[data-ai-settings]').forEach(b=>b.onclick=()=>openAISettings());
  root.querySelectorAll('[data-energy-review]').forEach(b=>b.onclick=()=>reviewOpenTrend());
};
const sceneBeforeEnergy=setScene;
setScene=function(s){
  sceneBeforeEnergy(s);
  const notes={today:['随手记。<br>心里有数。','一餐的摄入，一次训练的消耗。都只是估算，不是分数。','点热量看趋势；点一餐查看或修正估算。'],meal:['这一餐，<br>大概多少？','照片与文字一起估算。份量、酱汁和剩余量，都可以补充。','点「体验示例识别」查看结果、调整份量。原型不发送图片。'],workout:['练过的，<br>轻轻记下。','时长、体重与训练类型，共同决定运动消耗估算。','补充本次时长；组数仍按实际完成记录。'],review:['看趋势。<br>不盯一餐。','摄入与消耗放在一起看。没记全的日子，先留白。','选择日期区间，查看摄入与训练消耗趋势。'],profile:['从自己，<br>开始算起。','基础代谢只是静息估算，不等于一天该吃多少。','填写信息实时计算，或使用示例资料体验。']};
  if(notes[s]){const n=notes[s];$('#note-title').innerHTML=n[0];$('#note-description').textContent=n[1];$('#try-copy').textContent=n[2]}
};

function openProfile(onDone=null) {
  const p=state.profile?structuredClone(state.profile):{sex:'',age:'',height:'',weight:'',activity:1.2,target:null};
  sheet('身体资料',`<div class="profile-top"><span>仅保存在本机</span><button id="profile-example">填入示例</button></div>
  <div class="form-section"><div class="energy-form-grid"><div><label for="profile-sex">公式性别参数</label><select id="profile-sex"><option value="">请选择</option><option value="male">男性公式</option><option value="female">女性公式</option></select></div><div><label for="profile-age">年龄 / 岁</label><input id="profile-age" type="number" inputmode="numeric" min="18" max="59" value="${p.age}"></div><div><label for="profile-height">身高 / cm</label><input id="profile-height" type="number" inputmode="decimal" min="100" max="230" step="0.1" value="${p.height}"></div><div><label for="profile-weight">体重 / kg</label><input id="profile-weight" type="number" inputmode="decimal" min="30" max="250" step="0.1" value="${p.weight}"></div></div>
  <div class="energy-field"><label for="profile-activity">日常活动 · 不含训练</label><select id="profile-activity"><option value="1.2">多数时间坐着</option><option value="1.35">常有站立或步行</option><option value="1.5">日常走动较多</option></select></div></div>
  <div class="profile-result metric-pair" id="profile-result" aria-live="polite"></div>
  <section class="mine-target form-section"><h3>摄入目标</h3><div class="energy-field"><label for="profile-target">每日摄入目标 / kcal</label><input id="profile-target" type="number" inputmode="numeric" min="1" max="10000" placeholder="按自己的计划填写" value="${p.target??''}"></div><p class="energy-help">留空也可使用，不自动扣减摄入。</p></section>
  <details class="detail-disclosure"><summary>估算方式与适用范围</summary><p class="energy-help">Mifflin–St Jeor 静息代谢公式。日常消耗 = 静息估算 × 活动系数；训练另计净消耗。</p><p class="energy-help">适用于 18–59 岁普通成年人。孕哺期、疾病及特殊体成分需另行评估。公式估算不替代测量或专业建议。</p></details><p id="profile-error" class="field-error" role="alert"></p>`,
  '<button class="primary" id="save-profile">保存信息</button>',true,'返回',()=>{closeSheet();if(onDone)onDone()});
  setScene('profile');$('#profile-sex').value=p.sex;$('#profile-activity').value=String(p.activity);
  const read=()=>({sex:$('#profile-sex').value,age:Number($('#profile-age').value),height:Number($('#profile-height').value),weight:Number($('#profile-weight').value),activity:Number($('#profile-activity').value),target:$('#profile-target').value===''?null:Number($('#profile-target').value)});
  const update=()=>{const v=read(),b=restingKcal(v);$('#profile-result').innerHTML=`<div><span class="energy-caption">基础代谢 · 估算</span><span class="energy-number">${num(b)}<i>kcal / 天</i></span></div><div><span class="energy-caption">日常消耗 · 不含训练</span><span class="energy-number">${b==null?'—':num(b*v.activity)}<i>kcal / 天</i></span></div>`};
  $$('#overlay input, #overlay select').forEach(el=>el.addEventListener('input',update));
  $('#profile-example').onclick=()=>{for(const k of ['sex','age','height','weight','activity'])$('#profile-'+k).value=sampleProfile[k];update();toast('已填入示例资料，不代表你的真实信息。')};
  $('#save-profile').onclick=()=>{const v=read();if(!profileValid(v)){ $('#profile-error').textContent='请填写有效信息：年龄 18–59，身高 100–230 cm，体重 30–250 kg。';return }if(v.target!=null&&(!Number.isFinite(v.target)||v.target<1||v.target>10000)){const field=$('#profile-target');$('#profile-error').textContent='每日摄入目标需为 1–10,000 kcal，或留空。';field.focus();return}
    state.profile={...v,updatedAt:new Date().toISOString()};state.profileHistory.push({...state.profile,effectiveDate:selectedDate});persist();closeSheet();render();if(onDone)onDone();toast('已保存；历史日期的代谢快照不变。')};
  update();
}

function openAISettings(onBack=null) {
  sheet('食物 AI 估算',`<p class="energy-state">演示 · 接口未连接</p><p class="energy-help">照片留在本机，不产生 API 费用。</p>
  <div class="form-section"><label class="energy-line" for="auto-estimate"><span>添加照片后自动估算</span><input id="auto-estimate" type="checkbox" ${state.energySettings.autoEstimate?'checked':''}></label><p class="energy-help">当前仅预览开关状态。</p></div>
  <details class="detail-disclosure"><summary>连接与隐私说明</summary><div class="energy-integration"><p>正式版连接模型前，会确认图片与备注的发送范围，并说明供应商、保留政策和费用。</p><p>模型估算食物与份量后，可手动修正。原型不使用 API 密钥；实际连接时凭据须安全保存，不写入页面或导出资料。</p><p>连接、授权、撤回及离线重试的完整约定见设计说明。</p></div></details>`,
  '<button class="primary" id="ai-settings-save">完成</button>',true,'返回',()=>{closeSheet();if(onBack)onBack()});
  $('#auto-estimate').onchange=e=>{state.energySettings.autoEstimate=e.target.checked;persist()};
  $('#ai-settings-save').onclick=()=>{closeSheet();if(onBack)onBack()};
}

function mealEnergyPanel(m){
  const kcal=mealKcal(m),status=m.energy?.status;
  const label=kcal!=null?`${String(kcal)} kcal`:status==='loading'?'估算中…':status==='failed'?'估算失败':status==='stale'?'待重新估算':'待估算';
  return `<div class="editor-meta-row"><span>热量</span><button class="text-button" id="${kcal!=null?'adjust-energy':'manual-energy'}" aria-label="${kcal!=null?'修改':'填写'}热量">${label}</button></div>`;
}
function updateMealPanel(){
  if(!$('#meal-energy')||!mealDraft)return;
  $('#meal-energy').innerHTML=mealEnergyPanel(mealDraft);
  $('#adjust-energy')?.addEventListener('click',openMealEnergyEditor);$('#manual-energy')?.addEventListener('click',openMealEnergyEditor);
}
const mealBeforeEnergy=renderMeal;
renderMeal=function(){
  const m=mealDraft;
  if(m.energy&&m.energy.signature!==mealSignature(m)&&['ready','manual'].includes(m.energy.status))m.energy.status='stale';
  if(!m.energy&&m.photos.length)m.energy={status:preview==='offline'?'queued':'unconfigured'};
  mealBeforeEnergy();
  const panel=document.createElement('section');panel.id='meal-energy';panel.className='editor-meal-energy';panel.setAttribute('aria-live','polite');$('.editor-meta').append(panel);
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
    if(saved&&mealSignature(saved)===signature&&saved.energy?.status==='loading'&&saved.energy.signature===signature){saved.energy=structuredClone(m.energy);persist();render()}
    if(mealDraft===m&&$('#meal-energy'))updateMealPanel();
  },900);
}
function openMealEnergyEditor() {
  const m=mealDraft,rows=structuredClone(m.energy?.items?.length?m.energy.items:[{name:'整餐',grams:null,kcal:mealKcal(m)??0}]);
  const original=structuredClone(m.energy||{});
  sheet('热量',`<div class="form-section"><div class="energy-item energy-item-head"><span>食物</span><span>克数 / g</span><span>kcal</span></div>${rows.map((r,i)=>`<div class="energy-item"><input class="energy-item-name" data-food-name="${i}" aria-label="第${i+1}项食物" value="${esc(r.name)}"><input data-food-grams="${i}" aria-label="${esc(r.name)}克数" type="number" inputmode="decimal" min="0" step="0.1" value="${r.grams??''}" placeholder="—"><input data-food-kcal="${i}" aria-label="${esc(r.name)}热量" type="number" inputmode="decimal" min="0" max="10000" value="${r.kcal}"></div>`).join('')}</div><div class="profile-result energy-line"><span class="energy-caption">合计</span><span class="energy-number" id="adjusted-total">${num(rows.reduce((n,r)=>n+r.kcal,0))}<i>kcal</i></span></div><details class="detail-disclosure"><summary>如何调整</summary><p class="energy-help">修改克数会按比例更新热量，也可直接填写 kcal。原始照片保持不变。</p></details><p id="adjust-error" class="field-error" role="alert"></p>`,
  '<button class="primary" id="save-energy-adjustment">确认调整</button>',false,'返回',renderMeal);
  const total=()=>{$('#adjusted-total').innerHTML=`${num(rows.reduce((n,r)=>n+r.kcal,0))}<i>kcal</i>`};
  $$('[data-food-grams]').forEach(input=>input.oninput=()=>{const i=+input.dataset.foodGrams,old=rows[i].grams,n=Number(input.value);if(old>0&&n>=0){rows[i].kcal=Math.round(rows[i].kcal*n/old);$(`[data-food-kcal="${i}"]`).value=rows[i].kcal}rows[i].grams=input.value===''?null:n;total()});
  $$('[data-food-kcal]').forEach(input=>input.oninput=()=>{rows[+input.dataset.foodKcal].kcal=input.value===''?NaN:Number(input.value);total()});
  $$('[data-food-name]').forEach(input=>input.oninput=()=>{rows[+input.dataset.foodName].name=input.value.trim()});
  $('#save-energy-adjustment').onclick=()=>{const sum=rows.reduce((n,r)=>n+r.kcal,0);if(rows.some(r=>!r.name||!Number.isFinite(r.kcal)||r.kcal<0||r.grams!=null&&(!Number.isFinite(r.grams)||r.grams<0))||sum>10000){$('#adjust-error').textContent='请填写食物名称和有效热量；整餐合计不超过 10,000 kcal。';return}
    m.energy={status:'manual',source:'manual',kcal:sum,items:rows,originalEstimate:original.originalEstimate||original,signature:mealSignature(m),updatedAt:new Date().toISOString()};renderMeal()};
}
const exportBeforeEnergy=openExport;
openExport=function(){exportBeforeEnergy();$('.sheet-body .helper').textContent='导出包含照片、个人身体信息、热量估算与修正记录。分享前请确认接收方；模型密钥不会写入资料包。'};

const workoutDetailBeforeEnergy=openWorkoutDetail;
openWorkoutDetail=function(id){workoutDetailBeforeEnergy(id);const w=state.workouts.find(w=>w.id===id);if(!w)return;const p=document.createElement('section');p.className='energy-panel';p.innerHTML=`<div class="energy-line"><span class="energy-caption">运动净消耗 · 估算</span><span class="energy-number">${num(workoutKcal(w))}<i>kcal</i></span></div>${w.energy?`<details class="detail-disclosure"><summary>估算方式</summary><p class="energy-help">${w.energy.automaticInputs?`按组数与次数粗估 · 每次 4 秒、组间 60 秒（默认假设） · ${w.energy.weight??"体重未知"}${w.energy.weight==null?"":" kg"}`:`${w.energy.minutes} 分钟 · ${w.energy.weight} kg · ${w.energy.met} MET。已扣除同时段静息消耗，采用训练时的体重快照。`}</p></details>`:'<p class="energy-help">缺少估算所需资料，未换算热量。</p>'}`;$('.workout-sub').after(p)};

function dateShift(date,n) {const d=new Date(date+'T12:00:00');d.setDate(d.getDate()+n);return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`}
// Override studio routing so the additional scene never falls through to Library.
$$('[data-scene]').forEach(b=>b.onclick=()=>{closeSheet();preview='normal';const s=b.dataset.scene;if(s==='meal')openMeal();else if(s==='workout')openWorkoutStart();else if(s==='profile')openProfile();else{page=s;if(s==='review')reviewMode='日历';render()}setScene(s)});
$$('[data-ai-demo]').forEach(b=>b.onclick=()=>{openMeal();runDemoRecognition(b.dataset.aiDemo==='failed')});
persist();
render();
