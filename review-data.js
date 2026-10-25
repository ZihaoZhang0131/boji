/* Display-only calendar arithmetic and shape-preserving interpolation. */
const ReviewData = (() => {
  const date = day => new Date(`${day}T12:00:00Z`);
  function shift(day, count) {const d=date(day);d.setUTCDate(d.getUTCDate()+count);return d.toISOString().slice(0,10)}
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
  return {shift,calendarDays,segments,controls,ceiling};
})();
if(typeof module!=='undefined')module.exports=ReviewData;
