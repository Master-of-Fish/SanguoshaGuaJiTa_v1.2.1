import {run,root} from './test_v111.mjs';
import fs from 'node:fs';
import path from 'node:path';
// Paired deterministic mechanics regression, not a time-to-progress simulation.
run(`
function seedTest(seed){let n=seed>>>0;Math.random=()=>{n=(Math.imul(n,1664525)+1013904223)>>>0;return n/4294967296}}
function progressionFixture(id,floor,asc,seed,stripBonus=false){
  seedTest(seed);S=migrate({...fresh(),floor,bestFloor:floor,auto:false});S.selected=id;S.unlocked[id]=1;S.stars[id]=5;
  S.rootLevels={fire:20,metal:20,wood:20,water:20,thunder:20};S.activeRoot='metal';
  S.activeTechnique='qinglong';S.secondaryTechnique='xuesha';for(let k in S.techniqueLevels){S.techniqueLevels[k]=30;S.techniqueBreaks[k]=3;S.techniqueQuality[k]=2}
  S.weaponLevels.qinglong=28;S.petLevels.qilin=18;S.fateUpgrades={war:4,idle:4,fortune:4,forge:0,soul:3};
  // Same pre-ascension build within each pair; level is calibrated to an explicit power ratio.
  let lo=1,hi=9999;while(lo<hi){let mid=Math.floor((lo+hi)/2);S.levels[id]=mid;if(power()/enemyPower(floor)<1e4)lo=mid+1;else hi=mid}S.levels[id]=lo;
  let milestones=[2000,3000,5000];for(let i=0;i<asc;i++){let reward=ascensionReward(milestones[i],i);if(!stripBonus)for(let k in reward)S.ascension.bonuses[k]+=reward[k];S.ascension.lastFloor=milestones[i]}
  S.ascensions=asc;S.fate=0;S.fateTotal=0;S.coins=0;S.cultivation=0;
  setupEnemy();busy=false;
}
function fightProbe(id,floor,asc,seed,stripBonus=false){
  progressionFixture(id,floor,asc,seed,stripBonus);
  let level=S.levels[id],ratio=power()/enemyPower(floor),actions=0,restarts=0,lastRound=0;
  while(S.floor===floor&&actions<120){fight();actions++;if(battleCtx.round<lastRound)restarts++;lastRound=battleCtx.round}
  return {general:id,floor,ascensions:asc,bonus:stripBonus?'removed':'enabled',seed,level,ratio,cleared:S.floor>floor,actions,restarts};
}
`);
const cases=[],scenarios=[{floor:2000,asc:0},{floor:5000,asc:1},{floor:8000,asc:3}];
for(const {floor,asc} of scenarios){
  for(const id of run('Object.keys(GENERAL_MAP)'))for(const seed of [11,29]){
    cases.push(run(`fightProbe('${id}',${floor},${asc},${seed},false)`));
    if(asc)cases.push(run(`fightProbe('${id}',${floor},${asc},${seed},true)`));
  }
}
const summaries=[];
for(const {floor,asc} of scenarios)for(const bonus of asc?['enabled','removed']:['enabled']){
  const xs=cases.filter(r=>r.floor===floor&&r.bonus===bonus),wins=xs.filter(r=>r.cleared),sorted=wins.map(r=>r.actions).sort((a,b)=>a-b);
  summaries.push({floor,ascensions:asc,bonus,samples:xs.length,cleared:wins.length,clearRate:wins.length/xs.length,medianActions:sorted.length?sorted[Math.floor(sorted.length/2)]:null,oneActionClears:wins.filter(r=>r.actions===1).length});
}
const curves=run(`(()=>{let b=emptyAscension().bonuses;return [2000,3000,5000,8000].map((floor,i)=>{let r=ascensionReward(floor,i);for(let k in r)b[k]+=r[k];return {floor,count:i+1,reward:r,cumulative:{...b},resourceMultiplier:1+b.resource}})})()`);
const report={version:'1.1.1',method:'32 generals x 2 deterministic seeds, 120 actions maximum. Level calibrated to power/enemyPower >= 10000 before ascension. Fixed mature skills/build; paired bonus removal is a mechanics probe, not full player economy or universal clear-rate evidence.',matrixFloorCap:8000,cases:cases.length,summaries,curves,limitations:['No real-time 0-to-8000 progression simulation','Not comparable to historical 1152-sample three-build matrix','Godot prototype runtime not tested']};
fs.writeFileSync(path.join(root,'docs/BALANCE_V111_MATRIX.json'),JSON.stringify(cases,null,2)+'\n');
fs.writeFileSync(path.join(root,'docs/BALANCE_V111.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
