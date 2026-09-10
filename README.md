# 0xVyrs Universal Tycoon — v1.0.0

Universal Roblox tycoon automation with adaptive progression, automatic collection, purchase routing, ROI learning, reward detection, rebirth support, diagnostics, and the 0xVyrs `.exe` console interface.

## Loader

```lua
loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/main/autonomous.lua"
))()
```

Load the script, then use **START RUN** in the console.

## v1.0 Features

- Universal tycoon/base discovery with ownership verification.
- Automatic upgrade purchasing with affordability verification.
- Automatic collection with self-healing touch handling and collector diagnostics.
- Adaptive learning per PlaceId.
- Learned purchase dependencies and route optimisation.
- ROI and payback-time learning from observed income changes.
- `Fastest`, `Income`, and `Rebirth` strategies.
- Hyper Buy for rapid progression through affordable upgrade chains.
- Automatic free-reward and free-boost detection with paid/ad safety filtering.
- Optional automatic rebirth support.
- Bottleneck detection and estimated completion timing.
- Personal-best and run analytics.
- Cached-root scanning and event-driven rescanning to reduce unnecessary work.
- Attempts to keep the owned tycoon streamed while the player is away from it.
- No autonomous purchase teleporting.
- Owner Safe Mode prevents automation against another player's detected plot.
- `.exe`-style 0xVyrs terminal UI with live status, diagnostics, controls, and commands.
- Matching in-world purchase labels, highlights, and current-target HUD.
- Saved per-game settings and learning data.

## Console

The interface uses the same visual language as the 0xVyrs Universal ESP Suite: a dark terminal window, code font, green/cyan telemetry, quick-control categories, and a command prompt.

Useful commands include:

```text
help
status
start
stop
strategy fastest
strategy income
strategy rebirth
toggle autocollect
toggle autobuy
clear
hide
```

Press **Right Shift** to hide or show the console.

## Safety Behaviour

The automation filters Robux, gamepass, premium, developer-product, and ad/rewarded-video purchase contexts. Free-reward detection is deliberately conservative. Owner verification is enabled by default.

## Compatibility

Tycoon detection is pattern-based because Roblox tycoon frameworks differ substantially. The scanner looks for ownership signals, purchase interactions, prices, collectors, buttons, drops, and common tycoon structures, then caches the verified root for faster rescanning.

Some games may validate physical proximity or touch interactions server-side. In those games, certain actions may not work while the player is far away even if the plot remains streamed to the client.

## Legacy Core

`tycoon.lua` remains in the repository as the earlier compact core runtime. The v1.0 public entry point is `autonomous.lua`.
