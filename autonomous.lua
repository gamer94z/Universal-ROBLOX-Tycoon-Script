--[[
	Copyright (c) 2026 gamer94z / 0xVyrs
	All Rights Reserved.

	0xVyrs Tycoon Autonomous Runtime
	Adaptive progression, learning, recovery and spectator support.
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

local ACTIVE_TOKEN = "autonomous:" .. tostring(os.clock())
SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN = ACTIVE_TOKEN

local CONFIG = {
	version = "0.2.0-dev",
	enabled = false,
	autoCollect = true,
	autoBuy = true,
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
	renderInterval = 0.75,
	uiInterval = 0.35,
	statsInterval = 1,
	collectInterval = 0.5,
	buyInterval = 0.5,
	maxButtons = 80,
	maxDrops = 60,
	maxLabels = 12,
	uiOffsetX = 24,
	uiOffsetY = 180,

	autopilotEnabled = true,
	learningEnabled = true,
	burstMode = true,
	autoClaim = false,
	autoRebirth = false,
	spectatorMode = false,

	moduleBaseUrl = tostring(SHARED_ENV.__VYRS_TYCOON_MODULE_BASE_URL
		or "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/core-hardening/tycoon_modules"),
}

local SETTINGS_FILE = "tycoon_settings.json"
local MODULE_NAMES = { "scanner", "ui", "collector", "upgrades", "stats", "brain", "autopilot", "spectator" }

local function canUseFileApi()
	return type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function"
end

local function loadSettings()
	if not canUseFileApi() or not isfile(SETTINGS_FILE) then return end
	local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(SETTINGS_FILE)) end)
	if not ok or type(decoded) ~= "table" then return end
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
	if not canUseFileApi() then return end
	local payload = {}
	if isfile(SETTINGS_FILE) then
		pcall(function()
			local decoded = HttpService:JSONDecode(readfile(SETTINGS_FILE))
			if type(decoded) == "table" then payload = decoded end
		end)
	end
	for key, value in pairs(CONFIG) do
		if key ~= "version" and key ~= "moduleBaseUrl" then payload[key] = value end
	end
	payload.placeConfigs = payload.placeConfigs or {}
	payload.placeConfigs[tostring(game.PlaceId)] = {}
	for key, value in pairs(CONFIG) do
		if key ~= "version" and key ~= "moduleBaseUrl" then
			payload.placeConfigs[tostring(game.PlaceId)][key] = value
		end
	end
	pcall(function() writefile(SETTINGS_FILE, HttpService:JSONEncode(payload)) end)
end

local function getLocalRoot()
	local character = LOCAL_PLAYER.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getCashObject()
	local leaderstats = LOCAL_PLAYER:FindFirstChild("leaderstats")
	if not leaderstats then return nil end
	for _, exactName in ipairs({ "Cash", "Money", "Coins", "Balance" }) do
		local item = leaderstats:FindFirstChild(exactName)
		if item and tonumber(item.Value) then return item end
	end
	for _, item in ipairs(leaderstats:GetChildren()) do
		local name = item.Name:lower()
		if (name:find("cash", 1, true) or name:find("money", 1, true) or name:find("coin", 1, true)) and tonumber(item.Value) then
			return item
		end
	end
	return nil
end

local function getCash()
	local item = getCashObject()
	return item and tonumber(item.Value) or nil
end

local context = {
	Players = Players,
	RunService = RunService,
	CoreGui = CoreGui,
	HttpService = HttpService,
	LOCAL_PLAYER = LOCAL_PLAYER,
	CONFIG = CONFIG,
	SHARED_ENV = SHARED_ENV,
	saveSettings = saveSettings,
	getLocalRoot = getLocalRoot,
	getCash = getCash,
}

