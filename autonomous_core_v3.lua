--[[
    0xVyrs Tycoon Autonomous Runtime v1.0.0 - Core Rebuild v3
    Audited state machine: one scan owner, one purchase-state owner,
    structured interaction outcomes and one target authority for UI + dispatch.
]]

local Players=game:GetService("Players")
local CoreGui=game:GetService("CoreGui")
local HttpService=game:GetService("HttpService")
local LOCAL_PLAYER=Players.LocalPlayer
local ENV=(type(getgenv)=="function" and getgenv()) or (type(getfenv)=="function" and getfenv(0)) or _G

local previousCleanup=ENV.__VYRS_TYCOON_CLEANUP
if type(previousCleanup)=="function" then pcall(previousCleanup) end

local TOKEN="core-v3:"..tostring(os.clock())
ENV.__VYRS_TYCOON_ACTIVE_TOKEN=TOKEN

local CONFIG={
    version="1.0.0",enabled=false,autoCollect=true,autoBuy=true,autoLoadGamePreset=true,
    highlightAffordable=true,showLabels=false,showWaypoint=true,requireOwnerMatch=true,
    touchMode="Virtual",buyMode="Nearest",collectMode="Nearby",collectRange=90,
    scanInterval=6,renderInterval=0.45,uiInterval=0.65,statsInterval=0.9,
    collectInterval=0.6,buyInterval=0.35,maxButtons=80,maxDrops=60,maxLabels=12,
    uiOffsetX=24,uiOffsetY=180,autopilotEnabled=true,learningEnabled=true,
    burstMode=true,autoRewards=true,autoRebirth=false,strategy="Fastest",
    moduleBaseUrl=tostring(ENV.__VYRS_TYCOON_MODULE_BASE_URL or
        "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/v1.0-core-rebuild/tycoon_modules"),
}

local SETTINGS_FILE="tycoon_settings.json"
local cleaned=false

local function active()
    return not cleaned and ENV.__VYRS_TYCOON_ACTIVE_TOKEN==TOKEN
end
local function safe(label,fn,...)
    if type(fn)~="function" then return nil end
    local ok,a,b,c=pcall(fn,...)
    if not ok then warn("[0xVyrs Tycoon] "..label.." failed: "..tostring(a)); return nil end
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
        if CONFIG[key]~=nil and key~="version" and key~="enabled" and key~="moduleBaseUrl" then CONFIG[key]=value end
    end
    if CONFIG.strategy~="Fastest" and CONFIG.strategy~="Income" and CONFIG.strategy~="Rebirth" then CONFIG.strategy="Fastest" end
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
    for key,value in pairs(CONFIG) do if key~="version" and key~="moduleBaseUrl" then payload[key]=value end end
    payload.placeConfigs=payload.placeConfigs or {}
    payload.placeConfigs[tostring(game.PlaceId)]={}
    for key,value in pairs(CONFIG) do if key~="version" and key~="moduleBaseUrl" then payload.placeConfigs[tostring(game.PlaceId)][key]=value end end
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
    local ok,result=pcall(function() return game:HttpGet(CONFIG.moduleBaseUrl:gsub("/+$","").."/"..file) end)
    if ok and type(result)=="string" and result~="" then return result,"remote" end
    error("missing module "..name..": "..tostring(result))
end
local function loadFactory(name)
    local source=fetchSource(name)
    local chunk,err=loadstring(source)
    if type(chunk)~="function" then error(name.." compile failed: "..tostring(err)) end
    local ok,result=pcall(chunk)
    if not ok then error(name.." load failed: "..tostring(result)) end
    return result
end
local function init(factory,name,context)
    if type(factory)~="function" then return factory end
    local ok,result=pcall(factory,context)
    if not ok or type(result)~="table" then error(name.." init failed: "..tostring(result)) end
    return result
end

