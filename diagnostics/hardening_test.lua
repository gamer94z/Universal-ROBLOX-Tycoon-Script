-- 0xVyrs Tycoon v1.0.0 deep-hardening test loader.
-- Deterministic, remote-first, with one standalone currency provider.

local env=(type(getgenv)=="function" and getgenv()) or (type(getfenv)=="function" and getfenv(0)) or _G
local Players=game:GetService("Players")
local repo="https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/"
local STABLE_RUNTIME="8c2e708a6faf50bc3bc7e7f038df2585d95ddc49"
local HARDENING_COMMIT="436b9f617daf1bf04b71ec53b536223c6b476f86"

local currencySource=game:HttpGet(repo..HARDENING_COMMIT.."/tycoon_modules/currency.lua")
local currencyChunk,currencyCompileError=loadstring(currencySource)
if type(currencyChunk)~="function" then
    warn("[0xVyrs Tycoon Test] currency compile failed: "..tostring(currencyCompileError))
    return
end
local currencyFactory=currencyChunk()
local currency=type(currencyFactory)=="function" and currencyFactory({LOCAL_PLAYER=Players.LocalPlayer,SHARED_ENV=env}) or nil
if type(currency)~="table" or type(currency.get)~="function" then
    warn("[0xVyrs Tycoon Test] currency init failed")
    return
end

env.__VYRS_TYCOON_GET_CASH=currency.get
env.__VYRS_TYCOON_CURRENCY_MARK=currency.mark
env.__VYRS_TYCOON_CURRENCY_STATUS=currency.status
env.__VYRS_TYCOON_MODULE_BASE_URL=repo..HARDENING_COMMIT.."/tycoon_modules"
env.__VYRS_TYCOON_USE_LOCAL_MODULES=false

local source=game:HttpGet(repo..STABLE_RUNTIME.."/autonomous.lua")
local function patch(pattern,replacement,expected)
    local count
    source,count=source:gsub(pattern,function() return replacement end)
    if expected and count~=expected then
        warn("[0xVyrs Tycoon Test] patch mismatch: expected "..expected..", got "..count)
        return false
    end
    return true
end

local oldCash='local function getCash%(%)\n\tlocal item = getCashObject%(%)\n\treturn item and tonumber%(item%.Value%) or nil\nend'
local newCash=[[local function getCash()
    local provider=SHARED_ENV.__VYRS_TYCOON_GET_CASH
    if type(provider)=="function" then
        local ok,value=pcall(provider)
        if ok and tonumber(value)~=nil then return tonumber(value) end
    end
    local item=getCashObject()
    return item and tonumber(item.Value) or nil
end]]
if not patch(oldCash,newCash,1) then return end

if not patch('if type%(readfile%) == "function" then\n\t\tfor _, path in ipairs%(%{',
    'if SHARED_ENV.__VYRS_TYCOON_USE_LOCAL_MODULES == true and type(readfile) == "function" then\n\t\tfor _, path in ipairs({',1) then return end

