# 米游 深渊水族馆 Technical Reverse Engineering

## Result

The supplied text is a valid Total RP 3 Extended short export for the item `米游·深渊水族馆` (`TY = "IT"`). The decoded root ID is `0119013913NMg8A`; its Extended export version is `1058`, display version is `2.3.2`, and the object model version is `2711`.

The source and generated representation live in `references/decoded/abyss-aquarium/`. Decoding was static: no embedded Lua, workflow, macro or WoW API call was executed.

## Export format

The Extended list tool writes a short export by serializing a tuple, escaping pipe characters, compressing it, then prefixing the printable payload with `!`. The corresponding importer reverses the same stages in `references/total-rp-3-extended/totalRP3_Extended_Tools/List/List.lua`.

For this export the verified pipeline is:

```text
! printable export, 62,552 characters
  -> LibDeflate DecodeForPrint, 46,913 bytes
  -> C_EncodingUtil raw DEFLATE decompression, 315,090 bytes
  -> replace || with |
  -> AceSerializer 3.0 revision 1
  -> tuple { [1] version, [2] root ID, [3] class, [4] display version }
```

The decoded tuple is `{ 1058, "0119013913NMg8A", class, "2.3.2" }`. The repository decoder at `tools/decode-trp3-export.mjs` implements only this data path. It rejects malformed printable characters and serializer controls, uses `inflateRawSync` for the verified raw-DEFLATE layer, and never evaluates Lua.

## Class structure

The root class exposes `BA`, `MD`, `LI`, `SC`, `IN`, `HA`, `CO`, `US`, `details` and `securityLevel`.

- `BA` is the item metadata: name, description, icon, placement-oriented label, creator-facing metadata and usability flags.
- `MD` contains provenance and version metadata: object version `2711`, Extended display version `2.3.2`, locale `en`, and the original author fields.
- `IN` contains two child documents: `idcard` and `saveData`. The former is a formatted information/QR document; the latter contains saved UI data.
- `SC` contains 22 root workflows, including `grow`, `close`, `copy`, `hide`, `crystal`, `putfood`, `openbgm`, `clean`, `build` and `reset`.

The workflow tree contains 23 workflow containers and 373 structured nodes. Its declared effects are:

| Effect | Count | Role observed in this object |
| --- | ---: | --- |
| `sound_id_self` / `sound_id_stop` | 23 / 4 | UI feedback and cleanup |
| `sound_music_self` / `sound_music_stop` | 7 / 1 | Background music control |
| `var_object` | 11 | Object-scoped state changes |
| `document_show` | 3 | Child document presentation |
| `run_workflow` | 2 | Workflow composition |
| `item_add` / `item_remove` | 2 / 1 | Copy and reset behavior for this item ID |
| `script` | 2 | Bootstrap check and the aquarium implementation |
| `secure_macro` | 1 | Global Lua execution bridge |
| `var_operand` / `text` | 1 / 3 | Random operand and status messages |

## Runtime design

The main script is approximately 246,719 UTF-8 bytes. It creates the `AbyssAquariumGlobal` frame, uses `PlayerModel` frames for fish and reef models, drives updates with `C_Timer`, and saves gameplay state under the object variable key `ABYSS_AQUARIUM_SAVE_V3`.

The game is an incremental aquarium: fish and reef configurations set unlock gates, click rewards, production rewards, milestones, hidden fish and timed state. Its workflow layer supplies sounds, document display, item copy/reset and other TRP3-native effects, while the large script owns UI construction and simulation state. The static scan also finds use of `CreateFrame`, `UIParent`, `GetTime`, `date`, `UnitName`, `PlaySound`, `StopSound`, `C_Timer` and `SendChatMessage` through `args._G`.

## Global API bridge and risk

The workflow named `AAA建材王总` first invokes a `secure_macro` that replaces `TRP3_API.script.runLuaScriptEffect` with a wrapper assigning `a._G = _G` before delegation. Its next script refuses to continue unless `args._G` is available, and the final script depends on that global bridge.

This is not standard per-item Extended behavior. The wrapper changes the execution boundary for later Lua effects, so it must be treated as trusted-content-only infrastructure. The reference is retained for analysis, not execution: do not import, enable its macro, or run the embedded script before a separate in-game review. The imported source also contains author contact/QR content and an external link, which should not be republished without permission.
