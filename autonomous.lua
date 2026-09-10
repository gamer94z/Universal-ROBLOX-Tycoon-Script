--[[
	Copyright (c) 2026 gamer94z / 0xVyrs
	All Rights Reserved.

	0xVyrs Tycoon Autonomous Runtime v1.0.0
	Adaptive progression, ROI learning, rewards and recovery.
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
if type(previousCleanup) == "function" then pcall(previousCleanup) end

local ACTIVE_TOKEN = "autonomous:" .. tostring(os.clock())
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
	scanInterval = 10,
	renderInterval = 1.2,
	uiInterval = 0.65,
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
	autoRewards = true,
	autoRebirth = false,
	strategy = "Fastest",

	moduleBaseUrl = tostring(SHARED_ENV.__VYRS_TYCOON_MODULE_BASE_URL
		or "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/main/tycoon_modules"),
}

local SETTINGS_FILE = "tycoon_settings.json"
local MODULE_NAMES = { "scanner", "ui", "collector", "upgrades", "stats", "brain", "autopilot", "boosts" }

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
	if CONFIG.strategy ~= "Fastest" and CONFIG.strategy ~= "Income" and CONFIG.strategy ~= "Rebirth" then
		CONFIG.strategy = "Fastest"
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
		if key ~= "version" and key ~= "moduleBaseUrl" then payload.placeConfigs[tostring(game.PlaceId)][key] = value end
	end
	pcall(function() writefile(SETTINGS_FILE, HttpService:JSONEncode(payload)) end)
end

local function getLocalRoot()
	local character = LOCAL_PLAYER.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local CASH_HINTS = { "cash", "money", "coin", "balance", "credit", "fund", "currency", "gold" }
local CASH_EXACT = { cash=true, money=true, coins=true, balance=true, credits=true, funds=true, currency=true, gold=true }
local cashObjectCache
local lastCashSearch = -math.huge

local function cashNameScore(item)
	if not item then return -math.huge end
	local name = tostring(item.Name or ""):lower():gsub("[^%w]", "")
	local score = CASH_EXACT[name] and 100 or 0
	for _, hint in ipairs(CASH_HINTS) do if name:find(hint, 1, true) then score = math.max(score, 65) end end
	if score == 0 then return -math.huge end
	local parentName = item.Parent and tostring(item.Parent.Name or ""):lower() or ""
	if parentName == "leaderstats" then score = score + 40 end
	if parentName:find("data",1,true) or parentName:find("stat",1,true) or parentName:find("profile",1,true)
		or parentName:find("wallet",1,true) or parentName:find("currency",1,true) then score = score + 18 end
	return score
end

local function getCashObject()
	if cashObjectCache and cashObjectCache.Parent and tonumber(cashObjectCache.Value) ~= nil then return cashObjectCache end
	cashObjectCache = nil
	local now = os.clock()
	if now - lastCashSearch < 4 then return nil end
	lastCashSearch = now

	local best, bestScore
	local leaderstats = LOCAL_PLAYER:FindFirstChild("leaderstats")
	if leaderstats then
		for _, item in ipairs(leaderstats:GetChildren()) do
			if item:IsA("IntValue") or item:IsA("NumberValue") or item:IsA("StringValue") then
				if tonumber(item.Value) ~= nil then
					local score = cashNameScore(item)
					if score > -math.huge and (not bestScore or score > bestScore) then best, bestScore = item, score end
				end
			end
		end
	end
	if not best or (bestScore or 0) < 100 then
		for _, item in ipairs(LOCAL_PLAYER:GetDescendants()) do
			if item:IsA("IntValue") or item:IsA("NumberValue") or item:IsA("StringValue") then
				if tonumber(item.Value) ~= nil then
					local score = cashNameScore(item)
					if score > -math.huge and (not bestScore or score > bestScore) then best, bestScore = item, score end
				end
			end
		end
	end
	cashObjectCache = best
	return best
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

local function remoteModule(fileName)
	if type(game.HttpGet) ~= "function" then return nil end
	local ok, result = pcall(function()
		return game:HttpGet(CONFIG.moduleBaseUrl:gsub("/+$", "") .. "/" .. fileName)
	end)
	return ok and type(result) == "string" and result ~= "" and result or nil
end

local function localModule(fileName)
	if type(readfile) ~= "function" then return nil end
	for _, path in ipairs({
		"Tycoon/tycoon_modules/" .. fileName,
		"Tycoon\\tycoon_modules\\" .. fileName,
		"tycoon_modules/" .. fileName,
		"tycoon_modules\\" .. fileName,
	}) do
		local ok, result = pcall(function() return readfile(path) end)
		if ok and type(result) == "string" and result ~= "" then return result end
	end
	return nil
end

local function requireModule(name)
	if type(loadstring) ~= "function" then return nil end
	local fileName = name .. ".lua"
	local preferLocal = SHARED_ENV.__VYRS_TYCOON_USE_LOCAL_MODULES == true
	local source = preferLocal and localModule(fileName) or remoteModule(fileName)
	if not source then source = preferLocal and remoteModule(fileName) or localModule(fileName) end
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
local boosts = init(factories.boosts)
local ui = safe("ui init", factories.ui, context)
local stats = safe("stats init", factories.stats, context)

if type(scanner) ~= "table" or type(collector) ~= "table" or type(upgrades) ~= "table"
	or type(brain) ~= "table" or type(autopilot) ~= "table" or type(boosts) ~= "table"
	or type(ui) ~= "table" or type(stats) ~= "table" then
	error("[0xVyrs Tycoon] Autonomous module init failed")
end

local runtime = {
	data=nil, nearest=nil, cheapest=nil, bestValue=nil, nextLocked=nil, plannedTarget=nil, planScore=nil, brainStatus=nil,
	lastScan=-math.huge, lastRender=-math.huge, lastUi=-math.huge, lastStats=-math.huge, lastBuy=-math.huge,
	lastCollect=-math.huge, lastRewardSweep=-math.huge, lastCashConnect=-math.huge,
	bought=0, collected=0, rewardsActivated=0, purchaseAttempts=0, purchaseFailures=0, scanCount=0,
	scanDirty=true, scanDirtyAt=0, buyBusy=false, collectBusy=false, rewardBusy=false, scanBusy=false, wasEnabled=false,
	watchedRoot=nil, rootConnections={}, globalConnections={}, cashConnection=nil, cashObject=nil,
}

local EVENT_SCAN_DEBOUNCE = 0.45
local EVENT_SCAN_MIN_INTERVAL = 1.0
local heartbeatConnection
local cleanedUp = false

local function active()
	return not cleanedUp and SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN == ACTIVE_TOKEN
end

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
	return name:find("button",1,true) or name:find("purchase",1,true) or name:find("buy",1,true)
		or name:find("price",1,true) or name:find("cost",1,true) or name:find("owner",1,true)
		or name:find("drop",1,true) or name:find("collect",1,true)
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
	local affordable, locked = 0, 0
	for _, button in ipairs(runtime.data.buttons or {}) do
		if not button.paidPurchase then
			local price = tonumber(button.price)
			if price then
				button.affordable = price <= cash
				button.locked = price > cash
				if button.affordable then affordable = affordable + 1 elseif button.locked then locked = locked + 1 end
			end
		end
	runtime.data.affordableCount = affordable
	runtime.data.lockedCount = locked
end

local function refreshBrainStatus()
	if CONFIG.learningEnabled then runtime.brainStatus = safe("brain status", brain.getStatus, runtime.data, statsState())
	else runtime.brainStatus = nil end
	return runtime.brainStatus
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
end

local function performScan(now)
	if runtime.scanBusy then return end
	runtime.scanBusy = true
	runtime.scanDirty = false
	runtime.lastScan = now
	local scanned = safe("scan", scanner.scan, context)
	if scanned then
		runtime.data = scanned
		local mode = scanned.debug and scanned.debug.scanMode
		local meaningful = mode ~= "cached-throttle"
		if meaningful then
			runtime.scanCount = runtime.scanCount + 1
			watchRoot(scanned.root)
			if CONFIG.learningEnabled then safe("brain observe", brain.observe, scanned, statsState()) end
			safe("recovery", autopilot.updateRecovery, scanned)
		end
	end
	refreshTargets()
	refreshBrainStatus()
	runtime.scanBusy = false
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
		connectCashWatch()
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

local function stop()
	setEnabled(false)
	return true
end

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

local function status()
	local brainState = runtime.brainStatus or refreshBrainStatus()
	return {
		version=CONFIG.version, enabled=CONFIG.enabled, autopilotEnabled=CONFIG.autopilotEnabled,
		learningEnabled=CONFIG.learningEnabled, burstMode=CONFIG.burstMode, autoRewards=CONFIG.autoRewards,
		autoRebirth=CONFIG.autoRebirth, strategy=CONFIG.strategy, bought=runtime.bought, collected=runtime.collected,
		rewardsActivated=runtime.rewardsActivated, purchaseAttempts=runtime.purchaseAttempts,
		purchaseFailures=runtime.purchaseFailures, scanCount=runtime.scanCount,
		root=runtime.data and runtime.data.rootName or nil, ownerVerified=runtime.data and runtime.data.ownerVerified or false,
		buttons=runtime.data and runtime.data.totalButtons or 0, cash=runtime.data and runtime.data.cash or getCash(),
		brain=brainState, autopilot=safe("autopilot status", autopilot.getStatus), boosts=safe("boost status", boosts.getStatus),
	}
end

local function cleanup()
	if cleanedUp then return end
	cleanedUp = true
	if heartbeatConnection then pcall(function() heartbeatConnection:Disconnect() end) end
	if runtime.cashConnection then pcall(function() runtime.cashConnection:Disconnect() end) end
	disconnectRootWatch()
	disconnectList(runtime.globalConnections)
	safe("brain save", brain.save)
	safe("highlight clear", upgrades.clear)
	safe("label clear", upgrades.clearLabels)
	safe("waypoint hide", upgrades.hideWaypoint)
	if upgrades.destroy then safe("upgrades destroy", upgrades.destroy) end
	if ui.destroy then safe("ui destroy", ui.destroy) end
	if SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN == ACTIVE_TOKEN then SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN = nil end
	if SHARED_ENV.__VYRS_TYCOON_CLEANUP == cleanup then SHARED_ENV.__VYRS_TYCOON_CLEANUP = nil end
	if SHARED_ENV.__VYRS_TYCOON_DIAGNOSTICS == runtime then SHARED_ENV.__VYRS_TYCOON_DIAGNOSTICS = nil end
	if SHARED_ENV.__VYRS_TYCOON_AUTONOMOUS then SHARED_ENV.__VYRS_TYCOON_AUTONOMOUS = nil end
end

SHARED_ENV.__VYRS_TYCOON_CLEANUP = cleanup
SHARED_ENV.__VYRS_TYCOON_DIAGNOSTICS = runtime
SHARED_ENV.__VYRS_TYCOON_AUTONOMOUS = {
	start=start, stop=stop, setEnabled=setEnabled,
	setAutopilot=function(v) CONFIG.autopilotEnabled=v==true refreshTargets() saveSettings() return CONFIG.autopilotEnabled end,
	setAutoRebirth=function(v) CONFIG.autoRebirth=v==true saveSettings() return CONFIG.autoRebirth end,
	setAutoRewards=function(v) CONFIG.autoRewards=v==true saveSettings() return CONFIG.autoRewards end,
	setLearning=function(v) CONFIG.learningEnabled=v==true refreshTargets() saveSettings() return CONFIG.learningEnabled end,
	setBurst=function(v) CONFIG.burstMode=v==true saveSettings() return CONFIG.burstMode end,
	setStrategy=setStrategy, resetLearning=resetLearning, status=status, cleanup=cleanup,
}

table.insert(runtime.globalConnections, LOCAL_PLAYER.CharacterAdded:Connect(function()
	if scanner.invalidateRoot then safe("character invalidate", scanner.invalidateRoot) end
	markScanDirty(true)
	connectCashWatch()
end))

table.insert(runtime.globalConnections, LOCAL_PLAYER.DescendantAdded:Connect(function(instance)
	if instance:IsA("IntValue") or instance:IsA("NumberValue") or instance:IsA("StringValue") then
		if cashNameScore(instance) > -math.huge then lastCashSearch=-math.huge; if not runtime.cashObject then connectCashWatch() end end
	end
end))

connectCashWatch()
safe("autopilot enabled", autopilot.noteEnabled, CONFIG.enabled)

heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
	if not active() then cleanup() return end
	local now = os.clock()

	if not runtime.cashConnection and now - runtime.lastCashConnect >= 4 then
		runtime.lastCashConnect = now
		connectCashWatch()
	end

	if CONFIG.enabled and now - runtime.lastStats >= CONFIG.statsInterval then
		runtime.lastStats = now
		safe("stats update", stats.update, deltaTime)
		if CONFIG.learningEnabled and brain.observeEconomy then
			safe("brain economy", brain.observeEconomy, getCash(), statsState())
			runtime.brainStatus = safe("brain status", brain.getStatus, runtime.data, statsState())
		end
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

		local complete = safe("completion", autopilot.updateCompletion, brain, runtime.data) == true
		if complete then
			safe("record completion", autopilot.recordCompletion, brain)
			refreshBrainStatus()
			if CONFIG.autoRebirth and not runtime.buyBusy and safe("auto rebirth", autopilot.tryRebirth, runtime.data) then
				if scanner.invalidateRoot then safe("rebirth invalidate", scanner.invalidateRoot) end
				if CONFIG.learningEnabled and brain.beginRun then safe("brain begin run", brain.beginRun, CONFIG.strategy) end
				markScanDirty(true)
			end
		end

		if CONFIG.autoRewards and not runtime.rewardBusy and now - runtime.lastRewardSweep >= 5 then
			runtime.lastRewardSweep = now
			runtime.rewardBusy = true
			local activated = safe("free rewards", boosts.sweep, runtime.data) or 0
			runtime.rewardsActivated = runtime.rewardsActivated + activated
			runtime.rewardBusy = false
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

		local brainState = runtime.brainStatus
		local buyInterval = CONFIG.buyInterval
		if CONFIG.autopilotEnabled and CONFIG.burstMode then buyInterval = safe("buy interval", autopilot.getBuyInterval, runtime.data, brainState) or buyInterval end
		if CONFIG.autoBuy and runtime.data.automationAllowed and not complete and not runtime.buyBusy and now - runtime.lastBuy >= buyInterval then
			runtime.lastBuy = now
			runtime.buyBusy = true
			refreshTargets()
			local target = runtime.plannedTarget
			if target then
				runtime.purchaseAttempts = runtime.purchaseAttempts + 1
				if safe("buy", collector.buyButton, context, target) == true then
					runtime.bought = runtime.bought + 1
					if stats.noteSpend then safe("record spend", stats.noteSpend, target.price) end
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
		if CONFIG.autopilotEnabled then collectInterval = safe("collect interval", autopilot.getCollectInterval, runtime.data, brainState) or collectInterval end
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
		refreshBrainStatus()
		safe("ui update", ui.update, {
			data=runtime.data, nearest=runtime.plannedTarget or runtime.nearest, cheapest=runtime.cheapest,
			bestValue=runtime.bestValue, nextLocked=runtime.nextLocked, stats=statsState(), collected=runtime.collected,
			bought=runtime.bought, autonomous=status(),
		})
	end
end)

local spawn = task and task.spawn or coroutine.wrap
spawn(function()
	while active() do
		if task and task.wait then task.wait(20) else wait(20) end
		if active() then saveSettings(); if CONFIG.learningEnabled then safe("brain autosave", brain.save) end end
	end
end)

print("[0xVyrs Tycoon] v1.0.0 loaded. Use the dashboard START button to begin.")