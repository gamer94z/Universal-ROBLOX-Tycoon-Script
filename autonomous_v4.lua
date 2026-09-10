--[[
    0xVyrs Tycoon Autonomous Runtime v4.1
    Canonical audited runtime: one module path, one target authority,
    structured purchase outcomes, live-cash gating and isolated workers.
]]

local Players=game:GetService("Players")
local CoreGui=game:GetService("CoreGui")
local HttpService=game:GetService("HttpService")
local LOCAL_PLAYER=Players.LocalPlayer
local ENV=(type(getgenv)=="function" and getgenv()) or (type(getfenv)=="function" and getfenv(0)) or _G

local RUNTIME_VERSION="4.1-audit2"
local MODULE_MANIFEST={scanner="v4.1",currency="strict-canonical",collector="v4.1",brain="planner-canonical",stats="v4.1"}

local previousCleanup=ENV.__VYRS_TYCOON_CLEANUP
if type(previousCleanup)=="function" then pcall(previousCleanup) end

local TOKEN="core-v4.1:"..tostring(os.clock())
ENV.__VYRS_TYCOON_ACTIVE_TOKEN=TOKEN

local CONFIG={
    version="1.0.0",
    enabled=false,
    autoCollect=true,
    autoBuy=true,
    autoLoadGamePreset=true,
    highlightAffordable=true,
    showLabels=false,
    showWaypoint=true,
    requireOwnerMatch=true,
    touchMode="Virtual",
    buyMode="Nearest",
    collectMode="Nearby",
    collectRange=90,
    scanInterval=6,
    renderInterval=0.45,
    uiInterval=0.65,
    statsInterval=0.9,
    collectInterval=0.6,
    buyInterval=0.35,
    maxButtons=80,
    maxDrops=60,
    maxLabels=12,
    uiOffsetX=24,
    uiOffsetY=180,
    autopilotEnabled=true,
    learningEnabled=true,
    burstMode=true,
    autoRewards=true,
    autoRebirth=false,
    strategy="Fastest",
    moduleBaseUrl=tostring(ENV.__VYRS_TYCOON_MODULE_BASE_URL or
        "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/v1.0-core-v4/tycoon_modules"),
}

local SETTINGS_FILE="tycoon_settings.json"
local cleaned=false

local function active()
    return not cleaned and ENV.__VYRS_TYCOON_ACTIVE_TOKEN==TOKEN
end

local function safe(label,fn,...)
    if type(fn)~="function" then return nil end
    local ok,a,b,c=pcall(fn,...)
    if not ok then
        warn("[0xVyrs Tycoon v4.1] "..label.." failed: "..tostring(a))
        return nil
    end
    return a,b,c
end

local function canFile()
    return type(isfile)=="function" and type(readfile)=="function" and type(writefile)=="function"
end

local function loadSettings()
    if not canFile() or not isfile(SETTINGS_FILE) then return end
    local ok,decoded=pcall(function() return HttpService:JSONDecode(readfile(SETTINGS_FILE)) end)
    if not ok or type(decoded)~="table" then return end
    local source=decoded
    if decoded.placeConfigs and decoded.placeConfigs[tostring(game.PlaceId)] and decoded.autoLoadGamePreset~=false then
        source=decoded.placeConfigs[tostring(game.PlaceId)]
    end
    for key,value in pairs(source) do
        if CONFIG[key]~=nil and key~="version" and key~="enabled" and key~="moduleBaseUrl" then
            CONFIG[key]=value
        end
    end
    if CONFIG.strategy~="Fastest" and CONFIG.strategy~="Income" and CONFIG.strategy~="Rebirth" then
        CONFIG.strategy="Fastest"
    end
    CONFIG.enabled=false
end

local function saveSettings()
    if not canFile() then return end
    local payload={}
    if isfile(SETTINGS_FILE) then
        pcall(function()
            local decoded=HttpService:JSONDecode(readfile(SETTINGS_FILE))
            if type(decoded)=="table" then payload=decoded end
        end)
    end
    for key,value in pairs(CONFIG) do
        if key~="version" and key~="moduleBaseUrl" then payload[key]=value end
    end
    payload.placeConfigs=payload.placeConfigs or {}
    payload.placeConfigs[tostring(game.PlaceId)]={}
    for key,value in pairs(CONFIG) do
        if key~="version" and key~="moduleBaseUrl" then
            payload.placeConfigs[tostring(game.PlaceId)][key]=value
        end
    end
    pcall(function() writefile(SETTINGS_FILE,HttpService:JSONEncode(payload)) end)
end

