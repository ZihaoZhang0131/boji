/* Presentation only. Original user photos and stored records are never altered. */
const pixelPaths={
  camera:'M5 2h6v2h3v1h1v9H1V5h1V4h3z M2 6v7h12V6z M6 7h4v1h1v3h-1v1H6v-1H5V8h1z M7 8v3h2V8z',
  dumbbell:'M2 3h2v10H2zM0 5h2v6H0zM4 7h8v2H4zM12 3h2v10h-2zM14 5h2v6h-2z',
  'upper-body':'M6 1h4v4H6zM7 5h2v1h3v1h2v2h1v4h-3v-3h-1v5H5v-5H4v3H1V9h1V7h2V6h3z',
  'lower-body':'M4 1h8v5h1v8h-2V9h-1V7H9v8H7V7H6v2H5v5H3V6h1z',
  'full-body':'M6 0h4v4H6zM5 5h6v1h2v5h-2V8h-1v8H8v-5H7v5H5V8H4v3H2V6h3z',
  calendar:'M3 1h2v2h6V1h2v2h2v12H1V3h2zM2 7v7h12V7zM4 9h2v2H4zM8 9h2v2H8zM4 12h2v1H4z',
  book:'M2 1h12v14H2zM4 3v10h8V3zM3 3v10h1V3zM6 5h4v1H6zM6 8h4v1H6z',
  folder:'M1 4h5V2h5v2h4v3H1zM1 8h6v3h2V8h6v7H1zM7 7h2v2H7z',
  chart:'M2 2h1v11h12v1H2zM5 8h2v4H5zM9 5h2v7H9zM13 2h2v10h-2z',
  plus:'M7 2h2v5h5v2H9v5H7V9H2V7h5z',
  arrow:'M5 2h2v2h2v2h2v4H9v2H7v2H5v-2h2v-2h2V6H7V4H5z',
  back:'M9 2h2v2H9v2H7v4h2v2h2v2H9v-2H7v-2H5V6h2V4h2z',
  check:'M12 3h2v2h-2v2h-2v2H8v2H6v2H4v-2H2V7h2v2h2V7h2V5h2V3z',
  cloud:'M5 2h6v2h2v2h2v6H1V6h2V4h2zM3 7v3h10V7h-2V5H9V4H6v2H4v1z',
  leaf:'M7 7H4V5H2V2h4v1h2v3h1V4h2V3h4v3h-1v2h-4v5h3v2H4v-2h3z',
  sun:'M7 0h2v2H7zM7 14h2v2H7zM0 7h2v2H0zM14 7h2v2h-2zM3 2h2v2H3zM11 2h2v2h-2zM3 12h2v2H3zM11 12h2v2h-2zM5 4h6v1h1v6h-1v1H5v-1H4V5h1zM6 6v4h4V6z',
  image:'M1 2h14v12H1zM2 3v10h12V3zM3 10h2V8h2v2h2V9h2v2h2v1H3zM10 4h2v2h-2z',
  clock:'M4 1h8v1h2v2h1v8h-1v2h-2v1H4v-1H2v-2H1V4h1V2h2zM4 3v1H3v8h1v1h8v-1h1V4h-1V3zM7 4h2v4h3v2H7z',
  download:'M7 1h2v7h3v2h-2v2H6v-2H4V8h3zM2 12h2v2h8v-2h2v4H2z',
  edit:'M11 1h2v1h1v2h-1v2h-2v2H9v2H7v2H5v2H1v-4h2V8h2V6h2V4h2V2h2zM3 11v1h2v-2H4v1z',
  shield:'M7 1h2v1h3v1h2v6h-1v2h-2v2H9v2H7v-2H5v-2H3V9H2V3h2V2h3zM4 4v5h1v2h2v1h2v-1h2V9h1V4H9V3H7v1z',
  wifi:'M1 3h14v2H1zM3 7h10v2H3zM6 11h4v2H6zM7 15h2v1H7z'
};
icon=function(name,cls=''){return `<svg class="icon pixel-icon ${cls}" viewBox="0 0 16 16" aria-hidden="true"><path fill-rule="evenodd" d="${pixelPaths[name]||pixelPaths.book}"/></svg>`};
tabbar=function(){return `<nav class="tabbar" aria-label="应用导航">${[['today','book','记录'],['review','chart','回顾'],['library','folder','我的']].map(([id,i,label])=>`<button data-tab="${id}" class="${page===id?'active':''}" ${page===id?'aria-current="page"':''}>${icon(i)}<span>${label}</span></button>`).join('')}</nav>`};
const pixelSceneBefore=setScene;
setScene=function(s){pixelSceneBefore(s);if(s==='today'){$('#note-title').innerHTML='日常，<br>一格一格。';$('#note-description').textContent='把每一餐、每一组，收进自己的像素手账。';$('#try-copy').textContent='记录和热量功能照常。像素小图仅为示例，不改变上传照片。'}};
const pixelChartBefore=energyChart;
energyChart=function(...args){return pixelChartBefore(...args).replaceAll('rx="2"','rx="0"').replaceAll('stroke-width=".6"','stroke-width="1"').replace(/<circle cx="([^"]+)" cy="([^"]+)" r="2.5" fill="var\(--bg\)" stroke="var\(--ink\)"\/>/g,(_,x,y)=>`<rect x="${Math.round(Number(x))-2}" y="${Math.round(Number(y))-2}" width="4" height="4" fill="var(--bg)" stroke="var(--ink)"/>`)};
const pixelPhotoMap={
  'assets/bowl-line.svg':'assets/bowl-pixel.svg',
  'assets/breakfast-line.svg':'assets/breakfast-pixel.svg'
};
function pixelizeImages(){
  document.querySelectorAll('#app img, #overlay img').forEach(img=>{
    const src=img.getAttribute('src');
    if(pixelPhotoMap[src])img.setAttribute('src',pixelPhotoMap[src]);
    img.classList.toggle('pixel-art',Object.values(pixelPhotoMap).includes(img.getAttribute('src')));
  });
  // Some platforms fall back to a smooth system glyph for the checkmark.
  document.querySelectorAll('.set-done,.circle-check,.plan-choice > span').forEach(el=>{
    if(el.textContent.trim()==='✓')el.innerHTML=icon('check');
  });
}
const pixelObserver=new MutationObserver(pixelizeImages);
for(const el of [$('#app'),$('#overlay')])pixelObserver.observe(el,{subtree:true,childList:true,attributes:true,attributeFilter:['src']});
$('.studio .brand').insertAdjacentHTML('afterbegin',icon('leaf'));
render();pixelizeImages();
