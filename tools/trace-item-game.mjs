#!/usr/bin/env node
import {readFile} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';

export async function traceLine(directory,line) {
  if (!Number.isSafeInteger(line) || line<1) throw new Error('Line must be a positive integer');
  const map=JSON.parse(await readFile(join(directory,'engine.source-map.json'),'utf8'));
  const code=await readFile(join(directory,'engine.generated.lua'),'utf8');
  const debug=await readFile(join(directory,'engine.debug.lua'),'utf8');
  const hash=value=>createHash('sha256').update(value).digest('hex');
  if (map.outputHash!==hash(code) || map.debugHash!==hash(debug)) throw new Error('Source map does not match generated/debug Lua');
  if (line>code.split('\n').length) throw new Error('Line exceeds generated Lua');
  const token=map.tokens?.findLast(t=>t[3]<=line);
  const debugLine=token ? token[2]+line-token[3] : line;
  const section=map.sections.find(s=>debugLine>=s.startLine && debugLine<=s.endLine);
  return {sourceHash:map.sourceHash,generatedLine:line,debugLine,
    source:section?.path ?? 'engine.debug.lua',line:section?debugLine-section.startLine+1:debugLine,
    text:debug.split('\n')[debugLine-1]};
}
if (process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  try {
    if (!process.argv[2] || !process.argv[3] || process.argv.slice(4).some(flag=>flag!=='--trp3')) throw new Error('Usage: node tools/trace-item-game.mjs <dist directory> <Lua line> [--trp3]');
    // Pinned TRP3 runLuaScriptEffect prepends "return function(args)\n".
    const line=Number(process.argv[3])-(process.argv.includes('--trp3')?1:0);
    console.log(JSON.stringify(await traceLine(resolve(process.argv[2]),line),null,2));
  } catch (err) { console.error(err.message);process.exitCode=1; }
}
