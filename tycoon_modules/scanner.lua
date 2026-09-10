-- Performance-hardening scanner wrapper.
-- Adds a second-stage GUI-aware currency resolver on top of the structural,
-- ownership-aware hardening scanner. This keeps purchase affordability safe
-- while supporting tycoons that expose the spendable balance only in PlayerGui.

local BASE_URL = "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/9cf3977bd4954337dd0f30d56d852fceb75ff95f/tycoon_modules/scanner.lua"

return function(context)
	local source = game:HttpGet(BASE_URL)
	local chunk = loadstring(source)
	if type(chunk) ~= "function" then return nil end
	local factory = chunk()
	if type(factory) ~= "function" then return nil end

	-- The base factory installs the structural scanner, generic ownership rules,
	-- and Value/attribute currency discovery first.
	local base = factory(context)
	if type(base) ~= "table" or type(base.scan) ~= "function" then return nil end

	local previousGetCash = context.getCash
	local guiSource
	local guiSourceScore = 0
	local lastGuiSearch = -math.huge
	local GUI_SEARCH_COOLDOWN = 2.0
	local MAX_GUI_INSPECT = 520

	local function lower(value)
		return tostring(value or ""):lower()
	end

	local function clean(value)
		return lower(value):gsub("[^%w]", "")
	end

	local function parseCompactNumber(value)
		if type(value) == "number" then return value >= 0 and value or nil end
		local text = lower(value):gsub(",", ""):gsub("_", " ")
		local scientific = text:match("([%d%.]+e[%+%-]?%d+)")
		if scientific then
			local n = tonumber(scientific)
			if n and n >= 0 then return n end
		end
		local numberText, suffix = text:match("([%d]+%.?[%d]*)%s*([kmbtq])")
		if not numberText then
			numberText = text:match("([%d]+%.?[%d]*)")
			suffix = ""
		end
		local n = tonumber(numberText)
		if not n or n < 0 then return nil end
		local multiplier = 1
		if suffix == "k" or text:find("thousand", 1, true) then multiplier = 1e3
		elseif suffix == "m" or text:find("million", 1, true) then multiplier = 1e6
		elseif suffix == "b" or text:find("billion", 1, true) then multiplier = 1e9
		elseif suffix == "t" or text:find("trillion", 1, true) then multiplier = 1e12
		elseif suffix == "q" or text:find("quadrillion", 1, true) then multiplier = 1e15
		elseif text:find("quintillion", 1, true) then multiplier = 1e18 end
		return n * multiplier
	end

	local RATE_WORDS = {
		"/s", "/sec", "per sec", "per second", "income", "rate", "cash/sec",
		"money/sec", "coins/sec", "cps", "dps", "rpm",
	}
	local PRICE_WORDS = {
		"cost", "price", "buy", "purchase", "upgrade", "unlock", "locked",
		"required", "requirement", "shop", "store", "gamepass", "premium", "robux",
		"reward", "rebirth", "prestige",
	}
	local NON_CASH_WORDS = {
		"gem", "diamond", "crystal", "token", "ticket", "star", "xp", "level",
	}
	local CASH_STRONG = { "cash", "money", "balance", "wallet", "fund" }
	local CASH_WEAK = { "coin", "credit", "currency", "gold" }

	local function hasAny(text, words)
		text = lower(text)
		for _, word in ipairs(words) do
			if text:find(word, 1, true) then return true end
		end
		return false
	end

	local function guiVisible(object)
		local current = object
		local depth = 0
		while current and depth <= 8 do
			if current:IsA("GuiObject") and current.Visible == false then return false end
			if current:IsA("LayerCollector") and current.Enabled == false then return false end
			current = current.Parent
			depth = depth + 1
		end
		return true
	end

	local function ancestorContext(object)
		local pieces = {}
		local current = object
		local depth = 0
		while current and depth <= 5 do
			table.insert(pieces, tostring(current.Name or ""))
			current = current.Parent
			depth = depth + 1
		end
		return lower(table.concat(pieces, " "))
	end

	local function candidateScore(object)
		if not object or not object.Parent then return nil, nil end
		if not (object:IsA("TextLabel") or object:IsA("TextButton")) then return nil, nil end
		if not guiVisible(object) then return nil, nil end

		local text = tostring(object.Text or "")
		local lowered = lower(text)
		if lowered == "" or hasAny(lowered, RATE_WORDS) or hasAny(lowered, PRICE_WORDS) then return nil, nil end
		if lowered:find("%%", 1, true) then return nil, nil end

		local value = parseCompactNumber(text)
		if value == nil then return nil, nil end

		local contextText = ancestorContext(object)
		if hasAny(contextText, RATE_WORDS) or hasAny(contextText, PRICE_WORDS) then return nil, nil end
		if hasAny(contextText, NON_CASH_WORDS) and not hasAny(contextText, CASH_STRONG) then return nil, nil end

		local score = 0
		local objectName = lower(object.Name)
		local hasCurrencySymbol = lowered:find("$", 1, true) ~= nil
			or lowered:find("£", 1, true) ~= nil
			or lowered:find("€", 1, true) ~= nil
			or lowered:find("¥", 1, true) ~= nil

		if hasCurrencySymbol then score = score + 35 end
		if hasAny(objectName, CASH_STRONG) then score = score + 85
		elseif hasAny(objectName, CASH_WEAK) then score = score + 45 end
		if hasAny(contextText, CASH_STRONG) then score = score + 75
		elseif hasAny(contextText, CASH_WEAK) then score = score + 35 end

		-- Bare numeric labels are only accepted when their UI ancestry strongly
		-- identifies them as the player's wallet/balance display.
		if not hasCurrencySymbol and not hasAny(contextText, CASH_STRONG) and not hasAny(objectName, CASH_STRONG) then
			return nil, nil
		end
		if score < 70 then return nil, nil end
		return score, value
	end

	local function readGuiSource()
		if not guiSource or not guiSource.Parent then return nil end
		local score, value = candidateScore(guiSource)
		if not score then
			guiSource = nil
			guiSourceScore = 0
			return nil
		end
		guiSourceScore = score
		return value
	end

	local function findGuiSource()
		local player = context.LOCAL_PLAYER
		local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then return nil end

		local bestObject, bestScore, bestValue
		local queue = { playerGui }
		local cursor = 1
		local inspected = 0
		while cursor <= #queue and inspected < MAX_GUI_INSPECT do
			local current = queue[cursor]
			cursor = cursor + 1
			local score, value = candidateScore(current)
			if score and (not bestScore or score > bestScore or (score == bestScore and value > (bestValue or -1))) then
				bestObject, bestScore, bestValue = current, score, value
			end
			for _, child in ipairs(current:GetChildren()) do
				inspected = inspected + 1
				if inspected <= MAX_GUI_INSPECT then table.insert(queue, child) end
				if inspected >= MAX_GUI_INSPECT then break end
			end
		end
		guiSource = bestObject
		guiSourceScore = bestScore or 0
		return bestValue
	end

	local function safePreviousCash()
		if type(previousGetCash) ~= "function" then return nil end
		local ok, value = pcall(previousGetCash)
		return ok and tonumber(value) or nil
	end

	local function finalGetCash()
		local guiValue = readGuiSource()
		local previousValue = safePreviousCash()

		local now = os.clock()
		if guiValue == nil and now - lastGuiSearch >= GUI_SEARCH_COOLDOWN then
			lastGuiSearch = now
			guiValue = findGuiSource()
		end

		-- A high-confidence wallet label wins over a stale/ambiguous zero Value.
		-- Otherwise retain the normal player-data source when it is usable.
		if guiValue ~= nil and guiSourceScore >= 100 then return guiValue end
		if previousValue ~= nil and previousValue > 0 then return previousValue end
		if guiValue ~= nil then return guiValue end
		return previousValue
	end

	context.getCash = finalGetCash

	local function syncCash(data)
		if not data then return data end
		local cash = tonumber(finalGetCash())
		if cash == nil then return data end
		data.cash = cash
		local affordable, locked = 0, 0
		for _, button in ipairs(data.buttons or {}) do
			if not button.paidPurchase and button.object and button.object.Parent then
				local price = tonumber(button.price)
				if price ~= nil then
					button.affordable = price <= cash
					button.locked = price > cash
					if button.affordable then affordable = affordable + 1 else locked = locked + 1 end
				end
			end
		end
		data.affordableCount = affordable
		data.lockedCount = locked
		if data.debug then
			data.debug.guiCurrencySource = guiSource and guiSource:GetFullName() or nil
			data.debug.guiCurrencyScore = guiSourceScore
		end
		return data
	end

	local function scan(scanContext)
		local data = base.scan(scanContext or context)
		return syncCash(data)
	end

	return {
		scan = scan,
		parseCompactNumber = base.parseCompactNumber or parseCompactNumber,
		invalidateRoot = base.invalidateRoot,
	}
end
