import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import path from 'node:path';
const root=path.resolve(new URL('..',import.meta.url).pathname);
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const source=html.match(/<script>([\s\S]*?)<\/script>/)[1].replace(/installButtonGuards\(\);initNav\(\);bind\(\);applyOffline\(\);[\s\S]*$/,'');
const elements=new Map(),storage=new Map();let failWrites=false;
function element(id){if(!elements.has(id))elements.set(id,{textContent:'',dataset:{},style:{},classList:{add(){},remove(){},toggle(){}},setAttribute(){},getAttribute(){return null},querySelectorAll(){return []}});return elements.get(id)}
const context=vm.createContext({console:{log(){},error(){}},Date,Math:Object.create(Math),JSON,Map,Set,WeakSet,Promise,URL,Blob,Response,CompressionStream,DecompressionStream,TextEncoder,TextDecoder,
  btoa:s=>Buffer.from(s,'binary').toString('base64'),atob:s=>Buffer.from(s,'base64').toString('binary'),escape,unescape,encodeURIComponent,decodeURIComponent,
  setTimeout:()=>0,clearTimeout(){},setInterval:()=>0,clearInterval(){},
  document:{querySelector:element,querySelectorAll:()=>[],getElementById:element,addEventListener(){},body:{classList:{toggle(){}}}},
  window:{addEventListener(){},matchMedia:()=>({matches:false})},
  localStorage:{getItem:k=>storage.get(k)||null,setItem(k,v){if(failWrites)throw new Error('test storage full');storage.set(k,v)},removeItem:k=>storage.delete(k)}});