local function requireModule(name)
	if type(loadstring) ~= "function" then return nil end
	local source
	local fileName = name .. ".lua"
	if type(readfile) == "function" then
		for _, path in ipairs({
			"Tycoon/tycoon_modules/" .. fileName,
			"Tycoon\\tycoon_modules\\" .. fileName,
			"tycoon_modules/" .. fileName,
			"tycoon_modules\\" .. fileName,
		}) do
			local ok, result = pcall(function() return readfile(path) end)
			if ok and type(result) == "string" and result ~= "" then source = result; break end
		end
	end
	if not source and type(game.HttpGet) == "function" then
		local ok, result = pcall(function()
			return game:HttpGet(CONFIG.moduleBaseUrl:gsub("/+$", "") .. "/" .. fileName)
		end)
		if ok and type(result) == "string" and result ~= "" then source = result end
	end
	if not source then return nil end
	local ok, result = pcall(function()
		local chunk = loadstring(source)
		return chunk and chunk() or nil
	end)
	if not ok then
		warn("[0xVyrs Tycoon] " .. name .. " compile failed: " .. tostring(result))
		return nil
	end
	return result
end

local function init(factory)
	if type(factory) ~= "function" then return factory end
	local ok, result = pcall(factory, context)
	if ok and result ~= nil then return result end
	ok, result = pcall(factory)
	return ok and result or nil
end

local function safe(name, callback, ...)
	if type(callback) ~= "function" then return nil end
	local ok, a, b = pcall(callback, ...)
	if not ok then
		warn("[0xVyrs Tycoon] " .. name .. " failed: " .. tostring(a))
		return nil
	end
	return a, b
end

loadSettings()
local oldGui = CoreGui:FindFirstChild("TycoonCoreGUI")
if oldGui then oldGui:Destroy() end

local factories = {}
for _, name in ipairs(MODULE_NAMES) do
	factories[name] = requireModule(name)
	if not factories[name] then error("[0xVyrs Tycoon] Missing module: " .. name) end
end

local scanner = init(factories.scanner)
local collector = init(factories.collector)
local upgrades = init(factories.upgrades)
local brain = init(factories.brain)
local autopilot = init(factories.autopilot)
local spectator = init(factories.spectator)
local ui = safe("ui init", factories.ui, context)
local stats = safe("stats init", factories.stats, context)

if type(scanner) ~= "table" or type(collector) ~= "table" or type(upgrades) ~= "table"
	or type(brain) ~= "table" or type(autopilot) ~= "table" or type(spectator) ~= "table"
	or type(ui) ~= "table" or type(stats) ~= "table" then
	error("[0xVyrs Tycoon] Autonomous module init failed")
end

local runtime = {
	data = nil,
	nearest = nil,
	cheapest = nil,
	bestValue = nil,
	nextLocked = nil,
	plannedTarget = nil,
	planScore = nil,
	lastScan = -math.huge,
	lastRender = -math.huge,
	lastUi = -math.huge,
	lastStats = -math.huge,
	lastBuy = -math.huge,
	lastCollect = -math.huge,
	lastClaim = -math.huge,
	lastCashConnect = -math.huge,
	bought = 0,
	collected = 0,
	purchaseAttempts = 0,
	purchaseFailures = 0,
	scanCount = 0,
	scanDirty = true,
	scanDirtyAt = 0,
	buyBusy = false,
	collectBusy = false,
	scanBusy = false,
	wasEnabled = false,
	watchedRoot = nil,
	rootConnections = {},
	globalConnections = {},
	cashConnection = nil,
	cashObject = nil,
}

local EVENT_SCAN_DEBOUNCE = 0.16
local EVENT_SCAN_MIN_INTERVAL = 0.38
local heartbeatConnection
local cleanedUp = false

local function markScanDirty(immediate)
	if not runtime.scanDirty then
		runtime.scanDirty = true
		runtime.scanDirtyAt = immediate and 0 or os.clock()
	elseif immediate then
		runtime.scanDirtyAt = 0
	end
end

local function disconnectList(list)
	for _, connection in ipairs(list) do pcall(function() connection:Disconnect() end) end
	table.clear(list)