loadSettings()
local oldGui=CoreGui:FindFirstChild("TycoonCoreGUI")
if oldGui then oldGui:Destroy() end

local currency=nil
local function legacyCash()
    local stats=LOCAL_PLAYER:FindFirstChild("leaderstats")
    if not stats then return nil end
    for _,name in ipairs({"Cash","Money","Coins","Balance"}) do
        local value=stats:FindFirstChild(name)
        if value and tonumber(value.Value) then return tonumber(value.Value) end
    end
    return nil
end
local function getCash()
    if currency and type(currency.get)=="function" then
        local value=safe("currency get",currency.get)
        if tonumber(value)~=nil then return tonumber(value) end
    end
    return legacyCash()
end
local function getCashSourceKey()
    if currency and type(currency.status)=="function" then
        local status=safe("currency status",currency.status)
        if type(status)=="table" then return status.path or status.source end
    end
    return nil
end

local context={Players=Players,CoreGui=CoreGui,HttpService=HttpService,LOCAL_PLAYER=LOCAL_PLAYER,
    CONFIG=CONFIG,SHARED_ENV=ENV,saveSettings=saveSettings,getLocalRoot=getRoot,getCash=getCash,getCashSourceKey=getCashSourceKey}

currency=init(loadFactory("currency_v3"),"currency_v3",context)
ENV.__VYRS_TYCOON_GET_CASH=getCash
ENV.__VYRS_TYCOON_CURRENCY_MARK=currency.mark
ENV.__VYRS_TYCOON_CURRENCY_STATUS=currency.status

local scanner=init(loadFactory("scanner_v3"),"scanner_v3",context)
local collector=init(loadFactory("collector_v3"),"collector_v3",context)
local brain=init(loadFactory("brain_v3"),"brain_v3",context)
local ui=init(loadFactory("ui"),"ui",context)
local upgrades=init(loadFactory("upgrades"),"upgrades",context)
local stats=init(loadFactory("stats"),"stats",context)
local autopilot=init(loadFactory("autopilot"),"autopilot",context)
local boosts=init(loadFactory("boosts"),"boosts",context)

local R={
    data=nil,target=nil,targetScore=nil,targetPhase="idle",targetSignature=nil,
    bought=0,collected=0,rewardsActivated=0,purchaseAttempts=0,purchaseFailures=0,
    deferredPurchases=0,blockedPurchases=0,scanCount=0,lastScan=-math.huge,
    lastBuy=-math.huge,lastCollect=-math.huge,lastRender=-math.huge,lastUi=-math.huge,
    lastStats=-math.huge,lastReward=-math.huge,lastDispatchAt=-math.huge,
    scanRequested=true,scanDueAt=0,scanReason="startup",scanBusy=false,buyBusy=false,
    collectBusy=false,rewardBusy=false,rebirthBusy=false,buyGate="initialising",
    lastOutcome=nil,lastHealth=nil,purchaseStates=setmetatable({}, {__mode="k"}),
    rootConnections={},connections={},brainStatus=nil,collectorStatus=nil,currencyStatus=nil,
    cashResolved=false,
}

local function disconnectAll(list)
    for _,connection in ipairs(list) do pcall(function() connection:Disconnect() end) end
    table.clear(list)
end
local function requestScan(delay,reason)
    local due=os.clock()+math.max(0,tonumber(delay) or 0)
    if not R.scanRequested or due<R.scanDueAt then R.scanDueAt=due end
    R.scanRequested=true
    R.scanReason=reason or R.scanReason or "requested"
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
    local sig=buttonSignature(button)
    local state=R.purchaseStates[key]
    if not state or state.signature~=sig then
        state={signature=sig,failures=0,blockedUntil=nil,lastReason=nil,learned=false,phase="ready"}
        R.purchaseStates[key]=state
    end
    if state.blockedUntil and state.blockedUntil<=os.clock() then state.blockedUntil=nil state.phase="ready" end
    return state
