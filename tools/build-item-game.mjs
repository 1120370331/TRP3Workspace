#!/usr/bin/env node
import { readFile, writeFile, mkdir, rename, realpath, rm } from 'node:fs/promises';
import { resolve, dirname, relative, isAbsolute, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
import luaparse from 'luaparse';
import { encodeExport, decodeExport, serializeAce } from './lib/trp3-codec.mjs';
import { makeBootstrap } from './lib/item-game-bootstrap.mjs';
import { resolvePackages, validatePackageContent, buildSettings, checkBudgets } from './lib/item-game-packages.mjs';
import { compileLua } from './lib/lua-compile.mjs';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const digest = value => createHash('sha256').update(value).digest('hex');
function assert(ok, message) { if (!ok) throw new Error(message); }
function luaString(value) {
  return '"' + String(value).replace(/[\\"\x00-\x1f\x7f]/g, c => '\\' + c.charCodeAt(0).toString().padStart(3, '0')) + '"';
}
function luaValue(value) {
  if (value === null) return 'nil';
  if (typeof value === 'string') return luaString(value);
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (Array.isArray(value)) return '{' + value.map(luaValue).join(',') + '}';
  return '{' + Object.entries(value).map(([k,v]) => '[' + luaString(k) + ']=' + luaValue(v)).join(',') + '}';
}
export async function readLocal(base, name) {
  assert(typeof name === 'string' && !isAbsolute(name), 'Source path must be relative');
  const canonicalBase = await realpath(base), full = await realpath(resolve(base, name));
  const rel = relative(canonicalBase, full);
  assert(rel && !rel.startsWith('..') && !isAbsolute(rel), `Source escapes item directory: ${name}`);
  const bytes = await readFile(full);
  assert(!(bytes[0]===0xef&&bytes[1]===0xbb&&bytes[2]===0xbf), `Unexpected UTF-8 BOM: ${name}`);
  const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  assert(!text.startsWith('\ufeff'), `Unexpected UTF-8 BOM: ${name}`);
  // TRP3's outer workflow compiler escapes LF but leaves CR inside quoted
  // script arguments. Canonicalize every input (entry, modules and engine)
  // before hashing/bundling so Windows checkouts remain importable.
  return text.replace(/\r\n?/g, '\n');
}
export async function readPackageCatalog(engineRoot = join(repo,'framework/item-game')) {
  try { return JSON.parse(await readLocal(engineRoot,'packages.json')); }
  catch (err) {
    // Existing engine directories predate the declarative catalog.
    if (err.code !== 'ENOENT') throw err;
    return JSON.parse(await readLocal(join(repo,'framework/item-game'),'packages.json'));
  }
}
function workflow(code) { return { ST: { '1': { t: 'list', e: [{ id:'script', args:[code] }] } } }; }
function document(name, text) { return { TY:'DO', MD:{MO:'NO'}, BA:{NA:name}, BT:true, PA:[{TX:text}], SC:{}, LI:{}, HA:[] }; }
const securityMap = { script:[1,'SEC_REASON_SCRIPT'], secure_macro:[1,'SEC_REASON_MACRO'], document_show:[3], text:[3], run_workflow:[3] };
export function scanSecurity(rootId, root) {
  let minimum = 3; const details = {};
  function visit(id, object) {
    for (const wf of Object.values(object.SC || {})) for (const step of Object.values(wf.ST || {})) {
      if (!['list','delay'].includes(step.t)) throw new Error('This builder only emits list/delay steps');
      for (const effect of step.e || []) {
        const known = securityMap[effect.id]; assert(known, `Unknown effect: ${effect.id}`);
        minimum = Math.min(minimum, known[0]);
        if (known[0] < 3) (details[known[1]] ||= []).push(id);
      }
    }
    // Match the pinned upstream iterateObject's child-ID convention exactly.
    for (const group of ['IN','QE','ST']) for (const [id, child] of Object.entries(object[group] || {})) visit(id, child);
  }
  visit(rootId, root); return { securityLevel:minimum, details };
}
export function validateContent(content) {
  for (const key of ['viewport','limits','controls','prefabs','actions','levels','assets','sounds','music','items']) assert(content[key] && typeof content[key] === 'object', `Missing content.${key}`);
  assert([30,60].includes(content.simulationHz || 60), 'simulationHz must be 30 or 60');
  assert(content.viewport.width > 100 && content.viewport.width <= 4000 && content.viewport.height > 100 && content.viewport.height <= 2000, 'Invalid viewport');
  assert(Number.isInteger(content.limits.maxEntities) && content.limits.maxEntities >= 1 && content.limits.maxEntities <= 1500, 'maxEntities must be 1..1500');
  if(content.limits.maxSoundVoices!==undefined)assert(Number.isInteger(content.limits.maxSoundVoices)&&content.limits.maxSoundVoices>=1&&content.limits.maxSoundVoices<=32,'maxSoundVoices must be 1..32');
  if (content.limits.maxSurfaceModels !== undefined) assert(Number.isInteger(content.limits.maxSurfaceModels) && content.limits.maxSurfaceModels >= 1 && content.limits.maxSurfaceModels <= 128, 'maxSurfaceModels must be 1..128');
  for (const [key,max] of [['maxScene3DNodes',1024],['maxScene3DFaces',4096],['maxParticles3D',2048],['maxEmitters3D',64],['maxParticleSpawns3DPerStep',1024]])
    if (content.limits[key] !== undefined) assert(Number.isInteger(content.limits[key]) && content.limits[key]>=1 && content.limits[key]<=max, `${key} must be 1..${max}`);
  if (content.limits.maxParticles !== undefined) assert(Number.isInteger(content.limits.maxParticles) && content.limits.maxParticles >= 1 && content.limits.maxParticles <= 512, 'maxParticles must be 1..512');
  if (content.limits.maxEmitters !== undefined) assert(Number.isInteger(content.limits.maxEmitters) && content.limits.maxEmitters >= 1 && content.limits.maxEmitters <= 64, 'maxEmitters must be 1..64');
  if (content.limits.maxParticleSpawnsPerStep !== undefined) assert(Number.isInteger(content.limits.maxParticleSpawnsPerStep) && content.limits.maxParticleSpawnsPerStep >= 1 && content.limits.maxParticleSpawnsPerStep <= 128, 'maxParticleSpawnsPerStep must be 1..128');
  for (const [id,p] of Object.entries(content.particles3d || {})) {
    assert(/^[a-zA-Z0-9_.-]+$/.test(id),`Invalid 3D particle ID: ${id}`);
    assert(['burst','continuous'].includes(p.mode||'burst') && ['sphere','ring','cone'].includes(p.shape||'sphere'),`Invalid 3D particle mode/shape: ${id}`);
    for (const [key,lo,hi] of [['count',1,2048],['rate',0,2048],['duration',.02,60],['spread',0,Math.PI],['radius',0,20],['drag',0,20],['endSize',0,2],['priority',-10,10]])
      if(p[key]!==undefined)assert(Number.isFinite(p[key])&&p[key]>=lo&&p[key]<=hi&&(key!=='count'||Number.isInteger(p[key])),`Invalid 3D particle ${id}.${key}`);
    for (const [key,lo,hi] of [['speed',0,100],['lifetime',.02,15],['size',.002,2]]) if(p[key]!==undefined){
      const r=Array.isArray(p[key])?p[key]:[p[key],p[key]];
      assert(r.length===2&&r.every(v=>Number.isFinite(v)&&v>=lo&&v<=hi)&&r[0]<=r[1],`Invalid 3D particle range ${id}.${key}`);
    }
    for(const key of ['direction','gravity'])if(p[key]!==undefined){
      const v=p[key];assert(v&&['x','y','z'].every(k=>Number.isFinite(v[k]))&&Math.hypot(v.x,v.y,v.z)<=100000&&(key!=='direction'||Math.hypot(v.x,v.y,v.z)>1e-9),`Invalid 3D particle vector ${id}.${key}`);
    }
    for(const key of ['startColor','endColor'])if(p[key]!==undefined)assert(Array.isArray(p[key])&&p[key].length===4&&p[key].every(v=>Number.isFinite(v)&&v>=0&&v<=1),`Invalid 3D particle color ${id}.${key}`);
  }
  if(content.fireworksLab!==undefined){
    const lab=content.fireworksLab;
    assert(lab&&Number.isFinite(lab.duration)&&lab.duration>=.1&&lab.duration<=60&&Number.isFinite(lab.warmup)&&lab.warmup>=0&&lab.warmup<=10,'Invalid fireworks benchmark timing');
  }
  for (const [id, p] of Object.entries(content.prefabs)) {
    assert(/^[a-zA-Z0-9_.-]+$/.test(id), 'Invalid prefab ID');
    assert(p.width > 0 && p.width <= 256 && p.height > 0 && p.height <= 256, `Invalid collider: ${id}`);
    assert(['static','dynamic','kinematic'].includes(p.motion || 'static'), `Invalid motion: ${id}`);
    if (['model','scene_model'].includes(p.visual?.kind)) assert(content.assets.models?.[p.visual.asset], `Missing model for ${id}`);
    for (const action of p.actions || []) assert(content.actions[action], `Unknown action ${action}`);
    if (p.ai) assert(content.actions[p.ai.action], `Unknown AI action for ${id}`);
  }
  for (const [id, action] of Object.entries(content.actions)) {
    assert(action.damage >= 0 && action.windup >= 0 && action.active > 0 && action.recovery >= 0, `Invalid action: ${id}`);
    if (action.projectile) assert(content.prefabs[action.projectile]?.projectile, `Invalid projectile prefab: ${id}`);
  }
  for (const [id, level] of Object.entries(content.levels)) {
    assert(Array.isArray(level.terrain) && level.terrain.length <= 200, `Invalid terrain: ${id}`);
    for (const r of level.terrain) assert([r.x,r.y,r.w,r.h].every(Number.isFinite) && r.w > 0 && r.h > 0, `Invalid terrain rectangle: ${id}`);
    for (const s of level.spawns || []) assert(content.prefabs[s.prefab], `Unknown level spawn: ${s.prefab}`);
  }
  for (const [id, asset] of Object.entries(content.assets.textures || {})) {
    if(asset.maskPath!==undefined)assert(typeof asset.maskPath==='string'&&asset.maskPath.length>0&&!asset.maskPath.includes('\0'),`Invalid texture mask ${id}`);
    assert((asset.kind==='fileID' && Number.isInteger(asset.id) && asset.id>0) ||
      (asset.kind==='texturePath' && typeof asset.path==='string' && asset.path.length>0 && !asset.path.includes('\0')) ||
      (asset.kind==='atlas' && typeof asset.atlas==='string' && asset.atlas.length>0 && !asset.atlas.includes('\0')), `Invalid texture asset ${id}`);
  }
  const numericRange=(value,name,low,high,required=false)=>{
    if (value===undefined) { assert(!required,`Missing ${name}`); return; }
    const values=Array.isArray(value)?value:[value];
    assert((values.length===1||values.length===2)&&values.every(n=>Number.isFinite(n)&&n>=low&&n<=high),`Invalid ${name}`);
  };
  const rgba=(value,name)=>{
    if(value===undefined)return;
    assert(Array.isArray(value)&&value.length===4&&value.every(n=>Number.isFinite(n)&&n>=0&&n<=1),`Invalid ${name}`);
  };
  for (const [id,effect] of Object.entries(content.effects || {})) {
    assert(/^[a-zA-Z0-9_.-]+$/.test(id),`Invalid effect ID ${id}`);
    assert(content.assets.textures?.[effect.texture],`Unknown particle texture ${id}`);
    assert(['burst','continuous'].includes(effect.mode||'burst'),`Invalid particle mode ${id}`);
    assert(['screen','world'].includes(effect.space||'screen'),`Invalid particle space ${id}`);
    if(effect.shape!==undefined)assert(['sprite','crystal'].includes(effect.shape),`Invalid particle shape ${id}`);
    if(effect.alignToVelocity!==undefined)assert(typeof effect.alignToVelocity==='boolean',`Invalid particle alignment ${id}`);
    if(effect.shape==='crystal')assert(content.assets.textures[effect.texture].kind!=='atlas'&&!content.assets.textures[effect.texture].maskPath&&!effect.flipbook,`Crystal particles need an unmasked texture: ${id}`);
    assert(['BLEND','ADD','MOD','ALPHAKEY'].includes(effect.blend||'BLEND'),`Invalid particle blend ${id}`);
    const layer=effect.layer??0;
    assert(Number.isInteger(layer)&&layer>=0&&layer<=30,`Invalid particle layer ${id}`);
    if ((effect.mode||'burst')==='burst') { const count=effect.count??1;assert(Number.isInteger(count)&&count>=1&&count<=128,`Invalid particle count ${id}`); }
    if (effect.mode==='continuous') assert(Number.isFinite(effect.rate)&&effect.rate>0&&effect.rate<=512,`Invalid particle rate ${id}`);
    if(effect.duration!==undefined)assert(Number.isFinite(effect.duration)&&effect.duration>=.01&&effect.duration<=3600,`Invalid particle duration ${id}`);
    numericRange(effect.initialBurst,`particle initialBurst ${id}`,0,128);
    if(effect.initialBurst!==undefined)assert(Number.isInteger(effect.initialBurst),`Invalid particle initialBurst ${id}`);
    numericRange(effect.lifetime,`particle lifetime ${id}`,1/120,30,true);
    numericRange(effect.delay,`particle delay ${id}`,0,3);
    if(effect.fadeIn!==undefined)assert(Number.isFinite(effect.fadeIn)&&effect.fadeIn>=0&&effect.fadeIn<=3,`Invalid particle fadeIn ${id}`);
    if(effect.aspectRatio!==undefined)assert(Number.isFinite(effect.aspectRatio)&&effect.aspectRatio>=.1&&effect.aspectRatio<=8,`Invalid particle aspectRatio ${id}`);
    numericRange(effect.speed,`particle speed ${id}`,0,10000);
    numericRange(effect.directionDeg,`particle direction ${id}`,-3600,3600);
    numericRange(effect.spreadDeg,`particle spread ${id}`,0,3600);
    numericRange(effect.gravity,`particle gravity ${id}`,-10000,10000);
    numericRange(effect.wind,`particle wind ${id}`,-10000,10000);
    numericRange(effect.drag,`particle drag ${id}`,0,60);
    numericRange(effect.offsetX,`particle offsetX ${id}`,-4000,4000);
    numericRange(effect.offsetY,`particle offsetY ${id}`,-4000,4000);
    numericRange(effect.startSize,`particle startSize ${id}`,.01,1024);
    numericRange(effect.endSize,`particle endSize ${id}`,.01,1024);
    numericRange(effect.startAlpha,`particle startAlpha ${id}`,0,1);
    numericRange(effect.endAlpha,`particle endAlpha ${id}`,0,1);
    numericRange(effect.startRotationDeg,`particle startRotation ${id}`,-3600,3600);
    numericRange(effect.spinDeg,`particle spin ${id}`,-36000,36000);
    rgba(effect.startColor,`particle startColor ${id}`);rgba(effect.endColor,`particle endColor ${id}`);
    if(effect.priority!==undefined)assert(Number.isInteger(effect.priority)&&effect.priority>=-10&&effect.priority<=10,`Invalid particle priority ${id}`);
    if(effect.maxAlive!==undefined)assert(Number.isInteger(effect.maxAlive)&&effect.maxAlive>=1&&effect.maxAlive<=(content.limits.maxParticles||128),`Invalid particle maxAlive ${id}`);
    if(effect.flipbook){
      const f=effect.flipbook;
      assert(content.assets.textures[effect.texture].kind!=='atlas',`Particle atlas flipbooks require a native animation backend: ${id}`);
      assert(Number.isInteger(f.rows)&&f.rows>=1&&f.rows<=32&&Number.isInteger(f.columns)&&f.columns>=1&&f.columns<=32,`Invalid particle flipbook grid ${id}`);
      assert(Number.isInteger(f.frames)&&f.frames>=1&&f.frames<=f.rows*f.columns,`Invalid particle flipbook frames ${id}`);
      assert(Number.isFinite(f.fps)&&f.fps>0&&f.fps<=120,`Invalid particle flipbook fps ${id}`);
    }
  }
  for (const [id, asset] of Object.entries(content.assets.models || {})) {
    assert(['creatureDisplayID','fileID','petSpeciesID'].includes(asset.kind) && Number.isInteger(asset.id) && asset.id > 0, `Invalid model asset ${id}`);
    if (asset.displayIndex !== undefined) assert(Number.isInteger(asset.displayIndex) && asset.displayIndex>0, `Invalid pet display index ${id}`);
    if (asset.fitToBounds !== undefined) assert(typeof asset.fitToBounds==='boolean', `Invalid model bounds-fit flag ${id}`);
    if (asset.screenFacing !== undefined) assert(['left','right'].includes(asset.screenFacing), `Invalid model screen direction ${id}`);
    if (asset.forwardYaw !== undefined) assert(Number.isFinite(asset.forwardYaw), `Invalid model forward axis ${id}`);
    if (asset.fallbackMode !== undefined) assert(['icon','model'].includes(asset.fallbackMode), `Invalid model fallback mode ${id}`);
    if (asset.fitFill !== undefined) assert(Number.isFinite(asset.fitFill) && asset.fitFill>=.35 && asset.fitFill<=(content.surfaceModelScene ? 1 : .9), `Invalid model fit fill ${id}`);
    if (asset.render) assert([asset.render.width,asset.render.height].every(n=>Number.isFinite(n)&&n>=24&&n<=256), `Invalid model display footprint ${id}`);
    if (asset.modelAnchor !== undefined) assert(['x','y','z'].every(key=>Number.isFinite(asset.modelAnchor?.[key])), `Invalid model anchor ${id}`);
    for (const key of ['offsetX','offsetY']) if (asset.render?.[key] !== undefined) assert(Number.isFinite(asset.render[key]) && Math.abs(asset.render[key])<=256, `Invalid model render ${key}: ${id}`);
    if (asset.fallback !== undefined) assert(content.assets.textures?.[asset.fallback], `Unknown model fallback ${id}`);
    for (const key of ['scale','distance']) if (asset[key] !== undefined) assert(Number.isFinite(asset[key]) && asset[key]>0 && asset[key]<=20, `Invalid model ${key}: ${id}`);
  }
  // Optional visual catalog for projects that compose units, tools and materials.
  for (const group of Object.values(content.visuals || {})) for (const [id, visual] of Object.entries(group)) {
    for (const key of ['texture','badge']) if (visual[key]) assert(content.assets.textures?.[visual[key]], `Unknown visual ${key}: ${id}`);
    if (visual.model) assert(content.assets.models?.[visual.model], `Unknown visual model: ${id}`);
  }
  if (content.surfaceModelScene !== undefined) assert(typeof content.surfaceModelScene==='boolean', 'Invalid shared model scene flag');
  for (const [id, group] of Object.entries(content.soundGroups || {})) {
    for (const key of ['interval','window','densityStep','maxExtra']) if (group[key]!==undefined) assert(Number.isFinite(group[key]) && group[key]>=0 && (key!=='window' || group[key]>0), `Invalid sound group ${id}.${key}`);
    if (group.maxConcurrent!==undefined) assert(Number.isInteger(group.maxConcurrent) && group.maxConcurrent>=1 && group.maxConcurrent<=(content.limits.maxSoundVoices||12), `Invalid sound group concurrency ${id}`);
  }
  for (const [id, sound] of Object.entries(content.sounds)) {
    if(sound.bus!==undefined)assert(Object.hasOwn(content.soundBuses||{},sound.bus),`Missing sound bus ${id}`);
    for(const key of ['volume','baseVolume'])if(sound[key]!==undefined)assert(Number.isFinite(sound[key])&&sound[key]>=0&&sound[key]<=1,`Invalid sound ${key} ${id}`);
    if(sound.volumeSoundKitID!==undefined)assert(sound.kind==='fileID'&&Number.isInteger(sound.volumeSoundKitID)&&sound.volumeSoundKitID>0,`Invalid volume SoundKit ${id}`);
    assert(['soundKitID','fileID'].includes(sound.kind) && Number.isInteger(sound.id) && sound.id > 0, `Invalid sound ${id}`);
    if(sound.maxConcurrent!==undefined)assert(Number.isInteger(sound.maxConcurrent)&&sound.maxConcurrent>=1&&sound.maxConcurrent<=(content.limits.maxSoundVoices||12),`Invalid sound concurrency ${id}`);
    if(sound.cooldown!==undefined)assert(Number.isFinite(sound.cooldown)&&sound.cooldown>=0&&sound.cooldown<=60,`Invalid sound cooldown ${id}`);
    if(sound.maxDuration!==undefined)assert(Number.isFinite(sound.maxDuration)&&sound.maxDuration>0&&sound.maxDuration<=120,`Invalid sound maxDuration ${id}`);
    if(sound.priority!==undefined)assert(Number.isInteger(sound.priority)&&sound.priority>=-10&&sound.priority<=10,`Invalid sound priority ${id}`);
    if(sound.duckDuration!==undefined)assert(Number.isFinite(sound.duckDuration)&&sound.duckDuration>=0&&sound.duckDuration<=30,`Invalid sound duckDuration ${id}`);
    if (sound.group) assert(content.soundGroups?.[sound.group], `Missing sound group for ${id}`);
    for (const group of sound.duckGroups || []) assert(content.soundGroups?.[group], `Missing ducked sound group for ${id}`);
    if (sound.fadeMs!==undefined) assert(Number.isFinite(sound.fadeMs) && sound.fadeMs>=0 && sound.fadeMs<=1000, `Invalid sound fade ${id}`);
  }
  for(const [id,volume] of Object.entries(content.soundBuses||{}))assert(Number.isFinite(volume)&&volume>=0&&volume<=1,`Invalid sound bus volume ${id}`);
  for (const [id, track] of Object.entries(content.music)) {
    assert(track.nativeFileId > 0 || typeof track.musicianCode === 'string', `Missing music source ${id}`);
    if (track.musicianCode !== undefined) assert(typeof track.musicianCode === 'string' && track.musicianCode.length > 0 && track.musicianCode.length <= 150000, `Invalid Musician code size ${id}`);
    if (track.nativeFileId !== undefined) assert(Number.isInteger(track.nativeFileId) && track.nativeFileId > 0, `Invalid native music file ID ${id}`);
    if (track.volumeSoundKitID !== undefined) assert(track.nativeFileId > 0 && Number.isInteger(track.volumeSoundKitID) && track.volumeSoundKitID > 0, `Invalid music volume SoundKit ${id}`);
    if (track.baseVolume !== undefined) assert(track.volumeSoundKitID > 0 && Number.isFinite(track.baseVolume) && track.baseVolume >= 0 && track.baseVolume <= 1, `Invalid music base volume ${id}`);
    if (track.channel !== undefined) assert(['SFX','Music'].includes(track.channel), `Invalid music channel ${id}; use SFX or Music`);
  }
  if (content.endless !== undefined) {
    const e=content.endless;
    assert(e && typeof e==='object' && !Array.isArray(e),'Invalid endless configuration');
    assert(Number.isInteger(e.level) && Array.isArray(content.campaign) && e.level>=1 && e.level<=content.campaign.length,'Invalid endless level');
    assert(Array.isArray(e.openingRows) && e.openingRows.length>=2 && e.openingRows.length<=3 && new Set(e.openingRows).size===e.openingRows.length && e.openingRows.every(row=>Number.isInteger(row)&&row>=1&&row<=5),'Invalid endless opening rows');
    assert(Number.isInteger(e.allRowsFromRound) && e.allRowsFromRound===2,'Invalid endless all-rows round');
    for (const key of ['prepare','roundGap','spawnIntervalBase','spawnIntervalStep','spawnIntervalMin','roundSunBase','roundSunStep','roundSunMax'])
      assert(Number.isFinite(e[key]) && e[key]>=0,`Invalid endless ${key}`);
    assert(e.spawnIntervalMin>0 && e.spawnIntervalBase>=e.spawnIntervalMin && e.roundSunMax>=e.roundSunBase,'Invalid endless pacing');
    assert(e.score && typeof e.score==='object' && Object.keys(content.enemies||{}).every(id=>Number.isInteger(e.score[id])&&e.score[id]>0&&e.score[id]<=10000),'Invalid endless score table');
  }
  const inner = new Set(['ig_help','ig_manifest','ig_game','ig_assets','ig_levels','ig_music']);
  for (const [id, item] of Object.entries(content.items)) {
    assert(/^[a-z][a-z0-9_]*$/.test(item.innerId) && !inner.has(item.innerId), `Duplicate/invalid internal item ID: ${id}`);
    inner.add(item.innerId);
    if (item.stack) assert(Number.isInteger(item.stack) && item.stack > 1 && item.stack <= 9999, 'Invalid item stack');
    assert(!item.stack || !item.attributes, 'Stateful equipment must not stack');
  }
  for (const sound of Object.values(content.feedback || {})) assert(content.sounds[sound], `Unknown feedback sound ${sound}`);
}
function validateObject(root) {
  function visit(object) {
    for (const key of ['OU','OD']) if (object.LI?.[key]) assert(object.SC?.[object.LI[key]], `Dangling LI.${key}`);
    if (object.US?.SC) assert(object.SC?.[object.US.SC], 'Dangling use workflow');
    for (const [id,wf] of Object.entries(object.SC || {})) {
      assert(wf.ST?.['1'], `Workflow ${id} missing string entry 1`);
      for (const step of Object.values(wf.ST)) {
        if (step.n) assert(wf.ST[step.n], 'Dangling workflow successor');
        if (step.t==='delay') assert(Number.isFinite(step.d)&&step.d>0&&step.d<=60,'Invalid workflow delay');
      }
    }
    for (const [id, child] of Object.entries(object.IN || {})) { assert(!id.includes(' '), 'Inner ID contains space'); visit(child); }
  }
  visit(root); assert(!root.BA.ST && !root.BA.CT, 'Main item must not stack or be a container');
}
export async function build(manifestPath, options = {}) {
  manifestPath = resolve(manifestPath); const base = dirname(manifestPath);
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  assert(!(options.updateLock && (options.frozenLockfile || options.verifyOnly)), '--update-lock cannot be combined with --frozen-lockfile or --verify-only');
  const settings = buildSettings(manifest,options);
  for (const k of ['gameId','name','rootId','publisher','createdAt','savedAt','releaseVersion','objectVersion','target']) assert(manifest[k], `Missing manifest.${k}`);
  assert(/^[a-zA-Z0-9]+$/.test(manifest.rootId), 'Root ID must be alphanumeric and stable');
  assert(/^[^\s]+-[^\s-]+$/.test(manifest.publisher), 'publisher must be a character-realm ID');
  assert(Number.isInteger(manifest.objectVersion) && manifest.objectVersion > 0, 'objectVersion must be positive');
  assert(manifest.quality === undefined || (Number.isInteger(manifest.quality) && manifest.quality >= 0 && manifest.quality <= 8), 'quality must be a WoW ItemQuality value from 0 to 8');
  assert(manifest.showReleaseVersion === undefined || typeof manifest.showReleaseVersion === 'boolean', 'showReleaseVersion must be boolean');
  assert(manifest.rightText === undefined || (typeof manifest.rightText === 'string' && manifest.rightText.length > 0 && manifest.rightText.length <= 100), 'rightText must be a non-empty string up to 100 characters');
  assert(manifest.engineApiVersion === 1 && Number.isInteger(manifest.saveVersion), 'Unsupported API/save version');
  assert(Number.isInteger(manifest.target.extendedBuild) && manifest.target.extendedDisplayVersion, 'Explicit target profile required');
  const sourceName = typeof manifest.entry === 'string' ? manifest.entry : manifest.entry?.source;
  const gameSource = await readLocal(base, sourceName);
  assert(!/\brequire\s*\(/.test(gameSource), 'Runtime require is not supported');
  const gameModules = {};
  assert(!manifest.modules || (typeof manifest.modules === 'object' && !Array.isArray(manifest.modules)), 'modules must map names to local Lua paths');
  for (const [name, path] of Object.entries(manifest.modules || {}).sort(([a],[b]) => a.localeCompare(b))) {
    assert(/^[a-zA-Z][a-zA-Z0-9_]*$/.test(name), 'Invalid game module name');
    gameModules[name] = await readLocal(base, path);
    assert(!/\brequire\s*\(/.test(gameModules[name]), 'Runtime require is not supported');
  }
  const contentText = await readLocal(base, manifest.content);
  const content = JSON.parse(contentText); validateContent(content);
  assert(manifest.engine === undefined || (typeof manifest.engine === 'string' && manifest.engine.length > 0 && !isAbsolute(manifest.engine)), 'engine must be a relative source directory');
  const engineRoot = manifest.engine ? resolve(base, manifest.engine) : join(repo, 'framework/item-game');
  const catalog = await readPackageCatalog(engineRoot);
  const packagePlan = resolvePackages(catalog,manifest.packages);
  validatePackageContent(content,packagePlan);
  const modules = packagePlan.modules;
  const sourceFiles = {};
  for (const name of modules) sourceFiles[name] = await readLocal(engineRoot, name + '.lua');
  const generatorFiles = ['tools/build-item-game.mjs','tools/lib/item-game-bootstrap.mjs','tools/lib/item-game-packages.mjs','tools/lib/lua-compile.mjs','tools/lib/trp3-codec.mjs','package-lock.json'];
  const generatorHash=digest(JSON.stringify(await Promise.all(generatorFiles.map(async name=>[name,await readLocal(repo,name)]))));
  const catalogHash = digest(JSON.stringify(catalog));
  const sourceHashes = Object.fromEntries(Object.entries(sourceFiles).map(([name,source])=>[name,digest(source)]));
  const lock = {schemaVersion:1,engineVersion:catalog.version,catalogHash,generatorHash,
    requested:packagePlan.requested,resolved:packagePlan.resolved,modules:sourceHashes};
  const lockPath = join(base,'item-game.lock.json');
  if (options.frozenLockfile) {
    let previousLock;
    try { previousLock=JSON.parse(await readFile(lockPath,'utf8')); }
    catch (err) { throw new Error(`Cannot read item-game.lock.json; run --update-lock: ${err.message}`); }
    assert(isDeepStrictEqual(previousLock,lock),'Engine package lock is stale; review changes and run --update-lock');
  }
  const sourceHash = digest(JSON.stringify({ manifest, content, gameSource, gameModules, sourceFiles, generatorHash, catalogHash, settings, packagePlan }));
  const effectiveManifest={...manifest};delete effectiveManifest.objectVersion;delete effectiveManifest.releaseVersion;delete effectiveManifest.savedAt;
  const effectiveHash=digest(JSON.stringify({manifest:effectiveManifest,content,gameSource,gameModules,sourceFiles,generatorHash,catalogHash,settings,packagePlan}));
  const runtimeManifest = { gameId:manifest.gameId, name:manifest.name, rootId:manifest.rootId, objectVersion:manifest.objectVersion,
    releaseVersion:manifest.releaseVersion, saveVersion:manifest.saveVersion, sourceHash, logPolicy:settings.logs };
  const moduleBundle = Object.entries(gameModules).map(([name,source]) => `-- game module: ${name}\ngameModules[${luaString(name)}]=(function()\n${source}\nend)()`).join('\n');
  const debugBundle = `-- Generated by build-item-game; sourceHash ${sourceHash}\nlocal G=args._G\nif not G then effect("text",args,"GUI host missing; use the item from your bag.",1);return end\nlocal assert,error=G.assert,G.error\nlocal old=G.TRP3_ItemGame\nif old and old.bundleId~=${luaString(sourceHash)} and old.current then old.current.stop("engine_update") end\nlocal E=old\nif not E or E.bundleId~=${luaString(sourceHash)} then\n E={bundleId=${luaString(sourceHash)},packages=${luaValue(Object.fromEntries(packagePlan.resolved.map(name=>[name,true])))}}\n${modules.map(name => '-- module: '+name+'\ndo local install=(function()\n'+sourceFiles[name]+'\nend)();install(E,G) end').join('\n')}\n G.TRP3_ItemGame=E\nend\nlocal gameModules={}\n${moduleBundle}\n-- game entry\nlocal gameFactory=(function()\n${gameSource}\nend)()\nlocal function createGame(ctx) return gameFactory(ctx,gameModules) end\nE.registerGame(${luaString(manifest.gameId)},{apiVersion=1,saveVersion=${manifest.saveVersion},create=createGame})\nargs.custom.ig_status="ready"\nG.TRP3_API.script.runWorkflow(args,"o","wf_open")\n`;
  const compilation = compileLua(debugBundle,{minify:settings.profile==='release'});
  const bundle = compilation.code;
  const sourceSections = [];
  let sectionCursor = 0;
  const section = (name,source,path) => {
    const start=debugBundle.indexOf(source,sectionCursor);assert(start>=0,`Cannot map source ${name}`);
    const startLine=debugBundle.slice(0,start).split('\n').length;
    sourceSections.push({name,path,startLine,endLine:startLine+source.split('\n').length-1,sha256:digest(source)});
    sectionCursor=start+source.length;
  };
  for (const name of modules) section(name,sourceFiles[name],relative(base,join(engineRoot,name+'.lua')).replaceAll('\\','/'));
  for (const [name,source] of Object.entries(gameModules)) section('game:'+name,source,manifest.modules[name]);
  section('game:entry',gameSource,sourceName);
  const openCode = `local G=args._G
if not G or not G.TRP3_ItemGame then effect("text",args,"[IG ENGINE] 引擎尚未就绪，请从主道具的 onUse 启动。",1);return end
local E=G.TRP3_ItemGame
local manifest=${luaValue(runtimeManifest)}
local objectRevision
local ok,err=G.pcall(function()
 local root=G.TRP3_API.extended.getClass(manifest.rootId)
 objectRevision=root and root.MD and root.MD.V
 local content=E.JSON.decode(root.IN.ig_game.PA[1].TX)
 content.assets=E.JSON.decode(root.IN.ig_assets.PA[1].TX)
 content.levels=E.JSON.decode(root.IN.ig_levels.PA[1].TX)
 content.music=E.JSON.decode(root.IN.ig_music.PA[1].TX)
 local host=E.newWoWHost(args,manifest)
 local session,why=E.start(host,manifest,content)
 if not session or session.stopping then G.error(why or "startup_stopped") end
 if not session.view.frame:IsShown() then G.error("UI_NOT_SHOWN") end
end)
local message
if not ok then
 if E.current and E.current.host.item==args.object then G.pcall(E.current.stop,"bootstrap_error",{save=false}) end
 args.custom.ig_status="failed"
 message="[IG OPEN] "..G.tostring(err)
else
 args.custom.ig_status="running"
 message="[IG 3/3] "..manifest.name.."已打开（构建版本 "..manifest.objectVersion.."，道具修订 "..G.tostring(objectRevision).."）"
end
setVar(args,"o","IG_BOOT_STATUS_V1",message:sub(1,2000))
G.print(message)
`;
  const bootstrap=makeBootstrap(manifest.rootId);
  const {macro}=bootstrap;
  const helpText = manifest.helpText || `${manifest.name}

测试候选 ${manifest.releaseVersion} / 对象版本 ${manifest.objectVersion}

重新导入对象版本 ${manifest.objectVersion} 后执行一次 /reload，再从 TRP3 背包右键使用。导入代码先登记定义，需要添加到背包；交易收到实例可直接使用。请按宿主提示审阅本道具脚本和宏。

启动顺序：253 字节短宏 → 延时 0.1 秒 → Lua。聊天会显示 [IG 1/3]、[IG 2/3]、[IG 3/3]，失败显示 INJECTION、BOOTSTRAP 或 OPEN；最近提示保存在 IG_BOOT_STATUS_V1。

选择自动基准或单项测试。测完点“复制日志”，Ctrl+A/C 复制文本，在游戏外保存为 .ndjson；道具不能直接创建电脑文件。

键盘默认只读透传；接管后 A/D 移动，Space 跳跃，J 近战，K 发射。Esc 或右上角 X 关闭游戏；日志/输入框有焦点时，第一次 Esc 返回，第二次关闭。暂停使用“暂停/继续”。进副本/进入 WoW 战斗自动关闭。

Sound 与内置 BGM 无需 Musician；BGM 默认跟随魔兽音效通道和音量，关闭魔兽背景音乐仍可播放。不会修改你的全局声音设置；总声音/音效静音仍然生效。自定义 MIDI 可选 Musician，只在本机播放。

短时注入仅匹配本根物品，用完或两秒超时后恢复，不长期开放脚本执行器。当前修复仍需在你的客户端复测。

请勿堆叠主道具；存档和日志在物品变量中。删除道具会删除其数据。`;
  const baseContent = {...content}; delete baseContent.assets; delete baseContent.levels; delete baseContent.music;
  const root = {
    TY:'IT', MD:{MO:'EX',V:manifest.objectVersion,CB:manifest.publisher,SB:manifest.publisher,CD:manifest.createdAt,SD:options.savedAt||manifest.savedAt,tV:manifest.target.extendedBuild,dV:manifest.target.extendedDisplayVersion,LO:'zhCN'},
    BA:{NA:manifest.name,DE:manifest.description,IC:manifest.icon||'inv_misc_enggizmos_17',US:true,VA:0,WE:0,
      ...(manifest.quality!==undefined?{QA:manifest.quality}:{}),
      ...(manifest.showReleaseVersion?{LE:`版本：${manifest.releaseVersion}`} : {}),
      ...(manifest.rightText?{RI:manifest.rightText}:{})},
    US:{SC:'onUse',AC:manifest.actionText||'打开性能测试台'}, LI:{OU:'onUse',OD:'wf_destroy'}, HA:[],
    SC:{
      onUse:{ST:{'1':{t:'list',e:[{id:'secure_macro',args:[macro]}],n:'2'},'2':{t:'delay',d:bootstrap.delay,n:'3'},'3':{t:'list',e:[{id:'script',args:[bootstrap.launch]}]}}},
      wf_bootstrap:workflow(bundle), wf_open:workflow(openCode),
      wf_stop:workflow('setVar(args,"o","IG_CONTROL_V1","stop")'),
      wf_destroy:workflow('setVar(args,"o","IG_CONTROL_V1","destroy")'),
      wf_help:{ST:{'1':{t:'list',e:[{id:'script',args:['setVar(args,"o","IG_CONTROL_V1","pause")']},{id:'document_show',args:[manifest.rootId+' ig_help']}]}}}
    },
    IN:{ig_help:document('操作与测试说明',helpText),ig_manifest:document('包清单',JSON.stringify(runtimeManifest)),
      ig_game:document('游戏配置',JSON.stringify(baseContent)),ig_assets:document('资产配置',JSON.stringify(content.assets)),
      ig_levels:document('关卡配置',JSON.stringify(content.levels)),ig_music:document('曲目配置',JSON.stringify(content.music))}
  };
  for (const [id,item] of Object.entries(content.items)) {
    const child = {TY:'IT',MD:{MO:'EX'},BA:{NA:item.name,IC:item.icon||'inv_misc_coin_01',WE:0,VA:0},HA:[],LI:{},SC:{},IN:{}};
    if (item.stack) child.BA.ST = item.stack;
    else {
      child.BA.US=true; child.US={SC:'onUse',AC:'查看测试装备'}; child.LI.OU='onUse';
      child.SC.onUse=workflow(`effect("text",args,${luaString(item.name + '：')}..getVar(args,"o","IG_EQUIP_V1"),1)`);
    }
    root.IN[item.innerId] = child;
  }
  validateObject(root); Object.assign(root, scanSecurity(manifest.rootId,root));
  const validateLua = object => {
    for (const wf of Object.values(object.SC || {})) for (const step of Object.values(wf.ST)) for (const e of step.e || []) {
      if (e.id==='script') {
        assert(!e.args[0].includes('\r'), 'TRP3 script arguments must use canonical LF line endings');
        luaparse.parse(e.args[0],{luaVersion:'5.1'});
      }
      if (e.id==='secure_macro') luaparse.parse(e.args[0].replace(/^\/run /,''),{luaVersion:'5.1'});
    }
    Object.values(object.IN || {}).forEach(validateLua);
  };
  validateLua(root);
  const tuple = [manifest.target.extendedBuild,manifest.rootId,root,manifest.target.extendedDisplayVersion];
  const encoded = encodeExport(tuple); assert(encoded.length < 500000, 'Short export exceeds 500,000 characters');
  const sizes={sourceBytes:Buffer.byteLength(bundle),exportCharacters:encoded.length,macroCharacters:macro.length,macroBytes:bootstrap.macroBytes,macroLimit:255,
    unminifiedSourceBytes:Buffer.byteLength(debugBundle),engineSourceBytes:Object.values(sourceFiles).reduce((n,s)=>n+Buffer.byteLength(s),0)};
  // Release budgets do not prevent building readable diagnostics locally.
  if (settings.profile==='release') checkBudgets(sizes,settings.budgets);
  const typed = decodeExport(encoded,true);
  assert(typed instanceof Map && typed.get(3).get('SC').get('onUse').get('ST').has('1'), 'Workflow key type corrupted');
  assert(!typed.get(3).get('SC').get('onUse').get('ST').has(1), 'Workflow nodes must remain string keys');
  assert(typed.get(3).get('SC').get('wf_bootstrap').get('ST').get('1').get('e').get(1).get('args').get(1) === bundle, 'Lua source bytes changed');
  const objectHash = digest(serializeAce(root));
  if (options.previous) {
    const prev = JSON.parse(await readFile(resolve(options.previous),'utf8'));
    for (const key of ['rootId','publisher','createdAt']) assert(prev[key]===manifest[key], `Published identity changed: ${key}`);
    assert(manifest.objectVersion>prev.objectVersion,'Published objectVersion must increase');
    assert(effectiveHash!==(prev.effectiveHash||prev.sourceHash),'No effective change since previous release');
  }
  const report = { format:'TRP3 Extended short export', candidateStatus:'requires-in-game-verification', rootId:manifest.rootId,
    publisher:manifest.publisher,createdAt:manifest.createdAt,objectVersion:manifest.objectVersion,releaseVersion:manifest.releaseVersion,
    target:manifest.target,sourceHash,effectiveHash,generatorHash,objectHash,exportHash:digest(encoded),
    engine: { path: relative(base, engineRoot).replaceAll('\\','/'), apiVersion: manifest.engineApiVersion,version:catalog.version },
    packages:packagePlan, build:settings, packageLockHash:digest(JSON.stringify(lock)),
    toolchain:{node:process.versions.node,zlib:process.versions.zlib,luaparse:luaparse.version},
    sourceFiles:sourceHashes,
    gameModules:Object.fromEntries(Object.entries(gameModules).map(([k,v])=>[k,{path:manifest.modules[k],hash:digest(v)}])),
    sizes,
    sizeBreakdown:{engine:Object.fromEntries(Object.entries(sourceFiles).map(([k,v])=>[k,Buffer.byteLength(v)])),
      game:Object.fromEntries([...Object.entries(gameModules),['entry',gameSource]].map(([k,v])=>[k,Buffer.byteLength(v)])),
      documents:Object.fromEntries(Object.entries(root.IN).filter(([,v])=>v.TY==='DO').map(([k,v])=>[k,Buffer.byteLength(v.PA[0].TX)]))},
    bootstrap:{workflowOrder:['secure_macro','delay','script'],delaySeconds:bootstrap.delay,injectionTimeoutSeconds:bootstrap.timeout},
    checks:{typedRoundTrip:true,sourceByteEquality:true,canonicalLuaLineEndings:true,structuralValidation:true,securityScan:true,lua51Syntax:true,
      packageDependencies:true,sizeBudgets:true,minifiedASTEquality:settings.profile==='release',frozenLockfile:options.frozenLockfile===true},
    security:{level:root.securityLevel,details:root.details}, inGameVerified:false };
  const out = resolve(options.out || join(base,'dist'));
  if (options.verifyOnly) {
    const current = (await readFile(join(out,'item.t3e.txt'),'utf8')).trim(); assert(current===encoded,'Existing build is stale');
    return report;
  }
  await mkdir(out,{recursive:true});
  const outputs = { 'item.t3e.txt':encoded+'\n','item.decoded.json':JSON.stringify({exportTuple:decodeExport(encoded),summary:report},null,2)+'\n',
    'build-report.json':JSON.stringify(report,null,2)+'\n','engine.generated.lua':bundle,'bootstrap-macro.txt':macro,'bootstrap-launch.lua':bootstrap.launch,
    'engine.debug.lua':debugBundle,'engine.source-map.json':JSON.stringify({schemaVersion:1,sourceHash,outputHash:digest(bundle),debugHash:digest(debugBundle),
      offsets:'UTF-16 code units; line numbers are 1-based',columns:['outputOffset','debugOffset','debugLine','outputLine'],tokens:compilation.map,sections:sourceSections})+'\n',
    'package-lock.json':JSON.stringify(lock,null,2)+'\n'};
  // Validate everything before touching any previous successful artifact.
  for (const [name,text] of Object.entries(outputs)) await writeFile(join(out,name+'.tmp'),text,'utf8');
  for (const name of Object.keys(outputs)) await rename(join(out,name+'.tmp'),join(out,name));
  if (options.updateLock) {
    await writeFile(lockPath+'.tmp',JSON.stringify(lock,null,2)+'\n','utf8');
    await rename(lockPath+'.tmp',lockPath);
  }
  return report;
}
if (process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  const [manifestPath,...args]=process.argv.slice(2);
  if (manifestPath==='--list-packages') console.log(JSON.stringify(await readPackageCatalog(),null,2));
  else if (!manifestPath) { console.error('Usage: node tools/build-item-game.mjs <item.json> [--profile development|release] [--update-lock|--frozen-lockfile] [--verify-only] [--out path] [--previous report]\n       node tools/build-item-game.mjs --list-packages'); process.exitCode=1; }
  else {
    const options={};
    try {
      for (let i=0;i<args.length;i++) {
        if (args[i]==='--verify-only') options.verifyOnly=true;
        else if (args[i]==='--update-lock') options.updateLock=true;
        else if (args[i]==='--frozen-lockfile') options.frozenLockfile=true;
        else if (['--out','--previous','--saved-at','--profile'].includes(args[i])) { const k={'--out':'out','--previous':'previous','--saved-at':'savedAt','--profile':'profile'}[args[i]]; assert(args[i+1], 'Missing option value'); options[k]=args[++i]; }
        else throw new Error('Unknown option '+args[i]);
      }
      console.log(JSON.stringify(await build(manifestPath,options),null,2));
    } catch (err) { console.error(err.message); process.exitCode=1; }
  }
}