local function getRoot()
    local character=LOCAL_PLAYER.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function fetchSource(name)
    local file=name..".lua"
    if ENV.__VYRS_TYCOON_USE_LOCAL_MODULES==true and type(readfile)=="function" then
        for _,path in ipairs({"Tycoon/tycoon_modules/"..file,"tycoon_modules/"..file}) do
            local ok,result=pcall(function() return readfile(path) end)
            if ok and type(result)=="string" and result~="" then return result,"local:"..path end
        end
    end
    local url=CONFIG.moduleBaseUrl:gsub("/+$","").."/"..file
    local ok,result=pcall(function() return game:HttpGet(url) end)
    if ok and type(result)=="string" and result~="" then return result,"remote" end
    error("missing canonical module "..name..": "..tostring(result))
end

local function loadFactory(name)
    local source,origin=fetchSource(name)
    local chunk,compileError=loadstring(source)
    if type(chunk)~="function" then error(name.." compile failed: "..tostring(compileError)) end
    local ok,result=pcall(chunk)
    if not ok then error(name.." load failed: "..tostring(result)) end
    return result,origin
end

local function init(name,context)
    local factory,origin=loadFactory(name)
    if type(factory)~="function" then error(name.." did not return a factory") end
    local ok,result=pcall(factory,context)
    if not ok or type(result)~="table" then error(name.." init failed: "..tostring(result)) end
    return result,origin
end

loadSettings()
local oldGui=CoreGui:FindFirstChild("TycoonCoreGUI")
if oldGui then oldGui:Destroy() end

local currency=nil
local function legacyCash()
    local leaderstats=LOCAL_PLAYER:FindFirstChild("leaderstats")
    if not leaderstats then return nil end
    for _,name in ipairs({"Cash","Money","Coins","Balance"}) do
        local object=leaderstats:FindFirstChild(name)
        if object and tonumber(object.Value)~=nil then return tonumber(object.Value) end
    end
    return nil
end

local function getCash()
    if currency and type(currency.get)=="function" then
        local value=safe("currency.get",currency.get)
        if tonumber(value)~=nil then return tonumber(value) end
    end
    return legacyCash()
end

local function getCashSourceKey()
    if currency and type(currency.status)=="function" then
        local status=safe("currency.status",currency.status)
        if type(status)=="table" then return status.path or status.source end
    end
    return nil
end

local context={
    Players=Players,
    CoreGui=CoreGui,
    HttpService=HttpService,
    LOCAL_PLAYER=LOCAL_PLAYER,
    CONFIG=CONFIG,
    SHARED_ENV=ENV,
    saveSettings=saveSettings,
    getLocalRoot=getRoot,
    getCash=getCash,
    getCashSourceKey=getCashSourceKey,
}

local moduleOrigins={}
currency,moduleOrigins.currency=init("currency",context)
ENV.__VYRS_TYCOON_GET_CASH=getCash
ENV.__VYRS_TYCOON_CURRENCY_MARK=currency.mark
ENV.__VYRS_TYCOON_CURRENCY_STATUS=currency.status

local scanner; scanner,moduleOrigins.scanner=init("scanner",context)
local collector; collector,moduleOrigins.collector=init("collector",context)
local brain; brain,moduleOrigins.brain=init("brain",context)
local ui; ui,moduleOrigins.ui=init("ui",context)
local upgrades; upgrades,moduleOrigins.upgrades=init("upgrades",context)
local stats; stats,moduleOrigins.stats=init("stats",context)
local autopilot; autopilot,moduleOrigins.autopilot=init("autopilot",context)
local boosts; boosts,moduleOrigins.boosts=init("boosts",context)

local S={
    data=nil,
    target=nil,
    targetScore=nil,
    targetSignature=nil,
    targetPhase="idle",
    bought=0,
    collected=0,
    rewardsActivated=0,
    purchaseDispatches=0,
    purchaseFailures=0,
    deferredPurchases=0,
    blockedPurchases=0,
    scanCount=0,
    scanRequested=true,
    scanDueAt=0,
    scanReason="startup",
    scanBusy=false,
    buyBusy=false,
    collectBusy=false,
    rewardBusy=false,
    rebirthBusy=false,
    lastScan=-math.huge,
    lastBuy=-math.huge,
    lastCollect=-math.huge,
    lastRender=-math.huge,
    lastUi=-math.huge,
    lastStats=-math.huge,
    lastReward=-math.huge,
    buyGate="initialising",
    lastOutcome=nil,
    rootConnections={},
    connections={},
    purchaseStates=setmetatable({}, {__mode="k"}),
    brainStatus=nil,
    collectorStatus=nil,
    currencyStatus=nil,
}

local function disconnectAll(list)
    for _,connection in ipairs(list) do pcall(function() connection:Disconnect() end) end
    table.clear(list)
end

local function requestScan(delay,reason)
    local due=os.clock()+math.max(0,tonumber(delay) or 0)
    if not S.scanRequested or due<S.scanDueAt then S.scanDueAt=due end
    S.scanRequested=true
    S.scanReason=reason or S.scanReason
