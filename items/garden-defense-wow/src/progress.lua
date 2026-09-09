-- Per-slot, pure-data progress. The caller owns persistence and notifications.
local LIMIT = 1000000000
local plantIds = {"pea", "sunflower", "cherry", "wall", "mine", "snow", "chomper", "repeater", "puff", "sunshroom"}
local enemyIds = {"basic", "flag", "cone", "bucket", "pole", "paper", "abomination", "necromancer"}
local statIds = {"seconds", "runsStarted", "wins", "losses", "kills", "sunCollected", "sunSpent", "plantsPlaced", "mowersUsed", "noMowerWins", "cleared", "endlessRuns", "endlessBestRound", "endlessBestScore"}
local definitions = {
    {id="first_plant", title="种下希望", description="首次部署一名守卫。", field="plantsPlaced", target=1},
    {id="first_win", title="首次凯旋", description="成功守住任意一关。", field="firstWin", target=1},
    {id="clean_win", title="防线固若金汤", description="不使用割草机赢得一局。", field="noMowerWins", target=1},
    {id="hundred_kills", title="天灾克星", description="累计消灭 100 名天灾敌人。", field="kills", target=100},
    {id="thousand_sun", title="日光收藏家", description="累计收集 1,000 点阳光。", field="sunCollected", target=1000},
    {id="all_guardians", title="百花齐放", description="部署过全部 10 种守卫。", field="plantKindsUsed", target=10},
    {id="five_levels", title="半程守护者", description="通关前 5 关。", field="cleared", target=5},
    {id="ten_levels", title="艾泽拉斯园丁", description="通关全部 10 关。", field="cleared", target=10},
    {id="abomination", title="拆解憎恶", description="消灭一只憎恶。", enemy="abomination", target=1},
    {id="necromancer", title="终结死灵术", description="消灭一名通灵师。", enemy="necromancer", target=1},
}

local function finite(value)
    if type(value) ~= "number" and type(value) ~= "string" then return nil end
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

local function bounded(value, limit, fraction)
    local n = math.max(0, math.min(limit or LIMIT, finite(value) or 0))
    return fraction and n or math.floor(n)
end

local function validIndex(value, limit)
    local n = finite(value)
    if n and n >= 1 and n <= limit and n == math.floor(n) then return n end
end

local function asTable(value)
    return type(value) == "table" and value or {}
end

local function copyCounts(source, ids)
    local result = {}
    source = asTable(source)
    for _, id in ipairs(ids) do result[id] = bounded(source[id]) end
    return result
end

