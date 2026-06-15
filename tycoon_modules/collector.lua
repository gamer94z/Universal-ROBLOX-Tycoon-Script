return function()
	local function touch(root, part)
		if not root or not part or not part.Parent then
			return false
		end
		if type(firetouchinterest) ~= "function" then
			return false
		end
		pcall(function()
			firetouchinterest(root, part, 0)
			if task and task.wait then
				task.wait()
			else
				wait()
			end
			firetouchinterest(root, part, 1)
		end)
		return true
	end

	local function activateCollector(root, drop)
		if not drop then
			return false
		end

		if drop.part and touch(root, drop.part) then
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
				if activateCollector(root, drop) then
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
		return touch(root, button.part)
	end

	return {
		collectNearby = collectNearby,
		buyButton = buyButton,
	}
end
