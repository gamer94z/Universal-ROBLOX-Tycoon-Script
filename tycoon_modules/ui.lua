return function(context)
	local CONFIG = context.CONFIG
	local CoreGui = context.CoreGui

	local callbacks = {}

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

	local function stroke(parent, color, transparency)
		create("UIStroke", {
			Color = color,
			Transparency = transparency or 0,
			Thickness = 1,
			Parent = parent,
		})
	end

	local gui = create("ScreenGui", {
		Name = "TycoonCoreGUI",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = CoreGui,
	})

	local panel = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(9, 16, 28),
		BorderSizePixel = 0,
		Position = UDim2.new(0, CONFIG.uiOffsetX, 0, CONFIG.uiOffsetY),
		Size = UDim2.new(0, 278, 0, 286),
		Parent = gui,
	})
	corner(panel, 8)
	stroke(panel, Color3.fromRGB(40, 128, 255), 0.35)

	create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(17, 29, 48)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 10, 18)),
		}),
		Rotation = 90,
		Parent = panel,
	})

	local title = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Position = UDim2.new(0, 14, 0, 10),
		Size = UDim2.new(1, -28, 0, 22),
		Text = "0xVyrs Tycoon Core",
		TextColor3 = Color3.fromRGB(225, 242, 255),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})

	local subtitle = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(0, 14, 0, 31),
		Size = UDim2.new(1, -28, 0, 14),
		Text = "v" .. CONFIG.version .. "  //  universal tycoon helper",
		TextColor3 = Color3.fromRGB(72, 164, 255),
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})

	local body = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 54),
		Size = UDim2.new(1, -24, 1, -66),
		Parent = panel,
	})

	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})

	local labels = {}
	local toggles = {}

	local function row(labelText)
		local frame = create("Frame", {
			BackgroundColor3 = Color3.fromRGB(13, 24, 40),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 24),
			Parent = body,
		})
		corner(frame, 6)
		return frame
	end

	local function statRow(key, labelText)
		local frame = row(labelText)
		local left = create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(0, 9, 0, 0),
			Size = UDim2.new(0.48, 0, 1, 0),
			Text = labelText,
			TextColor3 = Color3.fromRGB(118, 164, 218),
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local value = create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(0.48, 0, 0, 0),
			Size = UDim2.new(0.52, -9, 1, 0),
			Text = "--",
			TextColor3 = Color3.fromRGB(228, 244, 255),
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = frame,
		})
		labels[key] = value
		return left, value
	end

	local function toggleRow(key, labelText)
		local frame = row(labelText)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(0, 9, 0, 0),
			Size = UDim2.new(1, -64, 1, 0),
			Text = labelText,
			TextColor3 = Color3.fromRGB(118, 164, 218),
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local button = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = CONFIG[key] and Color3.fromRGB(24, 84, 144) or Color3.fromRGB(31, 42, 58),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 48, 0, 16),
			Text = CONFIG[key] and "ON" or "OFF",
			TextColor3 = Color3.fromRGB(228, 244, 255),
			TextSize = 9,
			Parent = frame,
		})
		corner(button, 999)
		toggles[key] = button
		button.MouseButton1Click:Connect(function()
			CONFIG[key] = not CONFIG[key]
			button.Text = CONFIG[key] and "ON" or "OFF"
			button.BackgroundColor3 = CONFIG[key] and Color3.fromRGB(24, 84, 144) or Color3.fromRGB(31, 42, 58)
			if callbacks[key] then
				callbacks[key](CONFIG[key])
			end
		end)
	end

	toggleRow("enabled", "ENABLED")
	toggleRow("autoCollect", "AUTO COLLECT")
	toggleRow("highlightAffordable", "HIGHLIGHT UPGRADES")
	toggleRow("showWaypoint", "WAYPOINT")
	statRow("base", "BASE")
	statRow("cash", "CASH")
	statRow("income", "INCOME / MIN")
	statRow("buttons", "AFFORDABLE")
	statRow("nearest", "NEAREST")
	statRow("collected", "COLLECT TOUCHES")

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

	game:GetService("UserInputService").InputChanged:Connect(function(input)
		if not dragging or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) then
			return
		end
		local delta = input.Position - dragStart
		panel.Position = UDim2.new(0, panelStart.X + delta.X, 0, panelStart.Y + delta.Y)
	end)

	local function trim(text, length)
		text = tostring(text or "--")
		if #text <= length then
			return text
		end
		return text:sub(1, length - 3) .. "..."
	end

	local function update(payload)
		local data = payload.data or {}
		local stats = payload.stats or {}
		local affordable = 0
		if data.buttons then
			for _, button in ipairs(data.buttons) do
				if button.affordable then
					affordable = affordable + 1
				end
			end
		end

		labels.base.Text = trim(data.rootName or "Scanning", 18)
		labels.cash.Text = tostring(stats.cash or 0)
		labels.income.Text = tostring(stats.cashPerMinute or 0)
		labels.buttons.Text = tostring(affordable)
		labels.nearest.Text = payload.nearest and trim(payload.nearest.name, 18) or "None"
		labels.collected.Text = tostring(payload.collected or 0)
	end

	return {
		update = update,
		onToggle = function(key, callback)
			callbacks[key] = callback
		end,
		destroy = function()
			gui:Destroy()
		end,
	}
end
