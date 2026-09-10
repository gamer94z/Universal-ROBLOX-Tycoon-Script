-- 0xVyrs Tycoon v1.0.0 deep-hardening test loader.
-- Deterministic and remote-first. Compatibility fixes live in the modules themselves.

local env=(type(getgenv)=="function" and getgenv()) or (type(getfenv)=="function" and getfenv(0)) or _G
local Players=game:GetService("Players")
local repo="https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/"
local STABLE_RUNTIME="8c2e708a6faf50bc3bc7e7f038df2585d95ddc49"
local HARDENING_COMMIT="65548394bd6384930d5491ff9f879099da467461"

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
        end
    end)

    task.spawn(function()
        local deadline=os.clock()+45
        while os.clock()<deadline do
            task.wait(1)
            local api=env.__VYRS_TYCOON_AUTONOMOUS
            local ok,status=api and type(api.status)=="function" and pcall(api.status)
            if ok and status and status.enabled then
                task.wait(8)
                local runtime=env.__VYRS_TYCOON_DIAGNOSTICS
                local data=runtime and runtime.data
                local collectorStatus=runtime and runtime.collectorStatus
                print(string.format("[0xVyrs Tycoon Test] BUY STATE // attempts=%s failures=%s bought=%s cash=%s buttons=%s affordable=%s target=%s",
                    tostring(runtime and runtime.purchaseAttempts or 0),
                    tostring(runtime and runtime.purchaseFailures or 0),
                    tostring(runtime and runtime.bought or 0),
                    tostring(data and data.cash or "?"),
                    tostring(data and data.totalButtons or 0),
                    tostring(data and data.affordableCount or 0),
                    tostring(runtime and runtime.plannedTarget and runtime.plannedTarget.name or "nil")))
                return
            end
        end
    end)
end

print("[0xVyrs Tycoon Test] deep hardening active // direct modules // strict currency // isolated purchases // reused-pad verification // stable waypoint")
return chunk()
