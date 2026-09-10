-- Performance-hardening scanner wrapper.
-- Reuses the structural scanner pinned at a known-good commit, adds generic
-- ownership recognition for player-named plots, and installs a bounded
-- currency reader for games that do not expose cash through leaderstats.

local BASE_URL = "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/07768b7b71e3999b9fdd065004b278803b3dff5e/tycoon_modules/scanner.lua"

return function(context)
	local source = game:HttpGet(BASE_URL)
	local chunk = loadstring(source)
	if type(chunk) ~= "function" then
		return nil
	end

	local factory = chunk()
	if type(factory) ~= "function" then
		return nil
	end

	local function lower(value)
		return tostring(value or ""):lower()
	end

	local function clean(value)
		return lower(value):gsub("[^%w]", "")
	end

	-- Currency discovery is intentionally limited to the local player's tree.
	-- It does not inspect remotes or attempt to modify server-side currency.
	local originalGetCash = context.getCash
	local cashSource
	local lastCashSearch = -math.huge
	local CASH_SEARCH_COOLDOWN = 3.5
	local MAX_DATA_INSPECT = 320
	local MAX_GUI_INSPECT = 180
	local CASH_EXACT = {
		cash = true, money = true, coins = true, coin = true,
		balance = true, credits = true, credit = true,
		funds = true, fund = true, currency = true, gold = true,
	}
	local CASH_HINTS = {
		"cash", "money", "coin", "balance", "credit",
		"fund", "currency", "wallet", "gold",
	}

	local function cashNameScore(name, parentName)
		local key = clean(name)
		local score = CASH_EXACT[key] and 100 or 0
		for _, hint in ipairs(CASH_HINTS) do
			if key:find(hint, 1, true) then
				score = math.max(score, 62)
			end
		end
		if score == 0 then
			return nil
		end

		local parent = lower(parentName)
		if parent == "leaderstats" then score = score + 32 end
		if parent:find("data", 1, true) or parent:find("stat", 1, true)
			or parent:find("wallet", 1, true) or parent:find("currency", 1, true)
			or parent:find("profile", 1, true) then
			score = score + 20
		end
		return score
	end

	local function readCashSource(sourceInfo)
		if not sourceInfo or not sourceInfo.object or not sourceInfo.object.Parent then
			return nil
		end
		if sourceInfo.kind == "value" then
			local ok, value = pcall(function() return sourceInfo.object.Value end)
			return ok and tonumber(value) or nil
		end
		if sourceInfo.kind == "attribute" then
			local ok, value = pcall(function() return sourceInfo.object:GetAttribute(sourceInfo.key) end)
			return ok and tonumber(value) or nil
		end
		return nil
	end

	local function considerValue(best, item)
		if not item or not item.Parent then return best end
		if not (item:IsA("IntValue") or item:IsA("NumberValue") or item:IsA("StringValue")) then
			return best
		end
		local ok, raw = pcall(function() return item.Value end)
		if not ok or tonumber(raw) == nil then return best end
		local score = cashNameScore(item.Name, item.Parent and item.Parent.Name)
		if not score then return best end
		if not best or score > best.score then
			return { kind = "value", object = item, score = score }
		end
		return best
	end

	local function considerAttributes(best, object)
		if not object then return best end
		local ok, attributes = pcall(function() return object:GetAttributes() end)
		if not ok or type(attributes) ~= "table" then return best end
		for key, value in pairs(attributes) do
			if tonumber(value) ~= nil then
				local score = cashNameScore(key, object.Name)
				if score and (not best or score > best.score) then
					best = { kind = "attribute", object = object, key = key, score = score }
				end
			end
		end
		return best
	end

	local function scanChildrenBounded(root, limit, best)
		if not root then return best end
		local queue = { root }
		local cursor = 1
		local inspected = 0
		while cursor <= #queue and inspected < limit do
			local current = queue[cursor]
			cursor = cursor + 1
			best = considerValue(best, current)
			best = considerAttributes(best, current)
			for _, child in ipairs(current:GetChildren()) do
				inspected = inspected + 1
				if inspected <= limit then
					table.insert(queue, child)
				end
				if inspected >= limit then break end
			end
		end
		return best
	end

	local function findCashSource()
		local player = context.LOCAL_PLAYER
		if not player then return nil end
		local best

		-- Prefer normal player data and avoid walking large UI trees unless needed.
		for _, child in ipairs(player:GetChildren()) do
			if not child:IsA("PlayerGui") and not child:IsA("PlayerScripts") then
				best = scanChildrenBounded(child, MAX_DATA_INSPECT, best)
			end
		end
		best = considerAttributes(best, player)

		if not best then
			local playerGui = player:FindFirstChildOfClass("PlayerGui")
			best = scanChildrenBounded(playerGui, MAX_GUI_INSPECT, best)
		end
		return best
	end

	local function enhancedGetCash()
		local cached = readCashSource(cashSource)
		if cached ~= nil then return cached end
		cashSource = nil

		local now = os.clock()
		if now - lastCashSearch >= CASH_SEARCH_COOLDOWN then
			lastCashSearch = now
			cashSource = findCashSource()
			cached = readCashSource(cashSource)
			if cached ~= nil then return cached end
		end

		if type(originalGetCash) == "function" then
			local ok, value = pcall(originalGetCash)
			if ok then return tonumber(value) end
		end
		return nil
	end

	context.getCash = enhancedGetCash

	local base = factory(context)
	if type(base) ~= "table" or type(base.scan) ~= "function" then
		return nil
	end

	local latestData
	local activeToken = context.SHARED_ENV and context.SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN

	local function playerNameMatches(instance)
		if not instance or not context.LOCAL_PLAYER then
			return false
		end

		local name = clean(instance.Name)
		local username = clean(context.LOCAL_PLAYER.Name)
		local displayName = clean(context.LOCAL_PLAYER.DisplayName)
		local userId = tostring(context.LOCAL_PLAYER.UserId)

		if name ~= username and name ~= displayName and name ~= userId then
			return false
		end

		local parent = instance.Parent
		local parentName = parent and lower(parent.Name) or ""
		return parentName:find("tycoon", 1, true) ~= nil
			or parentName:find("plot", 1, true) ~= nil
			or parentName:find("base", 1, true) ~= nil
			or parentName:find("player", 1, true) ~= nil
			or parentName:find("land", 1, true) ~= nil
	end

	local function rootHasPlayerOwnership(root)
		local current = root
		local depth = 0
		while current and current ~= workspace and depth <= 8 do
			if playerNameMatches(current) then return true end
			current = current.Parent
			depth = depth + 1
		end
		return false
	end

	local function syncCash(data)
		if not data then return data end
		local cash = tonumber(enhancedGetCash())
		if cash == nil then return data end
		data.cash = cash
		local affordable = 0
		local locked = 0
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
			data.debug.currencySource = cashSource and ((cashSource.object and cashSource.object:GetFullName()) or "attribute") or "runtime"
		end
		return data
	end

	local function applyOwnership(data, required)
		if not data then return data end
		local namedOwner = rootHasPlayerOwnership(data.root)
		local verified = data.ownerVerified == true or data.selectedByPosition == true or namedOwner
		local allowed = required == false or verified

		data.ownerMatch = verified
		data.ownerVerified = verified
		data.automationAllowed = allowed
		data.safeAutomation = allowed
		if namedOwner then data.ownerSource = "player-named-plot" end

		if data.debug then
			data.debug.ownerSource = data.ownerSource
			data.debug.playerNamedOwner = namedOwner
		end

		for _, list in ipairs({ data.buttons or {}, data.drops or {} }) do
			for _, entry in ipairs(list) do
				entry.ownerMatch = verified
				entry.ownerVerified = verified
				entry.automationAllowed = allowed
			end
		end
		return syncCash(data)
	end

	local function scan(scanContext)
		scanContext = scanContext or context
		local required = scanContext.CONFIG.requireOwnerMatch
		scanContext.CONFIG.requireOwnerMatch = false
		local data = base.scan(scanContext)
		scanContext.CONFIG.requireOwnerMatch = required
		latestData = applyOwnership(data, required)
		return latestData
	end

	local spawn = task and task.spawn or coroutine.wrap
	spawn(function()
		while context.SHARED_ENV and context.SHARED_ENV.__VYRS_TYCOON_ACTIVE_TOKEN == activeToken do
			if task and task.wait then task.wait(0.5) else wait(0.5) end
			if latestData then syncCash(latestData) end
		end
	end)

	return {
		scan = scan,
		parseCompactNumber = base.parseCompactNumber,
		invalidateRoot = function(root)
			latestData = nil
			if base.invalidateRoot then return base.invalidateRoot(root) end
		end,
	}
end
