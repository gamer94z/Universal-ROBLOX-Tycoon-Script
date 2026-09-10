return function(context)
	local CONFIG = context and context.CONFIG or {}
	local highlights = {}
	local labels = {}
	local waypointGui
	local guiHost = context and context.LOCAL_PLAYER and context.LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui")

	-- Same visual language as 0xVyrs ESP Console.exe.
	local THEME = {
		panel = Color3.fromRGB(2, 3, 3),
		surface = Color3.fromRGB(8, 10, 10),
		border = Color3.fromRGB(74, 74, 74),
		text = Color3.fromRGB(229, 232, 230),
		muted = Color3.fromRGB(132, 140, 137),
		accent = Color3.fromRGB(91, 221, 137),
		cyan = Color3.fromRGB(89, 198, 226),
		warning = Color3.fromRGB(238, 193, 84),
		danger = Color3.fromRGB(238, 103, 103),
	}

	local function stroke(parent, colour, transparency)
		local item = Instance.new("UIStroke")
		item.Color = colour or THEME.border
		item.Transparency = transparency or 0
		item.Thickness = 1
		item.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		item.Parent = parent
		return item
	end

	local function makeText(parent, name, text, size, colour, alignment)
		local item = Instance.new("TextLabel")
		item.Name = name
		item.BackgroundTransparency = 1
		item.BorderSizePixel = 0
		item.Font = Enum.Font.Code
		item.Text = text or ""
		item.TextColor3 = colour or THEME.text
		item.TextSize = size or 10
		item.TextXAlignment = alignment or Enum.TextXAlignment.Left
		item.TextYAlignment = Enum.TextYAlignment.Center
		item.TextTruncate = Enum.TextTruncate.AtEnd
		item.Parent = parent
		return item
	end

	local function formatNumber(value)
		local n = tonumber(value)
		if not n then return "?" end
		local a = math.abs(n)
		if a >= 1e15 then return string.format("%.2fQ", n / 1e15) end
		if a >= 1e12 then return string.format("%.2fT", n / 1e12) end
		if a >= 1e9 then return string.format("%.2fB", n / 1e9) end
		if a >= 1e6 then return string.format("%.2fM", n / 1e6) end
		if a >= 1e3 then return string.format("%.1fK", n / 1e3) end
		return tostring(math.floor(n + 0.5))
	end

	local function cleanName(value)
		local text = tostring(value or "UPGRADE")
		text = text:gsub("%b[]", " ")
		text = text:gsub("%$[%d%.,]+[%a]*", " ")
		text = text:gsub("%s+%-%s+$", "")
		text = text:gsub("%s+", " ")
		text = text:match("^%s*(.-)%s*$") or text
		if text == "" then text = "UPGRADE" end
		return text
	end

	local function clear()
		for object, highlight in pairs(highlights) do
			if highlight then highlight:Destroy() end
			highlights[object] = nil
		end
	end

	local function clearLabels()
		for object, gui in pairs(labels) do
			if gui then gui:Destroy() end
			labels[object] = nil
		end
	end

	local function hideWaypoint()
		if waypointGui then waypointGui.Enabled = false waypointGui.Adornee = nil end
	end

	local function destroy()
		clear()
		clearLabels()
		if waypointGui then waypointGui:Destroy() waypointGui = nil end
	end

	local function buttonAvailable(button)
		return button
			and button.affordable
			and not button.paidPurchase
			and (not button.blockedUntil or button.blockedUntil <= os.clock())
	end

	local function getDistance(entry, root)
		if not entry or not entry.part or not root then return math.huge end
		return (entry.part.Position - root.Position).Magnitude
	end

	local function getNearestAffordable(data, root)
		if not data or not data.buttons or not root then return nil end
		local best
		local bestDistance = math.huge
		for _, button in ipairs(data.buttons) do
			if buttonAvailable(button) and button.part and button.part.Parent then
				local distance = getDistance(button, root)
				if distance < bestDistance then bestDistance = distance best = button end
			end
		end
		return best
	end

	local function getCheapestAffordable(data)
		if not data or not data.buttons then return nil end
		local best
		local bestPrice = math.huge
		for _, button in ipairs(data.buttons) do
			if buttonAvailable(button) then
				local price = button.price or 0
				if price < bestPrice then bestPrice = price best = button end
			end
		end
		return best
	end

	local function getMostExpensiveAffordable(data)
		if not data or not data.buttons then return nil end
		local best
		local bestPrice = -math.huge
		for _, button in ipairs(data.buttons) do
			if buttonAvailable(button) then
				local price = button.price or 0
				if price > bestPrice then bestPrice = price best = button end
			end
		end
		return best
	end

	local function getNextLocked(data)
		if not data or not data.buttons then return nil end
		local best
		local bestPrice = math.huge
		for _, button in ipairs(data.buttons) do
			if button.locked and not button.paidPurchase and button.price and button.price < bestPrice then
				bestPrice = button.price
				best = button
			end
		end
		return best
	end

	local function choosePurchase(data, root, mode)
		if mode == "Cheapest" then return getCheapestAffordable(data) end
		if mode == "Value" then return getMostExpensiveAffordable(data) end
		return getNearestAffordable(data, root)
	end

	local function render(data, target)
		if not data or not data.buttons then clear() return end
		local seen = {}
		for _, button in ipairs(data.buttons) do
			local object = button.object
			if buttonAvailable(button) and object and object.Parent then
				seen[object] = true
				local highlight = highlights[object]
				if not highlight then
					highlight = Instance.new("Highlight")
					highlight.Name = "VyrsTycoonHighlight"
					highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					highlight.Parent = object
					highlights[object] = highlight
				end
				local isTarget = target and target.object == object
				highlight.FillColor = THEME.accent
				highlight.OutlineColor = isTarget and THEME.cyan or THEME.accent
				highlight.FillTransparency = isTarget and 0.84 or 1
				highlight.OutlineTransparency = isTarget and 0.04 or 0.48
			end
		end
		for object, highlight in pairs(highlights) do
			if not seen[object] then highlight:Destroy() highlights[object] = nil end
		end
	end

	local function makeLabel(button)
		local gui = Instance.new("BillboardGui")
		gui.Name = "VyrsPurchaseHUD"
		gui.AlwaysOnTop = true
		gui.MaxDistance = 260
		gui.Size = UDim2.new(0, 176, 0, 40)
		gui.StudsOffset = Vector3.new(0, 3.1, 0)

		local panel = Instance.new("Frame")
		panel.Name = "Panel"
		panel.BackgroundColor3 = THEME.panel
		panel.BackgroundTransparency = 0.03
		panel.BorderColor3 = THEME.border
		panel.BorderSizePixel = 1
		panel.Size = UDim2.new(1, 0, 1, 0)
		panel.Parent = gui

		local prompt = makeText(panel, "Prompt", ">", 11, THEME.accent)
		prompt.Position = UDim2.new(0, 7, 0, 2)
		prompt.Size = UDim2.new(0, 12, 0, 17)

		local title = makeText(panel, "Title", cleanName(button.name), 9, THEME.muted)
		title.Position = UDim2.new(0, 20, 0, 2)
		title.Size = UDim2.new(1, -26, 0, 17)

		local price = makeText(panel, "Price", "$" .. formatNumber(button.price), 11, THEME.text)
		price.Position = UDim2.new(0, 8, 0, 20)
		price.Size = UDim2.new(0.55, -8, 0, 16)

		local state = makeText(panel, "State", button.affordable and "[ READY ]" or "[ LOCKED ]", 9, button.affordable and THEME.accent or THEME.warning, Enum.TextXAlignment.Right)
		state.Position = UDim2.new(0.55, 0, 0, 20)
		state.Size = UDim2.new(0.45, -7, 0, 16)

		gui.Adornee = button.part
		gui.Parent = guiHost or button.part
		return gui
	end

	local function removeLabel(object)
		local gui = labels[object]
		if gui then gui:Destroy() labels[object] = nil end
	end

	local function updateLabel(gui, button)
		local panel = gui and gui:FindFirstChild("Panel")
		if not panel then return end
		local title = panel:FindFirstChild("Title")
		local price = panel:FindFirstChild("Price")
		local state = panel:FindFirstChild("State")
		if title then title.Text = cleanName(button.name) end
		if price then price.Text = "$" .. formatNumber(button.price) end
		if state then
			state.Text = button.affordable and "[ READY ]" or "[ LOCKED ]"
			state.TextColor3 = button.affordable and THEME.accent or THEME.warning
		end
	end

	local function renderLabels(data, target)
		if not data or not data.buttons or data.showLabels == false then clearLabels() return end
		local seen = {}
		local shown = 0
		for _, button in ipairs(data.buttons) do
			if shown >= (data.maxLabels or CONFIG.maxLabels or 12) then break end
			local object = button.object
			local isTarget = CONFIG.showWaypoint == true and target and target.object == object
			if isTarget then
				removeLabel(object)
			elseif button.part and button.part.Parent and object and object.Parent and not button.paidPurchase then
				shown = shown + 1
				seen[object] = true
				local gui = labels[object]
				if not gui or not gui.Parent then gui = makeLabel(button) labels[object] = gui end
				gui.Enabled = true
				gui.Adornee = button.part
				updateLabel(gui, button)
			end
		end
		for object, gui in pairs(labels) do
			if not seen[object] then gui:Destroy() labels[object] = nil end
		end
	end

	local function createWaypoint()
		local gui = Instance.new("BillboardGui")
		gui.Name = "VyrsCurrentTargetHUD"
		gui.AlwaysOnTop = true
		gui.MaxDistance = 600
		gui.Size = UDim2.new(0, 238, 0, 68)
		gui.StudsOffset = Vector3.new(0, 4.35, 0)

		local panel = Instance.new("Frame")
		panel.Name = "Panel"
		panel.BackgroundColor3 = THEME.panel
		panel.BackgroundTransparency = 0.01
		panel.BorderColor3 = THEME.accent
		panel.BorderSizePixel = 1
		panel.Size = UDim2.new(1, 0, 0, 58)
		panel.Parent = gui

		local prompt = makeText(panel, "Prompt", ">_", 11, THEME.accent)
		prompt.Position = UDim2.new(0, 8, 0, 4)
		prompt.Size = UDim2.new(0, 24, 0, 15)

		local kicker = makeText(panel, "Kicker", "CURRENT TARGET", 9, THEME.cyan)
		kicker.Position = UDim2.new(0, 35, 0, 4)
		kicker.Size = UDim2.new(1, -43, 0, 15)

		local title = makeText(panel, "Title", "UPGRADE", 11, THEME.text)
		title.Position = UDim2.new(0, 8, 0, 20)
		title.Size = UDim2.new(1, -105, 0, 17)

		local price = makeText(panel, "Price", "$0", 11, THEME.text, Enum.TextXAlignment.Right)
		price.AnchorPoint = Vector2.new(1, 0)
		price.Position = UDim2.new(1, -8, 0, 20)
		price.Size = UDim2.new(0, 90, 0, 17)

		local detail = makeText(panel, "Detail", "[ READY ]", 9, THEME.accent)
		detail.Position = UDim2.new(0, 8, 0, 39)
		detail.Size = UDim2.new(1, -16, 0, 14)

		local stem = Instance.new("Frame")
		stem.Name = "Stem"
		stem.BackgroundColor3 = THEME.accent
		stem.BorderSizePixel = 0
		stem.Position = UDim2.new(0.5, 0, 0, 58)
		stem.Size = UDim2.new(0, 1, 0, 8)
		stem.Parent = gui

		local point = Instance.new("Frame")
		point.Name = "Point"
		point.AnchorPoint = Vector2.new(0.5, 0)
		point.BackgroundColor3 = THEME.accent
		point.BorderSizePixel = 0
		point.Position = UDim2.new(0.5, 0, 0, 65)
		point.Size = UDim2.new(0, 5, 0, 3)
		point.Parent = gui
		gui.Parent = guiHost
		return gui
	end

	local function updateWaypoint(entry)
		if not entry or entry.affordable ~= true or entry.paidPurchase
			or not entry.part or not entry.part.Parent then
			hideWaypoint()
			return
		end
		if not waypointGui or not waypointGui.Parent then waypointGui = createWaypoint() end
		if not waypointGui then return end
		waypointGui.Adornee = entry.part
		waypointGui.Enabled = true

		local panel = waypointGui:FindFirstChild("Panel")
		if not panel then return end
		local title = panel:FindFirstChild("Title")
		local price = panel:FindFirstChild("Price")
		local detail = panel:FindFirstChild("Detail")
		if title then title.Text = cleanName(entry.name) end
		if price then price.Text = "$" .. formatNumber(entry.price) end
		if detail then
			local root = context and context.getLocalRoot and context.getLocalRoot()
			local distance = root and entry.part and math.floor((entry.part.Position - root.Position).Magnitude + 0.5) or nil
			detail.Text = distance and string.format("[ READY ]  //  %d STUDS", distance) or "[ READY ]"
			detail.TextColor3 = THEME.accent
		end
	end

	return {
		clear = clear,
		clearLabels = clearLabels,
		hideWaypoint = hideWaypoint,
		destroy = destroy,
		getNearestAffordable = getNearestAffordable,
		getCheapestAffordable = getCheapestAffordable,
		getMostExpensiveAffordable = getMostExpensiveAffordable,
		getNextLocked = getNextLocked,
		choosePurchase = choosePurchase,
		render = render,
		renderLabels = renderLabels,
		updateWaypoint = updateWaypoint,
	}
end