return function(context)
	local CONFIG = context.CONFIG
	local CoreGui = context.CoreGui
	local UserInputService = game:GetService("UserInputService")
	local autonomousMode = CONFIG.autopilotEnabled ~= nil

	local callbacks = {}
	local cycleCallbacks = {}
	local actionCallbacks = {}
	local connections = {}
	local destroyed = false

	local CYCLES = {
		buyMode = { "Nearest", "Cheapest", "Value" },
		collectMode = { "Nearby", "Tycoon", "Collectors" },
		touchMode = { "Virtual", "Teleport" },
		strategy = { "Fastest", "Income", "Rebirth" },
	}

	local THEME = {
		window = Color3.fromRGB(20, 22, 30),
		header = Color3.fromRGB(26, 29, 39),
		panel = Color3.fromRGB(29, 32, 43),
		panelAlt = Color3.fromRGB(23, 25, 34),
		border = Color3.fromRGB(78, 84, 102),
		text = Color3.fromRGB(244, 246, 252),
		muted = Color3.fromRGB(172, 180, 200),
		accent = Color3.fromRGB(88, 166, 255),
		accentSoft = Color3.fromRGB(39, 72, 116),
		danger = Color3.fromRGB(255, 116, 116),
		ok = Color3.fromRGB(117, 255, 160),
	}

	local function track(connection)
		if connection then table.insert(connections, connection) end
		return connection
	end

	local function create(className, props)
		local instance = Instance.new(className)
		for key, value in pairs(props) do
			if key ~= "Parent" then instance[key] = value end
		end
		instance.Parent = props.Parent
		return instance
	end

	local function corner(parent, radius)
		create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
	end

	local function stroke(parent, colour, transparency)
		create("UIStroke", {
			Color = colour,
			Transparency = transparency or 0,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = parent,
		})
	end

	local function label(parent, text, size, colour, font, alignment)
		return create("TextLabel", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = font or Enum.Font.GothamMedium,
			Text = text,
			TextColor3 = colour or THEME.text,
			TextSize = size or 10,
			TextXAlignment = alignment or Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = parent,
		})
	end

	local oldGui = CoreGui:FindFirstChild("TycoonCoreGUI")
	if oldGui then oldGui:Destroy() end

	local camera = workspace.CurrentCamera
	local viewportHeight = camera and camera.ViewportSize.Y or 1080
	local wantedHeight = autonomousMode and 610 or 356
	local panelHeight = math.min(wantedHeight, math.max(360, viewportHeight - 40))

	local gui = create("ScreenGui", {
		Name = "TycoonCoreGUI",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = CoreGui,
	})

	local panel = create("Frame", {
		BackgroundColor3 = THEME.window,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.new(0, CONFIG.uiOffsetX or 24, 0, CONFIG.uiOffsetY or 180),
		Size = UDim2.new(0, 300, 0, panelHeight),
		Parent = gui,
	})
	corner(panel, 8)
	stroke(panel, THEME.border, 0.25)

	local header = create("Frame", {
		BackgroundColor3 = THEME.header,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 52),
		Parent = panel,
	})
	create("Frame", {
		BackgroundColor3 = THEME.accent,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 3),
		Parent = header,
	})

	local title = label(header, "0xVyrs Tycoon", 14, THEME.text, Enum.Font.GothamBlack)
	title.Position = UDim2.new(0, 12, 0, 9)
	title.Size = UDim2.new(1, -112, 0, 18)

	local subtitle = label(
		header,
		"v" .. tostring(CONFIG.version) .. (autonomousMode and "  //  speedrun brain" or "  //  automation"),
		8,
		THEME.accent,
		Enum.Font.GothamBold
	)
	subtitle.Position = UDim2.new(0, 13, 0, 29)
	subtitle.Size = UDim2.new(1, -112, 0, 12)

	local stateBadge = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(46, 50, 64),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -12, 0, 14),
		Size = UDim2.new(0, 82, 0, 20),
		Text = "STOPPED",
		TextColor3 = THEME.muted,
		TextSize = 8,
		Parent = header,
	})
	corner(stateBadge, 999)

	local body = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 10, 0, 61),
		Size = UDim2.new(1, -20, 1, -71),
		CanvasSize = UDim2.new(),
		ScrollBarThickness = autonomousMode and 3 or 0,
		ScrollBarImageColor3 = THEME.border,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = panel,
	})

	local layout = create("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})

	local toggles = {}
	local cycleButtons = {}
	local statusLabels = {}

	local function makeRow(labelText, height)
		local row = create("Frame", {
			BackgroundColor3 = THEME.panel,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -5, 0, height or 25),
			Parent = body,
		})
		corner(row, 7)
		stroke(row, THEME.border, 0.55)
		local rowLabel = label(row, labelText, 9, THEME.muted, Enum.Font.GothamBold)
		rowLabel.Position = UDim2.new(0, 10, 0, 0)
		rowLabel.Size = UDim2.new(1, -116, 1, 0)
		return row
	end

	local function setToggleVisual(button, value, danger)
		button.Text = value and "ON" or "OFF"
		button.TextColor3 = value and THEME.text or THEME.muted
		button.BackgroundColor3 = value
			and (danger and Color3.fromRGB(82, 46, 50) or THEME.accentSoft)
			or Color3.fromRGB(35, 40, 53)
	end

	local function toggleRow(key, labelText, danger)
		local row = makeRow(labelText)
		local button = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(35, 40, 53),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -9, 0.5, 0),
			Size = UDim2.new(0, 48, 0, 17),
			Text = "OFF",
			TextColor3 = THEME.muted,
			TextSize = 9,
			Parent = row,
		})
		corner(button, 999)
		stroke(button, danger and THEME.danger or THEME.border, 0.4)
		toggles[key] = { button = button, danger = danger }
		setToggleVisual(button, CONFIG[key] == true, danger)
		track(button.MouseButton1Click:Connect(function()
			CONFIG[key] = not CONFIG[key]
			setToggleVisual(button, CONFIG[key], danger)
			if callbacks[key] then callbacks[key](CONFIG[key])
			elseif context.saveSettings then context.saveSettings() end
		end))
	end

	local function cycleRow(key, labelText)
		local row = makeRow(labelText)
		local button = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(35, 40, 53),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -9, 0.5, 0),
			Size = UDim2.new(0, 96, 0, 17),
			Text = tostring(CONFIG[key]),
			TextColor3 = THEME.text,
			TextSize = 8,
			Parent = row,
		})
		corner(button, 999)
		stroke(button, THEME.border, 0.4)
		cycleButtons[key] = button
		track(button.MouseButton1Click:Connect(function()
			local values = CYCLES[key] or {}
			if #values == 0 then return end
			local nextIndex = 1
			for index, value in ipairs(values) do
				if value == CONFIG[key] then nextIndex = (index % #values) + 1 break end
			end
			CONFIG[key] = values[nextIndex]
			button.Text = tostring(CONFIG[key])
			if cycleCallbacks[key] then cycleCallbacks[key](CONFIG[key])
			elseif context.saveSettings then context.saveSettings() end
		end))
	end

	local function section(text)
		local sectionLabel = label(body, text, 8, THEME.accent, Enum.Font.GothamBold)
		sectionLabel.Size = UDim2.new(1, -5, 0, 18)
		sectionLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	end

	local function actionButton(parent, key, text, danger)
		local button = create("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = danger and Color3.fromRGB(72, 39, 45) or THEME.accentSoft,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Size = UDim2.new(0.5, -3, 1, 0),
			Text = text,
			TextColor3 = danger and THEME.danger or THEME.text,
			TextSize = 8,
			Parent = parent,
		})
		corner(button, 7)
		stroke(button, danger and THEME.danger or THEME.border, 0.35)
		track(button.MouseButton1Click:Connect(function()
			if actionCallbacks[key] then actionCallbacks[key]() end
		end))
		return button
	end

	local function actionPair(leftKey, leftText, rightKey, rightText)
		local row = create("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -5, 0, 27),
			Parent = body,
		})
		local left = actionButton(row, leftKey, leftText, false)
		left.Position = UDim2.new(0, 0, 0, 0)
		local right = actionButton(row, rightKey, rightText, true)
		right.AnchorPoint = Vector2.new(1, 0)
		right.Position = UDim2.new(1, 0, 0, 0)
	end

	local function actionWide(key, text, danger)
		local row = create("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -5, 0, 27),
			Parent = body,
		})
		local button = actionButton(row, key, text, danger)
		button.Size = UDim2.new(1, 0, 1, 0)
	end

	local function statusLine(parent, key, caption, y)
		local left = label(parent, caption, 8, THEME.muted, Enum.Font.GothamBold)
		left.Position = UDim2.new(0, 10, 0, y)
		left.Size = UDim2.new(0, 86, 0, 14)
		local right = label(parent, "--", 9, THEME.text, Enum.Font.GothamMedium, Enum.TextXAlignment.Right)
		right.Position = UDim2.new(0, 98, 0, y)
		right.Size = UDim2.new(1, -108, 0, 14)
		statusLabels[key] = right
	end

	toggleRow("enabled", "ENABLED")
	toggleRow("autoBuy", "AUTO BUY")
	toggleRow("autoCollect", "AUTO COLLECT")
	cycleRow("touchMode", "TOUCH MODE")
	cycleRow("buyMode", "BUY MODE")
	cycleRow("collectMode", "COLLECT MODE")
	toggleRow("highlightAffordable", "HIGHLIGHT")
	toggleRow("showWaypoint", "WAYPOINT")
	toggleRow("showLabels", "LABELS")
	toggleRow("requireOwnerMatch", "OWNER SAFE")

	if autonomousMode then
		section("SPEEDRUN BRAIN")
		cycleRow("strategy", "STRATEGY")
		toggleRow("autopilotEnabled", "AUTOPILOT")
		toggleRow("learningEnabled", "LEARNING")
		toggleRow("burstMode", "BURST MODE")
		toggleRow("autoRewards", "FREE REWARDS")
		toggleRow("autoRebirth", "AUTO REBIRTH", true)

		section("ACTIONS")
		actionPair("start", "START", "stop", "STOP")
		actionWide("resetLearning", "RESET LEARNING", true)

		section("LIVE STATUS")
		local card = create("Frame", {
			BackgroundColor3 = THEME.panelAlt,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -5, 0, 178),
			Parent = body,
		})
		corner(card, 7)
		stroke(card, THEME.border, 0.48)
		statusLine(card, "plan", "PLAN", 7)
		statusLine(card, "strategy", "STRATEGY", 24)
		statusLine(card, "bottleneck", "BOTTLENECK", 41)
		statusLine(card, "eta", "ETA", 58)
		statusLine(card, "best", "PERSONAL BEST", 75)
		statusLine(card, "cash", "CASH / MIN", 92)
		statusLine(card, "activity", "ACTIVITY", 109)
		statusLine(card, "rewards", "REWARDS", 126)
		statusLine(card, "learning", "LEARNING", 143)
		statusLine(card, "scan", "SCAN", 160)
	end

	local function updateCanvas()
		body.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 6)
	end
	track(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas))
	updateCanvas()

	local dragging = false
	local dragStart
	local panelStart
	local dragHandle = create("TextButton", {
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -96, 0, 52),
		Text = "",
		ZIndex = 5,
		Parent = panel,
	})

	local function clampPanel(x, y)
		local currentCamera = workspace.CurrentCamera
		local viewport = currentCamera and currentCamera.ViewportSize or Vector2.new(1920, 1080)
		return math.clamp(x, 0, math.max(0, viewport.X - panel.AbsoluteSize.X)),
			math.clamp(y, 0, math.max(0, viewport.Y - panel.AbsoluteSize.Y))
	end

	track(dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		dragging = true
		dragStart = input.Position
		panelStart = panel.AbsolutePosition
		track(input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				CONFIG.uiOffsetX = panel.Position.X.Offset
				CONFIG.uiOffsetY = panel.Position.Y.Offset
				if context.saveSettings then context.saveSettings() end
			end
		end))
	end))

	track(UserInputService.InputChanged:Connect(function(input)
		if not dragging or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) then return end
		local delta = input.Position - dragStart
		local x, y = clampPanel(panelStart.X + delta.X, panelStart.Y + delta.Y)
		panel.Position = UDim2.new(0, x, 0, y)
	end))

	local function shortText(value, maxLength)
		local text = tostring(value or "--")
		if #text <= maxLength then return text end
		return text:sub(1, math.max(1, maxLength - 1)) .. "…"
	end

	local function formatNumber(value)
		local n = tonumber(value)
		if not n then return "--" end
		local absolute = math.abs(n)
		if absolute >= 1e12 then return string.format("%.2fT", n / 1e12) end
		if absolute >= 1e9 then return string.format("%.2fB", n / 1e9) end
		if absolute >= 1e6 then return string.format("%.2fM", n / 1e6) end
		if absolute >= 1e3 then return string.format("%.1fK", n / 1e3) end
		return tostring(math.floor(n + 0.5))
	end

	local function formatDuration(seconds)
		seconds = tonumber(seconds)
		if not seconds or seconds < 0 then return "--" end
		if seconds < 60 then return string.format("%ds", math.floor(seconds + 0.5)) end
		local minutes = math.floor(seconds / 60)
		local remaining = math.floor(seconds % 60)
		if minutes < 60 then return string.format("%dm %02ds", minutes, remaining) end
		return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
	end

	local function syncControls()
		for key, entry in pairs(toggles) do
			setToggleVisual(entry.button, CONFIG[key] == true, entry.danger)
		end
		for key, button in pairs(cycleButtons) do
			button.Text = tostring(CONFIG[key])
		end
	end

	local function update(payload)
		if destroyed then return end
		payload = payload or {}
		local data = payload.data or {}
		syncControls()

		if not CONFIG.enabled then
			stateBadge.Text = "STOPPED"
			stateBadge.BackgroundColor3 = Color3.fromRGB(46, 50, 64)
			stateBadge.TextColor3 = THEME.muted
		elseif data.ownerVerified then
			stateBadge.Text = autonomousMode and "AUTO" or "READY"
			stateBadge.BackgroundColor3 = THEME.accentSoft
			stateBadge.TextColor3 = THEME.text
		elseif CONFIG.requireOwnerMatch then
			stateBadge.Text = "BLOCKED"
			stateBadge.BackgroundColor3 = Color3.fromRGB(80, 40, 48)
			stateBadge.TextColor3 = THEME.danger
		else
			stateBadge.Text = "RELAXED"
			stateBadge.BackgroundColor3 = Color3.fromRGB(70, 64, 38)
			stateBadge.TextColor3 = THEME.text
		end

		if autonomousMode then
			local auto = payload.autonomous or {}
			local brain = auto.brain or {}
			local plan = brain.plan or {}
			local boost = auto.boosts or {}
			local stats = payload.stats or {}
			statusLabels.plan.Text = shortText(plan.name or "waiting", 28)
			statusLabels.strategy.Text = tostring(brain.strategy or auto.strategy or CONFIG.strategy or "Fastest")
			statusLabels.bottleneck.Text = shortText(brain.bottleneck or "--", 28)
			statusLabels.eta.Text = formatDuration(brain.etaSeconds)
			statusLabels.best.Text = formatDuration(brain.bestCompletionSeconds)
			statusLabels.cash.Text = formatNumber(data.cash or auto.cash) .. " / " .. formatNumber(stats.cashPerMinute)
			statusLabels.activity.Text = string.format("%d bought / %d collected", tonumber(auto.bought) or 0, tonumber(auto.collected) or 0)
			statusLabels.rewards.Text = string.format("%d activated", tonumber(auto.rewardsActivated) or tonumber(boost.activated) or 0)
			statusLabels.learning.Text = string.format("%d nodes / %d links", tonumber(brain.learnedNodes) or 0, tonumber(brain.learnedEdges) or 0)
			statusLabels.scan.Text = string.format("%s %.1fms", tostring(data.scanMode or "--"), tonumber(data.scanTimeMs) or 0)
		end
	end

	return {
		update = update,
		onToggle = function(key, callback) callbacks[key] = callback end,
		onCycle = function(key, callback) cycleCallbacks[key] = callback end,
		onAction = function(key, callback) actionCallbacks[key] = callback end,
		destroy = function()
			if destroyed then return end
			destroyed = true
			for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
			table.clear(connections)
			if gui then gui:Destroy() end
		end,
	}
end
