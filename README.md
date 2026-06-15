# 0xVyrs Tycoon Core

Standalone Roblox tycoon helper. This is separate from the ESP script and uses its own loader, modules, GUI, and settings file.

## Loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/main/tycoon.lua"))()
```

## Current MVP

- Scans for tycoon-like bases, buttons, collectors, and cash drops.
- Detects the local player's likely tycoon/base.
- Highlights affordable upgrade buttons.
- Shows nearest and cheapest upgrade.
- Tracks estimated cash per minute.
- Optional nearby touch collection for drops/collectors.
- Compact draggable UI.

## Notes

Universal tycoon detection is pattern-based because every game names tycoon objects differently. The scanner looks for common names like `Tycoon`, `Buttons`, `Drops`, `Collector`, `Cash`, `Owner`, `Cost`, and `Price`.