end
local function validButton(button)
    if not button or button.paidPurchase then return false end
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
    local cash=tonumber(getCash())
    if cash~=nil then data.cash=cash end
    local removed=0
    for i=#(data.buttons or {}),1,-1 do
        local button=data.buttons[i]
        if not validButton(button) then
            table.remove(data.buttons,i)
            removed=removed+1
        else
            button.automationAllowed=data.automationAllowed
            local state=stateFor(button)
            button.blockedUntil=state and state.blockedUntil or nil
            button.failureCount=state and state.failures or 0
            button.approaching=state and state.phase=="approaching" or false
            local price=tonumber(button.price)
            if price~=nil and cash~=nil then button.affordable=price<=cash button.locked=price>cash end
        end
    end
    for i=#(data.drops or {}),1,-1 do
        local drop=data.drops[i]
        if not drop or not drop.object or not drop.object.Parent then table.remove(data.drops,i)
        else drop.automationAllowed=data.automationAllowed end
    end
    if removed>0 then requestScan(0.12,"dead-button") end
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
local function statsState() return safe("stats get",stats.get) or {} end
local function distance(button)
    local root=getRoot()
    return root and button and button.part and (button.part.Position-root.Position).Magnitude or math.huge
end
local function actionable(button)
    if not validButton(button) or button.automationAllowed~=true or button.affordable~=true then return false end
    local state=stateFor(button)
    return not (state and state.blockedUntil and state.blockedUntil>os.clock())
end
local function directMetric(button)
    if CONFIG.buyMode=="Cheapest" then return tonumber(button.price) or math.huge end
    if CONFIG.buyMode=="Value" then return -(tonumber(button.price) or 0) end
    return distance(button)
end
local function chooseTarget()
    if not R.data then R.buyGate="no-data" return nil,nil end
    normalise(R.data)
    if R.data.automationAllowed~=true then R.buyGate="owner-blocked" return nil,nil end
    if tonumber(R.data.cash)==nil then R.buyGate="cash-unresolved" return nil,nil end

    local candidates={}
    for _,button in ipairs(R.data.buttons or {}) do if actionable(button) then table.insert(candidates,button) end end
    if #candidates==0 then
        R.buyGate=(R.data.affordableCount or 0)>0 and "all-on-cooldown" or "no-affordable"
        return nil,nil
    end

    if CONFIG.autopilotEnabled and CONFIG.learningEnabled then
        local target,score=safe("brain choose",brain.choosePurchase,R.data,statsState())
        if actionable(target) and type(score)=="number" and score==score and score~=math.huge and score~=-math.huge then
            R.buyGate="ready"
            return target,score
        end
    end

    local best,bestMetric=nil,nil
    for _,button in ipairs(candidates) do
        local metric=directMetric(button)
        if bestMetric==nil or metric<bestMetric then best,bestMetric=button,metric end
    end
    R.buyGate=best and "ready" or "candidate-filtered"
    return best,nil
end
local function refreshBrain()
    if CONFIG.learningEnabled then R.brainStatus=safe("brain status",brain.getStatus,R.data,statsState()) else R.brainStatus=nil end
    return R.brainStatus
end
local function refreshTarget(force)
    normalise(R.data)
    if R.target and not validButton(R.target) then R.target=nil R.targetSignature=nil R.targetPhase="idle" end
    if R.target then
        local sig=buttonSignature(R.target)
        if sig~=R.targetSignature then R.target=nil R.targetSignature=nil R.targetPhase="idle" end
    end
    if force or not R.target or (R.target and not actionable(R.target)) then
        local chosen,score=chooseTarget()
        if chosen then
            R.target=chosen
            R.targetScore=score
            R.targetSignature=buttonSignature(chosen)
            local state=stateFor(chosen)
            R.targetPhase=state and state.phase or "ready"
        elseif not R.buyBusy then
            -- Keep a live cooldown target visible instead of flashing it away.
            if not (R.target and validButton(R.target)) then R.target=nil R.targetSignature=nil R.targetPhase="idle" end
        end
    end
    return R.target,R.targetScore
