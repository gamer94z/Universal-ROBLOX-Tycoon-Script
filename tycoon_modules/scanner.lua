-- Performance-hardening scanner wrapper.
-- Adds a local-player player-list cash resolver on top of the adaptive scanner.
-- This handles games where spendable cash is replicated only in a custom player-list row.

local BASE_URL = "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/0354ba4cc688a08552ba07bf2875f514fadb9b75/tycoon_modules/scanner.lua"

return function(context)
	local source = game:HttpGet(BASE_URL)
	local chunk = loadstring(source)
	if type(chunk) ~= "function" then return nil end
	local factory = chunk()
	if type(factory) ~= "function" then return nil end

	local base = factory(context)
	if type(base) ~= "table" or type(base.scan) ~= "function" then return nil end

	local fallbackGetCash = context.getCash
	local selectedCash
	local selectedRow
	local lastSearch = -math.huge
	local SEARCH_COOLDOWN = 2.0
	local MAX_LIST_INSPECT = 1800
	local MAX_ROW_INSPECT = 120
	local lastPrinted

	local function lower(v) return tostring(v or ""):lower() end
	local function compact(v) return lower(v):gsub("[^%w]", "") end

	local function parseNumber(v)
		if type(base.parseCompactNumber) == "function" then
			local ok, n = pcall(base.parseCompactNumber, v)
			if ok and tonumber(n) ~= nil then return tonumber(n) end
		end
		local text = lower(v):gsub(",", "")
		if text:find("/s", 1, true) or text:find("/sec", 1, true) or text:find("per second", 1, true) then return nil end
		local num, suffix = text:match("([%d]+%.?[%d]*)%s*([kmbtq])")
		if not num then num = text:match("([%d]+%.?[%d]*)"); suffix = "" end
		local n = tonumber(num)
		if not n then return nil end
		local mult = ({k=1e3,m=1e6,b=1e9,t=1e12,q=1e15})[suffix] or 1
		return n * mult
	end

	local function playerIdentityScore(node)
		local player = context.LOCAL_PLAYER
		if not player or not node then return 0 end
		local username = compact(player.Name)
		local displayName = compact(player.DisplayName)
		local userId = tostring(player.UserId)
		local score = 0

		local function scoreText(value)
			local c = compact(value)
			if c == "" then return 0 end
			if c == username then return 500 end
			if displayName ~= "" and c == displayName then return 420 end
			if c == userId then return 520 end
			if #username >= 4 and c:find(username, 1, true) then return 280 end
			if displayName ~= "" and #displayName >= 4 and c:find(displayName, 1, true) then return 220 end
			return 0
		end

		score = math.max(score, scoreText(node.Name))
		if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
			score = math.max(score, scoreText(node.Text))
		end
		if node:IsA("ImageLabel") or node:IsA("ImageButton") then
			local image = tostring(node.Image or "")
			if image:find(userId, 1, true) then score = math.max(score, 500) end
		end
		if node:IsA("ObjectValue") and node.Value == player then score = math.max(score, 520) end
		if node:IsA("StringValue") or node:IsA("IntValue") or node:IsA("NumberValue") then
			local ok, value = pcall(function() return node.Value end)
			if ok then score = math.max(score, scoreText(value)) end
		end
		local ok, attrs = pcall(function() return node:GetAttributes() end)
		if ok and type(attrs) == "table" then
			for key, value in pairs(attrs) do
				local k = lower(key)
				if k:find("player", 1, true) or k:find("user", 1, true) or k:find("owner", 1, true) or k:find("name", 1, true) then
					score = math.max(score, scoreText(value))
				end
			end
		end
		return score
	end

	local function rowIdentityScore(row)
		if not row then return 0 end
		local best = playerIdentityScore(row)
		local queue = { row }
		local cursor, inspected = 1, 0
		while cursor <= #queue and inspected < MAX_ROW_INSPECT do
			local current = queue[cursor]
			cursor = cursor + 1
			best = math.max(best, playerIdentityScore(current))
			if best >= 500 then return best end
			for _, child in ipairs(current:GetChildren()) do
				inspected = inspected + 1
				if inspected <= MAX_ROW_INSPECT then table.insert(queue, child) end
				if inspected >= MAX_ROW_INSPECT then break end
			end
		end
		return best
	end

	local function cashLabelScore(object)
		if not object or not object.Parent or not (object:IsA("TextLabel") or object:IsA("TextButton")) then return nil end
		local text = tostring(object.Text or "")
		local ltext = lower(text)
		if ltext == "" or ltext:find("/s",1,true) or ltext:find("/sec",1,true) or ltext:find("per second",1,true)
			or ltext:find("income",1,true) or ltext:find("rate",1,true) then return nil end
		local value = parseNumber(text)
		if value == nil then return nil end
		local name = lower(object.Name)
		local score = 0
		if name == "cash" or name == "money" or name == "balance" then score = score + 300
		elseif name:find("cash",1,true) or name:find("money",1,true) or name:find("balance",1,true) or name:find("wallet",1,true) then score = score + 220 end
		if ltext:find("$",1,true) or ltext:find("£",1,true) or ltext:find("€",1,true) or ltext:find("¥",1,true) then score = score + 80 end
		if score == 0 then return nil end
		return score, value
	end

	local function findCashInsideRow(row)
		local bestObject, bestScore, bestValue
		local queue = { row }
		local cursor, inspected = 1, 0
		while cursor <= #queue and inspected < MAX_ROW_INSPECT do
			local current = queue[cursor]
			cursor = cursor + 1
			local score, value = cashLabelScore(current)
			if score and (not bestScore or score > bestScore) then
				bestObject, bestScore, bestValue = current, score, value
			end
			for _, child in ipairs(current:GetChildren()) do
				inspected = inspected + 1
				if inspected <= MAX_ROW_INSPECT then table.insert(queue, child) end
				if inspected >= MAX_ROW_INSPECT then break end
			end
		end
		return bestObject, bestValue
	end

	local function scanPlayerLists()
		local player = context.LOCAL_PLAYER
		local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then return nil end

		local queue = { playerGui }
		local cursor, inspected = 1, 0
		local scrollingFrames = {}
		while cursor <= #queue and inspected < MAX_LIST_INSPECT do
			local current = queue[cursor]
			cursor = cursor + 1
			if current:IsA("ScrollingFrame") then
				local ancestry = ""
				local a, depth = current, 0
				while a and depth <= 6 do ancestry = ancestry .. " " .. lower(a.Name); a = a.Parent; depth = depth + 1 end
				if ancestry:find("playerlist",1,true) or ancestry:find("player list",1,true) or ancestry:find("leaderboard",1,true) then
					table.insert(scrollingFrames, current)
				end
			end
			for _, child in ipairs(current:GetChildren()) do
				inspected = inspected + 1
				if inspected <= MAX_LIST_INSPECT then table.insert(queue, child) end
				if inspected >= MAX_LIST_INSPECT then break end
			end
		end

		local bestObject, bestRow, bestIdentity, bestValue
		for _, scrolling in ipairs(scrollingFrames) do
			for _, row in ipairs(scrolling:GetChildren()) do
				if row:IsA("GuiObject") then
					local identity = rowIdentityScore(row)
					if identity > 0 then
						local cashObject, value = findCashInsideRow(row)
						if cashObject and (not bestIdentity or identity > bestIdentity) then
							bestObject, bestRow, bestIdentity, bestValue = cashObject, row, identity, value
						end
					end
				end
			end
		end

		if bestObject then
			selectedCash = bestObject
			selectedRow = bestRow
			return bestValue
		end
		return nil
	end

	local function readSelected()
		if not selectedCash or not selectedCash.Parent or not selectedRow or not selectedRow.Parent then
			selectedCash, selectedRow = nil, nil
			return nil
		end
		if rowIdentityScore(selectedRow) <= 0 then
			selectedCash, selectedRow = nil, nil
			return nil
		end
		local _, value = cashLabelScore(selectedCash)
		return value
	end

	local function bridgedCash()
		local value = readSelected()
		local now = os.clock()
		if value == nil and now - lastSearch >= SEARCH_COOLDOWN then
			lastSearch = now
			value = scanPlayerLists()
		end
		if value ~= nil then
			if selectedCash ~= lastPrinted then
				lastPrinted = selectedCash
				print("[0xVyrs Tycoon] local cash row -> " .. selectedCash:GetFullName() .. " = " .. tostring(value))
			end
			return value
		end
		if type(fallbackGetCash) == "function" then
			local ok, fallback = pcall(fallbackGetCash)
			if ok then return tonumber(fallback) end
		end
		return nil
	end

	context.getCash = bridgedCash

	local function syncCash(data)
		if not data then return data end
		local cash = tonumber(bridgedCash())
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
			data.debug.cashSource = selectedCash and selectedCash:GetFullName() or data.debug.cashSource
		end
		return data
	end

	return {
		scan = function(scanContext) return syncCash(base.scan(scanContext or context)) end,
		parseCompactNumber = base.parseCompactNumber or parseNumber,
		invalidateRoot = function(root)
			selectedCash, selectedRow = nil, nil
			if base.invalidateRoot then return base.invalidateRoot(root) end
		end,
	}
end
