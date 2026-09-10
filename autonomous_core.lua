--[[
	Copyright (c) 2026 gamer94z / 0xVyrs
	All Rights Reserved.

	0xVyrs Tycoon Autonomous Runtime v1.0.0 - Core Rebuild
	Integrated currency, persistent interaction state and isolated workers.
]]

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local LOCAL_PLAYER = Players.LocalPlayer

local SHARED_ENV = (type(getgenv) == "function" and getgenv())
	or (type(getfenv) == "function" and getfenv(0))
	or _G

local previousCleanup = SHARED_ENV.__VYRS_TYCOON_CLEANUP
if type(previousCleanup) == "function" then pcall(previousCleanup) end

local ACTIVE_TOKEN = "core:" .. tostring(os.clock())
SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN = ACTIVE_TOKEN

local CONFIG = {
	version = "1.0.0",
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
	renderInterval = 0.45,
	uiInterval = 0.65,
	statsInterval = 0.9,
	collectInterval = 0.6,
	buyInterval = 0.35,
	maxButtons = 80,
	maxDrops = 60,
	maxLabels = 12,
	uiOffsetX = 24,
	uiOffsetY = 180,

	autopilotEnabled = true,
	learningEnabled = true,
	burstMode = true,
	autoRewards = true,
	autoRebirth = false,
	strategy = "Fastest",

	moduleBaseUrl = tostring(SHARED_ENV.__VYRS_TYCOON_MODULE_BASE_URL
		or "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/v1.0-core-rebuild/tycoon_modules"),
}

local SETTINGS_FILE = "tycoon_settings.json"
local MODULE_NAMES = { "scanner", "ui", "collector", "upgrades", "stats", "brain", "autopilot", "boosts" }
local EVENT_SCAN_DEBOUNCE = 0.35
local EVENT_SCAN_MAX_WAIT = 1.5
local EVENT_SCAN_MIN_INTERVAL = 1.25

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
		if CONFIG[key] ~= nil and key ~= "version" and key ~= "enabled" and key ~= "moduleBaseUrl" then CONFIG[key] = value end
	end
	if CONFIG.strategy ~= "Fastest" and CONFIG.strategy ~= "Income" and CONFIG.strategy ~= "Rebirth" then CONFIG.strategy = "Fastest" end
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
	for key, value in pairs(CONFIG) do if key ~= "version" and key ~= "moduleBaseUrl" then payload[key] = value end end
	payload.placeConfigs = payload.placeConfigs or {}
	payload.placeConfigs[tostring(game.PlaceId)] = {}
	for key, value in pairs(CONFIG) do
		if key ~= "version" and key ~= "moduleBaseUrl" then payload.placeConfigs[tostring(game.PlaceId)][key] = value end
	end
	pcall(function() writefile(SETTINGS_FILE, HttpService:JSONEncode(payload)) end)
end

local function getLocalRoot()
	local character = LOCAL_PLAYER.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getLegacyCashObject()
	local leaderstats = LOCAL_PLAYER:FindFirstChild("leaderstats")
	if not leaderstats then return nil end
	for _, exactName in ipairs({ "Cash", "Money", "Coins", "Balance" }) do
		local item = leaderstats:FindFirstChild(exactName)
		if item and tonumber(item.Value) then return item end
	end
	for _, item in ipairs(leaderstats:GetChildren()) do
		local name = tostring(item.Name):lower()
		if (name:find("cash", 1, true) or name:find("money", 1, true) or name:find("coin", 1, true)) and tonumber(item.Value) then return item end
	end
	return nil
end

local function fetchModuleSource(name)
	local fileName = name .. ".lua"
	if SHARED_ENV.__VYRS_TYCOON_USE_LOCAL_MODULES == true and type(readfile) == "function" then
		for _, path in ipairs({
			"Tycoon/tycoon_modules/" .. fileName,
			"Tycoon\\tycoon_modules\\" .. fileName,
			"tycoon_modules/" .. fileName,
			"tycoon_modules\\" .. fileName,
		}) do
			local ok, result = pcall(function() return readfile(path) end)
			if ok and type(result) == "string" and result ~= "" then return result, "local:" .. path end
		end
	end
	local ok, result = pcall(function()
		return game:HttpGet(CONFIG.moduleBaseUrl:gsub("/+$", "") .. "/" .. fileName)
	end)
	if ok and type(result) == "string" and result ~= "" then return result, "remote" end
	return nil, tostring(result or "not found")
