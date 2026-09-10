return function(context)
	local LOCAL_PLAYER = context.LOCAL_PLAYER
	local CONFIG = context.CONFIG

	local REBIRTH_WORDS = { "rebirth", "prestige", "ascend", "restart tycoon", "reset tycoon" }
	local BLOCKED_WORDS = { "robux", "gamepass", "game pass", "premium", "developer product", "watch ad", "video ad", "rewarded ad" }
	local STREAM_REQUEST_INTERVAL = 4
	local STREAM_DISTANCE = 85
	local STREAM_TIMEOUT = 1.5

	local state = {
		startedAt = nil,
		completedAt = nil,
		completionRecorded = false,
		lastCharacterSeen = nil,
		lastRootSeen = nil,
		lastRebirthAttempt = 0,
		rebirthAttempts = 0,
		rebirthSuccesses = 0,
		recoveries = 0,
		tycoonPosition = nil,
		lastStreamRequest = -math.huge,
		streamBusy = false,
		streamRequests = 0,
		streamSuccesses = 0,
		streamFailures = 0,
	}

	local function lower(value)
		return tostring(value or ""):lower()
	end

	local function waitStep(seconds)
		if task and task.wait then task.wait(seconds or 0) else wait(seconds or 0) end
	end

	local function hasAny(text, words)
		text = lower(text)
		for _, word in ipairs(words) do
			if text:find(word, 1, true) then return true end
		end
		return false
	end

	local function getRootPosition(root)
		if not root or not root.Parent then return nil end
		if root:IsA("BasePart") then return root.Position end
		if root:IsA("Model") then
			local ok, pivot = pcall(function() return root:GetPivot() end)
			if ok and pivot then return pivot.Position end
		end
		local part = root:FindFirstChildWhichIsA("BasePart", true)
		return part and part.Position or nil
	end

	local function rememberTycoonPosition(data)
		local position = data and getRootPosition(data.root)
		if position then state.tycoonPosition = position end
		return state.tycoonPosition
	end

	local function keepTycoonStreamed(data)
		local position = rememberTycoonPosition(data)
		if not CONFIG.enabled or not position or state.streamBusy then return end
		if workspace.StreamingEnabled ~= true then return end
		if type(LOCAL_PLAYER.RequestStreamAroundAsync) ~= "function" then return end

		local localRoot = context.getLocalRoot()
		if not localRoot or (localRoot.Position - position).Magnitude < STREAM_DISTANCE then return end

		local now = os.clock()
		if now - state.lastStreamRequest < STREAM_REQUEST_INTERVAL then return end
		state.lastStreamRequest = now
		state.streamBusy = true
		state.streamRequests = state.streamRequests + 1

		task.spawn(function()
			local ok = pcall(function()
				LOCAL_PLAYER:RequestStreamAroundAsync(position, STREAM_TIMEOUT)
			end)
			if ok then state.streamSuccesses = state.streamSuccesses + 1
			else state.streamFailures = state.streamFailures + 1 end
			state.streamBusy = false
		end)
	end

	local function affordableCount(data)
		local count = 0
		for _, button in ipairs(data and data.buttons or {}) do
			if button.affordable and not button.paidPurchase
				and not (button.blockedUntil and button.blockedUntil > os.clock()) then
				count = count + 1
			end
		end
		return count
	end

	local function getBuyInterval(data, brainStatus)
		local affordable = affordableCount(data)
		if affordable == 0 then return 0.65 end

		local strategy = (brainStatus and brainStatus.strategy) or CONFIG.strategy or "Fastest"
		local bottleneck = brainStatus and brainStatus.bottleneck
		if bottleneck == "interaction failures" then return 0.55 end

		if strategy == "Rebirth" then
			if affordable >= 5 then return 0.09 end
			if affordable >= 2 then return 0.13 end
			return 0.2
		elseif strategy == "Income" then
			if affordable >= 5 then return 0.11 end
			if affordable >= 2 then return 0.16 end
			return 0.24
		end

		if affordable >= 6 then return 0.09 end
		if affordable >= 3 then return 0.14 end
		return 0.22
	end

	local function getCollectInterval(data, brainStatus)
		keepTycoonStreamed(data)
		local drops = #(data and data.drops or {})
		if drops == 0 then return 1 end
		local bottleneck = brainStatus and brainStatus.bottleneck
		if bottleneck == "waiting for collector" or bottleneck == "waiting for cash" then
			return drops >= 6 and 0.12 or 0.18
		end
		if drops >= 15 then return 0.2 end
		if drops >= 5 then return 0.3 end
		return 0.48
	end

	local function resetRunClock()
		state.startedAt = os.clock()
		state.completedAt = nil
		state.completionRecorded = false
	end

	local function noteEnabled(enabled)
		if enabled and not state.startedAt then
			resetRunClock()
		elseif not enabled then
			state.startedAt = nil
			state.completedAt = nil
			state.completionRecorded = false
		end
	end

	local function updateRecovery(data)
		local character = LOCAL_PLAYER.Character
		local root = context.getLocalRoot()
		rememberTycoonPosition(data)
		if character and state.lastCharacterSeen and character ~= state.lastCharacterSeen then
			state.recoveries = state.recoveries + 1
		end
		if root and not state.lastRootSeen and state.lastCharacterSeen then
			state.recoveries = state.recoveries + 1
		end
		state.lastCharacterSeen = character
		state.lastRootSeen = root
		return root ~= nil and data ~= nil
	end

	local function objectText(instance)
		local parts = { instance and instance.Name or "" }
		if instance and instance:IsA("ProximityPrompt") then
			table.insert(parts, instance.ActionText)
			table.insert(parts, instance.ObjectText)
		elseif instance and (instance:IsA("TextButton") or instance:IsA("TextLabel")) then
			table.insert(parts, instance.Text)
		end
		return lower(table.concat(parts, " "))
	end

	local function rebirthLooksSafe(instance)
		if not instance then return false end
		local text = objectText(instance)
		if not hasAny(text, REBIRTH_WORDS) or hasAny(text, BLOCKED_WORDS) then return false end
		local parent = instance.Parent
		return not (parent and hasAny(parent.Name, BLOCKED_WORDS))
	end

	local function findRebirthCandidate(data)
		local root = data and data.root
		if root and root ~= workspace and root.Parent then
			for _, descendant in ipairs(root:GetDescendants()) do
				if descendant:IsA("ProximityPrompt") or descendant:IsA("ClickDetector") or descendant:IsA("TouchTransmitter") then
					local current = descendant.Parent
					local depth = 0
					while current and current ~= root and depth < 3 do
						if rebirthLooksSafe(current) then return { interaction = descendant, host = current } end
						current = current.Parent
						depth = depth + 1
					end
				end
			end
		end

		local playerGui = LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			for _, descendant in ipairs(playerGui:GetDescendants()) do
				if descendant:IsA("TextButton") and descendant.Visible and rebirthLooksSafe(descendant) then
					return { interaction = descendant, host = descendant, gui = true }
				end
			end
		end
		return nil
	end

	local function fireRebirthCandidate(candidate)
		if not candidate or not candidate.interaction then return false end
		local interaction = candidate.interaction
		if interaction:IsA("ProximityPrompt") and type(fireproximityprompt) == "function" then
			return pcall(function() fireproximityprompt(interaction) end)
		elseif interaction:IsA("ClickDetector") and type(fireclickdetector) == "function" then
			return pcall(function() fireclickdetector(interaction) end)
		elseif interaction:IsA("TouchTransmitter") and type(firetouchinterest) == "function" then
			local character = LOCAL_PLAYER.Character
			local actor = character and (character:FindFirstChild("LeftFoot") or character:FindFirstChild("Left Leg") or character:FindFirstChild("HumanoidRootPart"))
			local part = interaction.Parent
			if actor and part and part:IsA("BasePart") then
				local oldCollide = part.CanCollide
				local ok = pcall(function()
					part.CanCollide = false
					firetouchinterest(actor, part, 0)
					waitStep(0.03)
					firetouchinterest(actor, part, 1)
					part.CanCollide = oldCollide
				end)
				pcall(function() if part and part.Parent then part.CanCollide = oldCollide end end)
				return ok
			end
		elseif candidate.gui and type(firesignal) == "function" then
			return pcall(function() firesignal(interaction.MouseButton1Click) end)
		end
		return false
	end

	local function tryRebirth(data)
		if os.clock() - state.lastRebirthAttempt < 5 then return false end
		local candidate = findRebirthCandidate(data)
		if not candidate then return false end
		state.lastRebirthAttempt = os.clock()
		state.rebirthAttempts = state.rebirthAttempts + 1

		local beforeRoot = data and data.root
		local beforeCash = tonumber(context.getCash())
		local beforeCharacter = LOCAL_PLAYER.Character
		if not fireRebirthCandidate(candidate) then return false end
		waitStep(0.8)

		local rootGone = beforeRoot and not beforeRoot.Parent
		local characterChanged = beforeCharacter and LOCAL_PLAYER.Character ~= beforeCharacter
		local afterCash = tonumber(context.getCash())
		local cashReset = beforeCash and afterCash and afterCash < beforeCash * 0.25
		if rootGone or characterChanged or cashReset then
			state.rebirthSuccesses = state.rebirthSuccesses + 1
			resetRunClock()
			return true
		end
		return false
	end

	local function updateCompletion(brain, data)
		if not brain or not brain.isLikelyComplete then return false end
		local complete = brain.isLikelyComplete(data)
		if complete and not state.completedAt then state.completedAt = os.clock() end
		if not complete then
			state.completedAt = nil
			state.completionRecorded = false
		end
		return complete
	end

	local function recordCompletion(brain)
		if state.completionRecorded or not state.completedAt or not state.startedAt then return end
		state.completionRecorded = true
		if brain and brain.markRunComplete then brain.markRunComplete(state.completedAt - state.startedAt) end
	end

	local function getStatus()
		return {
			startedAt = state.startedAt,
			completedAt = state.completedAt,
			rebirthAttempts = state.rebirthAttempts,
			rebirthSuccesses = state.rebirthSuccesses,
			recoveries = state.recoveries,
			streamRequests = state.streamRequests,
			streamSuccesses = state.streamSuccesses,
			streamFailures = state.streamFailures,
			streamBusy = state.streamBusy,
		}
	end

	return {
		noteEnabled = noteEnabled,
		updateRecovery = updateRecovery,
		keepTycoonStreamed = keepTycoonStreamed,
		getBuyInterval = getBuyInterval,
		getCollectInterval = getCollectInterval,
		updateCompletion = updateCompletion,
		recordCompletion = recordCompletion,
		findRebirthCandidate = findRebirthCandidate,
		tryRebirth = tryRebirth,
		resetRunClock = resetRunClock,
		getStatus = getStatus,
	}
end