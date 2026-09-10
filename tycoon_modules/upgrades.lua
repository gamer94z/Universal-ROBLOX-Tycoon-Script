return function(context)
	local CONFIG = context and context.CONFIG or {}
	local highlights = {}
	local labels = {}
	local waypointGui

	local THEME = {
		panel = Color3.fromRGB(11, 13, 17),
		surface = Color3.fromRGB(17, 21, 27),
		border = Color3.fromRGB(52, 62, 76),
		text = Color3.fromRGB(241, 244, 248),
		muted = Color3.fromRGB(137, 148, 163),
		accent = Color3.fromRGB(77, 163, 255),
		accentDim = Color3.fromRGB(43, 94, 145),
		success = Color3.fromRGB(102, 214, 158),
		warning = Color3.fromRGB(228, 183, 91),
		danger = Color3.fromRGB(224, 108, 117),
	}

	local function corner(parent, radius)
		local item = Instance.new("UICorner")
		item.CornerRadius = UDim.new(0, radius or 4)
		item.Parent = parent
		return item
	end

	local function stroke(parent, colour, transparency)
		local item = Instance.new("UIStroke")
		item.Color = colour or THEME.border
		item.Transparency = transparency or 0
		item.Thickness = 1
		item.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		item.Parent = parent
		return item
	end

	local function makeText(parent, name, text, size, colour, font, alignment)
		local item = Instance.new("TextLabel")
		item.Name = name
		item.BackgroundTransparency = 1
		item.BorderSizePixel = 0
		item.Font = font or Enum.Font.GothamMedium
		item.Text = text or ""
		item.TextColor3 = colour or THEME.text
		item.TextSize = size or 9
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
		if waypointGui then waypointGui.Enabled = false end
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
				highlight.OutlineColor = isTarget and THEME.text or THEME.accent
				highlight.FillTransparency = isTarget and 0.76 or 1
				highlight.OutlineTransparency = isTarget and 0.04 or 0.42
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
		gui.Size = UDim2.new(0, 164, 0, 42)
		gui.StudsOffset = Vector3.new(0, 3.1, 0)

		local panel = Instance.new("Frame")
		panel.Name = "Panel"
		panel.BackgroundColor3 = THEME.panel
		panel.BackgroundTransparency = 0.06
		panel.BorderSizePixel = 0
		panel.Size = UDim2.new(1, 0, 1, 0)
		panel.Parent = gui
		corner(panel, 4)
		stroke(panel, THEME.border, 0.22)

		local rail = Instance.new("Frame")
		rail.Name = "Rail"
		rail.BackgroundColor3 = THEME.accent
		rail.BorderSizePixel = 0
		rail.Size = UDim2.new(0, 2, 1, 0)
		rail.Parent = panel

		local dot = Instance.new("Frame")
		dot.Name = "StateDot"
		dot.BackgroundColor3 = THEME.accent
		dot.BorderSizePixel = 0
		dot.Position = UDim2.new(0, 10, 0, 9)
		dot.Size = UDim2.new(0, 5, 0, 5)
		dot.Parent = panel
		corner(dot, 99)

		local title = makeText(panel, "Title", cleanName(button.name), 8, THEME.muted, Enum.Font.GothamBold)
		title.Position = UDim2.new(0, 21, 0, 3)
		title.Size = UDim2.new(1, -28, 0, 17)

		local price = makeText(panel, "Price", "$" .. formatNumber(button.price), 11, THEME.text, Enum.Font.GothamBold)
		price.Position = UDim2.new(0, 10, 0, 20)
		price.Size = UDim2.new(0.58, -10, 0, 18)

		local state = makeText(panel, "State", button.affordable and "READY" or "LOCKED", 7, button.affordable and THEME.success or THEME.warning, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
		state.Position = UDim2.new(0.58, 0, 0, 20)
		state.Size = UDim2.new(0.42, -9, 0, 18)

		gui.Adornee = button.part
		gui.Parent = button.part
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
		local dot = panel:FindFirstChild("StateDot")
		if title then title.Text = cleanName(button.name) end
		if price then price.Text = "$" .. formatNumber(button.price) end
		if state then
			state.Text = button.affordable and "READY" or "LOCKED"
			state.TextColor3 = button.affordable and THEME.success or THEME.warning
		end
		if dot then dot.BackgroundColor3 = button.affordable and THEME.accent or THEME.warning end
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
				if not gui then gui = makeLabel(button) labels[object] = gui end
				gui.Enabled = true
				gui.Adornee = button.part
				gui.Parent = button.part
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
		gui.Size = UDim2.new(0, 220, 0, 70)
		gui.StudsOffset = Vector3.new(0, 4.4, 0)

		local panel = Instance.new("Frame")
		panel.Name = "Panel"
		panel.BackgroundColor3 = THEME.panel
		panel.BackgroundTransparency = 0.02
		panel.BorderSizePixel = 0
		panel.Size = UDim2.new(1, 0, 0, 60)
		panel.Parent = gui
		corner(panel, 5)
		stroke(panel, THEME.accent, 0.12)

		local topRail = Instance.new("Frame")
		topRail.BackgroundColor3 = THEME.accent
		topRail.BorderSizePixel = 0
		topRail.Size = UDim2.new(1, 0, 0, 2)
		topRail.Parent = panel

		local kicker = makeText(panel, "Kicker", "CURRENT TARGET", 7, THEME.accent, Enum.Font.GothamBold)
		kicker.Position = UDim2.new(0, 10, 0, 5)
		kicker.Size = UDim2.new(1, -20, 0, 13)

		local title = makeText(panel, "Title", "UPGRADE", 11, THEME.text, Enum.Font.GothamBold)
		title.Position = UDim2.new(0, 10, 0, 19)
		title.Size = UDim2.new(1, -104, 0, 18)

		local price = makeText(panel, "Price", "$0", 11, THEME.text, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
		price.AnchorPoint = Vector2.new(1, 0)
		price.Position = UDim2.new(1, -10, 0, 19)
		price.Size = UDim2.new(0, 84, 0, 18)

		local detail = makeText(panel, "Detail", "READY", 7, THEME.success, Enum.Font.GothamBold)
		detail.Position = UDim2.new(0, 10, 0, 40)
		detail.Size = UDim2.new(1, -20, 0, 13)

		local stem = Instance.new("Frame")
		stem.Name = "Stem"
		stem.BackgroundColor3 = THEME.accent
		stem.BorderSizePixel = 0
		stem.Position = UDim2.new(0.5, -1, 0, 60)
		stem.Size = UDim2.new(0, 2, 0, 7)
		stem.Parent = gui

		local point = Instance.new("Frame")
		point.Name = "Point"
		point.AnchorPoint = Vector2.new(0.5, 0)
		point.BackgroundColor3 = THEME.accent
		point.BorderSizePixel = 0
		point.Position = UDim2.new(0.5, 0, 0, 66)
		point.Size = UDim2.new(0, 5, 0, 5)
		point.Parent = gui
		corner(point, 99)
		return gui
	end

	local function updateWaypoint(entry)
		if not entry or not entry.part or not entry.part.Parent then hideWaypoint() return end
		if not waypointGui then waypointGui = createWaypoint() end
		waypointGui.Adornee = entry.part
		waypointGui.Parent = entry.part
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
			local state = entry.affordable and "READY" or "WAITING"
			detail.Text = distance and string.format("%s  //  %d studs", state, distance) or state
			detail.TextColor3 = entry.affordable and THEME.success or THEME.warning
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