end

local function loadFactory(name)
	if type(loadstring) ~= "function" then error("[0xVyrs Tycoon] loadstring unavailable") end
	local source, origin = fetchModuleSource(name)
	if not source then error("[0xVyrs Tycoon] Missing module " .. name .. " // " .. tostring(origin)) end
	local chunk, compileError = loadstring(source)
	if type(chunk) ~= "function" then error("[0xVyrs Tycoon] " .. name .. " compile failed: " .. tostring(compileError)) end
	local ok, factory = pcall(chunk)
	if not ok then error("[0xVyrs Tycoon] " .. name .. " load failed: " .. tostring(factory)) end
	return factory
end

local function safe(name, callback, ...)
	if type(callback) ~= "function" then return nil end
	local ok, a, b, c = pcall(callback, ...)
	if not ok then
		warn("[0xVyrs Tycoon] " .. name .. " failed: " .. tostring(a))
		return nil
	end
	return a, b, c
end

loadSettings()
local oldGui = CoreGui:FindFirstChild("TycoonCoreGUI")
if oldGui then oldGui:Destroy() end

local currency
local function getCash()
	if currency and type(currency.get) == "function" then
		local value = safe("currency get", currency.get)
		if tonumber(value) ~= nil then return tonumber(value) end
	end
	local item = getLegacyCashObject()
	return item and tonumber(item.Value) or nil
end

local function getCashSourceKey()
	if currency and type(currency.status) == "function" then
		local status = safe("currency status", currency.status)
		if type(status) == "table" then return status.path or status.source end
	end
	local item = getLegacyCashObject()
	return item and item:GetFullName() or nil
end

local context = {
	Players = Players,
	CoreGui = CoreGui,
	HttpService = HttpService,
	LOCAL_PLAYER = LOCAL_PLAYER,
	CONFIG = CONFIG,
	SHARED_ENV = SHARED_ENV,
	saveSettings = saveSettings,
	getLocalRoot = getLocalRoot,
	getCash = getCash,
	getCashSourceKey = getCashSourceKey,
}

local function init(factory, name)
	if type(factory) ~= "function" then return factory end
	local ok, result = pcall(factory, context)
	if not ok or result == nil then error("[0xVyrs Tycoon] " .. tostring(name) .. " init failed: " .. tostring(result)) end
	return result
end

currency = init(loadFactory("currency"), "currency")
SHARED_ENV.__VYRS_TYCOON_GET_CASH = getCash
SHARED_ENV.__VYRS_TYCOON_CURRENCY_MARK = currency.mark
SHARED_ENV.__VYRS_TYCOON_CURRENCY_STATUS = currency.status

local factories = {}
for _, name in ipairs(MODULE_NAMES) do factories[name] = loadFactory(name) end
local scanner = init(factories.scanner, "scanner")
local collector = init(factories.collector, "collector")
local upgrades = init(factories.upgrades, "upgrades")
local stats = init(factories.stats, "stats")
local brain = init(factories.brain, "brain")
local autopilot = init(factories.autopilot, "autopilot")
local boosts = init(factories.boosts, "boosts")
local ui = init(factories.ui, "ui")

local runtime = {
	data = nil,
	nearest = nil,
	cheapest = nil,
	bestValue = nil,
	nextLocked = nil,
	plannedTarget = nil,
	planScore = nil,
	currentTarget = nil,
	currentPhase = "idle",
	brainStatus = nil,
	collectorStatus = nil,
	currencyStatus = nil,
	lastScan = -math.huge,
	lastRender = -math.huge,
	lastUi = -math.huge,
	lastStats = -math.huge,
	lastBuy = -math.huge,
	lastCollect = -math.huge,
	lastRewardSweep = -math.huge,
	bought = 0,
	collected = 0,
	rewardsActivated = 0,
	purchaseAttempts = 0,
	purchaseFailures = 0,
	scanCount = 0,
	scanDirty = true,
	scanDirtyAt = 0,
	scanDirtyFirst = 0,
	scanBusy = false,
	buyBusy = false,
	collectBusy = false,
	rewardBusy = false,
	rebirthBusy = false,
	watchedRoot = nil,
	rootConnections = {},
	globalConnections = {},
	purchaseStates = setmetatable({}, { __mode = "k" }),
}

