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
	autoBuy = false,
	autoLoadGamePreset = true,
	highlightAffordable = true,
	showLabels = true,
	showWaypoint = true,
	requireOwnerMatch = true,
	buyMode = "Nearest",
	collectMode = "Nearby",
	collectRange = 26,
	scanInterval = 4,
	renderInterval = 0.5,
	uiInterval = 0.25,
	collectInterval = 0.45,
	buyInterval = 1.1,
	maxButtons = 50,
	maxDrops = 60,
	maxLabels = 16,
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

	local source = decoded
	if decoded.placeConfigs and decoded.placeConfigs[tostring(game.PlaceId)] and decoded.autoLoadGamePreset ~= false then
		source = decoded.placeConfigs[tostring(game.PlaceId)]
	end

	for key, value in pairs(source) do
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
	if isfile(SETTINGS_FILE) then
		pcall(function()
			local existing = HttpService:JSONDecode(readfile(SETTINGS_FILE))
			if type(existing) == "table" then
				payload = existing
			end
		end)
	end
	for key, value in pairs(CONFIG) do
		if key ~= "version" then
			payload[key] = value
		end
	end
	payload.placeConfigs = payload.placeConfigs or {}
	payload.placeConfigs[tostring(game.PlaceId)] = {}
	for key, value in pairs(CONFIG) do
		if key ~= "version" and key ~= "placeConfigs" then
			payload.placeConfigs[tostring(game.PlaceId)][key] = value
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
		if not chunk then
			return nil
		end
		return chunk()
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

local function runSafe(taskName, callback, ...)
	local ok, result = pcall(callback, ...)
	if not ok then
		warn("[0xVyrs Tycoon] " .. tostring(taskName) .. " failed: " .. tostring(result))
		return nil
	end
	return result
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

local ui = runSafe("ui init", uiFactory, context)
local stats = runSafe("stats init", statsFactory, context)
if type(scanner) ~= "table" or type(collector) ~= "table" or type(upgrades) ~= "table" or type(ui) ~= "table" or type(stats) ~= "table" then
	error("[0xVyrs Tycoon] Module init failed")
end

if type(scanner.scan) ~= "function"
	or type(collector.collectNearby) ~= "function"
	or type(collector.buyButton) ~= "function"
	or type(upgrades.getNearestAffordable) ~= "function"
	or type(upgrades.getCheapestAffordable) ~= "function"
	or type(upgrades.getMostExpensiveAffordable) ~= "function"
	or type(upgrades.getNextLocked) ~= "function"
	or type(upgrades.choosePurchase) ~= "function"
	or type(upgrades.render) ~= "function"
	or type(upgrades.renderLabels) ~= "function"
	or type(upgrades.clear) ~= "function"
	or type(upgrades.clearLabels) ~= "function"
	or type(upgrades.updateWaypoint) ~= "function"
	or type(upgrades.hideWaypoint) ~= "function"
	or type(ui.update) ~= "function"
	or type(ui.onToggle) ~= "function"
	or type(ui.onCycle) ~= "function"
	or type(stats.update) ~= "function"
	or type(stats.get) ~= "function" then
	error("[0xVyrs Tycoon] Module contract failed")
end
local runtime = {
	lastScan = 0,
	lastCollect = 0,
	lastBuy = 0,
	lastRender = 0,
	lastUi = 0,
	data = nil,
	nearest = nil,
	cheapest = nil,
	bestValue = nil,
	nextLocked = nil,
	collected = 0,
	bought = 0,
}

ui.onToggle("enabled", function(value)
	CONFIG.enabled = value
	saveSettings()
end)
ui.onToggle("autoCollect", function(value)
	CONFIG.autoCollect = value
	saveSettings()
end)
ui.onToggle("autoBuy", function(value)
	CONFIG.autoBuy = value
	saveSettings()
end)
ui.onToggle("highlightAffordable", function(value)
	CONFIG.highlightAffordable = value
	saveSettings()
end)
ui.onToggle("showLabels", function(value)
	CONFIG.showLabels = value
	saveSettings()
end)
ui.onToggle("showWaypoint", function(value)
	CONFIG.showWaypoint = value
	saveSettings()
end)
ui.onToggle("requireOwnerMatch", function(value)
	CONFIG.requireOwnerMatch = value
	saveSettings()
end)
ui.onToggle("autoLoadGamePreset", function(value)
	CONFIG.autoLoadGamePreset = value
	saveSettings()
end)
ui.onCycle("buyMode", function(value)
	CONFIG.buyMode = value
	saveSettings()
end)
ui.onCycle("collectMode", function(value)
	CONFIG.collectMode = value
	saveSettings()
end)

