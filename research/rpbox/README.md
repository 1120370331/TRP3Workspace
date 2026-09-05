# RPBox Research Import

Imported from [`1120370331/RPBox`](https://github.com/1120370331/RPBox) at commit `8485f74be09f038218b54717101c6ab9beb81004` on 2026-09-05. `notes/` contains the analysis and `refs/` contains the source snapshots it refers to. These are research artifacts, not deployable TRP3 items.

## WoW API Global Bridge

The important mechanism is in `refs/totalRP3_Extended.lua`: a `/run` command stores the original `TRP3_API.script.runLuaScriptEffect`, wraps it, assigns `a._G = _G`, then calls the original handler. A Lua item effect can subsequently reach WoW global APIs as `args._G`, including UI APIs such as `CreateFrame`.

This is a global hook, not a normal per-item permission. It changes the trust boundary for every later Lua effect and must only be enabled for items you own and have reviewed. Do not activate it while evaluating imported or third-party props. `refs/TRP3ItemGuard.lua` is retained as the safer research path: it scans, quarantines and conditionally injects the bridge for trusted content.

The command is `/run`, rather than `/scripts`. Its exact source occurrence is preserved in `refs/totalRP3_Extended.lua`; retain the source context when updating the approach against a newer Extended version.
