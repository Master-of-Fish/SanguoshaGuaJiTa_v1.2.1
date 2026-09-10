// Central boundary for existing direct and delegated button handlers.
let errorLog=[];
try{let saved=JSON.parse(localStorage.getItem('errorLog')||'[]');if(Array.isArray(saved))errorLog=saved.slice(-100)}catch(e){}
let buttonFeedbackSerial=0;
const pendingButtonActions=new WeakSet();
const BUTTON_DELEGATES={
  nav:'[data-p]',generalSelector:'[data-g]',generalDetail:'[data-use-g],[data-level-g],[data-star-g],[data-train-g],[data-awaken-choice]',
  weaponSelector:'[data-w]',weaponDetail:'[data-equip-w],[data-up-w]',petSelector:'[data-pet]',petDetail:'[data-use-pet],[data-up-pet]',
  equipmentSelector:'[data-quick-equip],[data-eq]',equipLoadout:'[data-eq]',equipmentDetail:'[data-equip-gear],[data-lock-gear],[data-reroll-gear],[data-fate-reroll],[data-affix-lock]',gearGrid:'[data-bag-eq]',
  rootGrid:'[data-root-up],[data-root]',techniqueGrid:'[data-tech-quality],[data-tech-break],[data-tech-up],[data-tech-sub],[data-tech]',destinyGrid:'[data-destiny-roll],[data-destiny]',
  fateShopGrid:'[data-fate-shop]',fateUpgradeGrid:'[data-fate-up]',misfortunePanel:'[data-misfortune-choice]',mainShopGrid:'[data-shop-buy]',achievementPanel:'[data-ach-claim]',
  secretRealmGrid:'[data-secret],[data-secret-sweep]',cycleBossPanel:'#cycleBossBtn',dispatchPanel:'[data-dispatch],#dispatchClaimBtn',
  skinGeneralSelector:'[data-skin-g]',skinDetail:'[data-memory-skin],[data-memory-draw],[data-equip-skin]',poolGrid:'[data-draw]'
};
function recordButtonError(action,error){
  let entry={version:'1.1.1',time:new Date().toISOString(),action:String(action).slice(0,120),message:String(error?.message||error).slice(0,500),stack:String(error?.stack||'').slice(0,1600)};
  errorLog.push(entry);if(errorLog.length>100)errorLog.shift();
  try{localStorage.setItem('errorLog',JSON.stringify(errorLog))}catch(e){}
  console.error('buttonActionGuard',entry);
}
function buttonFailure(action,error){recordButtonError(action,error);toast('功能加载异常\n请重新打开页面');return {ok:false,error:true}}
async function buttonActionGuard(action,handler,{condition,button}={}){
  if(typeof handler!=='function')return buttonFailure(action,new Error('点击处理函数不存在'));
  if(button&&pendingButtonActions.has(button)){toast('操作处理中，请稍候');return {ok:false,pending:true}}
  try{
    let reason=condition?.();if(reason){toast(reason);return {ok:false,blocked:true,reason}}
    if(button)pendingButtonActions.add(button);
    let serial=buttonFeedbackSerial,result=handler();
    if(result&&typeof result.then==='function'){
      if(serial===buttonFeedbackSerial){toast('正在处理，请稍候');serial=buttonFeedbackSerial}
      result=await result;
    }
    if(serial===buttonFeedbackSerial)toast(`${action} · 已响应`);
    return {ok:result!==false,result};
  }catch(error){return buttonFailure(action,error)}
  finally{if(button)pendingButtonActions.delete(button)}
}
function buttonHandlerOwner(element,event='onclick'){
  for(let node=element;node&&node!==document;node=node.parentElement){
    if(typeof node[event]!=='function')continue;
    if(node!==element&&event==='onclick'){
      let selector=BUTTON_DELEGATES[node.id],target=selector?element.closest(selector):null;
      if(!target||!node.contains(target))return null;
    }
    return node;
  }
  return null;
}
function unavailableButtonReason(b){
  if(b.dataset.unavailable===undefined||b.dataset.unavailable==='false')return '';
  if(b.dataset.reason)return b.dataset.reason;
  let d=b.dataset,t=b.textContent.trim();
  if('achClaim' in d)return S.achievementClaims[d.achClaim]?'该成就已领取':'成就尚未完成，请查看目标进度';
  if('shopBuy' in d)return '该商品已售出，请等待商城刷新';
  if('fateShop' in d)return '仙缘不足，请查看兑换所需数量';
  if('memoryDraw' in d)return '该皮肤已集齐，无需继续回忆';
  if('equipSkin' in d)return '需要集齐25种碎片后使用皮肤';
  if('techSub' in d)return !secondaryUnlocked()?'最高100层后解锁辅修功法':'主修与辅修不能相同';
  if('rootUp' in d||'techUp' in d||'techQuality' in d)return '已达到当前等级上限';
  if('starG' in d)return S.unlocked[d.starG]?'武将已达到五星上限':'请先招募该武将';
  if('useG' in d||'levelG' in d||'trainG' in d)return '请先招募该武将';
  if('equipW' in d||'upW' in d)return '请先获得该神兵';
  if('usePet' in d||'upPet' in d)return '请先获得该灵宠';
  if('secret' in d||'secretSweep' in d)return '请先达到秘境要求；扫荡需先通关';
  let messages={claimOfflineBtn:'暂无可领取离线收益',claimOfflineOrganizeBtn:'暂无可领取离线收益',claimAllAchievementsBtn:'暂无可领取成就',achievementPrevBtn:'已经是第一页',achievementNextBtn:'已经是最后一页',dispatchClaimBtn:'派遣尚未完成',cycleBossBtn:'今日挑战次数已用完',equipBatchUpgradeBtn:'当前没有可替换的升级装备'};
  return messages[b.id]||`${t}：当前条件尚未满足，请查看功能说明`;
}
function auditButtons(root=document){
  return Array.from(root.querySelectorAll('button')).map(b=>({id:b.id||Object.keys(b.dataset).join(','),label:b.textContent.trim(),page:b.closest('[data-page]')?.dataset.page||'global',handler:!!buttonHandlerOwner(b),nativeDisabled:b.disabled,condition:unavailableButtonReason(b)}));
}
function installButtonGuards(){
  document.addEventListener('click',e=>{
    let b=e.target.closest?.('button,[role="button"]');if(!b)return;
    // Native file chooser labels retain their default activation.
    if(b.matches('label')&&b.querySelector('#importCodeFile')){toast('请选择 .sgst 存档文件');return}
    e.preventDefault();e.stopImmediatePropagation();
    let owner=buttonHandlerOwner(b),action=b.getAttribute('aria-label')||b.textContent.trim()||'按钮';
    buttonActionGuard(action,owner?()=>owner.onclick.call(owner,e):null,{button:b,condition:()=>b.id==='ascConfirmBtn'?(ascensionEligibility().ready?'':ascensionEligibility().reason):unavailableButtonReason(b)});
  },true);
  document.addEventListener('change',e=>{
    let owner=buttonHandlerOwner(e.target,'onchange');if(!owner)return;
    e.stopImmediatePropagation();buttonActionGuard(e.target.id==='importCodeFile'?'存档导入':'设置更新',()=>owner.onchange.call(owner,e),{button:e.target});
  },true);
  // Let native click handle modern touch. Fallback is only for older Touch APIs.
  let touch=null;
  document.addEventListener('touchstart',e=>{
    let b=e.target.closest?.('button,[role="button"]'),t=e.touches[0];
    touch=b&&e.touches.length===1?{b,x:t.clientX,y:t.clientY,moved:false}:null;
  },{passive:true});
  document.addEventListener('touchmove',e=>{if(touch){let t=e.touches[0];if(!t||Math.hypot(t.clientX-touch.x,t.clientY-touch.y)>12)touch.moved=true}},{passive:true});
  document.addEventListener('touchcancel',()=>{touch=null},{passive:true});
  document.addEventListener('touchend',e=>{
    let tap=touch;touch=null;
    if(!window.PointerEvent&&tap&&!tap.moved&&tap.b.isConnected&&e.cancelable){e.preventDefault();tap.b.click()}
  },{passive:false});
  document.addEventListener('keydown',e=>{
    if((e.key==='Enter'||e.key===' ')&&e.target.matches('[role="button"]:not(button)')){e.preventDefault();e.target.click()}
  });
  let upgradeControls=()=>{
    document.querySelectorAll('[data-unavailable]').forEach(b=>{let value=String(b.dataset.unavailable!=='false');if(b.getAttribute('aria-disabled')!==value)b.setAttribute('aria-disabled',value)});
    document.querySelectorAll('.selector-row,.equip-card[data-eq],.equip-slot[data-eq]').forEach(b=>{if(!b.hasAttribute('role')){b.setAttribute('role','button');b.tabIndex=0}});
  };
  new MutationObserver(upgradeControls).observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['data-unavailable']});
  upgradeControls();
  window.addEventListener('error',e=>buttonFailure('页面运行',e.error||e.message));
  window.addEventListener('unhandledrejection',e=>{e.preventDefault();buttonFailure('异步操作',e.reason)});
}