end

local function watchRoot(root)
    disconnectAll(R.rootConnections)
    if not root or root==workspace or not root.Parent then return end
    local function structural(o)
        if not o then return false end
        if o:IsA("TouchTransmitter") or o:IsA("ProximityPrompt") or o:IsA("ClickDetector") then return true end
        local name=tostring(o.Name):lower()
        return name:find("button",1,true) or name:find("purchase",1,true) or name:find("buy",1,true)
            or name:find("price",1,true) or name:find("cost",1,true) or name:find("collect",1,true)
    end
    table.insert(R.rootConnections,root.DescendantAdded:Connect(function(o) if structural(o) then requestScan(0.12,"descendant-added") end end))
    table.insert(R.rootConnections,root.DescendantRemoving:Connect(function(o) if structural(o) then requestScan(0.12,"descendant-removing") end end))
    table.insert(R.rootConnections,root.AncestryChanged:Connect(function(_,parent)
        if not parent then safe("scanner invalidate",scanner.invalidateRoot,root) requestScan(0,"root-lost") end
    end))
end

local function scanNow()
    if R.scanBusy or not active() then return end
    R.scanBusy=true
    local previousRoot=R.data and R.data.root
    local ok,result=pcall(scanner.scan,context)
    if ok and result then
        R.data=normalise(result)
        R.scanCount=R.scanCount+1
        R.lastScan=os.clock()
        R.scanRequested=false
        if previousRoot~=R.data.root then watchRoot(R.data.root) end
        if CONFIG.learningEnabled then safe("brain observe",brain.observe,R.data,statsState()) end
        safe("recovery",autopilot.updateRecovery,R.data)
        refreshTarget(true)
        refreshBrain()
    else
        if not ok then warn("[0xVyrs Tycoon] scanner worker failed: "..tostring(result)) end
        R.scanRequested=false
    end
    R.scanBusy=false
end

local function cooldownFor(outcome,state)
    local reason=outcome and outcome.reason or "unknown"
    if outcome and outcome.status=="deferred" then
        if reason=="player-moving" then return 0.25 end
        if reason=="cash-unresolved" or reason=="character-unavailable" then return 0.4 end
        if reason=="too-far" or reason=="autopilot-disabled" then return 0.8 end
        return 0.5
    end
    local failures=state and state.failures or 1
    return math.min(1.8,0.45+failures*0.22)
