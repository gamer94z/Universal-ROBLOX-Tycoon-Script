return function()
	local PRICE_NAMES = {
		Cost = true,
		Price = true,
		Amount = true,
		Cash = true,
		Money = true,
	}

	local function lower(text)
		return tostring(text or ""):lower()
	end

	local function hasAny(text, words)
		text = lower(text)
		for _, word in ipairs(words) do
			if text:find(word, 1, true) then
				return true
			end
		end
		return false
	end

	local function getCash(context)
		local cash = context.getCash()
		return tonumber(cash) or 0
	end

	local function findNumberInName(name)
		local clean = tostring(name or ""):gsub(",", "")
		for number in clean:gmatch("%d+") do
			local value = tonumber(number)
			if value and value > 0 then
				return value
			end
		end
		return nil
	end

	local function extractPrice(object)
		for _, descendant in ipairs(object:GetDescendants()) do
			if PRICE_NAMES[descendant.Name] and (descendant:IsA("IntValue") or descendant:IsA("NumberValue")) then
				return tonumber(descendant.Value)
			end
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				local text = descendant.Text
				local value = text and findNumberInName(text)
				if value then
					return value
				end
			end
		end
		return findNumberInName(object.Name)
	end

	local function getTouchPart(object)
		if object:IsA("BasePart") then
			return object
		end
		if object:IsA("Model") then
			if object.PrimaryPart then
				return object.PrimaryPart
			end
		end
		for _, descendant in ipairs(object:GetDescendants()) do
			if descendant:IsA("BasePart") then
				return descendant
			end
		end
		return nil
	end

	local function hasTouchInterest(object)
		local part = getTouchPart(object)
		if not part then
			return false
		end
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("TouchTransmitter") then
				return true
			end
		end
		return false
	end

	local function getModelScore(model)
		local score = 0
		local name = lower(model.Name)
		if name:find("tycoon") then score = score + 8 end
		if name:find("base") then score = score + 3 end
		if model:FindFirstChild("Buttons") then score = score + 8 end
		if model:FindFirstChild("PurchasedObjects") then score = score + 5 end
		if model:FindFirstChild("Drops") then score = score + 4 end
		if model:FindFirstChild("Owner") or model:FindFirstChild("OwnerValue") then score = score + 7 end
		return score
	end

	local function ownerMatches(context, object)
		for _, descendant in ipairs(object:GetDescendants()) do
			local name = lower(descendant.Name)
			if name:find("owner") then
				if descendant:IsA("ObjectValue") and descendant.Value == context.LOCAL_PLAYER then
					return true
				end
				if descendant:IsA("StringValue") and lower(descendant.Value) == lower(context.LOCAL_PLAYER.Name) then
					return true
				end
				if descendant:IsA("IntValue") and tonumber(descendant.Value) == context.LOCAL_PLAYER.UserId then
					return true
				end
			end
		end
		return false
	end

	local function collectCandidates(root, data, context)
		local cash = getCash(context)
		for _, descendant in ipairs(root:GetDescendants()) do
			local name = lower(descendant.Name)
			local isButton = hasAny(name, { "button", "buy", "purchase", "upgrade" }) or descendant:FindFirstChild("Cost") or descendant:FindFirstChild("Price")
			local isDrop = hasAny(name, { "drop", "cash", "money", "collect", "collector" })

			if isButton and hasTouchInterest(descendant) and #data.buttons < context.CONFIG.maxButtons then
				local price = extractPrice(descendant)
				table.insert(data.buttons, {
					object = descendant,
					part = getTouchPart(descendant),
					price = price,
					affordable = price == nil or price <= cash,
					locked = price ~= nil and price > cash,
					name = descendant.Name,
				})
			elseif isDrop and hasTouchInterest(descendant) and #data.drops < context.CONFIG.maxDrops then
				table.insert(data.drops, {
					object = descendant,
					part = getTouchPart(descendant),
					name = descendant.Name,
				})
			end
		end
	end

	local function findTycoonRoots(context)
		local roots = {}
		for _, child in ipairs(workspace:GetChildren()) do
			if child:IsA("Model") or child:IsA("Folder") then
				local score = getModelScore(child)
				local owned = ownerMatches(context, child)
				if score >= 8 or owned then
					table.insert(roots, {
						root = child,
						score = owned and (score + 100) or score,
						rawScore = score,
						ownerMatch = owned,
					})
				end
			end
		end
		table.sort(roots, function(a, b)
			return a.score > b.score
		end)
		return roots
	end

	local function scan(context)
		local roots = findTycoonRoots(context)
		local selected = roots[1]
		local data = {
			root = selected and selected.root or workspace,
			rootName = selected and selected.root.Name or "Workspace",
			confidence = selected and math.clamp(selected.score, 0, 100) or 0,
			rootScore = selected and selected.rawScore or 0,
			ownerMatch = selected and selected.ownerMatch or false,
			buttons = {},
			drops = {},
			cash = getCash(context),
			owned = selected ~= nil,
		}

		collectCandidates(data.root, data, context)
		if #data.buttons == 0 and data.root ~= workspace then
			collectCandidates(workspace, data, context)
		end

		local affordable = 0
		local locked = 0
		for _, button in ipairs(data.buttons) do
			if button.affordable then
				affordable = affordable + 1
			elseif button.locked then
				locked = locked + 1
			end
		end
		table.sort(data.buttons, function(a, b)
			local aPrice = a.price or 0
			local bPrice = b.price or 0
			if a.affordable ~= b.affordable then
				return a.affordable
			end
			return aPrice < bPrice
		end)
		data.affordableCount = affordable
		data.lockedCount = locked
		data.totalButtons = #data.buttons
		data.progressPercent = #data.buttons > 0 and math.floor((affordable / #data.buttons) * 100 + 0.5) or 0
		data.debug = string.format(
			"%s | score %d | owner %s | buttons %d | drops %d",
			data.rootName,
			data.rootScore,
			data.ownerMatch and "yes" or "no",
			#data.buttons,
			#data.drops
		)

		return data
	end

	return {
		scan = scan,
	}
end
