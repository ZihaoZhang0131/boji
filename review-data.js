/* Display-only calendar arithmetic and shape-preserving interpolation. */
const ReviewData = (() => {
  const date = day => new Date(`${day}T12:00:00Z`);
  function shift(day, count) {const d=date(day);d.setUTCDate(d.getUTCDate()+count);return d.toISOString().slice(0,10)}
  function validDay(day) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || day.slice(0,4)==='0000') return false;
    const value=date(day);
    return Number.isFinite(value.getTime()) && value.toISOString().slice(0,10)===day;
  }
  function rangeError(start, end, today) {
    if (!validDay(start) || !validDay(end)) return '请选择有效的起始日期和终止日期。';
    if (start>end) return '起始日期不能晚于终止日期。';
    if (today && (start>today || end>today)) return '日期不能晚于今天。';
    if ((date(end)-date(start))/86400000+1>90) return '日期区间最多 90 天，请缩短范围。';
    return '';
  }
  function rangeDays(start, end) {
    const error=rangeError(start,end);
    if (error) throw new RangeError(error);
    return Array.from({length:Math.round((date(end)-date(start))/86400000)+1},(_,i)=>shift(start,i));
  }
  function calendarDays(today, offset=0) {
    const monday=shift(today,-((date(today).getUTCDay()+6)%7));
    const start=shift(monday,-84-Math.max(0,offset)*91);
    return Array.from({length:91},(_,i)=>shift(start,i));
  }
  function segments(values) {
    const result=[];let run=[];
    values.forEach((y,x)=>{if(Number.isFinite(y)&&y>=0)run.push({x,y});else if(run.length){result.push(run);run=[]}});
    if(run.length)result.push(run);return result;
  }
  function controls(points) {
    if(points.length<2)return [];
    const slopes=points.slice(1).map((p,i)=>p.y-points[i].y),n=points.length;
    const edge=(a,b)=>{const m=(3*a-b)/2;return Math.sign(m)!==Math.sign(a)?0:Math.sign(a)!==Math.sign(b)&&Math.abs(m)>3*Math.abs(a)?3*a:m};
    const tangent=points.map((_,i)=>n===2?slopes[0]:i===0?edge(slopes[0],slopes[1]):i===n-1?edge(slopes[n-2],slopes[n-3]):slopes[i-1]*slopes[i]<=0?0:2*slopes[i-1]*slopes[i]/(slopes[i-1]+slopes[i]));
    return points.slice(1).map((p,i)=>({start:points[i],c1:{x:points[i].x+1/3,y:points[i].y+tangent[i]/3},c2:{x:p.x-1/3,y:p.y-tangent[i+1]/3},end:p}));
  }
  function ceiling(values) {
    const max=Math.max(0,...values.filter(Number.isFinite));if(max===0)return 100;
    const step=10**Math.floor(Math.log10(max));return Math.ceil(max/step)*step;
  }
  function chartLayout(count, maximum) {
    const width=300,height=160,inset=8,baseline=height-inset;
    return {width,height,baseline,dateTop:baseline+6,
      x:index=>(index+.5)*width/count,
      y:value=>baseline-value/maximum*(height-2*inset),
      ticks:[maximum,maximum/2,0],
      labels:count<=7?Array.from({length:count},(_,i)=>i):[0,Math.floor((count-1)/2),count-1]};
  }
  return {shift,validDay,rangeError,rangeDays,calendarDays,segments,controls,ceiling,chartLayout};
})();
if(typeof module!=='undefined')module.exports=ReviewData;