end

local function activationKey(button)
    return button and (button.activation or button.prompt or button.clickDetector or button.touchPart or button.object) or nil
end

local function buttonSignature(button)
    local key=activationKey(button)
    local keyName=key and (key.ClassName..":"..key.Name) or "none"
    return tostring(button and button.name or "").."|"..tostring(tonumber(button and button.price) or 0).."|"..keyName
end

local function stateFor(button)
    local key=activationKey(button)
    if not key then return nil end
    local signature=buttonSignature(button)
    local state=S.purchaseStates[key]
    if not state or state.signature~=signature then
        state={signature=signature,failures=0,blockedUntil=nil,lastReason=nil,lastEvidence=nil,learned=false,phase="ready"}
        S.purchaseStates[key]=state
    end
    if state.blockedUntil and state.blockedUntil<=os.clock() then
        state.blockedUntil=nil
        state.phase="ready"
        state.lastEvidence=nil
    end
    return state
end

local function validButton(button)
    if not button or button.paidPurchase==true then return false end
    if not button.object or not button.object.Parent then return false end
    local key=activationKey(button)
    if not key or not key.Parent then return false end
    if not button.part or not button.part.Parent then return false end
    return true
end

local function normalise(data)
    if not data then return nil end
    data.showLabels=CONFIG.showLabels
    data.maxLabels=CONFIG.maxLabels
    data.automationAllowed=(data.ownerVerified==true) or CONFIG.requireOwnerMatch==false
    data.safeAutomation=data.automationAllowed

    -- Live currency is authoritative. Never retain an old scan's balance when
    -- the resolver becomes unknown or loses identity verification.
    local cash=tonumber(getCash())
    data.cash=cash

    for index=#(data.buttons or {}),1,-1 do
        local button=data.buttons[index]
        if not validButton(button) then
            table.remove(data.buttons,index)
            requestScan(0.12,"dead-button")
        else
            button.automationAllowed=data.automationAllowed
            local state=stateFor(button)
            button.failureCount=state and state.failures or 0
            button.blockedUntil=state and state.blockedUntil or nil
            button.approaching=state and state.phase=="approaching" or false
            local price=tonumber(button.price)
            if price~=nil then
                button.affordable=(price==0) or (cash~=nil and price<=cash)
                button.locked=cash~=nil and price>cash or false
            else
                button.affordable=false
                button.locked=false
            end
        end
    end

    for index=#(data.drops or {}),1,-1 do
        local drop=data.drops[index]
        if not drop or not drop.object or not drop.object.Parent then
            table.remove(data.drops,index)
        else
            drop.automationAllowed=data.automationAllowed
        end
    end

    local affordable,locked=0,0
    for _,button in ipairs(data.buttons or {}) do
        if button.affordable and not button.paidPurchase then affordable=affordable+1
        elseif button.locked and not button.paidPurchase then locked=locked+1 end
    end
    data.totalButtons=#(data.buttons or {})
    data.affordableCount=affordable
    data.lockedCount=locked
    return data
end

local function statsState()
    return safe("stats.get",stats.get) or {}
end

local function actionable(button)
    if not validButton(button) or button.automationAllowed~=true or button.affordable~=true then return false end
    local state=stateFor(button)
    if state and state.blockedUntil and state.blockedUntil>os.clock() then return false end
    return true
end

local function distanceTo(button)
    local root=getRoot()
    return root and button and button.part and (button.part.Position-root.Position).Magnitude or math.huge
end

local function directMetric(button)
    if CONFIG.buyMode=="Cheapest" then return tonumber(button.price) or math.huge end
    if CONFIG.buyMode=="Value" then return -(tonumber(button.price) or 0) end
    return distanceTo(button)
end

local function chooseTarget()
    if not S.data then S.buyGate="no-data" return nil,nil end
    normalise(S.data)
    if S.data.automationAllowed~=true then S.buyGate="owner-blocked" return nil,nil end

    local candidates={}
    local hasPriced=false
    for _,button in ipairs(S.data.buttons or {}) do
        if tonumber(button.price) and tonumber(button.price)>0 then hasPriced=true end
        if actionable(button) then table.insert(candidates,button) end
    end

    if tonumber(S.data.cash)==nil then
        local free={}
        for _,button in ipairs(candidates) do
            if (tonumber(button.price) or 0)==0 then table.insert(free,button) end
        end
        candidates=free
        if #candidates==0 and hasPriced then
            S.buyGate="cash-unresolved"
            return nil,nil
        end
    end

    if #candidates==0 then
        local hasAffordable=false
        for _,button in ipairs(S.data.buttons or {}) do
            if button.affordable and not button.paidPurchase then hasAffordable=true break end
        end
        S.buyGate=hasAffordable and "all-on-cooldown" or "no-affordable"
        return nil,nil
    end

    if CONFIG.autopilotEnabled and CONFIG.learningEnabled then
        local target,score=safe("brain.choosePurchase",brain.choosePurchase,S.data)
        if actionable(target) and type(score)=="number" and score==score and score~=math.huge and score~=-math.huge then
            S.buyGate="ready"
            return target,score
        end
    end

    local best,bestMetric=nil,nil
    for _,button in ipairs(candidates) do
        local metric=directMetric(button)
        if bestMetric==nil or metric<bestMetric then best,bestMetric=button,metric end
    end
    S.buyGate=best and "ready" or "candidate-filtered"
    return best,nil
