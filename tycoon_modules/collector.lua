-- 0xVyrs Tycoon interaction worker v4.2
-- Adaptive confirmation, late-apply detection and structured proximity outcomes.

return function(context)
    local CONFIG=context.CONFIG or {}
    local actorIndexes=setmetatable({}, {__mode="k"})
    local collectCooldowns=setmetatable({}, {__mode="k"})
    local noclipStates=setmetatable({}, {__mode="k"})
    local collectCursor=1

    local COLLECT_COOLDOWN=0.8
    local APPROACH_DISTANCE=5.0
    local APPROACH_MAX_DISTANCE=140
    local APPROACH_TIMEOUT=4.5
    local LATE_CONFIRM_WINDOW=0.85
    local EVIDENCE_BUDGET=36
    local SIGNATURE_BUDGET=40
    local PURCHASE_ACTORS={"HumanoidRootPart","LeftFoot","RightFoot","LeftLowerLeg","RightLowerLeg","Left Leg","Right Leg","LowerTorso","Torso","Head"}
    local COLLECT_ACTORS={"LeftFoot","RightFoot","LeftLowerLeg","RightLowerLeg","Left Leg","Right Leg","LowerTorso","Torso","HumanoidRootPart"}

    local diagnostics={
        moduleVersion="4.2",
        collectAttempts=0,collectActivations=0,collectCashConfirmed=0,collectFailures=0,
        purchaseDispatches=0,purchaseSuccesses=0,purchaseFailures=0,purchaseDeferred=0,purchaseBlocked=0,
        physicalApproaches=0,approachSuccesses=0,approachDeferred=0,approachFailures=0,
        lateConfirmations=0,launchGuards=0,noclipApplied=0,
        lastPurchaseReason=nil,lastPurchaseName=nil,lastPurchasePrice=nil,lastPurchaseCash=nil,
        lastPurchaseDistance=nil,lastPurchaseActor=nil,lastPurchaseKind=nil,lastBlockEvidence=nil,
        lastConfirmWindow=nil,lastApproachStartDistance=nil,lastApproachBestDistance=nil,
    }

    local function lower(v) return tostring(v or ""):lower() end
    local function compact(v) return lower(v):gsub("[^%w]","") end
    local function waitStep(seconds)
        if task and task.wait then task.wait(seconds or 0) else wait(seconds or 0) end
    end
    local function result(status,reason,attempted,extra)
        local out={status=status,reason=reason,attempted=attempted==true}
        for key,value in pairs(extra or {}) do out[key]=value end
        return status=="success",out
    end
    local function markCurrency(kind,amount)
        local env=context.SHARED_ENV
        local callback=env and env.__VYRS_TYCOON_CURRENCY_MARK
        if type(callback)=="function" then pcall(callback,kind,amount) end
    end

    -- Instance names alone are never commercial evidence. Only user-facing
    -- paid wording, paid IDs or truthy paid metadata can block an interaction.
    local function paidText(value)
        local text=lower(value)
        if text=="" then return false end
        if text:find("rbxasset",1,true) or text:find("rbxthumb",1,true) then return false end
        return text:find("robux",1,true)~=nil
            or text:find("gamepass",1,true)~=nil
            or text:find("game pass",1,true)~=nil
            or text:find("developer product",1,true)~=nil
            or text:find("dev product",1,true)~=nil
            or text:find("watch ad",1,true)~=nil
            or text:find("watch video",1,true)~=nil
            or text:find("rewarded ad",1,true)~=nil
            or text:find("rewarded video",1,true)~=nil
            or text:find("premium purchase",1,true)~=nil
            or text:find("premium only",1,true)~=nil
            or text:match("%f[%w]r%$%s*%d")~=nil
    end
    local function truthyPaid(value)
        if value==true then return true end
        if type(value)=="number" then return value>0 end
        if type(value)=="string" then
            local key=compact(value)
            return key=="true" or key=="yes" or key=="paid" or key=="premium" or key=="robux"
        end
        return false
    end
    local function paidKey(name)
        local key=compact(name)
        return key=="gamepass" or key=="gamepassid" or key=="productid" or key=="developerproductid"
            or key=="devproductid" or key=="paid" or key=="robux" or key=="premiumonly"
            or key=="purchasecurrency" or key=="paymenttype"
    end
    local function metadataEvidence(object)
        if not object then return nil end
        if object:IsA("ProximityPrompt") then
            if object.Enabled~=false and paidText(object.ActionText) then return "prompt-action:"..tostring(object.ActionText) end
            if object.Enabled~=false and paidText(object.ObjectText) then return "prompt-object:"..tostring(object.ObjectText) end
        elseif object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
            if object.Visible~=false and paidText(object.Text) then return "visible-text:"..tostring(object.Text) end
        elseif object:IsA("IntValue") or object:IsA("NumberValue") or object:IsA("StringValue") or object:IsA("BoolValue") then
            local key=compact(object.Name)
            local ok,value=pcall(function() return object.Value end)
            if ok then
                if (key=="gamepassid" or key=="productid" or key=="developerproductid" or key=="devproductid") and tonumber(value) and tonumber(value)>0 then
                    return "value:"..object.Name.."="..tostring(value)
                end
                if (key=="gamepass" or key=="paid" or key=="robux" or key=="premiumonly") and truthyPaid(value) then
                    return "value:"..object.Name.."="..tostring(value)
                end
                if paidKey(key) and type(value)=="string" and paidText(value) then return "value:"..object.Name.."="..value end
            end
        end
        local ok,attributes=pcall(function() return object:GetAttributes() end)
        if ok and type(attributes)=="table" then
            for key,value in pairs(attributes) do
                local normal=compact(key)
                if (normal=="gamepassid" or normal=="productid" or normal=="developerproductid" or normal=="devproductid") and tonumber(value) and tonumber(value)>0 then
                    return "attr:"..tostring(key).."="..tostring(value)
                end
                if (normal=="gamepass" or normal=="paid" or normal=="robux" or normal=="premiumonly") and truthyPaid(value) then
                    return "attr:"..tostring(key).."="..tostring(value)
                end
                if paidKey(normal) and type(value)=="string" and paidText(value) then return "attr:"..tostring(key).."="..value end
            end
        end
        return nil
    end
    local function paidEvidence(button)
        if not button then return "missing-button" end
        if button.paidPurchase==true then return "scanner:paidPurchase" end
        local checked={}
        local function inspect(object)
            if not object or checked[object] then return nil end
            checked[object]=true
            return metadataEvidence(object)
        end
        for _,object in ipairs({button.activation,button.prompt,button.clickDetector,button.touchPart,button.part,button.object}) do
            local evidence=inspect(object)
            if evidence then return evidence end
        end
        local origin=button.object
        if not origin or not origin.Parent then return nil end
        local queue={origin}
        local cursor=1
        local visited=0
        while cursor<=#queue and visited<EVIDENCE_BUDGET do
            local current=queue[cursor]
            cursor=cursor+1
            for _,child in ipairs(current:GetChildren()) do
                visited=visited+1
                local evidence=inspect(child)
                if evidence then return evidence end
                if visited<EVIDENCE_BUDGET and #child:GetChildren()>0 then table.insert(queue,child) end
                if visited>=EVIDENCE_BUDGET then break end
            end
        end
        return nil
    end

    local function firePrompt(prompt)
        if not prompt or not prompt.Parent or type(fireproximityprompt)~="function" then return false end
        return pcall(function() fireproximityprompt(prompt) end)
    end
    local function fireClick(click)
        if not click or not click.Parent or type(fireclickdetector)~="function" then return false end
        return pcall(function() fireclickdetector(click) end)
    end
    local function fireTouch(actor,target)
        if not actor or not actor.Parent or not target or not target.Parent or type(firetouchinterest)~="function" then return false end
        return pcall(function()
            firetouchinterest(actor,target,0)
            waitStep(0.05)
            firetouchinterest(actor,target,1)
        end)
    end

    local function setCollectorNoClip(target)
        if not target or not target.Parent or not target:IsA("BasePart") then return end
        local size=target.Size
        if size.X>50 or size.Z>50 or size.Y>12 then return end
        if not noclipStates[target] then noclipStates[target]={original=target.CanCollide} end
        if target.CanCollide then
            pcall(function() target.CanCollide=false end)
            diagnostics.noclipApplied=diagnostics.noclipApplied+1
        end
    end
    local function guardCharacter(root,beforeCFrame,beforeLinear,beforeAngular)
        if not root or not root.Parent then return end
        local current=root.AssemblyLinearVelocity
        local launched=current.Y>math.max(42,beforeLinear.Y+24) or current.Magnitude>beforeLinear.Magnitude+70
        if not launched then return end
        diagnostics.launchGuards=diagnostics.launchGuards+1
        pcall(function()
            if root.Position.Y-beforeCFrame.Position.Y>6 then root.CFrame=beforeCFrame end
            root.AssemblyLinearVelocity=beforeLinear
            root.AssemblyAngularVelocity=beforeAngular
        end)
    end

    local function activationAlive(entry)
        return (entry.prompt and entry.prompt.Parent) or (entry.clickDetector and entry.clickDetector.Parent) or (entry.touchPart and entry.touchPart.Parent)
    end
    local function refreshInteraction(entry)
        if not entry or not entry.object or not entry.object.Parent then return false end
        if activationAlive(entry) then return true end
        entry.prompt=nil; entry.clickDetector=nil; entry.touchPart=nil; entry.activation=nil
        local queue={entry.object}
        local cursor=1
        local inspected=0
        while cursor<=#queue and inspected<56 do
            local current=queue[cursor]
            cursor=cursor+1
            if current:IsA("ProximityPrompt") and not entry.prompt then entry.prompt=current; entry.activation=current
            elseif current:IsA("ClickDetector") and not entry.clickDetector then entry.clickDetector=current; entry.activation=current
            elseif current:IsA("TouchTransmitter") and current.Parent and current.Parent:IsA("BasePart") and not entry.touchPart then entry.touchPart=current.Parent; entry.activation=current end
            if activationAlive(entry) then return true end
            for _,child in ipairs(current:GetChildren()) do
                inspected=inspected+1
                if inspected<=56 then table.insert(queue,child) end
                if inspected>=56 then break end
            end
        end
        return false
    end

    local function purchaseKind(button)
        if button and button.prompt and button.prompt.Parent then return "prompt" end
        if button and button.clickDetector and button.clickDetector.Parent then return "click" end
        if button and button.touchPart and button.touchPart.Parent then return "touch" end
        return "none"
    end
    local function purchasePart(button)
        if not button then return nil end
        if button.touchPart and button.touchPart.Parent then return button.touchPart end
        if button.part and button.part.Parent then return button.part end
        if button.prompt and button.prompt.Parent then
            local parent=button.prompt.Parent
            if parent:IsA("BasePart") then return parent end
            if parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then return parent.Parent end
        end
        if button.clickDetector and button.clickDetector.Parent and button.clickDetector.Parent:IsA("BasePart") then return button.clickDetector.Parent end
        return nil
    end
    local function purchaseDistance(root,button)
        local part=purchasePart(button)
        return root and part and (part.Position-root.Position).Magnitude or nil
    end
    local function confirmationTimeout(kind,distance,nearPhase)
        if kind=="prompt" then return nearPhase and 1.05 or 0.8 end
        if kind=="click" then return nearPhase and 1.15 or 0.9 end
        if kind=="touch" then
            if nearPhase then return 1.65 end
            distance=tonumber(distance) or math.huge
            if distance<=8 then return 1.45 end
            if distance<=35 then return 1.15 end
            return 0.85
        end
        return 0.7
    end

    local function priceLikeName(value)
        local key=compact(value)
        return key:find("price",1,true) or key:find("cost",1,true) or key:find("amount",1,true) or key:find("required",1,true)
    end
    local function focusedSignature(button)
        local origin=button and button.object
        if not origin or not origin.Parent then return nil end
        local pieces={"name="..tostring(origin.Name)}
        if button.prompt and button.prompt.Parent then table.insert(pieces,"prompt="..tostring(button.prompt.ActionText).."|"..tostring(button.prompt.ObjectText)) end
        local queue={origin}
        local cursor=1
        local inspected=0
        while cursor<=#queue and inspected<SIGNATURE_BUDGET do
            local current=queue[cursor]
            cursor=cursor+1
            inspected=inspected+1
            if current:IsA("TextLabel") or current:IsA("TextButton") then
                local text=tostring(current.Text or "")
                if priceLikeName(current.Name) or text:find("$",1,true) or text:find("£",1,true) or text:find("€",1,true) or text:find("¥",1,true) then table.insert(pieces,current.Name.."="..text) end
            elseif current:IsA("IntValue") or current:IsA("NumberValue") or current:IsA("StringValue") then
                if priceLikeName(current.Name) then table.insert(pieces,current.Name.."="..tostring(current.Value)) end
            end
            for _,child in ipairs(current:GetChildren()) do if #queue<SIGNATURE_BUDGET*2 then table.insert(queue,child) end end
        end
        table.sort(pieces)
        return table.concat(pieces,"\31")
    end
    local function purchasedAncestor(object)
        local current=object and object.Parent
        while current and current~=workspace do
            local name=compact(current.Name)
            if name=="purchased" or name=="purchasedobjects" or name=="bought" or name=="owneditems" then return true end
            current=current.Parent
        end
        return false
    end
    local function capture(button)
        return {object=button.object,parent=button.object and button.object.Parent or nil,activation=button.activation,cash=tonumber(context.getCash()),price=math.max(0,tonumber(button.price) or 0),signature=focusedSignature(button)}
    end
    local function applied(button,before)
        local object=before.object
        if not object or not object.Parent then return true,"object-gone" end
        if purchasedAncestor(object) then return true,"moved-to-owned" end
        if before.parent and object.Parent~=before.parent then return true,"reparented" end
        if before.activation and not before.activation.Parent then return true,"activation-gone" end
        if before.signature then
            local currentSignature=focusedSignature(button)
            if currentSignature and currentSignature~=before.signature then return true,"pad-changed" end
        end
        local nowCash=tonumber(context.getCash())
        if before.cash and nowCash and before.price>0 then
            local spent=before.cash-nowCash
            local tolerance=math.max(3,before.price*0.55)
            if spent>0 and (math.abs(spent-before.price)<=tolerance or spent>=before.price*0.75) then return true,"cash-spend-matched" end
        end
        return false,nil
    end
    local function verify(button,before,timeout)
        diagnostics.lastConfirmWindow=timeout
        local deadline=os.clock()+math.max(0.05,timeout or 0.8)
        repeat
            local success,reason=applied(button,before)
            if success then return true,reason end
            waitStep(0.06)
        until os.clock()>=deadline
        return applied(button,before)
    end
    local function lateVerify(button,before)
        local success,reason=verify(button,before,LATE_CONFIRM_WINDOW)
        if success then diagnostics.lateConfirmations=diagnostics.lateConfirmations+1 return true,"late-"..tostring(reason or "confirmed") end
        return false,nil
    end

    local function actorList(root,names)
        local list={}
        local seen={}
        local character=context.LOCAL_PLAYER and context.LOCAL_PLAYER.Character
        local function add(part)
            if part and part.Parent and part:IsA("BasePart") and not seen[part] then seen[part]=true; table.insert(list,part) end
        end
        if character then for _,name in ipairs(names) do add(character:FindFirstChild(name)) end end
        add(root)
        return list
    end
    local function activate(button,root)
        if button.prompt and button.prompt.Parent then diagnostics.lastPurchaseActor="ProximityPrompt" return firePrompt(button.prompt) end
        if button.clickDetector and button.clickDetector.Parent then diagnostics.lastPurchaseActor="ClickDetector" return fireClick(button.clickDetector) end
        local target=button.touchPart
        if not target or not target.Parent then return false end
        local actors=actorList(root,PURCHASE_ACTORS)
        if #actors==0 then return false end
        local key=button.activation or button.object or target
        local index=actorIndexes[key] or 1
        if index>#actors then index=1 end
        local actor=actors[index]
        actorIndexes[key]=(index%#actors)+1
        diagnostics.lastPurchaseActor=actor.Name
        return fireTouch(actor,target)
    end

    local function approach(button,before)
        if CONFIG.autopilotEnabled~=true then return false,"autopilot-disabled",false end
        local character=context.LOCAL_PLAYER and context.LOCAL_PLAYER.Character
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        local root=context.getLocalRoot()
        local target=purchasePart(button)
        if not humanoid or humanoid.Health<=0 or not root or not target then return false,"approach-unavailable",false end
        local distance=(target.Position-root.Position).Magnitude
        diagnostics.lastApproachStartDistance=distance
        diagnostics.lastApproachBestDistance=distance
        if distance<=APPROACH_DISTANCE then return false,"already-near",false end
        if distance>APPROACH_MAX_DISTANCE then return false,"too-far",false end
        if humanoid.MoveDirection.Magnitude>0.15 then return false,"player-moving",false end

        diagnostics.physicalApproaches=diagnostics.physicalApproaches+1
        diagnostics.lastPurchaseActor="Humanoid.MoveTo"
        pcall(function() humanoid:MoveTo(target.Position) end)
        local deadline=os.clock()+math.min(APPROACH_TIMEOUT,1.25+distance/11)
        local bestDistance=distance
        repeat
            local success,reason=applied(button,before)
            if success then diagnostics.approachSuccesses=diagnostics.approachSuccesses+1 return true,reason,true end
            if not root.Parent or not target.Parent or humanoid.Health<=0 then break end
            local currentDistance=(target.Position-root.Position).Magnitude
            bestDistance=math.min(bestDistance,currentDistance)
            diagnostics.lastApproachBestDistance=bestDistance
            if currentDistance<=APPROACH_DISTANCE then break end
            waitStep(0.08)
        until os.clock()>=deadline

        if root.Parent and target.Parent then
            local currentDistance=(target.Position-root.Position).Magnitude
            diagnostics.lastApproachBestDistance=math.min(bestDistance,currentDistance)
            if currentDistance<=APPROACH_DISTANCE then
                local fired=activate(button,root)
                if fired then
                    local success,reason=verify(button,before,confirmationTimeout(purchaseKind(button),currentDistance,true))
                    if success then diagnostics.approachSuccesses=diagnostics.approachSuccesses+1 return true,reason,true end
                    success,reason=lateVerify(button,before)
                    if success then diagnostics.approachSuccesses=diagnostics.approachSuccesses+1 return true,reason,true end
                    diagnostics.approachFailures=diagnostics.approachFailures+1
                    return false,"proximity-not-confirmed",true
                end
                diagnostics.approachFailures=diagnostics.approachFailures+1
                return false,"activation-unavailable",false
            end
        end

        -- Failing to physically reach a pad is not evidence that its purchase
        -- interaction is incompatible. Let the runtime retry/choose another target.
        diagnostics.approachDeferred=diagnostics.approachDeferred+1
        return false,"approach-stalled",false
    end

    local function buyButton(_,button)
        diagnostics.lastPurchaseReason=nil
        diagnostics.lastBlockEvidence=nil
        diagnostics.lastPurchaseName=button and (button.name or (button.object and button.object.Name)) or "?"
        diagnostics.lastPurchasePrice=tonumber(button and button.price)
        diagnostics.lastPurchaseCash=tonumber(context.getCash())
        diagnostics.lastPurchaseActor=nil
        diagnostics.lastPurchaseKind=purchaseKind(button)
        diagnostics.lastPurchaseDistance=nil
        diagnostics.lastConfirmWindow=nil
        diagnostics.lastApproachStartDistance=nil
        diagnostics.lastApproachBestDistance=nil

        if not button or button.automationAllowed~=true then diagnostics.purchaseDeferred=diagnostics.purchaseDeferred+1 diagnostics.lastPurchaseReason="not-authorised" return result("deferred","not-authorised",false) end
        local evidence=paidEvidence(button)
        if evidence then diagnostics.purchaseBlocked=diagnostics.purchaseBlocked+1 diagnostics.lastPurchaseReason="blocked-paid-context" diagnostics.lastBlockEvidence=evidence return result("blocked","blocked-paid-context",false,{evidence=evidence}) end
        if not refreshInteraction(button) then diagnostics.purchaseFailures=diagnostics.purchaseFailures+1 diagnostics.lastPurchaseReason="stale-interaction" return result("failed","stale-interaction",false) end

        local cash=tonumber(context.getCash())
        local price=math.max(0,tonumber(button.price) or 0)
        if cash==nil and price>0 then diagnostics.purchaseDeferred=diagnostics.purchaseDeferred+1 diagnostics.lastPurchaseReason="cash-unresolved" return result("deferred","cash-unresolved",false) end
        if cash~=nil and price>cash then diagnostics.purchaseDeferred=diagnostics.purchaseDeferred+1 diagnostics.lastPurchaseReason="unaffordable" return result("deferred","unaffordable",false) end
        local root=context.getLocalRoot()
        if not root then diagnostics.purchaseDeferred=diagnostics.purchaseDeferred+1 diagnostics.lastPurchaseReason="character-unavailable" return result("deferred","character-unavailable",false) end

        diagnostics.purchaseDispatches=diagnostics.purchaseDispatches+1
        local distance=purchaseDistance(root,button)
        diagnostics.lastPurchaseDistance=distance
        local kind=purchaseKind(button)
        diagnostics.lastPurchaseKind=kind
        markCurrency("buy",price)
        local before=capture(button)
        local fired=activate(button,root)
        if fired then
            local success,reason=verify(button,before,confirmationTimeout(kind,distance,false))
            if success then diagnostics.purchaseSuccesses=diagnostics.purchaseSuccesses+1 diagnostics.lastPurchaseReason=reason or "confirmed" return result("success",reason or "confirmed",true) end
        end

        distance=purchaseDistance(root,button)
        if distance and distance>APPROACH_DISTANCE then
            local success,reason,attempted=approach(button,before)
            if success then diagnostics.purchaseSuccesses=diagnostics.purchaseSuccesses+1 diagnostics.lastPurchaseReason=reason or "confirmed" return result("success",reason or "confirmed",true) end
            if reason=="player-moving" or reason=="autopilot-disabled" or reason=="too-far" or reason=="approach-unavailable" or reason=="approach-stalled" then
                diagnostics.purchaseDeferred=diagnostics.purchaseDeferred+1
                diagnostics.lastPurchaseReason=reason
                return result("deferred",reason,fired==true,{approached=attempted==true})
            end
            diagnostics.lastPurchaseReason=reason
            diagnostics.purchaseFailures=diagnostics.purchaseFailures+1
            return result("failed",reason or "proximity-not-confirmed",attempted==true or fired==true)
        end

        if fired then
            local success,reason=lateVerify(button,before)
            if success then diagnostics.purchaseSuccesses=diagnostics.purchaseSuccesses+1 diagnostics.lastPurchaseReason=reason return result("success",reason,true) end
            diagnostics.lastPurchaseReason="not-confirmed"
        else
            diagnostics.lastPurchaseReason="activation-unavailable"
        end
        diagnostics.purchaseFailures=diagnostics.purchaseFailures+1
        return result("failed",diagnostics.lastPurchaseReason,fired==true)
    end

    local function collectActor(root)
        local list=actorList(root,COLLECT_ACTORS)
        return list[1] or root
    end
    local function collectorTouch(root,target)
        if not root or not target then return false end
        setCollectorNoClip(target)
        local beforeCFrame=root.CFrame
        local beforeLinear=root.AssemblyLinearVelocity
        local beforeAngular=root.AssemblyAngularVelocity
        local actor=collectActor(root)
        local ok=fireTouch(actor,target)
        guardCharacter(root,beforeCFrame,beforeLinear,beforeAngular)
        if task and task.delay then
            task.delay(0.08,function() guardCharacter(root,beforeCFrame,beforeLinear,beforeAngular) end)
            task.delay(0.2,function() guardCharacter(root,beforeCFrame,beforeLinear,beforeAngular) end)
        end
        return ok
    end
    local function collectNearby(_,data)
        if not data or data.automationAllowed~=true or not data.drops or #data.drops==0 then return 0 end
        local root=context.getLocalRoot()
        if not root then return 0 end
        local total=#data.drops
        if collectCursor>total then collectCursor=1 end
        local now=os.clock()
        local checked=0
        local index=collectCursor
        while checked<total do
            local drop=data.drops[index]
            checked=checked+1
            index=(index%total)+1
            if drop and drop.object and drop.object.Parent and refreshInteraction(drop) then
                local key=drop.activation or drop.touchPart or drop.prompt or drop.clickDetector or drop.object
                if now>=(collectCooldowns[key] or 0) then
                    diagnostics.collectAttempts=diagnostics.collectAttempts+1
                    local before=tonumber(context.getCash())
                    markCurrency("collect")
                    local ok=false
                    if drop.prompt and drop.prompt.Parent then ok=firePrompt(drop.prompt)
                    elseif drop.clickDetector and drop.clickDetector.Parent then ok=fireClick(drop.clickDetector)
                    elseif drop.touchPart and drop.touchPart.Parent then ok=collectorTouch(root,drop.touchPart) end
                    collectCooldowns[key]=now+COLLECT_COOLDOWN
                    if ok then
                        diagnostics.collectActivations=diagnostics.collectActivations+1
                        waitStep(0.16)
                        local after=tonumber(context.getCash())
                        if before and after and after>before then diagnostics.collectCashConfirmed=diagnostics.collectCashConfirmed+1 end
                        collectCursor=index
                        return 1
                    end
                    diagnostics.collectFailures=diagnostics.collectFailures+1
                    collectCursor=index
                    return 0
                end
            end
        end
        collectCursor=index
        return 0
    end

    local function cleanup()
        for part,state in pairs(noclipStates) do
            if part and part.Parent and state then pcall(function() part.CanCollide=state.original end) end
            noclipStates[part]=nil
        end
    end
    local function getStatus()
        local copy={}
        for key,value in pairs(diagnostics) do copy[key]=value end
        return copy
    end

    return {moduleVersion="4.2",buyButton=buyButton,collectNearby=collectNearby,getStatus=getStatus,cleanup=cleanup}
end
