const assert = require('node:assert/strict');
async function selectReviewRange(page, start, end) {
  await page.click('[data-review-range]');
  await page.fill('#review-start', start);
  await page.fill('#review-end', end);
  assert(await page.locator('[data-review-apply]').isEnabled());
  await page.click('[data-review-apply]');
  await page.locator('#review-range-panel').waitFor({state:'detached'});
}
async function checkChartGeometry(page) {
  const charts=await page.locator('.review-curve:has(svg)').evaluateAll(sections=>sections.map(section=>{
    const svg=section.querySelector('svg'),plot=svg.getBoundingClientRect(),heading=section.querySelector('h3').getBoundingClientRect(),unit=section.querySelector('.review-curve-heading>span').getBoundingClientRect();
    const axes=[...section.querySelectorAll('[data-axis-value]')].map(el=>{
      const box=el.getBoundingClientRect(),line=section.querySelector(`[data-tick-value="${el.dataset.axisValue}"]`).getBoundingClientRect();
      return {center:box.y+box.height/2,line:line.y,right:box.right};
    });
    const dates=[...section.querySelectorAll('[data-label-day]')].map(el=>{
      const box=el.getBoundingClientRect(),tick=section.querySelector(`[data-tick-day="${el.dataset.labelDay}"]`).getBoundingClientRect();
      const mark=section.querySelector(`[data-point-day="${el.dataset.labelDay}"]`)?.getBoundingClientRect();
      return {left:box.left,right:box.right,anchor:el.classList.contains('first')?box.left:el.classList.contains('last')?box.right:box.x+box.width/2,tick:tick.x,point:mark?mark.x+mark.width/2:null};
    });
    return {left:plot.left,right:plot.right,heading:heading.left,unitGap:unit.left-heading.right,axes,dates};
  }));
  for(const chart of charts){
    assert(Math.abs(chart.left-charts[0].left)<1);assert(Math.abs(chart.right-charts[0].right)<1);
    assert(Math.abs(chart.heading-chart.left)<1);assert(Math.abs(chart.unitGap-6)<1);
    for(const axis of chart.axes){assert(Math.abs(axis.center-axis.line)<1);assert(Math.abs(chart.left-axis.right-6)<1)}
    chart.dates.forEach((date,i)=>{
      assert(Math.abs(date.anchor-date.tick)<1);
      if(date.point!==null)assert(Math.abs(date.point-date.tick)<1);
      assert(date.left>=chart.left-1&&date.right<=chart.right+1);
      if(i)assert(date.left>=chart.dates[i-1].right);
    });
  }
}
module.exports = { selectReviewRange, checkChartGeometry };