end

local function refreshBrain()
    if CONFIG.learningEnabled then S.brainStatus=safe("brain.getStatus",brain.getStatus,S.data,statsState())
    else S.brainStatus=nil end
    return S.brainStatus
end

local function refreshTarget(force)
    normalise(S.data)
    if S.target and (not validButton(S.target) or buttonSignature(S.target)~=S.targetSignature) then
        S.target=nil
        S.targetSignature=nil
        S.targetPhase="idle"
    end

    if force or not S.target or not actionable(S.target) then
        local chosen,score=chooseTarget()
        if chosen then
            S.target=chosen
            S.targetScore=score
            S.targetSignature=buttonSignature(chosen)
            local state=stateFor(chosen)
            S.targetPhase=state and state.phase or "ready"
        elseif not S.buyBusy and not (S.target and validButton(S.target)) then
            S.target=nil
            S.targetSignature=nil
            S.targetPhase="idle"
        end
    end
    return S.target,S.targetScore
end

local function structural(object)
    if not object then return false end
    if object:IsA("TouchTransmitter") or object:IsA("ProximityPrompt") or object:IsA("ClickDetector") then return true end
    local name=tostring(object.Name):lower()
    return name:find("button",1,true) or name:find("purchase",1,true) or name:find("buy",1,true)
        or name:find("price",1,true) or name:find("cost",1,true) or name:find("collect",1,true)
end

local function watchRoot(root)
    disconnectAll(S.rootConnections)
    if not root or root==workspace or not root.Parent then return end
    table.insert(S.rootConnections,root.DescendantAdded:Connect(function(object)
        if structural(object) then requestScan(0.12,"descendant-added") end
    end))
    table.insert(S.rootConnections,root.DescendantRemoving:Connect(function(object)
        if structural(object) then requestScan(0.12,"descendant-removing") end
    end))
    table.insert(S.rootConnections,root.AncestryChanged:Connect(function(_,parent)
        if not parent then
            safe("scanner.invalidateRoot",scanner.invalidateRoot,root)
            requestScan(0,"root-lost")
        end
    end))
end

local function scanNow()
    if S.scanBusy or not active() then return end
    S.scanBusy=true
    local previousRoot=S.data and S.data.root
    local started=os.clock()
    local ok,result=pcall(scanner.scan)
    if ok and result then
        S.data=normalise(result)
        S.scanCount=S.scanCount+1
        S.lastScan=os.clock()
        S.scanRequested=false
        S.data.runtimeScanMs=(os.clock()-started)*1000
        if previousRoot~=S.data.root then watchRoot(S.data.root) end
        if CONFIG.learningEnabled then safe("brain.observe",brain.observe,S.data,statsState()) end
        safe("autopilot.updateRecovery",autopilot.updateRecovery,S.data)
        refreshTarget(true)
        refreshBrain()
    else
        if not ok then warn("[0xVyrs Tycoon v4.1] scanner failed: "..tostring(result)) end
        S.scanRequested=false
        requestScan(1.0,"scanner-retry")
    end
    S.scanBusy=false
end

local function cooldownFor(outcome,state)
    local reason=outcome and outcome.reason or "unknown"
    if outcome and outcome.status=="deferred" then
        if reason=="player-moving" then return 0.25 end
        if reason=="cash-unresolved" or reason=="character-unavailable" then return 0.45 end
        if reason=="too-far" or reason=="autopilot-disabled" then return 0.9 end
        return 0.55
    end
    if outcome and outcome.status=="blocked" then return 30 end
    local failures=state and state.failures or 1
    return math.min(2.0,0.5+failures*0.24)
end

