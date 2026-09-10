-- 0xVyrs Tycoon v4 audit test loader
-- Verifies the immutable runtime/module build before executing it.

local env=(type(getgenv)=="function" and getgenv()) or (type(getfenv)=="function" and getfenv(0)) or _G
local repo="https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/"
local BUILD="72c47e10baf3e84abd1649a017b98c767df24f19"
local base=repo..BUILD.."/"

local expected={
    {path="autonomous_v4.lua",marker="Autonomous Runtime v4",label="runtime-v4"},
    {path="tycoon_modules/scanner.lua",marker="scanner v4.1",label="scanner-v4.1"},
    {path="tycoon_modules/currency.lua",marker="Never trusts another player's replicated player-list balance",label="currency-strict"},
    {path="tycoon_modules/collector.lua",marker="interaction worker v4.1",label="collector-v4.1"},
    {path="tycoon_modules/brain.lua",marker="finite target selection",label="planner-audited"},
}

local sources={}
for _,entry in ipairs(expected) do
    local ok,source=pcall(function() return game:HttpGet(base..entry.path) end)
    if not ok or type(source)~="string" or source=="" then
        warn("[0xVyrs Tycoon v4 Test] ABORT // missing "..entry.label.." // "..tostring(source))
        return
    end
    if not source:find(entry.marker,1,true) then
        warn("[0xVyrs Tycoon v4 Test] ABORT // identity mismatch for "..entry.label.." // expected marker: "..entry.marker)
        return
    end
    local chunk,compileError=loadstring(source)
    if type(chunk)~="function" then
        warn("[0xVyrs Tycoon v4 Test] ABORT // compile failed for "..entry.label.." // "..tostring(compileError))
        return
    end
    sources[entry.path]=source
end

env.__VYRS_TYCOON_USE_LOCAL_MODULES=false
env.__VYRS_TYCOON_MODULE_BASE_URL=base.."tycoon_modules"
env.__VYRS_TYCOON_TEST_BUILD=BUILD

print("[0xVyrs Tycoon v4 Test] VERIFIED BUILD // "..BUILD)
print("[0xVyrs Tycoon v4 Test] runtime=v4 scanner=v4.1 currency=strict collector=v4.1 planner=audited")

local runtimeChunk,runtimeError=loadstring(sources["autonomous_v4.lua"])
if type(runtimeChunk)~="function" then
    warn("[0xVyrs Tycoon v4 Test] ABORT // runtime compile failed // "..tostring(runtimeError))
    return
end
return runtimeChunk()