local function new(saved, seed)
    saved, seed = asTable(saved), asTable(seed)
    local original = asTable(saved.stats)
    local data = {
        version=1, stats={},
        plantsByKind=copyCounts(saved.plantsByKind, plantIds),
        killsByKind=copyCounts(saved.killsByKind, enemyIds),
        bestTimes={}, unlocked={},
    }
    for _, id in ipairs(statIds) do
        data.stats[id] = bounded(original[id], id == "cleared" and 10 or LIMIT, id == "seconds")
    end
    -- Old saves only prove campaign progress, not historical event totals.
    data.stats.cleared = math.max(data.stats.cleared, bounded(seed.cleared, 10))
    local oldTimes, oldUnlocks = asTable(saved.bestTimes), asTable(saved.unlocked)
    for level=1,10 do
        local key = tostring(level)
        local duration = finite(oldTimes[key] or oldTimes[level])
        if duration and duration >= 0 then data.bestTimes[key] = math.min(LIMIT, duration) end
    end
    for _, def in ipairs(definitions) do
        if oldUnlocks[def.id] == true then data.unlocked[def.id] = true end
    end

    local function kindCount()
        local count = 0
        for _, id in ipairs(plantIds) do
            if data.plantsByKind[id] > 0 then count = count + 1 end
        end
        return count
    end

    local function current(def)
        if def.enemy then return data.killsByKind[def.enemy] end
        if def.field == "plantKindsUsed" then return kindCount() end
        if def.field == "firstWin" then
            return (data.stats.wins > 0 or data.stats.cleared > 0) and 1 or 0
        end
        return data.stats[def.field]
    end

    local function achievement(def)
        local unlocked = data.unlocked[def.id] == true
        return {
            id=def.id, title=def.title, description=def.description,
            current=unlocked and def.target or math.min(def.target, current(def)),
            target=def.target, unlocked=unlocked,
        }
    end

    local function unlock()
        local gained = {}
        for _, def in ipairs(definitions) do
            if not data.unlocked[def.id] and current(def) >= def.target then
                data.unlocked[def.id] = true
                gained[#gained+1] = achievement(def)
            end
        end
        return gained
    end

    local function add(field, value)
        data.stats[field] = math.min(LIMIT, data.stats[field] + (value or 1))
    end

    local function record(event, payload)
        payload = asTable(payload)
        if event == "time" then
            add("seconds", bounded(payload.seconds, LIMIT, true))
        elseif event == "run_started" then
            if not validIndex(payload.level, 10) then return {} end
            add("runsStarted")
            if payload.mode == "endless" then add("endlessRuns") end
        elseif event == "plant" then
            if not data.plantsByKind[payload.kind] then return {} end
            add("plantsPlaced")
            add("sunSpent", bounded(payload.cost))
            data.plantsByKind[payload.kind] = math.min(LIMIT, data.plantsByKind[payload.kind] + 1)
        elseif event == "sun" then
            add("sunCollected", bounded(payload.amount))
        elseif event == "kill" then
            if not data.killsByKind[payload.kind] then return {} end
            add("kills")
            data.killsByKind[payload.kind] = math.min(LIMIT, data.killsByKind[payload.kind] + 1)
        elseif event == "mower" then
            if not validIndex(payload.row, 5) then return {} end
            add("mowersUsed")
        elseif event == "endless_progress" then
            local round, score = validIndex(payload.round, 1000000), bounded(payload.score)
            if not round then return {} end
            data.stats.endlessBestRound = math.max(data.stats.endlessBestRound, round)
            data.stats.endlessBestScore = math.max(data.stats.endlessBestScore, score)
        elseif event == "win" or event == "loss" then
            local level = validIndex(payload.level, 10)
            if not level then return {} end
            add(event == "win" and "wins" or "losses")
            if event == "win" then
                data.stats.cleared = math.max(data.stats.cleared, level)
                if payload.noMowersUsed == true then add("noMowerWins") end
                local duration, key = finite(payload.duration), tostring(level)
                if duration and duration >= 0 then
                    duration = math.min(LIMIT, duration)
                    if not data.bestTimes[key] or duration < data.bestTimes[key] then data.bestTimes[key] = duration end
                end
            end
            -- Durations only feed winning best times; "time" owns accumulated play time.
        else
            return {}
        end
        return unlock()
    end

    local function achievements()
        local result = {}
        for _, def in ipairs(definitions) do result[#result+1] = achievement(def) end
        return result
    end

    local function summary()
        local result = {}
        for _, id in ipairs(statIds) do result[id] = data.stats[id] end
        result.plantKindsUsed, result.achievementCount, result.achievementTotal = kindCount(), 0, #definitions
        result.bestTimes = {}
        for level=1,10 do result.bestTimes[tostring(level)] = data.bestTimes[tostring(level)] end
        result.plantsByKind = copyCounts(data.plantsByKind, plantIds)
        result.killsByKind = copyCounts(data.killsByKind, enemyIds)
        for _, def in ipairs(definitions) do
            if data.unlocked[def.id] then result.achievementCount = result.achievementCount + 1 end
        end
        return result
    end

    -- Reconcile restored totals/legacy campaign progress silently, once on load.
    unlock()
    return {data=data, record=record, summary=summary, achievements=achievements}
end

return {new=new}
