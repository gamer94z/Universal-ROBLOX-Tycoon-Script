--[[
    0xVyrs Tycoon Autonomous Runtime v1.0.0 - Core Rebuild v2
    One authoritative purchase queue for planning, UI and dispatch.
]]

local Players=game:GetService("Players")
local CoreGui=game:GetService("CoreGui")
local HttpService=game:GetService("HttpService")
local LOCAL_PLAYER=Players.LocalPlayer
local ENV=(type(getgenv)=="function" and getgenv()) or (type(getfenv)=="function" and getfenv(0)) or _G

local previousCleanup=ENV.__VYRS_TYCOON_CLEANUP
if type(previousCleanup)=="function" then pcall(previousCleanup) end

local TOKEN="core-v2:"..tostring(os.clock())
ENV.__VYRS_TYCOON_ACTIVE_TOKEN=TOKEN

local CONFIG={
    version="1.0.0", enabled=false, autoCollect=true, autoBuy=true,
    autoLoadGamePreset=true, highlightAffordable=true, showLabels=false,
    showWaypoint=true, requireOwnerMatch=true, touchMode="Virtual",
    buyMode="Nearest", collectMode="Nearby", collectRange=90,
    scanInterval=8, renderInterval=0.45, uiInterval=0.65,
    statsInterval=0.9, collectInterval=0.6, buyInterval=0.35,
    maxButtons=80, maxDrops=60, maxLabels=12, uiOffsetX=24, uiOffsetY=180,
    autopilotEnabled=true, learningEnabled=true, burstMode=true,
    autoRewards=true, autoRebirth=false, strategy="Fastest",
    moduleBaseUrl=tostring(ENV.__VYRS_TYCOON_MODULE_BASE_URL or
        "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/v1.0-core-rebuild/tycoon_modules"),
}

local SETTINGS_FILE="tycoon_settings.json"
local MODULE_NAMES={"scanner","ui","collector","upgrades","stats","brain","autopilot","boosts"}
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

local function fileApi()
    return type(isfile)=="function" and type(readfile)=="function" and type(writefile)=="function"
end

local function loadSettings()
    if not fileApi() or not isfile(SETTINGS_FILE) then return end
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
    if not fileApi() then return end
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
    for key,value in pairs(CONFIG) do
        if key~="version" and key~="moduleBaseUrl" then payload.placeConfigs[tostring(game.PlaceId)][key]=value end
    end
    pcall(function() writefile(SETTINGS_FILE,HttpService:JSONEncode(payload)) end)
end

local function getRoot()
    local character=LOCAL_PLAYER.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function legacyCashObject()
    local stats=LOCAL_PLAYER:FindFirstChild("leaderstats")
    if not stats then return nil end
    for _,name in ipairs({"Cash","Money","Coins","Balance"}) do
        local value=stats:FindFirstChild(name)
        if value and tonumber(value.Value) then return value end
    end
    return nil
end

local function fetchSource(name)
    local filename=name..".lua"
    if ENV.__VYRS_TYCOON_USE_LOCAL_MODULES==true and type(readfile)=="function" then
        for _,path in ipairs({"Tycoon/tycoon_modules/"..filename,"tycoon_modules/"..filename}) do
            local ok,result=pcall(function() return readfile(path) end)
            if ok and type(result)=="string" and result~="" then return result end
        end
    end
    local ok,result=pcall(function()
        return game:HttpGet(CONFIG.moduleBaseUrl:gsub("/+$","").."/"..filename)
    end)
    if ok and type(result)=="string" and result~="" then return result end
    error("missing module "..name..": "..tostring(result))
end

local function loadFactory(name)
    local chunk,err=loadstring(fetchSource(name))
    if type(chunk)~="function" then error(name.." compile failed: "..tostring(err)) end
    local ok,result=pcall(chunk)
    if not ok then error(name.." load failed: "..tostring(result)) end
    return result
end

loadSettings()
local oldGui=CoreGui:FindFirstChild("TycoonCoreGUI")
if oldGui then oldGui:Destroy() end

local currency
local function getCash()
    if currency and type(currency.get)=="function" then
        local value=safe("currency get",currency.get)
        if tonumber(value)~=nil then return tonumber(value) end
    end
    local object=legacyCashObject()
    return object and tonumber(object.Value) or nil
end

