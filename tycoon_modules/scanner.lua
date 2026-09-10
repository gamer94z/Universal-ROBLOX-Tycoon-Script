-- Performance-hardening scanner wrapper.
-- Adds an adaptive HUD currency resolver on top of the structural hardening scanner.
-- It can learn anonymous numeric wallet counters without mistaking rates/prices/ammo for cash.
-- Player-list cash is accepted only when the row is tied to the local player.

local BASE_URL = "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/87237a049e9cb6804265bda54d04c9d7605a1d0b/tycoon_modules/scanner.lua"

return function(context)
	local source = game:HttpGet(BASE_URL)
	local chunk = loadstring(source)
	if type(chunk) ~= "function" then return nil end
	local factory = chunk()
	if type(factory) ~= "function" then return nil end

	local base = factory(context)
	if type(base) ~= "table" or type(base.scan) ~= "function" then return nil end

	local previousGetCash = context.getCash
	local selected
	local selectedScore = 0
	local observations = setmetatable({}, { __mode = "k" })
	local lastSearch = -math.huge
	local SEARCH_COOLDOWN = 1.5
	local MAX_GUI_INSPECT = 520
	local lastPrintedSource

	local function lower(value) return tostring(value or ""):lower() end
	local function compact(value) return lower(value):gsub("[^%w]", "") end
	local function hasAny(text, words)
		text = lower(text)
		for _, word in ipairs(words) do
			if text:find(word, 1, true) then return true end
		end
		return false
	end

	local RATE_WORDS = { "/s", "/sec", "per sec", "per second", "income", "rate", "cash/sec", "money/sec", "cps", "dps", "rpm" }
	local PRICE_WORDS = { "cost", "price", "buy", "purchase", "upgrade", "unlock", "locked", "shop", "store", "gamepass", "premium", "robux", "rebirth", "prestige" }
	local NON_CASH_WORDS = {
		"gem", "diamond", "crystal", "token", "ticket", "star", "xp", "level",
		"ammo", "bullet", "magazine", "weapon", "hotbar", "inventory", "health", "hp",
		"kills", "deaths", "timer", "timeleft", "countdown", "ping", "fps", "streak", "round", "wave"
	}
	local CASH_STRONG = { "cash", "money", "balance", "wallet", "fund" }
	local CASH_WEAK = { "coin", "credit", "currency", "gold" }

	local function parseCompactNumber(value)
		if type(value) == "number" then return value >= 0 and value or nil end
		local text = lower(value):gsub(",", ""):gsub("_", " ")
		if hasAny(text, RATE_WORDS) or text:find("%%", 1, true) then return nil end
		local scientific = text:match("([%d%.]+e[%+%-]?%d+)")
		if scientific then
			local n = tonumber(scientific)
			if n and n >= 0 then return n end
		end
		local numberText, suffix = text:match("([%d]+%.?[%d]*)%s*([kmbtq])")
		if not numberText then numberText = text:match("([%d]+%.?[%d]*)"); suffix = "" end
		local n = tonumber(numberText)
		if not n or n < 0 then return nil end
		local mult = 1
		if suffix == "k" or text:find("thousand",1,true) then mult = 1e3
		elseif suffix == "m" or text:find("million",1,true) then mult = 1e6
		elseif suffix == "b" or text:find("billion",1,true) then mult = 1e9
		elseif suffix == "t" or text:find("trillion",1,true) then mult = 1e12
		elseif suffix == "q" or text:find("quadrillion",1,true) then mult = 1e15 end
		return n * mult
	end

	local function visible(object)
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

	local function contextText(object)
		local pieces = {}
		local current = object
		local depth = 0
		while current and depth <= 7 do
			table.insert(pieces, tostring(current.Name or ""))
			current = current.Parent
			depth = depth + 1
		end
		return lower(table.concat(pieces, " "))
	end

	local function textMatchesLocalPlayer(value)
		local player = context.LOCAL_PLAYER
		if not player then return false end
		local candidate = compact(value)
		if candidate == "" then return false end
		local username = compact(player.Name)
		local displayName = compact(player.DisplayName)
		local userId = tostring(player.UserId)
		return candidate == username
			or (displayName ~= "" and candidate == displayName)
			or candidate == userId
			or (#username >= 4 and candidate:find(username, 1, true) ~= nil)
	end

	local function ancestorContainsLocalPlayer(object)
		local current = object and object.Parent
		local depth = 0
		while current and depth <= 6 do
			local inspected = 0
			local queue = { current }
			local cursor = 1
			while cursor <= #queue and inspected < 48 do
				local node = queue[cursor]
				cursor = cursor + 1
				if node ~= object and (node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")) then
					if textMatchesLocalPlayer(node.Text) then return true end
				end
				if textMatchesLocalPlayer(node.Name) then return true end
				for _, child in ipairs(node:GetChildren()) do
					inspected = inspected + 1
					if inspected <= 48 then table.insert(queue, child) end
					if inspected >= 48 then break end
				end
			end
			current = current.Parent
			depth = depth + 1
		end
		return false
	end

	local function hasImageSibling(object)
		local parent = object and object.Parent
		if not parent then return false end
		for _, child in ipairs(parent:GetChildren()) do
			if child ~= object and (child:IsA("ImageLabel") or child:IsA("ImageButton")) and child.Visible ~= false then return true end
		end
		return false
	end

	local function greenDominant(object)
		local ok, colour = pcall(function() return object.TextColor3 end)
		if not ok or not colour then return false end
		return colour.G > colour.R * 1.18 and colour.G > colour.B * 1.12 and colour.G > 0.45
	end

	local function updateObservation(object, value)
		local now = os.clock()
		local obs = observations[object]
		if not obs then
			obs = { value = value, changes = 0, upward = 0, downward = 0, lastChange = -math.huge }
			observations[object] = obs
			return obs
		end
		if value ~= obs.value then
			obs.changes = math.min(8, obs.changes + 1)
			if value > obs.value then obs.upward = math.min(8, obs.upward + 1)
			elseif value < obs.value then obs.downward = math.min(8, obs.downward + 1) end
			obs.value = value
			obs.lastChange = now
		end
		return obs
	end

	local function scoreCandidate(object)
		if not object or not object.Parent or not (object:IsA("TextLabel") or object:IsA("TextButton")) or not visible(object) then return nil end
		local text = tostring(object.Text or "")
		local lowered = lower(text)
		if lowered == "" or hasAny(lowered, RATE_WORDS) or hasAny(lowered, PRICE_WORDS) then return nil end
		local value = parseCompactNumber(text)
		if value == nil then return nil end

		local ctx = contextText(object)
		if hasAny(ctx, RATE_WORDS) or hasAny(ctx, PRICE_WORDS) or hasAny(ctx, NON_CASH_WORDS) then return nil end

		local inPlayerList = ctx:find("playerlist", 1, true) ~= nil or ctx:find("leaderboard", 1, true) ~= nil
		local localPlayerRow = inPlayerList and ancestorContainsLocalPlayer(object) or false
		if inPlayerList and not localPlayerRow then return nil end

		local score = 0
		local name = lower(object.Name)
		local symbol = lowered:find("$",1,true) or lowered:find("£",1,true) or lowered:find("€",1,true) or lowered:find("¥",1,true)
		if symbol then score = score + 45 end
		if hasAny(name, CASH_STRONG) then score = score + 100 elseif hasAny(name, CASH_WEAK) then score = score + 48 end
		if hasAny(ctx, CASH_STRONG) then score = score + 90 elseif hasAny(ctx, CASH_WEAK) then score = score + 42 end
		if localPlayerRow then score = score + 260 end

		local imageSibling = hasImageSibling(object)
		if imageSibling then score = score + 24 end
		if greenDominant(object) then score = score + 24 end

		local bare = lowered:match("^%s*[%d][%d,%.]*%s*[kmbtq]?%s*$") ~= nil
		if bare then score = score + 8 end

		local obs = updateObservation(object, value)
		if obs.changes > 0 then score = score + math.min(60, obs.changes * 15) end
		if obs.upward > 0 then score = score + math.min(45, obs.upward * 15) end
		if os.clock() - obs.lastChange <= 4 then score = score + 25 end

		if not symbol and not hasAny(name, CASH_STRONG) and not hasAny(ctx, CASH_STRONG) and not localPlayerRow then
			local plausible = (imageSibling and greenDominant(object)) or obs.changes > 0
			if not plausible then return nil end
		end

		if score < 45 then return nil end
		return { object = object, value = value, score = score, localPlayerRow = localPlayerRow }
	end

	local function scanGui()
		local playerGui = context.LOCAL_PLAYER and context.LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui")
		if not playerGui then return nil end
		local best
		local queue = { playerGui }
		local cursor = 1
		local inspected = 0
		while cursor <= #queue and inspected < MAX_GUI_INSPECT do
			local current = queue[cursor]
			cursor = cursor + 1
			local candidate = scoreCandidate(current)
			if candidate and (not best or candidate.score > best.score or (candidate.score == best.score and candidate.value > best.value)) then best = candidate end
			for _, child in ipairs(current:GetChildren()) do
				inspected = inspected + 1
				if inspected <= MAX_GUI_INSPECT then table.insert(queue, child) end
				if inspected >= MAX_GUI_INSPECT then break end
			end
		end
		if best then selected = best.object; selectedScore = best.score end
		return best and best.value or nil
	end

	local function readSelected()
		if not selected or not selected.Parent then selected = nil; selectedScore = 0; return nil end
		local candidate = scoreCandidate(selected)
		if not candidate then selected = nil; selectedScore = 0; return nil end
		selectedScore = candidate.score
		return candidate.value
	end

	local function previousCash()
		if type(previousGetCash) ~= "function" then return nil end
		local ok, value = pcall(previousGetCash)
		return ok and tonumber(value) or nil
	end

	local function adaptiveGetCash()
		local oldValue = previousCash()
		local guiValue = readSelected()
		local now = os.clock()
		if (guiValue == nil or (oldValue == 0 and guiValue == 0)) and now - lastSearch >= SEARCH_COOLDOWN then
			lastSearch = now
			guiValue = scanGui()
		end

		local chosen
		if guiValue ~= nil and selectedScore >= 90 then chosen = guiValue
		elseif oldValue ~= nil and oldValue > 0 then chosen = oldValue
		elseif guiValue ~= nil and guiValue > 0 and selectedScore >= 45 then chosen = guiValue
		else chosen = oldValue or guiValue end

		if selected and selected ~= lastPrintedSource and chosen == guiValue then
			lastPrintedSource = selected
			print("[0xVyrs Tycoon] cash source -> " .. selected:GetFullName() .. " = " .. tostring(guiValue))
		end
		return chosen
	end

	context.getCash = adaptiveGetCash

	local function syncCash(data)
		if not data then return data end
		local cash = tonumber(adaptiveGetCash())
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
			data.debug.guiCurrencySource = selected and selected:GetFullName() or nil
			data.debug.guiCurrencyScore = selectedScore
		end
		return data
	end

	local function scan(scanContext)
		return syncCash(base.scan(scanContext or context))
	end

	return {
		scan = scan,
		parseCompactNumber = base.parseCompactNumber or parseCompactNumber,
		invalidateRoot = base.invalidateRoot,
	}
end