end
local function dispatchBuy()
    if R.buyBusy then R.buyGate="busy" return end
    if not CONFIG.enabled then R.buyGate="disabled" return end
    if not CONFIG.autoBuy then R.buyGate="auto-buy-off" return end
    if not R.data then R.buyGate="no-data" return end
    normalise(R.data)
    local target=refreshTarget(false)
    if not target or not actionable(target) then return end

    local state=stateFor(target)
    R.buyBusy=true
    R.buyGate="dispatching"
    R.targetPhase="dispatching"
    if state then state.phase="dispatching" end
    target.approaching=true
    R.purchaseAttempts=R.purchaseAttempts+1
    R.lastDispatchAt=os.clock()

    local ok,success,outcome=pcall(collector.buyButton,context,target)
    if not ok then
        outcome={status="failed",reason="collector-error",attempted=false,error=tostring(success)}
        success=false
        warn("[0xVyrs Tycoon] collector dispatch failed: "..tostring(outcome.error))
    end
    if type(outcome)~="table" then outcome={status=success and "success" or "failed",reason=success and "confirmed" or "unknown",attempted=true} end
    R.lastOutcome=outcome
    target.approaching=false

    if success==true or outcome.status=="success" then
        R.bought=R.bought+1
        R.buyGate="confirmed"
        R.targetPhase="confirmed"
        if stats.noteSpend then safe("stats spend",stats.noteSpend,target.price) end
        if CONFIG.learningEnabled then safe("brain purchase",brain.notePurchase,target,R.data,statsState()) end
        local key=activationKey(target)
        if key then R.purchaseStates[key]=nil end
        requestScan(0.12,"purchase-confirmed")
        task.delay(0.45,function() if active() and CONFIG.enabled then requestScan(0,"post-purchase-followup") end end)
    elseif outcome.status=="deferred" then
        R.deferredPurchases=R.deferredPurchases+1
        R.buyGate="deferred:"..tostring(outcome.reason)
        R.targetPhase=outcome.reason or "deferred"
        if state then state.lastReason=outcome.reason state.phase="deferred" state.blockedUntil=os.clock()+cooldownFor(outcome,state) end
    elseif outcome.status=="blocked" then
        R.blockedPurchases=R.blockedPurchases+1
        R.buyGate="blocked:"..tostring(outcome.reason)
        R.targetPhase="blocked"
        target.paidPurchase=true
        if state then state.lastReason=outcome.reason state.phase="blocked" state.blockedUntil=os.clock()+3 end
        requestScan(0.2,"blocked-target")
    else
        R.purchaseFailures=R.purchaseFailures+1
        R.buyGate="failed:"..tostring(outcome.reason)
        R.targetPhase=outcome.reason or "failed"
        if state then
            state.failures=(state.failures or 0)+1
            state.lastReason=outcome.reason
            state.phase="retry"
            state.blockedUntil=os.clock()+cooldownFor(outcome,state)
            if CONFIG.learningEnabled and state.failures>=3 and not state.learned then
                state.learned=true
                safe("brain failure",brain.noteFailure,target)
            end
        end
    end
    R.lastBuy=os.clock()
    R.buyBusy=false
    refreshBrain()
end

local function status()
    normalise(R.data)
    R.currencyStatus=safe("currency status",currency.status) or R.currencyStatus
    R.collectorStatus=safe("collector status",collector.getStatus) or R.collectorStatus
    local source=R.brainStatus or refreshBrain() or {}
    local brainOut={}
    for k,v in pairs(source) do brainOut[k]=v end
    if R.target and validButton(R.target) then
        brainOut.plan={name=R.target.name or R.target.object.Name,price=R.target.price,score=R.targetScore,phase=R.targetPhase}
    else brainOut.plan=nil end
    return {
        version=CONFIG.version,enabled=CONFIG.enabled,autopilotEnabled=CONFIG.autopilotEnabled,
        learningEnabled=CONFIG.learningEnabled,burstMode=CONFIG.burstMode,autoRewards=CONFIG.autoRewards,
        autoRebirth=CONFIG.autoRebirth,strategy=CONFIG.strategy,bought=R.bought,collected=R.collected,
        rewardsActivated=R.rewardsActivated,purchaseAttempts=R.purchaseAttempts,purchaseFailures=R.purchaseFailures,
        deferredPurchases=R.deferredPurchases,blockedPurchases=R.blockedPurchases,purchasePhase=R.targetPhase,
        buyGate=R.buyGate,lastOutcome=R.lastOutcome,scanCount=R.scanCount,root=R.data and R.data.rootName or nil,
        ownerVerified=R.data and R.data.ownerVerified or false,buttons=R.data and R.data.totalButtons or 0,
        cash=R.data and R.data.cash or getCash(),brain=brainOut,collector=R.collectorStatus,currency=R.currencyStatus,
        autopilot=safe("autopilot status",autopilot.getStatus),boosts=safe("boost status",boosts.getStatus),
    }
end

