-- 0xVyrs Tycoon v1.0.0 core-rebuild test loader.
-- No source rewriting: runtime and modules are pinned to one immutable commit.

local env=(type(getgenv)=="function" and getgenv()) or (type(getfenv)=="function" and getfenv(0)) or _G
local repo="https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/"
local CORE_COMMIT="1c40769b2d1afa79c56878a88cf7b6210e504161"

env.__VYRS_TYCOON_USE_LOCAL_MODULES=false
env.__VYRS_TYCOON_MODULE_BASE_URL=repo..CORE_COMMIT.."/tycoon_modules"

local source=game:HttpGet(repo..CORE_COMMIT.."/autonomous_core.lua")
local chunk,compileError=loadstring(source)
if type(chunk)~="function" then
	warn("[0xVyrs Tycoon Core Test] runtime compile failed: "..tostring(compileError))
	return
end

print("[0xVyrs Tycoon Core Test] integrated rebuild // pinned modules // isolated workers // persistent purchase state")
return chunk()
