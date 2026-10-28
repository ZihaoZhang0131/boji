const assert=require('node:assert/strict'),d=require('./review-data.js');
for(const [today,start,end]of[['2026-01-01','2025-10-06','2026-01-04'],['2024-02-29','2023-12-04','2024-03-03'],['2026-03-08','2025-12-08','2026-03-08']]){
 const days=d.calendarDays(today);assert.equal(days.length,91);assert.equal(new Set(days).size,91);assert.equal(days[0],start);assert.equal(days.at(-1),end);
 assert.equal(new Date(days[0]+'T12:00:00Z').getUTCDay(),1);assert.equal(d.shift(d.calendarDays(today,1).at(-1),1),start);
}
assert.deepEqual(d.segments([null,0,10,null,20,undefined,30,40,50]).map(r=>r.map(p=>p.x)),[[1,2],[4],[6,7,8]]);
assert.deepEqual(d.segments([null,undefined,NaN,-1]),[]);assert.equal(d.ceiling([null,0]),100);assert.equal(d.ceiling([1850,2060]),3000);
for(const values of [[0,200,2,300,0],[10,10,10],[0,0,10,10,0],[1,30000,2],[5,10],[300,20,10,0]]){
 const curves=d.controls(values.map((y,x)=>({x,y})));
 for(const c of curves){
  assert.equal(c.c1.x,c.start.x+1/3);assert.equal(c.c2.x,c.end.x-1/3);
  for(let i=0;i<=100;i++){const t=i/100,q=1-t,v=q*q*q*c.start.y+3*q*q*t*c.c1.y+3*q*t*t*c.c2.y+t*t*t*c.end.y;
   assert(v>=Math.min(c.start.y,c.end.y)-1e-8&&v<=Math.max(c.start.y,c.end.y)+1e-8,`${values}: overshoot ${v}`);
  }
 }
}
console.log('Review date and curve calculations passed');
for (const [start,end,count] of [['2026-10-09','2026-10-09',1],['2025-12-29','2026-01-04',7],['2024-02-28','2024-03-01',3],['2026-03-07','2026-03-09',3],['2026-07-12','2026-10-09',90]]) {
 const days=d.rangeDays(start,end);assert.equal(days.length,count);assert.equal(days[0],start);assert.equal(days.at(-1),end);assert.equal(new Set(days).size,count);
}
assert.match(d.rangeError('2026-07-11','2026-10-09','2026-10-09'),/90/);
assert.match(d.rangeError('2026-10-10','2026-10-11','2026-10-09'),/今天/);
assert.match(d.rangeError('2026-10-10','2026-10-09','2026-10-09'),/起始/);
for(const day of ['', '2026-02-29', '2026-13-01', '0000-01-01'])assert.match(d.rangeError(day,'2026-10-09'),/有效/);
assert.throws(()=>d.rangeDays('2026-10-10','2026-10-09'),RangeError);