local function dispatchBuy()
    if S.buyBusy then S.buyGate="busy" return end
    if not CONFIG.enabled then S.buyGate="disabled" return end
    if not CONFIG.autoBuy then S.buyGate="auto-buy-off" return end
    if not S.data then S.buyGate="no-data" S.lastBuy=os.clock() return end

    normalise(S.data)
    local target=refreshTarget(false)
    if not target or not actionable(target) then
        -- Advancing this timestamp prevents a 60 ms hot-loop while everything
        -- is on cooldown or waiting for cash.
        S.lastBuy=os.clock()
        return
    end

    local state=stateFor(target)
    S.buyBusy=true
    S.buyGate="dispatching"
    S.targetPhase="dispatching"
    if state then state.phase="dispatching" end
    target.approaching=true
    S.purchaseDispatches=S.purchaseDispatches+1

    local ok,success,outcome=pcall(collector.buyButton,context,target)
    if not ok then
        local dispatchError=success
        success=false
        outcome={status="failed",reason="collector-error",attempted=false,error=tostring(dispatchError)}
        warn("[0xVyrs Tycoon v4.1] collector dispatch failed: "..tostring(dispatchError))
    end
    if type(outcome)~="table" then
        outcome={status=success and "success" or "failed",reason=success and "confirmed" or "unknown",attempted=true}
    end

    S.lastOutcome=outcome
    target.approaching=false

    if success==true or outcome.status=="success" then
        S.bought=S.bought+1
        S.buyGate="confirmed"
        S.targetPhase="confirmed"
        if stats.noteSpend then safe("stats.noteSpend",stats.noteSpend,target.price) end
        if CONFIG.learningEnabled then safe("brain.notePurchase",brain.notePurchase,target,S.data,statsState()) end
        local key=activationKey(target)
        if key then S.purchaseStates[key]=nil end
        requestScan(0.08,"purchase-confirmed")
        task.delay(0.4,function()
            if active() and CONFIG.enabled then requestScan(0,"purchase-followup") end
        end)
    elseif outcome.status=="deferred" then
        S.deferredPurchases=S.deferredPurchases+1
        S.buyGate="deferred:"..tostring(outcome.reason)
        S.targetPhase=outcome.reason or "deferred"
        if state then
            state.lastReason=outcome.reason
            state.phase="deferred"
            state.blockedUntil=os.clock()+cooldownFor(outcome,state)
        end
    elseif outcome.status=="blocked" then
        S.blockedPurchases=S.blockedPurchases+1
        S.buyGate="safety-blocked:"..tostring(outcome.reason)
        S.targetPhase="blocked"
        if state then
            state.lastReason=outcome.reason
            state.lastEvidence=outcome.evidence
            state.phase="blocked"
            -- Safety blocks are quarantined and revalidated later instead of
            -- poisoning the target forever. The collector still refuses to fire.
            state.blockedUntil=os.clock()+cooldownFor(outcome,state)
        end
        requestScan(0.2,"blocked-target")
    else
        S.purchaseFailures=S.purchaseFailures+1
        S.buyGate="failed:"..tostring(outcome.reason)
        S.targetPhase=outcome.reason or "failed"
        if state then
            state.failures=(state.failures or 0)+1
            state.lastReason=outcome.reason
            state.phase="retry"
            state.blockedUntil=os.clock()+cooldownFor(outcome,state)
            if CONFIG.learningEnabled and outcome.attempted==true and state.failures>=3 and not state.learned then
                state.learned=true
                safe("brain.noteFailure",brain.noteFailure,target)
            end
        end
        if outcome.reason=="stale-interaction" or outcome.reason=="activation-unavailable" then
            requestScan(0.1,"interaction-stale")
        end
    end

    S.lastBuy=os.clock()
    S.buyBusy=false
    refreshBrain()
end

local function collectNow()
    if S.collectBusy or not CONFIG.enabled or not CONFIG.autoCollect or not S.data or S.data.automationAllowed~=true then return end
    S.collectBusy=true
    local gained=safe("collector.collectNearby",collector.collectNearby,context,S.data) or 0
    S.collected=S.collected+gained
    S.lastCollect=os.clock()
    S.collectBusy=false
end

local function status()
    normalise(S.data)
    S.currencyStatus=safe("currency.status",currency.status) or S.currencyStatus
    S.collectorStatus=safe("collector.getStatus",collector.getStatus) or S.collectorStatus
    local base=S.brainStatus or refreshBrain() or {}
    local brainOut={}
    for key,value in pairs(base) do brainOut[key]=value end
    if S.target and validButton(S.target) then
        brainOut.plan={name=S.target.name or S.target.object.Name,price=S.target.price,score=S.targetScore,phase=S.targetPhase}
    else
        brainOut.plan=nil
    end
    return {
        version=CONFIG.version,
        runtimeVersion=RUNTIME_VERSION,
        moduleManifest=MODULE_MANIFEST,
        enabled=CONFIG.enabled,
        autopilotEnabled=CONFIG.autopilotEnabled,
        learningEnabled=CONFIG.learningEnabled,
        burstMode=CONFIG.burstMode,
        autoRewards=CONFIG.autoRewards,
        autoRebirth=CONFIG.autoRebirth,
        strategy=CONFIG.strategy,
        bought=S.bought,
        collected=S.collected,
        rewardsActivated=S.rewardsActivated,
        purchaseAttempts=S.purchaseDispatches,
        purchaseFailures=S.purchaseFailures,
        deferredPurchases=S.deferredPurchases,
        blockedPurchases=S.blockedPurchases,
        purchasePhase=S.targetPhase,
        buyGate=S.buyGate,
        lastOutcome=S.lastOutcome,
        scanCount=S.scanCount,
        root=S.data and S.data.rootName or nil,
        ownerVerified=S.data and S.data.ownerVerified or false,
        buttons=S.data and S.data.totalButtons or 0,
        cash=S.data and S.data.cash or getCash(),
        brain=brainOut,
        collector=S.collectorStatus,
        currency=S.currencyStatus,
        autopilot=safe("autopilot.getStatus",autopilot.getStatus),
        boosts=safe("boosts.getStatus",boosts.getStatus),
    }
