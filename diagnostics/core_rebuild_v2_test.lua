-- 0xVyrs Tycoon core rebuild v2 test loader.
-- Runtime and modules are pinned to the same immutable commit.

local env=(type(getgenv)=="function" and getgenv()) or (type(getfenv)=="function" and getfenv(0)) or _G
local repo="https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/"
local BUILD="d406e2097648f3eedb6323e2af3be982502d08ea"

env.__VYRS_TYCOON_USE_LOCAL_MODULES=false
env.__VYRS_TYCOON_MODULE_BASE_URL=repo..BUILD.."/tycoon_modules"

local source=game:HttpGet(repo..BUILD.."/autonomous_core_v2.lua")
local chunk,err=loadstring(source)
if type(chunk)~="function" then
    warn("[0xVyrs Tycoon Core v2 Test] compile failed: "..tostring(err))
    return
end

print("[0xVyrs Tycoon Core v2 Test] authoritative purchase queue // pinned build // buy watchdog")
return chunk()
