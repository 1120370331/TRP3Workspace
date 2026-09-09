import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile,writeFile,mkdir,mkdtemp,cp } from 'node:fs/promises';
import { resolve,join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { build,scanSecurity,readLocal,validateContent } from '../tools/build-item-game.mjs';
import { encodeExport,decodeExport,encodeForPrint,decodeForPrint } from '../tools/lib/trp3-codec.mjs';
import { analyze,csv,markdown } from '../tools/analyze-perf-log.mjs';
import { makeBootstrap } from '../tools/lib/item-game-bootstrap.mjs';

const manifest=resolve('items/performance-lab/item.json');
const output=resolve('.test-output/build');
await mkdir(output,{recursive:true});

test('print codec preserves arbitrary byte tails',()=>{
  for(let length=1;length<130;length++){
    const input=Buffer.from(Array.from({length},(_,i)=>(i*73+length)%256));
    assert.deepEqual(decodeForPrint(encodeForPrint(input)),input);
  }
  assert.throws(()=>decodeForPrint('!'),/Invalid/);
});

test('typed Ace table keys and UTF-8 source survive export',()=>{
  const value=[1061,'ID',{SC:{onUse:{ST:{'1':{t:'list',e:[{id:'script',args:['中文🐺\n|~^\0\x1e\x7f"\\']}]}}}}},'v-dev'];
  const decoded=decodeExport(encodeExport(value),true);
  const step=decoded.get(3).get('SC').get('onUse').get('ST');
  assert(step.has('1'));assert(!step.has(1));
  assert.equal(step.get('1').get('e').get(1).get('args').get(1),value[2].SC.onUse.ST['1'].e[0].args[0]);
});

test('known aquarium export stays semantically identical through round trip',async()=>{
  const input=await readFile('references/decoded/abyss-aquarium/export.t3e.txt','utf8');
  const reference=JSON.parse(await readFile('references/decoded/abyss-aquarium/decoded.json','utf8'));
  const decoded=decodeExport(input);
  assert.deepEqual(JSON.parse(JSON.stringify(decoded)),reference.exportTuple);
  // Diagnostic JSON cannot recover numeric keys; compare meaning only for this fixture.
  assert.deepEqual(JSON.parse(JSON.stringify(decodeExport(encodeExport(decoded)))),reference.exportTuple);
});

test('builder emits reproducible complete item, verified by independent existing decoder',async()=>{
  const a=await build(manifest,{out:output});const first=await readFile(join(output,'item.t3e.txt'),'utf8');
  const b=await build(manifest,{out:output});assert.equal(a.exportHash,b.exportHash);
  assert.equal(first,await readFile(join(output,'item.t3e.txt'),'utf8'));
  assert.equal(a.publisher,'斯提芬丶九二-金色平原');assert.equal(a.inGameVerified,false);
  assert.equal(a.security.level,1);assert(a.security.details.SEC_REASON_MACRO.length);
  assert(a.sizes.macroBytes<=255);assert(a.sizes.exportCharacters<500000);
  await build(manifest,{out:output,verifyOnly:true});
  const decoded=join(output,'independent.json');
  const command=spawnSync(process.execPath,['tools/decode-trp3-export.mjs',join(output,'item.t3e.txt'),decoded],{encoding:'utf8'});
  assert.equal(command.status,0,command.stderr);
  const data=JSON.parse(await readFile(decoded,'utf8'));
  assert.equal(data.exportTuple['3'].LI.OD,'wf_destroy');
  assert.equal(Object.keys(data.exportTuple['3'].SC).length,6);
  assert.equal(data.exportTuple['3'].IN.gear_blade.BA.ST,undefined);
  assert.equal(data.exportTuple['3'].MD.dV,'v-dev');
  const steps=data.exportTuple['3'].SC.onUse.ST;
  assert.equal(steps['1'].e['1'].id,'secure_macro');
  assert.equal(steps['1'].n,'2');assert.equal(steps['2'].t,'delay');assert.equal(steps['2'].d,.1);
  assert.equal(steps['2'].n,'3');assert.equal(steps['3'].e['1'].id,'script');
  assert.equal(Buffer.byteLength(steps['1'].e['1'].args['1'],'utf8'),253);
  assert(!steps['1'].e['1'].args['1'].includes('ig_launch_token'));
  assert(data.exportTuple['3'].SC.wf_bootstrap.ST['1'].e['1'].args['1'].includes('Engine')||data.exportTuple['3'].SC.wf_bootstrap.ST['1'].e['1'].args['1'].includes('E.registerGame'));
});

test('manifest item metadata emits quality, fixed description, version and producer',async()=>{
  const out=await mkdtemp(resolve('.test-output/quality-'));
  const itemManifest=JSON.parse(await readFile('items/garden-defense-wow/item.json','utf8'));
  await build(resolve('items/garden-defense-wow/item.json'),{out});
  const root=decodeExport(await readFile(join(out,'item.t3e.txt'),'utf8'))['3'];
  assert.equal(root.BA.QA,2,'Enum.ItemQuality.Uncommon must produce the green excellent-quality frame');
  assert.equal(root.BA.DE,itemManifest.description,'packing must preserve the current manifest description');
  assert.equal(root.BA.LE,`版本：${itemManifest.releaseVersion}`);
  assert.equal(root.BA.RI,'斯托颂潮汐研究所');

  const temp=await mkdtemp(resolve('.test-output/quality-invalid-'));
  await cp('items/garden-defense-wow',temp,{recursive:true});
  const item=JSON.parse(await readFile(join(temp,'item.json'),'utf8'));item.quality=9;item.engine=resolve('framework/item-game');
  await writeFile(join(temp,'item.json'),JSON.stringify(item));
  await assert.rejects(build(join(temp,'item.json'),{out:join(temp,'dist-test')}),/quality/);
});

test('invalid content and Lua do not replace the last successful artifact',async()=>{
  const temp=await mkdtemp(resolve('.test-output/project-'));await cp('items/performance-lab',temp,{recursive:true});
  const out=join(temp,'candidate');await build(join(temp,'item.json'),{out});
  const original=await readFile(join(out,'item.t3e.txt'),'utf8');
  const content=JSON.parse(await readFile(join(temp,'content.json'),'utf8'));content.prefabs.hero.width=-1;
  await writeFile(join(temp,'content.json'),JSON.stringify(content));
  await assert.rejects(build(join(temp,'item.json'),{out}),/collider/);
  assert.equal(original,await readFile(join(out,'item.t3e.txt'),'utf8'));
  await cp('items/performance-lab/content.json',join(temp,'content.json'));
  await writeFile(join(temp,'game.lua'),'return function( broken');
  await assert.rejects(build(join(temp,'item.json'),{out}));
  assert.equal(original,await readFile(join(out,'item.t3e.txt'),'utf8'));
});

test('path escape, unknown security effects and changed release identity fail',async()=>{
  await assert.rejects(readLocal('items/performance-lab','../../README.md'),/escapes/);
  assert.throws(()=>scanSecurity('X',{SC:{x:{ST:{'1':{t:'list',e:[{id:'unknown'}]}}}}}),/Unknown effect/);
  const temp=await mkdtemp(resolve('.test-output/version-'));await cp('items/performance-lab',temp,{recursive:true});
  const prior=await build(join(temp,'item.json'),{out:join(temp,'candidate')});
  await assert.rejects(build(join(temp,'item.json'),{out:join(temp,'candidate'),previous:join(temp,'candidate/build-report.json')}),/must increase/);
  const m=JSON.parse(await readFile(join(temp,'item.json'),'utf8'));m.objectVersion++;m.releaseVersion='0.1.1';
  await writeFile(join(temp,'item.json'),JSON.stringify(m));
  await assert.rejects(build(join(temp,'item.json'),{out:join(temp,'candidate'),previous:join(temp,'candidate/build-report.json')}),/No effective change/);
  m.publisher='Someone-Else';await writeFile(join(temp,'item.json'),JSON.stringify(m));
  await assert.rejects(build(join(temp,'item.json'),{out:join(temp,'candidate'),previous:join(temp,'candidate/build-report.json')}),/identity changed/);
  assert(prior.objectVersion>0);
});

test('CRLF and CR in entry, game modules and shared engine produce the same LF-only package',async()=>{
  const temp=await mkdtemp(resolve('.test-output/line-endings-'));
  const m=JSON.parse(await readFile(manifest,'utf8'));
  m.engine='engine';m.modules={extra:'extra.lua'};
  await writeFile(join(temp,'item.json'),JSON.stringify(m));
  await cp('items/performance-lab/content.json',join(temp,'content.json'));
  await cp('framework/item-game',join(temp,'engine'),{recursive:true});
  const sources={
    'game.lua':'return function(ctx, modules)\n return {onStart=function()ctx.ui.notify(modules.extra.message)end}\nend\n',
    'extra.lua':'return {message="Windows module"}\n',
    'engine/core.lua':(await readFile(join(temp,'engine/core.lua'),'utf8')).replace(/\r\n?/g,'\n'),
  };
  const out=join(temp,'candidate');let reference;
  for(const ending of ['\n','\r\n','\r']){
    for(const [path,source] of Object.entries(sources))await writeFile(join(temp,path),source.replaceAll('\n',ending));
    const report=await build(join(temp,'item.json'),{out});
    const encoded=await readFile(join(out,'item.t3e.txt'),'utf8');
    if(reference)assert.equal(encoded,reference);else reference=encoded;
    assert.equal(report.checks.canonicalLuaLineEndings,true);
    const root=decodeExport(encoded)['3'];
    const script=root.SC.wf_bootstrap.ST['1'].e['1'].args['1'];
    assert(!script.includes('\r'));
    assert(script.includes(sources['game.lua']));assert(script.includes(sources['extra.lua']));
  }
});

test('bootstrap respects the upstream 255-byte macro editor limit',async()=>{
  const editor=await readFile('references/total-rp-3-extended/totalRP3_Extended_Tools/Script/Effects/Effects.lua','utf8');
  const limit=Number(editor.match(/MAX_CHARACTERS_IN_MACRO = (\d+)/)[1]);
  assert.equal(limit,255);
  assert(makeBootstrap('0905170116PLab1').macroBytes<=limit);
  assert.throws(()=>makeBootstrap('X'.repeat(40)),/255/);
});

test('music configuration accepts SFX and Music and rejects invalid file IDs or channels',async()=>{
  const content=JSON.parse(await readFile('items/performance-lab/content.json','utf8'));
  validateContent(content);
  for(const channel of ['SFX','Music']){content.music.arena.channel=channel;validateContent(content);}
  for(const channel of ['Master','music','invalid',null]){
    content.music.arena.channel=channel;assert.throws(()=>validateContent(content),/Invalid music channel/);
  }
  delete content.music.arena.channel;
  for(const id of ['1061171',1.5,-1]){
    content.music.arena.nativeFileId=id;assert.throws(()=>validateContent(content),/music/);
  }
});

test('endless configuration requires bounded pacing and a score for every enemy',async()=>{
  const content=JSON.parse(await readFile('items/garden-defense-wow/content.json','utf8'));
  validateContent(content);
  const score=content.endless.score.basic;delete content.endless.score.basic;
  assert.throws(()=>validateContent(content),/endless score/);content.endless.score.basic=score;
  content.endless.spawnIntervalMin=content.endless.spawnIntervalBase+1;
  assert.throws(()=>validateContent(content),/endless pacing/);
  content.endless.spawnIntervalMin=.55;content.endless.openingRows=[2,2,4];
  assert.throws(()=>validateContent(content),/opening rows/);
});

test('particle definitions and budgets are bounded at build time',async()=>{
  const content=JSON.parse(await readFile('items/performance-lab/content.json','utf8'));
  validateContent(content);
  content.limits.maxParticles=513;assert.throws(()=>validateContent(content),/maxParticles/);content.limits.maxParticles=256;
  const effect=content.effects.perf_particles;
  effect.texture='missing';assert.throws(()=>validateContent(content),/Unknown particle texture/);effect.texture='particle_probe';
  effect.lifetime=0;assert.throws(()=>validateContent(content),/particle lifetime/);effect.lifetime=1;
  effect.startColor=[1,2,1,1];assert.throws(()=>validateContent(content),/startColor/);effect.startColor=[.35,.72,1,1];
  effect.rate=[1,2];assert.throws(()=>validateContent(content),/particle rate/);effect.rate=128;
  effect.aspectRatio=0;assert.throws(()=>validateContent(content),/aspectRatio/);effect.aspectRatio=.35;
  effect.delay=-1;assert.throws(()=>validateContent(content),/particle delay/);effect.delay=[0,.12];
  effect.mode='burst';effect.count=0;assert.throws(()=>validateContent(content),/particle count/);effect.mode='continuous';delete effect.count;
  content.assets.textures.atlas_probe={kind:'atlas',atlas:'housing-dashboard-fillbar-pip-flipbook'};
  effect.texture='atlas_probe';effect.flipbook={rows:6,columns:6,frames:36,fps:24};
  assert.throws(()=>validateContent(content),/native animation backend/);
});

test('analysis preserves BGM failure reason and playback-time channel settings',()=>{
  const records=[
    {type:'run.start',data:{schema:'trp3-item-perf/1',hostKind:'wow',clientVersion:'12.1.0'}},
    {type:'music.playback',data:{trackId:'arena',fileID:1061171,channel:'Music',ok:false,reason:'channel_disabled',audio:{cvars:{Sound_EnableMusic:'0'}}}},
    {type:'check.music',data:{ok:false,reason:'channel_disabled'}},
  ];
  const report=analyze(records.map(r=>JSON.stringify(r)).join('\n'));
  assert.equal(report.musicPlayback.length,2);assert(report.warnings.some(w=>w.includes('BGM')));
  assert(markdown(report).includes('Sound_EnableMusic'));assert(markdown(report).includes('channel_disabled'));
});

test('model placement configuration rejects invalid anchors and screen offsets',async()=>{
  const content=JSON.parse(await readFile('items/garden-defense-wow/content.json','utf8'));
  const model=content.assets.models.pea;
  model.fitFill=1;model.modelAnchor={x:0,y:0,z:0};model.render.offsetX=-8;model.render.offsetY=6;
  validateContent(content);
  for (const anchor of [{x:0,y:0},{x:0,y:0,z:Infinity},null]) {
    model.modelAnchor=anchor;
    assert.throws(()=>validateContent(content),/Invalid model anchor/);
  }
  delete model.modelAnchor;
  for (const offset of [NaN,Infinity,'8',257]) {
    model.render.offsetX=offset;
    assert.throws(()=>validateContent(content),/Invalid model render offsetX/);
  }
});

test('analysis preserves incomplete-model status, warns on truncation and refuses mock evidence',()=>{
  const records=[
    {type:'run.start',data:{schema:'trp3-item-perf/1',hostKind:'mock',clientVersion:'MOCK',sourceHash:'functional-only'}},
    {type:'log.status',data:{droppedRecords:2,droppedSummaries:0}},
    {type:'phase.end',data:{id:1,name:'models',status:'models_not_verified',frames:100,metrics:{frameMs:{mean:20,p95:22,p99:30},luaFrameMs:{mean:1,p95:2}},resources:{loadedModels:0},counters:{droppedSimulationMs:5}}},
  ];
  const text=records.map(r=>JSON.stringify(r)).join('\n');
  assert.throws(()=>analyze(text),/Mock/);
  const report=analyze(text,{includeMock:true});assert.equal(report.phases[0].fpsFromMean,50);
  assert.equal(report.phases[0].status,'models_not_verified');assert(report.warnings.length>=3);
  assert(csv(report).includes('models_not_verified'));assert(markdown(report).includes('不能代表 WoW'));
});
