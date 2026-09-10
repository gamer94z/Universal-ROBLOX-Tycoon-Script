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
    source,count=source:gsub(pattern,replacement)
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

-- The structural scanner used to require repeated button-family evidence for
-- non-zero purchases. That rejects tycoons which expose only one next purchase
-- at a time. In a verified owned plot, accept a tightly-local priced interaction
-- as a purchase candidate while retaining the scanner's premium/ad filters.
local scannerCompat=[[if name == "scanner" and source then
        local patchedScanner, scannerPatchCount = source:gsub(
            "if familySize>=2 or hinted or r%.price==0 then",
            "if familySize>=2 or hinted or r.price==0 or (verified and (r.depth or 99)<=2) then"
        )
        if scannerPatchCount == 1 then
            source = patchedScanner
        else
            warn("[0xVyrs Tycoon Test] scanner isolated-purchase patch mismatch: " .. tostring(scannerPatchCount))
        end
    end
    if not source then return nil end]]
if not patch('if not source then return nil end',scannerCompat,1) then return end

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
                task.wait(5)
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
                if runtime and (runtime.bought or 0)==0 and data then
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

print("[0xVyrs Tycoon Test] deep hardening active // strict local-player currency // isolated-purchase compatibility")
return chunk()
