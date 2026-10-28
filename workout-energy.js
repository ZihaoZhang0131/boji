/* Versioned assumptions for coarse estimates, never measured duration or intensity. */
(function(root) {
  const method='sets-met-net-v1';
  function inputs(exercises) {
    const data={weightedReps:0,bodyweightReps:0,setCount:0,secondsPerRep:4,restSeconds:60,weightedMET:3.5,bodyweightMET:3,restMET:1.3};
    for(const exercise of exercises)for(const set of exercise.sets){data.setCount++;data[exercise.type==='body'?'bodyweightReps':'weightedReps']+=Number(set.reps)||0}
    return data;
  }
  function estimate(exercises,weight,profileSource=null) {
    const a=inputs(exercises),weightedMinutes=a.weightedReps*a.secondsPerRep/60,bodyweightMinutes=a.bodyweightReps*a.secondsPerRep/60,restMinutes=Math.max(0,a.setCount-1)*a.restSeconds/60;
    const total=((a.weightedReps+a.bodyweightReps)*a.secondsPerRep+Math.max(0,a.setCount-1)*a.restSeconds)/60,minutes=total>0&&total<=360?Math.round(total*1e6)/1e6:null;
    const validWeight=Number.isFinite(weight)&&weight>=30&&weight<=250?weight:null;
    const raw=validWeight==null||minutes==null?null:Math.round(((a.weightedMET-1)*weightedMinutes+(a.bodyweightMET-1)*bodyweightMinutes+(a.restMET-1)*restMinutes)*3.5*validWeight/200+1e-10);
    return {method,version:'1',weight:validWeight,minutes,activeKcal:raw!=null&&raw<=100000?raw:null,automaticInputs:a,profileSource,createdAt:new Date().toISOString()};
  }
  // Input-only comparison ignores IDs, completed flags and old energy metadata.
  function signature(workout) {
    return JSON.stringify(workout.exercises.map(e=>[e.name,e.type,e.unit,e.sets.map(s=>[e.type==='body'?null:s.weight,s.reps])]));
  }
  const api={method,inputs,estimate,signature};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;
  else root.WorkoutEnergy=api;
})(typeof globalThis==='undefined'?this:globalThis);
