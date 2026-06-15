return function()
	local PRICE_NAMES = {
		Cost = true,
		Price = true,
		Amount = true,
		Cash = true,
		Money = true,
	}
	local PAID_PURCHASE_WORDS = {
		"robux",
		"gamepass",
		"game pass",
		"developer product",
		"dev product",
		"productid",
		"product id",
		"gamepassid",
		"game pass id",
		"premium",
		"r$",
		" r$",
		"rbx",
	}
	local BLOCKED_INTERACTION_WORDS = {
		"watch ad",
		"watch_ad",
		"video ad",
		"rewarded ad",
		"advert",
		"advertisement",
		"watch",
		"video",
		"sponsor",
		"reward",
		"free cash",
		"free money",
		"free coins",
		"double cash",
		"2x cash",
		"earn",
		"invite",
		"group",
		"like",
		"favorite",
		"follow",
		"discord",
		"twitter",
		"boost",
		"vip",
		"shop",
		"store",
		"skip",
		"pass",
		"product",
	}
	local MACHINE_ANCESTOR_WORDS = {
		"purchasedobjects",
		"purchased",
		"dropper",
		"upgrader",
		"conveyor",
		"furnace",
		"machine",
		"processor",
		"generator",
		"producer",
	}
	local PURCHASE_CONTAINER_WORDS = {
		"buttons",
		"button",
		"buybuttons",
		"purchasebuttons",
		"pads",
		"buy pads",
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

	local function hasAncestorNamed(object, stopAt, words)
		local current = object and object.Parent
		while current and current ~= stopAt and current ~= workspace do
			if hasAny(current.Name, words) then
				return true
			end
			current = current.Parent
		end
		return false
	end

	local function hasAnyDescendantText(object, words)
		if hasAny(object.Name, words) then
			return true
		end

		for _, descendant in ipairs(object:GetDescendants()) do
			if hasAny(descendant.Name, words) then
				return true
			end
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				if hasAny(descendant.Text, words) then
					return true
				end
			end
		end

		return false
	end

	local function isPaidPurchase(object)
		return hasAnyDescendantText(object, PAID_PURCHASE_WORDS)
	end

	local function isBlockedInteraction(object)
		return isPaidPurchase(object) or hasAnyDescendantText(object, BLOCKED_INTERACTION_WORDS)
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

	local function hasExplicitPrice(object)
		if object:FindFirstChild("Cost") or object:FindFirstChild("Price") then
			return true
		end

		for _, descendant in ipairs(object:GetDescendants()) do
			if PRICE_NAMES[descendant.Name] and (descendant:IsA("IntValue") or descendant:IsA("NumberValue")) then
				return true
			end
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				if findNumberInName(descendant.Text) then
					return true
				end
			end
		end

		return findNumberInName(object.Name) ~= nil
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

	local function getPrompt(object)
		if object:IsA("ProximityPrompt") then
			return object
		end
		return object:FindFirstChildWhichIsA("ProximityPrompt", true)
	end

	local function getClickDetector(object)
		if object:IsA("ClickDetector") then
			return object
		end
		return object:FindFirstChildWhichIsA("ClickDetector", true)
	end

	local function hasCollectorActivation(object)
		return hasTouchInterest(object) or getPrompt(object) ~= nil or getClickDetector(object) ~= nil
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
		local playerName = lower(context.LOCAL_PLAYER.Name)
		local displayName = lower(context.LOCAL_PLAYER.DisplayName)

		for _, descendant in ipairs(object:GetDescendants()) do
			local name = lower(descendant.Name)
			if name:find("owner") then
				if descendant:IsA("ObjectValue") and descendant.Value == context.LOCAL_PLAYER then
					return true
				end
				if descendant:IsA("StringValue") and (lower(descendant.Value):find(playerName, 1, true) or lower(descendant.Value):find(displayName, 1, true)) then
					return true
				end
				if descendant:IsA("IntValue") and tonumber(descendant.Value) == context.LOCAL_PLAYER.UserId then
					return true
				end
				if (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and (lower(descendant.Text):find(playerName, 1, true) or lower(descendant.Text):find(displayName, 1, true)) then
					return true
				end
			end
		end
		return false
	end

	local function localPlayerInsideRoot(context, root)
		local localRoot = context.getLocalRoot and context.getLocalRoot()
		if not localRoot or not root then
			return false
		end

		if root:IsA("Model") then
			local ok, cframe, size = pcall(function()
				return root:GetBoundingBox()
			end)
			if ok and cframe and size then
				local localPosition = cframe:PointToObjectSpace(localRoot.Position)
				local padding = 18
				return math.abs(localPosition.X) <= (size.X * 0.5) + padding
					and math.abs(localPosition.Y) <= (size.Y * 0.5) + padding
					and math.abs(localPosition.Z) <= (size.Z * 0.5) + padding
			end
		end

		local padding = 18
		local minX, minY, minZ = math.huge, math.huge, math.huge
		local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
		local found = false
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("BasePart") then
				found = true
				local position = descendant.Position
				local half = descendant.Size * 0.5
				minX = math.min(minX, position.X - half.X)
				minY = math.min(minY, position.Y - half.Y)
				minZ = math.min(minZ, position.Z - half.Z)
				maxX = math.max(maxX, position.X + half.X)
				maxY = math.max(maxY, position.Y + half.Y)
				maxZ = math.max(maxZ, position.Z + half.Z)
			end
		end

		if not found then
			return false
		end

		local position = localRoot.Position
		return position.X >= minX - padding and position.X <= maxX + padding
			and position.Y >= minY - padding and position.Y <= maxY + padding
			and position.Z >= minZ - padding and position.Z <= maxZ + padding
	end

	local function collectCandidates(root, data, context)
		local cash = getCash(context)
		for _, descendant in ipairs(root:GetDescendants()) do
			local name = lower(descendant.Name)
			local inPurchaseContainer = hasAncestorNamed(descendant, root, PURCHASE_CONTAINER_WORDS)
			local inMachineContainer = hasAncestorNamed(descendant, root, MACHINE_ANCESTOR_WORDS)
			local explicitPrice = hasExplicitPrice(descendant)
			local isPurchaseNamed = hasAny(name, { "button", "buy", "purchase" })
			local isButton = (isPurchaseNamed or explicitPrice) and (inPurchaseContainer or isPurchaseNamed) and not inMachineContainer
			local isDrop = not isButton and hasAny(name, { "drop", "cash", "money", "collect", "collector" })

			if isButton and hasTouchInterest(descendant) and #data.buttons < context.CONFIG.maxButtons then
				if isBlockedInteraction(descendant) then
					data.paidSkipped = data.paidSkipped + 1
				else
					local price = extractPrice(descendant)
					if price and price > 0 then
						table.insert(data.buttons, {
							object = descendant,
							part = getTouchPart(descendant),
							price = price,
							affordable = price <= cash,
							locked = price > cash,
							paidPurchase = false,
							ownerMatch = data.ownerMatch,
							ownerVerified = data.ownerVerified,
							root = data.root,
							name = descendant.Name,
						})
					else
						data.paidSkipped = data.paidSkipped + 1
					end
				end
			elseif isDrop and not isBlockedInteraction(descendant) and hasCollectorActivation(descendant) and #data.drops < context.CONFIG.maxDrops then
				table.insert(data.drops, {
					object = descendant,
					part = getTouchPart(descendant),
					prompt = getPrompt(descendant),
					clickDetector = getClickDetector(descendant),
					ownerMatch = data.ownerMatch,
					ownerVerified = data.ownerVerified,
					root = data.root,
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
				local inside = localPlayerInsideRoot(context, child)
				if score >= 8 or owned then
					table.insert(roots, {
						root = child,
						score = owned and (score + 100) or (inside and (score + 35) or score),
						rawScore = score,
						ownerMatch = owned or inside,
						ownerSource = owned and "owner" or (inside and "position" or "none"),
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
			ownerSource = selected and selected.ownerSource or "none",
			ownerVerified = selected and selected.ownerSource == "owner" or false,
			buttons = {},
			drops = {},
			cash = getCash(context),
			owned = selected ~= nil,
			maxLabels = context.CONFIG.maxLabels or 16,
			paidSkipped = 0,
		}
		data.safeAutomation = not context.CONFIG.requireOwnerMatch or data.ownerMatch

		if context.CONFIG.requireOwnerMatch and not data.ownerMatch then
			data.affordableCount = 0
			data.lockedCount = 0
			data.totalButtons = 0
			data.progressPercent = 0
			data.debug = string.format("%s | owner no | automation blocked", data.rootName)
			return data
		end

		collectCandidates(data.root, data, context)

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
			"%s | owner %s:%s | blocked %d | buttons %d | drops %d",
			data.rootName,
			data.ownerMatch and "yes" or "no",
			data.ownerSource or "none",
			data.paidSkipped,
			#data.buttons,
			#data.drops
		)

		return data
	end

	return {
		scan = scan,
	}
end