local cleanedUp = false
local function active()
	return not cleanedUp and SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN == ACTIVE_TOKEN
end

local function disconnectList(list)
	for _, connection in ipairs(list) do pcall(function() connection:Disconnect() end) end
	table.clear(list)
end

local function markScanDirty(immediate)
	local now = os.clock()
	if immediate then
		runtime.scanDirty = true
		runtime.scanDirtyAt = 0
		runtime.scanDirtyFirst = 0
		return
	end
	if not runtime.scanDirty then runtime.scanDirtyFirst = now end
	runtime.scanDirty = true
	runtime.scanDirtyAt = now
end

local function looksStructural(instance)
	if not instance then return false end
	if instance:IsA("TouchTransmitter") or instance:IsA("ProximityPrompt") or instance:IsA("ClickDetector") then return true end
	local name = tostring(instance.Name or ""):lower()
	return name:find("button", 1, true) or name:find("purchase", 1, true) or name:find("buy", 1, true)
		or name:find("price", 1, true) or name:find("cost", 1, true) or name:find("owner", 1, true)
		or name:find("drop", 1, true) or name:find("collect", 1, true)
end

local function watchRoot(root)
	if runtime.watchedRoot == root then return end
	disconnectList(runtime.rootConnections)
	runtime.watchedRoot = nil
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
			if scanner.invalidateRoot then safe("scanner invalidate", scanner.invalidateRoot, root) end
			markScanDirty(true)
		end
	end))
end

local function buttonSignature(button)
	return tostring(button and button.name or "") .. "|" .. tostring(tonumber(button and button.price) or 0)
end

local function stateFor(button)
	local object = button and button.object
	if not object then return nil end
	local signature = buttonSignature(button)
	local state = runtime.purchaseStates[object]
	if not state or state.signature ~= signature then
		state = { signature = signature, failureCount = 0, blockedUntil = nil, phase = "ready", learnedFailure = false }
		runtime.purchaseStates[object] = state
	end
	return state
end

local function applyPurchaseState(button)
	local state = stateFor(button)
	if not state then return end
	local now = os.clock()
	if state.blockedUntil and state.blockedUntil <= now then state.blockedUntil = nil state.phase = "ready" end
	button.blockedUntil = state.blockedUntil
	button.failureCount = state.failureCount or 0
	button.approaching = state.phase == "buying" or state.phase == "approaching"
end

local function aliveButton(button)
	if not button or button.paidPurchase then return false end
	if not button.object or not button.object.Parent then return false end
	if button.part and not button.part.Parent then return false end
	return true
end

local function reconcileData(data)
	if not data then return nil end

	-- A position-only root can narrow discovery but must never prove ownership.
	if data.selectedByPosition == true and data.ownerSource == "position-cluster" then
		data.ownerVerified = false
		data.ownerMatch = false
		data.owned = false
	end
	data.automationAllowed = data.ownerVerified == true or CONFIG.requireOwnerMatch == false
	data.safeAutomation = data.automationAllowed

	local cash = tonumber(getCash())
	if cash ~= nil then data.cash = cash end

	for index = #(data.buttons or {}), 1, -1 do
		local button = data.buttons[index]
		if not aliveButton(button) then
			table.remove(data.buttons, index)
		else
			applyPurchaseState(button)
			local price = tonumber(button.price)
			if price ~= nil and cash ~= nil then
				button.affordable = price <= cash
				button.locked = price > cash
			end
			button.automationAllowed = data.automationAllowed
		end
	end
	for index = #(data.drops or {}), 1, -1 do
		local drop = data.drops[index]
		if not drop or not drop.object or not drop.object.Parent then table.remove(data.drops, index)
		else drop.automationAllowed = data.automationAllowed end
	end

	local affordable, locked = 0, 0
	for _, button in ipairs(data.buttons or {}) do
		if button.affordable and not button.paidPurchase then affordable = affordable + 1
		elseif button.locked and not button.paidPurchase then locked = locked + 1 end
	end
	data.totalButtons = #(data.buttons or {})
	data.affordableCount = affordable
	data.lockedCount = locked
	return data
