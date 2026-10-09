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
  const all=[...meals.map(m=>({type:'meal',time:m.time,item:m})),...workouts.map(w=>({type:'workout',time:w.time,item:w}))].sort((a,b)=>b.time.localeCompare(a.time));
  const weekday=['周日','周一','周二','周三','周四','周五','周六'][new Date(selectedDate+'T12:00:00').getDay()];
  return `<div class="scroll">${header('薄记','',`<button class="icon-button" data-jump-calendar aria-label="选择日期">${icon('calendar')}</button>`)}<div class="date-line">${shortDate(selectedDate)}<span>${weekday}</span></div>${banner()}
    ${state.draft&&preview!=='empty'?`<button class="continue-row" data-continue><span>训练进行中</span><span>继续 ${icon('arrow')}</span></button>`:''}
    <div class="feed">${all.length?all.map((e,i)=>e.type==='meal'?mealCard(e.item,i!==0):workoutCard(e.item)).join(''):`<div class="empty-state"><div class="empty-sketch">${icon('book')}</div><h3>今天，从一笔开始。</h3><button class="secondary" data-new-meal>记一餐</button></div>`}</div>
    ${all.length?`<button class="completeness ${state.complete.includes(selectedDate)?'is-complete':''}" data-complete aria-pressed="${state.complete.includes(selectedDate)}"><span class="circle-check">${state.complete.includes(selectedDate)?'✓':''}</span>今天基本记全</button>`:''}
    </div><div class="quickbar"><button class="primary" data-new-meal>${icon('camera')}饮食</button><button class="secondary" data-new-workout>${icon('dumbbell')}训练</button></div>${tabbar()}`;
};

mealCard = function(m,compact=false) {
  return `<article><div class="entry-heading"><b>${esc(m.slot==='未分类'?'饮食':m.slot)}</b><time>${esc(m.time)}</time></div><button class="entry-card ${compact?'compact':''}" data-meal="${esc(m.id)}">${m.photos[0]?`<img class="food-img" src="${esc(artwork(m.photos[0]))}" alt="${esc(m.title)}">`:''}<div class="food-info"><h3>${esc(m.title)}</h3>${m.note&&m.title!==m.note?`<p>${esc(m.note)}</p>`:''}</div></button></article>`;
};
workoutCard = function(w) {
  return `<article><div class="entry-heading"><b>训练</b><time>${esc(w.time)}</time></div><button class="entry-card training-preview" data-view-workout="${esc(w.id)}">${icon('dumbbell')}<div><h3>${esc(w.name)}</h3><p>${w.exercises.filter(e=>e.sets.some(s=>s.done)).length} 个动作 · ${countSets(w)} 组</p></div></button></article>`;
};

renderReview = function() {
  const days=new Date(reviewYear,reviewMonth+1,0).getDate(), offset=(new Date(reviewYear,reviewMonth,1).getDay()+6)%7;
  const meals=preview==='empty'?[]:state.meals, workouts=preview==='empty'?[]:state.workouts;
  const daily=meals.filter(m=>m.date===selectedDate), dayWorkouts=workouts.filter(w=>w.date===selectedDate);
  const prefix=`${reviewYear}-${String(reviewMonth+1).padStart(2,'0')}-`;
  return `<div class="scroll">${header('回顾')}${banner()}<div class="review-tabs">${['日历','照片','训练'].map(t=>`<button data-review-mode="${t}" class="${reviewMode===t?'active':''}">${t}</button>`).join('')}</div>
  ${reviewMode==='日历'?`<div class="week-head"><b>${reviewYear}.${String(reviewMonth+1).padStart(2,'0')}</b><div style="display:flex"><button data-month="-1" aria-label="上个月">${icon('back')}</button><button data-month="1" aria-label="下个月">${icon('arrow')}</button></div></div><div class="calendar">${['一','二','三','四','五','六','日'].map(t=>`<span class="weekday">${t}</span>`).join('')}${Array.from({length:offset},()=>'<span></span>').join('')}${Array.from({length:days},(_,i)=>{const d=`${prefix}${String(i+1).padStart(2,'0')}`;return `<button data-review-date="${d}" class="${selectedDate===d?'selected':''} ${meals.some(m=>m.date===d)||workouts.some(w=>w.date===d)?'recorded':''}" aria-label="${reviewMonth+1}月${i+1}日">${i+1}</button>`}).join('')}</div>
    <div class="section-line day-divider"><span>${shortDate(selectedDate)}</span><small>${daily.length+dayWorkouts.length} 条</small></div><div class="review-list">${daily.map(m=>mealCard(m,true)).join('')}${dayWorkouts.map(workoutCard).join('')}${!daily.length&&!dayWorkouts.length?`<div class="calendar-empty">没有记录<button class="text-button" data-date="${selectedDate}">补记</button></div>`:''}</div>`
  :reviewMode==='照片'?`<input class="search-field" id="search" type="search" placeholder="搜索记录" aria-label="搜索饮食记录" value="${esc(filterText)}"><div class="photo-grid" id="photo-results">${photoResults(meals)}</div>`
  :`<div class="training-totals"><b>${workouts.length}</b> 次训练<span>${workouts.reduce((n,w)=>n+countSets(w),0)} 个完成组</span></div><div class="review-list">${workouts.map(w=>`<div class="section-line"><small>${esc(w.date)}</small></div>${workoutCard(w)}`).join('')||'<div class="empty-state"><h3>还没留下训练记录。</h3></div>'}</div><button class="secondary" data-new-workout style="width:100%;margin-top:24px">记训练</button>`}</div>${tabbar()}`;
};