vm.runInContext(source,context);
const run=code=>vm.runInContext(code,context),plain=x=>JSON.parse(JSON.stringify(x));
run('render=()=>{};renderFast=()=>{};renderAscensionPreview=()=>{};combatFeedback=()=>{};renderLog=()=>{}');
const results=[];
async function test(name,fn){try{await fn();results.push({name,status:'PASS'})}catch(e){results.push({name,status:'FAIL',error:e.message})}}
const close=(actual,expected)=>assert.ok(Math.abs(actual-expected)<1e-8,`${actual} != ${expected}`);
const reset=(floor=2450)=>run(`S=migrate({...fresh(),floor:${floor},bestFloor:${floor},auto:false});playerHP=totalStats().hp*.6;`);
await test('1250 / 2035 / 2450 / 3000 reward examples',()=>{
  assert.deepEqual(plain(run('ascensionReward(1250,0)')),{attack:.08,hp:.08,defense:.08,resource:.12,fate:.08});
  close(run('ascensionReward(2035,0).attack'),.11);
  assert.deepEqual(plain(run('ascensionReward(2450,0)')),{attack:.122,hp:.122,defense:.116,resource:.184,fate:.136});
  close(run('ascensionReward(3000,0).resource'),.25);
});
await test('Below first threshold cannot settle, highest floor determines eligibility',()=>{
  reset(1999);assert.equal(run('ascend()'),false);assert.equal(run('S.ascensions'),0);
  run('S.bestFloor=2000;S.floor=1;S.realm=0');assert.equal(run('ascensionEligibility().ready'),true);
});
await test('Preview equals settlement; combat, HP, defense, idle and fate bonuses actually apply',()=>{
  reset();let before=plain(run('({stats:totalStats(),idle:idlePerMin(),preview:ascensionReward(),hp:playerHP})'));
  assert.equal(run('ascend()'),true);
  let after=plain(run('({stats:totalStats(),idle:idlePerMin(),bonus:S.ascension.bonuses,hp:playerHP})'));
  assert.deepEqual(after.bonus,before.preview);
  for(let [stat,key] of [['atk','attack'],['hp','hp'],['def','defense']])close(after.stats[stat]/before.stats[stat],1+before.preview[key]);
  close(after.idle/before.idle,1.184);close(after.hp/after.stats.hp,.6);
  close(run('addFate(10)'),11.36);close(run('addFate(10,false)'),10);
});
await test('All growth fields, currencies, inventory and active battle are retained',()=>{
  reset();run("S.inventory=[makeGear(2000)];S.levels.guanyu=100;S.weaponLevels.qinglong=10;S.petLevels.qilin=9;S.techniqueLevels.qinglong=20;S.realm=4;S.cultivation=123456;S.timedMods=[{untilFloor:3000,atkPct:.01}];S.pendingMisfortune={id:'test'};");
  let snapshot=plain(run('S'));assert.equal(run('ascend()'),true);let after=plain(run('S'));
  for(let key of Object.keys(snapshot).filter(k=>!['ascensions','ascension','lastSave'].includes(k)))assert.deepEqual(after[key],snapshot[key],key);
});
await test('Repeated confirmation cannot award twice; next floor increases and rewards decay',()=>{
  reset(2000);assert.equal(run('ascend()'),true);assert.equal(run('ascend()'),false);assert.equal(run('S.ascensions'),1);assert.equal(run('nextAscensionFloor()'),3000);
  run('S.bestFloor=3000');assert.equal(run('ascend()'),true);close(run('S.ascension.bonuses.attack'),.108+.15*.8);assert.equal(run('nextAscensionFloor()'),5000);
  assert.ok(run('ascensionReward(5000,2).attack < ascensionReward(5000,1).attack'));
});
await test('Failed persistent save rolls back ascension',()=>{
  reset();let before=plain(run('S.ascension'));failWrites=true;
  try{assert.equal(run('ascend()'),false);assert.equal(run('S.ascensions'),0);assert.deepEqual(plain(run('S.ascension')),before)}finally{failWrites=false}
});
await test('Deep Boss damage ceiling reflects attack bonus while retaining legacy limits',()=>{
  reset(8000);let before=run('enemyHitCapRatio()');run('S.ascension.bonuses.attack=.122');close(run('enemyHitCapRatio()')/before,1.122);
  run('S.ascension.bonuses.attack=100');assert.ok(run('enemyHitCapRatio()')<=.12);
});
await test('v1.1.0 migration preserves legacy multiplier and never grants it twice',()=>{
  run("let legacy={...fresh(),version:'1.1.0',ascensions:2,bestFloor:2450,floor:100,fate:8,fateTotal:30};delete legacy.ascension;S=migrate(legacy)");
  close(run('ascMult()'),Math.pow(1.32,2)*1.3);assert.equal(run('nextAscensionFloor()'),3000);
  let a=plain(run('S.ascension'));run('S=migrate(S);S=loadSaveCode(makeSaveCode())');assert.deepEqual(plain(run('S.ascension')),a);
  assert.equal(run('S.version'),'1.1.1');assert.equal(run("makeSaveCode().startsWith('SGST111-')"),true);
});
await test('All legacy save prefixes and invalid import are checked',()=>{
  for(let prefix of ['SGST110','SGST1091','SGST109','SGST108','SGST107','SGST106','SGST105','SGST104','SGST103','SGST102','SGST101','SGST20','SGST19','SGST18','SGST17','SGST16','SGST15','SGST14','SGST13','SGST12','SGST11','SGST10','SGST9','SGST8','SGST7','SGST6','SGST5','DXT1','DXT2','DXT3','DXT4']){
    assert.equal(run(`loadSaveCode('${prefix}-'+b64e(JSON.stringify({...fresh(),version:'1.1.0',ascension:undefined}))).version`),'1.1.1');
  }
  assert.throws(()=>run("loadSaveCode('SGST111-'+b64e('null'))"));assert.throws(()=>run("loadSaveCode('SGST111-'+b64e('{}'))"));
});
await test('Online and offline resource settlement share the bonus without double application',()=>{
  reset(2001);run('const oldAfter=afterFloorCleared,oldSetup=setupEnemy;afterFloorCleared=()=>{};setupEnemy=()=>{};Math.random=()=>.999;');
  let base=run('let start=S.coins;win();S.coins-start');
  reset(2001);run('ascend()');let boosted=run('let start2=S.coins;win();S.coins-start2');
  close(boosted/base,1+run('S.ascension.bonuses.resource'));
  let offline=run('offlinePreview(3600).coins');close(offline/run('idlePerMin()'),60);
  run('afterFloorCleared=oldAfter;setupEnemy=oldSetup;');
});
await test('Button guard reports missing, thrown and rejected actions; conditions do not mutate',async()=>{
  let missing=await run("buttonActionGuard('missing',null)");assert.equal(missing.error,true);
  let thrown=await run("buttonActionGuard('throw',()=>{throw new Error('fixture')})");assert.equal(thrown.error,true);
  let rejected=await run("buttonActionGuard('reject',()=>Promise.reject(new Error('async fixture')))");assert.equal(rejected.error,true);
  let blocked=await run("buttonActionGuard('condition',()=>{S.coins=-1},{condition:()=> '资源不足'})");assert.equal(blocked.blocked,true);
  assert.equal(run('errorLog.length'),3);assert.equal(JSON.parse(storage.get('errorLog')).length,3);
});
await test('Async duplicate click executes only once',async()=>{
  await run("(async()=>{let button={},calls=0,finish;let first=buttonActionGuard('async',()=>{calls++;return new Promise(r=>finish=r)},{button});let second=await buttonActionGuard('async',()=>{calls++},{button});finish();await first;if(calls!==1||!second.pending)throw new Error('duplicate action')})()");
});
await test('Immediate feedback inside an async handler is not overwritten',async()=>{
  await run("buttonActionGuard('copy',async()=>{toast('复制受限，请长按存档码手动复制')})");
  assert.equal(elements.get('#toast').textContent,'复制受限，请长按存档码手动复制');
});
await test('Corrupt current save falls back to an intact legacy backup',()=>{
  storage.clear();storage.set('sgs_idle_v1110','{broken');storage.set('sgs_idle_v1100_backup',JSON.stringify({...plain(run('fresh()')),floor:888,bestFloor:1000}));
  assert.equal(run('loadStoredState().bestFloor'),1000);storage.clear();
});
await test('Reward curve is monotonic, finite, decays, and four milestones accumulate additively',()=>{
  let last=0;for(let floor=0;floor<=8000;floor+=25){let r=run(`ascensionReward(${floor},0)`);assert.ok(Number.isFinite(r.resource)&&r.resource>=last);last=r.resource;}
  reset(2000);for(let floor of [2000,3000,5000,8000]){run(`S.bestFloor=${floor}`);assert.equal(run('ascend()'),true)}
  assert.ok(run('ascensionResourceMult()<2.1'));assert.ok(run('1+ascensionBonus("attack")<1.7'));
});
const report={version:'1.1.1',engine:'Node VM executing the shipped inline game script; presentation stubbed',tests:results,passed:results.filter(t=>t.status==='PASS').length,failed:results.filter(t=>t.status==='FAIL').length};
fs.writeFileSync(path.join(root,'docs/LOGIC_TEST_V111.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
if(report.failed)process.exitCode=1;
export {run,context,root};
