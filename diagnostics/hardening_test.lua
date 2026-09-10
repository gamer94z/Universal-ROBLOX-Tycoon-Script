-- 0xVyrs Tycoon v1.0.0 deep-hardening test loader.
-- Deterministic, remote-first, with one standalone currency provider.

local env=(type(getgenv)=="function" and getgenv()) or (type(getfenv)=="function" and getfenv(0)) or _G
local Players=game:GetService("Players")
local repo="https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/"
local STABLE_RUNTIME="8c2e708a6faf50bc3bc7e7f038df2585d95ddc49"
local HARDENING_COMMIT="cfbf49530b2ac502703a533201635c04aca115aa"

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
        if ok and status and status.value==nil then
            print("[0xVyrs Tycoon Test] currency still learning // candidates="..tostring(status.candidates or 0))
            for i,item in ipairs(status.top or {}) do
                print(string.format("[0xVyrs Tycoon Test] cash candidate #%d value=%s source=%s correlation=%s path=%s",i,tostring(item.value),tostring(item.source),tostring(item.correlation),tostring(item.path)))
            end
        end
    end)
end

print("[0xVyrs Tycoon Test] deep hardening active // remote-first // adaptive currency // specific-root scanner")
return chunk()
