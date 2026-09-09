#!/usr/bin/env node
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, dirname, basename, extname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

export function analyze(text, {includeMock=false}={}) {
  const records=text.replace(/^\uFEFF/,'').split(/\r?\n/).filter(line=>line.trim()).map((line,index)=>{
    try {const r=JSON.parse(line);if(!r||typeof r.type!=='string')throw new Error('record.type required');return r;}
    catch(err){throw new Error(`Invalid NDJSON line ${index+1}: ${err.message}`);}
  });
  const start=records.find(r=>r.type==='run.start');
  if(!start||start.data?.schema!=='trp3-item-perf/1')throw new Error('Expected trp3-item-perf/1 run.start header');
  const metadata=start.data;
  const mock=metadata.hostKind!=='wow'||metadata.clientVersion==='MOCK';
  if(mock&&!includeMock)throw new Error('Mock/non-WoW log rejected as performance evidence. Use --include-mock only for diagnostics.');
  const phases=records.filter(r=>r.type==='phase.end').map(r=>({
    id:r.data.id,name:r.data.name,status:r.data.status,workload:r.data.metadata||{},
    duration:r.data.measuredSeconds,frames:r.data.frames,framesOver33Ms:r.data.framesOver33Ms,
    metrics:r.data.metrics||{},resources:r.data.resources||{},counters:r.data.counters||{},
    fpsFromMean:r.data.metrics?.frameMs?.mean>0?1000/r.data.metrics.frameMs.mean:null,
  }));
  const errors=records.filter(r=>r.type==='error'||r.type==='music.error');
  const musicPlayback=records.filter(r=>r.type==='music.playback'||r.type==='check.music');
  const logStatus=records.find(r=>r.type==='log.status')?.data||{};
  const warnings=[];
  if(mock)warnings.push('这是模拟宿主的功能验证日志，不能代表 WoW 性能。');
  if(logStatus.droppedRecords)warnings.push(`已裁剪 ${logStatus.droppedRecords} 条记录；阶段汇总丢失 ${logStatus.droppedSummaries||0} 条。`);
  if(logStatus.phaseActive)warnings.push('导出时仍有未结束的采样阶段；本报告仅比较已有阶段汇总。');
  if(!phases.length)warnings.push('没有阶段汇总。先检查启动或错误记录，不能据此判断性能。');
  if(phases.some(p=>p.status!=='complete'))warnings.push('存在暂停、中断、模型未验证或音频未起播的阶段；这些阶段不视为完整负载的合格样本。');
  if(phases.some(p=>(p.counters.droppedSimulationMs||0)+(p.counters.clampedSimulationMs||0)>0))warnings.push('出现逻辑补算丢弃/时间截断；已记录其毫秒数，需结合卡顿和玩法时间偏差分析。');
  if(errors.length)warnings.push(`发现 ${errors.length} 条错误记录。`);
  if(musicPlayback.some(r=>r.data?.ok===false))warnings.push('有 BGM 起播失败记录；请查看音频诊断中的通道、静音设置、音量与原因。');
  const baseline=phases.find(p=>p.name==='baseline_empty'&&p.status==='complete');
  const comparisons=baseline?phases.filter(p=>p.status==='complete').map(p=>({
    id:p.id,name:p.name,
    meanFrameDeltaMs:(p.metrics.frameMs?.mean??0)-(baseline.metrics.frameMs?.mean??0),
    meanLuaDeltaMs:(p.metrics.luaFrameMs?.mean??0)-(baseline.metrics.luaFrameMs?.mean??0),
  })):[];
  return {schema:'trp3-item-perf-analysis/1',metadata,mock,logStatus,phases,comparisons,errors,musicPlayback,warnings,
    notes:['frameMs 是窗口 OnUpdate 的实际间隔；luaFrameMs 是引擎 Lua 帧耗时，不包括全部原生/GPU 工作。',
      'P50/P95/P99 为直方图近似上界，精度记录在 quantileResolutionMs；模块指标按调用计数，不能相加各自 P95。',
      'baseline_empty 是空引擎窗口基线，不是关闭所有插件或关闭引擎的客户端基线。',
      '音频调用成功不等于实际可听，模型加载不等于视觉与坐标已经验收。']};
}
const number=n=>typeof n==='number'&&Number.isFinite(n)?n.toFixed(2):'—';
const safe=s=>String(s??'').replaceAll('|','\\|').replace(/[\r\n]/g,' ');
export function markdown(report) {
  const m=report.metadata;
  const lines=['# TRP3 性能日志分析','',`游戏：${safe(m.gameId)} / 引擎 ${safe(m.engineVersion)} / 对象版本 ${safe(m.objectVersion)}`,
    `客户端：${safe(m.clientVersion)}（${safe(m.clientBuild)}） / 宿主：${safe(m.hostKind)}`,
    `源码哈希：\`${safe(m.sourceHash)}\``,''];
  if(report.warnings.length){lines.push('## 需要关注','',...report.warnings.map(w=>'- '+w),'');}
  lines.push('## 阶段结果','', '| 阶段 | 状态 | 帧数 | 平均 FPS | 帧 P95 ms | 帧 P99 ms | Lua P95 ms | 实体 | 已加载模型 |',
    '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  for(const p of report.phases)lines.push(`| ${safe(p.name)} | ${safe(p.status)} | ${p.frames} | ${number(p.fpsFromMean)} | ${number(p.metrics.frameMs?.p95)} | ${number(p.metrics.frameMs?.p99)} | ${number(p.metrics.luaFrameMs?.p95)} | ${p.resources.entities??'—'} | ${p.resources.loadedModels??'—'} |`);
  if(report.musicPlayback?.length){
    lines.push('','## 音频诊断','','成功只表示客户端接受了播放请求；实际可听需在游戏内确认。','',
      '| 记录 | 曲目 / FileDataID | 通道 | 起播 | 原因 | 当时声音设置 |',
      '| --- | --- | --- | --- | --- | --- |');
    for(const r of report.musicPlayback){
      const d=r.data||{};
      lines.push(`| ${safe(r.type)} | ${safe(d.trackId)} / ${safe(d.fileID)} | ${safe(d.channel)} | ${d.ok===true?'成功':d.ok===false?'失败':'未知'} | ${safe(d.reason)} | ${safe(d.audio?.cvars?JSON.stringify(d.audio.cvars):'旧记录或未调用音频 API，无设置快照')} |`);
    }
  }
  const particlePhases=report.phases.filter(p=>p.resources.activeParticles!==undefined);
  if(particlePhases.length){
    lines.push('','## 粒子开销','','| 阶段 | 活动 / 可见 | 池 | 更新 P95 ms | 绘制 P95 ms | 丢弃 / 淘汰 |','| --- | ---: | ---: | ---: | ---: | ---: |');
    for(const p of particlePhases)lines.push(`| ${safe(p.name)} | ${p.resources.activeParticles} / ${p.resources.visibleParticles??'—'} | ${p.resources.pooledParticles} | ${number(p.metrics.effectsMs?.p95)} | ${number(p.metrics.effectsRenderMs?.p95)} | ${p.counters.particlesDropped??0} / ${p.counters.particlesEvicted??0} |`);
  }
  lines.push('','## 如何判断','',...report.notes.map(n=>'- '+n),'',
    '- 先看模型/音频阶段状态和实际负载，再比较同一客户端、画质、地点下的完整阶段。',
    '- Grid 与 Naive 应使用相同对象数和查询次数；对比 queryBatchMs 与 queryCandidates。',
    '- 看 baseline_after_load 是否恢复、池对象是否趋稳；保留池内对象本身不等于泄漏。',
    '- 详细模块分布、资源数、错误与相对基线差值见 summary.json，表格导入用 phases.csv。','');
  if(report.errors.length){lines.push('## 错误','');for(const e of report.errors)lines.push(`- ${safe(e.data?.stage||e.type)}：${safe(e.data?.message||e.data?.reason)}`);}
  return lines.join('\n')+'\n';
}
export function csv(report) {
  const columns=['phase','status','requested','frames','fpsFromMean','frameMeanMs','frameP95Ms','frameP99Ms','luaMeanMs','luaP95Ms','renderMeanMs','collisionMeanMs','aiMeanMs','queryBatchMeanMs','entities','activeModels','loadedModels','pooledTextures','pooledModels','pooledActors','droppedSimulationMs','clampedSimulationMs'];
  const rows=report.phases.map(p=>[p.name,p.status,p.workload.requested,p.frames,p.fpsFromMean,p.metrics.frameMs?.mean,p.metrics.frameMs?.p95,p.metrics.frameMs?.p99,
    p.metrics.luaFrameMs?.mean,p.metrics.luaFrameMs?.p95,p.metrics.renderMs?.mean,p.metrics.collisionMs?.mean,p.metrics.aiMs?.mean,p.metrics.queryBatchMs?.mean,
    p.resources.entities,p.resources.activeModels,p.resources.loadedModels,p.resources.pooledTextures,p.resources.pooledModels,p.resources.pooledActors,p.counters.droppedSimulationMs,p.counters.clampedSimulationMs]);
  const cell=v=>'"'+String(v??'').replaceAll('"','""')+'"';
  return '\ufeff'+[columns,...rows].map(row=>row.map(cell).join(',')).join('\r\n')+'\r\n';
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{
    const [file,...args]=process.argv.slice(2);if(!file)throw new Error('Usage: node tools/analyze-perf-log.mjs log.ndjson [--out directory] [--include-mock]');
    let out=resolve(dirname(file),basename(file,extname(file))+'.analysis');let includeMock=false;
    for(let i=0;i<args.length;i++){if(args[i]==='--include-mock')includeMock=true;else if(args[i]==='--out'&&args[i+1])out=resolve(args[++i]);else throw new Error('Unknown/missing option '+args[i]);}
    const report=analyze(await readFile(resolve(file),'utf8'),{includeMock});await mkdir(out,{recursive:true});
    await Promise.all([writeFile(join(out,'summary.json'),JSON.stringify(report,null,2)+'\n'),writeFile(join(out,'report.md'),markdown(report)),writeFile(join(out,'phases.csv'),csv(report))]);
    console.log(JSON.stringify({out,phases:report.phases.length,errors:report.errors.length,warnings:report.warnings},null,2));
  }catch(error){console.error(error.message);process.exitCode=1;}
}