local moduleCompat=[[local function literalReplace(text, needle, replacement)
        local first,last=string.find(text,needle,1,true)
        if not first then return text,0 end
        return string.sub(text,1,first-1)..replacement..string.sub(text,last+1),1
    end

    if name == "scanner" and source then
        local count
        source,count=literalReplace(source,
            "if familySize>=2 or hinted or r.price==0 then",
            "if familySize>=2 or hinted or r.price==0 or (verified and (r.depth or 99)<=2) then")
        if count~=1 then warn("[0xVyrs Tycoon Test] scanner isolated-purchase patch mismatch: "..tostring(count)) end
    elseif name == "collector" and source then
        local count
        source,count=literalReplace(source,"            waitStep(0.018)","            waitStep(0.045)")
        if count~=1 then warn("[0xVyrs Tycoon Test] collector touch-hold patch mismatch: "..tostring(count)) end

        local oldCapture=[[    local function capturePurchase(scanContext,button)
        local object=button and button.object
        return {object=object,parent=object and object.Parent or nil,cash=tonumber(scanContext.getCash()),price=tonumber(button and button.price) or 0,hadActivation=activationAlive(button) and true or false}
    end]]
        local newCapture=[[    local function purchaseSignature(button)
        local origin=button and (button.object or button.touchPart)
        if not origin or not origin.Parent then return nil end
        local pieces={}
        local queue={origin}
        local cursor=1
        local inspected=0
        while cursor<=#queue and inspected<56 do
            local current=queue[cursor]
            cursor=cursor+1
            local currentName=tostring(current.Name or "")
            if not currentName:find("Vyrs",1,true) then
                if current:IsA("TextLabel") or current:IsA("TextButton") then
                    local text=tostring(current.Text or "")
                    if text~="" then table.insert(pieces,currentName.."="..text) end
                elseif current:IsA("StringValue") or current:IsA("IntValue") or current:IsA("NumberValue") then
                    local lname=string.lower(currentName)
                    if lname:find("price",1,true) or lname:find("cost",1,true) or lname:find("amount",1,true) then
                        table.insert(pieces,currentName.."="..tostring(current.Value))
                    end
                end
                for _,child in ipairs(current:GetChildren()) do
                    inspected=inspected+1
                    if inspected<=56 and not tostring(child.Name or ""):find("Vyrs",1,true) then table.insert(queue,child) end
                    if inspected>=56 then break end
                end
            end
        end
        table.sort(pieces)
        return table.concat(pieces,"|")
    end

    local function capturePurchase(scanContext,button)
        local object=button and button.object
        return {
            object=object,
            parent=object and object.Parent or nil,
            cash=tonumber(scanContext.getCash()),
            price=tonumber(button and button.price) or 0,
            hadActivation=activationAlive(button) and true or false,
            signature=purchaseSignature(button),
        }
    end]]
        source,count=literalReplace(source,oldCapture,newCapture)
        if count~=1 then warn("[0xVyrs Tycoon Test] collector signature capture patch mismatch: "..tostring(count)) end

        local oldApplied=[[    local function purchaseApplied(scanContext,button,before)
        local object=before.object
        if not object or not object.Parent then return true end
        if hasPurchasedAncestor(object) then return true end
        if before.parent and object.Parent~=before.parent then return true end
        if before.hadActivation and not activationAlive(button) then return true end
        local current=tonumber(scanContext.getCash())
        return before.cash and current and before.price>0 and current<before.cash or false
    end]]
        local newApplied=[[    local function purchaseApplied(scanContext,button,before)
        local object=before.object
        if not object or not object.Parent then return true end
        if hasPurchasedAncestor(object) then return true end
        if before.parent and object.Parent~=before.parent then return true end
        if before.hadActivation and not activationAlive(button) then return true end
        local currentSignature=purchaseSignature(button)
        if before.signature and currentSignature and currentSignature~=before.signature then return true end
        local current=tonumber(scanContext.getCash())
        return before.cash and current and before.price>0 and current<before.cash or false
    end]]
        source,count=literalReplace(source,oldApplied,newApplied)
        if count~=1 then warn("[0xVyrs Tycoon Test] collector reused-pad verification patch mismatch: "..tostring(count)) end
    elseif name == "upgrades" and source then
        local count
        source,count=literalReplace(source,
            "\t\twaypointGui.Parent = entry.part",
            "\t\tlocal waypointHost = context and context.LOCAL_PLAYER and context.LOCAL_PLAYER:FindFirstChildOfClass(\"PlayerGui\")\n\t\tif waypointHost then waypointGui.Parent = waypointHost end")
        if count~=1 then warn("[0xVyrs Tycoon Test] waypoint lifecycle patch mismatch: "..tostring(count)) end
    end

    if not source then return nil end]]
