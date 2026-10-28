/* v0.2 presentation layer: preserve the tested recording model and reduce the UI. */
const artwork = p => p === 'assets/salad.jpg' ? 'assets/bowl-line.svg' : p === 'assets/breakfast.jpg' ? 'assets/breakfast-line.svg' : p;
const shortDate = d => `${Number(d.slice(5,7))} 月 ${Number(d.slice(8))} 日`;

setScene = function(scene) {
  $$('[data-scene]').forEach(el => el.classList.toggle('active', el.dataset.scene === scene));
  const notes = {
    today: ['少一点。<br>刚刚好。', '一餐，一组。按时间留下来。', '点「饮食」或「训练」开始记录。'],
    meal: ['一餐，<br>几笔。', '照片或文字，任选一种。', '先写一句话，其他信息需要时再展开。'],
    workout: ['一次，<br>记好。', '填好保存，随时修改。', '填写动作、重量与次数，保存训练。'],
    review: ['翻一翻，<br>就想起来。', '按日查找，也可以只看照片。', '选择日期，或切换到照片和训练。'],
    library: ['留给，<br>必要的事。', '身体资料、AI 估算与数据管理。', '资料保存在本机，随时可以导出。']
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
  return `<div class="scroll">${header('薄记')}<button class="date-line" data-jump-calendar aria-label="选择日期">${shortDate(selectedDate)}<span>${weekday}</span></button>${banner()}
    <div class="feed">${all.length?all.map((e,i)=>e.type==='meal'?mealCard(e.item,i!==0):workoutCard(e.item)).join(''):`<div class="empty-state"><h3>今天还没有记录</h3><p>从下面记下一餐或一次训练。</p></div>`}</div>
    ${all.length?`<button class="completeness ${state.complete.includes(selectedDate)?'is-complete':''}" data-complete aria-pressed="${state.complete.includes(selectedDate)}"><span class="circle-check">${state.complete.includes(selectedDate)?'✓':''}</span>今天基本记全</button>`:''}
    </div><div class="quickbar"><button class="primary" data-new-meal>记饮食</button><button class="secondary" data-new-workout>记训练</button></div>${tabbar()}`;
};

mealCard = function(m,compact=false) {
  return `<article class="record-entry"><button class="entry-card record-card meal-record" data-meal="${esc(m.id)}" aria-label="编辑饮食：${esc(m.title)}"><span class="record-media">${m.photos[0]?`<img class="food-img" src="${esc(artwork(m.photos[0]))}" alt="">`:`<span class="record-title">${esc(m.title || m.note || "饮食")}</span>`}</span><div class="record-data"></div></button></article>`;
};
function workoutSymbol(w) {
  if(/上肢|胸|肩|背|手臂/.test(w.name))return 'upper-body';
  if(/下肢|腿|臀/.test(w.name))return 'lower-body';
  if(/全身/.test(w.name))return 'full-body';
  return 'dumbbell';
}
workoutCard = function(w) {
  return `<article class="record-entry"><button class="entry-card record-card training-preview" data-view-workout="${esc(w.id)}" aria-label="编辑训练：${esc(w.name)}"><span class="record-media workout-text"><strong class="record-title">${esc(w.name || "训练")}</strong><small>${countSets(w)} 组完成</small></span><div class="record-data"></div></button></article>`;
};

photoResults = function(meals) {
  const matches=meals.filter(m=>`${m.note}${m.title}${m.slot}${m.tags.join('')}`.includes(filterText));
  return matches.map(m=>`<button data-meal="${esc(m.id)}" aria-label="编辑饮食：${esc(m.title)}，${esc(m.date)}">${m.photos[0]?`<img src="${esc(artwork(m.photos[0]))}" alt="">`:`<div class="text-photo" aria-hidden="true">${icon('image')}</div>`}<div class="photo-label"><span>${m.date.slice(5).replace('-','/')}</span></div></button>`).join('')||'<p class="helper">没有找到匹配的记录。</p>';
};

renderLibrary = function() {
  const functions = [['data-profile','身体资料'],['data-ai-settings','AI 估算'],['data-management','数据管理']];
  return `<div class="scroll mine-home">${header('我的')}${banner()}<nav class="mine-menu" aria-label="我的功能">${functions.map(([action,label])=>`<button class="mine-row" ${action}><span>${label}</span><span aria-hidden="true">›</span></button>`).join('')}</nav></div>${tabbar()}`;
};

function openDataManagement() {
  sheet('数据管理', `<div class="group"><button class="setting-row" data-export-open>导出数据<span class="arrow" aria-hidden="true">›</span></button></div><p class="helper">网页原型保存在当前浏览器，可导出 JSON。自动备份、导入恢复与回收站在 iPhone App 中使用。</p>`, '', false, '返回');
  bindCommon($('.sheet-body'));
}

const bindBeforeRedesign=bindMain;
bindMain=function(){
  bindBeforeRedesign();
  $('[data-management]')?.addEventListener('click', openDataManagement);
  $('[data-jump-calendar]')?.addEventListener('click',()=>{page='review';reviewMode='日历';render()});
};

const sheetBeforeRedesign=sheet;
sheet=function(...args){sheetBeforeRedesign(...args);const o=$('#overlay');o.querySelector('.sheet-intro')?.remove();o.querySelectorAll('img').forEach(i=>i.src=artwork(i.getAttribute('src')));o.querySelectorAll('.sheet-foot > small').forEach(n=>n.classList.add('sheet-foot-note'))};

// Move the original nodes so existing input state and event handlers stay intact.
function formDisclosure(label,nodes,className='form-details') {
  const details=document.createElement('details');details.className=className;
  const summary=document.createElement('summary');summary.textContent=label;details.append(summary);
  nodes.filter(Boolean).forEach(node=>details.append(node));
  return details;
}

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