end

local function disconnectRootWatch()
	disconnectList(runtime.rootConnections)
	runtime.watchedRoot = nil
end

local function looksStructural(instance)
	if not instance then return false end
	if instance:IsA("TouchTransmitter") or instance:IsA("ProximityPrompt") or instance:IsA("ClickDetector") then return true end
	local name = tostring(instance.Name or ""):lower()
	return name:find("button", 1, true) or name:find("purchase", 1, true)
		or name:find("buy", 1, true) or name:find("price", 1, true)
		or name:find("cost", 1, true) or name:find("owner", 1, true)
		or name:find("drop", 1, true) or name:find("collect", 1, true)
end

local function watchRoot(root)
	if runtime.watchedRoot == root then return end
	disconnectRootWatch()
	if not root or root == workspace or not root.Parent then return end
	runtime.watchedRoot = root
	table.insert(runtime.rootConnections, root.DescendantAdded:Connect(function(instance)
		if looksStructural(instance) then markScanDirty(false) end
	end))
	table.insert(runtime.rootConnections, root.DescendantRemoving:Connect(function(instance)
		if looksStructural(instance) then markScanDirty(false) end
	end))
	table.insert(runtime.rootConnections, root.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if scanner.invalidateRoot then safe("invalidate root", scanner.invalidateRoot, root) end
			markScanDirty(true)
		end
	end))
end

local function statsState()
	return safe("stats get", stats.get) or {}
end

local function updateCashState()
	if not runtime.data then return end
	local cash = getCash()
	if cash == nil then return end
	runtime.data.cash = cash
	for _, button in ipairs(runtime.data.buttons or {}) do
		if not button.paidPurchase then
			local price = tonumber(button.price)
			if price then
				button.affordable = price <= cash
				button.locked = price > cash
			end
		end
	end
end

local function connectCashWatch()
	local item = getCashObject()
	if item == runtime.cashObject and runtime.cashConnection then return end
	if runtime.cashConnection then pcall(function() runtime.cashConnection:Disconnect() end) end
	runtime.cashConnection = nil
	runtime.cashObject = item
	if not item then return end
	runtime.cashConnection = item:GetPropertyChangedSignal("Value"):Connect(function()
		updateCashState()
		if CONFIG.autopilotEnabled and CONFIG.burstMode then runtime.lastBuy = -math.huge end
		runtime.lastRender = -math.huge
	end)
end

local function refreshTargets()
	updateCashState()
	runtime.nearest = safe("nearest", upgrades.getNearestAffordable, runtime.data, getLocalRoot())
	runtime.cheapest = safe("cheapest", upgrades.getCheapestAffordable, runtime.data)
	runtime.bestValue = safe("value", upgrades.getMostExpensiveAffordable, runtime.data)
	runtime.nextLocked = safe("locked", upgrades.getNextLocked, runtime.data)
	if CONFIG.autopilotEnabled and CONFIG.learningEnabled and runtime.data then
		runtime.plannedTarget, runtime.planScore = safe("brain choose", brain.choosePurchase, runtime.data, statsState())
	else
		runtime.plannedTarget = safe("legacy choose", upgrades.choosePurchase, runtime.data, getLocalRoot(), CONFIG.buyMode)
		runtime.planScore = nil
	end
	if CONFIG.spectatorMode then safe("spectator target", spectator.setTarget, runtime.plannedTarget or runtime.nearest) end
end

local function performScan(now)
	if runtime.scanBusy then return end
	runtime.scanBusy = true
	runtime.scanDirty = false
	runtime.lastScan = now
	local scanned = safe("scan", scanner.scan, context)
	if scanned then
		runtime.data = scanned
		runtime.scanCount = runtime.scanCount + 1
		watchRoot(scanned.root)
		if CONFIG.learningEnabled then safe("brain observe", brain.observe, scanned, statsState()) end
		safe("recovery", autopilot.updateRecovery, scanned)
	end
	refreshTargets()
	runtime.scanBusy = false
