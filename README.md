# 0xVyrs Tycoon Core

Standalone Roblox tycoon helper. This is separate from the ESP script and uses its own loader, modules, GUI, and settings file.

## Loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/main/tycoon.lua"))()
```

## Current MVP

- Scans for tycoon-like bases, buttons, collectors, and cash drops.
- Detects the local player's likely tycoon/base.
- Shows scanner confidence, owner match, button count, drop count, and progress.
- Highlights affordable upgrade buttons.
- Adds floating labels over detected buttons with price/next markers.
- Shows nearest, cheapest, best-value, and next locked upgrade.
- Optional auto-buy with nearest, cheapest, or value mode.
- Optional collection modes: nearby, whole tycoon, or collectors only.
- Tracks estimated cash per minute.
- Saves per-place presets for tycoon-specific settings.
- Compact draggable UI.

## Notes

Universal tycoon detection is pattern-based because every game names tycoon objects differently. The scanner looks for common names like `Tycoon`, `Buttons`, `Drops`, `Collector`, `Cash`, `Owner`, `Cost`, and `Price`.
