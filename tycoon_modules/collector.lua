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
			task.wait()
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
			if part and part.Parent and (part.Position - root.Position).Magnitude <= context.CONFIG.collectRange then
				if touch(root, part) then
					collected = collected + 1
				end
			end
		end

		return collected
	end

	return {
		collectNearby = collectNearby,
	}
end
