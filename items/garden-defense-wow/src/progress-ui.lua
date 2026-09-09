-- Draw-only overlay. The owner supplies the surface lifecycle and navigation.
return function(surface, state, actions)
    local gold, cream, muted = {1,.78,.33,1}, {1,.94,.77,1}, {.72,.70,.61,1}
    local active = state.tab == "achievements" and "achievements" or "stats"
    local summary, achievements = state.summary or {}, state.achievements or {}
    local function draw(id, options) surface.draw("progress."..id, options) end
    local function text(id, value, x, y, w, h, size, color, layer)
        draw(id, {kind="text", text=value, x=x, y=y, w=w, h=h,
            size=size or 15, color=color or cream, layer=layer or 24})
    end
    local function rect(id, x, y, w, h, color, layer)
        draw(id, {kind="rect", x=x, y=y, w=w, h=h, color=color, layer=layer or 23})
    end
    local function button(id, label, x, y, w, h, callback, selected)
        draw(id, {kind="button", text=label, x=x, y=y, w=w, h=h, size=16,
            asset="ground_elwynn_wood", color=selected and {.88,.68,.36,1} or {.56,.46,.32,1},
            layer=25, onClick=function()
                callback()
                actions.clickSound()
                actions.redraw()
            end})
    end
    local function count(value) return tostring(math.floor(value or 0)) end
    local function clock(value)
        local seconds = math.floor(value or 0)
        local hours = math.floor(seconds / 3600)
        local minutes = math.floor(seconds / 60) % 60
        if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, seconds % 60) end
        return string.format("%d:%02d", minutes, seconds % 60)
    end

    draw("shield", {kind="button", text="", x=0, y=0, w=960, h=600,
        layer=20, color={.015,.012,.008,.90}, onClick=function() end})
    draw("frame", {kind="texture", asset="ground_elwynn_road", x=32, y=24, w=896, h=552,
        layer=21, color={.66,.54,.32,1}})
    draw("panel", {kind="texture", asset="ui_leather_background", x=38, y=30, w=884, h=540,
        layer=22, color={.40,.32,.23,1}})
    text("title", "花园手册", 62, 45, 260, 38, 26, gold)
    text("scope", "当前存档 · "..count(summary.cleared).." / 10 关 · 成就 "..
        count(summary.achievementCount).." / "..count(summary.achievementTotal or #achievements),
        400, 50, 494, 28, 16, cream)
    button("tab.stats", "战斗统计", 62, 98, 166, 38, function() actions.onTab("stats") end, active == "stats")
    button("tab.achievements", "成就手册", 240, 98, 166, 38, function() actions.onTab("achievements") end, active == "achievements")
    text("hint", "每一场守护，都记在这里。", 470, 102, 416, 28, 15, muted)
    rect("divider", 62, 146, 832, 2, {.64,.49,.27,.85})

    if active == "stats" then
        local metrics = {
            {"战斗时长", clock(summary.seconds)}, {"开局次数", count(summary.runsStarted)},
            {"胜利 / 失败", count(summary.wins).." / "..count(summary.losses)},
            {"消灭敌人", count(summary.kills)}, {"收集阳光", count(summary.sunCollected)},
            {"消耗阳光", count(summary.sunSpent)}, {"部署守卫", count(summary.plantsPlaced)},
            {"守卫种类", count(summary.plantKindsUsed).." / 10"},
            {"割草机出动", count(summary.mowersUsed)}, {"无割草机胜利", count(summary.noMowerWins)},
        }
        for i, metric in ipairs(metrics) do
            local x, y = 62 + ((i-1) % 5)*168, 162 + math.floor((i-1)/5)*87
            rect("stats.tile"..i, x, y, 160, 76, {.12,.095,.06,.67})
            text("stats.label"..i, metric[1], x+8, y+7, 144, 23, 14, muted)
            text("stats.value"..i, metric[2], x+8, y+34, 144, 31, 23, gold)
        end
        text("stats.endless", "无尽挑战：开局 "..count(summary.endlessRuns).." 次 · 最高第 "..
            count(summary.endlessBestRound).." 轮 · 最高 "..count(summary.endlessBestScore).." 分", 62, 329, 832, 22, 14, gold)
        text("stats.bestTitle", "各关最快通关", 62, 353, 390, 29, 19, gold)
        text("stats.bestHint", "按战局逻辑时间记录", 555, 358, 339, 23, 13, muted)
        for level=1,10 do
            local x, y = 62 + ((level-1) % 5)*168, 387 + math.floor((level-1)/5)*53
            local duration = summary.bestTimes and summary.bestTimes[tostring(level)]
            rect("stats.bestCell"..level, x, y, 160, 44, {.14,.11,.07,.64})
            text("stats.bestLevel"..level, "第 "..level.." 关", x+9, y+10, 63, 23, 13, muted)
            text("stats.bestTime"..level, duration and clock(duration) or "—", x+72, y+8, 80, 27, 18, duration and cream or muted)
        end
        text("stats.note", "旧存档保留已知通关进度；其余统计从启用手册后累计。", 62, 487, 832, 24, 13, muted)
    else
        for i, achievement in ipairs(achievements) do
            if i <= 10 then
                local x, y = 62 + ((i-1) % 2)*422, 160 + math.floor((i-1)/2)*67
                local color = achievement.unlocked and gold or muted
                rect("achievement.card"..i, x, y, 410, 59,
                    achievement.unlocked and {.27,.20,.10,.84} or {.11,.09,.065,.75})
                rect("achievement.accent"..i, x, y, 3, 59,
                    achievement.unlocked and {.94,.68,.22,1} or {.38,.32,.23,1})
                text("achievement.title"..i, achievement.title, x+12, y+4, 269, 23, 16, color)
                text("achievement.status"..i,
                    achievement.unlocked and "已达成" or (count(achievement.current).." / "..count(achievement.target)),
                    x+280, y+4, 119, 23, 13, color)
                text("achievement.description"..i, achievement.description, x+12, y+29, 386, 23, 13, cream)
            end
        end
        text("achievements.note", "成就记录你的旅程，不额外发放金币或道具。", 62, 499, 832, 20, 13, muted)
    end
    button("back", "返回", 735, 523, 159, 35, actions.onBack, false)
    text("footer", "三份花园，三份独立记录。", 62, 530, 620, 22, 13, muted)
end
