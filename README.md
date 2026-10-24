# International Server Patch for 033 DLSS5 plugin (Where Winds Meet)

[中文文档](README.zh-CN.md)

An unofficial patch for the "033 Yanyun edition" DLSS5 plugin for *Where Winds Meet* / 燕云十六声, made by Bilibili creator [@热心网友033](https://space.bilibili.com/88101991). Get the plugin only from the author's Bilibili page.

## What it fixes

- **V6.3 person/scene separation breaks after game updates** (Chinese and international clients). The plugin pins the hash of one game executable; after an update the native mask is silently disabled while the panel still shows the mask UI. The patch makes that check pass. Shaders are still matched by exact hash, so nothing is applied to the wrong shader.
- **V6.3.5 / V6.38 / V6.3 Enhanced R7 and structurally compatible updates:** materials missing from the author's mask library no longer void the whole frame's mask; they are treated as scenery (disable with `-NoRelax`).

Built-in exact profiles: V6.3, V6.3.5, V6.38, V6.3 Enhanced R7. Other versions are automatically scanned for compatible code, without manually adding their SHA-256 or file offsets. Detection targets the V6.38 / R7 code family. Changed or ambiguous code is rejected; compatibility with every future release is not guaranteed.

## Usage

1. Quit the game and install the plugin with the 033 installer.
2. Double-click `apply-patch.cmd` and follow the prompts in the console window:
   - It finds every game with 033 installed. **The Win64r and Win64rh launcher folders of the same game are handled together.**
   - If both the CN and the international client have a patchable 033, it lists them by number; type a number and press Enter to choose the game.
   - Before changing anything it lists the engines it will patch. **Type Y and press Enter to confirm**; anything else cancels without changes.
   - Versions that need no patch or cannot be patched (for example V6.0) are shown as skipped.
   - The international part is applied only when the game folder contains `wwm.exe`; the CN client gets the mask fix only.
3. Before uninstalling or upgrading the plugin, double-click `remove-patch.cmd`, choose the game the same way and confirm with Y. It restores the engine byte for byte to its pre-patch state. After installing the update, run `apply-patch.cmd` again to attempt automatic adaptation.

`check-status.cmd` lists every 033 engine it finds: CN or international, 033 version, patch state and launcher folder. It only reads; it does not write the engine or create recovery data.

The patch folder can live anywhere, as long as `apply-patch.cmd`, `check-status.cmd`, `remove-patch.cmd`, `patch-033.ps1` and `auto-detect.cs` stay together. The script finds games through the 033 installer's records (`%LOCALAPPDATA%\033Installer\index`) and tells CN from international by whether the engine's game folder contains `yysls.exe` or `wwm.exe`. The `.cmd` files call `patch-033.ps1`. Keep `auto-detect.cs` beside that script. The scanner uses the .NET compiler included with Windows PowerShell; no Python or disassembler installation is needed.

## Automatic adaptation

- Built-in profiles are checked first using their original SHA-256. Otherwise, the scanner uses PE sections and x64 function boundaries to identify two executable-hash references, the game-name check, and all four material checks. It recalculates the international string reference using the detected addresses.
- Before patching an unknown version for the first time, it saves the complete original beside the engine at `033-engine.dll.patch-033/<original-SHA-256>.original.dll`. Different originals are retained separately. **Keep this directory**: repeat runs, status detection, and restoration of automatically adapted versions depend on it.
- Subsequent runs verify and rescan the saved original, then check that the current engine contains only permitted patch changes. Unexpected modifications or missing/corrupt recovery data cause refusal. Writes replace the engine with a verified temporary file in the same directory, after rechecking the game process and engine hash.
- A newly calculated hash identifies a local original and verifies restoration; **it does not authenticate the publisher**. Built-in profiles retain their pinned original hashes. Use `apply-patch.cmd -KnownOnly` to disable automatic adaptation.
- First-time adaptation requires an unpatched engine. On failure, keep the error message and restore a clean engine with the 033 installer before retrying. Structural changes still require updated detection rules. The script will not guess offsets or apply only a subset of the detected family.

To specify an engine and client explicitly (with `-Engine`, only that engine is processed, without prompts):

```powershell
.\apply-patch.cmd -Engine 'D:\Games\WWM\033-runtime\033-engine.dll' -Client Intl
```

Add `-Yes` to skip the Y confirmation when the engines are found automatically, for example in your own script.

Automatic adaptation does not change shader hashes or the shader library, and does not download or upgrade the 033 plugin.

## Patched locations

| Version | Mask fix | International client | Relaxed check |
|---|---|---|---|
| V6.3 | `0x2F9110` | `0x29BAE0`, `0x29BAEA` | – |
| V6.3.5 | `0x327AB0` | `0x2ABB74`–`0x2ABB75` | `0x2743E5`, `0x274BE3`, `0x275423`, `0x275C51` |
| V6.38 | `0x338F40` | `0x2BA234` | `0x27CCF5`, `0x27D543`, `0x27DDD3`, `0x27E651` |
| V6.3 Enhanced R7 | `0x33FA10` | `0x2BB824` | `0x27CD95`, `0x27D5E3`, `0x27DE73`, `0x27E6F1` |

Built-in profiles require an exact match to the pinned original SHA-256 after normalization. Automatically detected profiles use a verified local original. Unknown versions use scanned offsets, not this table.

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-patch.ps1 -SampleEngine 'D:\Games\WWM\033-runtime\033-engine.dll'
```

Supply a real built-in engine from the detector's supported code family, such as R7 (this patch may already be applied). Tests operate only on temporary copies inside the repository and clean up afterwards. They cover known profiles, relocated PE file offsets, options, repeated application, exact restoration, and rejection of invalid inputs. No engine sample is distributed. Simulated relocation does not replace in-game validation of future releases.

## License

MIT. This repository contains no files from the 033 plugin.

## Disclaimer

Not affiliated with or endorsed by the 033 author, NetEase, NVIDIA, AMD or Intel. Loading third-party programs into an online game carries risk, including to your account. Use at your own risk. Report plugin problems to the author and patch problems here.
