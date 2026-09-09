"""Focused Lua 5.1 progress persistence and draw-only overlay contracts."""
from pathlib import Path
import json
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / ".local-tools/python"))
from lupa.lua51 import LuaRuntime, lua_type

PROJECT = ROOT / "items/garden-defense-wow"


def plain(value):
    if lua_type(value) == "table":
        return {key: plain(item) for key, item in value.items()}
    return value


class ProgressTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.progress = self.lua.execute((PROJECT / "src/progress.lua").read_text("utf-8"))
        self.draw = self.lua.execute((PROJECT / "src/progress-ui.lua").read_text("utf-8"))

    def table(self, value):
        return self.lua.table_from(value, recursive=True)

    def record(self, tracker, event, **payload):
        return tracker.record(event, self.table(payload))

    def test_event_totals_best_times_and_one_time_unlocks(self):
        tracker = self.progress.new(None, None)
        gained = []

        def record(event, **payload):
            gained.extend(item.id for _, item in self.record(tracker, event, **payload).items())

        record("run_started", level=1)
        record("time", seconds=12.5)
        record("time", seconds=7.25)
        for kind in ("pea", "sunflower", "cherry", "wall", "mine", "snow", "chomper", "repeater", "puff", "sunshroom"):
            record("plant", kind=kind, cost=50)
        record("sun", amount=1000)
        for _ in range(98):
            record("kill", kind="basic")
        record("kill", kind="abomination")
        record("kill", kind="necromancer")
        record("win", level=1, duration=100, noMowersUsed=True)
        record("win", level=1, duration=80, noMowersUsed=False)
        record("win", level=1, duration=95, noMowersUsed=False)
        record("win", level=5, duration=300, noMowersUsed=False)
        record("win", level=10, duration=600, noMowersUsed=False)
        record("mower", row=3)
        record("loss", level=10, duration=700)
        stats = tracker.summary()
        self.assertEqual(len(gained), 10)
        self.assertEqual(len(set(gained)), 10)
        self.assertEqual(stats.seconds, 19.75, "outcome durations must not double-count time events")
        self.assertEqual((stats.runsStarted, stats.wins, stats.losses), (1, 5, 1))
        self.assertEqual((stats.kills, stats.sunCollected, stats.sunSpent), (100, 1000, 500))
        self.assertEqual((stats.plantsPlaced, stats.plantKindsUsed, stats.mowersUsed, stats.noMowerWins), (10, 10, 1, 1))
        self.assertEqual((stats.cleared, stats.achievementCount), (10, 10))
        self.assertEqual(stats.bestTimes["1"], 80)
        self.assertEqual(len(self.record(tracker, "win", level=10, duration=550, noMowersUsed=True)), 0)

    def test_serialized_reload_retains_unlocks_without_replaying_notifications(self):
        tracker = self.progress.new(None, None)
        self.assertEqual(len(self.record(tracker, "plant", kind="pea", cost=100)), 1)
        self.assertEqual(len(self.record(tracker, "win", level=1, duration=125.25, noMowersUsed=True)), 2)
        encoded = json.dumps(plain(tracker.data), allow_nan=False)
        restored = self.progress.new(self.table(json.loads(encoded)), self.table({"cleared": 1}))
        self.assertEqual(plain(restored.data), plain(tracker.data))
        self.assertEqual(len(self.record(restored, "plant", kind="pea", cost=100)), 0)
        self.assertEqual(len(self.record(restored, "win", level=1, duration=126, noMowersUsed=True)), 0)
        self.assertEqual(restored.summary().bestTimes["1"], 125.25)

    def test_endless_runs_round_and_score_keep_independent_bests(self):
        tracker = self.progress.new(None, self.table({"cleared": 10}))
        self.record(tracker, "run_started", level=10, mode="endless")
        self.record(tracker, "endless_progress", round=1, score=0)
        self.record(tracker, "endless_progress", round=3, score=250)
        self.record(tracker, "endless_progress", round=2, score=900)
        stats = tracker.summary()
        self.assertEqual((stats.endlessRuns, stats.endlessBestRound, stats.endlessBestScore), (1, 3, 900))
        before = plain(tracker.data)
        self.assertEqual(len(self.record(tracker, "endless_progress", round=0, score=9999)), 0)
        self.assertEqual(plain(tracker.data), before)
        restored = self.progress.new(self.table(json.loads(json.dumps(before))), self.table({"cleared": 10}))
        self.assertEqual((restored.summary().endlessBestRound, restored.summary().endlessBestScore), (3, 900))

    def test_legacy_seed_and_three_trackers_are_independent(self):
        original = self.progress.new(None, self.table({"cleared": 5}))
        second = self.progress.new(original.data, None)
        third = self.progress.new(None, None)
        stats = original.summary()
        self.assertEqual((stats.cleared, stats.achievementCount), (5, 2))
        self.assertEqual((stats.wins, stats.kills, stats.runsStarted, stats.seconds), (0, 0, 0, 0))
        self.assertEqual(plain(stats.bestTimes), {})
        self.record(second, "plant", kind="pea", cost=100)
        self.record(third, "kill", kind="abomination")
        self.assertEqual((original.summary().plantsPlaced, original.summary().kills), (0, 0))
        self.assertEqual((second.summary().plantsPlaced, second.summary().kills), (1, 0))
        self.assertEqual((third.summary().plantsPlaced, third.summary().kills), (0, 1))
        second.summary().plantsByKind["pea"] = 999
        self.assertEqual(second.summary().plantsByKind["pea"], 1)

    def test_malformed_save_is_finite_bounded_and_has_no_unbounded_maps(self):
        saved = self.table({
            "stats": {"seconds": float("nan"), "kills": float("inf"), "wins": -5, "sunCollected": "999999999999", "cleared": 99},
            "plantsByKind": {"pea": -1, "invented": 100},
            "killsByKind": {"basic": "4", "invented": 100},
            "bestTimes": {"1": -1, "2": float("inf"), "3": "125.5", "999": 10},
            "unlocked": {"first_plant": "true", "invented": True},
            "unexpected": {"arbitrary": "data"},
        })
        tracker = self.progress.new(saved, None)
        stats = tracker.summary()
        self.assertEqual((stats.seconds, stats.kills, stats.wins, stats.cleared), (0, 0, 0, 10))
        self.assertEqual(stats.sunCollected, 1000000000)
        self.assertEqual(plain(stats.bestTimes), {"3": 125.5})
        self.assertIsNone(tracker.data.unexpected)
        self.assertIsNone(tracker.data.plantsByKind.invented)
        self.assertIsNone(tracker.data.unlocked.invented)
        before = plain(tracker.data)
        for event, payload in (("win", {"level": 999}), ("run_started", {"level": 0}), ("plant", {"kind": "invented"}),
                               ("kill", {}), ("mower", {"row": 6}), ("sun", {"amount": -10}),
                               ("time", {"seconds": float("nan")}), ("unknown", {})):
            self.assertEqual(len(tracker.record(event, self.table(payload))), 0)
        self.assertEqual(plain(tracker.data), before)
        json.dumps(plain(tracker.data), allow_nan=False)

    def test_overlay_tabs_bounds_stable_nodes_and_paused_redraw(self):
        tracker = self.progress.new(None, self.table({"cleared": 10}))
        self.lua.globals().drawProgress = self.draw
        self.lua.globals().progressSummary = tracker.summary()
        self.lua.globals().progressAchievements = tracker.achievements()
        self.lua.execute("""
local seen, current, sounds, redraws, backs = {}, {}, 0, 0, 0
local state = {tab='stats', summary=progressSummary, achievements=progressAchievements}
local surface = {draw=function(id, spec)
    assert(id:sub(1,9)=='progress.')
    assert(spec.x>=0 and spec.y>=0 and spec.x+spec.w<=960 and spec.y+spec.h<=600)
    assert(spec.layer>=20 and spec.layer<=26)
    if seen[id] then assert(seen[id].kind==spec.kind and seen[id].layer==spec.layer) end
    seen[id], current[id] = spec, spec
end}
local render
local actions = {
    onTab=function(tab) state.tab=tab end,
    onBack=function() backs=backs+1 end,
    clickSound=function() sounds=sounds+1 end,
    redraw=function() redraws=redraws+1;render() end,
}
render=function() current={};drawProgress(surface,state,actions) end
render()
assert(current['progress.shield'].kind=='button' and current['progress.shield'].layer==20)
assert(current['progress.stats.bestTime10'])
assert(current['progress.stats.endless'])
current['progress.tab.achievements'].onClick()
assert(state.tab=='achievements' and sounds==1 and redraws==1)
assert(current['progress.achievement.title10'] and not current['progress.stats.bestTime10'])
current['progress.tab.stats'].onClick()
assert(state.tab=='stats' and sounds==2 and redraws==2)
current['progress.back'].onClick()
assert(backs==1 and sounds==3 and redraws==3)
current['progress.shield'].onClick()
assert(backs==1 and sounds==3 and redraws==3)
""")


if __name__ == "__main__":
    unittest.main()
