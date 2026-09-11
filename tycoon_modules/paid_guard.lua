-- 0xVyrs strict paid-purchase guard v4.3
-- Shared by scanner and collector. Safety-first: ambiguous commercial buttons are skipped.

return function(context)
    local MAX_DESCENDANTS=120
    local MAX_ANCESTORS=8

    local function lower(value) return tostring(value or ""):lower() end
    local function compact(value) return lower(value):gsub("[^%w]","") end

    local function guiVisible(object,stopAt)
        local current=object
        local depth=0
        while current and depth<14 do
            if current:IsA("GuiObject") and current.Visible==false then return false end
            if (current:IsA("ScreenGui") or current:IsA("BillboardGui") or current:IsA("SurfaceGui")) and current.Enabled==false then return false end
            if current==stopAt then break end
            current=current.Parent
            depth=depth+1
        end
        return true
    end

    local function paidText(value)
        local text=lower(value)
        if text=="" then return false end
        if text:find("rbxasset",1,true) or text:find("rbxthumb",1,true) then return false end
        if text:find("robux",1,true) or text:find("gamepass",1,true) or text:find("game pass",1,true)
            or text:find("developer product",1,true) or text:find("dev product",1,true)
            or text:find("premium purchase",1,true) or text:find("premium only",1,true)
            or text:find("buy robux",1,true) or text:find("purchase robux",1,true)
            or text:find("watch ad",1,true) or text:find("rewarded ad",1,true)
            or text:find("watch video",1,true) or text:find("rewarded video",1,true) then
            return true
        end
        if text:find("r$",1,true) then return true end
        if text:match("%f[%a]rbx%f[%A]") then return true end
        return false
    end

    local function ordinaryCashText(value)
        local text=lower(value)
        if text=="" or paidText(text) then return false end
        if text:find("£",1,true) or text:find("€",1,true) or text:find("¥",1,true) then return true end
        if text:find("$",1,true) and not text:find("r$",1,true) then return true end
        if text:find("cash",1,true) or text:find("coins",1,true) or text:find("money",1,true) then return true end
        return false
    end

    local ID_KEYS={
        gamepassid=true,passid=true,developerproductid=true,devproductid=true,
        productid=true,marketplaceid=true,marketplaceproductid=true,
    }
    local FLAG_KEYS={
        gamepass=true,isgamepass=true,developerproduct=true,isdeveloperproduct=true,
        devproduct=true,isdevproduct=true,robux=true,isrobux=true,paid=true,ispaid=true,
        premiumonly=true,requiresrobux=true,robuxpurchase=true,purchasewithrobux=true,
    }
    local TYPE_KEYS={
        purchasecurrency=true,currencytype=true,currencyname=true,currency=true,
        paymenttype=true,purchasetype=true,purchasekind=true,producttype=true,
        monetizationtype=true,monetisationtype=true,purchasemethod=true,itemtype=true,
    }

    local function truthy(value)
        if value==true then return true end
        if type(value)=="number" then return value>0 end
        if type(value)=="string" then
            local key=compact(value)
            return key=="true" or key=="yes" or key=="on" or key=="paid"
                or key=="robux" or key=="gamepass" or key=="developerproduct"
        end
        return false
    end

    local function paidTypeValue(value)
        if type(value)~="string" then return false end
        local key=compact(value)
        return key:find("robux",1,true)~=nil or key:find("gamepass",1,true)~=nil
            or key:find("developerproduct",1,true)~=nil or key:find("devproduct",1,true)~=nil
            or key=="premium" or key=="premiumonly" or key=="marketplace"
    end

    local function weakCommercialName(object)
        if not object then return false end
        local key=compact(object.Name)
        if key=="" then return false end
        return key:find("robux",1,true)~=nil or key:find("gamepass",1,true)~=nil
            or key:find("developerproduct",1,true)~=nil or key:find("devproduct",1,true)~=nil
            or key:find("premium",1,true)~=nil or key:find("monetization",1,true)~=nil
            or key:find("monetisation",1,true)~=nil
    end

    local function inspectMetadata(object)
        if not object then return nil,false,false end
        local cashCue=false
        local weak=weakCommercialName(object)

        if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
            if guiVisible(object,nil) then
                local text=tostring(object.Text or "")
                if paidText(text) then return "visible-paid-text:"..text,cashCue,weak end
                cashCue=ordinaryCashText(text)
            end
        elseif object:IsA("ProximityPrompt") then
            if object.Enabled~=false then
                for _,text in ipairs({object.ActionText,object.ObjectText}) do
                    if paidText(text) then return "prompt-paid-text:"..tostring(text),cashCue,weak end
                    if ordinaryCashText(text) then cashCue=true end
                end
            end
        elseif object:IsA("IntValue") or object:IsA("NumberValue") or object:IsA("StringValue") or object:IsA("BoolValue") then
            local key=compact(object.Name)
            local ok,value=pcall(function() return object.Value end)
            if ok then
                if ID_KEYS[key] and tonumber(value) and tonumber(value)>0 then
                    return "paid-id:"..object.Name.."="..tostring(value),cashCue,weak
                end
                if FLAG_KEYS[key] and truthy(value) then
                    return "paid-flag:"..object.Name.."="..tostring(value),cashCue,weak
                end
                if TYPE_KEYS[key] and paidTypeValue(value) then
                    return "paid-type:"..object.Name.."="..tostring(value),cashCue,weak
                end
                if (key:find("robuxprice",1,true) or key:find("priceinrobux",1,true)) and tonumber(value) and tonumber(value)>0 then
                    return "robux-price:"..object.Name.."="..tostring(value),cashCue,weak
                end
            end
        elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
            if guiVisible(object,nil) and weakCommercialName(object) then weak=true end
        end

        local ok,attrs=pcall(function() return object:GetAttributes() end)
        if ok and type(attrs)=="table" then
            for name,value in pairs(attrs) do
                local key=compact(name)
                if ID_KEYS[key] and tonumber(value) and tonumber(value)>0 then
                    return "paid-id-attr:"..tostring(name).."="..tostring(value),cashCue,weak
                end
                if FLAG_KEYS[key] and truthy(value) then
                    return "paid-flag-attr:"..tostring(name).."="..tostring(value),cashCue,weak
                end
                if TYPE_KEYS[key] and paidTypeValue(value) then
                    return "paid-type-attr:"..tostring(name).."="..tostring(value),cashCue,weak
                end
                if (key:find("robuxprice",1,true) or key:find("priceinrobux",1,true)) and tonumber(value) and tonumber(value)>0 then
                    return "robux-price-attr:"..tostring(name).."="..tostring(value),cashCue,weak
                end
            end
        end
        return nil,cashCue,weak
    end

    local function evidence(button)
        if not button then return "missing-button" end
        if button.paidPurchase==true then return button.paidEvidence or "scanner:paidPurchase" end

        local checked={}
        local weakCount=0
        local cashCue=false
        local function inspect(object)
            if not object or checked[object] then return nil end
            checked[object]=true
            local found,cash,weak=inspectMetadata(object)
            cashCue=cashCue or cash
            if weak then weakCount=weakCount+1 end
            return found
        end

        for _,object in ipairs({button.activation,button.prompt,button.clickDetector,button.touchPart,button.part,button.priceSource,button.object}) do
            local found=inspect(object)
            if found then return found end
        end

        local origin=button.object or button.activation
        local current=origin
        local depth=0
        while current and current~=workspace and depth<MAX_ANCESTORS do
            local found=inspect(current)
            if found then return found end
            if button.root and current==button.root then break end
            current=current.Parent
            depth=depth+1
        end

        if origin and origin.Parent then
            local queue={origin}
            local cursor=1
            local visited=0
            while cursor<=#queue and visited<MAX_DESCENDANTS do
                local node=queue[cursor]
                cursor=cursor+1
                local found=inspect(node)
                if found then return found end
                for _,child in ipairs(node:GetChildren()) do
                    visited=visited+1
                    if visited<=MAX_DESCENDANTS then table.insert(queue,child) end
                    if visited>=MAX_DESCENDANTS then break end
                end
            end
        end

        -- Image-only Robux shops often expose no literal Robux text: a commercial
        -- container/icon plus a plain numeric price. Prefer a false negative on
        -- automation over opening a real-money prompt. A normal cash cue overrides
        -- this weak-name rule (important for tycoons with harmless Gamepass metadata).
        if weakCount>0 and not cashCue and tonumber(button.price)~=nil then
            return "ambiguous-commercial-context"
        end
        return nil
    end

    return {evidence=evidence,moduleVersion="4.3-paid-safe"}
end
