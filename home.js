/* Home and review share the device's local calendar day. */
let homeToday = currentLocalDay();
const homeNumber = n => n == null ? '—' : String(Math.round(n));
function homeDays(anchor = homeToday) {
  return Array.from({length:31}, (_, i) => {
    const date = new Date(`${anchor}T12:00:00`);
    date.setDate(date.getDate() + i - 15);
    return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
  });
}
function homeMealCategory(slot) {
  if (['早餐','午餐','晚餐','加餐'].includes(slot)) return slot;
  return slot === '下午茶' ? '加餐' : '饮食';
}
function homeRegionIn(text) {
  const value = text.toLowerCase();
  if (/全身|\bfull[ -]?body\b/.test(value)) return 'full-body';
  const upper = /上肢|胸|肩|背|手臂|二头|三头|卧推|推举|划船|引体|俯卧撑|\b(?:upper|bench|shoulder press|overhead press|chest press|rows?|pull[ -]?ups?|push[ -]?ups?|biceps?|hammer curls?|triceps?)\b/.test(value);
  const lower = /下肢|腿|臀|深蹲|硬拉|弓步|提踵|\b(?:lower|squats?|deadlifts?|lunges?|legs?|hips?|calf)\b/.test(value);
  if (upper && lower) return 'full-body';
  if (upper) return 'upper-body';
  if (lower) return 'lower-body';
  return /核心|腹|平板支撑|卷腹|\b(?:core|planks?|crunch(?:es)?)\b/.test(value) ? 'core' : null;
}
function homeWorkoutRegion(w) {
  return homeRegionIn(w.name || '') || homeRegionIn((w.exercises || []).map(e => e.name).join(' ')) || 'dumbbell';
}
const homeRegionLabels = {'upper-body':'上肢训练','lower-body':'下肢训练',core:'核心训练','full-body':'全身训练',dumbbell:'训练'};
// Small semantic icons use the existing monochrome pixel vocabulary.
pixelPaths.cutlery = 'M2 1h1v4h1V1h1v4h1V1h1v5H5v9H3V6H2zM12 1h2v14h-2V9h-2V4h1V2h1z';
pixelPaths.core = 'M6 0h4v4H6zM4 5h8v1h2v5h-2V8h-1v8H9v-4H7v4H5V8H4v3H2V6h2zM7 6v4h2V6z';
function homeDateStrip() {
  const weekday = ['周日','周一','周二','周三','周四','周五','周六'][new Date(`${selectedDate}T12:00:00`).getDay()];
  const heading = `${Number(selectedDate.slice(0,4))}年${Number(selectedDate.slice(5,7))}月${Number(selectedDate.slice(8))}日，${weekday}`;
  return `<section class="home-dates" aria-label="记录日期"><h2 class="home-date-heading">${heading}</h2><div class="home-date-strip" role="group" aria-label="今天前后各十五天">${homeDays().map(day => {
    const weekday = ['周日','周一','周二','周三','周四','周五','周六'][new Date(`${day}T12:00:00`).getDay()];
    return `<button data-home-date="${day}" class="home-date ${day===selectedDate?'selected':''}" aria-pressed="${day===selectedDate}" ${day===homeToday?'aria-current="date"':''} aria-label="${day} ${weekday}${day===homeToday?' 今天':''}"><b>${Number(day.slice(8))}</b></button>`;
  }).join('')}</div></section>`;
}
function homeEnergySummary() {
  const d = dayEnergy(selectedDate);
  return `<button class="home-energy" data-energy-review aria-label="查看近一周热量趋势"><span class="home-metric"><small>${d.unknown?'已知摄入':'摄入'}</small><span class="home-value" data-home-intake>${homeNumber(d.intake)}<small>kcal</small></span></span><span class="home-metric"><small>${d.unknownWorkouts?'已知训练消耗':'训练消耗'}</small><span class="home-value" data-home-burn>${homeNumber(d.active)}<small>kcal</small></span></span></button>`;
}
function homeRecordRow(type, record) {
  const symbol = type==='meal' ? 'cutlery' : homeWorkoutRegion(record);
  const label = type==='meal' ? homeMealCategory(record.slot) : homeRegionLabels[symbol];
  const value = type==='meal' ? mealKcal(record) : workoutKcal(record);
  const approximate=type==='workout'&&record.energy?.automaticInputs;
  const kcal = value==null ? '待估算' : `${approximate?'估算 ':''}${homeNumber(value)} kcal`;
  const action = type==='meal' ? `data-meal="${esc(record.id)}"` : `data-view-workout="${esc(record.id)}"`;
  return `<button class="home-record" ${action} aria-label="编辑${label}，${esc(record.time)}，${kcal}"><span class="home-record-icon">${icon(symbol)}</span><span class="home-record-copy"><strong>${label}</strong><span><time datetime="${record.date}T${record.time}">${esc(record.time)}</time></span></span><span class="home-record-energy ${value==null?'pending':''}">${value==null?'待估算':`${approximate?'≈ ':''}${homeNumber(value)}<small>kcal</small>`}</span></button>`;
}
renderToday = function() {
  const meals = preview==='empty' ? [] : state.meals.filter(m => m.date===selectedDate);
  const workouts = preview==='empty' ? [] : state.workouts.filter(w => w.date===selectedDate);
  const all = [...meals.map(item=>({type:'meal',item})), ...workouts.map(item=>({type:'workout',item}))].sort((a,b)=>b.item.time.localeCompare(a.item.time));
  return `<div class="scroll home-scroll">${homeDateStrip()}${banner()}${homeEnergySummary()}<div class="home-record-list">${all.length ? all.map(({type,item})=>homeRecordRow(type,item)).join('') : '<div class="empty-state"><h3>这天还没有记录</h3><p>从下面记下一餐或一次训练。</p></div>'}</div></div><div class="quickbar"><button class="primary" data-new-meal>记饮食</button><button class="secondary" data-new-workout>记训练</button></div>${tabbar()}`;
};
let homeScrollLeft = null;
const renderBeforeHome = render;
render = function() {
  const today = currentLocalDay();
  if (today !== homeToday) {
    if (selectedDate === homeToday && $('#overlay').hidden) selectedDate = today;
    homeToday = today;
    homeScrollLeft = null;
  }
  const previous = document.querySelector('.home-date-strip');
  const focusedDate = document.activeElement?.dataset.homeDate;
  if (previous) homeScrollLeft = previous.scrollLeft;
  if (page==='today' && !homeDays().includes(selectedDate)) selectedDate = homeToday;
  renderBeforeHome();
  const strip = document.querySelector('.home-date-strip');
  if (!strip) return;
  if (homeScrollLeft==null) {
    const selected = strip.querySelector('[aria-pressed="true"]');
    homeScrollLeft = selected.offsetLeft - (strip.clientWidth-selected.offsetWidth)/2;
  }
  strip.scrollLeft = homeScrollLeft;
  strip.addEventListener('scroll',()=>{ homeScrollLeft=strip.scrollLeft; }, {passive:true});
  let drag = null, dragged = false;
  strip.addEventListener('pointerdown', event => {
    if (event.pointerType!=='mouse' || event.button!==0) return;
    drag = {x:event.clientX, left:strip.scrollLeft}; dragged = false;
  });
  strip.addEventListener('pointermove', event => {
    if (!drag) return;
    const distance = event.clientX-drag.x;
    if (!dragged && Math.abs(distance)<=6) return;
    dragged = true; strip.setPointerCapture(event.pointerId);
    strip.classList.add('is-dragging'); strip.scrollLeft=drag.left-distance;
    event.preventDefault();
  });
  const finishDrag = event => {
    drag=null; strip.classList.remove('is-dragging');
    if (strip.hasPointerCapture(event.pointerId)) strip.releasePointerCapture(event.pointerId);
  };
  strip.addEventListener('pointerup',finishDrag);
  strip.addEventListener('pointercancel',finishDrag);
  strip.addEventListener('click',event=>{
    if (dragged) { event.preventDefault(); event.stopImmediatePropagation(); dragged=false; }
  },true);
  strip.querySelectorAll('[data-home-date]').forEach(button => button.onclick = () => {
    selectedDate=button.dataset.homeDate;
    render();
  });
  if (focusedDate) strip.querySelector(`[data-home-date="${focusedDate}"]`)?.focus({preventScroll:true});
};
function refreshLocalDay() {
  if (currentLocalDay() !== homeToday && $('#overlay').hidden) render();
}
window.addEventListener('focus', refreshLocalDay);
document.addEventListener('visibilitychange', () => { if (!document.hidden) refreshLocalDay(); });
setInterval(refreshLocalDay, 60000);
render();
