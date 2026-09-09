#!/usr/bin/env node
import {readdir,access} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {build} from './build-item-game.mjs';

try {
  const options={};
  const flags={'--update-lock':'updateLock','--frozen-lockfile':'frozenLockfile','--verify-only':'verifyOnly'};
  for (const flag of process.argv.slice(2)) {
    if (!Object.hasOwn(flags,flag)) throw new Error(`Unknown option: ${flag}`);
    options[flags[flag]]=true;
  }
  const items=new URL('../items/',import.meta.url);
  for (const entry of (await readdir(items,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))) {
    if (!entry.isDirectory()) continue;
    const input=new URL(entry.name+'/item.json',items);
    try { await access(input); } catch (err) { if (err.code==='ENOENT') continue;throw err; }
    const report=await build(fileURLToPath(input),options);
    console.log(`${entry.name}: ${report.build.profile}; ${report.packages.resolved.join(', ')}; ${report.sizes.sourceBytes} source bytes; ${report.sizes.exportCharacters} export characters`);
  }
} catch (err) { console.error(err.message);process.exitCode=1; }