local function cashSourceKey()
    if currency and type(currency.status)=="function" then
        local s=safe("currency status",currency.status)
        if type(s)=="table" then return s.path or s.source end
    end
    local object=legacyCashObject()
    return object and object:GetFullName() or nil
end

local context={
    Players=Players, CoreGui=CoreGui, HttpService=HttpService,
    LOCAL_PLAYER=LOCAL_PLAYER, CONFIG=CONFIG, SHARED_ENV=ENV,
    saveSettings=saveSettings, getLocalRoot=getRoot, getCash=getCash,
    getCashSourceKey=cashSourceKey,
}

local function initialise(factory,name)
    if type(factory)~="function" then return factory end
    local ok,result=pcall(factory,context)
    if not ok or type(result)~="table" then error(name.." init failed: "..tostring(result)) end
    return result
end

currency=initialise(loadFactory("currency"),"currency")
ENV.__VYRS_TYCOON_GET_CASH=getCash
ENV.__VYRS_TYCOON_CURRENCY_MARK=currency.mark
ENV.__VYRS_TYCOON_CURRENCY_STATUS=currency.status

local factory={}
for _,name in ipairs(MODULE_NAMES) do factory[name]=loadFactory(name) end
local scanner=initialise(factory.scanner,"scanner")
local ui=initialise(factory.ui,"ui")
local collector=initialise(factory.collector,"collector")
local upgrades=initialise(factory.upgrades,"upgrades")
local stats=initialise(factory.stats,"stats")
local brain=initialise(factory.brain,"brain")
local autopilot=initialise(factory.autopilot,"autopilot")
local boosts=initialise(factory.boosts,"boosts")

local R={
    data=nil,target=nil,targetScore=nil,targetPhase="idle",
    bought=0,collected=0,rewardsActivated=0,purchaseAttempts=0,purchaseFailures=0,
    scanCount=0,lastScan=-math.huge,lastBuy=-math.huge,lastCollect=-math.huge,
    lastRender=-math.huge,lastUi=-math.huge,lastStats=-math.huge,lastReward=-math.huge,
    scanBusy=false,buyBusy=false,collectBusy=false,rewardBusy=false,rebirthBusy=false,
    scanRequested=true,scanRequestedAt=0,buyGate="initialising",lastDispatchAt=-math.huge,
    purchaseStates=setmetatable({}, {__mode="k"}), rootConnections={}, connections={},
    brainStatus=nil,collectorStatus=nil,currencyStatus=nil,
}

local function disconnectAll(list)
    for _,c in ipairs(list) do pcall(function() c:Disconnect() end) end
    table.clear(list)
end

local function requestScan(immediate)
    R.scanRequested=true
    R.scanRequestedAt=immediate and 0 or os.clock()
end

local function validObject(button)
    return button and not button.paidPurchase and button.object and button.object.Parent
        and button.part and button.part.Parent
end

local function signature(button)
    return tostring(button.name or "").."|"..tostring(tonumber(button.price) or 0)
end

local function stateFor(button)
    if not button or not button.object then return nil end
    local sig=signature(button)
    local state=R.purchaseStates[button.object]
    if not state or state.signature~=sig then
        state={signature=sig,failures=0,blockedUntil=nil,learned=false}
        R.purchaseStates[button.object]=state
    end
    if state.blockedUntil and state.blockedUntil<=os.clock() then state.blockedUntil=nil end
    return state
end

local function normalise(data)
    if not data then return nil end
    if data.selectedByPosition==true and data.ownerSource=="position-cluster" then
        data.ownerVerified=false; data.ownerMatch=false; data.owned=false
    end
    data.automationAllowed=(data.ownerVerified==true) or CONFIG.requireOwnerMatch==false
    data.safeAutomation=data.automationAllowed
    data.showLabels=CONFIG.showLabels
    data.maxLabels=CONFIG.maxLabels

    local cash=tonumber(getCash())
    if cash~=nil then data.cash=cash end

    for i=#(data.buttons or {}),1,-1 do
        local b=data.buttons[i]
        if not validObject(b) then table.remove(data.buttons,i) else
            b.automationAllowed=data.automationAllowed
            local s=stateFor(b)
            b.blockedUntil=s and s.blockedUntil or nil
            b.failureCount=s and s.failures or 0
            b.approaching=false
            local price=tonumber(b.price)
            if price~=nil and cash~=nil then b.affordable=price<=cash; b.locked=price>cash end
        end
    end
    for i=#(data.drops or {}),1,-1 do
        local d=data.drops[i]
        if not d or not d.object or not d.object.Parent then table.remove(data.drops,i)
        else d.automationAllowed=data.automationAllowed end
    end

    local affordable,locked=0,0
    for _,b in ipairs(data.buttons or {}) do
        if b.affordable and not b.paidPurchase then affordable=affordable+1
        elseif b.locked and not b.paidPurchase then locked=locked+1 end
    end
    data.totalButtons=#(data.buttons or {})
    data.affordableCount=affordable
    data.lockedCount=locked
    return data
