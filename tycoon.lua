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

local previousCleanup = SHARED_ENV.__VYRS_TYCOON_CLEANUP
if type(previousCleanup) == "function" then
	pcall(previousCleanup)
end

local ACTIVE_TOKEN = tostring(os.clock())
SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN = ACTIVE_TOKEN

local CONFIG = {
	version = "0.1.0",
	enabled = false,
	autoCollect = false,
	autoBuy = false,
	autoLoadGamePreset = true,
	highlightAffordable = true,
	showLabels = false,
	showWaypoint = true,
	requireOwnerMatch = true,
	touchMode = "Virtual",
	buyMode = "Nearest",
	collectMode = "Nearby",
	collectRange = 90,
	scanInterval = 8,
	renderInterval = 1,
	uiInterval = 0.35,
	statsInterval = 1,
	collectInterval = 0.75,
	buyInterval = 1.35,
	maxButtons = 60,
	maxDrops = 50,
	maxLabels = 12,
	uiOffsetX = 24,
	uiOffsetY = 180,
	moduleBaseUrl = tostring(SHARED_ENV.__VYRS_TYCOON_MODULE_BASE_URL
		or "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/main/tycoon_modules"),
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
		if CONFIG[key] ~= nil and key ~= "version" and key ~= "enabled" and key ~= "moduleBaseUrl" then
			CONFIG[key] = value
		end
	end
	CONFIG.enabled = false
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
		if key ~= "version" and key ~= "moduleBaseUrl" then
			payload[key] = value
		end
	end

	payload.placeConfigs = payload.placeConfigs or {}
	payload.placeConfigs[tostring(game.PlaceId)] = {}
	for key, value in pairs(CONFIG) do
		if key ~= "version" and key ~= "moduleBaseUrl" and key ~= "placeConfigs" then
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
		local name = item.Name:lower()
		if (name:find("cash") or name:find("money") or name:find("coin")) and tonumber(item.Value) then
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

local EVENT_SCAN_DEBOUNCE = 0.15
local EVENT_SCAN_MIN_INTERVAL = 0.45

local runtime = {
	lastScan = 0,
	lastCollect = 0,
	lastBuy = 0,
	lastRender = 0,
	lastUi = 0,
	lastStats = 0,
	data = nil,
	nearest = nil,
	cheapest = nil,
	bestValue = nil,
	nextLocked = nil,
	collected = 0,
	bought = 0,
	purchaseAttempts = 0,
	purchaseFailures = 0,
	wasEnabled = false,
	scanDirty = true,
	scanDirtyAt = 0,
	watchedRoot = nil,
	rootConnections = {},
}

local function markScanDirty()
	if not runtime.scanDirty then
		runtime.scanDirty = true
		runtime.scanDirtyAt = os.clock()
	end
end

ui.onToggle("enabled", function(value)
	CONFIG.enabled = value
	if value then
		runtime.lastScan = -math.huge
		runtime.lastRender = -math.huge
		runtime.scanDirty = true
		runtime.scanDirtyAt = 0
	end
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
	runtime.lastScan = -math.huge
	runtime.scanDirty = true
	runtime.scanDirtyAt = 0
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
ui.onCycle("touchMode", function(value)
	CONFIG.touchMode = value
	saveSettings()
end)
ui.onCycle("collectMode", function(value)
	CONFIG.collectMode = value
	saveSettings()
end)

local heartbeatConnection
local cleanedUp = false

local function disconnectRootWatch()
	for _, connection in ipairs(runtime.rootConnections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	runtime.rootConnections = {}
	runtime.watchedRoot = nil
end

local function lowerName(instance)
	return instance and tostring(instance.Name or ""):lower() or ""
end

local function looksPurchaseRelated(instance)
	if not instance then
		return false
	end

	if instance:IsA("TouchTransmitter") or instance:IsA("ProximityPrompt") or instance:IsA("ClickDetector") then
		return true
	end

	local name = lowerName(instance)
	if name:find("button", 1, true)
		or name:find("purchase", 1, true)
		or name:find("buy", 1, true)
		or name:find("price", 1, true)
		or name:find("cost", 1, true)
		or name:find("owner", 1, true) then
		return true
	end

	local parent = instance.Parent
	local parentName = lowerName(parent)
	if parentName:find("button", 1, true)
		or parentName:find("purchase", 1, true)
		or parentName:find("buy", 1, true)
		or parentName:find("pad", 1, true) then
		return true
	end

	if (instance:IsA("IntValue") or instance:IsA("NumberValue") or instance:IsA("StringValue"))
		and (name:find("cash", 1, true) or name:find("money", 1, true)) then
		return true
	end

	return false
end

local function watchRoot(root)
	if runtime.watchedRoot == root then
		return
	end

	disconnectRootWatch()
	if not root or root == workspace or not root.Parent then
		return
	end

	runtime.watchedRoot = root
	table.insert(runtime.rootConnections, root.DescendantAdded:Connect(function(instance)
		if looksPurchaseRelated(instance) then
			markScanDirty()
		end
	end))
	table.insert(runtime.rootConnections, root.DescendantRemoving:Connect(function(instance)
		if looksPurchaseRelated(instance) then
			markScanDirty()
		end
	end))
	table.insert(runtime.rootConnections, root.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			markScanDirty()
		end
	end))
end

local function refreshUpgradeTargets()
	runtime.nearest = runSafe("nearest upgrade", upgrades.getNearestAffordable, runtime.data, getLocalRoot())
	runtime.cheapest = runSafe("cheapest upgrade", upgrades.getCheapestAffordable, runtime.data)
	runtime.bestValue = runSafe("best value upgrade", upgrades.getMostExpensiveAffordable, runtime.data)
	runtime.nextLocked = runSafe("next locked upgrade", upgrades.getNextLocked, runtime.data)
end

local function performScan(now)
	runtime.scanDirty = false
	runtime.lastScan = now
	local scanned = runSafe("scan", scanner.scan, context)
	if scanned then
		runtime.data = scanned
		watchRoot(scanned.root)
	end
	refreshUpgradeTargets()
end

local function cleanup()
	if cleanedUp then
		return
	end
	cleanedUp = true

	if heartbeatConnection then
		pcall(function()
			heartbeatConnection:Disconnect()
		end)
		heartbeatConnection = nil
	end
	disconnectRootWatch()

	runSafe("highlight clear", upgrades.clear)
	runSafe("label clear", upgrades.clearLabels)
	runSafe("waypoint hide", upgrades.hideWaypoint)
	if type(upgrades.destroy) == "function" then
		runSafe("upgrades destroy", upgrades.destroy)
	end
	if ui and ui.destroy then
		runSafe("ui destroy", ui.destroy)
	end

	if SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN == ACTIVE_TOKEN then
		SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN = nil
	end
	if SHARED_ENV.__VYRS_TYCOON_CLEANUP == cleanup then
		SHARED_ENV.__VYRS_TYCOON_CLEANUP = nil
	end
	if SHARED_ENV.__VYRS_TYCOON_DIAGNOSTICS == runtime then
		SHARED_ENV.__VYRS_TYCOON_DIAGNOSTICS = nil
	end
end

SHARED_ENV.__VYRS_TYCOON_CLEANUP = cleanup
SHARED_ENV.__VYRS_TYCOON_DIAGNOSTICS = runtime

local function isActiveToken()
	return SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN == ACTIVE_TOKEN and not cleanedUp
end

local function collectAllowed(data)
	return data and data.automationAllowed == true
end

local function buyAllowed(data)
	return data and data.automationAllowed == true
end

heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
	if not isActiveToken() then
		cleanup()
		return
	end

	local now = os.clock()
	if CONFIG.enabled and now - runtime.lastStats >= CONFIG.statsInterval then
		runtime.lastStats = now
		runSafe("stats update", stats.update, deltaTime)
	end

	if CONFIG.enabled then
		local eventScanDue = runtime.scanDirty
			and now - runtime.scanDirtyAt >= EVENT_SCAN_DEBOUNCE
			and now - runtime.lastScan >= EVENT_SCAN_MIN_INTERVAL
		local periodicScanDue = now - runtime.lastScan >= CONFIG.scanInterval
		if eventScanDue or periodicScanDue then
			performScan(now)
		end
	end

	if CONFIG.enabled and runtime.data then
		runtime.wasEnabled = true
		runtime.data.showLabels = CONFIG.showLabels

		if now - runtime.lastRender >= CONFIG.renderInterval then
			runtime.lastRender = now
			refreshUpgradeTargets()
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

		if buyAllowed(runtime.data) and CONFIG.autoBuy and now - runtime.lastBuy >= CONFIG.buyInterval then
			runtime.lastBuy = now
			refreshUpgradeTargets()
			local target = upgrades.choosePurchase(runtime.data, getLocalRoot(), CONFIG.buyMode)
			if target then
				runtime.purchaseAttempts = runtime.purchaseAttempts + 1
				if runSafe("buy", collector.buyButton, context, target) then
					runtime.bought = runtime.bought + 1
					markScanDirty()
				else
					runtime.purchaseFailures = runtime.purchaseFailures + 1
					refreshUpgradeTargets()
				end
			end
		end

		if collectAllowed(runtime.data) and CONFIG.autoCollect and now - runtime.lastCollect >= CONFIG.collectInterval then
			runtime.lastCollect = now
			runtime.collected = runtime.collected + (runSafe("collect", collector.collectNearby, context, runtime.data) or 0)
		end
	elseif runtime.wasEnabled then
		runtime.wasEnabled = false
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
		if isActiveToken() then
			saveSettings()
		end
	end
end)