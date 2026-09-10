// Real DOM regression fixture; only this test page exposes the lexical test bridge.
const output=document.querySelector('#results'),status=document.querySelector('#status');
const tick=()=>new Promise(r=>setTimeout(r,0));
const check=(ok,message='assertion failed')=>{if(!ok)throw new Error(message)};
document.querySelector('#run').onclick=async()=>{
  document.querySelector('#run').disabled=true;output.textContent='';status.textContent='正在运行';
  let frame,tests=[],pages=[],mobile=[],buttonClicks=[];
  const test=async(name,fn)=>{try{const evidence=await fn();tests.push({name,status:'PASS',evidence})}catch(e){tests.push({name,status:'FAIL',error:e.message})}status.textContent=`已完成 ${tests.length} 项：${tests.filter(t=>t.status==='FAIL').length} 项失败`};
  try{
    let html=await (await fetch('../index.html')).text();
    let isolation=`<script>const testStorage=new Map();Object.defineProperty(window,'localStorage',{value:{getItem:k=>testStorage.get(k)||null,setItem:(k,v)=>testStorage.set(k,String(v)),removeItem:k=>testStorage.delete(k)}});window.confirm=()=>false;window.prompt=()=>null;<\/script>`;
    html=html.replace('<head>','<head><base href="/">'+isolation).replace('</script></body>',`window.testRun=code=>eval(code);clearInterval(timer);S.auto=false;<\/script></body>`);
    frame=document.createElement('iframe');frame.width='1280';frame.height='900';frame.title='游戏测试视口';frame.srcdoc=html;
    const loaded=new Promise(resolve=>frame.onload=resolve);document.querySelector('#fixture').replaceChildren(frame);await loaded;
    const w=frame.contentWindow,d=frame.contentDocument,q=code=>w.testRun(code);
    const click=async selector=>{let b=d.querySelector(selector);check(b,'missing '+selector);b.click();await tick()};
    const reset=(floor=2450)=>q(`S=migrate({...fresh(),floor:${floor},bestFloor:${floor},auto:false});S.inventory=[makeGear(2000)];S.detailGear=S.inventory[0].id;playerHP=totalStats().hp;setupEnemy();render();renderAscensionPreview(true);`);
    await test('飞升：未满足时可打开并显示条件',async()=>{reset(1250);await click('#ascHeaderBtn');check(d.querySelector('#ascensionDialog').open);check(d.querySelector('#ascModalBody').textContent.includes('750层'));await click('#ascConfirmBtn');check(q('S.ascensions')===0);check(d.querySelector('#ascModalToast').textContent.includes('还需 750 层'));return {floor:1250,remaining:750}});
    await test('飞升：2450层预览实时刷新到3000层',async()=>{q('S.bestFloor=2450;renderFast()');check(d.querySelector('#ascModalBody [data-asc-effect="attack"]').textContent==='+12.2%');q('S.bestFloor=3000');await new Promise(r=>setTimeout(r,600));check(d.querySelector('#ascModalBody [data-asc-effect="resource"]').textContent==='+25%');return {attack2450:'+12.2%',resource3000:'+25%',refresh:'500ms timer without reopening'}});
    await test('飞升：确认与重复点击、已飞升面板',async()=>{reset(2450);await click('#ascConfirmBtn');await click('#ascConfirmBtn');check(q('S.ascensions')===1);check(q('S.floor')===2450);check(d.querySelector('#ascModalBody').textContent.includes('当前累计效果'));check(d.querySelector('#ascModalBody').textContent.includes('下一次飞升预览'));await click('#ascCloseBtn');return {count:1,floor:2450}});
    await test('装备强化：重铸与仙缘淬词有反馈和扣费',async()=>{reset();q('S.jade=100000;S.fate=100');await click('[data-p="equipment"]');let old=q('S.jade');await click('[data-reroll-gear]');check(q('S.jade')<old);let fate=q('S.fate');await click('[data-fate-reroll]');check(q('S.fate')<fate);return {operations:['重铸','仙缘淬词']}});
    await test('商城购买：只扣费一次，售出按钮说明原因',async()=>{reset();q("S.shop.slots=[{type:'memory',name:'测试回忆令',amount:1,currency:'jade',cost:10,rarity:'普通',sold:false}];renderShop()");await click('[data-p="shop"]');let old=q('S.jade'),tokens=q('S.memoryTokens');await click('[data-shop-buy="0"]');await click('[data-shop-buy="0"]');check(q('S.jade')===old-10);check(q('S.memoryTokens')===tokens+1);check(d.querySelector('#toast').textContent.includes('售出'));return {purchases:1}});
    await test('成就领取：成功到账，重复领取被拦截',async()=>{reset();await click('[data-p="achievements"]');let b=d.querySelector('[data-ach-claim]:not([data-unavailable="true"])');check(b,'no claimable achievement');let id=b.dataset.achClaim;await click(`[data-ach-claim="${id}"]`);check(q(`S.achievementClaims['${id}']`));let coins=q('S.coins');await click(`[data-ach-claim="${id}"]`);check(q('S.coins')===coins);return {id}});
    await test('存档导入：v1.1.0档码迁移、非法输入保持原档',async()=>{reset();await click('[data-p="settings"]');let code=q("(()=>{let old={...S,version:'1.1.0',daoName:'迁移测试',ascensions:2,fateTotal:30};delete old.ascension;return 'SGST110-'+b64e(JSON.stringify(old))})()");d.querySelector('#saveCode').value=code;await click('#codeLoad');check(q('S.daoName')==='迁移测试');check(q('S.ascension.legacyCount')===2);d.querySelector('#saveCode').value='SGST111-invalid';await click('#codeLoad');check(q('S.daoName')==='迁移测试');return {prefix:'SGST110-',migrated:'SGST111-',invalidPreserved:true}});
    await test('存档导入：压缩 .sgst 文件实际读取与恢复',async()=>{let code=q("S.daoName='档码文件测试';makeSaveCode()"),compressed=await new Response(new Blob([code]).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer(),file=new w.File([compressed],'fixture.sgst');q("S.daoName='等待导入'");const input=d.querySelector('#importCodeFile');Object.defineProperty(input,'files',{value:[file],configurable:true});input.dispatchEvent(new w.Event('change',{bubbles:true}));await new Promise(r=>setTimeout(r,100));check(q('S.daoName')==='档码文件测试');check(d.querySelector('#toast').textContent.includes('导入成功'));return {format:'.sgst',compression:'gzip',decoded:true}});
    await test('全部页面：可见按钮有处理函数、条件反馈和点击响应',async()=>{
      reset(2000);let navs=Array.from(d.querySelectorAll('#nav button')).map(b=>b.dataset.p);
      for(let page of navs){
        await click(`[data-p="${page}"]`);let buttons=Array.from(d.querySelectorAll(`.page[data-page="${page}"] button`));
        const selectors=buttons.filter(b=>b.getClientRects().length).map(b=>b.id?'#'+b.id:(()=>{let a=Array.from(b.attributes).find(a=>a.name.startsWith('data-')&&!['data-unavailable','data-reason','data-tip'].includes(a.name));return a?`[${a.name}="${CSS.escape(a.value)}"]`:null})());
        let audit=q(`auditButtons(document.querySelector('.page[data-page="${page}"]'))`);check(audit.every(b=>b.handler&&!b.nativeDisabled),'missing handler/native disabled on '+page);
        pages.push({page,buttons:selectors.length,handlers:'PASS'});
        for(let selector of selectors){
          check(selector,'unnamed button on '+page);await click(`[data-p="${page}"]`);
          const b=d.querySelector(selector);if(!b||!b.getClientRects().length)continue;
          if(['#codeCopy','#exportCodeBtn'].includes(selector))continue; // clipboard/download are separately/manual tested.
          if(selector==='#codeLoad')d.querySelector('#saveCode').value=q('makeSaveCode()');
          let serial=q('buttonFeedbackSerial'),errors=q('errorLog.length');b.click();await tick();
          check(q('buttonFeedbackSerial')>serial,'silent '+page+' '+selector);check(q('errorLog.length')===errors,'runtime '+selector);
          buttonClicks.push({page,selector,status:'PASS'});
          if(d.querySelector('#ascensionDialog').open)await click('#ascCloseBtn');
        }
      }
      return {pages:pages.length,buttonClicks:buttonClicks.length,excluded:['clipboard permission','native download']};
    });
    await test('高级状态：满星觉醒、功法突破、厄运选择与键盘选择武将',async()=>{
      reset();q("S.stars.guanyu=5;S.techniqueLevels.qinglong=5;S.pendingMisfortune={id:MISFORTUNE_EVENTS[0].id};S.jade=100000;render()");
      let audit=q('auditButtons()');check(audit.every(b=>b.handler),'unbound advanced button');
      await click('[data-p="generals"]');let choice=d.querySelector('[data-awaken-choice]');check(choice,'missing awakening choices');choice.click();await tick();check(q('!!S.awakeningChoices.guanyu'));
      let row=d.querySelector('[data-g="zhangfei"]');check(row.getAttribute('role')==='button');row.dispatchEvent(new w.KeyboardEvent('keydown',{key:'Enter',bubbles:true}));await tick();check(q('S.detailGeneral')==='zhangfei');
      await click('[data-p="events"]');await click('[data-misfortune-choice="0"]');check(q('S.pendingMisfortune')===null);
      return {advancedHandlers:true,keyboard:true,misfortune:true};
    });
    await test('手机：360/390/412视口、44px点击区、弹窗关闭与遮挡',async()=>{
      reset(2450);
      for(let width of [360,390,412]){
        frame.style.width=width+'px';frame.width=String(width);frame.height='844';await tick();
        let checks=[];
        for(let page of Array.from(d.querySelectorAll('#nav button')).map(b=>b.dataset.p)){
          await click(`[data-p="${page}"]`);let small=Array.from(d.querySelectorAll('button')).filter(b=>b.getClientRects().length).map(b=>({b,r:b.getBoundingClientRect()})).filter(({r})=>r.width<43.5||r.height<43.5).map(({b,r})=>({label:b.textContent,w:r.width,h:r.height}));
          check(small.length===0,'small targets '+width+' '+page+': '+JSON.stringify(small));
          check(d.documentElement.scrollWidth<=width+1,'horizontal overflow '+width+' '+page);
          checks.push(page);
        }
        await click('#ascHeaderBtn');d.querySelector('#ascModalBody').scrollTop=9999;await tick();
        let b=d.querySelector('#ascCloseBtn'),r=b.getBoundingClientRect();check(r.top>=0&&r.bottom<=844,'close button scrolls away');check(d.elementFromPoint(r.x+r.width/2,r.y+r.height/2)?.closest('#ascCloseBtn'),'close occluded');
        await click('#ascCloseBtn');mobile.push({width,height:844,pages:checks.length,minTarget:44,closeVisible:true,horizontalOverflow:false});
      }
      return mobile;
    });
    await test('手机点击：旧触摸API单次触发，滑动不触发',async()=>{
      await click('[data-p="shop"]');q("S.jade=1000;S.shop.slots=[{type:'memory',name:'触摸测试',amount:1,currency:'jade',cost:10,rarity:'普通',sold:false}];renderShop()");
      const pointer=w.PointerEvent;Object.defineProperty(w,'PointerEvent',{value:undefined,configurable:true});
      const touch=(type,b,x,y)=>{let point=new w.Touch({identifier:1,target:b,clientX:x,clientY:y});b.dispatchEvent(new w.TouchEvent(type,{bubbles:true,cancelable:true,touches:type==='touchend'?[]:[point],changedTouches:[point]}))};
      let b=d.querySelector('[data-shop-buy="0"]');touch('touchstart',b,30,30);touch('touchmove',b,30,100);touch('touchend',b,30,100);check(q('S.jade')===1000,'scroll bought item');
      touch('touchstart',b,30,30);touch('touchend',b,30,30);await tick();check(q('S.jade')===990,'tap count wrong');check(q('S.shop.slots[0].sold'));
      Object.defineProperty(w,'PointerEvent',{value:pointer,configurable:true});return {simulatedTouch:true,tapPurchases:1,scrollPurchases:0,physicalDeviceTested:false};
    });
    await test('异常：缺失函数、同步错误、异步拒绝均显示并记录',async()=>{
      let before=q('errorLog.length');await q("buttonActionGuard('test missing',null)");await q("buttonActionGuard('test thrown',()=>{throw new Error('expected test failure')})");await q("buttonActionGuard('test rejected',()=>Promise.reject(new Error('expected async failure')))");
      let orphan=d.createElement('button');orphan.textContent='未绑定测试';d.querySelector('#rootGrid').appendChild(orphan);orphan.click();await tick();orphan.remove();
      check(q('errorLog.length')===before+4);check(d.querySelector('#toast').textContent.includes('功能加载异常'));return {expectedErrors:4,persisted:q("JSON.parse(localStorage.getItem('errorLog')).length")};
    });
    await test('全部运行期间无意外脚本异常',()=>{let errors=q('errorLog');check(errors.length===4,'unexpected errors: '+JSON.stringify(errors));return {unexpected:0,expectedInjected:4}});
    const report={version:'1.1.1',engine:'Chrome browser with isolated srcdoc fixture',tests,pages,mobile,buttonClicks,physicalDeviceTested:false,passed:tests.filter(t=>t.status==='PASS').length,failed:tests.filter(t=>t.status==='FAIL').length};
    output.textContent=JSON.stringify(report,null,2);status.textContent=`完成：${report.passed} PASS / ${report.failed} FAIL`;
  }catch(e){status.textContent='测试未完成';output.textContent=JSON.stringify({fatal:e.message,tests},null,2)}
  finally{document.querySelector('#run').disabled=false}
};
