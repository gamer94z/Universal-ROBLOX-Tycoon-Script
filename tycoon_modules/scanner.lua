return function()
	local CACHE_TTL = 20
	local MAX_ROOT_DEPTH = 5
	local cache = {
		purchaseContainers = {},
		collectorCandidates = {},
		bounds = {},
	}

	local PRICE_NAMES = {
		cost = true,
		price = true,
		amount = true,
		cash = true,
		money = true,
	}

	local PAID_PURCHASE_WORDS = {
		"robux",
		"gamepass",
		"game pass",
		"developer product",
		"dev product",
		"productid",
		"product id",
		"developerproductid",
		"developer product id",
		"gamepassid",
		"game pass id",
		"passid",
		"pass id",
		"assetid",
		"asset id",
		"robuxprice",
		"robux price",
		"premium",
		"r$",
		"rbx",
	}

	local BLOCKED_INTERACTION_WORDS = {
		"watch ad",
		"watch_ad",
		"video ad",
		"rewarded ad",
		"advert",
		"advertisement",
		"sponsor",
		"free cash",
		"free money",
		"free coins",
		"double cash",
		"2x cash",
		"invite",
		"discord",
		"twitter",
		"starterpack",
		"starter pack",
		"gamepass",
		"developer product",
		"premium",
		"robux",
	}

	local PURCHASE_CONTAINER_WORDS = {
		"buttons",
		"button",
		"buybuttons",
		"purchasebuttons",
		"pads",
		"purchasepads",
		"buyitems",
		"buy pads",
	}

	local COLLECTOR_WORDS = {
		"drop",
		"cash",
		"money",
		"collect",
		"collector",
	}

	local function lower(text)
		return tostring(text or ""):lower()
	end

	local function trim(text)
		return tostring(text or ""):match("^%s*(.-)%s*$")
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

	local function isContainer(object)
		return object and (object:IsA("Model") or object:IsA("Folder"))
	end

	local function isPriceName(name)
		local clean = lower(name):gsub("%s+", ""):gsub("_", "")
		return PRICE_NAMES[clean]
			or clean:find("cost", 1, true) ~= nil
			or clean:find("price", 1, true) ~= nil
	end

	local function parseCompactNumber(value)
		if type(value) == "number" then
			return value > 0 and value or nil
		end

		local text = lower(value):gsub(",", ""):gsub("_", " ")
		local scientific = text:match("([%d%.]+[eE][%+%-]?%d+)")
		if scientific then
			local parsed = tonumber(scientific)
			if parsed and parsed > 0 then
				return parsed
			end
		end

		local numberText, suffix = text:match("([%d]+%.?[%d]*)%s*([kmbt])")
		if not numberText then
			numberText = text:match("([%d]+%.?[%d]*)")
			suffix = ""
		end

		local number = tonumber(numberText)
		if not number or number <= 0 then
			return nil
		end

		local multiplier = 1
		if suffix == "k" or text:find("thousand", 1, true) then
			multiplier = 1e3
		elseif suffix == "m" or text:find("million", 1, true) then
			multiplier = 1e6
		elseif suffix == "b" or text:find("billion", 1, true) then
			multiplier = 1e9
		elseif suffix == "t" or text:find("trillion", 1, true) then
			multiplier = 1e12
		elseif text:find("quadrillion", 1, true) then
			multiplier = 1e15
		elseif text:find("quintillion", 1, true) then
			multiplier = 1e18
		end

		return number * multiplier
	end

	local function hasCashPriceText(text)
		if not parseCompactNumber(text) then
			return false
		end

		local clean = lower(text)
		return clean:find("$", 1, true) ~= nil
			or clean:find("£", 1, true) ~= nil
			or clean:find("€", 1, true) ~= nil
			or clean:find("¥", 1, true) ~= nil
			or clean:find("cash", 1, true) ~= nil
			or clean:find("money", 1, true) ~= nil
			or clean:find("coin", 1, true) ~= nil
			or clean:find("cost", 1, true) ~= nil
			or clean:find("price", 1, true) ~= nil
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

	local function extractPrice(object)
		if isPriceName(object.Name) and (object:IsA("IntValue") or object:IsA("NumberValue") or object:IsA("StringValue")) then
			local direct = parseCompactNumber(object.Value)
			if direct then
				return direct
			end
		end

		for _, descendant in ipairs(object:GetDescendants()) do
			if isPriceName(descendant.Name) and (descendant:IsA("IntValue") or descendant:IsA("NumberValue") or descendant:IsA("StringValue")) then
				local value = parseCompactNumber(descendant.Value)
				if value then
					return value
				end
			end
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				if hasCashPriceText(descendant.Text) then
					local value = parseCompactNumber(descendant.Text)
					if value then
						return value
					end
				end
			end
		end
		return nil
	end

	local function hasExplicitPrice(object)
		if isPriceName(object.Name) and (object:IsA("IntValue") or object:IsA("NumberValue") or object:IsA("StringValue")) then
			return true
		end
		for _, descendant in ipairs(object:GetDescendants()) do
			if isPriceName(descendant.Name) and (descendant:IsA("IntValue") or descendant:IsA("NumberValue") or descendant:IsA("StringValue")) then
				return true
			end
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				if hasCashPriceText(descendant.Text) then
					return true
				end
			end
		end
		return false
	end

	local function partHasTouchInterest(part)
		if not part or not part:IsA("BasePart") then
			return false
		end
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("TouchTransmitter") then
				return true
			end
		end
		return false
	end

	local function getTouchPart(object)
		if object:IsA("BasePart") and partHasTouchInterest(object) then
			return object
		end
		if object:IsA("Model") and object.PrimaryPart and partHasTouchInterest(object.PrimaryPart) then
			return object.PrimaryPart
		end
		for _, descendant in ipairs(object:GetDescendants()) do
			if descendant:IsA("BasePart") and partHasTouchInterest(descendant) then
				return descendant
			end
		end
		return nil
	end

	local function getReferencePart(object)
		local touchPart = getTouchPart(object)
		if touchPart then
			return touchPart
		end
		if object:IsA("BasePart") then
			return object
		end
		if object:IsA("Model") and object.PrimaryPart then
			return object.PrimaryPart
		end
		for _, descendant in ipairs(object:GetDescendants()) do
			if descendant:IsA("BasePart") then
				return descendant
			end
		end

		local current = object.Parent
		while current and current ~= workspace do
			if current:IsA("BasePart") then
				return current
			end
			current = current.Parent
		end
		return nil
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

	local function getInteraction(object)
		return getTouchPart(object), getPrompt(object), getClickDetector(object)
	end

	local function hasActivation(object)
		local touchPart, prompt, clickDetector = getInteraction(object)
		return touchPart ~= nil or prompt ~= nil or clickDetector ~= nil
	end

	local function isPurchaseContainer(object)
		return isContainer(object) and hasAny(object.Name, PURCHASE_CONTAINER_WORDS)
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

	local function getPurchaseContainers(root)
		local now = os.clock()
		local cached = cache.purchaseContainers[root]
		if cached and cached.expires > now then
			return cached.items
		end

		local containers = {}
		for _, descendant in ipairs(root:GetDescendants()) do
			if isPurchaseContainer(descendant) then
				table.insert(containers, descendant)
			end
		end
		cache.purchaseContainers[root] = { items = containers, expires = now + CACHE_TTL }
		return containers
	end

	local function getCollectorCandidates(root)
		local now = os.clock()
		local cached = cache.collectorCandidates[root]
		if cached and cached.expires > now then
			return cached.items
		end

		local candidates = {}
		for _, descendant in ipairs(root:GetDescendants()) do
			if hasAny(descendant.Name, COLLECTOR_WORDS) and not isPurchaseContainer(descendant) then
				table.insert(candidates, descendant)
			end
		end
		cache.collectorCandidates[root] = { items = candidates, expires = now + CACHE_TTL }
		return candidates
	end

	local function hasOwnerAttribute(object)
		local ok, attributes = pcall(function()
			return object:GetAttributes()
		end)
		if not ok or type(attributes) ~= "table" then
			return false
		end
		for key in pairs(attributes) do
			if lower(key):find("owner", 1, true) then
				return true
			end
		end
		return false
	end

	local function getLocalStructureScore(object)
		if not isContainer(object) then
			return 0
		end

		local score = 0
		local name = lower(object.Name)
		if name:find("tycoon", 1, true) then score = score + 10 end
		if name:find("base", 1, true) then score = score + 4 end
		if name:find("plot", 1, true) then score = score + 4 end
		if name:find("factory", 1, true) then score = score + 3 end
		if hasOwnerAttribute(object) then score = score + 7 end

		local directPurchase = false
		local directPurchased = false
		local directDrops = false
		local directOwner = false
		local nearbyPurchase = false
		local nearbyPurchased = false
		local nearbyDrops = false
		local nearbyOwner = false

		for _, child in ipairs(object:GetChildren()) do
			local childName = lower(child.Name)
			if isPurchaseContainer(child) then directPurchase = true end
			if childName:find("purchasedobjects", 1, true) or childName == "purchased" then directPurchased = true end
			if childName:find("drops", 1, true) or childName:find("collector", 1, true) then directDrops = true end
			if childName:find("owner", 1, true) or hasOwnerAttribute(child) then directOwner = true end

			if isContainer(child) then
				for _, grandchild in ipairs(child:GetChildren()) do
					local grandchildName = lower(grandchild.Name)
					if isPurchaseContainer(grandchild) then nearbyPurchase = true end
					if grandchildName:find("purchasedobjects", 1, true) or grandchildName == "purchased" then nearbyPurchased = true end
					if grandchildName:find("drops", 1, true) or grandchildName:find("collector", 1, true) then nearbyDrops = true end
					if grandchildName:find("owner", 1, true) or hasOwnerAttribute(grandchild) then nearbyOwner = true end
				end
			end
		end

		if directPurchase then score = score + 9 elseif nearbyPurchase then score = score + 7 end
		if directPurchased then score = score + 5 elseif nearbyPurchased then score = score + 3 end
		if directDrops then score = score + 4 elseif nearbyDrops then score = score + 2 end
		if directOwner then score = score + 7 elseif nearbyOwner then score = score + 4 end
		return score
	end

	local function walkPotentialRoots(parent, depth, output)
		if depth > MAX_ROOT_DEPTH then
			return
		end
		for _, child in ipairs(parent:GetChildren()) do
			if isContainer(child) then
				local score = getLocalStructureScore(child)
				if score >= 7 then
					table.insert(output, { root = child, rawScore = score })
				end
				walkPotentialRoots(child, depth + 1, output)
			end
		end
	end

	local function ownerValueMatches(context, value)
		if type(value) == "number" then
			return tonumber(value) == context.LOCAL_PLAYER.UserId
		end
		if type(value) == "string" then
			local clean = lower(trim(value))
			return clean == lower(context.LOCAL_PLAYER.Name)
				or clean == lower(context.LOCAL_PLAYER.DisplayName)
				or tonumber(clean) == context.LOCAL_PLAYER.UserId
		end
		return false
	end

	local function ownerSignalMatches(context, object)
		local ok, attributes = pcall(function()
			return object:GetAttributes()
		end)
		if ok and type(attributes) == "table" then
			for key, value in pairs(attributes) do
				if lower(key):find("owner", 1, true) and ownerValueMatches(context, value) then
					return true
				end
			end
		end

		local name = lower(object.Name)
		local parentName = object.Parent and lower(object.Parent.Name) or ""
		if not name:find("owner", 1, true) and not parentName:find("owner", 1, true) then
			return false
		end

		local playerName = lower(context.LOCAL_PLAYER.Name)
		local displayName = lower(context.LOCAL_PLAYER.DisplayName)
		if object:IsA("ObjectValue") then
			return object.Value == context.LOCAL_PLAYER
		elseif object:IsA("StringValue") then
			return ownerValueMatches(context, object.Value)
		elseif object:IsA("IntValue") or object:IsA("NumberValue") then
			return tonumber(object.Value) == context.LOCAL_PLAYER.UserId
		elseif object:IsA("TextLabel") or object:IsA("TextButton") then
			local text = lower(object.Text)
			return text:find(playerName, 1, true) ~= nil or text:find(displayName, 1, true) ~= nil
		end
		return false
	end

	local function markVerifiedOwners(context, candidates)
		local candidateByRoot = {}
		for _, candidate in ipairs(candidates) do
			candidateByRoot[candidate.root] = candidate
			candidate.ownerVerified = false
		end

		for _, descendant in ipairs(workspace:GetDescendants()) do
			if ownerSignalMatches(context, descendant) then
				local current = descendant
				while current and current ~= workspace do
					local candidate = candidateByRoot[current]
					if candidate then
						candidate.ownerVerified = true
						break
					end
					current = current.Parent
				end
			end
		end
	end

	local function getRootBounds(root)
		local now = os.clock()
		local cached = cache.bounds[root]
		if cached and cached.expires > now then
			return cached
		end

		local bounds
		if root:IsA("Model") then
			local ok, cframe, size = pcall(function()
				return root:GetBoundingBox()
			end)
			if ok and cframe and size then
				bounds = { cframe = cframe, size = size }
			end
		end

		if not bounds then
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
			if found then
				bounds = {
					minX = minX, minY = minY, minZ = minZ,
					maxX = maxX, maxY = maxY, maxZ = maxZ,
				}
			end
		end

		bounds = bounds or {}
		bounds.expires = now + CACHE_TTL
		cache.bounds[root] = bounds
		return bounds
	end

	local function localPlayerInsideRoot(context, root)
		local localRoot = context.getLocalRoot and context.getLocalRoot()
		if not localRoot or not root then
			return false
		end
		local bounds = getRootBounds(root)
		local padding = 35

		if bounds.cframe and bounds.size then
			local localPosition = bounds.cframe:PointToObjectSpace(localRoot.Position)
			return math.abs(localPosition.X) <= (bounds.size.X * 0.5) + padding
				and math.abs(localPosition.Y) <= (bounds.size.Y * 0.5) + padding
				and math.abs(localPosition.Z) <= (bounds.size.Z * 0.5) + padding
		end
		if not bounds.minX then
			return false
		end
		local position = localRoot.Position
		return position.X >= bounds.minX - padding and position.X <= bounds.maxX + padding
			and position.Y >= bounds.minY - padding and position.Y <= bounds.maxY + padding
			and position.Z >= bounds.minZ - padding and position.Z <= bounds.maxZ + padding
	end

	local function countStrongChildRoots(candidate, candidateByRoot)
		local count = 0
		for _, child in ipairs(candidate.root:GetChildren()) do
			local nested = candidateByRoot[child]
			if nested and nested.rawScore >= 7 then
				count = count + 1
			end
		end
		return count
	end

	local function findTycoonRoots(context)
		local candidates = {}
		walkPotentialRoots(workspace, 1, candidates)
		markVerifiedOwners(context, candidates)

		local candidateByRoot = {}
		for _, candidate in ipairs(candidates) do
			candidateByRoot[candidate.root] = candidate
		end

		for _, candidate in ipairs(candidates) do
			candidate.inside = localPlayerInsideRoot(context, candidate.root)
			local nestedPenalty = countStrongChildRoots(candidate, candidateByRoot) * 18
			candidate.score = candidate.rawScore
				+ (candidate.ownerVerified and 1000 or 0)
				+ (candidate.inside and 45 or 0)
				- nestedPenalty
		end

		table.sort(candidates, function(a, b)
			if a.ownerVerified ~= b.ownerVerified then
				return a.ownerVerified
			end
			return a.score > b.score
		end)
		return candidates
	end

	local function qualifyPurchaseObject(object)
		if not object or not object.Parent or not hasExplicitPrice(object) or not hasActivation(object) then
			return false
		end
		if isBlockedInteraction(object) then
			return false
		end
		return extractPrice(object) ~= nil
	end

	local function findNestedPurchaseObject(containerChild)
		if qualifyPurchaseObject(containerChild) then
			return containerChild
		end
		for _, descendant in ipairs(containerChild:GetDescendants()) do
			if (descendant:IsA("Model") or descendant:IsA("BasePart")) and qualifyPurchaseObject(descendant) then
				return descendant
			end
		end
		return nil
	end

	local function getCash(context)
		return tonumber(context.getCash()) or 0
	end

	local function collectCandidates(root, data, context)
		local cash = getCash(context)
		local seenButtons = {}
		local seenDrops = {}

		for _, container in ipairs(getPurchaseContainers(root)) do
			if container and container.Parent then
				for _, child in ipairs(container:GetChildren()) do
					if #data.buttons >= context.CONFIG.maxButtons then
						break
					end
					local candidate = findNestedPurchaseObject(child)
					if candidate and not seenButtons[candidate] and not hasAncestorNamed(candidate, root, { "purchasedobjects", "purchased" }) then
						seenButtons[candidate] = true
						local price = extractPrice(candidate)
						local touchPart, prompt, clickDetector = getInteraction(candidate)
						if price and (touchPart or prompt or clickDetector) then
							table.insert(data.buttons, {
								object = candidate,
								part = getReferencePart(candidate),
								touchPart = touchPart,
								prompt = prompt,
								clickDetector = clickDetector,
								price = price,
								affordable = price <= cash,
								locked = price > cash,
								paidPurchase = false,
								ownerMatch = data.ownerMatch,
								ownerVerified = data.ownerVerified,
								automationAllowed = data.automationAllowed,
								root = data.root,
								name = candidate.Name,
							})
						end
					elseif child and child.Parent and isBlockedInteraction(child) then
						data.paidSkipped = data.paidSkipped + 1
					end
				end
			end
		end

		for _, candidate in ipairs(getCollectorCandidates(root)) do
			if #data.drops >= context.CONFIG.maxDrops then
				break
			end
			if candidate.Parent and not seenDrops[candidate] and not isBlockedInteraction(candidate) and not hasAncestorNamed(candidate, root, PURCHASE_CONTAINER_WORDS) then
				local touchPart, prompt, clickDetector = getInteraction(candidate)
				if touchPart or prompt or clickDetector then
					seenDrops[candidate] = true
					table.insert(data.drops, {
						object = candidate,
						part = getReferencePart(candidate),
						touchPart = touchPart,
						prompt = prompt,
						clickDetector = clickDetector,
						ownerMatch = data.ownerMatch,
						ownerVerified = data.ownerVerified,
						automationAllowed = data.automationAllowed,
						root = data.root,
						name = candidate.Name,
					})
				end
			end
		end
	end

	local function scan(context)
		local roots = findTycoonRoots(context)
		local selected = roots[1]
		local ownerVerified = selected and selected.ownerVerified or false
		local automationAllowed = ownerVerified or context.CONFIG.requireOwnerMatch == false

		local data = {
			root = selected and selected.root or workspace,
			rootName = selected and selected.root.Name or "Workspace",
			confidence = selected and math.clamp(selected.rawScore * 7 + (ownerVerified and 30 or 0), 0, 100) or 0,
			rootScore = selected and selected.rawScore or 0,
			ownerMatch = ownerVerified,
			ownerVerified = ownerVerified,
			ownerSource = ownerVerified and "owner" or (selected and selected.inside and "position" or "structure"),
			selectedByPosition = selected and selected.inside or false,
			automationAllowed = automationAllowed,
			buttons = {},
			drops = {},
			cash = getCash(context),
			owned = ownerVerified,
			maxLabels = context.CONFIG.maxLabels or 16,
			paidSkipped = 0,
		}
		data.safeAutomation = automationAllowed

		if not selected then
			data.affordableCount = 0
			data.lockedCount = 0
			data.totalButtons = 0
			data.progressPercent = 0
			data.debug = "no tycoon root detected"
			return data
		end

		if context.CONFIG.requireOwnerMatch and not ownerVerified then
			data.affordableCount = 0
			data.lockedCount = 0
			data.totalButtons = 0
			data.progressPercent = 0
			data.debug = string.format("%s | owner unverified | automation blocked", data.rootName)
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
			if a.affordable ~= b.affordable then
				return a.affordable
			end
			return (a.price or math.huge) < (b.price or math.huge)
		end)

		data.affordableCount = affordable
		data.lockedCount = locked
		data.totalButtons = #data.buttons
		data.progressPercent = 0
		data.debug = string.format(
			"%s | owner %s:%s | blocked %d | buttons %d | drops %d",
			data.rootName,
			ownerVerified and "yes" or "no",
			data.ownerSource,
			data.paidSkipped,
			#data.buttons,
			#data.drops
		)
		return data
	end

	return {
		scan = scan,
		parseCompactNumber = parseCompactNumber,
	}
end
