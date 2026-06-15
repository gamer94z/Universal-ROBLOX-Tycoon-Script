return function(context)
	local CONFIG = context.CONFIG
	local CoreGui = context.CoreGui
	local UserInputService = game:GetService("UserInputService")
	local TweenService = game:GetService("TweenService")

	local callbacks = {}
	local cycleCallbacks = {}
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

	local gui = create("ScreenGui", {
		Name = "TycoonCoreGUI",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = CoreGui,
	})

	local panel = create("Frame", {
		BackgroundColor3 = THEME.window,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.new(0, CONFIG.uiOffsetX - 14, 0, CONFIG.uiOffsetY),
		Size = UDim2.new(0, 286, 0, 356),
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

	local subtitle = label(header, "v" .. CONFIG.version .. "  //  safe automation", 8, THEME.accent, Enum.Font.GothamBold)
	subtitle.Position = UDim2.new(0, 13, 0, 28)
	subtitle.Size = UDim2.new(1, -112, 0, 12)

	local stateBadge = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = THEME.accentSoft,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -12, 0, 13),
		Size = UDim2.new(0, 82, 0, 20),
		Text = "SCANNING",
		TextColor3 = THEME.text,
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
			AnchorPoint = Vector2.new(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(20, 24, 34),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 24, 0, 0),
			Size = UDim2.new(1, 0, 0, 0),
			ZIndex = 31,
			Parent = toastLayer,
		})
		corner(toast, 10)
		stroke(toast, accentColor or THEME.accent, 0.2, 1)

		create("UIPadding", {
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 9),
			PaddingBottom = UDim.new(0, 9),
			Parent = toast,
		})

		local toastTitle = label(toast, titleText, 11, THEME.text, Enum.Font.GothamBold)
		toastTitle.AutomaticSize = Enum.AutomaticSize.Y
		toastTitle.Size = UDim2.new(1, 0, 0, 14)
		toastTitle.TextTransparency = 1
		toastTitle.ZIndex = 32

		local toastDetail = label(toast, detailText, 10, THEME.muted, Enum.Font.GothamMedium)
		toastDetail.AutomaticSize = Enum.AutomaticSize.Y
		toastDetail.Position = UDim2.new(0, 0, 0, 16)
		toastDetail.Size = UDim2.new(1, 0, 0, 12)
		toastDetail.TextTransparency = 1
		toastDetail.ZIndex = 32

		tween(toast, 0.18, {
			BackgroundTransparency = 0,
			Position = UDim2.new(0, 0, 0, 0),
		})
		tween(toastTitle, 0.18, { TextTransparency = 0 })
		tween(toastDetail, 0.18, { TextTransparency = 0 })

		task.delay(1.75, function()
			if not toast or not toast.Parent then
				return
			end
			tween(toast, 0.18, {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 24, 0, 0),
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(toastTitle, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(toastDetail, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

			task.delay(0.22, function()
				if toast then
					toast:Destroy()
				end
			end)
		end)
	end

	local loader = create("Frame", {
		BackgroundColor3 = THEME.window,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 20,
		Parent = panel,
	})
	corner(loader, 8)

	local loaderAccent = create("Frame", {
		BackgroundColor3 = THEME.accent,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(0, 0, 0, 3),
		ZIndex = 21,
		Parent = loader,
	})

	local loaderTitle = label(loader, "0xVyrs Tycoon", 15, THEME.text, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
	loaderTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	loaderTitle.Position = UDim2.new(0.5, 0, 0.5, -10)
	loaderTitle.Size = UDim2.new(1, -24, 0, 22)
	loaderTitle.ZIndex = 21

	local loaderSub = label(loader, "loading safe automation", 9, THEME.accent, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	loaderSub.AnchorPoint = Vector2.new(0.5, 0.5)
	loaderSub.Position = UDim2.new(0.5, 0, 0.5, 12)
	loaderSub.Size = UDim2.new(1, -24, 0, 14)
	loaderSub.ZIndex = 21

	local body = create("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 10, 0, 60),
		Size = UDim2.new(1, -20, 1, -70),
		Parent = panel,
	})

	create("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})

	local toggles = {}
	local cycleButtons = {}

	local function makeRow(labelText)
		local row = create("Frame", {
			BackgroundColor3 = THEME.panel,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 24),
			Parent = body,
		})
		corner(row, 7)
		stroke(row, THEME.border, 0.52, 1)

		local rowLabel = label(row, labelText, 10, THEME.muted, Enum.Font.GothamBold)
		rowLabel.Position = UDim2.new(0, 10, 0, 0)
		rowLabel.Size = UDim2.new(1, -112, 1, 0)

		return row
	end

	local function setToggleVisual(button, value)
		button.Text = value and "ON" or "OFF"
		button.TextColor3 = value and Color3.fromRGB(228, 241, 255) or THEME.muted
		button.BackgroundColor3 = value and THEME.accentSoft or Color3.fromRGB(35, 40, 53)
		local buttonStroke = button:FindFirstChildOfClass("UIStroke")
		if buttonStroke then
			buttonStroke.Transparency = value and 0.15 or 0.58
		end
	end

	local function toggleRow(key, labelText)
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
		setToggleVisual(button, CONFIG[key] == true)
		toggles[key] = button

		button.MouseButton1Click:Connect(function()
			CONFIG[key] = not CONFIG[key]
			setToggleVisual(button, CONFIG[key])
			if callbacks[key] then
				callbacks[key](CONFIG[key])
			end
			showToast("Tycoon", string.format("%s %s", labelText, CONFIG[key] and "enabled" or "disabled"), CONFIG[key] and THEME.accent or THEME.muted)
		end)
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

		button.MouseButton1Click:Connect(function()
			local values = CYCLES[key] or {}
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
			end
			showToast("Tycoon", string.format("%s set to %s", labelText, tostring(CONFIG[key])), THEME.accent)
		end)
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
		Parent = panel,
	})

	dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragging = true
		dragStart = input.Position
		panelStart = panel.AbsolutePosition
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				CONFIG.uiOffsetX = panel.Position.X.Offset
				CONFIG.uiOffsetY = panel.Position.Y.Offset
				context.saveSettings()
			end
		end)
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) then
			return
		end
		local delta = input.Position - dragStart
		panel.Position = UDim2.new(0, panelStart.X + delta.X, 0, panelStart.Y + delta.Y)
	end)

	local function update(payload)
		local data = payload.data or {}
		if data.ownerVerified then
			stateBadge.Text = "READY"
			stateBadge.BackgroundColor3 = THEME.accentSoft
			stateBadge.TextColor3 = THEME.text
		elseif data.ownerMatch then
			stateBadge.Text = "COLLECT"
			stateBadge.BackgroundColor3 = Color3.fromRGB(86, 71, 28)
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
	end

	tween(panel, 0.24, {
		BackgroundTransparency = 0,
		Position = UDim2.new(0, CONFIG.uiOffsetX, 0, CONFIG.uiOffsetY),
	})
	tween(header, 0.24, {
		BackgroundTransparency = 0,
	})
	tween(loaderAccent, 0.42, {
		Size = UDim2.new(1, 0, 0, 3),
	})
	task.delay(0.48, function()
		if not loader or not loader.Parent then
			return
		end
		tween(loaderTitle, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(loaderSub, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(loader, 0.22, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.24, function()
			if loader then
				loader:Destroy()
			end
			showToast("Tycoon Core", "Loaded with automation disabled", THEME.accent)
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
		destroy = function()
			gui:Destroy()
		end,
	}
end
