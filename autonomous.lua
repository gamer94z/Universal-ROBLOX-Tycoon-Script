--[[
    0xVyrs Universal Tycoon v1.0.0
    Public autonomous entry point.

    The audited v4.2 runtime is an internal implementation revision; the
    public release version remains v1.0.0.
]]

local env=(type(getgenv)=="function" and getgenv())
    or (type(getfenv)=="function" and getfenv(0))
    or _G

local base="https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/main/"
env.__VYRS_TYCOON_USE_LOCAL_MODULES=false
env.__VYRS_TYCOON_MODULE_BASE_URL=base.."tycoon_modules"

local source=game:HttpGet(base.."autonomous_v4.lua")
local chunk,compileError=loadstring(source)
if type(chunk)~="function" then
    warn("[0xVyrs Tycoon] v1.0.0 runtime compile failed: "..tostring(compileError))
    return
end

return chunk()