local function render()
    if not R.data then return end
    normalise(R.data)
    refreshTarget(false)
    local target=R.target
    if CONFIG.highlightAffordable then safe("highlights",upgrades.render,R.data,target) else safe("highlight clear",upgrades.clear) end
    safe("labels",upgrades.renderLabels,R.data,target)
    if CONFIG.showWaypoint and target and validButton(target) then safe("waypoint",upgrades.updateWaypoint,target) else safe("waypoint hide",upgrades.hideWaypoint) end
    local now=os.clock()
    if now-R.lastUi>=CONFIG.uiInterval then
        R.lastUi=now
        refreshBrain()
        safe("ui update",ui.update,{data=R.data,nearest=target,cheapest=safe("cheapest",upgrades.getCheapestAffordable,R.data),
            bestValue=safe("value",upgrades.getMostExpensiveAffordable,R.data),nextLocked=safe("locked",upgrades.getNextLocked,R.data),
            stats=statsState(),collected=R.collected,bought=R.bought,autonomous=status()})
    end
end

local function setEnabled(v)
    CONFIG.enabled=v==true
    safe("autopilot enabled",autopilot.noteEnabled,CONFIG.enabled)
    if CONFIG.enabled then
        if CONFIG.learningEnabled and brain.beginRun then safe("brain begin",brain.beginRun,CONFIG.strategy) end
        R.lastBuy=-math.huge
        R.lastCollect=-math.huge
        R.lastReward=-math.huge
        R.buyGate="starting"
        requestScan(0,"start")
        task.spawn(scanNow)
    else
        R.target=nil
        R.targetSignature=nil
        R.targetPhase="idle"
        R.buyGate="disabled"
        safe("collector cleanup",collector.cleanup)
        safe("highlight clear",upgrades.clear)
        safe("labels clear",upgrades.clearLabels)
        safe("waypoint hide",upgrades.hideWaypoint)
    end
    saveSettings()
end
local function start() CONFIG.autoBuy=true CONFIG.autoCollect=true CONFIG.autopilotEnabled=true setEnabled(true) return true end
local function stop() setEnabled(false) return true end
local function setStrategy(v)
    if v=="Fastest" or v=="Income" or v=="Rebirth" then CONFIG.strategy=v end
    R.target=nil R.targetSignature=nil refreshBrain() saveSettings() return CONFIG.strategy
end
local function resetLearning()
    local result=safe("brain reset",brain.resetPlaceProfile)
    R.target=nil R.targetSignature=nil requestScan(0,"learning-reset")
    return result~=false
end

ui.onToggle("enabled",setEnabled)
ui.onToggle("autoCollect",function(v) CONFIG.autoCollect=v saveSettings() end)
ui.onToggle("autoBuy",function(v) CONFIG.autoBuy=v saveSettings() end)
ui.onToggle("highlightAffordable",function(v) CONFIG.highlightAffordable=v saveSettings() end)
ui.onToggle("showLabels",function(v) CONFIG.showLabels=v saveSettings() end)
ui.onToggle("showWaypoint",function(v) CONFIG.showWaypoint=v saveSettings() end)
ui.onToggle("requireOwnerMatch",function(v) CONFIG.requireOwnerMatch=v safe("scanner invalidate",scanner.invalidateRoot) requestScan(0,"owner-setting") saveSettings() end)
ui.onToggle("autopilotEnabled",function(v) CONFIG.autopilotEnabled=v R.target=nil R.targetSignature=nil saveSettings() end)
ui.onToggle("learningEnabled",function(v) CONFIG.learningEnabled=v R.target=nil R.targetSignature=nil saveSettings() end)
ui.onToggle("burstMode",function(v) CONFIG.burstMode=v saveSettings() end)
ui.onToggle("autoRewards",function(v) CONFIG.autoRewards=v saveSettings() end)
ui.onToggle("autoRebirth",function(v) CONFIG.autoRebirth=v saveSettings() end)
ui.onToggle("autoLoadGamePreset",function(v) CONFIG.autoLoadGamePreset=v saveSettings() end)
ui.onCycle("strategy",setStrategy)
ui.onCycle("buyMode",function(v) CONFIG.buyMode=v R.target=nil R.targetSignature=nil saveSettings() end)
ui.onCycle("touchMode",function(v) CONFIG.touchMode=v saveSettings() end)
ui.onCycle("collectMode",function(v) CONFIG.collectMode=v saveSettings() end)
if ui.onAction then ui.onAction("start",start) ui.onAction("stop",stop) ui.onAction("resetLearning",resetLearning) end

