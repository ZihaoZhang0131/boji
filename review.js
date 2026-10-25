/* Review owns its browsing state; it never selects or edits a home record. */
let reviewCalendarOffset=0,reviewTrendEnd=selectedDate>homeToday?homeToday:selectedDate,reviewAnchorInput=selectedDate;
function reviewOpenTrend(){reviewTrendEnd=selectedDate>homeToday?homeToday:selectedDate;reviewAnchorInput=selectedDate;page='review';reviewMode='热量';render()}
function reviewEarliest(){return preview==='empty'?null:[...state.meals,...state.workouts].map(r=>r.date).filter(d=>d<=homeToday).sort()[0]??null}
function reviewPeriod(start,end){const format=d=>`${Number(d.slice(5,7))}/${Number(d.slice(8))}`;return `${start.slice(0,4)} · ${format(start)} — ${start.slice(0,4)!==end.slice(0,4)?end.slice(0,4)+' · ':''}${format(end)}`}
function reviewPager(start,end,kind,canNext){const earliest=reviewEarliest();return `<div class="review-period"><span data-review-period>${reviewPeriod(start,end)}</span><div class="review-pager"><button data-review-page="-1" data-kind="${kind}" ${!earliest||earliest>=start?'disabled':''}>上一段</button><button data-review-page="1" data-kind="${kind}" ${!canNext?'disabled':''}>下一段</button></div></div>`}
function reviewCalendar(){
  const dates=ReviewData.calendarDays(homeToday,reviewCalendarOffset),end=dates.at(-1)>homeToday?homeToday:dates.at(-1);
  const months=Array.from({length:13},(_,i)=>{const day=dates[i*7];if(i===0&&dates[7].slice(0,7)!==day.slice(0,7))return '';return i===0||day.slice(0,7)!==dates[(i-1)*7].slice(0,7)?`${Number(day.slice(5,7))}月`:''});
  const grid=(type,title,items)=>{const recorded=new Set(preview==='empty'?[]:items.map(r=>r.date));return `<section class="review-heatmap" aria-labelledby="review-${type}-title"><h3 id="review-${type}-title">${title}</h3><div class="review-heatmap-layout"><div class="review-weekdays" aria-hidden="true">${['一','','三','','五','','日'].map(d=>`<span>${d}</span>`).join('')}</div><div class="review-months" aria-hidden="true">${months.map(m=>`<span>${m}</span>`).join('')}</div><div class="review-cells" role="group" aria-label="${title}记录日历">${dates.map(day=>day>homeToday?'<span class="review-cell future" aria-hidden="true"></span>':`<span role="img" class="review-cell ${recorded.has(day)?'recorded':''}" data-record-type="${type}" data-record-day="${day}" aria-label="${day}，${title}${recorded.has(day)?'已记录':'未记录'}"></span>`).join('')}</div></div></section>`};
  return `${reviewPager(dates[0],end,'calendar',reviewCalendarOffset>0)}<div class="review-panels">${grid('meal','饮食',state.meals)}${grid('workout','训练',state.workouts)}</div><div class="review-legend" aria-hidden="true"><span><i></i>未记录</span><span><i class="recorded"></i>已记录</span></div>`;
}
function chartDays(){return Array.from({length:energyRange},(_,i)=>dayEnergy(ReviewData.shift(reviewTrendEnd,i-energyRange+1)))}
function reviewCurve(days,key,pending,label){
  const values=days.map(d=>d[key]),runs=ReviewData.segments(values),maximum=ReviewData.ceiling(values),title=days.some(d=>d[pending])?'已知'+label:label;
  if(!runs.length)return `<section class="review-curve" data-curve="${key}" data-day-count="${days.length}"><h3>${title}</h3><p class="review-empty">暂无热量数据</p></section>`;
  const x=i=>4+i/(days.length-1)*292,y=v=>156-v/maximum*148,point=p=>`${x(p.x).toFixed(3)},${y(p.y).toFixed(3)}`;
  const paths=runs.filter(r=>r.length>1).map(run=>`<path class="review-curve-line" d="M${point(run[0])} ${run.length===2?'L'+point(run[1]):ReviewData.controls(run).map(c=>`C${point(c.c1)} ${point(c.c2)} ${point(c.end)}`).join(' ')}"/>`).join('');
  const dots=runs.flat().map(p=>`<circle cx="${x(p.x)}" cy="${y(p.y)}" r="2.7" data-point-day="${days[p.x].date}" data-value="${p.y}"/>`).join('');
  const labels=[0,Math.floor((days.length-1)/2),days.length-1].map(i=>`${Number(days[i].date.slice(5,7))}/${Number(days[i].date.slice(8))}`);
  const description=days.map(d=>`${d.date}：${d[key]==null?'无有效热量':homeNumber(d[key])+' kcal'}`).join('；');
  return `<section class="review-curve" data-curve="${key}" data-day-count="${days.length}"><div class="review-curve-heading"><h3>${title}</h3><span>kcal</span></div><div class="review-plot"><div class="review-y-axis" aria-hidden="true"><span>${homeNumber(maximum)}</span><span>${homeNumber(maximum/2)}</span><span>0</span></div><svg viewBox="0 0 300 164" preserveAspectRatio="none" role="img" aria-label="${title}趋势。${description}"><path class="review-baseline" d="M4,156 H296"/>${paths}${dots}</svg><div class="review-x-axis" aria-hidden="true">${labels.map(t=>`<span>${t}</span>`).join('')}</div></div></section>`;
}
function reviewTrend(){const days=chartDays();return `<div class="review-ranges" role="group" aria-label="趋势范围">${[7,30].map(n=>`<button data-energy-range="${n}" class="${energyRange===n?'active':''}" aria-pressed="${energyRange===n}">${n} 天</button>`).join('')}</div>${reviewPager(days[0].date,reviewTrendEnd,'trend',reviewTrendEnd<homeToday)}<div class="review-panels">${reviewCurve(days,'intake','unknown','摄入')}${reviewCurve(days,'active','unknownWorkouts','训练消耗')}</div>`}
renderReview=function(){
  if(reviewAnchorInput!==selectedDate){reviewAnchorInput=selectedDate;reviewTrendEnd=selectedDate>homeToday?homeToday:selectedDate}
  if(!['日历','热量'].includes(reviewMode))reviewMode='日历';
  return `<div class="scroll review-scroll">${header('回顾')}${banner()}<div class="review-switch" role="group" aria-label="回顾方式">${['日历','热量'].map(mode=>`<button data-review-mode="${mode}" class="${mode===reviewMode?'active':''}" aria-pressed="${mode===reviewMode}">${mode==='热量'?'趋势':mode}</button>`).join('')}</div>${reviewMode==='热量'?reviewTrend():reviewCalendar()}</div>${tabbar()}`;
};
const bindBeforeReview=bindMain;
bindMain=function(){
  bindBeforeReview();
  const rerender=()=>{const top=$('#app .scroll').scrollTop;render();$('#app .scroll').scrollTop=top};
  $$('[data-review-page]').forEach(b=>b.onclick=()=>{if(b.disabled)return;const delta=Number(b.dataset.reviewPage);if(b.dataset.kind==='calendar')reviewCalendarOffset=Math.max(0,reviewCalendarOffset-delta);else{reviewTrendEnd=ReviewData.shift(reviewTrendEnd,delta*energyRange);if(reviewTrendEnd>homeToday)reviewTrendEnd=homeToday}rerender()});
  $$('[data-energy-range]').forEach(b=>b.onclick=()=>{energyRange=Number(b.dataset.energyRange);rerender()});
  $$('[data-review-mode]').forEach(b=>b.onclick=()=>{reviewMode=b.dataset.reviewMode;render()});
};
render();
