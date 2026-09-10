-- Performance-hardening collector wrapper.
-- Keeps the hardened purchase path, but makes collection low-rate and prevents
-- collector pads from physically supporting or launching the local character.

local BASE_URL = "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/07768b7b71e3999b9fdd065004b278803b3dff5e/tycoon_modules/collector.lua"

return function(context)
	local source = game:HttpGet(BASE_URL)
	local chunk = loadstring(source)
	if type(chunk) ~= "function" then return nil end
	local factory = chunk()
	if type(factory) ~= "function" then return nil end
	local base = factory(context)
	if type(base) ~= "table" or type(base.buyButton) ~= "function" then return nil end

	local cooldowns = setmetatable({}, { __mode = "k" })
	local collisionStates = setmetatable({}, { __mode = "k" })
	local cursor = 1
	local COLLECT_COOLDOWN = 0.7
	local FAILED_COOLDOWN = 1.1
	local CONFIRM_DELAY = 0.22
	local COLLISION_RESTORE_DELAY = 1.6

	local diagnostics = {
		attempts = 0,
		activations = 0,
		cashConfirmed = 0,
		failed = 0,
		launchGuards = 0,
		staleRefreshes = 0,
		noclipApplied = 0,
	}

	local function waitStep(seconds)
		if task and task.wait then task.wait(seconds or 0) else wait(seconds or 0) end
	end

	local function firePrompt(prompt)
		if not prompt or not prompt.Parent or type(fireproximityprompt) ~= "function" then return false end
		return pcall(function() fireproximityprompt(prompt) end)
	end

	local function fireClick(clickDetector)
		if not clickDetector or not clickDetector.Parent or type(fireclickdetector) ~= "function" then return false end
		return pcall(function() fireclickdetector(clickDetector) end)
	end

	local function entryAlive(entry)
		return (entry.prompt and entry.prompt.Parent)
			or (entry.clickDetector and entry.clickDetector.Parent)
			or (entry.touchPart and entry.touchPart.Parent)
	end

	local function refreshEntry(entry)
		if not entry or not entry.object or not entry.object.Parent then return false end
		if entryAlive(entry) then return true end
		entry.prompt, entry.clickDetector, entry.touchPart = nil, nil, nil

		local queue = { entry.object }
		local q, inspected = 1, 0
		while q <= #queue and inspected < 24 do
			local current = queue[q]
			q = q + 1
			if current:IsA("ProximityPrompt") then entry.prompt = current
			elseif current:IsA("ClickDetector") then entry.clickDetector = current
			elseif current:IsA("TouchTransmitter") and current.Parent and current.Parent:IsA("BasePart") then entry.touchPart = current.Parent end
			if entryAlive(entry) then
				diagnostics.staleRefreshes = diagnostics.staleRefreshes + 1
				return true
			end
			for _, child in ipairs(current:GetChildren()) do
				inspected = inspected + 1
				if inspected <= 24 then table.insert(queue, child) end
				if inspected >= 24 then break end
			end
		end
		return false
	end

	local function keepCollectorNonColliding(target)
		if not target or not target.Parent or not target:IsA("BasePart") then return end
		local state = collisionStates[target]
		if not state then
			state = { original = target.CanCollide, generation = 0 }
			collisionStates[target] = state
		end
		state.generation = state.generation + 1
		local generation = state.generation
		if target.CanCollide then
			pcall(function() target.CanCollide = false end)
			diagnostics.noclipApplied = diagnostics.noclipApplied + 1
		end

		if task and task.delay then
			task.delay(COLLISION_RESTORE_DELAY, function()
				local current = collisionStates[target]
				if current and current.generation == generation and target and target.Parent then
					pcall(function() target.CanCollide = current.original end)
					collisionStates[target] = nil
				end
			end)
		end
	end

	local function guardLaunch(root, beforeCFrame, beforeLinear, beforeAngular)
		if not root or not root.Parent then return end
		local current = root.AssemblyLinearVelocity
		local verticalSpike = current.Y > math.max(42, beforeLinear.Y + 24)
		local magnitudeSpike = current.Magnitude > beforeLinear.Magnitude + 65
		if not verticalSpike and not magnitudeSpike then return end
		diagnostics.launchGuards = diagnostics.launchGuards + 1
		pcall(function()
			if root.Position.Y - beforeCFrame.Position.Y > 6 then root.CFrame = beforeCFrame end
			root.AssemblyLinearVelocity = beforeLinear
			root.AssemblyAngularVelocity = beforeAngular
		end)
	end

	local function safeRootTouch(root, target)
		if not root or not root.Parent or not target or not target.Parent or type(firetouchinterest) ~= "function" then return false end
		keepCollectorNonColliding(target)
		local beforeCFrame = root.CFrame
		local beforeLinear = root.AssemblyLinearVelocity
		local beforeAngular = root.AssemblyAngularVelocity
		local ok = pcall(function()
			firetouchinterest(root, target, 0)
			waitStep(0.02)
			firetouchinterest(root, target, 1)
		end)
		guardLaunch(root, beforeCFrame, beforeLinear, beforeAngular)
		if task and task.delay then
			task.delay(0.08, function() guardLaunch(root, beforeCFrame, beforeLinear, beforeAngular) end)
			task.delay(0.2, function() guardLaunch(root, beforeCFrame, beforeLinear, beforeAngular) end)
		end
		return ok
	end

	local function activateCollection(root, entry)
		if entry.prompt and entry.prompt.Parent then return firePrompt(entry.prompt) end
		if entry.clickDetector and entry.clickDetector.Parent then return fireClick(entry.clickDetector) end
		if entry.touchPart and entry.touchPart.Parent then return safeRootTouch(root, entry.touchPart) end
		return false
	end

	local function collectNearby(scanContext, data)
		if not data or not data.drops or data.automationAllowed ~= true or #data.drops == 0 then return 0 end
		local root = scanContext.getLocalRoot()
		if not root then return 0 end

		local total = #data.drops
		if cursor > total then cursor = 1 end
		local now = os.clock()
		local checked, index = 0, cursor

		while checked < total do
			local entry = data.drops[index]
			checked = checked + 1
			index = (index % total) + 1
			if entry and entry.object and entry.object.Parent and refreshEntry(entry) then
				local key = entry.touchPart or entry.prompt or entry.clickDetector or entry.object
				if now >= (cooldowns[key] or 0) then
					diagnostics.attempts = diagnostics.attempts + 1
					local beforeCash = tonumber(scanContext.getCash())
					local activated = activateCollection(root, entry)
					if activated then
						diagnostics.activations = diagnostics.activations + 1
						cooldowns[key] = now + COLLECT_COOLDOWN
						waitStep(CONFIRM_DELAY)
						local afterCash = tonumber(scanContext.getCash())
						if beforeCash ~= nil and afterCash ~= nil and afterCash > beforeCash then diagnostics.cashConfirmed = diagnostics.cashConfirmed + 1 end
						cursor = index
						return 1
					end
					diagnostics.failed = diagnostics.failed + 1
					cooldowns[key] = now + FAILED_COOLDOWN
					cursor = index
					return 0
				end
			end
		end

		cursor = index
		return 0
	end

	local function getStatus()
		local status = type(base.getStatus) == "function" and base.getStatus() or {}
		status.attempts = diagnostics.attempts
		status.activations = diagnostics.activations
		status.cashConfirmed = diagnostics.cashConfirmed
		status.failed = diagnostics.failed
		status.actorRetries = 0
		status.rootFallbacks = 0
		status.staleRefreshes = diagnostics.staleRefreshes
		status.launchGuards = diagnostics.launchGuards
		status.noclipApplied = diagnostics.noclipApplied
		return status
	end

	return {
		collectNearby = collectNearby,
		buyButton = base.buyButton,
		getStatus = getStatus,
	}
end
