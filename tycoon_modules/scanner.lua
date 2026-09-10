-- 0xVyrs universal tycoon scanner v4.2
-- Readiness gate over the audited v4.1 scanner core.
-- Future/inactive purchase objects are discovered but excluded from Auto Buy.

return function(context)
    local CONFIG=context.CONFIG or {}
    local base=tostring(CONFIG.moduleBaseUrl or "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/main/tycoon_modules"):gsub("/+$","")
    local source=game:HttpGet(base.."/scanner_core.lua")
    local chunk,compileError=loadstring(source)
    assert(type(chunk)=="function","scanner_core compile failed: "..tostring(compileError))
    local factory=chunk()
    assert(type(factory)=="function","scanner_core did not return a factory")
    local core=factory(context)
    assert(type(core)=="table" and type(core.scan)=="function","scanner_core initialisation failed")

    local READINESS_KEYS={
        active=true,isactive=true,enabled=true,isenabled=true,
        available=true,isavailable=true,ready=true,isready=true,
        unlocked=true,isunlocked=true,purchasable=true,ispurchasable=true,
        purchaseenabled=true,canpurchase=true,
    }
    local VISIBLE_BUDGET=40

    local function compact(value)
        return tostring(value or ""):lower():gsub("[^%w]","")
    end

    local function falseLike(value)
        if value==false then return true end
        if type(value)=="number" then return value==0 end
        if type(value)=="string" then
            local key=compact(value)
            return key=="false" or key=="no" or key=="off" or key=="disabled"
                or key=="locked" or key=="unavailable" or key=="notready"
        end
        return false
    end

    local function guiVisible(object,stopAt)
        local current=object
        local depth=0
        while current and depth<12 do
            if current:IsA("GuiObject") and current.Visible==false then return false end
            if (current:IsA("ScreenGui") or current:IsA("BillboardGui") or current:IsA("SurfaceGui")) and current.Enabled==false then return false end
            if current==stopAt then break end
            current=current.Parent
            depth=depth+1
        end
        return true
    end

    local function explicitInactive(object)
        if not object then return nil end
        local ok,attrs=pcall(function() return object:GetAttributes() end)
        if ok and type(attrs)=="table" then
            for name,value in pairs(attrs) do
                if READINESS_KEYS[compact(name)] and falseLike(value) then
                    return "inactive-attr:"..tostring(name)
                end
            end
        end
        for _,child in ipairs(object:GetChildren()) do
            if READINESS_KEYS[compact(child.Name)] and child:IsA("BoolValue") and child.Value==false then
                return "inactive-value:"..tostring(child.Name)
            end
        end
        return nil
    end

    local function purchaseText(text)
        text=tostring(text or "")
        local lower=text:lower()
        if text:find("$",1,true) or text:find("£",1,true) or text:find("€",1,true) or text:find("¥",1,true) then return true end
        if lower:find("buy",1,true) or lower:find("purchase",1,true) or lower:find("price",1,true) or lower:find("cost",1,true) then return true end
        return false
    end

    local function visiblePurchaseCue(button)
        local sourceObject=button and button.priceSource
        if sourceObject and sourceObject.Parent and (sourceObject:IsA("TextLabel") or sourceObject:IsA("TextButton") or sourceObject:IsA("TextBox")) then
            if guiVisible(sourceObject,button.object) and tostring(sourceObject.Text or "")~="" then return true end
        end

        if button and button.prompt and button.prompt.Parent and button.prompt.Enabled~=false then
            if tostring(button.prompt.ActionText or "")~="" or tostring(button.prompt.ObjectText or "")~="" then return true end
        end

        local origin=button and button.object
        if not origin or not origin.Parent then return false end
        local queue={origin}
        local cursor=1
        local inspected=0
        while cursor<=#queue and inspected<VISIBLE_BUDGET do
            local current=queue[cursor]
            cursor=cursor+1
            inspected=inspected+1
            if current:IsA("TextLabel") or current:IsA("TextButton") then
                if guiVisible(current,origin) and purchaseText(current.Text) then return true end
            end
            for _,child in ipairs(current:GetChildren()) do
                if #queue<VISIBLE_BUDGET*2 then table.insert(queue,child) end
            end
        end
        return false
    end

    local function hostCompletelyHidden(button)
        local origin=button and button.object
        if not origin or not origin.Parent then return false end
        local queue={origin}
        local cursor=1
        local inspected=0
        local sawPart=false
        while cursor<=#queue and inspected<VISIBLE_BUDGET do
            local current=queue[cursor]
            cursor=cursor+1
            inspected=inspected+1
            if current:IsA("BasePart") then
                sawPart=true
                if current.Transparency<0.985 then return false end
            end
            for _,child in ipairs(current:GetChildren()) do
                if #queue<VISIBLE_BUDGET*2 then table.insert(queue,child) end
            end
        end
        return sawPart
    end

    local function readiness(button)
        if not button or not button.object or not button.object.Parent then return false,"missing-object" end

        if button.prompt and button.prompt.Parent then
            if button.prompt.Enabled==false then return false,"prompt-disabled" end
            if tonumber(button.prompt.MaxActivationDistance) and button.prompt.MaxActivationDistance<=0 then return false,"prompt-range-zero" end
        elseif button.clickDetector and button.clickDetector.Parent then
            if tonumber(button.clickDetector.MaxActivationDistance) and button.clickDetector.MaxActivationDistance<=0 then return false,"click-range-zero" end
        elseif button.touchPart and button.touchPart.Parent then
            if button.touchPart.CanTouch==false then return false,"touch-disabled" end
        else
            return false,"activation-unavailable"
        end

        for _,object in ipairs({button.activation,button.touchPart,button.part,button.object}) do
            local reason=explicitInactive(object)
            if reason then return false,reason end
        end

        local priceSource=button.priceSource
        if priceSource and priceSource.Parent and (priceSource:IsA("TextLabel") or priceSource:IsA("TextButton") or priceSource:IsA("TextBox")) then
            if not guiVisible(priceSource,button.object) then return false,"price-ui-hidden" end
        end

        local cue=visiblePurchaseCue(button)
        local touchPart=button.touchPart or button.part
        if touchPart and touchPart:IsA("BasePart") and touchPart.Transparency>=0.985 and not cue then
            return false,"hidden-touch-no-cue"
        end
        if hostCompletelyHidden(button) and not cue then
            return false,"hidden-host-no-cue"
        end

        return true,"ready"
    end

    local function filter(data)
        if type(data)~="table" then return data end
        local kept={}
        local skipped=0
        local reasons={}
        for _,button in ipairs(data.buttons or {}) do
            local ready,reason=readiness(button)
            button.ready=ready
            button.readinessReason=reason
            if ready then
                table.insert(kept,button)
            else
                skipped=skipped+1
                reasons[reason]=(reasons[reason] or 0)+1
            end
        end
        data.buttons=kept
        data.notReadyCount=skipped
        data.notReadyReasons=reasons

        local affordable,locked=0,0
        for _,button in ipairs(kept) do
            if button.affordable then affordable=affordable+1 elseif button.locked then locked=locked+1 end
        end
        data.totalButtons=#kept
        data.affordableCount=affordable
        data.lockedCount=locked
        data.debug=data.debug or {}
        data.debug.moduleVersion="4.2"
        data.debug.notReadySkipped=skipped
        data.debug.notReadyReasons=reasons
        return data
    end

    local function scan()
        return filter(core.scan())
    end

    local function invalidateRoot(root)
        if type(core.invalidateRoot)=="function" then return core.invalidateRoot(root) end
    end

    return {
        scan=scan,
        invalidateRoot=invalidateRoot,
        parseCompactNumber=core.parseCompactNumber,
        moduleVersion="4.2",
    }
end
