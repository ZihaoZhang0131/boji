/* Atomic training form: all input remains in this sheet until Save. */
function openWorkoutStart(){
  const now=new Date(),time=`${String(now.getHours()).padStart(2,'0')}:${String(now.getMinutes()).padStart(2,'0')}`;
  currentWorkout={id:uid(),name:'',date:selectedDate,time,exercises:[]};
  openWorkout();
}
function openWorkout(){
  const w=currentWorkout,original=state.workouts.find(item=>item.id===w.id);
  sheet(original?'编辑训练':'记训练','<div class="workout-exercises"></div><div id="exercise-picker-slot"></div><p class="field-error" id="workout-error" role="alert"></p>',
    '<button class="secondary" id="discard-workout">放弃</button><button class="primary" id="save-workout">保存</button>',true,'放弃');
  const dialog=$('.sheet'),body=$('.sheet-body');dialog.classList.add('record-editor','workout-editor');setScene('workout');
  // Retain the sheet's Escape handler, without a second visible exit in the header.
  const close=$('#close-sheet');close.hidden=true;close.tabIndex=-1;
  dialog.querySelector('.sheet-head').append(close);
  $('#sheet-title').tabIndex=-1;$('#sheet-title').focus({preventScroll:true});
  $('#discard-workout').onclick=()=>{closeSheet();render()};
  const cards=new Map();let pickerOpen=!w.exercises.length,customName='',customKind='weight';
  const error=(message,input)=>{ $('#workout-error').textContent=message;if(input){input.setAttribute('aria-invalid','true');input.focus();input.scrollIntoView({block:'nearest'})} };
  const weightHeading=e=>e.unit?.includes('单只')?'单只 kg':e.unit?.includes('含杆')?'含杆 kg':!e.unit||e.unit.includes('总重量')?'kg':/kg/i.test(e.unit)?e.unit:`${e.unit} kg`;
  const indexInputs=()=>{w.exercises.forEach((e,ei)=>{const card=cards.get(e);card.dataset.exerciseIndex=ei;card.querySelector('[data-add-set]').dataset.addSet=ei;card.querySelector('[data-less-set]').dataset.lessSet=ei;
    [...card.querySelectorAll('tbody tr')].forEach((row,si)=>row.querySelectorAll('input').forEach(input=>input.dataset.set=`${ei},${si},${input.dataset.field}`))})};
  function makeRow(e,s,si){
    const row=document.createElement('tr');row.innerHTML=`<td>${si+1}</td>${e.type==='body'?'':`<td><input aria-label="${esc(e.name)}第${si+1}组重量（${esc(weightHeading(e))}）" data-field="weight" inputmode="decimal" type="number" min="0" max="1000" step="any" value="${s.weight??''}" placeholder="—"></td>`}<td><input aria-label="${esc(e.name)}第${si+1}组次数" data-field="reps" inputmode="numeric" type="number" min="1" max="999" step="1" value="${s.reps??''}" placeholder="—"></td>`;
    row.querySelectorAll('input').forEach(input=>input.oninput=()=>{s[input.dataset.field]=input.value===''?null:Number(input.value);input.removeAttribute('aria-invalid');$('#workout-error').textContent=''});
    return row;
  }
  function updateCount(e){const card=cards.get(e);card.querySelector('.set-count').textContent=`${e.sets.length} 组`;card.querySelector('[data-less-set]').disabled=e.sets.length<=1;indexInputs()}
  function appendCard(e){
    const card=document.createElement('section');card.className='exercise workout-exercise-card';
    card.innerHTML=`<div class="exercise-heading"><h3>${esc(e.name)}</h3><button class="text-button" aria-label="删除${esc(e.name)}" data-remove-exercise>删除</button></div><table class="set-table"><thead><tr><th scope="col">组</th>${e.type==='body'?'':`<th scope="col">${esc(weightHeading(e))}</th>`}<th scope="col">次</th></tr></thead><tbody></tbody></table><div class="set-stepper"><button data-less-set aria-label="${esc(e.name)}减少一组">${icon('minus')}</button><span class="set-count" aria-live="polite"></span><button data-add-set aria-label="${esc(e.name)}增加一组">${icon('plus')}</button></div>`;
    cards.set(e,card);e.sets.forEach((s,i)=>card.querySelector('tbody').append(makeRow(e,s,i)));$('.workout-exercises').append(card);
    card.querySelector('[data-remove-exercise]').onclick=()=>{w.exercises.splice(w.exercises.indexOf(e),1);card.remove();cards.delete(e);indexInputs();if(!w.exercises.length)pickerOpen=true;renderPicker()};
    card.querySelector('[data-add-set]').onclick=()=>{const last=e.sets.at(-1)||{weight:null,reps:null},set={...last,done:false};delete set.id;e.sets.push(set);card.querySelector('tbody').append(makeRow(e,set,e.sets.length-1));updateCount(e)};
    card.querySelector('[data-less-set]').onclick=()=>{if(e.sets.length<=1)return;e.sets.pop();card.querySelector('tbody tr:last-child').remove();updateCount(e)};
  }
  function add(name,type){
    const scroll=body.scrollTop,e={name,unit:type==='body'?'自重':name.includes('哑铃')?'单只重量':'总重量',type,sets:[{weight:null,reps:null,done:false}]};
    w.exercises.push(e);appendCard(e);updateCount(e);pickerOpen=false;customName='';renderPicker();body.scrollTop=scroll;
  }
  function renderPicker(){
    const slot=$('#exercise-picker-slot');
    if(!pickerOpen&&w.exercises.length){slot.innerHTML='<button class="secondary editor-add-exercise" id="add-exercise" aria-expanded="false">添加动作</button>';$('#add-exercise').onclick=()=>{pickerOpen=true;renderPicker()};return}
    slot.innerHTML=`<div class="editor-exercise-options">${['杠铃卧推','杠铃深蹲','硬拉','哑铃划船','引体向上','俯卧撑'].map(name=>`<button data-exercise="${name}">${name}</button>`).join('')}</div><div class="editor-custom-exercise"><label class="visually-hidden" for="custom-exercise">其他动作</label><input id="custom-exercise" placeholder="其他动作" value="${esc(customName)}"><div class="custom-exercise-actions" ${customName.trim()?'':'hidden'}><select id="custom-kind" aria-label="动作类型"><option value="weight">负重</option><option value="body">自重</option></select><button class="text-button" id="save-custom">添加</button></div></div>${w.exercises.length?'<button class="text-button collapse-exercises" id="collapse-exercises">收起</button>':''}`;
    slot.querySelectorAll('[data-exercise]').forEach(button=>button.onclick=()=>add(button.dataset.exercise,/引体向上|俯卧撑/.test(button.dataset.exercise)?'body':'weight'));
    $('#custom-exercise').oninput=e=>{customName=e.target.value;$('.custom-exercise-actions').hidden=!customName.trim()};
    $('#custom-kind').value=customKind;$('#custom-kind').onchange=e=>customKind=e.target.value;
    $('#save-custom').onclick=()=>{if(customName.trim())add(customName.trim(),customKind)};
    $('#collapse-exercises')?.addEventListener('click',()=>{pickerOpen=false;renderPicker()});
  }
  w.exercises.forEach(appendCard);w.exercises.forEach(updateCount);renderPicker();
  $('#save-workout').onclick=()=>{
    if(!w.exercises.length)return error('请添加至少一个动作。');
    for(let ei=0;ei<w.exercises.length;ei++){
      const e=w.exercises[ei];
      if(!e.name.trim()||!e.sets.length)return error('请为每个动作填写至少一组，或删除该动作。');
      for(let si=0;si<e.sets.length;si++){
        const s=e.sets[si];
        if(e.type!=='body'&&(s.weight==null||!Number.isFinite(s.weight)||s.weight<0||s.weight>1000))return error(`${e.name}第${si+1}组：请填写 0–1000 kg 的重量。`,$(`[data-set="${ei},${si},weight"]`));
        if(!Number.isInteger(s.reps)||s.reps<1||s.reps>999)return error(`${e.name}第${si+1}组：次数须为 1–999 的整数。`,$(`[data-set="${ei},${si},reps"]`));
      }
    }
    const record=structuredClone(w);record.exercises.forEach(e=>e.sets.forEach(s=>s.done=true));
    if(!original||WorkoutEnergy.signature(original)!==WorkoutEnergy.signature(record)){
      const profile=profileAt(record.date),weight=original?.energy?original.energy.weight:profile?.weight??null;
      record.energy=WorkoutEnergy.estimate(record.exercises,weight,original?.energy?original.energy.profileSource??null:profile?{effectiveDate:profile.effectiveDate,updatedAt:profile.updatedAt??null}:null);
      record.energyHistory=[...(original?.energyHistory|| (original?.energy?[original.energy]:[])),structuredClone(record.energy)];
    }
    record.updated_at=new Date().toISOString();
    const previous=state.workouts,index=previous.findIndex(item=>item.id===record.id);
    state.workouts=index<0?[...previous,record]:previous.map(item=>item.id===record.id?record:item);
    if(!persist()){state.workouts=previous;return error('保存失败，请释放浏览器存储空间后重试。')}
    selectedDate=record.date;page='today';preview='normal';closeSheet();render();toast('训练已保存。');
  };
}
// Safari's visual viewport shrinks with its keyboard even when the layout viewport does not.
function sizeWorkoutViewport(){
  const viewport=window.visualViewport;if(!viewport)return;
  document.documentElement.style.setProperty('--workout-viewport-height',`${viewport.height}px`);
  document.documentElement.style.setProperty('--workout-viewport-top',`${viewport.offsetTop}px`);
}
window.visualViewport?.addEventListener('resize',sizeWorkoutViewport);
window.visualViewport?.addEventListener('scroll',sizeWorkoutViewport);
sizeWorkoutViewport();
