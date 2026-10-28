/* Settings presentation only; existing save, consent and export actions stay in their owners. */
function mineProfileStatus(){
  const profile=state.profileHistory.length?profileAt(currentLocalDay()):state.profile;
  return profileValid(profile)?'已填写':'待填写';
}
let mineRootFocus=null;
function rememberMineFocus(){if(!document.activeElement.closest('#overlay'))mineRootFocus=document.activeElement}
renderLibrary=function(){
  const entries=[['data-profile','身体资料',mineProfileStatus()],['data-ai-settings','AI 估算','演示'],['data-management','数据管理','']];
  return `<div class="scroll mine-home">${header('我的')}${banner()}<nav class="mine-menu" aria-label="我的功能">${entries.map(([action,title,status])=>`<button class="mine-row" ${action}><span class="mine-row-title">${title}</span>${status?`<small class="mine-row-status">${status}</small>`:''}<span class="mine-chevron" aria-hidden="true">${icon('arrow')}</span></button>`).join('')}</nav></div>${tabbar()}`;
};
function styleMineSheet(kind){
  const panel=$('.sheet');panel.classList.add('mine-sheet','full',`mine-${kind}`);
  if(mineRootFocus?.isConnected)returnFocus=mineRootFocus;
  const footer=$('.sheet-foot');if(footer&&!footer.textContent.trim())footer.hidden=true;
}
const mineProfileBefore=openProfile;
openProfile=function(onDone=null){
  rememberMineFocus();
  mineProfileBefore(()=>{if(onDone)onDone();else if(page==='library')$('[data-profile]')?.focus()});styleMineSheet('profile');
  const fields=[['sex','性别',''],['age','年龄','岁'],['height','身高','cm'],['weight','体重','kg'],['activity','日常活动',''],['target','每日摄入目标','kcal']];
  for(const [key,title,unit] of fields){
    const input=$('#profile-'+key),label=document.querySelector(`label[for="profile-${key}"]`),row=label.parentElement;
    input.setAttribute('aria-label',label.textContent);label.textContent=title;row.classList.add('mine-field');
    const value=document.createElement('div');value.className='mine-field-value';input.before(value);value.append(input);
    if(unit){const suffix=document.createElement('span');suffix.className='mine-unit';suffix.textContent=unit;value.append(suffix)}
  }
  const history=document.createElement('details');history.className='detail-disclosure mine-history';
  history.innerHTML=`<summary>历史版本</summary>${state.profileHistory.length?state.profileHistory.slice().reverse().map(p=>`<p><span>${esc(p.effectiveDate)} 起生效</span><small>${esc(String(p.weight))} kg · ${esc(String(p.height))} cm</small></p>`).join(''):'<p class="helper">还没有历史版本</p>'}`;
  $('#profile-error').before(history);
  $('#save-profile').before($('#profile-error'));
  $('#save-profile').textContent='保存资料';
  $('#profile-target').placeholder='选填';
};
const mineAIBefore=openAISettings;
openAISettings=function(...args){rememberMineFocus();mineAIBefore(...args);styleMineSheet('ai');$('#sheet-title').textContent='AI 估算'};
const mineDataBefore=openDataManagement;
openDataManagement=function(...args){
  rememberMineFocus();
  mineDataBefore(...args);styleMineSheet('data');
  // Child sheets return to this page, retaining an accessible, connected focus target.
  $('[data-export-open]').addEventListener('click',event=>{event.stopImmediatePropagation();openExport({fromManagement:true})},{capture:true});
};
const mineExportBefore=openExport;
openExport=function(options={}){
  rememberMineFocus();
  mineExportBefore();styleMineSheet('export');$('#sheet-title').textContent='导出数据';
  if(options.fromManagement){
    const back=()=>{openDataManagement();$('[data-export-open]').focus()};
    $('#close-sheet').onclick=back;
    $('.sheet').addEventListener('keydown',event=>{if(event.key==='Escape'){event.stopPropagation();event.preventDefault();back()}});
  }
};
render();