if not patch('if not source then return nil end',moduleCompat,1) then return end

if not patch('local EVENT_SCAN_DEBOUNCE = 0%.16','local EVENT_SCAN_DEBOUNCE = 0.35',1) then return end
if not patch('local EVENT_SCAN_MIN_INTERVAL = 0%.38','local EVENT_SCAN_MIN_INTERVAL = 1.25',1) then return end
if not patch('\tuiInterval = 0%.5,','\tuiInterval = 0.8,',1) then return end

if not patch('if upgrades%.destroy then safe%("upgrades destroy", upgrades%.destroy%) end',
    'if collector.cleanup then safe("collector cleanup", collector.cleanup) end\n\tif upgrades.destroy then safe("upgrades destroy", upgrades.destroy) end',1) then return end

local chunk,compileError=loadstring(source)
if type(chunk)~="function" then
    warn("[0xVyrs Tycoon Test] patched runtime compile failed: "..tostring(compileError))
    return
end

if task and task.spawn then
    task.spawn(function()
        task.wait(5)
        local ok,status=pcall(currency.status)
        if ok and status then
            print(string.format("[0xVyrs Tycoon Test] CURRENCY STATE // value=%s source=%s reason=%s identity=%s localRows=%s candidates=%s",
                tostring(status.value),tostring(status.source),tostring(status.reason),tostring(status.identityScore or 0),tostring(status.strictPlayerListCount or 0),tostring(status.candidates or 0)))
            if status.value==nil then
                for i,item in ipairs(status.top or {}) do
                    print(string.format("[0xVyrs Tycoon Test] cash candidate #%d value=%s source=%s correlation=%s rowScore=%s path=%s",i,tostring(item.value),tostring(item.source),tostring(item.correlation),tostring(item.rowScore),tostring(item.path)))
                end
            end
        end
    end)

    task.spawn(function()
        local deadline=os.clock()+45
        while os.clock()<deadline do
            task.wait(1)
            local api=env.__VYRS_TYCOON_AUTONOMOUS
            local ok,status=api and type(api.status)=="function" and pcall(api.status)
            if ok and status and status.enabled then
                task.wait(6)
                local runtime=env.__VYRS_TYCOON_DIAGNOSTICS
                local data=runtime and runtime.data
                local target=runtime and runtime.plannedTarget
                print(string.format("[0xVyrs Tycoon Test] BUY STATE // attempts=%s failures=%s bought=%s cash=%s buttons=%s affordable=%s locked=%s target=%s",
                    tostring(runtime and runtime.purchaseAttempts or 0),
                    tostring(runtime and runtime.purchaseFailures or 0),
                    tostring(runtime and runtime.bought or 0),
                    tostring(data and data.cash or "?"),
                    tostring(data and data.totalButtons or 0),
                    tostring(data and data.affordableCount or 0),
                    tostring(data and data.lockedCount or 0),
                    tostring(target and target.name or "nil")))
                if runtime and data then
                    for i=1,math.min(5,#(data.buttons or {})) do
                        local b=data.buttons[i]
                        local kind=(b.prompt and b.prompt.Parent and "prompt") or (b.clickDetector and b.clickDetector.Parent and "click") or (b.touchPart and b.touchPart.Parent and "touch") or "none"
                        local blocked=(b.blockedUntil and math.max(0,b.blockedUntil-os.clock())) or 0
                        local path=b.object and b.object.Parent and b.object:GetFullName() or "?"
                        print(string.format("[0xVyrs Tycoon Test] BUTTON #%d // %s // price=%s affordable=%s kind=%s retry=%.1fs path=%s",
                            i,tostring(b.name),tostring(b.price),tostring(b.affordable),kind,blocked,path))
                    end
                end
                return
            end
        end
    end)
end

print("[0xVyrs Tycoon Test] deep hardening active // strict currency // isolated buttons // reused-pad verification // stable waypoint")
return chunk()