end

local function statsState()
	return safe("stats get", stats.get) or {}
end

local function finiteScore(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function actionable(button)
	if not aliveButton(button) or button.automationAllowed ~= true or button.affordable ~= true then return false end
	if button.blockedUntil and button.blockedUntil > os.clock() then return false end
	return true
end

local function refreshBrainStatus()
	if not CONFIG.learningEnabled then runtime.brainStatus = nil return nil end
	runtime.brainStatus = safe("brain status", brain.getStatus, runtime.data, statsState())
	return runtime.brainStatus
end

local function chooseActionableTarget()
	if not runtime.data then return nil end
	reconcileData(runtime.data)
	local target, score
	if CONFIG.autopilotEnabled and CONFIG.learningEnabled then
		target, score = safe("brain choose", brain.choosePurchase, runtime.data, statsState())
		if not actionable(target) or not finiteScore(score) then target, score = nil, nil end
	end
	if not target then
		target = safe("fallback choose", upgrades.choosePurchase, runtime.data, getLocalRoot(), CONFIG.buyMode)
		if not actionable(target) then target = nil end
	end
	return target, score
end

local function refreshTargets()
	if not runtime.data then
		runtime.nearest, runtime.cheapest, runtime.bestValue, runtime.nextLocked, runtime.plannedTarget = nil, nil, nil, nil, nil
		return
	end
	reconcileData(runtime.data)
	runtime.nearest = safe("nearest", upgrades.getNearestAffordable, runtime.data, getLocalRoot())
	runtime.cheapest = safe("cheapest", upgrades.getCheapestAffordable, runtime.data)
	runtime.bestValue = safe("value", upgrades.getMostExpensiveAffordable, runtime.data)
	runtime.nextLocked = safe("locked", upgrades.getNextLocked, runtime.data)
	runtime.plannedTarget, runtime.planScore = chooseActionableTarget()

	if runtime.currentTarget and not aliveButton(runtime.currentTarget) then runtime.currentTarget = nil runtime.currentPhase = "idle" end
	if runtime.plannedTarget and not runtime.buyBusy then runtime.currentTarget = runtime.plannedTarget runtime.currentPhase = "ready" end
end

local function performScan()
	if runtime.scanBusy or not active() then return end
	runtime.scanBusy = true
	local scanned = safe("scan", scanner.scan, context)
	if scanned then
		runtime.data = reconcileData(scanned)
		runtime.scanCount = runtime.scanCount + 1
		runtime.lastScan = os.clock()
		watchRoot(runtime.data.root)
		if CONFIG.learningEnabled then safe("brain observe", brain.observe, runtime.data, statsState()) end
		safe("recovery", autopilot.updateRecovery, runtime.data)
	end
	runtime.scanDirty = false
	runtime.scanDirtyAt = os.clock()
	runtime.scanDirtyFirst = runtime.scanDirtyAt
	refreshTargets()
	refreshBrainStatus()
	runtime.scanBusy = false
end

local function learnableFailure(reason)
	return reason == "not-confirmed" or reason == "approach-not-confirmed" or reason == "activation-failed" or reason == "stale-interaction"
end

local function collectorReason()
	runtime.collectorStatus = safe("collector status", collector.getStatus) or runtime.collectorStatus or {}
	return runtime.collectorStatus.lastPurchaseReason
end

local function attemptBuy()
	if runtime.buyBusy or not CONFIG.enabled or not CONFIG.autoBuy or not runtime.data or runtime.data.automationAllowed ~= true then return end
	refreshTargets()
	local target = runtime.plannedTarget
	if not actionable(target) then return end

	runtime.buyBusy = true
	runtime.currentTarget = target
	runtime.currentPhase = "buying"
	local state = stateFor(target)
	if state then state.phase = "buying" end
	target.approaching = true
	runtime.purchaseAttempts = runtime.purchaseAttempts + 1

	local ok, result = pcall(collector.buyButton, context, target)
	local success = ok and result == true
	local reason = ok and collectorReason() or "collector-error"

	if success then
		runtime.bought = runtime.bought + 1
		if stats.noteSpend then safe("record spend", stats.noteSpend, target.price) end
		if CONFIG.learningEnabled then safe("learn purchase", brain.notePurchase, target, runtime.data, statsState()) end
		if target.object then runtime.purchaseStates[target.object] = nil end
		target.approaching = nil
		runtime.currentPhase = "confirmed"
		markScanDirty(true)
	else
		if not ok then warn("[0xVyrs Tycoon] buy worker failed: " .. tostring(result)) end
		state = stateFor(target)
		if state then
			state.failureCount = math.max(state.failureCount or 0, tonumber(target.failureCount) or 0)
			if state.failureCount == 0 then state.failureCount = 1 end
			state.blockedUntil = tonumber(target.blockedUntil) or (os.clock() + 0.7)
			state.phase = "retry"
			target.blockedUntil = state.blockedUntil
			target.failureCount = state.failureCount
			target.approaching = nil
			if CONFIG.learningEnabled and learnableFailure(reason) and state.failureCount >= 3 and not state.learnedFailure then
				state.learnedFailure = true
				safe("learn failure", brain.noteFailure, target)
			end
		end
		if learnableFailure(reason) or reason == "collector-error" then runtime.purchaseFailures = runtime.purchaseFailures + 1 end
		runtime.currentPhase = reason or "retry"
	end

	runtime.lastBuy = os.clock()
	refreshBrainStatus()
	runtime.buyBusy = false
end

local function attemptCollect()
	if runtime.collectBusy or not CONFIG.enabled or not CONFIG.autoCollect or not runtime.data or runtime.data.automationAllowed ~= true then return end
	runtime.collectBusy = true
	local gained = safe("collect", collector.collectNearby, context, runtime.data) or 0
	runtime.collected = runtime.collected + gained
	runtime.collectorStatus = safe("collector status", collector.getStatus) or runtime.collectorStatus
	runtime.lastCollect = os.clock()
	runtime.collectBusy = false
end

local function status()
	local brainState = runtime.brainStatus or refreshBrainStatus() or {}
	local brainOut = {}
	for key, value in pairs(brainState) do brainOut[key] = value end
	local displayTarget = runtime.currentTarget
	if displayTarget and aliveButton(displayTarget) then
		brainOut.plan = brainOut.plan or {}
		brainOut.plan.name = displayTarget.name or (displayTarget.object and displayTarget.object.Name) or "Purchase"
		brainOut.plan.price = displayTarget.price
		brainOut.plan.phase = runtime.currentPhase
	elseif runtime.plannedTarget then
		brainOut.plan = brainOut.plan or {}
		brainOut.plan.name = runtime.plannedTarget.name
	end
	runtime.currencyStatus = safe("currency status", currency.status) or runtime.currencyStatus
	runtime.collectorStatus = safe("collector status", collector.getStatus) or runtime.collectorStatus
	return {
		version = CONFIG.version,
		enabled = CONFIG.enabled,
		autopilotEnabled = CONFIG.autopilotEnabled,
		learningEnabled = CONFIG.learningEnabled,
		burstMode = CONFIG.burstMode,
		autoRewards = CONFIG.autoRewards,
		autoRebirth = CONFIG.autoRebirth,
		strategy = CONFIG.strategy,
		bought = runtime.bought,
		collected = runtime.collected,
		rewardsActivated = runtime.rewardsActivated,
		purchaseAttempts = runtime.purchaseAttempts,
		purchaseFailures = runtime.purchaseFailures,
		purchasePhase = runtime.currentPhase,
		scanCount = runtime.scanCount,
		root = runtime.data and runtime.data.rootName or nil,
		ownerVerified = runtime.data and runtime.data.ownerVerified or false,
		buttons = runtime.data and runtime.data.totalButtons or 0,
		cash = runtime.data and runtime.data.cash or getCash(),
		brain = brainOut,
		collector = runtime.collectorStatus,
		currency = runtime.currencyStatus,
		autopilot = safe("autopilot status", autopilot.getStatus),
		boosts = safe("boost status", boosts.getStatus),
	}
end

local function renderNow()
	if runtime.data then
		reconcileData(runtime.data)
		refreshTargets()
		local displayTarget = runtime.currentTarget or runtime.plannedTarget or runtime.nearest
		if CONFIG.highlightAffordable then safe("highlight", upgrades.render, runtime.data, displayTarget) else safe("highlight clear", upgrades.clear) end
		safe("labels", upgrades.renderLabels, runtime.data, displayTarget)
		if CONFIG.showWaypoint then safe("waypoint", upgrades.updateWaypoint, displayTarget or runtime.cheapest)
		else safe("waypoint hide", upgrades.hideWaypoint) end
	end
	local now = os.clock()
	if now - runtime.lastUi >= CONFIG.uiInterval then
		runtime.lastUi = now
		refreshBrainStatus()
		safe("ui update", ui.update, {
			data = runtime.data,
			nearest = runtime.currentTarget or runtime.plannedTarget or runtime.nearest,
			cheapest = runtime.cheapest,
			bestValue = runtime.bestValue,
			nextLocked = runtime.nextLocked,
			stats = statsState(),
			collected = runtime.collected,
			bought = runtime.bought,
			autonomous = status(),
		})
	end
end

local function setEnabled(value)
	CONFIG.enabled = value == true
	safe("autopilot enabled", autopilot.noteEnabled, CONFIG.enabled)
	if CONFIG.enabled then
		if CONFIG.learningEnabled and brain.beginRun then safe("brain begin run", brain.beginRun, CONFIG.strategy) end
		markScanDirty(true)
		runtime.lastBuy = -math.huge
		runtime.lastCollect = -math.huge
		runtime.lastRewardSweep = -math.huge
	else
		runtime.currentTarget = nil
		runtime.currentPhase = "idle"
		safe("collector cleanup", collector.cleanup)
		safe("highlight clear", upgrades.clear)
		safe("label clear", upgrades.clearLabels)
		safe("waypoint hide", upgrades.hideWaypoint)
	end
	saveSettings()
end

local function start()
	CONFIG.autoBuy = true
	CONFIG.autoCollect = true
	CONFIG.autopilotEnabled = true
	setEnabled(true)
	return true
end
local function stop() setEnabled(false) return true end
local function resetLearning()
	local result = safe("brain reset", brain.resetPlaceProfile)
	if CONFIG.enabled and brain.beginRun then safe("brain begin run", brain.beginRun, CONFIG.strategy) end
	refreshTargets()
	refreshBrainStatus()
	return result ~= false
end
local function setStrategy(value)
	if value ~= "Fastest" and value ~= "Income" and value ~= "Rebirth" then return CONFIG.strategy end
	CONFIG.strategy = value
	refreshTargets()
	refreshBrainStatus()
	saveSettings()
	return CONFIG.strategy
end

ui.onToggle("enabled", setEnabled)
ui.onToggle("autoCollect", function(v) CONFIG.autoCollect = v saveSettings() end)
ui.onToggle("autoBuy", function(v) CONFIG.autoBuy = v saveSettings() end)
ui.onToggle("highlightAffordable", function(v) CONFIG.highlightAffordable = v saveSettings() end)
ui.onToggle("showLabels", function(v) CONFIG.showLabels = v saveSettings() end)
ui.onToggle("showWaypoint", function(v) CONFIG.showWaypoint = v saveSettings() end)
ui.onToggle("requireOwnerMatch", function(v)
	CONFIG.requireOwnerMatch = v
	if scanner.invalidateRoot then safe("owner invalidate", scanner.invalidateRoot) end
	markScanDirty(true)
	saveSettings()
end)
ui.onToggle("autopilotEnabled", function(v) CONFIG.autopilotEnabled = v refreshTargets() saveSettings() end)
ui.onToggle("learningEnabled", function(v)
	CONFIG.learningEnabled = v
	if v and CONFIG.enabled and brain.beginRun then safe("brain begin run", brain.beginRun, CONFIG.strategy) end
	refreshTargets()
	refreshBrainStatus()
	saveSettings()
end)
ui.onToggle("burstMode", function(v) CONFIG.burstMode = v saveSettings() end)
ui.onToggle("autoRewards", function(v) CONFIG.autoRewards = v saveSettings() end)
ui.onToggle("autoRebirth", function(v) CONFIG.autoRebirth = v saveSettings() end)
ui.onToggle("autoLoadGamePreset", function(v) CONFIG.autoLoadGamePreset = v saveSettings() end)
ui.onCycle("strategy", setStrategy)
ui.onCycle("buyMode", function(v) CONFIG.buyMode = v refreshTargets() saveSettings() end)
ui.onCycle("touchMode", function(v) CONFIG.touchMode = v saveSettings() end)
ui.onCycle("collectMode", function(v) CONFIG.collectMode = v saveSettings() end)
if type(ui.onAction) == "function" then
	ui.onAction("start", start)
	ui.onAction("stop", stop)
	ui.onAction("resetLearning", resetLearning)
end

local function cleanup()
	if cleanedUp then return end
	cleanedUp = true
	disconnectList(runtime.rootConnections)
	disconnectList(runtime.globalConnections)
	safe("brain save", brain.save)
	safe("collector cleanup", collector.cleanup)
	safe("upgrades destroy", upgrades.destroy)
	if ui.destroy then safe("ui destroy", ui.destroy) end
	if currency.invalidate then safe("currency invalidate", currency.invalidate) end
	if SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN == ACTIVE_TOKEN then SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN = nil end
	if SHARED_ENV.__VYRS_TYCOON_CLEANUP == cleanup then SHARED_ENV.__VYRS_TYCOON_CLEANUP = nil end
	if SHARED_ENV.__VYRS_TYCOON_DIAGNOSTICS == runtime then SHARED_ENV.__VYRS_TYCOON_DIAGNOSTICS = nil end
	if SHARED_ENV.__VYRS_TYCOON_AUTONOMOUS then SHARED_ENV.__VYRS_TYCOON_AUTONOMOUS = nil end
end

SHARED_ENV.__VYRS_TYCOON_CLEANUP = cleanup
SHARED_ENV.__VYRS_TYCOON_DIAGNOSTICS = runtime
SHARED_ENV.__VYRS_TYCOON_AUTONOMOUS = {
	start = start,
	stop = stop,
	setEnabled = setEnabled,
	setAutopilot = function(v) CONFIG.autopilotEnabled = v == true refreshTargets() saveSettings() return CONFIG.autopilotEnabled end,
	setAutoRebirth = function(v) CONFIG.autoRebirth = v == true saveSettings() return CONFIG.autoRebirth end,
	setAutoRewards = function(v) CONFIG.autoRewards = v == true saveSettings() return CONFIG.autoRewards end,
	setLearning = function(v) CONFIG.learningEnabled = v == true refreshTargets() saveSettings() return CONFIG.learningEnabled end,
	setBurst = function(v) CONFIG.burstMode = v == true saveSettings() return CONFIG.burstMode end,
	setStrategy = setStrategy,
	resetLearning = resetLearning,
	status = status,
	cleanup = cleanup,
}

table.insert(runtime.globalConnections, LOCAL_PLAYER.CharacterAdded:Connect(function()
	if scanner.invalidateRoot then safe("character invalidate", scanner.invalidateRoot) end
	if currency.invalidate then safe("currency invalidate", currency.invalidate) end
	if stats.resetBaseline then safe("stats baseline", stats.resetBaseline) end
	markScanDirty(true)
end))

local function spawnWorker(name, interval, callback)
	task.spawn(function()
		while active() do
			local ok, err = pcall(callback)
			if not ok then warn("[0xVyrs Tycoon] " .. name .. " worker failed: " .. tostring(err)) end
			task.wait(interval)
		end
	end)
end

spawnWorker("scan", 0.12, function()
	if not CONFIG.enabled or runtime.scanBusy then return end
	local now = os.clock()
	local dirtyDue = runtime.scanDirty
		and now - runtime.lastScan >= EVENT_SCAN_MIN_INTERVAL
		and ((now - runtime.scanDirtyAt >= EVENT_SCAN_DEBOUNCE) or (now - runtime.scanDirtyFirst >= EVENT_SCAN_MAX_WAIT))
	local periodicDue = now - runtime.lastScan >= CONFIG.scanInterval
	if dirtyDue or periodicDue then performScan() end
end)

spawnWorker("buy", 0.08, function()
	if not CONFIG.enabled or runtime.buyBusy or not runtime.data then return end
	local interval = CONFIG.buyInterval
	if CONFIG.autopilotEnabled and CONFIG.burstMode then interval = safe("buy interval", autopilot.getBuyInterval, runtime.data, runtime.brainStatus) or interval end
	if os.clock() - runtime.lastBuy >= interval then attemptBuy() end
end)

spawnWorker("collect", 0.12, function()
	if not CONFIG.enabled or runtime.collectBusy or not runtime.data then return end
	local interval = CONFIG.collectInterval
	if CONFIG.autopilotEnabled then interval = safe("collect interval", autopilot.getCollectInterval, runtime.data, runtime.brainStatus) or interval end
	if os.clock() - runtime.lastCollect >= interval then attemptCollect() end
end)

spawnWorker("render", 0.18, function()
	if not CONFIG.enabled then return end
	if os.clock() - runtime.lastRender >= CONFIG.renderInterval then runtime.lastRender = os.clock() renderNow() end
end)

spawnWorker("stats", 0.22, function()
	if not CONFIG.enabled then return end
	local now = os.clock()
	if now - runtime.lastStats >= CONFIG.statsInterval then
		runtime.lastStats = now
		safe("stats update", stats.update)
		if CONFIG.learningEnabled and brain.observeEconomy then safe("brain economy", brain.observeEconomy, getCash(), statsState()) end
		refreshBrainStatus()
	end
end)

spawnWorker("rewards", 0.5, function()
	if not CONFIG.enabled or not CONFIG.autoRewards or runtime.rewardBusy or not runtime.data then return end
	if os.clock() - runtime.lastRewardSweep < 2.5 then return end
	runtime.lastRewardSweep = os.clock()
	runtime.rewardBusy = true
	local activated = safe("free rewards", boosts.sweep, runtime.data) or 0
	runtime.rewardsActivated = runtime.rewardsActivated + activated
	runtime.rewardBusy = false
end)

spawnWorker("completion", 0.5, function()
	if not CONFIG.enabled or not runtime.data then return end
	local complete = safe("completion", autopilot.updateCompletion, brain, runtime.data) == true
	if complete then
		safe("record completion", autopilot.recordCompletion, brain)
		refreshBrainStatus()
		if CONFIG.autoRebirth and not runtime.rebirthBusy then
			runtime.rebirthBusy = true
			task.spawn(function()
				local success = safe("auto rebirth", autopilot.tryRebirth, runtime.data)
				if success then
					if scanner.invalidateRoot then safe("rebirth invalidate", scanner.invalidateRoot) end
					if currency.invalidate then safe("rebirth currency invalidate", currency.invalidate) end
					if stats.resetBaseline then safe("rebirth stats baseline", stats.resetBaseline) end
					if CONFIG.learningEnabled and brain.beginRun then safe("brain begin run", brain.beginRun, CONFIG.strategy) end
					markScanDirty(true)
				end
				runtime.rebirthBusy = false
			end)
		end
	end
end)

spawnWorker("autosave", 15, function()
	saveSettings()
	if CONFIG.learningEnabled then safe("brain autosave", brain.save) end
end)

renderNow()
print("[0xVyrs Tycoon] v1.0.0 core rebuild loaded. Use the dashboard START button to begin.")