end

local function statsState() return safe("stats get",stats.get) or {} end

local function candidate(button)
    if not validObject(button) or button.automationAllowed~=true or button.affordable~=true then return false end
    local s=stateFor(button)
    return not (s and s.blockedUntil and s.blockedUntil>os.clock())
end

local function distance(button,root)
    if not root or not button or not button.part then return math.huge end
    return (button.part.Position-root.Position).Magnitude
end

local function directChoice(data)
    if not data then return nil end
    local root=getRoot()
    local best,bestMetric
    for _,b in ipairs(data.buttons or {}) do
        if candidate(b) then
            local metric
            if CONFIG.buyMode=="Cheapest" then metric=tonumber(b.price) or math.huge
            elseif CONFIG.buyMode=="Value" then metric=-(tonumber(b.price) or 0)
            else metric=distance(b,root) end
            if bestMetric==nil or metric<bestMetric then best,bestMetric=b,metric end
        end
    end
    return best
end

local function chooseTarget()
    if not R.data then R.buyGate="no-data"; return nil end
    normalise(R.data)
    if R.data.automationAllowed~=true then R.buyGate="owner-blocked"; return nil end
    if (R.data.affordableCount or 0)<=0 then R.buyGate="no-affordable"; return nil end

    local chosen,score
    if CONFIG.autopilotEnabled and CONFIG.learningEnabled then
        chosen,score=safe("brain choose",brain.choosePurchase,R.data,statsState())
        if not candidate(chosen) or type(score)~="number" or score~=score or score==math.huge or score==-math.huge then
            chosen,score=nil,nil
        end
    end
    if not chosen then chosen=directChoice(R.data) end
    if not chosen then
        -- Last-resort queue repair: ignore stale planner metadata and take any live affordable button.
        for _,b in ipairs(R.data.buttons or {}) do
            if validObject(b) and b.affordable==true and b.automationAllowed==true then
                local s=stateFor(b)
                if not s or not s.blockedUntil or s.blockedUntil<=os.clock() then chosen=b; break end
            end
        end
    end
    R.buyGate=chosen and "ready" or "candidate-filtered"
    return chosen,score
end

local function refreshBrain()
    if CONFIG.learningEnabled then R.brainStatus=safe("brain status",brain.getStatus,R.data,statsState()) else R.brainStatus=nil end
    return R.brainStatus
end

local function watchRoot(root)
    disconnectAll(R.rootConnections)
    if not root or root==workspace or not root.Parent then return end
    local function structural(o)
        if not o then return false end
        if o:IsA("TouchTransmitter") or o:IsA("ProximityPrompt") or o:IsA("ClickDetector") then return true end
        local n=tostring(o.Name):lower()
        return n:find("button",1,true) or n:find("purchase",1,true) or n:find("buy",1,true)
            or n:find("price",1,true) or n:find("cost",1,true) or n:find("collect",1,true)
    end
    table.insert(R.rootConnections,root.DescendantAdded:Connect(function(o) if structural(o) then requestScan(false) end end))
    table.insert(R.rootConnections,root.DescendantRemoving:Connect(function(o) if structural(o) then requestScan(false) end end))
    table.insert(R.rootConnections,root.AncestryChanged:Connect(function(_,parent)
        if not parent then safe("scanner invalidate",scanner.invalidateRoot,root); requestScan(true) end
    end))
end

local function scanNow()
    if R.scanBusy or not active() then return end
    R.scanBusy=true
    local ok,result=pcall(scanner.scan,context)
    if ok and result then
        local previousRoot=R.data and R.data.root
        R.data=normalise(result)
        R.scanCount=R.scanCount+1
        R.lastScan=os.clock()
        R.scanRequested=false
        if previousRoot~=R.data.root then watchRoot(R.data.root) end
        if CONFIG.learningEnabled then safe("brain observe",brain.observe,R.data,statsState()) end
        safe("recovery",autopilot.updateRecovery,R.data)
        local target,score=chooseTarget()
        if target then R.target,R.targetScore=target,score elseif not R.buyBusy then R.target=nil end
        refreshBrain()
    elseif not ok then
        warn("[0xVyrs Tycoon] scanner worker failed: "..tostring(result))
    end
    R.scanBusy=false
