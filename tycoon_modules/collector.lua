-- 0xVyrs universal tycoon interaction worker.
-- Hardening build: bounded interaction work, non-launching collection,
-- purchase verification and a normal-walk fallback for proximity-validated pads.

return function(context)
    local CONFIG=context and context.CONFIG or {}
    local purchaseFailures=setmetatable({}, {__mode="k"})
    local purchaseActorIndexes=setmetatable({}, {__mode="k"})
    local collectCooldowns=setmetatable({}, {__mode="k"})
    local noclipStates=setmetatable({}, {__mode="k"})
    local collectCursor=1

    local COLLECT_COOLDOWN=0.85
    local FAILED_COOLDOWN=1.2
    local CONFIRM_DELAY=0.28
    local VIRTUAL_CONFIRM_TIMEOUT=0.65
    local APPROACH_CONFIRM_TIMEOUT=1.15
    local APPROACH_TRIGGER_DISTANCE=9
    local APPROACH_MAX_DISTANCE=140
    local MAX_BLOCK_INSPECT=28
    local SIGNATURE_INSPECT=48
    local BLOCKED={"watch ad","watch video","video ad","rewarded ad","rewarded video","advertisement","developer product","game pass","gamepass","premium","robux","r$","rbx"}
    local PURCHASE_ACTOR_NAMES={"HumanoidRootPart","LeftFoot","RightFoot","LeftLowerLeg","RightLowerLeg","Left Leg","Right Leg","LowerTorso","Torso","Head"}

    local diagnostics={
        attempts=0,activations=0,cashConfirmed=0,failed=0,unaffordableSkips=0,
        verificationMisses=0,noclipApplied=0,launchGuards=0,staleRefreshes=0,
        purchaseActivations=0,purchaseSuccesses=0,purchaseFailures=0,purchaseActorRetries=0,
        physicalApproaches=0,approachSuccesses=0,approachFailures=0,
        lastPurchaseReason=nil,lastPurchaseName=nil,lastPurchasePrice=nil,lastPurchaseCash=nil,
        lastPurchaseDistance=nil,lastPurchaseActor=nil,lastPurchaseKind=nil,
    }

    local function lower(v) return tostring(v or ""):lower() end
    local function waitStep(seconds)
        if task and task.wait then task.wait(seconds or 0) else wait(seconds or 0) end
    end
    local function currencyMark(kind,amount)
        local env=context and context.SHARED_ENV
        local fn=env and env.__VYRS_TYCOON_CURRENCY_MARK
        if type(fn)=="function" then pcall(fn,kind,amount) end
    end
    local function blockedText(v)
        local text=lower(v)
        for _,phrase in ipairs(BLOCKED) do if text:find(phrase,1,true) then return true end end
        local tokens=" "..text:gsub("[^%w]+"," ").." "
        return tokens:find(" ad ",1,true)~=nil or tokens:find(" ads ",1,true)~=nil
    end
    local function instanceBlocked(o)
        if not o then return false end
        if blockedText(o.Name) then return true end
        if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
            if blockedText(o.Text) then return true end
        elseif o:IsA("ProximityPrompt") then
            if blockedText(o.ActionText) or blockedText(o.ObjectText) then return true end
        end
        local ok,a=pcall(function() return o:GetAttributes() end)
        if ok and type(a)=="table" then
            for key,value in pairs(a) do
                if blockedText(key) or (type(value)=="string" and blockedText(value)) then return true end
            end
        end
        return false
    end
    local function purchaseBlocked(button)
        if not button or button.paidPurchase then return true end
        local object=button.object
        if not object or not object.Parent or instanceBlocked(object) then return true end
        local queue={object}; local cursor=1; local inspected=0
        while cursor<=#queue and inspected<MAX_BLOCK_INSPECT do
            local current=queue[cursor]; cursor=cursor+1
            for _,child in ipairs(current:GetChildren()) do
                inspected=inspected+1
                if instanceBlocked(child) then return true end
                if inspected<MAX_BLOCK_INSPECT and #child:GetChildren()>0 then table.insert(queue,child) end
                if inspected>=MAX_BLOCK_INSPECT then break end
            end
        end
        local parent=object.Parent
        return parent and parent~=workspace and instanceBlocked(parent) or false
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
            waitStep(0.045)
            firetouchinterest(actor,target,1)
        end)
    end

    local function setCollectorNoClip(target)
        if not target or not target.Parent or not target:IsA("BasePart") then return end
        local size=target.Size
        if size.X>50 or size.Z>50 or size.Y>12 then return end
        local state=noclipStates[target]
        if not state then state={original=target.CanCollide}; noclipStates[target]=state end
        if target.CanCollide then
            pcall(function() target.CanCollide=false end)
            diagnostics.noclipApplied=diagnostics.noclipApplied+1
        end
    end
    local function guardCharacter(root,beforeCFrame,beforeLinear,beforeAngular)
        if not root or not root.Parent then return end
        local current=root.AssemblyLinearVelocity
        local vertical=current.Y>math.max(42,beforeLinear.Y+24)
        local magnitude=current.Magnitude>beforeLinear.Magnitude+70
        if not vertical and not magnitude then return end
        diagnostics.launchGuards=diagnostics.launchGuards+1
        pcall(function()
            if root.Position.Y-beforeCFrame.Position.Y>6 then root.CFrame=beforeCFrame end
            root.AssemblyLinearVelocity=beforeLinear
            root.AssemblyAngularVelocity=beforeAngular
        end)
    end
    local function touchRoot(root,target,isCollector)
        if not root or not root.Parent or not target or not target.Parent then return false end
        if isCollector then setCollectorNoClip(target) end
        local beforeCFrame=root.CFrame
        local beforeLinear=root.AssemblyLinearVelocity
        local beforeAngular=root.AssemblyAngularVelocity
        local ok=fireTouch(root,target)
        if isCollector then
            guardCharacter(root,beforeCFrame,beforeLinear,beforeAngular)
            if task and task.delay then
                task.delay(0.08,function() guardCharacter(root,beforeCFrame,beforeLinear,beforeAngular) end)
                task.delay(0.22,function() guardCharacter(root,beforeCFrame,beforeLinear,beforeAngular) end)
            end
        end
        return ok
    end

    local function activationAlive(entry)
        return (entry.prompt and entry.prompt.Parent) or (entry.clickDetector and entry.clickDetector.Parent) or (entry.touchPart and entry.touchPart.Parent)
    end
    local function refreshInteraction(entry)
        if not entry or not entry.object or not entry.object.Parent then return false end
        if activationAlive(entry) then return true end
        entry.prompt=nil; entry.clickDetector=nil; entry.touchPart=nil
        local queue={entry.object}; local cursor=1; local inspected=0
        while cursor<=#queue and inspected<40 do
            local current=queue[cursor]; cursor=cursor+1
            if current:IsA("ProximityPrompt") and not entry.prompt then entry.prompt=current
            elseif current:IsA("ClickDetector") and not entry.clickDetector then entry.clickDetector=current
            elseif current:IsA("TouchTransmitter") and current.Parent and current.Parent:IsA("BasePart") and not entry.touchPart then entry.touchPart=current.Parent end
            if activationAlive(entry) then diagnostics.staleRefreshes=diagnostics.staleRefreshes+1; return true end
            for _,child in ipairs(current:GetChildren()) do
                inspected=inspected+1
                if inspected<=40 then table.insert(queue,child) end
                if inspected>=40 then break end
            end
        end
        return false
    end

    local function activateCollection(entry,root)
        if entry.prompt and entry.prompt.Parent then return firePrompt(entry.prompt) end
        if entry.clickDetector and entry.clickDetector.Parent then return fireClick(entry.clickDetector) end
        if entry.touchPart and entry.touchPart.Parent then return touchRoot(root,entry.touchPart,true) end
        return false
    end
    local function collectNearby(scanContext,data)
        if not data or data.automationAllowed~=true or not data.drops or #data.drops==0 then return 0 end
        local root=scanContext.getLocalRoot(); if not root then return 0 end
        local total=#data.drops
        if collectCursor>total then collectCursor=1 end
        local now=os.clock(); local checked=0; local index=collectCursor
        while checked<total do
            local drop=data.drops[index]
            checked=checked+1
            index=(index%total)+1
            if drop and drop.object and drop.object.Parent and refreshInteraction(drop) then
                local key=drop.touchPart or drop.prompt or drop.clickDetector or drop.object
                if now>=(collectCooldowns[key] or 0) then
                    diagnostics.attempts=diagnostics.attempts+1
                    local before=tonumber(scanContext.getCash())
                    currencyMark("collect")
                    local ok=activateCollection(drop,root)
                    if ok then
                        diagnostics.activations=diagnostics.activations+1
                        collectCooldowns[key]=now+COLLECT_COOLDOWN
                        waitStep(CONFIRM_DELAY)
                        local after=tonumber(scanContext.getCash())
                        if before~=nil and after~=nil and after>before then diagnostics.cashConfirmed=diagnostics.cashConfirmed+1 end
                        collectCursor=index
                        return 1
                    end
                    diagnostics.failed=diagnostics.failed+1
                    collectCooldowns[key]=now+FAILED_COOLDOWN
                    collectCursor=index
                    return 0
                end
            end
        end
        collectCursor=index
        return 0
    end

    local function hasPurchasedAncestor(object)
        local current=object and object.Parent
        while current and current~=workspace do
            local name=lower(current.Name):gsub("[^%w]","")
            if name=="purchased" or name=="purchasedobjects" or name=="bought" or name=="owneditems" then return true end
            current=current.Parent
        end
        return false
    end
    local function purchaseSignature(button)
        local origin=button and (button.object or button.touchPart)
        if not origin or not origin.Parent then return nil end
        local pieces={}; local queue={origin}; local cursor=1; local inspected=0
        while cursor<=#queue and inspected<SIGNATURE_INSPECT do
            local current=queue[cursor]; cursor=cursor+1; inspected=inspected+1
            if current:IsA("TextLabel") or current:IsA("TextButton") or current:IsA("TextBox") then
                table.insert(pieces,current.Name.."="..tostring(current.Text))
            elseif current:IsA("IntValue") or current:IsA("NumberValue") or current:IsA("StringValue") then
                table.insert(pieces,current.Name.."="..tostring(current.Value))
            elseif current:IsA("ProximityPrompt") then
                table.insert(pieces,current.Name.."="..tostring(current.ActionText).."|"..tostring(current.ObjectText))
            end
            for _,child in ipairs(current:GetChildren()) do
                if #queue<SIGNATURE_INSPECT*2 then table.insert(queue,child) end
            end
        end
        if #pieces==0 then return nil end
        table.sort(pieces)
        return table.concat(pieces,"\31")
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
    end
    local function purchaseApplied(scanContext,button,before)
        local object=before.object
        if not object or not object.Parent then return true end
        if hasPurchasedAncestor(object) then return true end
        if before.parent and object.Parent~=before.parent then return true end
        if before.hadActivation and not activationAlive(button) then return true end
        if before.signature then
            local currentSignature=purchaseSignature(button)
            if currentSignature and currentSignature~=before.signature then return true end
        end
        local current=tonumber(scanContext.getCash())
        return before.cash and current and before.price>0 and current<before.cash or false
    end
    local function verifyPurchase(scanContext,button,before,timeout)
        local deadline=os.clock()+(timeout or VIRTUAL_CONFIRM_TIMEOUT)
        repeat
            if purchaseApplied(scanContext,button,before) then return true end
            waitStep(0.08)
        until os.clock()>=deadline
        return purchaseApplied(scanContext,button,before)
    end

    local function purchaseCooldown(button)
        if not button or not button.object then return end
        local failures=(purchaseFailures[button.object] or 0)+1
        purchaseFailures[button.object]=failures
        button.failureCount=failures
        -- Keep retry gaps short. The waypoint UI remains sticky during this gap.
        button.blockedUntil=os.clock()+math.min(1.4,0.45+failures*0.15)
    end
    local function purchaseActors(scanContext,root)
        local result={}; local seen={}
        local character=scanContext.LOCAL_PLAYER and scanContext.LOCAL_PLAYER.Character
        local function add(part)
            if part and part.Parent and part:IsA("BasePart") and not seen[part] then
                seen[part]=true; table.insert(result,part)
            end
        end
        add(root)
        if character then for _,name in ipairs(PURCHASE_ACTOR_NAMES) do add(character:FindFirstChild(name)) end end
        return result
    end
    local function purchaseKind(button)
        if button.prompt and button.prompt.Parent then return "prompt" end
        if button.clickDetector and button.clickDetector.Parent then return "click" end
        if button.touchPart and button.touchPart.Parent then return "touch" end
        return "none"
    end
    local function purchaseDistance(root,button)
        local part=button and (button.touchPart or button.part)
        if root and part and part.Parent and part:IsA("BasePart") then return (part.Position-root.Position).Magnitude end
        return nil
    end
    local function activatePurchase(scanContext,root,button)
        if button.prompt and button.prompt.Parent then diagnostics.lastPurchaseActor="ProximityPrompt"; return firePrompt(button.prompt) end
        if button.clickDetector and button.clickDetector.Parent then diagnostics.lastPurchaseActor="ClickDetector"; return fireClick(button.clickDetector) end
        local target=button.touchPart
        if not target or not target.Parent then return false end
        local actors=purchaseActors(scanContext,root)
        if #actors==0 then return false end
        local key=button.object or target
        local index=purchaseActorIndexes[key] or 1
        if index>#actors then index=1 end
        local actor=actors[index]
        purchaseActorIndexes[key]=(index%#actors)+1
        if index>1 then diagnostics.purchaseActorRetries=diagnostics.purchaseActorRetries+1 end
        diagnostics.lastPurchaseActor=actor.Name
        return fireTouch(actor,target)
    end

    local function approachPurchase(scanContext,button,before)
        if CONFIG.autopilotEnabled~=true then return false,"autopilot-disabled" end
        local player=scanContext.LOCAL_PLAYER
        local character=player and player.Character
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        local root=scanContext.getLocalRoot()
        local target=button and (button.touchPart or button.part)
        if not humanoid or humanoid.Health<=0 or not root or not target or not target.Parent then return false,"approach-unavailable" end
        local distance=(target.Position-root.Position).Magnitude
        if distance<=APPROACH_TRIGGER_DISTANCE then return false,"already-near" end
        if distance>APPROACH_MAX_DISTANCE then return false,"too-far" end
        -- Do not fight the player's current manual movement.
        if humanoid.MoveDirection.Magnitude>0.15 then return false,"player-moving" end

        diagnostics.physicalApproaches=diagnostics.physicalApproaches+1
        diagnostics.lastPurchaseReason="approaching"
        diagnostics.lastPurchaseActor="Humanoid.MoveTo"
        button.approaching=true
        pcall(function() humanoid:MoveTo(target.Position) end)

        local deadline=os.clock()+math.min(4.0,1.2+distance/12)
        repeat
            if purchaseApplied(scanContext,button,before) then
                button.approaching=nil
                diagnostics.approachSuccesses=diagnostics.approachSuccesses+1
                return true,"natural-touch"
            end
            if not root.Parent or not target.Parent or humanoid.Health<=0 then break end
            distance=(target.Position-root.Position).Magnitude
            if distance<=APPROACH_TRIGGER_DISTANCE then break end
            waitStep(0.08)
        until os.clock()>=deadline

        if root.Parent and target.Parent and (target.Position-root.Position).Magnitude<=APPROACH_TRIGGER_DISTANCE then
            diagnostics.lastPurchaseActor="nearby-touch"
            fireTouch(root,target)
            if verifyPurchase(scanContext,button,before,APPROACH_CONFIRM_TIMEOUT) then
                button.approaching=nil
                diagnostics.approachSuccesses=diagnostics.approachSuccesses+1
                return true,"nearby-touch"
            end
        end
        button.approaching=nil
        diagnostics.approachFailures=diagnostics.approachFailures+1
        return false,"approach-not-confirmed"
    end

    local function logPurchaseMiss(button,reason,cash,price,root)
        diagnostics.lastPurchaseReason=reason
        diagnostics.lastPurchaseName=button and (button.name or (button.object and button.object.Name)) or "?"
        diagnostics.lastPurchasePrice=price
        diagnostics.lastPurchaseCash=cash
        diagnostics.lastPurchaseDistance=purchaseDistance(root,button)
        diagnostics.lastPurchaseKind=purchaseKind(button)
        local dist=diagnostics.lastPurchaseDistance and string.format("%.0f",diagnostics.lastPurchaseDistance) or "?"
        print(string.format("[0xVyrs Tycoon] buy miss // %s // reason=%s // kind=%s // actor=%s // price=%s cash=%s dist=%s",
            tostring(diagnostics.lastPurchaseName),tostring(reason),tostring(diagnostics.lastPurchaseKind),tostring(diagnostics.lastPurchaseActor or "?"),tostring(price),tostring(cash),dist))
    end
    local function markPurchaseSuccess(button)
        if button.object then purchaseFailures[button.object]=nil; purchaseActorIndexes[button.object]=nil end
        button.blockedUntil=nil; button.failureCount=0; button.approaching=nil
        diagnostics.purchaseSuccesses=diagnostics.purchaseSuccesses+1
        diagnostics.lastPurchaseReason="success"
        return true
    end

    local function buyButton(scanContext,button)
        if not button or button.automationAllowed~=true then return false end
        if button.blockedUntil and button.blockedUntil>os.clock() then return false end
        if purchaseBlocked(button) then
            button.paidPurchase=true; button.affordable=false; button.locked=false
            diagnostics.lastPurchaseReason="blocked-paid-context"
            return false
        end
        if not refreshInteraction(button) then
            diagnostics.purchaseFailures=diagnostics.purchaseFailures+1
            purchaseCooldown(button)
            logPurchaseMiss(button,"stale-interaction",tonumber(scanContext.getCash()),tonumber(button.price),scanContext.getLocalRoot())
            return false
        end
        local cash=tonumber(scanContext.getCash())
        local price=math.max(0,tonumber(button.price) or 0)
        if cash~=nil and price>cash then
            button.affordable=false; button.locked=true; diagnostics.unaffordableSkips=diagnostics.unaffordableSkips+1
            diagnostics.lastPurchaseReason="unaffordable"
            return false
        end
        if cash==nil and price>0 then
            diagnostics.unaffordableSkips=diagnostics.unaffordableSkips+1
            diagnostics.lastPurchaseReason="cash-unresolved"
            return false
        end
        local root=scanContext.getLocalRoot(); if not root then return false end
        local before=capturePurchase(scanContext,button)
        currencyMark("buy",price)
        diagnostics.purchaseActivations=diagnostics.purchaseActivations+1

        if activatePurchase(scanContext,root,button) and verifyPurchase(scanContext,button,before,VIRTUAL_CONFIRM_TIMEOUT) then
            return markPurchaseSuccess(button)
        end

        diagnostics.verificationMisses=diagnostics.verificationMisses+1
        local distance=purchaseDistance(root,button)
        if purchaseKind(button)=="touch" and distance and distance>APPROACH_TRIGGER_DISTANCE then
            local approached,reason=approachPurchase(scanContext,button,before)
            if approached then return markPurchaseSuccess(button) end
            diagnostics.lastPurchaseReason=reason
        end

        diagnostics.purchaseFailures=diagnostics.purchaseFailures+1
        purchaseCooldown(button)
        logPurchaseMiss(button,diagnostics.lastPurchaseReason or "not-confirmed",cash,price,root)
        return false
    end

    local function cleanup()
        for part,state in pairs(noclipStates) do
            if part and part.Parent and state then pcall(function() part.CanCollide=state.original end) end
            noclipStates[part]=nil
        end
    end
    local function getStatus()
        return {
            attempts=diagnostics.attempts,activations=diagnostics.activations,cashConfirmed=diagnostics.cashConfirmed,
            failed=diagnostics.failed,unaffordableSkips=diagnostics.unaffordableSkips,verificationMisses=diagnostics.verificationMisses,
            actorRetries=0,rootFallbacks=0,staleRefreshes=diagnostics.staleRefreshes,noclipApplied=diagnostics.noclipApplied,launchGuards=diagnostics.launchGuards,
            purchaseActivations=diagnostics.purchaseActivations,purchaseSuccesses=diagnostics.purchaseSuccesses,purchaseFailures=diagnostics.purchaseFailures,
            purchaseActorRetries=diagnostics.purchaseActorRetries,physicalApproaches=diagnostics.physicalApproaches,
            approachSuccesses=diagnostics.approachSuccesses,approachFailures=diagnostics.approachFailures,
            lastPurchaseReason=diagnostics.lastPurchaseReason,lastPurchaseName=diagnostics.lastPurchaseName,
            lastPurchasePrice=diagnostics.lastPurchasePrice,lastPurchaseCash=diagnostics.lastPurchaseCash,
            lastPurchaseDistance=diagnostics.lastPurchaseDistance,lastPurchaseActor=diagnostics.lastPurchaseActor,lastPurchaseKind=diagnostics.lastPurchaseKind,
        }
    end

    return {collectNearby=collectNearby,buyButton=buyButton,getStatus=getStatus,cleanup=cleanup}
end
