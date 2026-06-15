return function()
	local highlights = {}
	local labels = {}
	local waypointGui

	local function clear()
		for object, highlight in pairs(highlights) do
			if highlight then
				highlight:Destroy()
			end
			highlights[object] = nil
		end
	end

	local function clearLabels()
		for object, label in pairs(labels) do
			if label then
				label:Destroy()
			end
			labels[object] = nil
		end
	end

	local function hideWaypoint()
		if waypointGui then
			waypointGui.Enabled = false
		end
	end

	local function getDistance(entry, root)
		if not entry or not entry.part or not root then
			return math.huge
		end
		return (entry.part.Position - root.Position).Magnitude
	end

	local function getNearestAffordable(data, root)
		if not data or not data.buttons or not root then
			return nil
		end

		local best
		local bestDistance = math.huge
		for _, button in ipairs(data.buttons) do
			if button.affordable and not button.paidPurchase and button.part and button.part.Parent then
				local distance = getDistance(button, root)
				if distance < bestDistance then
					bestDistance = distance
					best = button
				end
			end
		end
		return best
	end

	local function getCheapestAffordable(data)
		if not data or not data.buttons then
			return nil
		end

		local best
		local bestPrice = math.huge
		for _, button in ipairs(data.buttons) do
			if button.affordable and not button.paidPurchase then
				local price = button.price or 0
				if price < bestPrice then
					bestPrice = price
					best = button
				end
			end
		end
		return best
	end

	local function getMostExpensiveAffordable(data)
		if not data or not data.buttons then
			return nil
		end

		local best
		local bestPrice = -math.huge
		for _, button in ipairs(data.buttons) do
			if button.affordable and not button.paidPurchase then
				local price = button.price or 0
				if price > bestPrice then
					bestPrice = price
					best = button
				end
			end
		end
		return best
	end

	local function getNextLocked(data)
		if not data or not data.buttons then
			return nil
		end

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
		if mode == "Cheapest" then
			return getCheapestAffordable(data)
		elseif mode == "Value" then
			return getMostExpensiveAffordable(data)
		end
		return getNearestAffordable(data, root)
	end

	local function render(data, nearest)
		if not data or not data.buttons then
			clear()
			return
		end

		local seen = {}
		for _, button in ipairs(data.buttons) do
			local object = button.object
			if button.affordable and not button.paidPurchase and object and object.Parent then
				seen[object] = true
				local highlight = highlights[object]
				if not highlight then
					highlight = Instance.new("Highlight")
					highlight.Name = "TycoonAffordableHighlight"
					highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					highlight.Parent = object
					highlights[object] = highlight
				end
				local isNearest = nearest and nearest.object == object
				highlight.FillColor = isNearest and Color3.fromRGB(255, 214, 102) or Color3.fromRGB(62, 164, 255)
				highlight.OutlineColor = isNearest and Color3.fromRGB(255, 246, 184) or Color3.fromRGB(190, 225, 255)
				highlight.FillTransparency = isNearest and 0.35 or 0.55
				highlight.OutlineTransparency = 0.08
			end
		end

		for object, highlight in pairs(highlights) do
			if not seen[object] then
				highlight:Destroy()
				highlights[object] = nil
			end
		end
	end

	local function makeLabel(button)
		local gui = Instance.new("BillboardGui")
		gui.Name = "TycoonButtonLabel"
		gui.AlwaysOnTop = true
		gui.Size = UDim2.new(0, 132, 0, 30)
		gui.StudsOffset = Vector3.new(0, 3, 0)

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundColor3 = Color3.fromRGB(6, 14, 26)
		label.BackgroundTransparency = 0.18
		label.BorderSizePixel = 0
		label.Font = Enum.Font.GothamBold
		label.Size = UDim2.new(1, 0, 1, 0)
		label.TextColor3 = Color3.fromRGB(205, 232, 255)
		label.TextSize = 11
		label.Parent = gui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = label

		gui.Adornee = button.part
		gui.Parent = button.part
		return gui
	end

	local function renderLabels(data, nearest)
		if not data or not data.buttons or data.showLabels == false then
			clearLabels()
			return
		end

		local seen = {}
		for index, button in ipairs(data.buttons) do
			if index > (data.maxLabels or 16) then
				break
			end
			if button.part and button.part.Parent then
				seen[button.object] = true
				local gui = labels[button.object]
				if not gui then
					gui = makeLabel(button)
					labels[button.object] = gui
				end
				gui.Enabled = true
				gui.Adornee = button.part
				gui.Parent = button.part
				local label = gui:FindFirstChild("Label")
				if label then
					local tag = nearest and nearest.object == button.object and "NEXT " or ""
					local price = button.price and tostring(button.price) or "?"
					label.Text = string.format("%s$%s", tag, price)
					label.TextColor3 = button.affordable and Color3.fromRGB(180, 232, 255) or Color3.fromRGB(255, 154, 154)
				end
			end
		end

		for object, gui in pairs(labels) do
			if not seen[object] then
				gui:Destroy()
				labels[object] = nil
			end
		end
	end

	local function updateWaypoint(entry)
		if not entry or not entry.part or not entry.part.Parent then
			hideWaypoint()
			return
		end

		if not waypointGui then
			waypointGui = Instance.new("BillboardGui")
			waypointGui.Name = "TycoonWaypoint"
			waypointGui.AlwaysOnTop = true
			waypointGui.Size = UDim2.new(0, 140, 0, 34)
			waypointGui.StudsOffset = Vector3.new(0, 4, 0)

			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.BackgroundColor3 = Color3.fromRGB(8, 18, 34)
			label.BackgroundTransparency = 0.12
			label.BorderSizePixel = 0
			label.Font = Enum.Font.GothamBold
			label.Size = UDim2.new(1, 0, 1, 0)
			label.TextColor3 = Color3.fromRGB(190, 225, 255)
			label.TextSize = 12
			label.Parent = waypointGui

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent = label
		end

		waypointGui.Adornee = entry.part
		waypointGui.Parent = entry.part
		waypointGui.Enabled = true
		local label = waypointGui:FindFirstChild("Label")
		if label then
			label.Text = string.format("NEXT: %s", tostring(entry.price or "?"))
		end
	end

	return {
		clear = clear,
		clearLabels = clearLabels,
		hideWaypoint = hideWaypoint,
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