end

local function purchaseReason()
    R.collectorStatus=safe("collector status",collector.getStatus) or R.collectorStatus or {}
    return R.collectorStatus.lastPurchaseReason
end

local function dispatchBuy()
    if R.buyBusy then R.buyGate="busy"; return end
    if not CONFIG.enabled then R.buyGate="disabled"; return end
    if not CONFIG.autoBuy then R.buyGate="auto-buy-off"; return end
    if not R.data then R.buyGate="no-data"; return end

    local target,score=chooseTarget()
    if not target then return end

    R.buyBusy=true
    R.target=target
    R.targetScore=score
    R.targetPhase="dispatch"
    R.buyGate="dispatching"
    R.purchaseAttempts=R.purchaseAttempts+1
    R.lastDispatchAt=os.clock()
    target.approaching=true

    local ok,result=pcall(collector.buyButton,context,target)
    local success=ok and result==true
    local reason=ok and purchaseReason() or "collector-error"
    target.approaching=false

    if success then
        R.bought=R.bought+1
        R.targetPhase="confirmed"
        R.buyGate="confirmed"
        if stats.noteSpend then safe("stats spend",stats.noteSpend,target.price) end
        if CONFIG.learningEnabled then safe("brain purchase",brain.notePurchase,target,R.data,statsState()) end
        if target.object then R.purchaseStates[target.object]=nil end
        requestScan(true)
        task.delay(0.12,function() if active() and CONFIG.enabled then scanNow() end end)
    else
        if not ok then warn("[0xVyrs Tycoon] collector dispatch failed: "..tostring(result)) end
        local s=stateFor(target)
        if s then
            s.failures=math.max((s.failures or 0)+1,tonumber(target.failureCount) or 0)
            s.blockedUntil=tonumber(target.blockedUntil) or (os.clock()+math.min(1.6,0.45+s.failures*0.18))
            target.blockedUntil=s.blockedUntil
            target.failureCount=s.failures
            -- Only teach the route learner after repeated real dispatch misses.
            if CONFIG.learningEnabled and s.failures>=4 and not s.learned
                and (reason=="not-confirmed" or reason=="approach-not-confirmed" or reason=="stale-interaction") then
                s.learned=true
                safe("brain failure",brain.noteFailure,target)
            end
        end
        R.purchaseFailures=R.purchaseFailures+1
        R.targetPhase=reason or "retry"
        R.buyGate="retry:"..tostring(reason or "unknown")
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
    if R.target and validObject(R.target) then
        brainOut.plan={name=R.target.name or R.target.object.Name,price=R.target.price,score=R.targetScore,phase=R.targetPhase}
    elseif brainOut.plan and not candidate(R.target) then
        brainOut.plan=nil
    end
    return {
        version=CONFIG.version,enabled=CONFIG.enabled,autopilotEnabled=CONFIG.autopilotEnabled,
        learningEnabled=CONFIG.learningEnabled,burstMode=CONFIG.burstMode,autoRewards=CONFIG.autoRewards,
        autoRebirth=CONFIG.autoRebirth,strategy=CONFIG.strategy,bought=R.bought,collected=R.collected,
        rewardsActivated=R.rewardsActivated,purchaseAttempts=R.purchaseAttempts,purchaseFailures=R.purchaseFailures,
        purchasePhase=R.targetPhase,buyGate=R.buyGate,scanCount=R.scanCount,
        root=R.data and R.data.rootName or nil,ownerVerified=R.data and R.data.ownerVerified or false,
        buttons=R.data and R.data.totalButtons or 0,cash=R.data and R.data.cash or getCash(),
        brain=brainOut,collector=R.collectorStatus,currency=R.currencyStatus,
        autopilot=safe("autopilot status",autopilot.getStatus),boosts=safe("boost status",boosts.getStatus),
    }
end

