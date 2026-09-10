-- 0xVyrs Tycoon v1.0.0 performance-hardening test loader.
-- Uses immutable commit URLs so branch/CDN caching cannot serve stale code.
-- The stable runtime is patched in-memory only so its live cash reads use the
-- adaptive provider installed by the hardening scanner.

local env = (type(getgenv) == "function" and getgenv())
	or (type(getfenv) == "function" and getfenv(0))
	or _G

local STABLE_RUNTIME_COMMIT = "8c2e708a6faf50bc3bc7e7f038df2585d95ddc49"
local HARDENING_MODULE_COMMIT = "8f309c898b0ed3204b40c92239db59796bd8b092"
local repoBase = "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/"

env.__VYRS_TYCOON_MODULE_BASE_URL = repoBase .. HARDENING_MODULE_COMMIT .. "/tycoon_modules"

local source = game:HttpGet(repoBase .. STABLE_RUNTIME_COMMIT .. "/autonomous.lua")

local replacements = 0
local function patch(pattern, replacement)
	local count
	source, count = source:gsub(pattern, replacement)
	replacements = replacements + count
end

patch("local cash = getCash%(%)", "local cash = context.getCash()")
patch("cash = runtime%.data and runtime%.data%.cash or getCash%(%)", "cash = runtime.data and runtime.data.cash or context.getCash()")
patch("brain%.observeEconomy, getCash%(%), statsState%(%)", "brain.observeEconomy, context.getCash(), statsState()")

if replacements ~= 3 then
	local message = "[0xVyrs Tycoon Test] runtime cash bridge patch mismatch: expected 3, got " .. tostring(replacements)
	if type(warn) == "function" then warn(message) else print(message) end
	return
end

local chunk, compileError = loadstring(source)
if type(chunk) ~= "function" then
	local message = "[0xVyrs Tycoon Test] patched autonomous.lua compile failed: " .. tostring(compileError)
	if type(warn) == "function" then warn(message) else print(message) end
	return
end

print("[0xVyrs Tycoon Test] stable runtime compiled // player-list row cash binding active")
return chunk()
