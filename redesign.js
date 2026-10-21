/* v0.2 presentation layer: preserve the tested recording model and reduce the UI. */
const artwork = p => p === 'assets/salad.jpg' ? 'assets/bowl-line.svg' : p === 'assets/breakfast.jpg' ? 'assets/breakfast-line.svg' : p;
const shortDate = d => `${Number(d.slice(5,7))} 月 ${Number(d.slice(8))} 日`;

setScene = function(scene) {
  $$('[data-scene]').forEach(el => el.classList.toggle('active', el.dataset.scene === scene));
  const notes = {
    today: ['少一点。<br>刚刚好。', '一餐，一组。按时间留下来。', '点「饮食」或「训练」开始记录。'],
    meal: ['一餐，<br>几笔。', '照片或文字，任选一种。', '先写一句话，其他信息需要时再展开。'],
    workout: ['一组，<br>一勾。', '沿用上次，确认这次。', '改一下次数，勾选实际完成的组。'],
    review: ['翻一翻，<br>就想起来。', '按日查找，也可以只看照片。', '选择日期，或切换到照片和训练。'],
    library: ['记在这里。<br>带去哪里。', '目标、记录、自己的分析方式。', '调整目标，或导出已有记录。']
  };
  const n=notes[scene]||notes.today;
  $('#note-title').innerHTML=n[0]; $('#note-description').textContent=n[1]; $('#try-copy').textContent=n[2];
};

tabbar = function() {
  return `<nav class="tabbar" aria-label="应用导航">${[['today','记录'],['review','回顾'],['library','我的']].map(([id,t])=>`<button data-tab="${id}" class="${page===id?'active':''}" ${page===id?'aria-current="page"':''}>${t}</button>`).join('')}</nav>`;
};

banner = function() { return preview==='offline' ? '<div class="offline-banner">离线 · 已保存到本机</div>' : ''; };
header = function(title,eyebrow='',right='') { return `<header class="page-head"><h2>${title}</h2>${right}</header>`; };

renderToday = function() {
  const meals=preview==='empty'?[]:state.meals.filter(m=>m.date===selectedDate);
  const workouts=preview==='empty'?[]:state.workouts.filter(w=>w.date===selectedDate);
  if(preview!=='empty'&&state.draft?.date===selectedDate){
    const index=workouts.findIndex(w=>w.id===state.draft.id);
    if(index<0)workouts.push(state.draft);else workouts[index]=state.draft;
  }
  const all=[...meals.map(m=>({type:'meal',time:m.time,item:m})),...workouts.map(w=>({type:'workout',time:w.time,item:w}))].sort((a,b)=>b.time.localeCompare(a.time));
  const weekday=['周日','周一','周二','周三','周四','周五','周六'][new Date(selectedDate+'T12:00:00').getDay()];
  return `<div class="scroll">${header('薄记','',`<button class="icon-button" data-jump-calendar aria-label="选择日期">${icon('calendar')}</button>`)}<div class="date-line">${shortDate(selectedDate)}<span>${weekday}</span></div>${banner()}
    <div class="feed">${all.length?all.map((e,i)=>e.type==='meal'?mealCard(e.item,i!==0):workoutCard(e.item)).join(''):`<div class="empty-state"><div class="empty-sketch">${icon('book')}</div><h3>今天，从一笔开始。</h3><button class="secondary" data-new-meal>记一餐</button></div>`}</div>
    ${all.length?`<button class="completeness ${state.complete.includes(selectedDate)?'is-complete':''}" data-complete aria-pressed="${state.complete.includes(selectedDate)}"><span class="circle-check">${state.complete.includes(selectedDate)?'✓':''}</span>今天基本记全</button>`:''}
    </div><div class="quickbar"><button class="primary" data-new-meal>${icon('camera')}饮食</button><button class="secondary" data-new-workout>${icon('dumbbell')}训练</button></div>${tabbar()}`;
};

mealCard = function(m,compact=false) {
  return `<article class="record-entry"><button class="entry-card record-card meal-record" data-meal="${esc(m.id)}" aria-label="查看饮食：${esc(m.title)}"><span class="record-media">${m.photos[0]?`<img class="food-img" src="${esc(artwork(m.photos[0]))}" alt="">`:icon('image')}</span><div class="record-data"></div></button></article>`;
};
function workoutSymbol(w) {
  if(/上肢|胸|肩|背|手臂/.test(w.name))return 'upper-body';
  if(/下肢|腿|臀/.test(w.name))return 'lower-body';
  if(/全身/.test(w.name))return 'full-body';
  return 'dumbbell';
}
workoutCard = function(w) {
  return `<article class="record-entry"><button class="entry-card record-card training-preview" data-view-workout="${esc(w.id)}" aria-label="编辑训练：${esc(w.name)}${state.draft?.id===w.id?'，草稿':''}"><span class="record-media workout-symbol" data-workout-symbol="${workoutSymbol(w)}">${icon(workoutSymbol(w))}</span><div class="record-data"></div></button></article>`;
};

