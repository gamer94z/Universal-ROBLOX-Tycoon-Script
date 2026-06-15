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
			return object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart", true)
		end
		return object:FindFirstChildWhichIsA("BasePart", true)
	end

	local function hasTouchInterest(object)
		local part = getTouchPart(object)
		return part and part:FindFirstChildWhichIsA("TouchTransmitter") ~= nil
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
				if score >= 8 or ownerMatches(context, child) then
					table.insert(roots, {
						root = child,
						score = ownerMatches(context, child) and (score + 100) or score,
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
		local data = {
			root = roots[1] and roots[1].root or workspace,
			rootName = roots[1] and roots[1].root.Name or "Workspace",
			buttons = {},
			drops = {},
			cash = getCash(context),
			owned = roots[1] ~= nil,
		}

		collectCandidates(data.root, data, context)
		if #data.buttons == 0 and data.root ~= workspace then
			collectCandidates(workspace, data, context)
		end

		return data
	end

	return {
		scan = scan,
	}
end
