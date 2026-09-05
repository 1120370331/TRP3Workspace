# TRP3 Item Repository Architecture

## Purpose

This repository keeps Total RP 3 item scripts in three distinct layers so reusable runtime code does not get confused with installable item implementations.

```text
TRP3 runtime
├── framework/octopus/Octopus.lua
│   └── reusable utility, UI, persistence, listener and dispatch API
├── framework/ovo/ovo.lua
│   └── document RGB data to texture renderer
├── apps/rprecorder/RPRecorder.lua
│   └── standalone record and playback application
└── items/<item-slug>/
    └── future independently deployable item scripts

Upstream source is held separately in `references/` as Git submodules. RPBox-derived evidence and snapshots live in `docs/research/rpbox/`; neither directory is part of a deployable item.
```

## Ownership boundaries

| Area | Role | Current artifact |
| --- | --- | --- |
| `framework/octopus/` | General-purpose TRP3 Lua runtime utilities | `Octopus.lua` 1.1.5 |
| `framework/ovo/` | One focused rendering capability | `ovo.lua` |
| `apps/rprecorder/` | A complete application and reference implementation | `RPRecorder.lua` |
| `items/` | One directory per future standalone prop | Reserved |
| `docs/` | Human-facing API and architecture reference | `API.docx`, this file |
| `references/` | Pinned upstream source for implementation tracing | Total RP 3 and Extended submodules |
| `docs/research/rpbox/` | Preserved RPBox analysis and source snapshots | RPBox commit `8485f74be09f038218b54717101c6ab9beb81004` |

## Runtime contracts

All current Lua artifacts are designed for the TRP3 sandbox, not a standalone Lua interpreter. The shared host-facing surface consists mainly of `args`, `getVar`, `setVar`, and `effect`. `ovo.lua` additionally uses `args._G`, `CreateFrame`, `CreateTexture`, and `TRP3_DocumentFrame`.

`args._G` is not a normal TRP3-Extended sandbox capability. The imported research identifies a `/run` bridge that wraps `TRP3_API.script.runLuaScriptEffect` and assigns `a._G = _G` before delegating to the original handler. That bridge exposes the WoW global API to later Lua item effects and changes the execution boundary for every affected item. Treat it as trusted-content-only infrastructure, never as a default on imported or third-party items. `docs/research/rpbox/refs/TRP3ItemGuard.lua` records a guarded alternative.

`RPRecorder.lua` is intentionally treated as a self-contained deployable artifact. It embeds an Octopus 1.2.0 implementation before defining `RPRecorder` and `SCRIPTS`; its later changes are not automatically reflected in `framework/octopus/Octopus.lua` (1.1.5). Any future extraction or synchronization should be an explicit compatibility task with an in-game regression check.

## Change rules

1. Put reusable code in the appropriate `framework/` component and document its public API changes.
2. Put a completed, independently installable application in `apps/`.
3. Put each new prop in its own `items/<item-slug>/` directory; do not mix its code with framework sources.
4. Keep artifacts deployable as TRP3 Lua scripts. Do not add local `require` dependencies unless the intended TRP3 delivery process supports them.
5. Validate behavior in the relevant TRP3 item or workflow before release.
