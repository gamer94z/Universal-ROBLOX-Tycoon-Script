return function()
	local BLOCKED_PHRASES = {
		"watch ad",
		"watch ads",
		"watch video",
		"video ad",
		"video ads",
		"rewarded ad",
		"rewarded video",
		"ad reward",
		"advertisement",
		"developer product",
		"game pass",
		"gamepass",
		"robux",
		"premium purchase",
	}

	local purchaseFailures = setmetatable({}, { __mode = "k" })
	local collectCooldowns = setmetatable({}, { __mode = "k" })
	local collectCursor = 1
	local MAX_COLLECT_PER_PASS = 6
	local COLLECT_TARGET_COOLDOWN = 0.45

	local function lower(value)
		return tostring(value or ""):lower()
	end

	local function waitStep(seconds)
		seconds = seconds or 0
		if task and task.wait then
			task.wait(seconds)
		else
			wait(seconds)
		end
	end

	local function hasStandaloneToken(text, token)
		local normalized = " " .. lower(text):gsub("[^%w]+", " ") .. " "
		return normalized:find(" " .. token .. " ", 1, true) ~= nil
	end

	local function textLooksBlocked(text)
		local clean = lower(text)
		for _, phrase in ipairs(BLOCKED_PHRASES) do
			if clean:find(phrase, 1, true) then
				return true
			end
		end

		if hasStandaloneToken(clean, "ad") or hasStandaloneToken(clean, "ads") then
			return true
		end
		if hasStandaloneToken(clean, "advert") or hasStandaloneToken(clean, "advertisement") then
			return true
		end
		if hasStandaloneToken(clean, "rewarded") and hasStandaloneToken(clean, "video") then
			return true
		end
		return false
	end

	local function instanceLooksBlocked(instance)
		if not instance then
			return false
		end

		if textLooksBlocked(instance.Name) then
			return true
		end

		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			if textLooksBlocked(instance.Text) then
				return true
			end
		elseif instance:IsA("ProximityPrompt") then
			if textLooksBlocked(instance.ActionText) or textLooksBlocked(instance.ObjectText) then
				return true
			end
		end

		local ok, attributes = pcall(function()
			return instance:GetAttributes()
		end)
		if ok and type(attributes) == "table" then
			for key, value in pairs(attributes) do
				if textLooksBlocked(key) or (type(value) == "string" and textLooksBlocked(value)) then
					return true
				end
			end
		end

		return false
	end

	local function isGenericPurchaseContainer(instance)
		if not instance then
			return false
		end
		local name = lower(instance.Name):gsub("[^%w]", "")
		return name == "buttons"
			or name == "button"
			or name == "pads"
			or name == "purchasepads"
			or name == "purchasebuttons"
			or name == "buybuttons"
			or name == "buyitems"
	end

	local function purchaseLooksBlocked(button)
		if not button then
			return true
		end
		if button.paidPurchase then
			return true
		end

		local object = button.object
		if not object or not object.Parent then
			return true
		end

		if instanceLooksBlocked(object) then
			return true
		end
		for _, descendant in ipairs(object:GetDescendants()) do
			if instanceLooksBlocked(descendant) then
				return true
			end
		end

		local parent = object.Parent
		if parent and parent ~= workspace and not isGenericPurchaseContainer(parent) then
			if instanceLooksBlocked(parent) then
				return true
			end
		end

		return false
	end

	local function firePrompt(prompt)
		if not prompt or not prompt.Parent or type(fireproximityprompt) ~= "function" then
			return false
		end
		return pcall(function()
			fireproximityprompt(prompt)
		end)
	end

	local function fireClick(clickDetector)
		if not clickDetector or not clickDetector.Parent or type(fireclickdetector) ~= "function" then
			return false
		end
		return pcall(function()
			fireclickdetector(clickDetector)
		end)
	end

	local function captureRootState(root)
		if not root or not root.Parent then
			return nil
		end

		return {
			cframe = root.CFrame,
			linearVelocity = root.AssemblyLinearVelocity,
			angularVelocity = root.AssemblyAngularVelocity,
		}
	end

	local function restoreRootState(root, state)
		if not root or not root.Parent or not state then
			return
		end

		pcall(function()
			root.CFrame = state.cframe
			root.AssemblyLinearVelocity = state.linearVelocity
			root.AssemblyAngularVelocity = state.angularVelocity
		end)
	end

	local function getCollectionTouchActor(context, root)
		local character = context.LOCAL_PLAYER and context.LOCAL_PLAYER.Character
		if not character then
			return root
		end

		-- Prefer a non-root character limb. Touch handlers usually only care that
		-- the touching part belongs to the player's character, while avoiding the
		-- HumanoidRootPart prevents touch simulation from disturbing movement.
		local preferredNames = {
			"LeftFoot",
			"RightFoot",
			"LeftLowerLeg",
			"RightLowerLeg",
			"Left Leg",
			"Right Leg",
			"LowerTorso",
			"Torso",
			"Head",
		}

		for _, name in ipairs(preferredNames) do
			local part = character:FindFirstChild(name)
			if part and part:IsA("BasePart") and part ~= root then
				return part
			end
		end

		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("BasePart") and child ~= root then
				return child
			end
		end

		return root
	end

	local function touch(actor, part, suppressCollision)
		if not actor or not actor.Parent or not part or not part.Parent then
			return false
		end
		if type(firetouchinterest) ~= "function" then
			return false
		end

		local oldTargetCanCollide
		if suppressCollision and part:IsA("BasePart") then
			oldTargetCanCollide = part.CanCollide
			pcall(function()
				part.CanCollide = false
			end)
		end

		local ok = pcall(function()
			firetouchinterest(actor, part, 0)
			waitStep(0.02)
			firetouchinterest(actor, part, 1)
		end)

		if suppressCollision and oldTargetCanCollide ~= nil and part and part.Parent then
			pcall(function()
				part.CanCollide = oldTargetCanCollide
			end)
		end

		return ok
	end

	local function teleportTouch(root, part)
		if not root or not root.Parent or not part or not part.Parent then
			return false
		end

		local originalState = captureRootState(root)
		local targetCFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
		local moved = pcall(function()
			root.CFrame = targetCFrame
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end)
		if not moved then
			return touch(root, part, false)
		end

		waitStep(0.08)
		local touched = touch(root, part, false)
		waitStep(0.08)
		restoreRootState(root, originalState)

		return touched
	end

	local function activateEntry(context, root, entry, allowTeleport, collectionActor)
		if not entry then
			return false
		end

		if firePrompt(entry.prompt) then
			return true
		end
		if fireClick(entry.clickDetector) then
			return true
		end
		if entry.touchPart then
			if allowTeleport and context.CONFIG.touchMode == "Teleport" then
				return teleportTouch(root, entry.touchPart)
		end

			local actor = collectionActor or root
			return touch(actor, entry.touchPart, collectionActor ~= nil)
		end

		return false
	end

	local function hasPurchasedAncestor(object)
		local current = object and object.Parent
		while current and current ~= workspace do
			local name = lower(current.Name):gsub("[^%w]", "")
			if name == "purchased" or name == "purchasedobjects" or name == "bought" or name == "owneditems" then
				return true
			end
			current = current.Parent
		end
		return false
	end

	local function entryHasLiveActivation(entry)
		return (entry.prompt and entry.prompt.Parent)
			or (entry.clickDetector and entry.clickDetector.Parent)
			or (entry.touchPart and entry.touchPart.Parent)
	end

	local function capturePurchaseState(context, button)
		local object = button and button.object
		return {
			object = object,
			parent = object and object.Parent or nil,
			cash = tonumber(context.getCash()),
			price = tonumber(button and button.price) or 0,
			hadActivation = entryHasLiveActivation(button) and true or false,
		}
	end

	local function purchaseWasApplied(context, button, before)
		local object = before.object
		if not object or not object.Parent then
			return true
		end
		if hasPurchasedAncestor(object) then
			return true
		end
		if before.parent and object.Parent ~= before.parent then
			return true
		end
		if before.hadActivation and not entryHasLiveActivation(button) then
			return true
		end

		local currentCash = tonumber(context.getCash())
		if before.cash and currentCash and before.price > 0 and currentCash < before.cash then
			return true
		end

		return false
	end

	local function verifyPurchase(context, button, before)
		local deadline = os.clock() + 1.15
		repeat
			if purchaseWasApplied(context, button, before) then
				return true
			end
			waitStep(0.08)
		until os.clock() >= deadline
		return purchaseWasApplied(context, button, before)
	end

	local function putPurchaseOnCooldown(button)
		if not button or not button.object then
			return
		end

		local failures = (purchaseFailures[button.object] or 0) + 1
		purchaseFailures[button.object] = failures
		button.failureCount = failures
		button.blockedUntil = os.clock() + math.min(12, 1.5 + failures * 1.5)
	end

	local function collectNearby(context, data)
		if not data or not data.drops or data.automationAllowed ~= true or #data.drops == 0 then
			return 0
		end

		local root = context.getLocalRoot()
		if not root then
			return 0
		end

		local actor = getCollectionTouchActor(context, root)
		local now = os.clock()
		local total = #data.drops
		if collectCursor > total then
			collectCursor = 1
		end

		local collected = 0
		local activated = 0
		local checked = 0
		local index = collectCursor

		while checked < total and activated < MAX_COLLECT_PER_PASS do
			local drop = data.drops[index]
			checked = checked + 1

			if drop and drop.object and drop.object.Parent then
				local targetPart = drop.touchPart or drop.part
				if not targetPart and drop.prompt and drop.prompt.Parent and drop.prompt.Parent:IsA("BasePart") then
					targetPart = drop.prompt.Parent
				elseif not targetPart and drop.clickDetector and drop.clickDetector.Parent and drop.clickDetector.Parent:IsA("BasePart") then
					targetPart = drop.clickDetector.Parent
				end

				local inRange = context.CONFIG.collectMode == "Tycoon"
					or (targetPart and (targetPart.Position - root.Position).Magnitude <= context.CONFIG.collectRange)
				local modeAllows = context.CONFIG.collectMode ~= "Collectors"
					or lower(drop.name):find("collect", 1, true) ~= nil
				local cooldownUntil = collectCooldowns[drop.object] or 0

				if inRange and modeAllows and now >= cooldownUntil then
					activated = activated + 1
					if activateEntry(context, root, drop, false, actor) then
						collected = collected + 1
						collectCooldowns[drop.object] = now + COLLECT_TARGET_COOLDOWN
					else
						collectCooldowns[drop.object] = now + 0.2
					end
				end
			end

			index = (index % total) + 1
		end

		collectCursor = index
		return collected
	end

	local function buyButton(context, button)
		if not button or button.automationAllowed ~= true then
			return false
		end
		if button.blockedUntil and button.blockedUntil > os.clock() then
			return false
		end
		if purchaseLooksBlocked(button) then
			button.paidPurchase = true
			button.affordable = false
			button.locked = false
			return false
		end

		local root = context.getLocalRoot()
		if not root then
			return false
		end

		local before = capturePurchaseState(context, button)
		if not activateEntry(context, root, button, true, nil) then
			putPurchaseOnCooldown(button)
			return false
		end

		if verifyPurchase(context, button, before) then
			if button.object then
				purchaseFailures[button.object] = nil
			end
			button.blockedUntil = nil
			button.failureCount = 0
			return true
		end

		putPurchaseOnCooldown(button)
		return false
	end

	return {
		collectNearby = collectNearby,
		buyButton = buyButton,
	}
end
