return function(context)
	local CONFIG = context.CONFIG
	local CoreGui = context.CoreGui
	local UserInputService = game:GetService("UserInputService")
	local TweenService = game:GetService("TweenService")

	local callbacks = {}
	local cycleCallbacks = {}
	local actionCallbacks = {}
	local connections = {}
	local autonomousMode = CONFIG.autopilotEnabled ~= nil

	local CYCLES = {
		buyMode = { "Nearest", "Cheapest", "Value" },
		collectMode = { "Nearby", "Tycoon", "Collectors" },
		touchMode = { "Virtual", "Teleport" },
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
		focus = Color3.fromRGB(255, 214, 102),
		danger = Color3.fromRGB(255, 116, 116),
		ok = Color3.fromRGB(117, 255, 160),
	}

	local function track(connection)
		table.insert(connections, connection)
		return connection
	end

	local function create(className, props)
		local instance = Instance.new(className)
		for key, value in pairs(props) do
			if key ~= "Parent" then
				instance[key] = value
			end
		end
		instance.Parent = props.Parent
		return instance
	end

	local function corner(parent, radius)
		create("UICorner", {
			CornerRadius = UDim.new(0, radius),
			Parent = parent,
		})
	end

	local function stroke(parent, color, transparency, thickness)
		create("UIStroke", {
			Color = color,
			Transparency = transparency or 0,
			Thickness = thickness or 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = parent,
		})
	end

	local function label(parent, text, size, color, font, align)
		return create("TextLabel", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = font or Enum.Font.GothamMedium,
			Text = text,
			TextColor3 = color or THEME.text,
			TextSize = size or 10,
			TextXAlignment = align or Enum.TextXAlignment.Left,
			Parent = parent,
		})
	end

	local function tween(instance, duration, props, style, direction)
		local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
		local created = TweenService:Create(instance, info, props)
		created:Play()
		return created
	end

	local function getShared()
		return (type(getgenv) == "function" and getgenv())
			or (type(getfenv) == "function" and getfenv(0))
			or _G
	end

	local function getBot()
		local shared = getShared()
		return shared and shared.__VYRS_TYCOON_AUTONOMOUS or nil
	end

	local function invokeBot(methodName, ...)
		local bot = getBot()
		local method = bot and bot[methodName]
		if type(method) ~= "function" then
			return false, "autonomous runtime not ready"
		end
		local ok, result = pcall(method, ...)
		if not ok then
			return false, result
		end
		return result ~= false, result
	end

	local gui = create("ScreenGui", {
		Name = "TycoonCoreGUI",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = CoreGui,
	})

	local panelHeight = autonomousMode and 420 or 356
	local panel = create("Frame", {
		BackgroundColor3 = THEME.window,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.new(0, CONFIG.uiOffsetX - 14, 0, CONFIG.uiOffsetY),
		Size = UDim2.new(0, 286, 0, panelHeight),
		Parent = gui,
	})
	corner(panel, 8)
	stroke(panel, THEME.border, 0.25, 1)

	local header = create("Frame", {
		BackgroundColor3 = THEME.header,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 50),
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

	local subtitleText = autonomousMode and ("v" .. CONFIG.version .. "  //  autonomous") or ("v" .. CONFIG.version .. "  //  safe automation")
	local subtitle = label(header, subtitleText, 8, THEME.accent, Enum.Font.GothamBold)
	subtitle.Position = UDim2.new(0, 13, 0, 28)
	subtitle.Size = UDim2.new(1, -112, 0, 12)

	local stateBadge = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(46, 50, 64),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -12, 0, 13),
		Size = UDim2.new(0, 82, 0, 20),
		Text = "STOPPED",
		TextColor3 = THEME.muted,
		TextSize = 8,
		Parent = header,
	})
	corner(stateBadge, 999)

	local toastLayer = create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.new(0, 260, 0, 180),
		ZIndex = 30,
		Parent = gui,
	})

	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toastLayer,
	})

	local function showToast(titleText, detailText, accentColor)
		local toast = create("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(20, 24, 34),
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 44),
			ZIndex = 31,
			Parent = toastLayer,
		})
		corner(toast, 9)
		stroke(toast, accentColor or THEME.accent, 0.2, 1)

		local toastTitle = label(toast, titleText, 10, THEME.text, Enum.Font.GothamBold)
		toastTitle.Position = UDim2.new(0, 11, 0, 7)
		toastTitle.Size = UDim2.new(1, -22, 0, 13)
		toastTitle.ZIndex = 32

		local toastDetail = label(toast, detailText, 9, THEME.muted, Enum.Font.GothamMedium)
		toastDetail.Position = UDim2.new(0, 11, 0, 22)
		toastDetail.Size = UDim2.new(1, -22, 0, 13)
		toastDetail.ZIndex = 32

		task.delay(1.65, function()
			if not toast or not toast.Parent then
				return
			end
			tween(toast, 0.16, { BackgroundTransparency = 1 })
			tween(toastTitle, 0.16, { TextTransparency = 1 })
			tween(toastDetail, 0.16, { TextTransparency = 1 })
			task.delay(0.18, function()
				if toast then
					toast:Destroy()
				end
			end)
		end)
	end

	local body = create("ScrollingFrame", {
		Active = true,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Position = UDim2.new(0, 10, 0, 60),
		ScrollBarImageColor3 = THEME.border,
		ScrollBarThickness = autonomousMode and 3 or 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.new(1, -20, 1, -70),
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
			Size = UDim2.new(1, autonomousMode and -5 or 0, 0, height or 24),
			Parent = body,
		})
		corner(row, 7)
		stroke(row, THEME.border, 0.52, 1)

		local rowLabel = label(row, labelText, 10, THEME.muted, Enum.Font.GothamBold)
		rowLabel.Position = UDim2.new(0, 10, 0, 0)
		rowLabel.Size = UDim2.new(1, -112, 1, 0)
		return row
	end

	local function section(text)
		local sectionLabel = label(body, text, 8, THEME.accent, Enum.Font.GothamBold)
		sectionLabel.Size = UDim2.new(1, -5, 0, 16)
		sectionLabel.TextXAlignment = Enum.TextXAlignment.Left
		return sectionLabel
	end

	local function setToggleVisual(button, value, danger)
		button.Text = value and "ON" or "OFF"
		button.TextColor3 = value and Color3.fromRGB(228, 241, 255) or THEME.muted
		if value and danger then
			button.BackgroundColor3 = Color3.fromRGB(92, 48, 54)
		else
			button.BackgroundColor3 = value and THEME.accentSoft or Color3.fromRGB(35, 40, 53)
		end
		local buttonStroke = button:FindFirstChildOfClass("UIStroke")
		if buttonStroke then
			buttonStroke.Color = value and danger and THEME.danger or THEME.accent
			buttonStroke.Transparency = value and 0.15 or 0.58
		end
	end

	local BOT_TOGGLE_METHODS = {
		autopilotEnabled = "setAutopilot",
		learningEnabled = "setLearning",
		burstMode = "setBurst",
		autoClaim = "setAutoClaim",
		autoRebirth = "setAutoRebirth",
		spectatorMode = "setSpectator",
	}

	local function toggleRow(key, labelText, danger)
		local row = makeRow(labelText)
		local button = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = THEME.accentSoft,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -9, 0.5, 0),
			Size = UDim2.new(0, 48, 0, 17),
			Text = "ON",
			TextColor3 = THEME.text,
			TextSize = 9,
			Parent = row,
		})
		corner(button, 999)
		stroke(button, THEME.accent, 0.15, 1)
		toggles[key] = { button = button, danger = danger == true }
		setToggleVisual(button, CONFIG[key] == true, danger == true)

		track(button.MouseButton1Click:Connect(function()
			local nextValue = not (CONFIG[key] == true)
			CONFIG[key] = nextValue
			setToggleVisual(button, nextValue, danger == true)

			if callbacks[key] then
				callbacks[key](nextValue)
			elseif BOT_TOGGLE_METHODS[key] then
				invokeBot(BOT_TOGGLE_METHODS[key], nextValue)
			elseif context.saveSettings then
				context.saveSettings()
			end

			showToast("Tycoon", string.format("%s %s", labelText, nextValue and "enabled" or "disabled"), nextValue and (danger and THEME.danger or THEME.accent) or THEME.muted)
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
			Size = UDim2.new(0, 92, 0, 17),
			Text = tostring(CONFIG[key]),
			TextColor3 = THEME.text,
			TextSize = 8,
			Parent = row,
		})
		corner(button, 999)
		stroke(button, THEME.border, 0.35, 1)
		cycleButtons[key] = button

		track(button.MouseButton1Click:Connect(function()
			local values = CYCLES[key] or {}
			if #values == 0 then
				return
			end
			local nextIndex = 1
			for index, value in ipairs(values) do
				if value == CONFIG[key] then
					nextIndex = (index % #values) + 1
					break
				end
			end
			CONFIG[key] = values[nextIndex] or CONFIG[key]
			button.Text = tostring(CONFIG[key])
			if cycleCallbacks[key] then
				cycleCallbacks[key](CONFIG[key])
			elseif context.saveSettings then
				context.saveSettings()
			end
			showToast("Tycoon", string.format("%s set to %s", labelText, tostring(CONFIG[key])), THEME.accent)
		end))
	end

	local function actionButton(parent, key, text, danger)
		local button = create("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = danger and Color3.fromRGB(72, 39, 45) or Color3.fromRGB(35, 40, 53),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Size = UDim2.new(0.5, -3, 1, 0),
			Text = text,
			TextColor3 = danger and THEME.danger or THEME.text,
			TextSize = 8,
			Parent = parent,
		})
		corner(button, 7)
		stroke(button, danger and THEME.danger or THEME.border, 0.35, 1)

		track(button.MouseButton1Click:Connect(function()
			local ok = false
			if actionCallbacks[key] then
				local callOk, result = pcall(actionCallbacks[key])
				ok = callOk and result ~= false
			else
				local methodMap = {
					start = "start",
					startFull = "startFull",
					stop = "stop",
					resetLearning = "resetLearning",
				}
				local method = methodMap[key]
				if method then
					ok = select(1, invokeBot(method))
				end
			end
			showToast("Autonomous", ok and (text .. " complete") or (text .. " unavailable"), ok and THEME.accent or THEME.danger)
		end))
		return button
	end

	local function actionPair(leftKey, leftText, rightKey, rightText, rightDanger)
		local row = create("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -5, 0, 25),
			Parent = body,
		})
		local left = actionButton(row, leftKey, leftText, false)
		left.Position = UDim2.new(0, 0, 0, 0)
		local right = actionButton(row, rightKey, rightText, rightDanger)
		right.AnchorPoint = Vector2.new(1, 0)
		right.Position = UDim2.new(1, 0, 0, 0)
	end

	local function statusLine(parent, key, caption, y)
		local captionLabel = label(parent, caption, 8, THEME.muted, Enum.Font.GothamBold)
		captionLabel.Position = UDim2.new(0, 10, 0, y)
		captionLabel.Size = UDim2.new(0, 76, 0, 14)

		local valueLabel = label(parent, "--", 9, THEME.text, Enum.Font.GothamMedium, Enum.TextXAlignment.Right)
		valueLabel.Position = UDim2.new(0, 88, 0, y)
		valueLabel.Size = UDim2.new(1, -98, 0, 14)
		statusLabels[key] = valueLabel
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
		section("AUTONOMOUS")
		toggleRow("autopilotEnabled", "AUTOPILOT")
		toggleRow("learningEnabled", "LEARNING")
		toggleRow("burstMode", "BURST MODE")
		toggleRow("autoClaim", "AUTO CLAIM")
		toggleRow("autoRebirth", "AUTO REBIRTH", true)
		toggleRow("spectatorMode", "SPECTATOR")

		section("ACTIONS")
		actionPair("start", "START", "startFull", "START FULL", false)
		actionPair("stop", "STOP", "resetLearning", "RESET LEARNING", true)

		section("LIVE STATUS")
		local statusCard = create("Frame", {
			BackgroundColor3 = THEME.panelAlt,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -5, 0, 144),
			Parent = body,
		})
		corner(statusCard, 7)
		stroke(statusCard, THEME.border, 0.48, 1)

		statusLine(statusCard, "plan", "PLAN", 7)
		statusLine(statusCard, "category", "CATEGORY", 24)
		statusLine(statusCard, "eta", "ETA", 41)
		statusLine(statusCard, "economy", "CASH", 58)
		statusLine(statusCard, "counts", "ACTIVITY", 75)
		statusLine(statusCard, "failures", "FAILURES", 92)
		statusLine(statusCard, "learning", "LEARNING", 109)
		statusLine(statusCard, "scan", "SCAN", 126)
	end

	local function updateCanvas()
		body.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 4)
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
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 50),
		Text = "",
		ZIndex = 4,
		Parent = panel,
	})

	local function clampPosition(x, y)
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
		local width = panel.AbsoluteSize.X > 0 and panel.AbsoluteSize.X or 286
		local height = panel.AbsoluteSize.Y > 0 and panel.AbsoluteSize.Y or panelHeight
		return math.clamp(x, 0, math.max(0, viewport.X - width)),
			math.clamp(y, 0, math.max(0, viewport.Y - height))
	end

	track(dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragging = true
		dragStart = input.Position
		panelStart = panel.AbsolutePosition
		track(input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				CONFIG.uiOffsetX = panel.Position.X.Offset
				CONFIG.uiOffsetY = panel.Position.Y.Offset
				if context.saveSettings then
					context.saveSettings()
				end
			end
		end))
	end))

	track(UserInputService.InputChanged:Connect(function(input)
		if not dragging or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) then
			return
		end
		local delta = input.Position - dragStart
		local x, y = clampPosition(panelStart.X + delta.X, panelStart.Y + delta.Y)
		panel.Position = UDim2.new(0, x, 0, y)
	end))

	local function shortText(value, maxLength)
		local text = tostring(value or "--")
		if #text <= maxLength then
			return text
		end
		return text:sub(1, math.max(1, maxLength - 1)) .. "…"
	end

	local function formatNumber(value)
		local number = tonumber(value)
		if not number then
			return "--"
		end
		local absolute = math.abs(number)
		if absolute >= 1e9 then
			return string.format("%.2fB", number / 1e9)
		elseif absolute >= 1e6 then
			return string.format("%.2fM", number / 1e6)
		elseif absolute >= 1e3 then
			return string.format("%.1fK", number / 1e3)
		end
		return tostring(math.floor(number + 0.5))
	end

	local function formatDuration(seconds)
		seconds = tonumber(seconds)
		if not seconds or seconds < 0 then
			return "--"
		end
		if seconds < 60 then
			return string.format("%ds", math.floor(seconds + 0.5))
		end
		local minutes = math.floor(seconds / 60)
		local remaining = math.floor(seconds % 60)
		if minutes < 60 then
			return string.format("%dm %02ds", minutes, remaining)
		end
		local hours = math.floor(minutes / 60)
		return string.format("%dh %02dm", hours, minutes % 60)
	end

	local cachedBotStatus = nil
	local lastBotStatusAt = -math.huge

	local function refreshBotStatus()
		if not autonomousMode or os.clock() - lastBotStatusAt < 0.7 then
			return cachedBotStatus
		end
		lastBotStatusAt = os.clock()
		local bot = getBot()
		if not bot or type(bot.status) ~= "function" then
			return cachedBotStatus
		end
		local ok, result = pcall(bot.status)
		if ok and type(result) == "table" then
			cachedBotStatus = result
		end
		return cachedBotStatus
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
			stateBadge.BackgroundColor3 = Color3.fromRGB(86, 71, 28)
			stateBadge.TextColor3 = THEME.focus
		end

		if autonomousMode and statusLabels.plan then
			local status = refreshBotStatus() or {}
			local brainStatus = status.brain or {}
			local plan = brainStatus.plan or {}
			local category = plan.category or "--"

			statusLabels.plan.Text = shortText(plan.name or (payload.nearest and payload.nearest.name) or "waiting", 24)
			statusLabels.category.Text = shortText(category, 18)
			statusLabels.eta.Text = formatDuration(brainStatus.etaSeconds)
			statusLabels.economy.Text = formatNumber(status.cash or data.cash)
			statusLabels.counts.Text = string.format("B %d  /  C %d", tonumber(status.bought or payload.bought) or 0, tonumber(status.collected or payload.collected) or 0)
			statusLabels.failures.Text = tostring(tonumber(status.purchaseFailures) or 0)
			statusLabels.learning.Text = string.format("%d nodes / %d links", tonumber(brainStatus.learnedNodes) or 0, tonumber(brainStatus.learnedEdges) or 0)
			statusLabels.scan.Text = string.format("%s / %.1fms", tostring(data.scanMode or "--"), tonumber(data.scanTimeMs) or 0)
		end
	end

	local loader = create("Frame", {
		BackgroundColor3 = THEME.window,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 20,
		Parent = panel,
	})
	corner(loader, 8)

	local loaderTitle = label(loader, "0xVyrs Tycoon", 15, THEME.text, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
	loaderTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	loaderTitle.Position = UDim2.new(0.5, 0, 0.5, -7)
	loaderTitle.Size = UDim2.new(1, -24, 0, 22)
	loaderTitle.ZIndex = 21

	local loaderSub = label(loader, autonomousMode and "loading autonomous engine" or "loading safe automation", 9, THEME.accent, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	loaderSub.AnchorPoint = Vector2.new(0.5, 0.5)
	loaderSub.Position = UDim2.new(0.5, 0, 0.5, 14)
	loaderSub.Size = UDim2.new(1, -24, 0, 14)
	loaderSub.ZIndex = 21

	tween(panel, 0.24, {
		BackgroundTransparency = 0,
		Position = UDim2.new(0, CONFIG.uiOffsetX, 0, CONFIG.uiOffsetY),
	})
	tween(header, 0.24, { BackgroundTransparency = 0 })

	task.delay(0.38, function()
		if not loader or not loader.Parent then
			return
		end
		tween(loader, 0.18, { BackgroundTransparency = 1 })
		tween(loaderTitle, 0.16, { TextTransparency = 1 })
		tween(loaderSub, 0.16, { TextTransparency = 1 })
		task.delay(0.2, function()
			if loader then
				loader:Destroy()
			end
			showToast(autonomousMode and "Autonomous" or "Tycoon Core", autonomousMode and "Controls ready" or "Loaded with automation disabled", THEME.accent)
		end)
	end)

	return {
		update = update,
		onToggle = function(key, callback)
			callbacks[key] = callback
		end,
		onCycle = function(key, callback)
			cycleCallbacks[key] = callback
		end,
		onAction = function(key, callback)
			actionCallbacks[key] = callback
		end,
		showToast = showToast,
		destroy = function()
			for _, connection in ipairs(connections) do
				pcall(function()
					connection:Disconnect()
				end)
			end
			table.clear(connections)
			if gui then
				gui:Destroy()
			end
		end,
	}
end
