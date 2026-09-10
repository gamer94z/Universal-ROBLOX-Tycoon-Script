return function(context)
	local HttpService = context.HttpService
	local PROFILE_FILE = "tycoon_brain.json"
	local PROFILE_VERSION = 1
	local placeKey = tostring(game.PlaceId)

	local CATEGORY_WEIGHTS = {
		income = 120,
		upgrader = 110,
		generator = 105,
		conveyor = 78,
		unlock = 72,
		utility = 48,
		unknown = 42,
		structure = 18,
		cosmetic = 4,
	}

	local INCOME_WORDS = { "dropper", "miner", "mine", "generator", "printer", "farm", "oil", "cash", "money", "income", "factory" }
	local UPGRADER_WORDS = { "upgrader", "upgrade", "multiplier", "multiply", "enhancer", "processor", "refiner", "furnace" }
	local CONVEYOR_WORDS = { "conveyor", "belt", "ore track", "oretrack" }
	local UNLOCK_WORDS = { "stairs", "stair", "floor", "unlock", "bridge", "elevator", "lift", "extension", "expand", "gate" }
	local STRUCTURE_WORDS = { "wall", "window", "door", "roof", "fence", "railing", "pillar", "ceiling", "path" }
	local COSMETIC_WORDS = { "decor", "decoration", "sign", "poster", "plant", "tree", "chair", "table", "light", "lamp", "statue", "colour", "color", "paint" }

	local profileStore = { version = PROFILE_VERSION, places = {} }
	local profile
	local lastSnapshot = {}
	local pendingPurchase
	local lastPlan
	local noButtonsSince
	local lastCash
	local lastCashAt
	local observedIncomePerSecond = 0

	local function lower(value)
		return tostring(value or ""):lower()
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

	local function canUseFileApi()
		return type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function"
	end

	local function loadStore()
		if not canUseFileApi() or not isfile(PROFILE_FILE) then
			return
		end
		pcall(function()
			local decoded = HttpService:JSONDecode(readfile(PROFILE_FILE))
			if type(decoded) == "table" and type(decoded.places) == "table" then
				profileStore = decoded
			end
		end)
	end

	local function saveStore()
		if not canUseFileApi() then
			return
		end
		pcall(function()
			writefile(PROFILE_FILE, HttpService:JSONEncode(profileStore))
		end)
	end

	local function ensureProfile()
		profileStore.version = PROFILE_VERSION
		profileStore.places = profileStore.places or {}
		profileStore.places[placeKey] = profileStore.places[placeKey] or {
			runs = 0,
			nodes = {},
			edges = {},
			categoryStats = {},
			bestCompletionSeconds = nil,
			lastCompletionSeconds = nil,
		}
		profile = profileStore.places[placeKey]
		profile.nodes = profile.nodes or {}
		profile.edges = profile.edges or {}
		profile.categoryStats = profile.categoryStats or {}
		return profile
	end

	local function normaliseName(name)
		local text = lower(name)
		text = text:gsub("%b[]", " ")
		text = text:gsub("%$[%d%.,]+[%a]*", " ")
		text = text:gsub("[%d%.,]+%s*[kmbt]?", " ")
		text = text:gsub("[^%w]+", " ")
		text = text:gsub("%s+", " ")
		text = text:match("^%s*(.-)%s*$") or text
		return text ~= "" and text or "unnamed"
	end

	local function relativeParentHint(button)
		local object = button and button.object
		local root = button and button.root
		if not object then
			return ""
		end
		local parts = {}
		local current = object.Parent
		local depth = 0
		while current and current ~= root and current ~= workspace and depth < 2 do
			table.insert(parts, 1, normaliseName(current.Name))
			current = current.Parent
			depth = depth + 1
		end
		return table.concat(parts, "/")
	end

	local function signature(button)
		if not button then
			return nil
		end
		return normaliseName(button.name or (button.object and button.object.Name)) .. "|" .. relativeParentHint(button)
	end

	local function classify(button)
		local object = button and button.object
		local textParts = { button and button.name or "", relativeParentHint(button) }
		if object then
			local count = 0
			for _, descendant in ipairs(object:GetDescendants()) do
				if count >= 30 then break end
				count = count + 1
				table.insert(textParts, descendant.Name)
				if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
					table.insert(textParts, descendant.Text)
				elseif descendant:IsA("StringValue") then
					table.insert(textParts, tostring(descendant.Value))
				end
			end
		end
		local text = lower(table.concat(textParts, " "))

		if hasAny(text, UPGRADER_WORDS) then return "upgrader" end
		if hasAny(text, INCOME_WORDS) then
			if text:find("generator", 1, true) then return "generator" end
			return "income"
		end
		if hasAny(text, CONVEYOR_WORDS) then return "conveyor" end
		if hasAny(text, UNLOCK_WORDS) then return "unlock" end
		if hasAny(text, COSMETIC_WORDS) then return "cosmetic" end
		if hasAny(text, STRUCTURE_WORDS) then return "structure" end
		return "unknown"
	end

	local function getNode(button)
		local key = signature(button)
		if not key then return nil, nil end
		local node = profile.nodes[key]
		if not node then
			node = {
				name = button.name or (button.object and button.object.Name) or key,
				category = classify(button),
				seen = 0,
				purchased = 0,
				failures = 0,
				avgPrice = 0,
				avgIncomeDelta = 0,
				unlockCount = 0,
			}
			profile.nodes[key] = node
		end
		return key, node
	end

	local function snapshot(data)
		local result = {}
		if data and data.buttons then
			for _, button in ipairs(data.buttons) do
				if not button.paidPurchase then
					local key = signature(button)
					if key then result[key] = true end
				end
			end
		end
		return result
	end

	local function updateIncomeEstimate(cash)
		cash = tonumber(cash)
		local now = os.clock()
		if cash and lastCash and lastCashAt and now > lastCashAt then
			local delta = cash - lastCash
			local elapsed = now - lastCashAt
			if delta > 0 and elapsed > 0.2 then
				local rate = delta / elapsed
				if observedIncomePerSecond <= 0 then
					observedIncomePerSecond = rate
				else
					observedIncomePerSecond = observedIncomePerSecond * 0.8 + rate * 0.2
				end
			end
		end
		if cash then
			lastCash = cash
			lastCashAt = now
		end
	end

	local function observe(data, stats)
		ensureProfile()
		updateIncomeEstimate(data and data.cash)

		local current = snapshot(data)
		if data and data.buttons then
			for _, button in ipairs(data.buttons) do
				local _, node = getNode(button)
				if node then
					node.seen = (node.seen or 0) + 1
					local price = tonumber(button.price) or 0
					if node.avgPrice == 0 then
						node.avgPrice = price
					else
						node.avgPrice = node.avgPrice * 0.9 + price * 0.1
					end
				end
			end
		end

		if pendingPurchase then
			local unlocked = {}
			for key in pairs(current) do
				if not pendingPurchase.beforeSnapshot[key] then
					table.insert(unlocked, key)
				end
			end

			local sourceNode = profile.nodes[pendingPurchase.key]
			if sourceNode then
				sourceNode.purchased = (sourceNode.purchased or 0) + 1
				sourceNode.unlockCount = math.max(sourceNode.unlockCount or 0, #unlocked)
				local currentRate = stats and tonumber(stats.cashPerMinute)
				if currentRate and pendingPurchase.cashPerMinute then
					local delta = currentRate - pendingPurchase.cashPerMinute
					if delta > 0 then
						sourceNode.avgIncomeDelta = (sourceNode.avgIncomeDelta or 0) * 0.7 + delta * 0.3
					end
				end
			end

			if #unlocked > 0 then
				profile.edges[pendingPurchase.key] = profile.edges[pendingPurchase.key] or {}
				for _, childKey in ipairs(unlocked) do
					profile.edges[pendingPurchase.key][childKey] = (profile.edges[pendingPurchase.key][childKey] or 0) + 1
				end
			end
			pendingPurchase = nil
			saveStore()
		end

		lastSnapshot = current
		if data and data.totalButtons == 0 and data.ownerVerified then
			noButtonsSince = noButtonsSince or os.clock()
		else
			noButtonsSince = nil
		end
	end

	local function notePurchase(button, data, stats)
		ensureProfile()
		local key, node = getNode(button)
		if not key then return end
		pendingPurchase = {
			key = key,
			beforeSnapshot = snapshot(data),
			cashPerMinute = stats and tonumber(stats.cashPerMinute) or 0,
			at = os.clock(),
		}
		if node then
			node.category = node.category or classify(button)
		end
	end

	local function noteFailure(button)
		ensureProfile()
		local _, node = getNode(button)
		if node then
			node.failures = (node.failures or 0) + 1
		end
	end

	local function scoreButton(button, data, stats)
		ensureProfile()
		local key, node = getNode(button)
		if not node then return -math.huge end
		local category = node.category or classify(button)
		local score = CATEGORY_WEIGHTS[category] or CATEGORY_WEIGHTS.unknown
		local price = math.max(0, tonumber(button.price) or 0)
		local cash = math.max(0, tonumber(data and data.cash) or 0)

		local learnedUnlocks = node.unlockCount or 0
		local learnedIncome = node.avgIncomeDelta or 0
		score = score + math.min(80, learnedUnlocks * 18)
		score = score + math.min(90, learnedIncome / 100)

		local edges = profile.edges[key]
		if edges then
			local edgeCount = 0
			for _ in pairs(edges) do edgeCount = edgeCount + 1 end
			score = score + math.min(55, edgeCount * 12)
		end

		if price == 0 then
			score = score + 35
		elseif cash > 0 then
			local spendRatio = price / cash
			if spendRatio <= 0.15 then score = score + 26
			elseif spendRatio <= 0.4 then score = score + 18
			elseif spendRatio <= 0.75 then score = score + 8
			elseif spendRatio > 0.95 then score = score - 8 end
		end

		if category == "income" or category == "upgrader" or category == "generator" then
			score = score + math.max(0, 28 - math.log(math.max(price, 1), 10) * 3)
		end
		score = score - math.min(80, (node.failures or 0) * 16)

		if button.failureCount then score = score - button.failureCount * 20 end
		if button.blockedUntil and button.blockedUntil > os.clock() then return -math.huge end
		if button.paidPurchase or not button.affordable then return -math.huge end

		return score
	end

	local function choosePurchase(data, stats)
		if not data or not data.buttons then return nil end
		local best, bestScore
		for _, button in ipairs(data.buttons) do
			local score = scoreButton(button, data, stats)
			if not bestScore or score > bestScore then
				best = button
				bestScore = score
			end
		end
		if best then
			local key, node = getNode(best)
			lastPlan = {
				key = key,
				name = best.name,
				category = node and node.category or "unknown",
				price = best.price,
				score = bestScore,
				at = os.clock(),
			}
		else
			lastPlan = nil
		end
		return best, bestScore
	end

	local function estimateETA(data, stats)
		if not data then return nil end
		local ratePerMinute = stats and tonumber(stats.cashPerMinute) or 0
		if ratePerMinute <= 0 and observedIncomePerSecond > 0 then
			ratePerMinute = observedIncomePerSecond * 60
		end
		if ratePerMinute <= 0 then return nil end

		local remainingCost = 0
		local remainingCount = 0
		for _, button in ipairs(data.buttons or {}) do
			if not button.paidPurchase then
				remainingCost = remainingCost + math.max(0, tonumber(button.price) or 0)
				remainingCount = remainingCount + 1
			end
		end
		if remainingCount == 0 then return 0 end
		local cash = math.max(0, tonumber(data.cash) or 0)
		local unfunded = math.max(0, remainingCost - cash)
		local economySeconds = unfunded / (ratePerMinute / 60)
		local interactionSeconds = remainingCount * 0.35
		return economySeconds + interactionSeconds
	end

	local function isLikelyComplete(data)
		return data and data.ownerVerified and data.totalButtons == 0 and noButtonsSince and (os.clock() - noButtonsSince) >= 3
	end

	local function markRunComplete(seconds)
		ensureProfile()
		profile.runs = (profile.runs or 0) + 1
		if seconds then
			profile.lastCompletionSeconds = seconds
			if not profile.bestCompletionSeconds or seconds < profile.bestCompletionSeconds then
				profile.bestCompletionSeconds = seconds
			end
		end
		saveStore()
	end

	local function resetPlaceProfile()
		profileStore.places[placeKey] = nil
		profile = nil
		lastSnapshot = {}
		pendingPurchase = nil
		lastPlan = nil
		ensureProfile()
		saveStore()
	end

	local function getStatus(data, stats)
		ensureProfile()
		local nodeCount, edgeCount = 0, 0
		for _ in pairs(profile.nodes) do nodeCount = nodeCount + 1 end
		for _, children in pairs(profile.edges) do
			for _ in pairs(children) do edgeCount = edgeCount + 1 end
		end
		return {
			placeId = game.PlaceId,
			runs = profile.runs or 0,
			learnedNodes = nodeCount,
			learnedEdges = edgeCount,
			plan = lastPlan,
			etaSeconds = estimateETA(data, stats),
			complete = isLikelyComplete(data),
			observedIncomePerSecond = observedIncomePerSecond,
			bestCompletionSeconds = profile.bestCompletionSeconds,
		}
	end

	loadStore()
	ensureProfile()

	return {
		observe = observe,
		notePurchase = notePurchase,
		noteFailure = noteFailure,
		classify = classify,
		scoreButton = scoreButton,
		choosePurchase = choosePurchase,
		estimateETA = estimateETA,
		isLikelyComplete = isLikelyComplete,
		markRunComplete = markRunComplete,
		resetPlaceProfile = resetPlaceProfile,
		getStatus = getStatus,
		save = saveStore,
	}
end
