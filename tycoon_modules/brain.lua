return function(context)
	local HttpService = context.HttpService
	local CONFIG = context.CONFIG
	local PROFILE_FILE = "tycoon_brain.json"
	local PROFILE_VERSION = 2
	local placeKey = tostring(game.PlaceId)

	local STRATEGY_WEIGHTS = {
		Fastest = {
			income = 118, upgrader = 116, generator = 112, conveyor = 72,
			unlock = 105, utility = 48, unknown = 38, structure = 12, cosmetic = -8,
		},
		Income = {
			income = 150, upgrader = 148, generator = 142, conveyor = 92,
			unlock = 58, utility = 38, unknown = 25, structure = -8, cosmetic = -28,
		},
		Rebirth = {
			income = 112, upgrader = 108, generator = 106, conveyor = 66,
			unlock = 125, utility = 55, unknown = 45, structure = 28, cosmetic = 6,
		},
	}

	local CATEGORY_UNLOCK_VALUE = {
		income = 34,
		upgrader = 32,
		generator = 31,
		conveyor = 18,
		unlock = 28,
		utility = 10,
		unknown = 8,
		structure = 3,
		cosmetic = 0,
	}

	local INCOME_WORDS = { "dropper", "miner", "mine", "generator", "printer", "farm", "oil", "cash", "money", "income", "factory", "producer" }
	local UPGRADER_WORDS = { "upgrader", "upgrade", "multiplier", "multiply", "enhancer", "processor", "refiner", "furnace", "converter" }
	local CONVEYOR_WORDS = { "conveyor", "belt", "ore track", "oretrack" }
	local UNLOCK_WORDS = { "stairs", "stair", "floor", "unlock", "bridge", "elevator", "lift", "extension", "expand", "gate", "area", "room" }
	local STRUCTURE_WORDS = { "wall", "window", "door", "roof", "fence", "railing", "pillar", "ceiling", "path" }
	local COSMETIC_WORDS = { "decor", "decoration", "sign", "poster", "plant", "tree", "chair", "table", "light", "lamp", "statue", "colour", "color", "paint" }

	local profileStore = { version = PROFILE_VERSION, places = {} }
	local profile
	local lastSnapshot = {}
	local pendingEffects = {}
	local lastPlan
	local noButtonsSince
	local latestData
	local latestStats = {}
	local lastEconomyAt
	local lastCash
	local observedIncomePerSecond = 0
	local currentRun

	local function lower(value)
		return tostring(value or ""):lower()
	end

	local function hasAny(text, words)
		text = lower(text)
		for _, word in ipairs(words) do
			if text:find(word, 1, true) then return true end
		end
		return false
	end

	local function canUseFileApi()
		return type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function"
	end

	local function loadStore()
		if not canUseFileApi() or not isfile(PROFILE_FILE) then return end
		pcall(function()
			local decoded = HttpService:JSONDecode(readfile(PROFILE_FILE))
			if type(decoded) == "table" and type(decoded.places) == "table" then
				profileStore = decoded
			end
		end)
	end

	local function saveStore()
		if not canUseFileApi() then return end
		pcall(function()
			writefile(PROFILE_FILE, HttpService:JSONEncode(profileStore))
		end)
	end

	local function ensureProfile()
		profileStore.version = PROFILE_VERSION
		profileStore.places = profileStore.places or {}
		profileStore.places[placeKey] = profileStore.places[placeKey] or {}
		profile = profileStore.places[placeKey]
		profile.runs = profile.runs or 0
		profile.nodes = profile.nodes or {}
		profile.edges = profile.edges or {}
		profile.runHistory = profile.runHistory or {}
		profile.bestCompletionSeconds = profile.bestCompletionSeconds
		profile.lastCompletionSeconds = profile.lastCompletionSeconds
		profile.bestRoute = profile.bestRoute or {}
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
		if not object then return "" end
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
		if not button then return nil end
		return normaliseName(button.name or (button.object and button.object.Name)) .. "|" .. relativeParentHint(button)
	end

	local function classify(button)
		local object = button and button.object
		local textParts = { button and button.name or "", relativeParentHint(button) }
		if object then
			local count = 0
			for _, descendant in ipairs(object:GetDescendants()) do
				if count >= 24 then break end
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
		ensureProfile()
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
				roiSamples = 0,
				avgPaybackSeconds = nil,
				unlockCount = 0,
				unlockSamples = 0,
			}
			profile.nodes[key] = node
		end
		node.category = node.category or classify(button)
		node.roiSamples = node.roiSamples or 0
		node.unlockSamples = node.unlockSamples or 0
		node.unlockCount = node.unlockCount or 0
		return key, node
	end

	local function snapshot(data)
		local result = {}
		for _, button in ipairs(data and data.buttons or {}) do
			if not button.paidPurchase then
				local key = signature(button)
				if key then result[key] = true end
			end
		end
		return result
	end

	local function edgeInfo(sourceKey, childKey)
		local source = profile.edges[sourceKey]
		if not source then return nil end
		local edge = source[childKey]
		if type(edge) == "number" then
			edge = { count = edge, observations = edge }
			source[childKey] = edge
		end
		if type(edge) ~= "table" then return nil end
		edge.count = edge.count or 0
		edge.observations = edge.observations or edge.count
		return edge
	end

	local function addEdge(sourceKey, childKey)
		profile.edges[sourceKey] = profile.edges[sourceKey] or {}
		local edge = edgeInfo(sourceKey, childKey)
		if not edge then
			edge = { count = 0, observations = 0 }
			profile.edges[sourceKey][childKey] = edge
		end
		edge.count = edge.count + 1
		edge.observations = edge.observations + 1
	end

	local function beginRun(strategy)
		currentRun = {
			startedAt = os.clock(),
			strategy = strategy or CONFIG.strategy or "Fastest",
			purchases = 0,
			spent = 0,
			failures = 0,
			sequence = {},
			purchasedKeys = {},
			categoryCounts = {},
			waitingForCashSeconds = 0,
			peakCashPerMinute = 0,
		}
		pendingEffects = {}
		lastPlan = nil
		noButtonsSince = nil
	end

	local function ensureRun()
		if not currentRun then beginRun(CONFIG.strategy) end
		return currentRun
	end

	local function currentRatePerSecond(stats)
		local cpm = stats and tonumber(stats.cashPerMinute) or 0
		if cpm > 0 then return cpm / 60 end
		return observedIncomePerSecond
	end

	local function updateIncomeEstimate(cash, stats)
		local now = os.clock()
		cash = tonumber(cash)
		local directRate
		if cash and lastCash and lastEconomyAt and now > lastEconomyAt then
			local elapsed = now - lastEconomyAt
			local delta = cash - lastCash
			if delta > 0 and elapsed >= 0.4 then directRate = delta / elapsed end
		end
		local statsRate = stats and tonumber(stats.cashPerMinute)
		if statsRate and statsRate > 0 then statsRate = statsRate / 60 else statsRate = nil end
		local rate = statsRate or directRate
		if rate and rate >= 0 then
			if observedIncomePerSecond <= 0 then
				observedIncomePerSecond = rate
			else
				observedIncomePerSecond = observedIncomePerSecond * 0.72 + rate * 0.28
			end
		end
		if cash then lastCash = cash end
		lastEconomyAt = now
	end

	local function matureROI(stats)
		local now = os.clock()
		local rate = currentRatePerSecond(stats)
		for index = #pendingEffects, 1, -1 do
			local effect = pendingEffects[index]
			if now - effect.at >= 2.5 then
				local node = profile.nodes[effect.key]
				if node then
					local delta = math.max(0, rate - (effect.baselineRate or 0))
					if delta > 0 then
						local samples = node.roiSamples or 0
						local alpha = samples < 2 and 0.55 or 0.28
						node.avgIncomeDelta = (node.avgIncomeDelta or 0) * (1 - alpha) + delta * alpha
						node.roiSamples = samples + 1
						if effect.price > 0 then
							local payback = effect.price / delta
							if not node.avgPaybackSeconds then
								node.avgPaybackSeconds = payback
							else
								node.avgPaybackSeconds = node.avgPaybackSeconds * 0.7 + payback * 0.3
							end
						end
					end
				end
				table.remove(pendingEffects, index)
			end
		end
	end

	local function observeEconomy(cash, stats)
		latestStats = stats or latestStats
		local now = os.clock()
		local previousAt = lastEconomyAt
		updateIncomeEstimate(cash, latestStats)
		matureROI(latestStats)

		if currentRun then
			currentRun.peakCashPerMinute = math.max(currentRun.peakCashPerMinute or 0, tonumber(latestStats.cashPerMinute) or 0)
			if previousAt and latestData then
				local elapsed = math.min(2, math.max(0, now - previousAt))
				local hasAffordable = false
				for _, button in ipairs(latestData.buttons or {}) do
					if button.affordable and not button.paidPurchase then hasAffordable = true; break end
				end
				if not hasAffordable and (latestData.lockedCount or 0) > 0 then
					currentRun.waitingForCashSeconds = (currentRun.waitingForCashSeconds or 0) + elapsed
				end
			end
		end
	end

	local function resolveUnlockEffects(current)
		for _, effect in ipairs(pendingEffects) do
			if not effect.unlockResolved then
				local unlocked = {}
				for key in pairs(current) do
					if not effect.beforeSnapshot[key] then table.insert(unlocked, key) end
				end
				local node = profile.nodes[effect.key]
				if node then
					node.unlockSamples = (node.unlockSamples or 0) + 1
					node.unlockCount = (node.unlockCount or 0) * 0.7 + #unlocked * 0.3
				end
				for _, childKey in ipairs(unlocked) do addEdge(effect.key, childKey) end
				effect.unlockResolved = true
			end
		end
	end

	local function observe(data, stats)
		ensureProfile()
		latestData = data
		latestStats = stats or latestStats
		local current = snapshot(data)

		for _, button in ipairs(data and data.buttons or {}) do
			local _, node = getNode(button)
			if node then
				node.seen = (node.seen or 0) + 1
				local price = tonumber(button.price) or 0
				if not node.avgPrice or node.avgPrice == 0 then node.avgPrice = price
				else node.avgPrice = node.avgPrice * 0.86 + price * 0.14 end
			end
		end

		resolveUnlockEffects(current)
		lastSnapshot = current
		if data and data.totalButtons == 0 and data.ownerVerified then
			noButtonsSince = noButtonsSince or os.clock()
		else
			noButtonsSince = nil
		end
	end

	local function notePurchase(button, data, stats)
		ensureProfile()
		local run = ensureRun()
		local key, node = getNode(button)
		if not key or not node then return end

		local price = math.max(0, tonumber(button.price) or 0)
		node.purchased = (node.purchased or 0) + 1
		run.purchases = run.purchases + 1
		run.spent = run.spent + price
		run.purchasedKeys[key] = true
		run.categoryCounts[node.category] = (run.categoryCounts[node.category] or 0) + 1
		table.insert(run.sequence, key)

		table.insert(pendingEffects, {
			key = key,
			price = price,
			beforeSnapshot = snapshot(data),
			baselineRate = currentRatePerSecond(stats or latestStats),
			at = os.clock(),
			unlockResolved = false,
		})
		while #pendingEffects > 8 do table.remove(pendingEffects, 1) end
	end

	local function noteFailure(button)
		ensureProfile()
		local run = ensureRun()
		local _, node = getNode(button)
		if node then node.failures = (node.failures or 0) + 1 end
		run.failures = run.failures + 1
	end

	local function edgePotential(key, depth, visited)
		if depth <= 0 then return 0 end
		visited = visited or {}
		if visited[key] then return 0 end
		visited[key] = true
		local total = 0
		local children = profile.edges[key]
		if children then
			for childKey in pairs(children) do
				local edge = edgeInfo(key, childKey)
				local child = profile.nodes[childKey]
				if edge and child then
					local reliability = math.min(1, (edge.count or 0) / math.max(1, profile.nodes[key] and profile.nodes[key].purchased or 1))
					local value = CATEGORY_UNLOCK_VALUE[child.category or "unknown"] or 6
					total = total + value * (0.45 + reliability * 0.55)
					if depth > 1 then total = total + edgePotential(childKey, depth - 1, visited) * 0.35 end
				end
			end
		end
		visited[key] = nil
		return total
	end

	local function bestRouteBonus(key)
		if not currentRun or not profile.bestRoute or #profile.bestRoute == 0 then return 0 end
		for _, routeKey in ipairs(profile.bestRoute) do
			if not currentRun.purchasedKeys[routeKey] then
				return routeKey == key and 95 or 0
			end
		end
		return 0
	end

	local function scoreButton(button, data, stats)
		ensureProfile()
		local key, node = getNode(button)
		if not node then return -math.huge end
		if button.blockedUntil and button.blockedUntil > os.clock() then return -math.huge end
		if button.paidPurchase or not button.affordable then return -math.huge end

		local strategy = CONFIG.strategy or "Fastest"
		local weights = STRATEGY_WEIGHTS[strategy] or STRATEGY_WEIGHTS.Fastest
		local category = node.category or "unknown"
		local score = weights[category] or weights.unknown
		local price = math.max(0, tonumber(button.price) or 0)
		local cash = math.max(0, tonumber(data and data.cash) or 0)

		-- Dependency Graph 2.0: value reliable direct unlocks and two-hop branches.
		score = score + math.min(150, edgePotential(key, 2))
		score = score + math.min(70, (node.unlockCount or 0) * 18)

		-- Real ROI learning: known fast-payback purchases dominate later runs.
		if (node.roiSamples or 0) > 0 then
			local incomeDelta = math.max(0, node.avgIncomeDelta or 0)
			score = score + math.min(120, math.log(1 + incomeDelta) * 22)
			local payback = node.avgPaybackSeconds
			if payback then
				if payback <= 12 then score = score + 95
				elseif payback <= 25 then score = score + 70
				elseif payback <= 60 then score = score + 42
				elseif payback <= 120 then score = score + 18
				else score = score - 12 end
			end
		end

		if price == 0 then
			score = score + 42
		elseif cash > 0 then
			local spendRatio = price / cash
			if spendRatio <= 0.12 then score = score + 30
			elseif spendRatio <= 0.35 then score = score + 21
			elseif spendRatio <= 0.7 then score = score + 10
			elseif spendRatio > 0.96 then score = score - 8 end
		end

		if strategy == "Fastest" then score = score + bestRouteBonus(key) end
		if strategy == "Income" and (category == "income" or category == "upgrader" or category == "generator") then score = score + 38 end
		if strategy == "Rebirth" and category == "unlock" then score = score + 30 end

		-- Near the end, stop being precious about cosmetics/structure if they are
		-- the only things preventing completion.
		if data and (data.totalButtons or 0) <= 4 and (category == "structure" or category == "cosmetic" or category == "unknown") then
			score = score + 65
		end

		score = score - math.min(100, (node.failures or 0) * 14)
		if button.failureCount then score = score - button.failureCount * 22 end
		return score
	end

	local function choosePurchase(data, stats)
		if not data or not data.buttons then return nil end
		local best, bestScore
		for _, button in ipairs(data.buttons) do
			local score = scoreButton(button, data, stats)
			if not bestScore or score > bestScore then best, bestScore = button, score end
		end
		if best then
			local key, node = getNode(best)
			lastPlan = {
				key = key,
				name = best.name,
				category = node and node.category or "unknown",
				price = best.price,
				score = bestScore,
				paybackSeconds = node and node.avgPaybackSeconds or nil,
				incomeDelta = node and node.avgIncomeDelta or 0,
				strategy = CONFIG.strategy or "Fastest",
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
		if ratePerMinute <= 0 and observedIncomePerSecond > 0 then ratePerMinute = observedIncomePerSecond * 60 end
		local remainingCount = 0
		local remainingCost = 0
		for _, button in ipairs(data.buttons or {}) do
			if not button.paidPurchase then
				remainingCount = remainingCount + 1
				remainingCost = remainingCost + math.max(0, tonumber(button.price) or 0)
			end
		end
		if remainingCount == 0 then return 0 end

		local routeEstimate
		if currentRun and profile.bestCompletionSeconds and profile.bestRoute and #profile.bestRoute > 0 then
			local progress = math.min(0.95, currentRun.purchases / #profile.bestRoute)
			routeEstimate = math.max(0, profile.bestCompletionSeconds * (1 - progress))
		end

		local economyEstimate
		if ratePerMinute > 0 then
			local cash = math.max(0, tonumber(data.cash) or 0)
			local unfunded = math.max(0, remainingCost - cash)
			economyEstimate = unfunded / (ratePerMinute / 60) + remainingCount * 0.22
		end

		if routeEstimate and economyEstimate then return math.min(routeEstimate, economyEstimate * 1.25) end
		return routeEstimate or economyEstimate
	end

	local function getBottleneck(data, stats)
		if not data or not data.ownerVerified then return "waiting for tycoon" end
		if data.totalButtons == 0 then return noButtonsSince and "verifying completion" or "waiting for unlock" end

		local affordable = {}
		for _, button in ipairs(data.buttons or {}) do
			if button.affordable and not button.paidPurchase and not (button.blockedUntil and button.blockedUntil > os.clock()) then
				table.insert(affordable, button)
			end
		end
		if #affordable == 0 then
			if currentRatePerSecond(stats) <= 0 then return "no income detected" end
			if #(data.drops or {}) > 0 then return "waiting for collector" end
			return "waiting for cash"
		end

		if currentRun and currentRun.failures >= 3 and currentRun.failures >= math.max(3, currentRun.purchases * 0.3) then
			return "interaction failures"
		end

		local economic, unlocks, cleanup = 0, 0, 0
		for _, button in ipairs(affordable) do
			local category = classify(button)
			if category == "income" or category == "upgrader" or category == "generator" then economic = economic + 1
			elseif category == "unlock" then unlocks = unlocks + 1
			elseif category == "structure" or category == "cosmetic" then cleanup = cleanup + 1 end
		end
		if economic > 0 then return "scaling income" end
		if unlocks > 0 then return "unlocking progression" end
		if cleanup == #affordable then return "cleanup purchases" end
		return "buying upgrades"
	end

	local function isLikelyComplete(data)
		return data and data.ownerVerified and data.totalButtons == 0 and noButtonsSince and (os.clock() - noButtonsSince) >= 3
	end

	local function markRunComplete(seconds)
		ensureProfile()
		local run = ensureRun()
		seconds = tonumber(seconds) or (os.clock() - run.startedAt)
		profile.runs = (profile.runs or 0) + 1
		profile.lastCompletionSeconds = seconds

		local record = {
			seconds = seconds,
			purchases = run.purchases,
			spent = run.spent,
			failures = run.failures,
			waitingForCashSeconds = run.waitingForCashSeconds,
			peakCashPerMinute = run.peakCashPerMinute,
			strategy = run.strategy,
			categoryCounts = run.categoryCounts,
			at = os.time and os.time() or 0,
		}
		table.insert(profile.runHistory, record)
		while #profile.runHistory > 12 do table.remove(profile.runHistory, 1) end
		profile.lastRun = record

		if not profile.bestCompletionSeconds or seconds < profile.bestCompletionSeconds then
			profile.bestCompletionSeconds = seconds
			profile.bestRoute = {}
			for _, key in ipairs(run.sequence) do table.insert(profile.bestRoute, key) end
		end
		saveStore()
		beginRun(CONFIG.strategy)
	end

	local function resetPlaceProfile()
		profileStore.places[placeKey] = nil
		profile = nil
		lastSnapshot = {}
		pendingEffects = {}
		lastPlan = nil
		currentRun = nil
		ensureProfile()
		saveStore()
		return true
	end

	local function getStatus(data, stats)
		ensureProfile()
		data = data or latestData
		stats = stats or latestStats
		local nodeCount, edgeCount = 0, 0
		for _ in pairs(profile.nodes) do nodeCount = nodeCount + 1 end
		for sourceKey, children in pairs(profile.edges) do
			for childKey in pairs(children) do
				if edgeInfo(sourceKey, childKey) then edgeCount = edgeCount + 1 end
			end
		end

		return {
			placeId = game.PlaceId,
			strategy = CONFIG.strategy or "Fastest",
			runs = profile.runs or 0,
			learnedNodes = nodeCount,
			learnedEdges = edgeCount,
			plan = lastPlan,
			etaSeconds = estimateETA(data, stats),
			bottleneck = getBottleneck(data, stats),
			complete = isLikelyComplete(data),
			observedIncomePerSecond = observedIncomePerSecond,
			bestCompletionSeconds = profile.bestCompletionSeconds,
			lastCompletionSeconds = profile.lastCompletionSeconds,
			bestRouteLength = #(profile.bestRoute or {}),
			lastRun = profile.lastRun,
			currentRun = currentRun,
		}
	end

	loadStore()
	ensureProfile()

	return {
		observe = observe,
		observeEconomy = observeEconomy,
		beginRun = beginRun,
		notePurchase = notePurchase,
		noteFailure = noteFailure,
		classify = classify,
		scoreButton = scoreButton,
		choosePurchase = choosePurchase,
		estimateETA = estimateETA,
		getBottleneck = getBottleneck,
		isLikelyComplete = isLikelyComplete,
		markRunComplete = markRunComplete,
		resetPlaceProfile = resetPlaceProfile,
		getStatus = getStatus,
		save = saveStore,
	}
end