end

local function renderNow()
    if not S.data then return end
    normalise(S.data)
    refreshTarget(false)
    local target=S.target
    if CONFIG.highlightAffordable then safe("upgrades.render",upgrades.render,S.data,target)
    else safe("upgrades.clear",upgrades.clear) end
    safe("upgrades.renderLabels",upgrades.renderLabels,S.data,target)
    if CONFIG.showWaypoint and target and validButton(target) then safe("upgrades.updateWaypoint",upgrades.updateWaypoint,target)
    else safe("upgrades.hideWaypoint",upgrades.hideWaypoint) end

    local now=os.clock()
    if now-S.lastUi>=CONFIG.uiInterval then
        S.lastUi=now
        refreshBrain()
        safe("ui.update",ui.update,{
            data=S.data,
            nearest=target,
            cheapest=safe("upgrades.getCheapestAffordable",upgrades.getCheapestAffordable,S.data),
            bestValue=safe("upgrades.getMostExpensiveAffordable",upgrades.getMostExpensiveAffordable,S.data),
            nextLocked=safe("upgrades.getNextLocked",upgrades.getNextLocked,S.data),
            stats=statsState(),
            collected=S.collected,
            bought=S.bought,
            autonomous=status(),
        })
    end
end

local function setEnabled(value)
    CONFIG.enabled=value==true
    safe("autopilot.noteEnabled",autopilot.noteEnabled,CONFIG.enabled)
    if CONFIG.enabled then
        if CONFIG.learningEnabled and brain.beginRun then safe("brain.beginRun",brain.beginRun,CONFIG.strategy) end
        S.lastBuy=-math.huge
        S.lastCollect=-math.huge
        S.lastReward=-math.huge
        S.buyGate="starting"
        requestScan(0,"start")
        task.spawn(scanNow)
    else
        S.target=nil
        S.targetSignature=nil
        S.targetPhase="idle"
        S.buyGate="disabled"
        safe("collector.cleanup",collector.cleanup)
        safe("upgrades.clear",upgrades.clear)
        safe("upgrades.clearLabels",upgrades.clearLabels)
        safe("upgrades.hideWaypoint",upgrades.hideWaypoint)
    end
    saveSettings()
end

local function start()
    CONFIG.autoBuy=true
    CONFIG.autoCollect=true
    CONFIG.autopilotEnabled=true
    setEnabled(true)
    return true
end

local function stop()
    setEnabled(false)
    return true
end

local function setStrategy(value)
    if value=="Fastest" or value=="Income" or value=="Rebirth" then CONFIG.strategy=value end
    S.target=nil
    S.targetSignature=nil
    refreshBrain()
    saveSettings()
    return CONFIG.strategy
end

local function resetLearning()
    local result=safe("brain.resetPlaceProfile",brain.resetPlaceProfile)
    S.target=nil
    S.targetSignature=nil
    requestScan(0,"learning-reset")
    return result~=false
end

ui.onToggle("enabled",setEnabled)
ui.onToggle("autoCollect",function(v) CONFIG.autoCollect=v saveSettings() end)
ui.onToggle("autoBuy",function(v) CONFIG.autoBuy=v saveSettings() end)
ui.onToggle("highlightAffordable",function(v) CONFIG.highlightAffordable=v saveSettings() end)
ui.onToggle("showLabels",function(v) CONFIG.showLabels=v saveSettings() end)
ui.onToggle("showWaypoint",function(v) CONFIG.showWaypoint=v saveSettings() end)
ui.onToggle("requireOwnerMatch",function(v)
    CONFIG.requireOwnerMatch=v
    safe("scanner.invalidateRoot",scanner.invalidateRoot)
    requestScan(0,"owner-setting")
    saveSettings()
end)
ui.onToggle("autopilotEnabled",function(v) CONFIG.autopilotEnabled=v S.target=nil S.targetSignature=nil saveSettings() end)
ui.onToggle("learningEnabled",function(v) CONFIG.learningEnabled=v S.target=nil S.targetSignature=nil saveSettings() end)
ui.onToggle("burstMode",function(v) CONFIG.burstMode=v saveSettings() end)
ui.onToggle("autoRewards",function(v) CONFIG.autoRewards=v saveSettings() end)
ui.onToggle("autoRebirth",function(v) CONFIG.autoRebirth=v saveSettings() end)
ui.onToggle("autoLoadGamePreset",function(v) CONFIG.autoLoadGamePreset=v saveSettings() end)
ui.onCycle("strategy",setStrategy)
ui.onCycle("buyMode",function(v) CONFIG.buyMode=v S.target=nil S.targetSignature=nil saveSettings() end)
ui.onCycle("touchMode",function(v) CONFIG.touchMode=v saveSettings() end)
ui.onCycle("collectMode",function(v) CONFIG.collectMode=v saveSettings() end)
if ui.onAction then
    ui.onAction("start",start)
    ui.onAction("stop",stop)
    ui.onAction("resetLearning",resetLearning)