local function cleanup()
    if cleaned then return end
    cleaned=true
    disconnectAll(R.rootConnections)
    disconnectAll(R.connections)
    safe("brain save",brain.save)
    safe("collector cleanup",collector.cleanup)
    safe("upgrades destroy",upgrades.destroy)
    safe("ui destroy",ui.destroy)
    if currency.invalidate then safe("currency invalidate",currency.invalidate) end
    if ENV.__VYRS_TYCOON_ACTIVE_TOKEN==TOKEN then ENV.__VYRS_TYCOON_ACTIVE_TOKEN=nil end
    if ENV.__VYRS_TYCOON_CLEANUP==cleanup then ENV.__VYRS_TYCOON_CLEANUP=nil end
    if ENV.__VYRS_TYCOON_DIAGNOSTICS==R then ENV.__VYRS_TYCOON_DIAGNOSTICS=nil end
    ENV.__VYRS_TYCOON_AUTONOMOUS=nil
end

ENV.__VYRS_TYCOON_CLEANUP=cleanup
ENV.__VYRS_TYCOON_DIAGNOSTICS=R
ENV.__VYRS_TYCOON_AUTONOMOUS={start=start,stop=stop,setEnabled=setEnabled,setStrategy=setStrategy,resetLearning=resetLearning,status=status,cleanup=cleanup,
    setAutopilot=function(v) CONFIG.autopilotEnabled=v==true R.target=nil R.targetSignature=nil saveSettings() return CONFIG.autopilotEnabled end,
    setAutoRebirth=function(v) CONFIG.autoRebirth=v==true saveSettings() return CONFIG.autoRebirth end,
    setAutoRewards=function(v) CONFIG.autoRewards=v==true saveSettings() return CONFIG.autoRewards end,
    setLearning=function(v) CONFIG.learningEnabled=v==true R.target=nil R.targetSignature=nil saveSettings() return CONFIG.learningEnabled end,
    setBurst=function(v) CONFIG.burstMode=v==true saveSettings() return CONFIG.burstMode end}

table.insert(R.connections,LOCAL_PLAYER.CharacterAdded:Connect(function()
    safe("scanner invalidate",scanner.invalidateRoot)
    if currency.invalidate then safe("currency invalidate",currency.invalidate) end
    if stats.resetBaseline then safe("stats baseline",stats.resetBaseline) end
    R.target=nil R.targetSignature=nil requestScan(0,"character-added")
end))

local function worker(name,delay,fn)
    task.spawn(function()
        while active() do
            local ok,err=pcall(fn)
            if not ok then warn("[0xVyrs Tycoon] "..name.." worker failed: "..tostring(err)) end
            task.wait(delay)
        end
    end)
end

