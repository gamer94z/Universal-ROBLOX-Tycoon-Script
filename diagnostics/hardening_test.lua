-- 0xVyrs Tycoon v1.0.0 performance-hardening test loader.
-- Loads only this branch for the current run and restores any previous module override afterwards.

local env = (type(getgenv) == "function" and getgenv())
	or (type(getfenv) == "function" and getfenv(0))
	or _G

local key = "__VYRS_TYCOON_MODULE_BASE_URL"
local previous = env[key]
env[key] = "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/v1.0-performance-hardening/tycoon_modules"

local ok, result = pcall(function()
	local source = game:HttpGet(
		"https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/v1.0-performance-hardening/autonomous.lua"
	)
	local chunk = loadstring(source)
	if type(chunk) ~= "function" then
		return nil, "autonomous.lua did not compile into a callable chunk"
	end
	return chunk()
end)

env[key] = previous

if not ok then
	local message = "[0xVyrs Tycoon Test] runtime load failed: " .. tostring(result)
	if type(warn) == "function" then
		warn(message)
	elseif type(print) == "function" then
		print(message)
	end
	return nil, message
end

return result