local function render()
    if not R.data then return end
    normalise(R.data)
    if not R.target or not validObject(R.target) or (not R.buyBusy and not candidate(R.target)) then
        R.target,R.targetScore=chooseTarget()
    end
    local target=R.target
    if CONFIG.highlightAffordable then safe("highlights",upgrades.render,R.data,target) else safe("highlight clear",upgrades.clear) end
    safe("labels",upgrades.renderLabels,R.data,target)
    if CONFIG.showWaypoint and target then safe("waypoint",upgrades.updateWaypoint,target) else safe("waypoint hide",upgrades.hideWaypoint) end

    local now=os.clock()
    if now-R.lastUi>=CONFIG.uiInterval then
        R.lastUi=now
        refreshBrain()
        safe("ui update",ui.update,{
            data=R.data,nearest=target,cheapest=safe("cheapest",upgrades.getCheapestAffordable,R.data),
            bestValue=safe("value",upgrades.getMostExpensiveAffordable,R.data),
            nextLocked=safe("locked",upgrades.getNextLocked,R.data),stats=statsState(),
            collected=R.collected,bought=R.bought,autonomous=status(),
        })
    end
end

local function setEnabled(v)
    CONFIG.enabled=v==true
    safe("autopilot enabled",autopilot.noteEnabled,CONFIG.enabled)
    if CONFIG.enabled then
        if CONFIG.learningEnabled and brain.beginRun then safe("brain begin",brain.beginRun,CONFIG.strategy) end
        R.lastBuy=-math.huge; R.lastCollect=-math.huge; R.lastReward=-math.huge
        requestScan(true)
    else
        R.target=nil; R.targetPhase="idle"; R.buyGate="disabled"
        safe("collector cleanup",collector.cleanup); safe("highlight clear",upgrades.clear)
        safe("labels clear",upgrades.clearLabels); safe("waypoint hide",upgrades.hideWaypoint)
    end
    saveSettings()
end

local function start() CONFIG.autoBuy=true; CONFIG.autoCollect=true; CONFIG.autopilotEnabled=true; setEnabled(true); return true end
local function stop() setEnabled(false); return true end
local function setStrategy(v)
    if v=="Fastest" or v=="Income" or v=="Rebirth" then CONFIG.strategy=v end
    R.target=nil; refreshBrain(); saveSettings(); return CONFIG.strategy
end
local function resetLearning()
    local ok=safe("brain reset",brain.resetPlaceProfile)
    R.target=nil; requestScan(true); return ok~=false
end

ui.onToggle("enabled",setEnabled)
ui.onToggle("autoCollect",function(v) CONFIG.autoCollect=v; saveSettings() end)
ui.onToggle("autoBuy",function(v) CONFIG.autoBuy=v; saveSettings() end)
ui.onToggle("highlightAffordable",function(v) CONFIG.highlightAffordable=v; saveSettings() end)
ui.onToggle("showLabels",function(v) CONFIG.showLabels=v; saveSettings() end)
ui.onToggle("showWaypoint",function(v) CONFIG.showWaypoint=v; saveSettings() end)
ui.onToggle("requireOwnerMatch",function(v) CONFIG.requireOwnerMatch=v; safe("scanner invalidate",scanner.invalidateRoot); requestScan(true); saveSettings() end)
ui.onToggle("autopilotEnabled",function(v) CONFIG.autopilotEnabled=v; R.target=nil; saveSettings() end)
ui.onToggle("learningEnabled",function(v) CONFIG.learningEnabled=v; R.target=nil; saveSettings() end)
ui.onToggle("burstMode",function(v) CONFIG.burstMode=v; saveSettings() end)
ui.onToggle("autoRewards",function(v) CONFIG.autoRewards=v; saveSettings() end)
ui.onToggle("autoRebirth",function(v) CONFIG.autoRebirth=v; saveSettings() end)
ui.onToggle("autoLoadGamePreset",function(v) CONFIG.autoLoadGamePreset=v; saveSettings() end)
ui.onCycle("strategy",setStrategy)
ui.onCycle("buyMode",function(v) CONFIG.buyMode=v; R.target=nil; saveSettings() end)
ui.onCycle("touchMode",function(v) CONFIG.touchMode=v; saveSettings() end)
ui.onCycle("collectMode",function(v) CONFIG.collectMode=v; saveSettings() end)
if ui.onAction then ui.onAction("start",start); ui.onAction("stop",stop); ui.onAction("resetLearning",resetLearning) end