worker("scan",0.10,function()
    if not CONFIG.enabled or R.scanBusy then return end
    local now=os.clock()
    if R.scanRequested and now>=R.scanDueAt then scanNow()
    elseif not R.scanRequested and now-R.lastScan>=CONFIG.scanInterval then requestScan(0,"periodic") end
end)
worker("buy",0.06,function()
    if not CONFIG.enabled or R.buyBusy or not R.data then return end
    normalise(R.data)
    local cash=tonumber(R.data.cash)
    if cash~=nil and not R.cashResolved then R.cashResolved=true requestScan(0,"currency-resolved") end
    local interval=CONFIG.buyInterval
    if CONFIG.autopilotEnabled and CONFIG.burstMode then interval=safe("buy interval",autopilot.getBuyInterval,R.data,R.brainStatus) or interval end
    if os.clock()-R.lastBuy>=interval then dispatchBuy() end
end)
worker("collect",0.12,function()
    if not CONFIG.enabled or R.collectBusy or not CONFIG.autoCollect or not R.data or R.data.automationAllowed~=true then return end
    local interval=CONFIG.collectInterval
    if CONFIG.autopilotEnabled then interval=safe("collect interval",autopilot.getCollectInterval,R.data,R.brainStatus) or interval end
    if os.clock()-R.lastCollect<interval then return end
    R.collectBusy=true
    R.collected=R.collected+(safe("collect",collector.collectNearby,context,R.data) or 0)
    R.lastCollect=os.clock()
    R.collectBusy=false
end)
worker("render",0.16,function()
    if CONFIG.enabled and os.clock()-R.lastRender>=CONFIG.renderInterval then R.lastRender=os.clock() render() end
end)
worker("stats",0.22,function()
    if not CONFIG.enabled or os.clock()-R.lastStats<CONFIG.statsInterval then return end
    R.lastStats=os.clock()
    safe("stats update",stats.update)
    if CONFIG.learningEnabled and brain.observeEconomy then safe("brain economy",brain.observeEconomy,getCash(),statsState()) end
    refreshBrain()
end)
worker("rewards",0.5,function()
    if not CONFIG.enabled or not CONFIG.autoRewards or R.rewardBusy or not R.data or os.clock()-R.lastReward<2.5 then return end
    R.lastReward=os.clock()
    R.rewardBusy=true
    R.rewardsActivated=R.rewardsActivated+(safe("rewards",boosts.sweep,R.data) or 0)
    R.rewardBusy=false
end)
worker("completion",0.5,function()
    if not CONFIG.enabled or not R.data then return end
    local complete=safe("completion",autopilot.updateCompletion,brain,R.data)==true
    if complete then
        safe("record completion",autopilot.recordCompletion,brain)
        if CONFIG.autoRebirth and not R.rebirthBusy then
            R.rebirthBusy=true
            task.spawn(function()
                if safe("rebirth",autopilot.tryRebirth,R.data) then
                    safe("scanner invalidate",scanner.invalidateRoot)
                    if currency.invalidate then safe("currency invalidate",currency.invalidate) end
                    R.target=nil R.targetSignature=nil requestScan(0,"rebirth")
                end
                R.rebirthBusy=false
            end)
        end
    end
end)
worker("health",2,function()
    if not CONFIG.enabled then return end
    normalise(R.data)
    local target=R.target and (R.target.name or (R.target.object and R.target.object.Name)) or "nil"
    local price=R.target and tostring(R.target.price) or "nil"
    local cash=R.data and tostring(R.data.cash) or "nil"
    local buttons=R.data and tostring(R.data.totalButtons or 0) or "0"
    local affordable=R.data and tostring(R.data.affordableCount or 0) or "0"
    local scanMs=R.data and R.data.debug and tonumber(R.data.debug.scanTimeMs)
    local outcome=R.lastOutcome and (tostring(R.lastOutcome.status)..":"..tostring(R.lastOutcome.reason)) or "none"
    local line=string.format("[0xVyrs Tycoon] HEALTH // gate=%s phase=%s cash=%s buttons=%s affordable=%s target=%s price=%s attempts=%d outcome=%s scan=%s",
        tostring(R.buyGate),tostring(R.targetPhase),cash,buttons,affordable,tostring(target),price,R.purchaseAttempts,outcome,scanMs and string.format("%.1fms",scanMs) or "--")
    if line~=R.lastHealth then print(line) R.lastHealth=line end
end)
worker("autosave",15,function() saveSettings() if CONFIG.learningEnabled then safe("brain save",brain.save) end end)

print("[0xVyrs Tycoon] v1.0.0 core rebuild v3 loaded // audited state machine")
