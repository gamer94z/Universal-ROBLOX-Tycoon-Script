return function(context)
	local LOCAL_PLAYER = context.LOCAL_PLAYER

	local REBIRTH_WORDS = { "rebirth", "prestige", "ascend", "restart tycoon", "reset tycoon" }
	local CLAIM_WORDS = { "claim tycoon", "claim plot", "claim base", "touch to claim", "claim" }
	local BLOCKED_WORDS = { "robux", "gamepass", "game pass", "premium", "developer product", "watch ad", "video ad", "rewarded ad" }

	local state = {
		startedAt = nil,
		completedAt = nil,
		completionRecorded = false,
		lastCharacterSeen = nil,
		lastRootSeen = nil,
		lastRebirthAttempt = 0,
		lastClaimAttempt = 0,
		rebirthAttempts = 0,
		rebirthSuccesses = 0,
		claimAttempts = 0,
		claimSuccesses = 0,
		recoveries = 0,
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

	local function getBuyInterval(data)
		if not data or not data.buttons then return 0.8 end
		local affordable = 0
		for _, button in ipairs(data.buttons) do
			if button.affordable and not button.paidPurchase and not (button.blockedUntil and button.blockedUntil > os.clock()) then
				affordable = affordable + 1
			end
		end
		if affordable >= 6 then return 0.12 end
		if affordable >= 3 then return 0.18 end
		if affordable >= 1 then return 0.28 end
		return 0.7
	end

	local function getCollectInterval(data)
		if not data or not data.drops then return 1 end
		if #data.drops >= 15 then return 0.18 end
		if #data.drops >= 5 then return 0.3 end
		return 0.5
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

	local function instanceLooksSafeFor(instance, wantedWords)
		if not instance then return false end
		local text = objectText(instance)
		if not hasAny(text, wantedWords) then return false end
		if hasAny(text, BLOCKED_WORDS) then return false end
		local parent = instance.Parent
		if parent and hasAny(parent.Name, BLOCKED_WORDS) then return false end
		return true
	end

	local function fireCandidate(candidate, useRootTouch)
		if not candidate or not candidate.interaction then return false end
		local interaction = candidate.interaction
		if interaction:IsA("ProximityPrompt") and type(fireproximityprompt) == "function" then
			return pcall(function() fireproximityprompt(interaction) end)
		elseif interaction:IsA("ClickDetector") and type(fireclickdetector) == "function" then
			return pcall(function() fireclickdetector(interaction) end)
		elseif interaction:IsA("TouchTransmitter") and type(firetouchinterest) == "function" and useRootTouch then
			local root = context.getLocalRoot()
			local part = interaction.Parent
			if root and part and part:IsA("BasePart") then
				return pcall(function()
					firetouchinterest(root, part, 0)
					waitStep(0.03)
					firetouchinterest(root, part, 1)
				end)
			end
		elseif candidate.gui and type(firesignal) == "function" then
			return pcall(function() firesignal(interaction.MouseButton1Click) end)
		end
		return false
	end

	local function findClaimCandidate()
		local root = context.getLocalRoot()
		local best, bestDistance = nil, math.huge
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if descendant:IsA("ProximityPrompt") or descendant:IsA("ClickDetector") or descendant:IsA("TouchTransmitter") then
				local current = descendant.Parent
				local depth = 0
				while current and current ~= workspace and depth < 3 do
					if instanceLooksSafeFor(current, CLAIM_WORDS) then
						local part = descendant.Parent and descendant.Parent:IsA("BasePart") and descendant.Parent or current:FindFirstChildWhichIsA("BasePart", true)
						local distance = root and part and (part.Position - root.Position).Magnitude or math.huge
						if distance < bestDistance then
							best = { interaction = descendant, host = current, part = part }
							bestDistance = distance
						end
						break
					end
					current = current.Parent
					depth = depth + 1
				end
			end
		end
		if best and bestDistance <= 120 then return best end
		return nil
	end

	local function tryClaim()
		if os.clock() - state.lastClaimAttempt < 4 then return false end
		local candidate = findClaimCandidate()
		if not candidate then return false end
		state.lastClaimAttempt = os.clock()
		state.claimAttempts = state.claimAttempts + 1
		local ok = fireCandidate(candidate, true)
		if not ok then return false end
		waitStep(0.35)
		state.claimSuccesses = state.claimSuccesses + 1
		return true
	end

	local function findRebirthCandidate(data)
		local root = data and data.root
		if root and root ~= workspace and root.Parent then
			for _, descendant in ipairs(root:GetDescendants()) do
				if descendant:IsA("ProximityPrompt") or descendant:IsA("ClickDetector") or descendant:IsA("TouchTransmitter") then
					local current = descendant.Parent
					local depth = 0
					while current and current ~= root and depth < 3 do
						if instanceLooksSafeFor(current, REBIRTH_WORDS) then
							return { interaction = descendant, host = current }
						end
						current = current.Parent
						depth = depth + 1
					end
				end
			end
		end

		local playerGui = LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			for _, descendant in ipairs(playerGui:GetDescendants()) do
				if descendant:IsA("TextButton") and descendant.Visible and instanceLooksSafeFor(descendant, REBIRTH_WORDS) then
					return { interaction = descendant, host = descendant, gui = true }
				end
			end
		end
		return nil
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
		if not fireCandidate(candidate, true) then return false end
		waitStep(0.8)

		local rootGone = beforeRoot and not beforeRoot.Parent
		local characterChanged = beforeCharacter and LOCAL_PLAYER.Character ~= beforeCharacter
		local cashReset = beforeCash and tonumber(context.getCash()) and tonumber(context.getCash()) < beforeCash * 0.25
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
			claimAttempts = state.claimAttempts,
			claimSuccesses = state.claimSuccesses,
			rebirthAttempts = state.rebirthAttempts,
			rebirthSuccesses = state.rebirthSuccesses,
			recoveries = state.recoveries,
		}
	end

	return {
		noteEnabled = noteEnabled,
		updateRecovery = updateRecovery,
		getBuyInterval = getBuyInterval,
		getCollectInterval = getCollectInterval,
		updateCompletion = updateCompletion,
		recordCompletion = recordCompletion,
		findClaimCandidate = findClaimCandidate,
		tryClaim = tryClaim,
		findRebirthCandidate = findRebirthCandidate,
		tryRebirth = tryRebirth,
		resetRunClock = resetRunClock,
		getStatus = getStatus,
	}
end
