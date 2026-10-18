# Mask Layer & International Server Patch for 033 DLSS5 Plugin

[中文文档](README.zh-CN.md)

An unofficial patch for the "033 Yanyun edition" DLSS5 plugin for *Where Winds Meet* / 燕云十六声, made by Bilibili creator [@热心网友033](https://space.bilibili.com/88101991). Get the plugin only from the author's Bilibili page.

## What it fixes

- **V6.3 person/scene separation breaks after game updates** (Chinese and international clients). The plugin pins the hash of one game executable; after an update the native mask is silently disabled while the panel still shows the mask UI. The patch makes that check pass. Shaders are still matched by exact hash, so nothing is applied to the wrong shader.
- **Native masks on the international client** (`wwm.exe`). The plugin only enables them for `yysls.exe`. Everything else in 033 already works on the international client without this patch.
- **V6.3.5 / V6.38 only:** materials missing from the author's mask library no longer void the whole frame's mask; they are treated as scenery (disable with `-NoRelax`).

Supported versions: V6.3, V6.3.5, V6.38. Any other file is left untouched.

## Usage

1. Quit the game and install the plugin with the 033 installer.
2. Double-click `apply-patch.cmd`. It finds the game automatically and applies the international part only if `wwm.exe` is present.
3. Before uninstalling or upgrading the plugin, double-click `remove-patch.cmd`. It restores the author's original engine byte for byte, no backup needed.

`check-status.cmd` only shows the current state. The `.cmd` files call `patch-033.ps1`; you do not need to run it yourself.

## Patched locations

| Version | Mask fix | International client | Relaxed check |
|---|---|---|---|
| V6.3 | `0x2F9110` | `0x29BAE0`, `0x29BAEA` | – |
| V6.3.5 | `0x327AB0` | `0x2ABB74`–`0x2ABB75` | `0x2743E5`, `0x274BE3`, `0x275423`, `0x275C51` |
| V6.38 | `0x338F40` | `0x2BA234` | `0x27CCF5`, `0x27D543`, `0x27DDD3`, `0x27E651` |

The script refuses to write unless restoring every location gives exactly the author's original SHA-256.

## License

MIT. This repository contains no files from the 033 plugin.

## Disclaimer

Not affiliated with or endorsed by the 033 author, NetEase, NVIDIA, AMD or Intel. Loading third-party programs into an online game carries risk, including to your account. Use at your own risk. Report plugin problems to the author and patch problems here.