end

local function cleanup()
    if cleaned then return end
    cleaned=true
    disconnectAll(S.rootConnections)
    disconnectAll(S.connections)
    safe("brain.save",brain.save)
    safe("collector.cleanup",collector.cleanup)
    safe("upgrades.destroy",upgrades.destroy)
    safe("ui.destroy",ui.destroy)
    if currency.invalidate then safe("currency.invalidate",currency.invalidate) end
    if ENV.__VYRS_TYCOON_ACTIVE_TOKEN==TOKEN then ENV.__VYRS_TYCOON_ACTIVE_TOKEN=nil end
    if ENV.__VYRS_TYCOON_CLEANUP==cleanup then ENV.__VYRS_TYCOON_CLEANUP=nil end
    if ENV.__VYRS_TYCOON_DIAGNOSTICS==S then ENV.__VYRS_TYCOON_DIAGNOSTICS=nil end
    if ENV.__VYRS_TYCOON_GET_CASH==getCash then ENV.__VYRS_TYCOON_GET_CASH=nil end
    if ENV.__VYRS_TYCOON_CURRENCY_MARK==currency.mark then ENV.__VYRS_TYCOON_CURRENCY_MARK=nil end
    if ENV.__VYRS_TYCOON_CURRENCY_STATUS==currency.status then ENV.__VYRS_TYCOON_CURRENCY_STATUS=nil end
    ENV.__VYRS_TYCOON_AUTONOMOUS=nil
end

ENV.__VYRS_TYCOON_CLEANUP=cleanup
ENV.__VYRS_TYCOON_DIAGNOSTICS=S
ENV.__VYRS_TYCOON_AUTONOMOUS={
    start=start,
    stop=stop,
    setEnabled=setEnabled,
    setStrategy=setStrategy,
    resetLearning=resetLearning,
    status=status,
    cleanup=cleanup,
    setAutopilot=function(v) CONFIG.autopilotEnabled=v==true S.target=nil S.targetSignature=nil saveSettings() return CONFIG.autopilotEnabled end,
    setAutoRebirth=function(v) CONFIG.autoRebirth=v==true saveSettings() return CONFIG.autoRebirth end,
    setAutoRewards=function(v) CONFIG.autoRewards=v==true saveSettings() return CONFIG.autoRewards end,
    setLearning=function(v) CONFIG.learningEnabled=v==true S.target=nil S.targetSignature=nil saveSettings() return CONFIG.learningEnabled end,
    setBurst=function(v) CONFIG.burstMode=v==true saveSettings() return CONFIG.burstMode end,
}

local function worker(name,delay,callback)
    task.spawn(function()
        while active() do
            local ok,err=pcall(callback)
            if not ok then warn("[0xVyrs Tycoon v4.1] "..name.." worker failed: "..tostring(err)) end
            task.wait(delay)
        end
    end)
end

table.insert(S.connections,LOCAL_PLAYER.CharacterAdded:Connect(function()
    safe("scanner.invalidateRoot",scanner.invalidateRoot)
    if currency.invalidate then safe("currency.invalidate",currency.invalidate) end
    if stats.resetBaseline then safe("stats.resetBaseline",stats.resetBaseline) end
    S.target=nil
    S.targetSignature=nil
    requestScan(0,"character-added")
end))

worker("scan",0.10,function()
    if not CONFIG.enabled or S.scanBusy then return end
    local now=os.clock()
    if S.scanRequested and now>=S.scanDueAt then
        scanNow()
    elseif not S.scanRequested and now-S.lastScan>=CONFIG.scanInterval then
        requestScan(0,"periodic")
    end
end)

