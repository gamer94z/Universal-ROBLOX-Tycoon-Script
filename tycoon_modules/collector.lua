return function()
	local function waitStep(seconds)
		if task and task.wait then
			task.wait(seconds)
		else
			wait(seconds)
		end
	end

	local function touch(root, part)
		if not root or not part or not part.Parent then
			return false
		end
		if type(firetouchinterest) ~= "function" then
			return false
		end
		pcall(function()
			firetouchinterest(root, part, 0)
			waitStep()
			firetouchinterest(root, part, 1)
		end)
		return true
	end

	local function teleportTouch(root, part)
		if not root or not part or not part.Parent then
			return false
		end

		local originalCFrame = root.CFrame
		local targetCFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
		local ok = pcall(function()
			root.CFrame = targetCFrame
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end)
		if not ok then
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

	local function activatePart(context, root, part)
		if context.CONFIG.touchMode == "Teleport" then
			return teleportTouch(root, part)
		end
		return touch(root, part)
	end

	local function activateCollector(context, root, drop)
		if not drop then
			return false
		end

		if drop.part and activatePart(context, root, drop.part) then
			return true
		end

		if drop.prompt and drop.prompt.Parent and type(fireproximityprompt) == "function" then
			local ok = pcall(function()
				fireproximityprompt(drop.prompt)
			end)
			if ok then
				return true
			end
		end

		if drop.clickDetector and drop.clickDetector.Parent and type(fireclickdetector) == "function" then
			local ok = pcall(function()
				fireclickdetector(drop.clickDetector)
			end)
			if ok then
				return true
			end
		end

		return false
	end

	local function collectNearby(context, data)
		if not data or not data.drops then
			return 0
		end
		if not data.ownerMatch then
			return 0
		end

		local root = context.getLocalRoot()
		if not root then
			return 0
		end

		local collected = 0
		for _, drop in ipairs(data.drops) do
			local targetPart = drop.part
			if not targetPart and drop.prompt and drop.prompt.Parent and drop.prompt.Parent:IsA("BasePart") then
				targetPart = drop.prompt.Parent
			elseif not targetPart and drop.clickDetector and drop.clickDetector.Parent and drop.clickDetector.Parent:IsA("BasePart") then
				targetPart = drop.clickDetector.Parent
			end
			local inRange = context.CONFIG.collectMode == "Tycoon" or (targetPart and (targetPart.Position - root.Position).Magnitude <= context.CONFIG.collectRange)
			local modeAllows = context.CONFIG.collectMode ~= "Collectors" or tostring(drop.name or ""):lower():find("collect", 1, true) ~= nil
			if targetPart and targetPart.Parent and inRange and modeAllows then
				if activateCollector(context, root, drop) then
					collected = collected + 1
				end
			end
		end

		return collected
	end

	local function buyButton(context, button)
		if not button or not button.part or button.paidPurchase or not button.ownerVerified then
			return false
		end
		local root = context.getLocalRoot()
		return activatePart(context, root, button.part)
	end

	return {
		collectNearby = collectNearby,
		buyButton = buyButton,
	}
end