photoResults = function(meals) {
  const matches=meals.filter(m=>`${m.note}${m.title}${m.slot}${m.tags.join('')}`.includes(filterText));
  return matches.map(m=>`<button data-meal="${esc(m.id)}">${m.photos[0]?`<img src="${esc(artwork(m.photos[0]))}" alt="${esc(m.title)}">`:`<div class="text-photo">${esc(m.title)}</div>`}<div class="photo-label"><span>${m.date.slice(5).replace('-','/')}</span><span>${esc(m.slot)}</span></div></button>`).join('')||'<p class="helper">没有找到匹配的记录。</p>';
};

renderLibrary = function() {
  return `<div class="scroll">${header('我的')}${banner()}
    <button class="plan-row" data-open-plan><span class="row-content"><small>当前目标</small><b>${esc(state.plan.goal)}</b></span>${icon('arrow')}</button>
    <div class="group">
      <button class="setting-row" data-storage><span class="row-content"><b>全部记录</b></span><small>${state.meals.length+state.workouts.length} 条</small>${icon('arrow')}</button>
      <button class="setting-row" data-history><span class="row-content"><b>阶段历史</b></span>${icon('arrow')}</button>
    </div>
    <div class="group">
      <button class="setting-row" data-cloud><span class="row-content"><b>iCloud Drive</b></span><small>未连接</small>${icon('arrow')}</button>
      <button class="setting-row" data-export-open><span class="row-content"><b>导出记录</b></span>${icon('arrow')}</button>
      <button class="setting-row" data-agent><span class="row-content"><b>交给 Agent</b></span>${icon('arrow')}</button>
    </div>
    <div class="library-signature"><span>薄记</span><p>轻一点，记久一点。</p></div>
    </div>${tabbar()}`;
};

const bindBeforeRedesign=bindMain;
bindMain=function(){bindBeforeRedesign();$('[data-jump-calendar]')?.addEventListener('click',()=>{page='review';reviewMode='日历';render()})};

const sheetBeforeRedesign=sheet;
sheet=function(...args){sheetBeforeRedesign(...args);const o=$('#overlay');o.querySelector('.sheet-intro')?.remove();o.querySelectorAll('img').forEach(i=>i.src=artwork(i.getAttribute('src')));o.querySelector('.sheet-foot small')?.remove()};

