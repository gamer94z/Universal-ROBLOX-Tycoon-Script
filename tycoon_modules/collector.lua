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

	local function touch(root, part)
		if not root or not root.Parent or not part or not part.Parent then
			return false
		end
		if type(firetouchinterest) ~= "function" then
			return false
		end

		local ok = pcall(function()
			firetouchinterest(root, part, 0)
			waitStep()
			firetouchinterest(root, part, 1)
		end)
		return ok
	end

	local function teleportTouch(root, part)
		if not root or not root.Parent or not part or not part.Parent then
			return false
		end

		local originalCFrame = root.CFrame
		local targetCFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
		local moved = pcall(function()
			root.CFrame = targetCFrame
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end)
		if not moved then
			return touch(root, part)
		end

		waitStep(0.08)
		local touched = touch(root, part)
		waitStep(0.08)
		pcall(function()
			if root and root.Parent then
				root.CFrame = originalCFrame
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end)

		return touched
	end

	local function activatePart(context, root, part, allowTeleport)
		if not part or not part.Parent then
			return false
		end
		if allowTeleport and context.CONFIG.touchMode == "Teleport" then
			return teleportTouch(root, part)
		end
		return touch(root, part)
	end

	local function activateEntry(context, root, entry, allowTeleport)
		if not entry then
			return false
		end

		if firePrompt(entry.prompt) then
			return true
		end
		if fireClick(entry.clickDetector) then
			return true
		end
		if entry.touchPart and activatePart(context, root, entry.touchPart, allowTeleport) then
			return true
		end

		return false
	end

	local function collectNearby(context, data)
		if not data or not data.drops or data.automationAllowed ~= true then
			return 0
		end

		local root = context.getLocalRoot()
		if not root then
			return 0
		end

		local collected = 0
		for _, drop in ipairs(data.drops) do
			local targetPart = drop.touchPart or drop.part
			if not targetPart and drop.prompt and drop.prompt.Parent and drop.prompt.Parent:IsA("BasePart") then
				targetPart = drop.prompt.Parent
			elseif not targetPart and drop.clickDetector and drop.clickDetector.Parent and drop.clickDetector.Parent:IsA("BasePart") then
				targetPart = drop.clickDetector.Parent
			end

			local inRange = context.CONFIG.collectMode == "Tycoon"
				or (targetPart and (targetPart.Position - root.Position).Magnitude <= context.CONFIG.collectRange)
			local modeAllows = context.CONFIG.collectMode ~= "Collectors"
				or tostring(drop.name or ""):lower():find("collect", 1, true) ~= nil

			if inRange and modeAllows and activateEntry(context, root, drop, false) then
				collected = collected + 1
			end
		end

		return collected
	end

	local function buyButton(context, button)
		if not button or button.automationAllowed ~= true then
			return false
		end
		if purchaseLooksBlocked(button) then
			-- Keep this result out of subsequent target selection until the next scan.
			button.paidPurchase = true
			button.affordable = false
			button.locked = false
			return false
		end

		local root = context.getLocalRoot()
		if not root then
			return false
		end
		return activateEntry(context, root, button, true)
	end

	return {
		collectNearby = collectNearby,
		buyButton = buyButton,
	}
end