renderReview = function() {
  const days=new Date(reviewYear,reviewMonth+1,0).getDate(), offset=(new Date(reviewYear,reviewMonth,1).getDay()+6)%7;
  const meals=preview==='empty'?[]:state.meals, workouts=preview==='empty'?[]:state.workouts;
  const daily=meals.filter(m=>m.date===selectedDate), dayWorkouts=workouts.filter(w=>w.date===selectedDate);
  const prefix=`${reviewYear}-${String(reviewMonth+1).padStart(2,'0')}-`;
  return `<div class="scroll">${header('回顾')}${banner()}<div class="review-tabs">${['日历','照片','训练'].map(t=>`<button data-review-mode="${t}" class="${reviewMode===t?'active':''}">${t}</button>`).join('')}</div>
  ${reviewMode==='日历'?`<div class="week-head"><b>${reviewYear}.${String(reviewMonth+1).padStart(2,'0')}</b><div style="display:flex"><button data-month="-1" aria-label="上个月">${icon('back')}</button><button data-month="1" aria-label="下个月">${icon('arrow')}</button></div></div><div class="calendar">${['一','二','三','四','五','六','日'].map(t=>`<span class="weekday">${t}</span>`).join('')}${Array.from({length:offset},()=>'<span></span>').join('')}${Array.from({length:days},(_,i)=>{const d=`${prefix}${String(i+1).padStart(2,'0')}`;return `<button data-review-date="${d}" class="${selectedDate===d?'selected':''} ${meals.some(m=>m.date===d)||workouts.some(w=>w.date===d)?'recorded':''}" aria-label="${reviewMonth+1}月${i+1}日">${i+1}</button>`}).join('')}</div>
    <div class="section-line day-divider"><span>${shortDate(selectedDate)}</span><small>${daily.length+dayWorkouts.length} 条</small></div><div class="review-list record-grid">${daily.map(m=>mealCard(m,true)).join('')}${dayWorkouts.map(workoutCard).join('')}${!daily.length&&!dayWorkouts.length?`<div class="calendar-empty">没有记录<button class="text-button" data-date="${selectedDate}">补记</button></div>`:''}</div>`
  :reviewMode==='照片'?`<input class="search-field" id="search" type="search" placeholder="搜索记录" aria-label="搜索饮食记录" value="${esc(filterText)}"><div class="photo-grid" id="photo-results">${photoResults(meals)}</div>`
  :`<div class="training-totals"><b>${workouts.length}</b> 次训练<span>${workouts.reduce((n,w)=>n+countSets(w),0)} 个完成组</span></div><div class="review-list record-grid">${workouts.map(w=>`<section class="training-day"><small class="record-date">${esc(w.date)}</small>${workoutCard(w)}</section>`).join('')||'<div class="empty-state"><h3>还没留下训练记录。</h3></div>'}</div><button class="secondary" data-new-workout style="width:100%;margin-top:24px">记训练</button>`}</div>${tabbar()}`;
};

photoResults = function(meals) {
  const matches=meals.filter(m=>`${m.note}${m.title}${m.slot}${m.tags.join('')}`.includes(filterText));
  return matches.map(m=>`<button data-meal="${esc(m.id)}" aria-label="查看饮食：${esc(m.title)}，${esc(m.date)}">${m.photos[0]?`<img src="${esc(artwork(m.photos[0]))}" alt="">`:`<div class="text-photo" aria-hidden="true">${icon('image')}</div>`}<div class="photo-label"><span>${m.date.slice(5).replace('-','/')}</span></div></button>`).join('')||'<p class="helper">没有找到匹配的记录。</p>';
};

renderLibrary = function() {
  return `<div class="scroll">${header('我的')}${banner()}
    <section class="settings-section"><h3 class="section-label">个人与目标</h3>
    <div class="group"><button class="setting-row" data-open-plan><span class="row-content"><b>阶段目标</b></span><small>${esc(state.plan.goal)}</small>${icon('arrow')}</button></div></section>
    <section class="settings-section"><h3 class="section-label">记录</h3>
    <div class="group">
      <button class="setting-row" data-storage><span class="row-content"><b>全部记录</b></span><small>${state.meals.length+state.workouts.length} 条</small>${icon('arrow')}</button>
      <button class="setting-row" data-history><span class="row-content"><b>阶段历史</b></span>${icon('arrow')}</button>
    </div></section>
    <section class="settings-section"><h3 class="section-label">资料管理</h3>
    <div class="group">
      <button class="setting-row" data-export-open><span class="row-content"><b>导出记录</b></span>${icon('arrow')}</button>
      <button class="setting-row" data-agent><span class="row-content"><b>Agent 复盘</b></span>${icon('arrow')}</button>
      <button class="setting-row" data-cloud><span class="row-content"><b>iCloud Drive</b></span><small>未连接</small>${icon('arrow')}</button>
    </div></section>
    <p class="library-local-note">记录保存在本机</p>
    </div>${tabbar()}`;
};

