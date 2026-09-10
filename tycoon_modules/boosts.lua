return function(context)
	local LOCAL_PLAYER = context.LOCAL_PLAYER

	local FREE_WORDS = {
		"free reward", "claim reward", "daily reward", "daily bonus", "free bonus",
		"free boost", "free cash", "free money", "free coins", "gift", "reward chest",
		"claim gift", "collect reward", "group reward", "free multiplier",
	}
	local BOOST_WORDS = {
		"2x cash", "2x money", "double cash", "double money", "cash boost", "money boost",
		"income boost", "production boost", "speed boost", "multiplier",
	}
	local CLAIM_WORDS = { "claim", "collect", "redeem", "activate", "use", "open" }
	local BLOCKED_WORDS = {
		"robux", "r$", "gamepass", "game pass", "premium", "developer product",
		"dev product", "watch ad", "watch video", "rewarded ad", "rewarded video",
		"advert", "purchase", "buy now", "shop", "store", "subscribe",
	}

	local DISCOVERY_INTERVAL = 30
	local SWEEP_INTERVAL = 5
	local PLAYER_GUI_BUDGET = 260
	local TYCOON_BUDGET = 320
	local MAX_CANDIDATES = 14

	local cooldowns = setmetatable({}, { __mode = "k" })
	local cachedCandidates = {}
	local cachedRoot
	local lastDiscovery = -math.huge
	local lastSweep = 0
	local lastActivated
	local activated = 0
	local skipped = 0

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

	local function objectText(object)
		if not object then return "" end
		local parts = { object.Name }
		if object:IsA("TextButton") or object:IsA("TextLabel") or object:IsA("TextBox") then
			table.insert(parts, object.Text)
		elseif object:IsA("ProximityPrompt") then
			table.insert(parts, object.ActionText)
			table.insert(parts, object.ObjectText)
		end
		return lower(table.concat(parts, " "))
	end

	local function localContextText(object)
		local parts = { objectText(object) }
		local parent = object and object.Parent
		if parent then
			table.insert(parts, objectText(parent))
			local inspected = 0
			for _, sibling in ipairs(parent:GetChildren()) do
				inspected = inspected + 1
				if inspected > 10 then break end
				table.insert(parts, objectText(sibling))
			end
		end
		if object then
			local inspected = 0
			for _, child in ipairs(object:GetChildren()) do
				inspected = inspected + 1
				if inspected > 8 then break end
				table.insert(parts, objectText(child))
			end
		end
		return lower(table.concat(parts, " "))
	end

	local function isSafeFreeCandidate(object)
		if not object or not object.Parent then return false end
		if object:IsA("TextButton") and object.Visible == false then return false end
		local text = localContextText(object)
		if hasAny(text, BLOCKED_WORDS) then return false end
		local explicitFree = hasAny(text, FREE_WORDS)
		local boostWithClaim = hasAny(text, BOOST_WORDS) and hasAny(text, CLAIM_WORDS)
		return explicitFree or boostWithClaim
	end

	local function getTouchActor()
		local character = LOCAL_PLAYER.Character
		if not character then return nil end
		for _, name in ipairs({ "LeftFoot", "RightFoot", "Left Leg", "Right Leg", "LowerTorso", "Torso" }) do
			local part = character:FindFirstChild(name)
			if part and part:IsA("BasePart") then return part end
		end
		return character:FindFirstChild("HumanoidRootPart")
	end

	local function activate(candidate)
		if not candidate or not candidate.Parent then return false end
		if candidate:IsA("TextButton") and type(firesignal) == "function" then
			if candidate.Visible == false then return false end
			return pcall(function() firesignal(candidate.MouseButton1Click) end)
		elseif candidate:IsA("ProximityPrompt") and type(fireproximityprompt) == "function" then
			return pcall(function() fireproximityprompt(candidate) end)
		elseif candidate:IsA("ClickDetector") and type(fireclickdetector) == "function" then
			return pcall(function() fireclickdetector(candidate) end)
		elseif candidate:IsA("TouchTransmitter") and type(firetouchinterest) == "function" then
			local actor = getTouchActor()
			local part = candidate.Parent
			if not actor or not part or not part:IsA("BasePart") then return false end
			return pcall(function()
				firetouchinterest(actor, part, 0)
				if task and task.wait then task.wait(0.015) else wait(0.015) end
				firetouchinterest(actor, part, 1)
			end)
		end
		return false
	end

	local function addCandidate(list, seen, object)
		if not object or seen[object] or not isSafeFreeCandidate(object) then return end
		local interactive = object:IsA("TextButton") or object:IsA("ProximityPrompt")
			or object:IsA("ClickDetector") or object:IsA("TouchTransmitter")
		if not interactive then return end
		seen[object] = true
		table.insert(list, object)
	end

	local function gatherFrom(container, list, seen, maxInspect)
		if not container then return end
		local inspected = 0
		for _, descendant in ipairs(container:GetDescendants()) do
			inspected = inspected + 1
			if inspected > maxInspect then break end
			addCandidate(list, seen, descendant)
			if #list >= MAX_CANDIDATES then break end
		end
	end

	local function discover(data)
		local root = data and data.ownerVerified and data.root ~= workspace and data.root or nil
		local now = os.clock()
		if root == cachedRoot and now - lastDiscovery < DISCOVERY_INTERVAL then return end
		cachedRoot = root
		lastDiscovery = now

		local found = {}
		local seen = {}
		gatherFrom(LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui"), found, seen, PLAYER_GUI_BUDGET)
		if root and #found < MAX_CANDIDATES then gatherFrom(root, found, seen, TYCOON_BUDGET) end
		cachedCandidates = found
	end

	local function sweep(data)
		local now = os.clock()
		if now - lastSweep < SWEEP_INTERVAL then return 0 end
		lastSweep = now
		discover(data)

		local count = 0
		for index = #cachedCandidates, 1, -1 do
			local candidate = cachedCandidates[index]
			if not candidate or not candidate.Parent then
				table.remove(cachedCandidates, index)
			else
				local cooldownUntil = cooldowns[candidate] or 0
				if now >= cooldownUntil and isSafeFreeCandidate(candidate) then
					cooldowns[candidate] = now + 30
					if activate(candidate) then
						count = count + 1
						activated = activated + 1
						lastActivated = localContextText(candidate)
					else
						skipped = skipped + 1
					end
				end
			end
			if count >= 2 then break end
		end
		return count
	end

	local function invalidate()
		cachedRoot = nil
		lastDiscovery = -math.huge
		cachedCandidates = {}
	end

	local function getStatus()
		return {
			activated = activated,
			skipped = skipped,
			lastActivated = lastActivated,
			candidateCount = #cachedCandidates,
			lastSweep = lastSweep,
		}
	end

	return {
		sweep = sweep,
		invalidate = invalidate,
		getStatus = getStatus,
	}
end