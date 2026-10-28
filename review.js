/* Review owns its browsing state; it never selects or edits a home record. */
let reviewCalendarOffset=0,reviewAppliedRange=null;
function reviewRange(){const end=currentLocalDay();return reviewAppliedRange??{start:ReviewData.shift(end,-6),end}}
function reviewOpenTrend(){reviewAppliedRange=null;page='review';reviewMode='热量';render()}
function reviewEarliest(){return preview==='empty'?null:[...state.meals,...state.workouts].map(r=>r.date).filter(d=>d<=homeToday).sort()[0]??null}
function reviewPeriod(start,end){const format=d=>`${Number(d.slice(5,7))}/${Number(d.slice(8))}`;return `${start.slice(0,4)} · ${format(start)} — ${start.slice(0,4)!==end.slice(0,4)?end.slice(0,4)+' · ':''}${format(end)}`}
function reviewPager(start,end,kind,canNext){const earliest=reviewEarliest();return `<div class="review-period"><span data-review-period>${reviewPeriod(start,end)}</span><div class="review-pager"><button data-review-page="-1" data-kind="${kind}" ${!earliest||earliest>=start?'disabled':''}>上一段</button><button data-review-page="1" data-kind="${kind}" ${!canNext?'disabled':''}>下一段</button></div></div>`}
function reviewCalendar(){
  const dates=ReviewData.calendarDays(homeToday,reviewCalendarOffset),end=dates.at(-1)>homeToday?homeToday:dates.at(-1);
  const months=Array.from({length:13},(_,i)=>{const day=dates[i*7];if(i===0&&dates[7].slice(0,7)!==day.slice(0,7))return '';return i===0||day.slice(0,7)!==dates[(i-1)*7].slice(0,7)?`${Number(day.slice(5,7))}月`:''});
  const grid=(type,title,items)=>{const recorded=new Set(preview==='empty'?[]:items.map(r=>r.date));return `<section class="review-heatmap" aria-labelledby="review-${type}-title"><h3 id="review-${type}-title">${title}</h3><div class="review-heatmap-layout"><div class="review-weekdays" aria-hidden="true">${['一','','三','','五','','日'].map(d=>`<span>${d}</span>`).join('')}</div><div class="review-months" aria-hidden="true">${months.map(m=>`<span>${m}</span>`).join('')}</div><div class="review-cells" role="group" aria-label="${title}记录日历">${dates.map(day=>day>homeToday?'<span class="review-cell future" aria-hidden="true"></span>':`<span role="img" class="review-cell ${recorded.has(day)?'recorded':''}" data-record-type="${type}" data-record-day="${day}" aria-label="${day}，${title}${recorded.has(day)?'已记录':'未记录'}">${recorded.has(day)?icon(type==='meal'?'cutlery':'dumbbell','review-cell-icon'):''}</span>`).join('')}</div></div></section>`};
  return `${reviewPager(dates[0],end,'calendar',reviewCalendarOffset>0)}<div class="review-panels">${grid('meal','饮食',state.meals)}${grid('workout','训练',state.workouts)}</div><div class="review-legend" aria-hidden="true"><span><i></i>未记录</span><span><i class="recorded"></i>已记录</span></div>`;
}
function chartDays(){const {start,end}=reviewRange();return ReviewData.rangeDays(start,end).map(dayEnergy)}
function reviewCurve(days,key,pending,label){
  const values=days.map(d=>d[key]),runs=ReviewData.segments(values),maximum=ReviewData.ceiling(values),title=days.some(d=>d[pending])?'已知'+label:label;
  if(!runs.length)return `<section class="review-curve" data-curve="${key}" data-day-count="${days.length}"><div class="review-curve-heading"><h3>${title}</h3></div><p class="review-empty">暂无热量数据</p></section>`;
  const training=key==='active',layout=ReviewData.chartLayout(days.length,maximum),{x,y,baseline}=layout,barWidth=layout.width/days.length*.6;
  const point=p=>`${x(p.x).toFixed(3)},${y(p.y).toFixed(3)}`;
  const paths=training?'':runs.filter(r=>r.length>1).map(run=>`<path class="review-curve-line" d="M${point(run[0])} ${run.length===2?'L'+point(run[1]):ReviewData.controls(run).map(c=>`C${point(c.c1)} ${point(c.c2)} ${point(c.end)}`).join(' ')}"/>`).join('');
  const marks=runs.flat().map(p=>{
    const data=`data-point-day="${days[p.x].date}" data-value="${p.y}"`;
    if(!training)return `<circle cx="${x(p.x)}" cy="${y(p.y)}" r="2.7" ${data}/>`;
    return p.y===0?`<path class="review-zero" d="M${x(p.x)-barWidth/2},${baseline} h${barWidth}" ${data}/>`:`<rect class="review-bar" x="${x(p.x)-barWidth/2}" y="${y(p.y)}" width="${barWidth}" height="${baseline-y(p.y)}" ${data}/>`;
  }).join('');
  const labels=layout.labels.map(i=>`<span data-label-day="${days[i].date}" class="${days.length>7?(i===0?'first':i===days.length-1?'last':''):''}" style="left:${x(i)/layout.width*100}%">${Number(days[i].date.slice(5,7))}/${Number(days[i].date.slice(8))}</span>`).join('');
  const grid=layout.ticks.map(value=>`<path class="${value===0?'review-baseline':'review-gridline'}" data-tick-value="${value}" d="M0,${y(value)} H${layout.width}"/>`).join('');
  const dateTicks=layout.labels.map(i=>`<path class="review-date-tick" data-tick-day="${days[i].date}" d="M${x(i)},${baseline} v3"/>`).join('');
  const axis=layout.ticks.map(value=>`<span data-axis-value="${value}" style="top:${y(value)}px">${homeNumber(value)}</span>`).join('');
  const widest=layout.ticks.map(homeNumber).sort((a,b)=>b.length-a.length)[0];
  const description=days.map(d=>`${d.date}：${d[key]==null?'无有效热量':homeNumber(d[key])+' kcal'}`).join('；');
  return `<section class="review-curve" data-curve="${key}" data-chart-type="${training?'bar':'line'}" data-day-count="${days.length}"><div class="review-curve-heading"><h3>${title}</h3><span>kcal</span></div><div class="review-plot" style="--plot-height:${layout.height}px;--date-offset:${layout.dateTop-layout.height}px"><div class="review-y-axis" data-widest="${widest}" aria-hidden="true">${axis}</div><svg viewBox="0 0 ${layout.width} ${layout.height}" preserveAspectRatio="none" role="img" aria-label="${title}趋势。${description}">${grid}${dateTicks}${paths}${marks}</svg><div class="review-x-axis" aria-hidden="true">${labels}</div></div></section>`;
}
function reviewTrend(){
  const days=chartDays(),{start,end}=reviewRange();
  return `<button class="review-range-button" data-review-range aria-haspopup="dialog" aria-expanded="false" aria-label="选择日期区间，${start} 至 ${end}">${icon('calendar')}<span data-review-period>${reviewPeriod(start,end)}</span>${icon('arrow','review-range-chevron')}</button><div class="review-panels review-trends">${reviewCurve(days,'intake','unknown','摄入')}${reviewCurve(days,'active','unknownWorkouts','训练消耗')}</div>`;
}
function openReviewRange(){
  const existing=$('#review-range-panel');if(existing){existing.hidePopover();return}
  const trigger=$('[data-review-range]'),{start,end}=reviewRange();
  const panel=document.createElement('div');
  panel.className='review-range-panel';panel.id='review-range-panel';panel.setAttribute('popover','auto');
  panel.setAttribute('role','dialog');panel.setAttribute('aria-labelledby','review-range-title');
  panel.innerHTML=`<h3 id="review-range-title">日期区间</h3><label for="review-start">起始日期</label><input id="review-start" type="date" min="0001-01-01" max="${currentLocalDay()}" value="${start}" required aria-describedby="review-range-message"><label for="review-end">终止日期</label><input id="review-end" type="date" min="0001-01-01" max="${currentLocalDay()}" value="${end}" required aria-describedby="review-range-message"><p id="review-range-message" aria-live="polite">最多选择 90 天</p><div class="review-range-actions"><button data-review-cancel>取消</button><button data-review-apply>确定</button></div>`;
  $('#phone').append(panel);
  trigger.setAttribute('aria-controls',panel.id);trigger.setAttribute('aria-expanded','true');
  const first=panel.querySelector('#review-start'),last=panel.querySelector('#review-end'),apply=panel.querySelector('[data-review-apply]'),message=panel.querySelector('#review-range-message');
  const validate=()=>{
    const today=currentLocalDay();first.max=today;last.max=today;
    const error=ReviewData.rangeError(first.value,last.value,today);
    apply.disabled=!!error;message.textContent=error||'最多选择 90 天';message.classList.toggle('invalid',!!error);
    first.setAttribute('aria-invalid',String(!!error));last.setAttribute('aria-invalid',String(!!error));
    return !error;
  };
  const position=()=>{
    const anchor=trigger.getBoundingClientRect(),phone=$('#phone').getBoundingClientRect();
    const width=Math.min(320,phone.width-32,innerWidth-32);
    panel.style.width=width+'px';
    panel.style.left=Math.max(16,Math.min(anchor.left,phone.right-width-16,innerWidth-width-16))+'px';
    panel.style.top=Math.max(16,Math.min(anchor.bottom+8,innerHeight-panel.offsetHeight-16))+'px';
  };
  const onFocus=()=>validate();
  panel.addEventListener('toggle',event=>{
    if(event.newState!=='closed')return;
    window.removeEventListener('resize',position);window.removeEventListener('focus',onFocus);
    document.removeEventListener('scroll',position,true);
    panel.remove();
    const current=$('[data-review-range]');
    if(current){current.setAttribute('aria-expanded','false');current.removeAttribute('aria-controls');current.focus({preventScroll:true})}
  });
  panel.querySelector('[data-review-cancel]').onclick=()=>panel.hidePopover();
  first.oninput=last.oninput=validate;
  apply.onclick=()=>{
    if(!validate())return;
    reviewAppliedRange={start:first.value,end:last.value};
    const top=$('#app .scroll').scrollTop;
    panel.hidePopover();render();$('#app .scroll').scrollTop=top;
  };
  window.addEventListener('resize',position);window.addEventListener('focus',onFocus);
  document.addEventListener('scroll',position,true);
  validate();panel.showPopover();position();first.focus({preventScroll:true});
}
renderReview=function(){
  if(!['日历','热量'].includes(reviewMode))reviewMode='日历';
  return `<div class="scroll review-scroll">${header('回顾')}${banner()}<div class="review-switch" role="group" aria-label="回顾方式">${['日历','热量'].map(mode=>`<button data-review-mode="${mode}" class="${mode===reviewMode?'active':''}" aria-pressed="${mode===reviewMode}">${mode==='热量'?'趋势':mode}</button>`).join('')}</div>${reviewMode==='热量'?reviewTrend():reviewCalendar()}</div>${tabbar()}`;
};
const bindBeforeReview=bindMain;
bindMain=function(){
  bindBeforeReview();
  const rerender=()=>{const top=$('#app .scroll').scrollTop;render();$('#app .scroll').scrollTop=top};
  $$('[data-review-page]').forEach(b=>b.onclick=()=>{if(b.disabled)return;reviewCalendarOffset=Math.max(0,reviewCalendarOffset-Number(b.dataset.reviewPage));rerender()});
  $('[data-review-range]')?.addEventListener('click',openReviewRange);
  $$('[data-review-mode]').forEach(b=>b.onclick=()=>{reviewMode=b.dataset.reviewMode;render()});
};
render();