const bindBeforeRedesign=bindMain;
bindMain=function(){bindBeforeRedesign();$('[data-jump-calendar]')?.addEventListener('click',()=>{page='review';reviewMode='日历';render()})};

const sheetBeforeRedesign=sheet;
sheet=function(...args){sheetBeforeRedesign(...args);const o=$('#overlay');o.querySelector('.sheet-intro')?.remove();o.querySelectorAll('img').forEach(i=>i.src=artwork(i.getAttribute('src')));o.querySelectorAll('.sheet-foot > small').forEach(n=>n.classList.add('sheet-foot-note'))};

// Move the original nodes so existing input state and event handlers stay intact.
function formDisclosure(label,nodes,className='form-details') {
  const details=document.createElement('details');details.className=className;
  const summary=document.createElement('summary');summary.textContent=label;details.append(summary);
  nodes.filter(Boolean).forEach(node=>details.append(node));
  return details;
}

const mealBeforeRedesign=renderMeal;
renderMeal=function(){
  mealBeforeRedesign();
  $('#sheet-title').textContent=state.meals.some(m=>m.id===mealDraft.id)?'编辑饮食':'记饮食';
  $('#add-photo').innerHTML=`${icon('camera')}<span>${mealDraft.photos.length?'添加照片':'拍照'}</span>`;
  $('#add-photo').setAttribute('aria-label',`添加照片，当前 ${mealDraft.photos.length} 张，最多 9 张`);
  $('#album').textContent='相册';
  $('#sample-photo').hidden=true;
  const choices=$('.photo-options'),capture=$('#add-photo');
  const mediaRow=document.createElement('div');mediaRow.className='media-row';capture.before(mediaRow);mediaRow.append(capture,choices);
  $('label[for="meal-note"]').classList.add('visually-hidden');
  $('#meal-note').placeholder='吃了什么？份量、做法或剩余量';
  const details=document.createElement('details');details.className='meal-details';
  const summary=document.createElement('summary');summary.textContent='时间、餐次与标签';
  details.append(summary);
  const timeLabel=$('label[for="meal-time"]');const body=$('.sheet-body');timeLabel.before(details);
  const nodes=[];for(let node=timeLabel;node;node=node.nextSibling)nodes.push(node);
  for(const node of nodes)if(node.id!=='meal-error')details.append(node);
  $('label[for="meal-time"]').textContent='时间';
  details.querySelectorAll('.form-label').forEach(l=>{if(!l.htmlFor)l.innerHTML=l.textContent.includes('标签')?'标签':'餐次'});
  $('#save-meal').innerHTML='保存';
  $('.sheet-foot-note')?.remove();
};

const mealDetailBeforeRedesign=openMealDetail;
openMealDetail=function(id){
  mealDetailBeforeRedesign(id);
  const m=state.meals.find(meal=>meal.id===id);if(!m)return;
  $('#sheet-title').textContent='饮食';
  const body=$('.sheet-body'),heading=body.querySelector('h3');
  heading.className='visually-hidden';heading.removeAttribute('style');
  const note=body.querySelector('.detail-note');if(!m.note.trim())note.remove();
  const metadata=body.querySelector('.eyebrow');metadata.className='sheet-context';metadata.removeAttribute('style');
  const slot=document.createElement('p');slot.className='sheet-context';slot.textContent=m.slot==='未分类'?'未分类':m.slot;
  const tags=body.querySelector('.tags');if(!m.tags.length)tags.remove();
  const details=formDisclosure('记录信息',[metadata,slot,m.tags.length?tags:null,body.querySelector('.source-label')]);
  body.append(details);
  $('#edit-meal').textContent='编辑';$('#delete-meal').textContent='删除记录';
};