end

local function setEnabled(value)
	CONFIG.enabled = value == true
	safe("autopilot enabled", autopilot.noteEnabled, CONFIG.enabled)
	if CONFIG.enabled then
		markScanDirty(true)
		runtime.lastBuy = -math.huge
		runtime.lastCollect = -math.huge
		connectCashWatch()
	end
	saveSettings()
end

local function setSpectator(value)
	CONFIG.spectatorMode = value == true
	safe("spectator toggle", spectator.setEnabled, CONFIG.spectatorMode)
	if CONFIG.spectatorMode then safe("spectator target", spectator.setTarget, runtime.plannedTarget or runtime.nearest) end
	saveSettings()
end

ui.onToggle("enabled", setEnabled)
ui.onToggle("autoCollect", function(v) CONFIG.autoCollect = v; saveSettings() end)
ui.onToggle("autoBuy", function(v) CONFIG.autoBuy = v; saveSettings() end)
ui.onToggle("highlightAffordable", function(v) CONFIG.highlightAffordable = v; saveSettings() end)
ui.onToggle("showLabels", function(v) CONFIG.showLabels = v; saveSettings() end)
ui.onToggle("showWaypoint", function(v) CONFIG.showWaypoint = v; saveSettings() end)
ui.onToggle("requireOwnerMatch", function(v)
	CONFIG.requireOwnerMatch = v
	if scanner.invalidateRoot then safe("owner invalidate", scanner.invalidateRoot) end
	markScanDirty(true)
	saveSettings()
end)
ui.onToggle("autoLoadGamePreset", function(v) CONFIG.autoLoadGamePreset = v; saveSettings() end)
ui.onCycle("buyMode", function(v) CONFIG.buyMode = v; refreshTargets(); saveSettings() end)
ui.onCycle("touchMode", function(v) CONFIG.touchMode = v; saveSettings() end)
ui.onCycle("collectMode", function(v) CONFIG.collectMode = v; saveSettings() end)

local function cleanup()
	if cleanedUp then return end
	cleanedUp = true
	if heartbeatConnection then pcall(function() heartbeatConnection:Disconnect() end) end
	if runtime.cashConnection then pcall(function() runtime.cashConnection:Disconnect() end) end
	disconnectRootWatch()
	disconnectList(runtime.globalConnections)
	safe("brain save", brain.save)
	safe("spectator destroy", spectator.destroy)
	safe("highlight clear", upgrades.clear)
	safe("label clear", upgrades.clearLabels)
	safe("waypoint hide", upgrades.hideWaypoint)
	if upgrades.destroy then safe("upgrades destroy", upgrades.destroy) end
	if ui.destroy then safe("ui destroy", ui.destroy) end
	if SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN == ACTIVE_TOKEN then SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN = nil end
	if SHARED_ENV.__VYRS_TYCOON_CLEANUP == cleanup then SHARED_ENV.__VYRS_TYCOON_CLEANUP = nil end
	if SHARED_ENV.__VYRS_TYCOON_DIAGNOSTICS == runtime then SHARED_ENV.__VYRS_TYCOON_DIAGNOSTICS = nil end
	SHARED_ENV.__VYRS_TYCOON_AUTONOMOUS = nil
end

local function status()
	return {
		version = CONFIG.version,
		enabled = CONFIG.enabled,
		autopilotEnabled = CONFIG.autopilotEnabled,
		autoBuy = CONFIG.autoBuy,
		autoCollect = CONFIG.autoCollect,
		autoClaim = CONFIG.autoClaim,
		autoRebirth = CONFIG.autoRebirth,
		spectatorMode = CONFIG.spectatorMode,
		bought = runtime.bought,
		collected = runtime.collected,
		purchaseAttempts = runtime.purchaseAttempts,
		purchaseFailures = runtime.purchaseFailures,
		scanCount = runtime.scanCount,
		root = runtime.data and runtime.data.rootName or nil,
		ownerVerified = runtime.data and runtime.data.ownerVerified or false,
		buttons = runtime.data and runtime.data.totalButtons or 0,
		cash = runtime.data and runtime.data.cash or getCash(),
		brain = safe("brain status", brain.getStatus, runtime.data, statsState()),
		autopilot = safe("autopilot status", autopilot.getStatus),
		spectator = safe("spectator status", spectator.getStatus),
	}