const mealBeforeRedesign=renderMeal;
renderMeal=function(){
  mealBeforeRedesign();
  $('#sheet-title').textContent=state.meals.some(m=>m.id===mealDraft.id)?'编辑饮食':'记饮食';
  $('#add-photo').innerHTML=`${icon('camera')}<span>${mealDraft.photos.length?'添加照片':'拍照'}</span>`;
  $('#album').textContent='相册';
  $('#sample-photo').hidden=true;
  const choices=$('.photo-options'),capture=$('#add-photo');
  const mediaRow=document.createElement('div');mediaRow.className='media-row';capture.before(mediaRow);mediaRow.append(capture,choices);
  $('label[for="meal-note"]').remove();
  $('#meal-note').placeholder='吃了什么，随手记。';
  const details=document.createElement('details');details.className='meal-details';
  const summary=document.createElement('summary');summary.textContent=`${shortDate(mealDraft.date)} · ${mealDraft.time}`;
  details.append(summary);
  const timeLabel=$('label[for="meal-time"]');const body=$('.sheet-body');timeLabel.before(details);
  const nodes=[];for(let node=timeLabel;node;node=node.nextSibling)nodes.push(node);
  for(const node of nodes)if(node.id!=='meal-error')details.append(node);
  $('label[for="meal-time"]').textContent='时间';
  details.querySelectorAll('.form-label').forEach(l=>{if(!l.htmlFor)l.innerHTML=l.textContent.includes('标签')?'标签':'餐次'});
  $('#meal-time').addEventListener('change',()=>summary.textContent=$('#meal-time').value.replace('T',' · '));
  $('#save-meal').innerHTML='保存';
  const blank=document.createElement('div');blank.className='meal-sketch';blank.setAttribute('aria-hidden','true');
  blank.innerHTML='<svg viewBox="0 0 240 120"><g fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M53 46c-5 35 25 52 65 52 41 1 73-22 69-52M54 45c11-15 111-16 132 0 3 14-125 20-132 0Zm15 29c11 12 27 19 45 19m40-53 44-30m-39 34 44-28M103 23c-7-10 8-9 3-20m19 20c-7-10 8-9 3-20"/></g></svg>';
  body.append(blank);
};

const workoutBeforeRedesign=openWorkout;
openWorkout=function(){
  workoutBeforeRedesign();
  $('#sheet-title').textContent='记训练';
  $('.workout-status')?.remove();
  const sub=$('.workout-sub');sub.textContent=`${shortDate(currentWorkout.date)} · ${currentWorkout.time}`;
  $('.workout-title').style.marginTop='0';
  $('.workout-progress').lastElementChild.remove();
  $('.progress-track').classList.add('visually-hidden');
  $$('.exercise>small').forEach(e=>e.remove());
  $$('[data-done]').forEach(b=>{b.classList.toggle('unchecked',b.getAttribute('aria-pressed')!=='true');b.addEventListener('click',()=>b.classList.toggle('unchecked',b.getAttribute('aria-pressed')!=='true'))});
  $$('.add-set').forEach(b=>b.textContent='＋ 一组');
  $('#add-exercise').textContent='添加动作';$('#batch-entry').textContent='批量补记';
  const count=$('#finish-count');$('#finish-workout').replaceChildren(document.createTextNode('完成训练'));count.className='visually-hidden';$('#finish-workout').append(count);
};

const startBeforeRedesign=openWorkoutStart;
openWorkoutStart=function(){
  startBeforeRedesign();
  if(!$('#copy-workout'))return;
  $('#sheet-title').textContent='记训练';
  $('#copy-workout').querySelector('p').textContent=state.workouts.length?'沿用上次':'示例训练';
  $$('#overlay .setting-row small').forEach(e=>e.remove());
  $('#new-workout').querySelector('b').textContent='新建训练';
  $('#quick-workout').querySelector('b').textContent='批量补记';
};

const batchBeforeRedesign=openBatch;
openBatch=function(){batchBeforeRedesign();$('#sheet-title').textContent='补记训练';$('.sheet-body .helper').textContent='生成后可逐组修改。';$('#save-batch').textContent='记录完成组'};

openCloud=function(){
  sheet('iCloud Drive','<div class="cloud-note"><p>将记录导出到 iCloud Drive，<br>在 Mac 上继续查看。</p><p class="helper">正式 App 通过系统「文件」选择位置。<br>当前原型尚未连接 iCloud。</p></div>','<button class="primary" id="cloud-export">导出记录</button>',false,'返回');
  $('#cloud-export').onclick=openExport;
};

const exportBeforeRedesign=openExport;
openExport=function(){exportBeforeRedesign();$('.summary-box h3').textContent='全部记录';$('#download-json').textContent='导出';$('.sheet-body .helper').textContent='原型将图片、文字与训练明细打包为 JSON。';$('.source-label')?.remove()};

const agentBeforeRedesign=openAgent;
openAgent=function(){agentBeforeRedesign();$('#sheet-title').textContent='交给 Agent';$('.summary-box h3').textContent='复盘提示词';$('.source-label')?.remove();$('#copy-prompt').textContent='复制提示词'};

const planBeforeRedesign=openPlan;
openPlan=function(){planBeforeRedesign();$('#sheet-title').textContent='当前目标';$('label[for="plan-note"]').innerHTML='备注';$('#save-plan').textContent='保存'};

// Keep references in exported fixture data consistent with the illustrated UI.
for(const m of initial.meals)m.photos=m.photos.map(artwork);
for(const m of state.meals)m.photos=m.photos.map(artwork);
render();
