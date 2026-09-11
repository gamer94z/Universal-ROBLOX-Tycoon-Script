-- 0xVyrs Tycoon collector wrapper v4.3
-- Final paid-purchase fail-safe around the audited v4.2 collector core.

return function(context)
    local CONFIG=context.CONFIG or {}
    local base=tostring(CONFIG.moduleBaseUrl or "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/main/tycoon_modules"):gsub("/+$","")

    local function loadFactory(path,label)
        local source=game:HttpGet(base.."/"..path)
        local chunk,compileError=loadstring(source)
        assert(type(chunk)=="function",label.." compile failed: "..tostring(compileError))
        local factory=chunk()
        assert(type(factory)=="function",label.." did not return a factory")
        return factory
    end

    local core=loadFactory("collector_core.lua","collector_core")(context)
    local guard=loadFactory("paid_guard.lua","paid_guard")(context)
    assert(type(core)=="table" and type(core.buyButton)=="function","collector_core initialisation failed")
    assert(type(guard)=="table" and type(guard.evidence)=="function","paid_guard initialisation failed")

    local strictBlocked=0
    local lastStrictEvidence=nil

    local function buyButton(runtimeContext,button)
        local evidence=guard.evidence(button)
        if evidence then
            strictBlocked=strictBlocked+1
            lastStrictEvidence=evidence
            if button then
                button.paidPurchase=true
                button.paidEvidence=evidence
            end
            return false,{
                status="blocked",
                reason="blocked-paid-context",
                attempted=false,
                evidence=evidence,
                permanent=false,
            }
        end
        return core.buyButton(runtimeContext,button)
    end

    local function collectNearby(...)
        return core.collectNearby(...)
    end

    local function cleanup(...)
        if type(core.cleanup)=="function" then return core.cleanup(...) end
    end

    local function getStatus()
        local status={}
        if type(core.getStatus)=="function" then
            local ok,result=pcall(core.getStatus)
            if ok and type(result)=="table" then
                for key,value in pairs(result) do status[key]=value end
            end
        end
        status.moduleVersion="4.3-paid-safe"
        status.strictPaidBlocked=strictBlocked
        status.lastStrictPaidEvidence=lastStrictEvidence
        if lastStrictEvidence then status.lastBlockEvidence=lastStrictEvidence end
        return status
    end

    return {
        moduleVersion="4.3-paid-safe",
        buyButton=buyButton,
        collectNearby=collectNearby,
        getStatus=getStatus,
        cleanup=cleanup,
    }
end