worker("buy",0.06,function()
    if not CONFIG.enabled or S.buyBusy or not S.data then return end
    normalise(S.data)
    local interval=CONFIG.buyInterval
    if CONFIG.autopilotEnabled and CONFIG.burstMode then
        interval=safe("autopilot.getBuyInterval",autopilot.getBuyInterval,S.data,S.brainStatus) or interval
    end
    if os.clock()-S.lastBuy>=interval then dispatchBuy() end
end)

worker("collect",0.12,function()
    if not CONFIG.enabled or S.collectBusy or not S.data then return end
    local interval=CONFIG.collectInterval
    if CONFIG.autopilotEnabled then
        interval=safe("autopilot.getCollectInterval",autopilot.getCollectInterval,S.data,S.brainStatus) or interval
    end
    if os.clock()-S.lastCollect>=interval then collectNow() end
end)

worker("render",0.16,function()
    if CONFIG.enabled and os.clock()-S.lastRender>=CONFIG.renderInterval then
        S.lastRender=os.clock()
        renderNow()
    end
end)

worker("stats",0.22,function()
    if not CONFIG.enabled or os.clock()-S.lastStats<CONFIG.statsInterval then return end
    S.lastStats=os.clock()
    safe("stats.update",stats.update)
    if CONFIG.learningEnabled and brain.observeEconomy then
        safe("brain.observeEconomy",brain.observeEconomy,getCash(),statsState())
    end
    refreshBrain()
end)

worker("rewards",0.5,function()
    if not CONFIG.enabled or not CONFIG.autoRewards or S.rewardBusy or not S.data or os.clock()-S.lastReward<2.5 then return end
    S.lastReward=os.clock()
    S.rewardBusy=true
    S.rewardsActivated=S.rewardsActivated+(safe("boosts.sweep",boosts.sweep,S.data) or 0)
    S.rewardBusy=false
end)

worker("completion",0.5,function()
    if not CONFIG.enabled or not S.data then return end
    local complete=safe("autopilot.updateCompletion",autopilot.updateCompletion,brain,S.data)==true
    if complete then
        safe("autopilot.recordCompletion",autopilot.recordCompletion,brain)
        if CONFIG.autoRebirth and not S.rebirthBusy then
            S.rebirthBusy=true
            task.spawn(function()
                if safe("autopilot.tryRebirth",autopilot.tryRebirth,S.data) then
                    safe("scanner.invalidateRoot",scanner.invalidateRoot)
                    if currency.invalidate then safe("currency.invalidate",currency.invalidate) end
                    if stats.resetBaseline then safe("stats.resetBaseline",stats.resetBaseline) end
                    S.target=nil
                    S.targetSignature=nil
                    requestScan(0,"rebirth")
                end
                S.rebirthBusy=false
            end)
        end
    end
end)

worker("health",2,function()
    if not CONFIG.enabled then return end
    normalise(S.data)
    refreshTarget(false)
    local target=S.target and (S.target.name or (S.target.object and S.target.object.Name)) or "nil"
    local price=S.target and tostring(S.target.price) or "nil"
    local cash=S.data and tostring(S.data.cash) or "nil"
    local buttons=S.data and tostring(S.data.totalButtons or 0) or "0"
    local affordable=S.data and tostring(S.data.affordableCount or 0) or "0"
    local outcome=S.lastOutcome and (tostring(S.lastOutcome.status)..":"..tostring(S.lastOutcome.reason)) or "none"
    local evidence=S.lastOutcome and S.lastOutcome.evidence and tostring(S.lastOutcome.evidence) or "none"
    local scanMs=S.data and ((S.data.debug and tonumber(S.data.debug.scanTimeMs)) or tonumber(S.data.runtimeScanMs))
    print(string.format("[0xVyrs Tycoon v4.1] HEALTH // gate=%s phase=%s cash=%s buttons=%s affordable=%s target=%s price=%s dispatches=%d outcome=%s evidence=%s scan=%s",
        tostring(S.buyGate),tostring(S.targetPhase),cash,buttons,affordable,tostring(target),price,S.purchaseDispatches,outcome,evidence,
        scanMs and string.format("%.1fms",scanMs) or "--"))
end)

worker("autosave",15,function()
    saveSettings()
    if CONFIG.learningEnabled then safe("brain.save",brain.save) end
end)

print("[0xVyrs Tycoon v4.1] runtime="..RUNTIME_VERSION.." loaded")
print("[0xVyrs Tycoon v4.1] modules // scanner="..MODULE_MANIFEST.scanner.." currency="..MODULE_MANIFEST.currency.." collector="..MODULE_MANIFEST.collector.." brain="..MODULE_MANIFEST.brain.." stats="..MODULE_MANIFEST.stats)
print("[0xVyrs Tycoon v4.1] module origins // scanner="..tostring(moduleOrigins.scanner).." currency="..tostring(moduleOrigins.currency).." collector="..tostring(moduleOrigins.collector).." brain="..tostring(moduleOrigins.brain))
