-- 0xVyrs Tycoon core rebuild v3 test loader
-- Runtime and all v3 modules are pinned to one immutable build.

local env=(type(getgenv)=="function" and getgenv()) or (type(getfenv)=="function" and getfenv(0)) or _G
local repo="https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/"
local BUILD="60fb92450c7f35fbb3f330c59a8d722f65213b6c"

env.__VYRS_TYCOON_USE_LOCAL_MODULES=false
env.__VYRS_TYCOON_MODULE_BASE_URL=repo..BUILD.."/tycoon_modules"

local source=game:HttpGet(repo..BUILD.."/autonomous_core_v3.lua")
local chunk,err=loadstring(source)
if type(chunk)~="function" then
    warn("[0xVyrs Tycoon Core v3 Test] compile failed: "..tostring(err))
    return
end

print("[0xVyrs Tycoon Core v3 Test] audited scanner // strict currency // structured outcomes // single state owner")
return chunk()
