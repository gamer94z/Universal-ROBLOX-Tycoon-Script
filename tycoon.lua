--[[
	Copyright (c) 2026 gamer94z / 0xVyrs
	All Rights Reserved.

	0xVyrs Tycoon Core is standalone and does not depend on the ESP runtime.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local LOCAL_PLAYER = Players.LocalPlayer

local SHARED_ENV = (type(getgenv) == "function" and getgenv())
	or (type(getfenv) == "function" and getfenv(0))
	or _G

local ACTIVE_TOKEN = tostring(os.clock())
SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN = ACTIVE_TOKEN

local CONFIG = {
	version = "0.1.0",
	enabled = true,
	autoCollect = false,
	highlightAffordable = true,
	showWaypoint = true,
	collectRange = 26,
	scanInterval = 2,
	collectInterval = 0.45,
	maxButtons = 80,
	maxDrops = 120,
	uiOffsetX = 24,
	uiOffsetY = 180,
	moduleBaseUrl = "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/main/tycoon_modules",
}

local SETTINGS_FILE = "tycoon_settings.json"
local MODULE_SOURCES = {
	scanner = nil,
	ui = nil,
	collector = nil,
	upgrades = nil,
	stats = nil,
}

local function canUseFileApi()
	return type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function"
end

local function loadSettings()
	if not canUseFileApi() or not isfile(SETTINGS_FILE) then
		return
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(readfile(SETTINGS_FILE))
	end)
	if not ok or type(decoded) ~= "table" then
		return
	end

	for key, value in pairs(decoded) do
		if CONFIG[key] ~= nil and key ~= "version" then
			CONFIG[key] = value
		end
	end
end

local function saveSettings()
	if not canUseFileApi() then
		return
	end

	local payload = {}
	for key, value in pairs(CONFIG) do
		if key ~= "version" then
			payload[key] = value
		end
	end

	pcall(function()
		writefile(SETTINGS_FILE, HttpService:JSONEncode(payload))
	end)
end

local function requireTycoonModule(moduleName)
	if type(loadstring) ~= "function" then
		return nil
	end

	local source = MODULE_SOURCES[moduleName]
	local fileName = moduleName .. ".lua"

	if type(readfile) == "function" then
		for _, path in ipairs({
			"Tycoon/tycoon_modules/" .. fileName,
			"Tycoon\\tycoon_modules\\" .. fileName,
			"tycoon_modules/" .. fileName,
			"tycoon_modules\\" .. fileName,
		}) do
			local ok, result = pcall(function()
				return readfile(path)
			end)
			if ok and type(result) == "string" and result ~= "" then
				source = result
				break
			end
		end
	end

	if (type(source) ~= "string" or source == "") and type(game.HttpGet) == "function" then
		local url = CONFIG.moduleBaseUrl:gsub("/+$", "") .. "/" .. fileName
		local ok, result = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(result) == "string" and result ~= "" then
			source = result
		end
	end

	if type(source) ~= "string" or source == "" then
		warn("[0xVyrs Tycoon] Failed to load module: " .. tostring(moduleName))
		return nil
	end

	local ok, result = pcall(function()
		local chunk = loadstring(source)
		return chunk and chunk()
	end)
	if not ok then
		warn("[0xVyrs Tycoon] Module compile failed: " .. tostring(moduleName) .. " | " .. tostring(result))
		return nil
	end

	return result
end

local function getLocalRoot()
	local character = LOCAL_PLAYER.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getLeaderstatValue(names)
	local leaderstats = LOCAL_PLAYER:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end

	for _, name in ipairs(names) do
		local item = leaderstats:FindFirstChild(name)
		if item and tonumber(item.Value) then
			return tonumber(item.Value)
		end
	end

	for _, item in ipairs(leaderstats:GetChildren()) do
		local lower = item.Name:lower()
		if (lower:find("cash") or lower:find("money") or lower:find("coin")) and tonumber(item.Value) then
			return tonumber(item.Value)
		end
	end

	return nil
end

local function createContext()
	return {
		Players = Players,
		RunService = RunService,
		CoreGui = CoreGui,
		HttpService = HttpService,
		LOCAL_PLAYER = LOCAL_PLAYER,
		CONFIG = CONFIG,
		SHARED_ENV = SHARED_ENV,
		saveSettings = saveSettings,
		getLocalRoot = getLocalRoot,
		getCash = function()
			return getLeaderstatValue({ "Cash", "Money", "Coins", "Balance" })
		end,
	}
end

local function initModule(factory, moduleContext)
	if type(factory) == "function" then
		local ok, result = pcall(factory, moduleContext)
		if ok and result ~= nil then
			return result
		end
		ok, result = pcall(factory)
		if ok then
			return result
		end
	end
	return factory
end

loadSettings()

local oldGui = CoreGui:FindFirstChild("TycoonCoreGUI")
if oldGui then
	oldGui:Destroy()
end

local context = createContext()
local scanner = requireTycoonModule("scanner")
local uiFactory = requireTycoonModule("ui")
local collector = requireTycoonModule("collector")
local upgrades = requireTycoonModule("upgrades")
local statsFactory = requireTycoonModule("stats")

if not scanner or not uiFactory or not collector or not upgrades or not statsFactory then
	error("[0xVyrs Tycoon] Missing required module")
end

scanner = initModule(scanner, context)
collector = initModule(collector, context)
upgrades = initModule(upgrades, context)

local ui = uiFactory(context)
local stats = statsFactory(context)
local runtime = {
	lastScan = 0,
	lastCollect = 0,
	data = nil,
	nearest = nil,
	cheapest = nil,
	collected = 0,
}

ui.onToggle("enabled", function(value)
	CONFIG.enabled = value
	saveSettings()
end)
ui.onToggle("autoCollect", function(value)
	CONFIG.autoCollect = value
	saveSettings()
end)
ui.onToggle("highlightAffordable", function(value)
	CONFIG.highlightAffordable = value
	saveSettings()
end)
ui.onToggle("showWaypoint", function(value)
	CONFIG.showWaypoint = value
	saveSettings()
end)

local function cleanup()
	upgrades.clear()
	if ui and ui.destroy then
		ui.destroy()
	end
end

local function isActiveToken()
	return SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN == ACTIVE_TOKEN
end

RunService.Heartbeat:Connect(function(deltaTime)
	if not isActiveToken() then
		cleanup()
		return
	end

	stats.update(deltaTime)
	local now = os.clock()

	if now - runtime.lastScan >= CONFIG.scanInterval then
		runtime.lastScan = now
		runtime.data = scanner.scan(context)
		runtime.nearest = upgrades.getNearestAffordable(runtime.data, getLocalRoot())
		runtime.cheapest = upgrades.getCheapestAffordable(runtime.data)
	end

	if CONFIG.enabled and runtime.data then
		if CONFIG.highlightAffordable then
			upgrades.render(runtime.data, runtime.nearest)
		else
			upgrades.clear()
		end

		if CONFIG.showWaypoint then
			upgrades.updateWaypoint(runtime.nearest)
		else
			upgrades.hideWaypoint()
		end

		if CONFIG.autoCollect and now - runtime.lastCollect >= CONFIG.collectInterval then
			runtime.lastCollect = now
			runtime.collected = runtime.collected + collector.collectNearby(context, runtime.data)
		end
	else
		upgrades.clear()
		upgrades.hideWaypoint()
	end

	ui.update({
		data = runtime.data,
		nearest = runtime.nearest,
		cheapest = runtime.cheapest,
		stats = stats.get(),
		collected = runtime.collected,
	})
end)

task.spawn(function()
	while isActiveToken() do
		task.wait(15)
		saveSettings()
	end
end)