local function cleanup()
    if cleaned then return end
    cleaned=true
    disconnectAll(R.rootConnections); disconnectAll(R.connections)
    safe("brain save",brain.save); safe("collector cleanup",collector.cleanup)
    safe("upgrades destroy",upgrades.destroy); safe("ui destroy",ui.destroy)
    if currency.invalidate then safe("currency invalidate",currency.invalidate) end
    if ENV.__VYRS_TYCOON_ACTIVE_TOKEN==TOKEN then ENV.__VYRS_TYCOON_ACTIVE_TOKEN=nil end
    if ENV.__VYRS_TYCOON_CLEANUP==cleanup then ENV.__VYRS_TYCOON_CLEANUP=nil end
    if ENV.__VYRS_TYCOON_DIAGNOSTICS==R then ENV.__VYRS_TYCOON_DIAGNOSTICS=nil end
    ENV.__VYRS_TYCOON_AUTONOMOUS=nil
end

ENV.__VYRS_TYCOON_CLEANUP=cleanup
ENV.__VYRS_TYCOON_DIAGNOSTICS=R
ENV.__VYRS_TYCOON_AUTONOMOUS={
    start=start,stop=stop,setEnabled=setEnabled,setStrategy=setStrategy,resetLearning=resetLearning,status=status,cleanup=cleanup,
    setAutopilot=function(v) CONFIG.autopilotEnabled=v==true; R.target=nil; saveSettings(); return CONFIG.autopilotEnabled end,
    setAutoRebirth=function(v) CONFIG.autoRebirth=v==true; saveSettings(); return CONFIG.autoRebirth end,
    setAutoRewards=function(v) CONFIG.autoRewards=v==true; saveSettings(); return CONFIG.autoRewards end,
    setLearning=function(v) CONFIG.learningEnabled=v==true; R.target=nil; saveSettings(); return CONFIG.learningEnabled end,
    setBurst=function(v) CONFIG.burstMode=v==true; saveSettings(); return CONFIG.burstMode end,
}

table.insert(R.connections,LOCAL_PLAYER.CharacterAdded:Connect(function()
    safe("scanner invalidate",scanner.invalidateRoot)
    if currency.invalidate then safe("currency invalidate",currency.invalidate) end
    if stats.resetBaseline then safe("stats baseline",stats.resetBaseline) end
    R.target=nil; requestScan(true)
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
    if R.scanRequested then
        if R.scanRequestedAt==0 or now-R.scanRequestedAt>=0.22 then scanNow() end
    elseif now-R.lastScan>=CONFIG.scanInterval then scanNow() end
end)

worker("buy",0.06,function()
    if not CONFIG.enabled or R.buyBusy or not R.data then return end
    normalise(R.data)
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
    R.lastCollect=os.clock(); R.collectBusy=false
end)

worker("render",0.15,function()
    if CONFIG.enabled and os.clock()-R.lastRender>=CONFIG.renderInterval then R.lastRender=os.clock(); render() end
end)

worker("stats",0.20,function()
    if not CONFIG.enabled or os.clock()-R.lastStats<CONFIG.statsInterval then return end
    R.lastStats=os.clock(); safe("stats update",stats.update)
    if CONFIG.learningEnabled and brain.observeEconomy then safe("brain economy",brain.observeEconomy,getCash(),statsState()) end
    refreshBrain()
end)

worker("rewards",0.5,function()
    if not CONFIG.enabled or not CONFIG.autoRewards or R.rewardBusy or not R.data or os.clock()-R.lastReward<2.5 then return end
    R.lastReward=os.clock(); R.rewardBusy=true
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
                    R.target=nil; requestScan(true)
                end
                R.rebirthBusy=false
            end)
        end
    end
end)

worker("health",2,function()
    if not CONFIG.enabled or not R.data then return end
    normalise(R.data)
    local affordable=R.data.affordableCount or 0
    if affordable>0 and os.clock()-R.lastDispatchAt>3 then
        local t=R.target and (R.target.name or (R.target.object and R.target.object.Name)) or "nil"
        print(string.format("[0xVyrs Tycoon] BUY HEALTH // gate=%s attempts=%d affordable=%d target=%s cash=%s busy=%s",
            tostring(R.buyGate),R.purchaseAttempts,affordable,tostring(t),tostring(R.data.cash),tostring(R.buyBusy)))
    end
end)

worker("autosave",15,function() saveSettings(); if CONFIG.learningEnabled then safe("brain save",brain.save) end end)

print("[0xVyrs Tycoon] v1.0.0 core rebuild v2 loaded // authoritative purchase queue")
