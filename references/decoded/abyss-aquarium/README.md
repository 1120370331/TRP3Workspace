# 米游 深渊水族馆 Reference Project

This is a read-only reference project reconstructed from a user-supplied Total RP 3 Extended short export. It is not an approved or deployable artifact.

| Field | Value |
| --- | --- |
| Root ID | `0119013913NMg8A` |
| TRP3 Extended export version | `1058` |
| Display version | `2.3.2` |
| Object type | `IT` item |
| Object version | `2711` |
| Object name | 米游 深渊水族馆 |

Files:

- `export.t3e.txt` is the original printable export, preserved verbatim.
- `decoded.json` is the structured result generated without executing embedded Lua.
- [`docs/research/abyss-aquarium-technical.md`](../../../docs/research/abyss-aquarium-technical.md) explains the format, structure, behavior and security boundary.

Regenerate the JSON with the repository decoder:

```bash
node tools/decode-trp3-export.mjs \
  references/decoded/abyss-aquarium/export.t3e.txt \
  references/decoded/abyss-aquarium/decoded.json
```

The raw object includes an author-provided contact/QR display and an external link. Preserve it only as source evidence; do not reuse or redistribute those elements without authorization.
