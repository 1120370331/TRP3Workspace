// Generate an opt-in, in-memory native WoW probe using the exact engine and recipes.
// Paste the generated Lua into the development input; it never writes a game save.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
const source=await readFile(resolve(root,'framework/item-game/effects.lua'),'utf8');
const recipe=await readFile(resolve(root,'items/garden-defense-wow/src/vfx.lua'),'utf8');
const data=JSON.parse(await readFile(resolve(root,'items/garden-defense-wow/content.json'),'utf8'));
const probe=await readFile(resolve(root,'tools/particle-client-probe.lua'),'utf8');
const content={viewport:{width:900,height:330},limits:{maxParticles:256,maxEmitters:16,maxParticleSpawnsPerStep:96},assets:{textures:data.assets.textures},effects:data.effects};
content.effects.load={...data.effects.ice_shards,mode:'continuous',rate:256,lifetime:1,initialBurst:0,maxAlive:256,offsetX:[-330,330],offsetY:[-110,110],speed:12};
const hash=createHash('sha256').update(source+recipe+JSON.stringify(content)+probe).digest('hex');
const lua=`local E={util=TRP3_ItemGame.util,JSON=TRP3_ItemGame.JSON,newTelemetry=TRP3_ItemGame.newTelemetry}\n(function()\n${source}\nend)()(E,_G)\nlocal recipe=(function()\n${recipe}\nend)()\nlocal content=E.JSON.decode([==[${JSON.stringify(content)}]==])\nlocal sourceHash="${hash}"\n${probe}`;
await mkdir(resolve(root,'.test-output'),{recursive:true});
await writeFile(resolve(root,'.test-output/particle-client-probe.lua'),lua);
console.log(JSON.stringify({path:resolve(root,'.test-output/particle-client-probe.lua'),sourceHash:hash,bytes:Buffer.byteLength(lua)}));
