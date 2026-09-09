import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile,writeFile,mkdir,mkdtemp,cp } from 'node:fs/promises';
import { resolve,join } from 'node:path';
import { build,readPackageCatalog } from '../tools/build-item-game.mjs';
import { resolvePackages,validatePackageContent,buildSettings } from '../tools/lib/item-game-packages.mjs';
import { compileLua } from '../tools/lib/lua-compile.mjs';
import { decodeExport } from '../tools/lib/trp3-codec.mjs';
import { traceLine } from '../tools/trace-item-game.mjs';

const catalog=await readPackageCatalog();
await mkdir('.test-output',{recursive:true});
async function fixture() {
  const path=await mkdtemp(resolve('.test-output/packages-'));
  const manifest={...JSON.parse(await readFile('items/performance-lab/item.json','utf8')),
    engine:'engine',packages:[],build:{profile:'release'}};
  const content={viewport:{width:640,height:480},limits:{maxEntities:1},controls:{},prefabs:{},actions:{},levels:{},assets:{},sounds:{},music:{},items:{}};
  await cp('framework/item-game',join(path,'engine'),{recursive:true});
  await writeFile(join(path,'item.json'),JSON.stringify(manifest));
  await writeFile(join(path,'content.json'),JSON.stringify(content));
  await writeFile(join(path,'game.lua'),'-- source-only diagnostic comment\nreturn function(ctx) return {onStart=function()ctx.ui.notify("包管理 | 中文 ~ ^")end} end');
  return {path,manifest,input:join(path,'item.json'),out:join(path,'dist')};
}

test('packages resolve minimal, transitive, full and canonical selections',()=>{
  const minimal=resolvePackages(catalog,[]);
  assert.deepEqual(minimal.resolved,['runtime']);
  assert(!minimal.modules.includes('world') && !minimal.modules.includes('audio'));
  const a=resolvePackages(catalog,['particles3d','surface-models']);
  assert.deepEqual(a,resolvePackages(catalog,['surface-models','particles3d']));
  assert.deepEqual(a.automatic,['runtime','scene3d','surface']);
  assert(a.modules.indexOf('math3d')<a.modules.indexOf('particles3d'));
  assert.deepEqual(resolvePackages(catalog).modules,catalog.moduleOrder);
  assert.throws(()=>resolvePackages(catalog,['typo']),/Unknown engine package/);
  assert.throws(()=>resolvePackages(catalog,['audio','audio']),/unique/);
  const cyclic=structuredClone(catalog);cyclic.packages.runtime.dependencies=['particles3d'];
  assert.throws(()=>resolvePackages(cyclic,[]),/dependency cycle/);
  const duplicate=structuredClone(catalog);duplicate.packages.audio.modules.push('core');
  assert.throws(()=>resolvePackages(duplicate),/multiply owned/);
});

test('omitted systems cannot silently discard declared content',()=>{
  const plan=resolvePackages(catalog,[]);
  for(const [field,value] of Object.entries({prefabs:{hero:{}},levels:{arena:{}},music:{theme:{}},effects:{spark:{}},particles3d:{fire:{}},surfaceModelScene:true})) {
    assert.throws(()=>validatePackageContent({[field]:value},plan),/requires engine package/);
  }
  assert.equal(buildSettings({}).logs.persist,'auto');
  assert.equal(buildSettings({build:{profile:'release'}}).logs.persist,'manual');
  assert.throws(()=>buildSettings({build:{profile:'production'}}),/profile/);
  assert.throws(()=>buildSettings({build:{logs:{maxBytes:200000}}}),/build.logs/);
});

test('Lua release compiler preserves tricky literals, numeric concatenation and line mappings',()=>{
  const source='-- remove me\nlocal x = [=[中文\n-- literal stays]=]\nlocal a = { [ [[key]] ] = "a\\n|~^" }\nlocal n=1 .. 2\nreturn x, a, n, 3 - -2, .5, 1e-3';
  const result=compileLua(source,{minify:true});
  assert(result.code.length<source.length);
  assert(!result.code.includes('remove me'));
  assert(result.code.includes('-- literal stays') && result.code.includes('1 ..2'));
  for(const [outputOffset,debugOffset,debugLine,outputLine] of result.map) {
    assert.equal(result.code[outputOffset],source[debugOffset]);
    assert.equal(source.slice(0,debugOffset).split('\n').length,debugLine);
    assert.equal(result.code.slice(0,outputOffset).split('\n').length,outputLine);
  }
  assert.throws(()=>compileLua('return function( broken',{minify:true}));
});