local function cleanup()
	upgrades.clear()
	upgrades.clearLabels()
	if ui and ui.destroy then
		ui.destroy()
	end
end

local function isActiveToken()
	return SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN == ACTIVE_TOKEN
end

local function automationAllowed(data)
	if not data then
		return false
	end
	if CONFIG.requireOwnerMatch and not data.ownerMatch then
		return false
	end
	return true
end

RunService.Heartbeat:Connect(function(deltaTime)
	if not isActiveToken() then
		cleanup()
		return
	end

	runSafe("stats update", stats.update, deltaTime)
	local now = os.clock()

	if now - runtime.lastScan >= CONFIG.scanInterval then
		runtime.lastScan = now
		runtime.data = runSafe("scan", scanner.scan, context) or runtime.data
		runtime.nearest = runSafe("nearest upgrade", upgrades.getNearestAffordable, runtime.data, getLocalRoot())
		runtime.cheapest = runSafe("cheapest upgrade", upgrades.getCheapestAffordable, runtime.data)
		runtime.bestValue = runSafe("best value upgrade", upgrades.getMostExpensiveAffordable, runtime.data)
		runtime.nextLocked = runSafe("next locked upgrade", upgrades.getNextLocked, runtime.data)
	end

	if CONFIG.enabled and runtime.data then
		runtime.data.showLabels = CONFIG.showLabels
		if now - runtime.lastRender >= CONFIG.renderInterval then
			runtime.lastRender = now
			if CONFIG.highlightAffordable then
				runSafe("highlight render", upgrades.render, runtime.data, runtime.nearest)
			else
				runSafe("highlight clear", upgrades.clear)
			end
			runSafe("label render", upgrades.renderLabels, runtime.data, runtime.nearest)

			if CONFIG.showWaypoint then
				runSafe("waypoint update", upgrades.updateWaypoint, runtime.nearest or runtime.cheapest)
			else
				runSafe("waypoint hide", upgrades.hideWaypoint)
			end
		end

		if automationAllowed(runtime.data) and CONFIG.autoBuy and now - runtime.lastBuy >= CONFIG.buyInterval then
			runtime.lastBuy = now
			local target = upgrades.choosePurchase(runtime.data, getLocalRoot(), CONFIG.buyMode)
			if target and collector.buyButton(context, target) then
				runtime.bought = runtime.bought + 1
			end
		end

		if automationAllowed(runtime.data) and CONFIG.autoCollect and now - runtime.lastCollect >= CONFIG.collectInterval then
			runtime.lastCollect = now
			runtime.collected = runtime.collected + (runSafe("collect", collector.collectNearby, context, runtime.data) or 0)
		end
	else
		runSafe("highlight clear", upgrades.clear)
		runSafe("label clear", upgrades.clearLabels)
		runSafe("waypoint hide", upgrades.hideWaypoint)
	end

	if now - runtime.lastUi >= CONFIG.uiInterval then
		runtime.lastUi = now
		runSafe("ui update", ui.update, {
			data = runtime.data,
			nearest = runtime.nearest,
			cheapest = runtime.cheapest,
			bestValue = runtime.bestValue,
			nextLocked = runtime.nextLocked,
			stats = runSafe("stats get", stats.get) or {},
			collected = runtime.collected,
			bought = runtime.bought,
		})
	end
end)

local spawn = task and task.spawn or coroutine.wrap
spawn(function()
	while isActiveToken() do
		if task and task.wait then
			task.wait(15)
		else
			wait(15)
		end
		saveSettings()
	end
end)
