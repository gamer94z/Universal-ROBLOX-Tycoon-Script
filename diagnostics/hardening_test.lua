-- 0xVyrs Tycoon v1.0.0 performance-hardening test loader.
-- Uses immutable commit URLs so branch/CDN caching cannot serve stale code.

local env = (type(getgenv) == "function" and getgenv())
	or (type(getfenv) == "function" and getfenv(0))
	or _G

local STABLE_RUNTIME_COMMIT = "8c2e708a6faf50bc3bc7e7f038df2585d95ddc49"
local HARDENING_MODULE_COMMIT = "07768b7b71e3999b9fdd065004b278803b3dff5e"
local repoBase = "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/"

env.__VYRS_TYCOON_MODULE_BASE_URL = repoBase .. HARDENING_MODULE_COMMIT .. "/tycoon_modules"

local source = game:HttpGet(repoBase .. STABLE_RUNTIME_COMMIT .. "/autonomous.lua")
local chunk, compileError = loadstring(source)

if type(chunk) ~= "function" then
	local message = "[0xVyrs Tycoon Test] stable autonomous.lua compile failed: " .. tostring(compileError)
	if type(warn) == "function" then warn(message) else print(message) end
	return
end

print("[0xVyrs Tycoon Test] stable runtime compiled // hardening modules pinned")
return chunk()