end

SHARED_ENV.__VYRS_TYCOON_CLEANUP = cleanup
SHARED_ENV.__VYRS_TYCOON_DIAGNOSTICS = runtime
SHARED_ENV.__VYRS_TYCOON_AUTONOMOUS = {
	start = function()
		CONFIG.autoBuy = true
		CONFIG.autoCollect = true
		CONFIG.autopilotEnabled = true
		setEnabled(true)
		return true
	end,
	startFull = function()
		CONFIG.autoClaim = true
		CONFIG.autoBuy = true
		CONFIG.autoCollect = true
		CONFIG.autopilotEnabled = true
		setEnabled(true)
		return true
	end,
	stop = function() setEnabled(false); return true end,
	setEnabled = setEnabled,
	setAutopilot = function(v) CONFIG.autopilotEnabled = v == true; refreshTargets(); saveSettings(); return CONFIG.autopilotEnabled end,
	setAutoClaim = function(v) CONFIG.autoClaim = v == true; saveSettings(); return CONFIG.autoClaim end,
	setAutoRebirth = function(v) CONFIG.autoRebirth = v == true; saveSettings(); return CONFIG.autoRebirth end,
	setSpectator = function(v) setSpectator(v); return CONFIG.spectatorMode end,
	setLearning = function(v) CONFIG.learningEnabled = v == true; saveSettings(); return CONFIG.learningEnabled end,
	setBurst = function(v) CONFIG.burstMode = v == true; saveSettings(); return CONFIG.burstMode end,
	resetLearning = function() return safe("brain reset", brain.resetPlaceProfile) end,
	status = status,
	cleanup = cleanup,
}

local function active()
	return not cleanedUp and SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN == ACTIVE_TOKEN
end

table.insert(runtime.globalConnections, LOCAL_PLAYER.CharacterAdded:Connect(function()
	if scanner.invalidateRoot then safe("character invalidate", scanner.invalidateRoot) end
	markScanDirty(true)
	connectCashWatch()
end))

connectCashWatch()
setSpectator(CONFIG.spectatorMode)
safe("autopilot enabled", autopilot.noteEnabled, CONFIG.enabled)

heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
	if not active() then cleanup(); return end
	local now = os.clock()

	if not runtime.cashConnection and now - runtime.lastCashConnect >= 2 then
		runtime.lastCashConnect = now
		connectCashWatch()
	end

	if CONFIG.enabled and now - runtime.lastStats >= CONFIG.statsInterval then
		runtime.lastStats = now
		safe("stats update", stats.update, deltaTime)
	end

	if CONFIG.enabled then
		local eventDue = runtime.scanDirty and now - runtime.scanDirtyAt >= EVENT_SCAN_DEBOUNCE and now - runtime.lastScan >= EVENT_SCAN_MIN_INTERVAL
		local periodicDue = now - runtime.lastScan >= CONFIG.scanInterval
		if eventDue or periodicDue then performScan(now) end
	end

	if CONFIG.enabled and runtime.data then
		runtime.wasEnabled = true
		runtime.data.showLabels = CONFIG.showLabels
		updateCashState()

		if not runtime.data.ownerVerified and CONFIG.autoClaim and now - runtime.lastClaim >= 4 then
			runtime.lastClaim = now
			if safe("auto claim", autopilot.tryClaim) then
				if scanner.invalidateRoot then safe("claim invalidate", scanner.invalidateRoot) end
				markScanDirty(true)
			end
		end

		local complete = safe("completion", autopilot.updateCompletion, brain, runtime.data) == true
		if complete then
			safe("record completion", autopilot.recordCompletion, brain)
			if CONFIG.autoRebirth and not runtime.buyBusy and safe("auto rebirth", autopilot.tryRebirth, runtime.data) then
				if scanner.invalidateRoot then safe("rebirth invalidate", scanner.invalidateRoot) end
				markScanDirty(true)
			end
		end

		if now - runtime.lastRender >= CONFIG.renderInterval then
			runtime.lastRender = now
			refreshTargets()
			if CONFIG.highlightAffordable then safe("highlight", upgrades.render, runtime.data, runtime.plannedTarget or runtime.nearest)
			else safe("highlight clear", upgrades.clear) end
			safe("labels", upgrades.renderLabels, runtime.data, runtime.plannedTarget or runtime.nearest)
			if CONFIG.showWaypoint then safe("waypoint", upgrades.updateWaypoint, runtime.plannedTarget or runtime.nearest or runtime.cheapest)
			else safe("waypoint hide", upgrades.hideWaypoint) end
		end

		local buyInterval = CONFIG.buyInterval
		if CONFIG.autopilotEnabled and CONFIG.burstMode then buyInterval = safe("buy interval", autopilot.getBuyInterval, runtime.data) or buyInterval end
		if CONFIG.autoBuy and runtime.data.automationAllowed and not complete and not runtime.buyBusy and now - runtime.lastBuy >= buyInterval then
			runtime.lastBuy = now
			runtime.buyBusy = true
			refreshTargets()
			local target = runtime.plannedTarget
			if target then
				runtime.purchaseAttempts = runtime.purchaseAttempts + 1
				if safe("buy", collector.buyButton, context, target) == true then
					runtime.bought = runtime.bought + 1
					if CONFIG.learningEnabled then safe("learn purchase", brain.notePurchase, target, runtime.data, statsState()) end
					markScanDirty(true)
					if CONFIG.burstMode then runtime.lastBuy = -math.huge end
				else
					runtime.purchaseFailures = runtime.purchaseFailures + 1
					if CONFIG.learningEnabled then safe("learn failure", brain.noteFailure, target) end
				end
			end
			runtime.buyBusy = false
		end

		local collectInterval = CONFIG.collectInterval
		if CONFIG.autopilotEnabled then collectInterval = safe("collect interval", autopilot.getCollectInterval, runtime.data) or collectInterval end
		if CONFIG.autoCollect and runtime.data.automationAllowed and not runtime.collectBusy and now - runtime.lastCollect >= collectInterval then
			runtime.lastCollect = now
			runtime.collectBusy = true
			runtime.collected = runtime.collected + (safe("collect", collector.collectNearby, context, runtime.data) or 0)
			runtime.collectBusy = false
		end
	elseif runtime.wasEnabled then
		runtime.wasEnabled = false
		safe("highlight clear", upgrades.clear)
		safe("label clear", upgrades.clearLabels)
		safe("waypoint hide", upgrades.hideWaypoint)
	end

	if now - runtime.lastUi >= CONFIG.uiInterval then
		runtime.lastUi = now
		safe("ui update", ui.update, {
			data = runtime.data,
			nearest = runtime.plannedTarget or runtime.nearest,
			cheapest = runtime.cheapest,
			bestValue = runtime.bestValue,
			nextLocked = runtime.nextLocked,
			stats = statsState(),
			collected = runtime.collected,
			bought = runtime.bought,
		})
	end
end)

local spawn = task and task.spawn or coroutine.wrap
spawn(function()
	while active() do
		if task and task.wait then task.wait(15) else wait(15) end
		if active() then
			saveSettings()
			if CONFIG.learningEnabled then safe("brain autosave", brain.save) end
		end
	end
end)

print("[0xVyrs Tycoon] Autonomous runtime loaded. Use getgenv().__VYRS_TYCOON_AUTONOMOUS.start() to begin.")
