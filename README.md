# Mask Layer & International Server Patch for 033 DLSS5 Plugin

[中文文档](README.zh-CN.md)

> Fixes broken person/scene separation in the 033 Yanyun DLSS5 plugin V6.3 after game updates, and enables its native masks on the international client.

This is an unofficial patch for the "033 Yanyun edition" DLSS5 plugin by Bilibili creator [@热心网友033](https://space.bilibili.com/88101991), made for *Where Winds Meet* / 燕云十六声. This project is not affiliated with or endorsed by the plugin author.

**The main target is V6.3.** After a game update, V6.3 keeps showing its native skin-mask panel, but person/scene separation silently stops working: characters and scenery get the same effect. This affects both the Chinese and the international client. The patch fixes that, and also lets the native masks run on the international client (`wwm.exe`), which the plugin otherwise only enables for the Chinese client (`yysls.exe`).

V6.3.5 and V6.38 are supported as well.

The patch only edits the plugin engine that the 033 installer has already put in your game folder. It contains no files from the plugin author.

## ⚠️ Risks — read before use

- **This is an unofficial modification.** It changes software published by the plugin author and has not been reviewed by them. It may cause visual problems, crashes or other issues the author never tested.
- **The game is online and has anti-cheat.** The 033 plugin is already a third-party component injected into the game, and using it (and this patch) may violate the game's terms of service. Whether the game operator penalizes this, including account bans, is outside this project's control. **Use entirely at your own risk.**
- **The 033 installer will see the engine as modified.** Run `remove-patch.cmd` before using the 033 installer to uninstall ("还原安装前") or upgrade, otherwise the installer may report a replaced file or leave it behind.
- **New versions are refused.** If the plugin releases a version this patch does not know, the script refuses to change anything. Game updates that change shaders may still leave some materials uncovered by the native masks.
- The plugin author has asked that their package not be redistributed; this project only ships a patch script. Report problems with the plugin itself to the author, and problems with this patch as an issue here. Please do not send patch-caused problems to the plugin author.

## Usage

1. Quit the game completely.
2. Install (or upgrade) the plugin with the 033 installer as usual. Get the plugin only from the author's Bilibili page: https://space.bilibili.com/88101991
3. Double-click **`apply-patch.cmd`**. It finds the game from the 033 installer's records. With `wwm.exe` it also applies the international-client part; with `yysls.exe` it applies only the mask fix.
4. Before uninstalling or upgrading the plugin, double-click **`remove-patch.cmd`** to remove the patch and restore the author's original engine.
5. **`check-status.cmd`** only shows the current state and changes nothing.

You do not need to run `patch-033.ps1` yourself; the three `.cmd` files call it. From a command line:

```powershell
powershell -ExecutionPolicy Bypass -File patch-033.ps1 -Action Status|Apply|Revert [-Engine <path to 033-runtime\033-engine.dll>] [-Client Auto|CN|Intl] [-NoMaskFix] [-NoRelax]
```

## How it works

**Mask fix (both clients).** The plugin engine contains the SHA-256 of the one Chinese game executable the author tested. At startup it hashes the running game executable, and if it does not match, it skips shader registration entirely, so the native mask is never drawn. Whether the panel switches to the mask UI depends on a different check, which is why you see the mask panel but no separation. Every game update changes the executable and breaks the match. The patch changes the first 5 bytes of that check function so it returns "pass".

Shaders are still matched by their exact hash, so a shader that changed in a game update is never replaced. Removing the executable check cannot make the mask apply to the wrong shader.

**International client.** The native-mask switch only compares the executable name with `yysls.exe`; the patch makes it compare with `wwm.exe`.

**Relaxed unknown-material check (V6.3.5 / V6.38 only).** In these versions, a single material shader that is not in the author's mask library voids the masks for the whole frame. Part of the international client's materials are not in the library. The patch treats such materials as scenery and keeps the rest of the mask. The trade-off: where such a material covers a character, that small area may be processed as the character. Disable with `-NoRelax`.

**Safety check.** Before writing, the script restores every patch location in memory and requires the result to match the author's original engine SHA-256 exactly. So `remove-patch.cmd` needs no backup: what it restores is byte-identical to the original.

## Patched locations

| Version | Original SHA-256 | Mask fix (5 bytes) | International client | Relaxed check |
|---|---|---|---|---|
| V6.3 | `d69c4e8b…a42b637` | `0x2F9110` | `0x29BAE0`, `0x29BAEA` | none |
| V6.3.5 | `4dfe6ac3…d056b0c` | `0x327AB0` | `0x2ABB74`–`0x2ABB75` | `0x2743E5`, `0x274BE3`, `0x275423`, `0x275C51` |
| V6.38 | `721810f3…f1a329d0` | `0x338F40` | `0x2BA234` | `0x27CCF5`, `0x27D543`, `0x27DDD3`, `0x27E651` |

The mask fix changes `48 89 5C 24 08` to `B0 01 C3 90 90` (`mov al,1; ret`).

## License

MIT
