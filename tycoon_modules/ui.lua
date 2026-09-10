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
	local collapsed = false
	local activePage = "COMMAND"
	local latestPayload = {}

	local CYCLES = {
		buyMode = { "Nearest", "Cheapest", "Value" },
		collectMode = { "Nearby", "Tycoon", "Collectors" },
		touchMode = { "Virtual", "Teleport" },
		strategy = { "Fastest", "Income", "Rebirth" },
	}

	local THEME = {
		window = Color3.fromRGB(11, 13, 17),
		surface = Color3.fromRGB(17, 21, 27),
		surface2 = Color3.fromRGB(23, 28, 36),
		surface3 = Color3.fromRGB(29, 35, 45),
		border = Color3.fromRGB(41, 49, 61),
		borderBright = Color3.fromRGB(62, 74, 91),
		text = Color3.fromRGB(241, 244, 248),
		muted = Color3.fromRGB(137, 148, 163),
		faint = Color3.fromRGB(85, 95, 109),
		accent = Color3.fromRGB(77, 163, 255),
		accentDim = Color3.fromRGB(24, 54, 83),
		success = Color3.fromRGB(102, 214, 158),
		warning = Color3.fromRGB(228, 183, 91),
		danger = Color3.fromRGB(224, 108, 117),
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
		create("UICorner", { CornerRadius = UDim.new(0, radius or 4), Parent = parent })
	end

	local function stroke(parent, colour, transparency)
		return create("UIStroke", {
			Color = colour or THEME.border,
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
			Text = text or "",
			TextColor3 = colour or THEME.text,
			TextSize = size or 10,
			TextXAlignment = alignment or Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = parent,
		})
	end

	local function formatNumber(value)
		local n = tonumber(value)
		if not n then return "--" end
		local a = math.abs(n)
		if a >= 1e15 then return string.format("%.2fQ", n / 1e15) end
		if a >= 1e12 then return string.format("%.2fT", n / 1e12) end
		if a >= 1e9 then return string.format("%.2fB", n / 1e9) end
		if a >= 1e6 then return string.format("%.2fM", n / 1e6) end
		if a >= 1e3 then return string.format("%.1fK", n / 1e3) end
		return tostring(math.floor(n + 0.5))
	end

	local function formatDuration(seconds)
		seconds = tonumber(seconds)
		if not seconds or seconds < 0 or seconds == math.huge then return "--" end
		if seconds < 60 then return string.format("%.1fs", seconds) end
		local minutes = math.floor(seconds / 60)
		local remaining = math.floor(seconds % 60)
		if minutes < 60 then return string.format("%dm %02ds", minutes, remaining) end
		return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
	end

	local function shortText(value, maxLength)
		local text = tostring(value or "--")
		if #text <= maxLength then return text end
		return text:sub(1, math.max(1, maxLength - 3)) .. "..."
	end

	local oldGui = CoreGui:FindFirstChild("TycoonCoreGUI")
	if oldGui then oldGui:Destroy() end

	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	local panelWidth = math.min(560, math.max(470, viewport.X - 40))
	local panelHeight = math.min(470, math.max(390, viewport.Y - 50))
	local initialX = math.clamp(CONFIG.uiOffsetX or 24, 0, math.max(0, viewport.X - panelWidth))
	local initialY = math.clamp(CONFIG.uiOffsetY or 120, 0, math.max(0, viewport.Y - panelHeight))

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
		Position = UDim2.new(0, initialX, 0, initialY),
		Size = UDim2.new(0, panelWidth, 0, panelHeight),
		Parent = gui,
	})
	corner(panel, 6)
	stroke(panel, THEME.borderBright, 0.2)

	local accentRail = create("Frame", {
		BackgroundColor3 = THEME.accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 1, 0),
		Parent = panel,
	})

	local header = create("Frame", {
		BackgroundColor3 = THEME.surface,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 3, 0, 0),
		Size = UDim2.new(1, -3, 0, 58),
		Parent = panel,
	})
	create("Frame", {
		BackgroundColor3 = THEME.border,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		Parent = header,
	})

	local title = label(header, "0xVyrs / TYCOON", 14, THEME.text, Enum.Font.GothamBold)
	title.Position = UDim2.new(0, 16, 0, 8)
	title.Size = UDim2.new(0, 220, 0, 20)
	local subtitle = label(header, autonomousMode and "AUTONOMOUS CONTROL SYSTEM" or "TYCOON CONTROL SYSTEM", 8, THEME.muted, Enum.Font.GothamBold)
	subtitle.Position = UDim2.new(0, 16, 0, 29)
	subtitle.Size = UDim2.new(0, 260, 0, 14)

	local stateDot = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = THEME.faint,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -111, 0.5, 0),
		Size = UDim2.new(0, 6, 0, 6),
		Parent = header,
	})
	corner(stateDot, 99)
	local stateText = label(header, "OFFLINE", 8, THEME.muted, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
	stateText.AnchorPoint = Vector2.new(1, 0.5)
	stateText.Position = UDim2.new(1, -18, 0.5, 0)
	stateText.Size = UDim2.new(0, 82, 0, 16)

	local collapseButton = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.new(0, 24, 0, 20),
		Text = "_",
		TextColor3 = THEME.faint,
		TextSize = 12,
		Parent = header,
	})

	local sidebar = create("Frame", {
		BackgroundColor3 = THEME.surface,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 3, 0, 58),
		Size = UDim2.new(0, 96, 1, -58),
		Parent = panel,
	})
	create("Frame", {
		BackgroundColor3 = THEME.border,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -1, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		Parent = sidebar,
	})

	local content = create("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 99, 0, 58),
		Size = UDim2.new(1, -99, 1, -58),
		Parent = panel,
	})

	local pages = {}
	local navButtons = {}
	local toggles = {}
	local cycleButtons = {}
	local status = {}
	local feedLines = {}
	local feedHistory = {}
	local previous = { bought = 0, rewards = 0, plan = nil, owner = nil }

	local function makePage(name)
		local page = create("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, 0),
			Visible = false,
			Parent = content,
		})
		pages[name] = page
		return page
	end

	local function makeScrollPage(name)
		local page = makePage(name)
		local scroll = create("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 12, 0, 12),
			Size = UDim2.new(1, -24, 1, -24),
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = THEME.borderBright,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Parent = page,
		})
		local layout = create("UIListLayout", {
			Padding = UDim.new(0, 7),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = scroll,
		})
		track(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 4)
		end))
		return page, scroll
	end

	local function setPage(name)
		if not pages[name] then return end
		activePage = name
		for pageName, page in pairs(pages) do page.Visible = pageName == name end
		for pageName, button in pairs(navButtons) do
			button.TextColor3 = pageName == name and THEME.text or THEME.muted
			button.BackgroundColor3 = pageName == name and THEME.surface2 or THEME.surface
			local marker = button:FindFirstChild("Marker")
			if marker then marker.Visible = pageName == name end
		end
	end

	local navNames = autonomousMode and { "COMMAND", "AUTOPILOT", "ECONOMY", "SCANNER", "SETTINGS" }
		or { "COMMAND", "AUTOMATION", "SCANNER", "SETTINGS" }
	for index, name in ipairs(navNames) do
		local button = create("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = THEME.surface,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(0, 0, 0, 18 + ((index - 1) * 35)),
			Size = UDim2.new(1, -1, 0, 30),
			Text = "  " .. name,
			TextColor3 = THEME.muted,
			TextSize = 8,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = sidebar,
		})
		local marker = create("Frame", {
			Name = "Marker",
			BackgroundColor3 = THEME.accent,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 0, 5),
			Size = UDim2.new(0, 2, 1, -10),
			Visible = false,
			Parent = button,
		})
		navButtons[name] = button
		track(button.MouseButton1Click:Connect(function() setPage(name) end))
	end

	local version = label(sidebar, "v" .. tostring(CONFIG.version), 7, THEME.faint, Enum.Font.GothamMedium)
	version.AnchorPoint = Vector2.new(0, 1)
	version.Position = UDim2.new(0, 10, 1, -11)
	version.Size = UDim2.new(1, -20, 0, 12)

	local function pageTitle(parent, kicker, heading)
		local a = label(parent, kicker, 7, THEME.accent, Enum.Font.GothamBold)
		a.Position = UDim2.new(0, 14, 0, 11)
		a.Size = UDim2.new(1, -28, 0, 12)
		local b = label(parent, heading, 15, THEME.text, Enum.Font.GothamBold)
		b.Position = UDim2.new(0, 14, 0, 24)
		b.Size = UDim2.new(1, -28, 0, 22)
	end

	local function card(parent, x, y, w, h)
		local frame = create("Frame", {
			BackgroundColor3 = THEME.surface,
			BorderSizePixel = 0,
			Position = UDim2.new(0, x, 0, y),
			Size = UDim2.new(0, w, 0, h),
			Parent = parent,
		})
		corner(frame, 5)
		stroke(frame, THEME.border, 0.15)
		return frame
	end

	local function metric(parent, caption, x, y, w)
		local c = label(parent, caption, 7, THEME.muted, Enum.Font.GothamBold)
		c.Position = UDim2.new(0, x, 0, y)
		c.Size = UDim2.new(0, w, 0, 11)
		local v = label(parent, "--", 11, THEME.text, Enum.Font.GothamBold)
		v.Position = UDim2.new(0, x, 0, y + 12)
		v.Size = UDim2.new(0, w, 0, 17)
		return v
	end

	local function feedAdd(text)
		if not text or text == "" then return end
		table.insert(feedHistory, 1, text)
		while #feedHistory > 5 do table.remove(feedHistory) end
		for i, line in ipairs(feedLines) do
			line.Text = feedHistory[i] or ""
			line.TextColor3 = i == 1 and THEME.text or THEME.muted
		end
	end

	-- COMMAND
	local command = makePage("COMMAND")
	pageTitle(command, "LIVE CONTROL", "Command")
	local objective = card(command, 14, 56, panelWidth - 141, 132)
	local objectiveKicker = label(objective, "CURRENT OBJECTIVE", 7, THEME.accent, Enum.Font.GothamBold)
	objectiveKicker.Position = UDim2.new(0, 12, 0, 9)
	objectiveKicker.Size = UDim2.new(1, -24, 0, 12)
	status.objective = label(objective, "Waiting for scan", 15, THEME.text, Enum.Font.GothamBold)
	status.objective.Position = UDim2.new(0, 12, 0, 24)
	status.objective.Size = UDim2.new(1, -126, 0, 22)
	status.objectivePrice = label(objective, "--", 13, THEME.text, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
	status.objectivePrice.AnchorPoint = Vector2.new(1, 0)
	status.objectivePrice.Position = UDim2.new(1, -12, 0, 24)
	status.objectivePrice.Size = UDim2.new(0, 100, 0, 22)
	local progressTrack = create("Frame", {
		BackgroundColor3 = THEME.surface3,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 12, 0, 56),
		Size = UDim2.new(1, -24, 0, 4),
		Parent = objective,
	})
	corner(progressTrack, 99)
	status.progress = create("Frame", {
		BackgroundColor3 = THEME.accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = progressTrack,
	})
	corner(status.progress, 99)
	status.progressText = label(objective, "-- / --", 8, THEME.muted, Enum.Font.GothamMedium)
	status.progressText.Position = UDim2.new(0, 12, 0, 64)
	status.progressText.Size = UDim2.new(1, -24, 0, 13)
	status.eta = metric(objective, "ETA", 12, 88, 70)
	status.payback = metric(objective, "PAYBACK", 92, 88, 78)
	status.category = metric(objective, "TYPE", 180, 88, 88)
	status.score = metric(objective, "SCORE", 278, 88, 70)

	local commandWidth = panelWidth - 141
	local halfMetric = math.floor((commandWidth - 7) / 2)
	local metricsCard = card(command, 14, 197, commandWidth, 66)
	status.cash = metric(metricsCard, "CASH", 12, 8, halfMetric - 18)
	status.cpm = metric(metricsCard, "CASH / MIN", halfMetric + 2, 8, halfMetric - 18)
	status.pb = metric(metricsCard, "PERSONAL BEST", 12, 36, halfMetric - 18)
	status.bottleneck = metric(metricsCard, "BOTTLENECK", halfMetric + 2, 36, halfMetric - 18)

	local feedCard = card(command, 14, 272, commandWidth, panelHeight - 344)
	local feedTitle = label(feedCard, "ACTIVITY", 7, THEME.muted, Enum.Font.GothamBold)
	feedTitle.Position = UDim2.new(0, 12, 0, 8)
	feedTitle.Size = UDim2.new(1, -24, 0, 12)
	for i = 1, 5 do
		local line = label(feedCard, "", 8, THEME.muted, Enum.Font.GothamMedium)
		line.Position = UDim2.new(0, 12, 0, 23 + ((i - 1) * 17))
		line.Size = UDim2.new(1, -24, 0, 14)
		feedLines[i] = line
	end

	local function scrollSection(scroll, text)
		local l = label(scroll, text, 7, THEME.accent, Enum.Font.GothamBold)
		l.Size = UDim2.new(1, -4, 0, 16)
		return l
	end

	local function makeControlRow(scroll, caption)
		local row = create("Frame", {
			BackgroundColor3 = THEME.surface,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -4, 0, 34),
			Parent = scroll,
		})
		corner(row, 4)
		stroke(row, THEME.border, 0.2)
		local text = label(row, caption, 8, THEME.muted, Enum.Font.GothamBold)
		text.Position = UDim2.new(0, 11, 0, 0)
		text.Size = UDim2.new(1, -120, 1, 0)
		return row
	end

	local function setToggleVisual(entry, value)
		entry.dot.BackgroundColor3 = value and (entry.danger and THEME.danger or THEME.accent) or THEME.faint
		entry.button.Text = value and "ACTIVE" or "OFF"
		entry.button.TextColor3 = value and THEME.text or THEME.muted
		entry.button.BackgroundColor3 = value and (entry.danger and Color3.fromRGB(67, 34, 39) or THEME.accentDim) or THEME.surface2
	end

	local function toggleRow(scroll, key, caption, danger)
		local row = makeControlRow(scroll, caption)
		local dot = create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = THEME.faint,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -86, 0.5, 0),
			Size = UDim2.new(0, 5, 0, 5),
			Parent = row,
		})
		corner(dot, 99)
		local button = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = THEME.surface2,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -9, 0.5, 0),
			Size = UDim2.new(0, 68, 0, 20),
			Text = "OFF",
			TextColor3 = THEME.muted,
			TextSize = 7,
			Parent = row,
		})
		corner(button, 3)
		stroke(button, danger and THEME.danger or THEME.border, 0.45)
		local entry = { button = button, dot = dot, danger = danger }
		toggles[key] = entry
		setToggleVisual(entry, CONFIG[key] == true)
		track(button.MouseButton1Click:Connect(function()
			CONFIG[key] = not CONFIG[key]
			setToggleVisual(entry, CONFIG[key])
			if callbacks[key] then callbacks[key](CONFIG[key]) elseif context.saveSettings then context.saveSettings() end
		end))
		return row
	end

	local function cycleRow(scroll, key, caption)
		local row = makeControlRow(scroll, caption)
		local button = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = THEME.surface2,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -9, 0.5, 0),
			Size = UDim2.new(0, 104, 0, 20),
			Text = tostring(CONFIG[key]),
			TextColor3 = THEME.text,
			TextSize = 7,
			Parent = row,
		})
		corner(button, 3)
		stroke(button, THEME.border, 0.35)
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
			if cycleCallbacks[key] then cycleCallbacks[key](CONFIG[key]) elseif context.saveSettings then context.saveSettings() end
		end))
		return row
	end

	local function actionRow(scroll, leftKey, leftText, rightKey, rightText, rightDanger)
		local row = create("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -4, 0, 34), Parent = scroll })
		local function make(key, text, x, danger)
			local b = create("TextButton", {
				AutoButtonColor = false,
				BackgroundColor3 = danger and Color3.fromRGB(58, 31, 35) or THEME.accentDim,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Position = UDim2.new(x, x == 0 and 0 or 4, 0, 0),
				Size = UDim2.new(0.5, -4, 1, 0),
				Text = text,
				TextColor3 = danger and THEME.danger or THEME.text,
				TextSize = 8,
				Parent = row,
			})
			corner(b, 4)
			stroke(b, danger and THEME.danger or THEME.borderBright, 0.25)
			track(b.MouseButton1Click:Connect(function() if actionCallbacks[key] then actionCallbacks[key]() end end))
		end
		make(leftKey, leftText, 0, false)
		make(rightKey, rightText, 0.5, rightDanger)
		return row
	end

	local function dangerAction(scroll, key, text)
		local b = create("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(49, 28, 32),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Size = UDim2.new(1, -4, 0, 34),
			Text = text,
			TextColor3 = THEME.danger,
			TextSize = 8,
			Parent = scroll,
		})
		corner(b, 4)
		stroke(b, THEME.danger, 0.45)
		track(b.MouseButton1Click:Connect(function() if actionCallbacks[key] then actionCallbacks[key]() end end))
		return b
	end

	-- AUTOPILOT / AUTOMATION
	local autoName = autonomousMode and "AUTOPILOT" or "AUTOMATION"
	local autoPage, autoScroll = makeScrollPage(autoName)
	scrollSection(autoScroll, autonomousMode and "RUN CONTROL" or "AUTOMATION")
	toggleRow(autoScroll, "enabled", "SYSTEM")
	toggleRow(autoScroll, "autoBuy", "AUTO BUY")
	toggleRow(autoScroll, "autoCollect", "AUTO COLLECT")
	if autonomousMode then
		cycleRow(autoScroll, "strategy", "STRATEGY")
		toggleRow(autoScroll, "autopilotEnabled", "AUTOPILOT BRAIN")
		toggleRow(autoScroll, "learningEnabled", "ADAPTIVE LEARNING")
		toggleRow(autoScroll, "burstMode", "HYPER BUY")
		toggleRow(autoScroll, "autoRewards", "FREE REWARDS")
		toggleRow(autoScroll, "autoRebirth", "AUTO REBIRTH", true)
		scrollSection(autoScroll, "ACTIONS")
		actionRow(autoScroll, "start", "START RUN", "stop", "STOP", true)
		dangerAction(autoScroll, "resetLearning", "RESET LEARNED ROUTE")
	end

	-- ECONOMY
	if autonomousMode then
		local economy = makePage("ECONOMY")
		pageTitle(economy, "TELEMETRY", "Economy")
		local econWidth = panelWidth - 141
		local top = card(economy, 14, 58, econWidth, 92)
		status.econCash = metric(top, "BALANCE", 12, 10, 110)
		status.econRate = metric(top, "INCOME / MIN", 135, 10, 110)
		status.econPeak = metric(top, "PEAK / MIN", 258, 10, 110)
		status.econSpend = metric(top, "RUN SPEND", 12, 49, 110)
		status.econBought = metric(top, "PURCHASES", 135, 49, 110)
		status.econCollected = metric(top, "COLLECTIONS", 258, 49, 110)
		local lower = card(economy, 14, 160, econWidth, 118)
		local h = label(lower, "RUN ANALYSIS", 7, THEME.accent, Enum.Font.GothamBold)
		h.Position = UDim2.new(0, 12, 0, 8)
		h.Size = UDim2.new(1, -24, 0, 12)
		status.econBottleneck = metric(lower, "CURRENT BOTTLENECK", 12, 28, 160)
		status.econEta = metric(lower, "ESTIMATED FINISH", 190, 28, 140)
		status.econPB = metric(lower, "PERSONAL BEST", 12, 70, 160)
		status.econRewards = metric(lower, "FREE REWARDS", 190, 70, 140)
	end

	-- SCANNER
	local scannerPage = makePage("SCANNER")
	pageTitle(scannerPage, "SYSTEM TELEMETRY", "Scanner")
	local scanWidth = panelWidth - 141
	local scanCard = card(scannerPage, 14, 58, scanWidth, 214)
	local scanFields = {
		{ "scanRoot", "ROOT", 10 }, { "scanOwner", "OWNER", 34 }, { "scanMode", "SCAN MODE", 58 },
		{ "scanTime", "SCAN TIME", 82 }, { "scanButtons", "BUTTONS", 106 }, { "scanCollectors", "COLLECTORS", 130 },
		{ "scanAffordable", "AFFORDABLE", 154 }, { "scanLearning", "LEARNED GRAPH", 178 },
	}
	for _, field in ipairs(scanFields) do
		local left = label(scanCard, field[2], 7, THEME.muted, Enum.Font.GothamBold)
		left.Position = UDim2.new(0, 12, 0, field[3])
		left.Size = UDim2.new(0, 110, 0, 16)
		local right = label(scanCard, "--", 9, THEME.text, Enum.Font.GothamMedium, Enum.TextXAlignment.Right)
		right.Position = UDim2.new(0, 128, 0, field[3])
		right.Size = UDim2.new(1, -140, 0, 16)
		status[field[1]] = right
	end

	-- SETTINGS
	local settingsPage, settingsScroll = makeScrollPage("SETTINGS")
	scrollSection(settingsScroll, "INTERACTION")
	cycleRow(settingsScroll, "touchMode", "TOUCH MODE")
	cycleRow(settingsScroll, "buyMode", "LEGACY BUY MODE")
	cycleRow(settingsScroll, "collectMode", "COLLECT MODE")
	scrollSection(settingsScroll, "WORLD HUD")
	toggleRow(settingsScroll, "highlightAffordable", "AFFORDABLE HIGHLIGHTS")
	toggleRow(settingsScroll, "showWaypoint", "TARGET MARKER")
	toggleRow(settingsScroll, "showLabels", "PURCHASE LABELS")
	scrollSection(settingsScroll, "SAFETY")
	toggleRow(settingsScroll, "requireOwnerMatch", "OWNER VERIFICATION")
	if CONFIG.autoLoadGamePreset ~= nil then toggleRow(settingsScroll, "autoLoadGamePreset", "LOAD GAME PROFILE") end

	-- Compact bar
	local compact = create("Frame", {
		BackgroundColor3 = THEME.window,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = panel.Position,
		Size = UDim2.new(0, math.min(430, panelWidth), 0, 36),
		Visible = false,
		Parent = gui,
	})
	corner(compact, 5)
	stroke(compact, THEME.borderBright, 0.2)
	create("Frame", { BackgroundColor3 = THEME.accent, BorderSizePixel = 0, Size = UDim2.new(0, 3, 1, 0), Parent = compact })
	status.compact = label(compact, "0xVyrs // OFFLINE", 8, THEME.text, Enum.Font.GothamBold)
	status.compact.Position = UDim2.new(0, 14, 0, 0)
	status.compact.Size = UDim2.new(1, -48, 1, 0)
	local compactOpen = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0,
		Font = Enum.Font.GothamBold, Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 30, 0, 24),
		Text = ">", TextColor3 = THEME.accent, TextSize = 10, Parent = compact,
	})

	local function setCollapsed(value)
		collapsed = value == true
		if collapsed then
			compact.Position = panel.Position
			panel.Visible = false
			compact.Visible = true
		else
			panel.Position = compact.Position
			panel.Visible = true
			compact.Visible = false
		end
	end
	track(collapseButton.MouseButton1Click:Connect(function() setCollapsed(true) end))
	track(compactOpen.MouseButton1Click:Connect(function() setCollapsed(false) end))
	track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.RightShift then setCollapsed(not collapsed) end
	end))

	-- Dragging
	local dragging = false
	local dragStart
	local panelStart
	local function clampPosition(x, y, w, h)
		local currentCamera = workspace.CurrentCamera
		local vp = currentCamera and currentCamera.ViewportSize or Vector2.new(1920, 1080)
		x = math.clamp(x, 0, math.max(0, vp.X - w))
		y = math.clamp(y, 0, math.max(0, vp.Y - h))
		if x <= 12 then x = 0 elseif vp.X - (x + w) <= 12 then x = vp.X - w end
		if y <= 12 then y = 0 elseif vp.Y - (y + h) <= 12 then y = vp.Y - h end
		return x, y
	end
	local dragHandle = create("TextButton", {
		AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(0, 3, 0, 0), Size = UDim2.new(1, -132, 0, 58), Text = "", ZIndex = 4, Parent = panel,
	})
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
		local x, y = clampPosition(panelStart.X + delta.X, panelStart.Y + delta.Y, panel.AbsoluteSize.X, panel.AbsoluteSize.Y)
		panel.Position = UDim2.new(0, x, 0, y)
	end))

	local function syncControls()
		for key, entry in pairs(toggles) do setToggleVisual(entry, CONFIG[key] == true) end
		for key, button in pairs(cycleButtons) do button.Text = tostring(CONFIG[key]) end
	end

	local function setSystemState(data)
		if not CONFIG.enabled then
			stateText.Text = "OFFLINE"
			stateText.TextColor3 = THEME.muted
			stateDot.BackgroundColor3 = THEME.faint
		elseif data.ownerVerified then
			stateText.Text = autonomousMode and "AUTONOMOUS" or "READY"
			stateText.TextColor3 = THEME.success
			stateDot.BackgroundColor3 = THEME.success
		elseif CONFIG.requireOwnerMatch then
			stateText.Text = "BLOCKED"
			stateText.TextColor3 = THEME.danger
			stateDot.BackgroundColor3 = THEME.danger
		else
			stateText.Text = "RELAXED"
			stateText.TextColor3 = THEME.warning
			stateDot.BackgroundColor3 = THEME.warning
		end
	end

	local function updateFeed(auto, brain)
		local bought = tonumber(auto.bought) or 0
		local rewards = tonumber(auto.rewardsActivated) or 0
		local planName = brain.plan and brain.plan.name or nil
		local owner = auto.ownerVerified == true
		if previous.owner ~= nil and previous.owner ~= owner then
			feedAdd(owner and "Owner verification acquired" or "Owner verification lost")
		end
		if bought > previous.bought then
			feedAdd(string.format("Purchase confirmed  //  total %d", bought))
		end
		if rewards > previous.rewards then
			feedAdd(string.format("Free reward activated  //  total %d", rewards))
		end
		if planName and planName ~= previous.plan then
			feedAdd("Target -> " .. shortText(planName, 42))
		end
		previous.bought = bought
		previous.rewards = rewards
		previous.plan = planName
		previous.owner = owner
	end

	local function update(payload)
		if destroyed then return end
		latestPayload = payload or latestPayload
		payload = latestPayload or {}
		local data = payload.data or {}
		local statsData = payload.stats or {}
		local auto = payload.autonomous or {}
		local brain = auto.brain or {}
		local plan = brain.plan or {}
		local collectorStatus = auto.collector or {}

		syncControls()
		setSystemState(data)
		updateFeed(auto, brain)

		local cash = tonumber(auto.cash or data.cash or statsData.cash) or 0
		local price = tonumber(plan.price)
		status.objective.Text = shortText(plan.name or (CONFIG.enabled and "Analysing tycoon" or "System stopped"), 34)
		status.objectivePrice.Text = price and ("$" .. formatNumber(price)) or "--"
		local ratio = price and price > 0 and math.clamp(cash / price, 0, 1) or (price == 0 and 1 or 0)
		status.progress.Size = UDim2.new(ratio, 0, 1, 0)
		status.progressText.Text = price and ("$" .. formatNumber(cash) .. " / $" .. formatNumber(price)) or ("$" .. formatNumber(cash))
		status.eta.Text = formatDuration(brain.etaSeconds)
		status.payback.Text = formatDuration(plan.paybackSeconds)
		status.category.Text = tostring(plan.category or "--"):upper()
		status.score.Text = plan.score and tostring(math.floor(plan.score + 0.5)) or "--"
		status.cash.Text = "$" .. formatNumber(cash)
		status.cpm.Text = "+" .. formatNumber(statsData.cashPerMinute or 0) .. "/m"
		status.pb.Text = formatDuration(brain.bestCompletionSeconds)
		status.bottleneck.Text = shortText(brain.bottleneck or "--", 20)

		if autonomousMode then
			status.econCash.Text = "$" .. formatNumber(cash)
			status.econRate.Text = "+" .. formatNumber(statsData.cashPerMinute or 0)
			status.econPeak.Text = "+" .. formatNumber(statsData.peakCashPerMinute or 0)
			local run = brain.currentRun or {}
			status.econSpend.Text = "$" .. formatNumber(run.spent or statsData.totalSpend or 0)
			status.econBought.Text = tostring(auto.bought or 0)
			status.econCollected.Text = tostring(auto.collected or 0)
			status.econBottleneck.Text = shortText(brain.bottleneck or "--", 24)
			status.econEta.Text = formatDuration(brain.etaSeconds)
			status.econPB.Text = formatDuration(brain.bestCompletionSeconds)
			status.econRewards.Text = tostring(auto.rewardsActivated or 0)
		end

		local debugText = tostring(data.debug or "--")
		status.scanRoot.Text = shortText(auto.root or data.rootName or "--", 32)
		status.scanOwner.Text = (data.ownerVerified and "VERIFIED" or "UNVERIFIED")
		status.scanOwner.TextColor3 = data.ownerVerified and THEME.success or THEME.warning
		local scanMode = debugText:match("^(%S+)") or "--"
		local scanMs = debugText:match("([%d%.]+ms)") or "--"
		status.scanMode.Text = tostring(scanMode):upper()
		status.scanTime.Text = scanMs
		status.scanButtons.Text = tostring(data.totalButtons or auto.buttons or 0)
		status.scanCollectors.Text = tostring(#(data.drops or {}))
		status.scanAffordable.Text = string.format("%s ready / %s locked", tostring(data.affordableCount or 0), tostring(data.lockedCount or 0))
		status.scanLearning.Text = string.format("%s nodes / %s edges", tostring(brain.learnedNodes or 0), tostring(brain.learnedEdges or 0))

		local compactState = CONFIG.enabled and (data.ownerVerified and "AUTO" or "WAIT") or "OFF"
		status.compact.Text = string.format("0xVyrs  //  %s  //  $%s  //  +%s/m  //  %s", compactState, formatNumber(cash), formatNumber(statsData.cashPerMinute or 0), shortText(plan.name or "idle", 20))
	end

	local function destroy()
		if destroyed then return end
		destroyed = true
		for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
		table.clear(connections)
		if gui then gui:Destroy() end
	end

	setPage("COMMAND")
	feedAdd("Command console initialised")

	return {
		onToggle = function(key, callback) callbacks[key] = callback end,
		onCycle = function(key, callback) cycleCallbacks[key] = callback end,
		onAction = function(key, callback) actionCallbacks[key] = callback end,
		update = update,
		destroy = destroy,
	}
end