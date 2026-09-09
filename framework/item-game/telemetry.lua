return function(E, G)
    local floor, ceil = math.floor, math.ceil
    local function meter(quantum)
        local self = { n = 0, sum = 0, max = 0, bins = {}, quantum = quantum }
        function self.add(value)
            if not E.util.finite(value) or value < 0 then return end
            self.n = self.n + 1; self.sum = self.sum + value; self.max = math.max(self.max, value)
            local bucket = ceil(value / quantum)
            self.bins[bucket] = (self.bins[bucket] or 0) + 1
        end
        function self.summary()
            if self.n == 0 then return { count = 0, available = false } end
            local keys = {}; for k in pairs(self.bins) do keys[#keys + 1] = k end; table.sort(keys)
            local function q(f)
                local target, seen = ceil(self.n * f), 0
                for _, k in ipairs(keys) do seen = seen + self.bins[k]; if seen >= target then return k * quantum end end
            end
            return { count = self.n, mean = self.sum / self.n, max = self.max, p50 = q(.5), p95 = q(.95), p99 = q(.99), quantileResolutionMs = quantum }
        end
        return self
    end
    E.newMeter = meter
    function E.newTelemetry(host, metadata, options)
        options = options or {}
        local self = { phase = nil, completed = 0, records = {}, dropped = 0, droppedSummaries = 0, nextPhase = 0, frameCount = 0, counters = {} }
        local started, sampleAt = host.now(), host.now()
        metadata = E.util.copy(metadata)
        metadata.hostKind = host.kind; metadata.schema = "trp3-item-perf/1"
        metadata.clock = host.profileClock; metadata.startedAt = host.date()
        local header = { type = "run.start", t = 0, data = metadata }
        function self.note(kind, data)
            local record = { type = kind, t = host.now() - started, data = data or {} }
            self.records[#self.records + 1] = record
            if #self.records > 480 then
                if self.records[1].type=="phase.end" then self.droppedSummaries=self.droppedSummaries+1 end
                table.remove(self.records, 1); self.dropped = self.dropped + 1
            end
        end
        function self.increment(name, amount) self.counters[name] = (self.counters[name] or 0) + (amount or 1) end
        function self.finish(status, resources)
            local p = self.phase
            if not p then return end
            resources=resources or {}
            if status=="complete" and (p.metadata.expectedModels or 0)>(resources.loadedModels or 0) then status="models_not_verified" end
            if status=="complete" and p.metadata.kind=="music" and resources.musicBackend=="silent" then status="music_not_started" end
            local summaries = {}; for name, m in pairs(p.meters) do summaries[name] = m.summary() end
            local summary={
                id = p.id, name = p.name, status = status or "complete", metadata = p.metadata,
                measuredSeconds = p.measureStart and host.now() - p.measureStart or 0,
                frames = p.frames, framesOver33Ms = p.longFrames, metrics = summaries,
                counters = E.util.copy(self.counters), resources = resources or {},
            }
            self.lastPhase=summary;self.note("phase.end",summary)
            self.phase = nil; self.completed = self.completed + 1
        end
        function self.begin(name, phaseMetadata, options)
            if self.phase then self.finish("interrupted") end
            options = options or {}; self.nextPhase = self.nextPhase + 1; self.counters = {}
            local now = host.now()
            self.phase = {
                id = self.nextPhase, name = name, metadata = E.util.copy(phaseMetadata or {}),
                start = now, warmUntil = now + (options.warmup or 2), duration = options.duration or 10,
                measuring = false, frames = 0, longFrames = 0, meters = {},
            }
            sampleAt = now
            self.note("phase.start", { id = self.nextPhase, name = name, warmup = options.warmup or 2, duration = options.duration or 10, metadata = phaseMetadata or {} })
        end
        function self.beforeFrame()
            local p = self.phase
            if p and not p.measuring and host.now() >= p.warmUntil then
                p.measuring = true; p.measureStart = host.now(); sampleAt = host.now();self.counters={}
            end
        end
        function self.record(name, milliseconds)
            local p = self.phase
            if not p or not p.measuring then return end
            p.meters[name] = p.meters[name] or meter(name == "frameMs" and .1 or .01)
            p.meters[name].add(milliseconds)
        end
        function self.snapshot()
            local p=self.phase
            if not p then return {active=false,hostKind=host.kind,hostFPS=host.fps(),last=self.lastPhase and E.util.copy(self.lastPhase)} end
            local metrics={};for name,m in pairs(p.meters)do metrics[name]=m.summary()end
            return {active=true,hostKind=host.kind,hostFPS=host.fps(),name=p.name,measuring=p.measuring,
                seconds=p.measureStart and host.now()-p.measureStart or 0,duration=p.duration,frames=p.frames,metrics=metrics}
        end
        function self.afterFrame(elapsed, luaMs, stats)
            self.frameCount = self.frameCount + 1
            local p = self.phase
            if not p or not p.measuring then return end
            p.frames = p.frames + 1
            if elapsed > 1 / 30 then p.longFrames = p.longFrames + 1 end
            self.record("frameMs", elapsed * 1000); self.record("luaFrameMs", luaMs)
            local now = host.now()
            if now - sampleAt >= 1 then
                sampleAt = now
                self.note("sample", { phaseId = p.id, seconds = now - p.measureStart, frames = p.frames,
                    frameMs = p.meters.frameMs.summary(), luaFrameMs = p.meters.luaFrameMs.summary(),
                    resources = stats(), counters = E.util.copy(self.counters), memoryKB = host.memoryKB(), hostFPS = host.fps() })
            end
            if now - p.measureStart >= p.duration then self.finish("complete", stats()) end
        end
        function self.export(maxBytes)
            local limit = math.min(maxBytes or 190000, options.maxBytes or 190000)
            local lines = { E.JSON.encode(header) }
            local selected, encoded, count, bytes, summariesDropped = {}, {}, 0, #lines[1]+1, self.droppedSummaries
            for i=1,#self.records do encoded[i]=E.JSON.encode(self.records[i]) end
            -- Prefer summaries over periodic samples, but preserve chronological order.
            for pass=1,2 do
                for i=#self.records,1,-1 do
                    local sample=self.records[i].type=="sample"
                    if (pass==1 and not sample) or (pass==2 and sample) then
                        if bytes+#encoded[i]+1<=limit-220 then selected[i]=true;count=count+1;bytes=bytes+#encoded[i]+1
                        elseif self.records[i].type=="phase.end" then summariesDropped=summariesDropped+1 end
                    end
                end
            end
            local omitted = self.dropped + #self.records - count
            lines[#lines + 1] = E.JSON.encode({ type = "log.status", t = host.now() - started, data = { droppedRecords = omitted, droppedSummaries=summariesDropped, phaseActive = self.phase ~= nil } })
            for i=1,#self.records do if selected[i] then lines[#lines+1]=encoded[i] end end
            return table.concat(lines, "\n") .. "\n"
        end
        function self.close(reason, stats)
            self.finish(reason == "complete" and "complete" or "stopped", stats and stats() or nil)
            self.note("run.end", { reason = reason, frames = self.frameCount, seconds = host.now() - started })
        end
        return self
    end
end