test('release builds ship only selected source, preserve original diagnostics and reproduce exactly',async()=>{
  const f=await fixture();
  const report=await build(f.input,{out:f.out,updateLock:true});
  const first=await readFile(join(f.out,'item.t3e.txt'),'utf8');
  const shipped=decodeExport(first)['3'].SC.wf_bootstrap.ST['1'].e['1'].args['1'];
  assert(!/function\s+E\.newWorld/.test(shipped) && !/function\s+E\.newSound/.test(shipped));
  assert(!shipped.includes('source-only diagnostic comment'));
  assert((await readFile(join(f.out,'engine.debug.lua'),'utf8')).includes('source-only diagnostic comment'));
  assert.equal(shipped,await readFile(join(f.out,'engine.generated.lua'),'utf8'));
  assert(report.sizes.sourceBytes<report.sizes.unminifiedSourceBytes);
  assert.equal(decodeExport(first)['3'].securityLevel,1);
  const map=JSON.parse(await readFile(join(f.out,'engine.source-map.json'),'utf8'));
  assert.equal(map.sourceHash,report.sourceHash);assert(map.tokens.length>0);
  assert.equal(map.sections.at(-1).path,'game.lua');
  const section=map.sections.at(-1);
  const token=map.tokens.find(t=>t[2]===section.startLine+1);
  const frame=await traceLine(f.out,token[3]);
  assert.equal(frame.source,'game.lua');assert.equal(frame.line,2);
  await build(f.input,{out:f.out,frozenLockfile:true,verifyOnly:true});
  assert.equal(first,await readFile(join(f.out,'item.t3e.txt'),'utf8'));
  const dev=await build(f.input,{out:join(f.path,'debug'),profile:'development'});
  assert.notEqual(dev.sourceHash,report.sourceHash,'profile must invalidate the running bundle cache');
  assert(dev.sizes.sourceBytes>report.sizes.sourceBytes);
});

test('frozen locks reject used dependency drift but do not lock unused source',async()=>{
  const f=await fixture();
  await assert.rejects(build(f.input,{out:f.out,frozenLockfile:true}),/Cannot read.*lock/);
  await build(f.input,{out:f.out,updateLock:true});
  const before=await readFile(join(f.out,'item.t3e.txt'),'utf8');
  await writeFile(join(f.path,'engine/audio.lua'),'not valid Lua, deliberately not selected');
  await build(f.input,{out:f.out,frozenLockfile:true,verifyOnly:true});
  const core=await readFile(join(f.path,'engine/core.lua'),'utf8');
  await writeFile(join(f.path,'engine/core.lua'),core+'\n-- changed dependency\n');
  await assert.rejects(build(f.input,{out:f.out,frozenLockfile:true}),/lock is stale/);
  assert.equal(before,await readFile(join(f.out,'item.t3e.txt'),'utf8'));
});

test('budgets and invalid selections fail before replacing artifacts or updating a lock',async()=>{
  const f=await fixture();await build(f.input,{out:f.out,updateLock:true});
  const previous=await readFile(join(f.out,'item.t3e.txt'),'utf8');
  const lock=await readFile(join(f.path,'item-game.lock.json'),'utf8');
  f.manifest.build.budgets={exportCharacters:10};await writeFile(f.input,JSON.stringify(f.manifest));
  await assert.rejects(build(f.input,{out:f.out,updateLock:true}),/Build budget exceeded/);
  assert.equal(previous,await readFile(join(f.out,'item.t3e.txt'),'utf8'));
  assert.equal(lock,await readFile(join(f.path,'item-game.lock.json'),'utf8'));
  await build(f.input,{out:join(f.path,'debug'),profile:'development'});
  f.manifest.packages=['missing'];await writeFile(f.input,JSON.stringify(f.manifest));
  await assert.rejects(build(f.input,{out:f.out}),/Unknown engine package/);
});
