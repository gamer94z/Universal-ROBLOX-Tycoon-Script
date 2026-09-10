-- 0xVyrs Tycoon v1.0.0 performance-hardening test loader.

local env = (type(getgenv) == "function" and getgenv())
	or (type(getfenv) == "function" and getfenv(0))
	or _G

local branchBase = "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/v1.0-performance-hardening"
env.__VYRS_TYCOON_MODULE_BASE_URL = branchBase .. "/tycoon_modules"

local source = game:HttpGet(branchBase .. "/autonomous.lua")
local chunk, compileError = loadstring(source)

if type(chunk) ~= "function" then
	local message = "[0xVyrs Tycoon Test] autonomous.lua compile failed: " .. tostring(compileError)
	if type(warn) == "function" then
		warn(message)
	else
		print(message)
	end
	return
end

print("[0xVyrs Tycoon Test] autonomous.lua compiled successfully")
return chunk()