const workoutBeforeRedesign=openWorkout;
openWorkout=function(){
  workoutBeforeRedesign();
  const editing=state.workouts.some(w=>w.id===currentWorkout.id);
  $('#sheet-title').textContent=editing?'编辑训练':'记训练';
  $('.workout-status')?.remove();
  const sub=$('.workout-sub');sub.textContent=`${shortDate(currentWorkout.date)} · ${currentWorkout.time}`;
  $('.workout-title').style.marginTop='0';
  $('.workout-progress').lastElementChild.remove();
  $('.progress-track').classList.add('visually-hidden');
  $$('.exercise>small').forEach(e=>e.remove());
  $$('[data-done]').forEach(b=>{b.classList.toggle('unchecked',b.getAttribute('aria-pressed')!=='true');b.addEventListener('click',()=>b.classList.toggle('unchecked',b.getAttribute('aria-pressed')!=='true'))});
  $$('.add-set').forEach(b=>b.textContent='＋ 一组');
  $('#add-exercise').textContent='添加动作';$('#batch-entry').textContent='批量补记';
  const count=$('#finish-count');$('#finish-workout').replaceChildren(document.createTextNode(editing?'保存修改':'完成训练'));count.className='visually-hidden';$('#finish-workout').append(count);
  $('.sheet-foot-note').textContent='仅保存已勾选的组';
};

const startBeforeRedesign=openWorkoutStart;
openWorkoutStart=function(){
  startBeforeRedesign();
  if(!$('#copy-workout'))return;
  $('#sheet-title').textContent='记训练';
  const copy=$('#copy-workout');copy.className='setting-row workout-copy';
  copy.querySelector('p').textContent=state.workouts.length?'沿用上次 · 逐组确认':'示例训练 · 逐组确认';
  copy.querySelector('div').classList.add('row-content');
  $$('#overlay .setting-row small').forEach(e=>e.remove());
  $('#new-workout').querySelector('b').textContent='新建训练';
  $('#quick-workout').querySelector('b').textContent='批量补记';
  const group=$('#new-workout').parentElement;group.style.marginTop='0';group.prepend(copy);
};

const batchBeforeRedesign=openBatch;
openBatch=function(){
  batchBeforeRedesign();$('#sheet-title').textContent='补记训练';
  $('.sheet-body .helper').textContent='杠铃重量含杆；生成后可逐组修改。';
  const timeLabel=$('label[for="batch-time"]'),time=$('#batch-time');
  const details=formDisclosure('训练时间',[timeLabel,time]);$('.sheet-body .helper').before(details);
  $('#save-batch').textContent='添加完成组';
};

const exerciseBeforeRedesign=openExercisePicker;
openExercisePicker=function(){
  exerciseBeforeRedesign();
  const label=$('label[for="custom-exercise"]'),input=$('#custom-exercise'),save=$('#save-custom');
  label.textContent='动作名称';save.textContent='添加';
  $('.sheet-body').append(formDisclosure('自定义动作',[label,input,save]));
};

openCloud=function(){
  sheet('iCloud Drive','<div class="cloud-note"><p>当前原型尚未连接 iCloud。</p><p class="helper">可先导出 JSON，再将文件存入 iCloud Drive。</p><details class="form-details"><summary>同步说明</summary><p class="helper">正式 App 通过系统「文件」选择资料文件夹。此原型不会自动同步或上传记录。</p></details></div>','<button class="primary" id="cloud-export">导出记录</button>',false,'返回');
  $('#cloud-export').onclick=openExport;
};

const exportBeforeRedesign=openExport;
openExport=function(){
  exportBeforeRedesign();$('.summary-box h3').textContent='全部记录';$('#download-json').textContent='导出 JSON';
  $('.sheet-body .helper').textContent='图片、文字、训练和目标保存在同一份 JSON 中。';
  const source=$('.sheet-body .source-label');source.textContent='包含示例记录，请在复盘时与真实记录区分。';
  $('#export-error').before(formDisclosure('文件说明',[source]));
};

const agentBeforeRedesign=openAgent;
openAgent=function(){
  agentBeforeRedesign();$('#sheet-title').textContent='Agent 复盘';$('.summary-box h3').textContent='复盘提示词';
  const instructions=$('.sheet-body .helper');instructions.textContent='导出记录，将 JSON 交给你的 Agent，再粘贴上方提示词。';
  const boundary=$('.sheet-body .source-label');boundary.textContent='本页只复制提示词，不调用模型。导出含个人记录，分享前请确认接收方。';
  $('.sheet-body').append(formDisclosure('使用说明',[instructions,boundary]));
  $('#copy-prompt').textContent='复制提示词';
};

const planBeforeRedesign=openPlan;
openPlan=function(){
  planBeforeRedesign();$('#sheet-title').textContent='阶段目标';$('label[for="plan-note"]').textContent='备注';
  const label=$('label[for="plan-note"]'),note=$('#plan-note');note.placeholder='补充自己的计划';
  const details=formDisclosure('补充备注',[label,note]);details.open=!!state.plan.note;$('.sheet-body').append(details);
  $('#save-plan').textContent='保存';
};

// Keep references in exported fixture data consistent with the illustrated UI.
for(const m of initial.meals)m.photos=m.photos.map(artwork);
for(const m of state.meals)m.photos=m.photos.map(artwork);
render();
