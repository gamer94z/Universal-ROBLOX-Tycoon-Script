return function()
	local MAX_COLLECT_PER_PASS = 2
	local COLLECT_TARGET_COOLDOWN = 0.65
	local COLLECTION_CONFIRM_DELAY = 0.12
	local RETRY_AFTER_MISSES = 3
	local ROOT_FALLBACK_MISSES = 6
	local ROOT_FALLBACK_COOLDOWN = 3
	local MAX_BLOCK_INSPECT = 28

	local BLOCKED = {
		"watch ad", "watch video", "video ad", "rewarded ad", "rewarded video", "advertisement",
		"developer product", "game pass", "gamepass", "premium", "robux", "r$", "rbx",
	}
	local ACTOR_NAMES = { "LeftFoot", "RightFoot", "LeftLowerLeg", "RightLowerLeg", "Left Leg", "Right Leg", "LowerTorso", "Torso" }

	local purchaseFailures=setmetatable({}, {__mode="k"})
	local collectCooldowns=setmetatable({}, {__mode="k"})
	local collectStates=setmetatable({}, {__mode="k"})
	local collectCursor=1
	local cachedCharacter=nil
	local cachedActors={}

	local diagnostics={attempts=0,activations=0,cashConfirmed=0,actorRetries=0,rootFallbacks=0,staleRefreshes=0,failed=0,unaffordableSkips=0,verificationMisses=0}

	local function lower(v) return tostring(v or ""):lower() end
	local function waitStep(seconds) if task and task.wait then task.wait(seconds or 0) else wait(seconds or 0) end end
	local function blockedText(v)
		local text=lower(v)
		for _,phrase in ipairs(BLOCKED) do if text:find(phrase,1,true) then return true end end
		local tokens=" "..text:gsub("[^%w]+"," ").." "
		return tokens:find(" ad ",1,true)~=nil or tokens:find(" ads ",1,true)~=nil
	end
	local function instanceBlocked(o)
		if not o then return false end
		if blockedText(o.Name) then return true end
		if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then if blockedText(o.Text) then return true end end
		if o:IsA("ProximityPrompt") and (blockedText(o.ActionText) or blockedText(o.ObjectText)) then return true end
		local ok,a=pcall(function() return o:GetAttributes() end)
		if ok and type(a)=="table" then for key,value in pairs(a) do if blockedText(key) or (type(value)=="string" and blockedText(value)) then return true end end end
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
	local function touch(actor,target,suppressCollision)
		if not actor or not actor.Parent or not target or not target.Parent or type(firetouchinterest)~="function" then return false end
		local oldCollide
		if suppressCollision and target:IsA("BasePart") then oldCollide=target.CanCollide; pcall(function() target.CanCollide=false end) end
		local ok=pcall(function()
			firetouchinterest(actor,target,0)
			waitStep(0.015)
			firetouchinterest(actor,target,1)
		end)
		if oldCollide~=nil and target and target.Parent then pcall(function() target.CanCollide=oldCollide end) end
		return ok
	end

	local function actorsFor(context,root)
		local character=context.LOCAL_PLAYER and context.LOCAL_PLAYER.Character
		if character~=cachedCharacter then cachedCharacter=character; cachedActors={} end
		if not character then return cachedActors end
		local valid=true
		for _,part in ipairs(cachedActors) do if not part or not part.Parent then valid=false; break end end
		if #cachedActors>0 and valid then return cachedActors end
		cachedActors={}; local seen={}
		local function add(part)
			if part and part.Parent and part:IsA("BasePart") and part~=root and not seen[part] then seen[part]=true; table.insert(cachedActors,part) end
		end
		for _,name in ipairs(ACTOR_NAMES) do add(character:FindFirstChild(name)) end
		if #cachedActors==0 then add(character:FindFirstChild("HumanoidRootPart")) end
		return cachedActors
	end

	local function activationAlive(entry)
		return (entry.prompt and entry.prompt.Parent) or (entry.clickDetector and entry.clickDetector.Parent) or (entry.touchPart and entry.touchPart.Parent)
	end
	local function refreshInteraction(entry)
		if not entry or not entry.object or not entry.object.Parent then return false end
		if activationAlive(entry) then return true end
		entry.prompt=nil; entry.clickDetector=nil; entry.touchPart=nil
		local queue={entry.object}; local cursor=1; local inspected=0
		while cursor<=#queue and inspected<36 do
			local current=queue[cursor]; cursor=cursor+1
			if current:IsA("ProximityPrompt") and not entry.prompt then entry.prompt=current
			elseif current:IsA("ClickDetector") and not entry.clickDetector then entry.clickDetector=current
			elseif current:IsA("TouchTransmitter") and current.Parent and current.Parent:IsA("BasePart") and not entry.touchPart then entry.touchPart=current.Parent end
			if activationAlive(entry) then diagnostics.staleRefreshes=diagnostics.staleRefreshes+1; return true end
			for _,child in ipairs(current:GetChildren()) do inspected=inspected+1; if inspected<=36 then table.insert(queue,child) end; if inspected>=36 then break end end
		end
		return false
	end
	local function stateFor(entry)
		local key=entry and (entry.touchPart or entry.prompt or entry.clickDetector or entry.object)
		if not key then return nil end
		local state=collectStates[key]
		if not state then state={actorIndex=1,misses=0,lastRootFallback=-math.huge}; collectStates[key]=state end
		return state
	end
	local function cashIncreased(context,before)
		if before==nil then return nil end
		local now=tonumber(context.getCash())
		if now==nil then return nil end
		return now>before
	end

	local function collectEntry(context,root,entry)
		if not refreshInteraction(entry) then diagnostics.failed=diagnostics.failed+1; return false end
		if entry.prompt and entry.prompt.Parent then local ok=firePrompt(entry.prompt); if ok then diagnostics.activations=diagnostics.activations+1 end; return ok end
		if entry.clickDetector and entry.clickDetector.Parent then local ok=fireClick(entry.clickDetector); if ok then diagnostics.activations=diagnostics.activations+1 end; return ok end
		local target=entry.touchPart; if not target or not target.Parent then diagnostics.failed=diagnostics.failed+1; return false end
		local actors=actorsFor(context,root); if #actors==0 then diagnostics.failed=diagnostics.failed+1; return false end
		local state=stateFor(entry); if state.actorIndex>#actors then state.actorIndex=1 end
		local actor=actors[state.actorIndex]; state.actorIndex=(state.actorIndex%#actors)+1
		local before=tonumber(context.getCash())
		local touched=touch(actor,target,false)
		if not touched then diagnostics.failed=diagnostics.failed+1; return false end
		diagnostics.activations=diagnostics.activations+1
		if before==nil then state.misses=0; return true end
		waitStep(COLLECTION_CONFIRM_DELAY)
		local confirmed=cashIncreased(context,before)
		if confirmed==true then state.misses=0; diagnostics.cashConfirmed=diagnostics.cashConfirmed+1; return true end
		if confirmed==nil then state.misses=0; return true end
		state.misses=math.min(20,(state.misses or 0)+1); diagnostics.verificationMisses=diagnostics.verificationMisses+1

		-- Do not double-touch on every replication delay. Escalate only after repeated real misses.
		if state.misses>=RETRY_AFTER_MISSES and state.misses%RETRY_AFTER_MISSES==0 and #actors>1 then
			diagnostics.actorRetries=diagnostics.actorRetries+1
			if state.actorIndex>#actors then state.actorIndex=1 end
			local retryActor=actors[state.actorIndex]; state.actorIndex=(state.actorIndex%#actors)+1
			local retry=touch(retryActor,target,state.misses>=RETRY_AFTER_MISSES*2)
			if retry then diagnostics.activations=diagnostics.activations+1; waitStep(COLLECTION_CONFIRM_DELAY); if cashIncreased(context,before)==true then state.misses=0; diagnostics.cashConfirmed=diagnostics.cashConfirmed+1; return true end end
		end
		local now=os.clock()
		if state.misses>=ROOT_FALLBACK_MISSES and now-state.lastRootFallback>=ROOT_FALLBACK_COOLDOWN and root and root.Parent then
			state.lastRootFallback=now; diagnostics.rootFallbacks=diagnostics.rootFallbacks+1
			local fallback=touch(root,target,true)
			if fallback then diagnostics.activations=diagnostics.activations+1; waitStep(COLLECTION_CONFIRM_DELAY); if cashIncreased(context,before)==true then state.misses=0; diagnostics.cashConfirmed=diagnostics.cashConfirmed+1; return true end end
		end
		return touched
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
	local function capturePurchase(context,button)
		local object=button and button.object
		return {object=object,parent=object and object.Parent or nil,cash=tonumber(context.getCash()),price=tonumber(button and button.price) or 0,hadActivation=activationAlive(button) and true or false}
	end
	local function purchaseApplied(context,button,before)
		local object=before.object
		if not object or not object.Parent then return true end
		if hasPurchasedAncestor(object) then return true end
		if before.parent and object.Parent~=before.parent then return true end
		if before.hadActivation and not activationAlive(button) then return true end
		local current=tonumber(context.getCash())
		return before.cash and current and before.price>0 and current<before.cash or false
	end
	local function verifyPurchase(context,button,before)
		local deadline=os.clock()+0.95
		repeat if purchaseApplied(context,button,before) then return true end; waitStep(0.1) until os.clock()>=deadline
		return purchaseApplied(context,button,before)
	end
	local function purchaseCooldown(button)
		if not button or not button.object then return end
		local failures=(purchaseFailures[button.object] or 0)+1; purchaseFailures[button.object]=failures; button.failureCount=failures; button.blockedUntil=os.clock()+math.min(12,1.5+failures*1.5)
	end
	local function activatePurchase(context,root,button)
		if firePrompt(button.prompt) then return true end
		if fireClick(button.clickDetector) then return true end
		if button.touchPart then return touch(root,button.touchPart,false) end
		return false
	end

	local function collectNearby(context,data)
		if not data or not data.drops or data.automationAllowed~=true or #data.drops==0 then return 0 end
		local root=context.getLocalRoot(); if not root then return 0 end
		local now=os.clock(); local total=#data.drops; if collectCursor>total then collectCursor=1 end
		local collected,activated,checked,index=0,0,0,collectCursor
		while checked<total and activated<MAX_COLLECT_PER_PASS do
			local drop=data.drops[index]; checked=checked+1
			if drop and drop.object and drop.object.Parent then
				local target=drop.touchPart or drop.part
				local autonomous=context.CONFIG.autopilotEnabled~=nil
				local inRange=autonomous or context.CONFIG.collectMode=="Tycoon" or (target and target.Parent and (target.Position-root.Position).Magnitude<=context.CONFIG.collectRange)
				local modeAllows=context.CONFIG.collectMode~="Collectors" or lower(drop.name):find("collect",1,true)~=nil
				local key=drop.touchPart or drop.prompt or drop.clickDetector or drop.object; local untilAt=collectCooldowns[key] or 0
				if inRange and modeAllows and now>=untilAt then
					activated=activated+1; diagnostics.attempts=diagnostics.attempts+1
					if collectEntry(context,root,drop) then collected=collected+1; collectCooldowns[key]=os.clock()+COLLECT_TARGET_COOLDOWN else collectCooldowns[key]=os.clock()+0.35 end
				end
			end
			index=(index%total)+1
		end
		collectCursor=index; return collected
	end

	local function buyButton(context,button)
		if not button or button.automationAllowed~=true then return false end
		if button.blockedUntil and button.blockedUntil>os.clock() then return false end
		if purchaseBlocked(button) then button.paidPurchase=true; button.affordable=false; button.locked=false; return false end
		local cash=tonumber(context.getCash()); local price=math.max(0,tonumber(button.price) or 0)
		if cash~=nil and price>cash then button.affordable=false; button.locked=true; diagnostics.unaffordableSkips=diagnostics.unaffordableSkips+1; return false end
		local root=context.getLocalRoot(); if not root then return false end
		local before=capturePurchase(context,button)
		if not activatePurchase(context,root,button) then purchaseCooldown(button); return false end
		if verifyPurchase(context,button,before) then if button.object then purchaseFailures[button.object]=nil end; button.blockedUntil=nil; button.failureCount=0; return true end
		purchaseCooldown(button); return false
	end

	local function getStatus()
		return {attempts=diagnostics.attempts,activations=diagnostics.activations,cashConfirmed=diagnostics.cashConfirmed,actorRetries=diagnostics.actorRetries,rootFallbacks=diagnostics.rootFallbacks,staleRefreshes=diagnostics.staleRefreshes,failed=diagnostics.failed,unaffordableSkips=diagnostics.unaffordableSkips,verificationMisses=diagnostics.verificationMisses}
	end
	return {collectNearby=collectNearby,buyButton=buyButton,getStatus=getStatus}
end