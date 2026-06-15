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

	local function collectNearby(context, data)
		if not data or not data.drops then
			return 0
		end

		local root = context.getLocalRoot()
		if not root then
			return 0
		end

		local collected = 0
		for _, drop in ipairs(data.drops) do
			local part = drop.part
			local inRange = context.CONFIG.collectMode == "Tycoon" or (part and (part.Position - root.Position).Magnitude <= context.CONFIG.collectRange)
			local modeAllows = context.CONFIG.collectMode ~= "Collectors" or tostring(drop.name or ""):lower():find("collect", 1, true) ~= nil
			if part and part.Parent and inRange and modeAllows then
				if touch(root, part) then
					collected = collected + 1
				end
			end
		end

		return collected
	end

	local function buyButton(context, button)
		if not button or not button.part then
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
