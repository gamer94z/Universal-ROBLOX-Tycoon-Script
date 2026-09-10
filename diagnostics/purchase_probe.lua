--[[
	0xVyrs Tycoon Core - purchase structure probe
	Read-only diagnostic utility. It does not activate, touch, click, or purchase anything.
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function lower(value)
	return tostring(value or ""):lower()
end

local function compact(value)
	return tostring(value or ""):gsub("%s+", " ")
end

local function pathOf(object)
	local parts = {}
	local current = object
	while current and current ~= game do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, ".")
end

local function ownerValueMatches(value)
	if typeof(value) == "Instance" then
		return value == LocalPlayer
	end
	if type(value) == "number" then
		return value == LocalPlayer.UserId
	end
	if type(value) == "string" then
		local text = lower(value)
		return text == lower(LocalPlayer.Name)
			or text == lower(LocalPlayer.DisplayName)
			or tonumber(text) == LocalPlayer.UserId
	end
	return false
end

local function hasMatchingOwnerSignal(object)
	local ok, attributes = pcall(function()
		return object:GetAttributes()
	end)
	if ok then
		for key, value in pairs(attributes) do
			if lower(key):find("owner", 1, true) and ownerValueMatches(value) then
				return true
			end
		end
	end

	local objectName = lower(object.Name)
	local parentName = object.Parent and lower(object.Parent.Name) or ""
	if not objectName:find("owner", 1, true) and not parentName:find("owner", 1, true) then
		return false
	end

	if object:IsA("ObjectValue") then
		return object.Value == LocalPlayer
	elseif object:IsA("StringValue") or object:IsA("IntValue") or object:IsA("NumberValue") then
		return ownerValueMatches(object.Value)
	elseif object:IsA("TextLabel") or object:IsA("TextButton") then
		local text = lower(object.Text)
		return text:find(lower(LocalPlayer.Name), 1, true) ~= nil
			or text:find(lower(LocalPlayer.DisplayName), 1, true) ~= nil
	end

	return false
end

local function structureScore(object)
	if not (object:IsA("Model") or object:IsA("Folder")) then
		return 0
	end
	local name = lower(object.Name)
	local score = 0
	if name:find("tycoon", 1, true) then score = score + 10 end
	if name:find("plot", 1, true) then score = score + 6 end
	if name:find("base", 1, true) then score = score + 5 end
	if name:find("factory", 1, true) then score = score + 4 end

	for _, child in ipairs(object:GetChildren()) do
		local childName = lower(child.Name)
		if childName:find("button", 1, true) or childName:find("purchase", 1, true) or childName:find("pad", 1, true) then
			score = score + 7
		end
		if childName:find("owner", 1, true) then score = score + 7 end
		if childName:find("drop", 1, true) or childName:find("collector", 1, true) then score = score + 4 end
	end
	return score
end

local function findOwnedRoot()
	local bestRoot
	local bestScore = -math.huge

	for _, object in ipairs(workspace:GetDescendants()) do
		if hasMatchingOwnerSignal(object) then
			local current = object.Parent
			local depth = 0
			while current and current ~= workspace and depth < 7 do
				if current:IsA("Model") or current:IsA("Folder") then
					local score = structureScore(current) - depth
					if score > bestScore then
						bestScore = score
						bestRoot = current
					end
				end
				current = current.Parent
				depth = depth + 1
			end
		end
	end

	return bestRoot, bestScore
end

local function interactionType(object)
	if object:IsA("ProximityPrompt") then
		return "ProximityPrompt"
	elseif object:IsA("ClickDetector") then
		return "ClickDetector"
	elseif object:IsA("TouchTransmitter") then
		return "TouchTransmitter"
	end
	return nil
end

local function findNearbyPriceText(object)
	local current = object.Parent
	for _ = 1, 4 do
		if not current then break end
		for _, descendant in ipairs(current:GetDescendants()) do
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				local text = compact(descendant.Text)
				if text:match("%d") then
					return text, pathOf(descendant)
				end
			elseif descendant:IsA("IntValue") or descendant:IsA("NumberValue") or descendant:IsA("StringValue") then
				local name = lower(descendant.Name)
				if name:find("price", 1, true) or name:find("cost", 1, true) or name:find("cash", 1, true) or name:find("money", 1, true) then
					return tostring(descendant.Value), pathOf(descendant)
				end
			end
		end
		current = current.Parent
	end
	return nil, nil
end

local root, score = findOwnedRoot()
print("[0xVyrs Probe] ===== PURCHASE PROBE =====")
print("[0xVyrs Probe] Player:", LocalPlayer.Name, "UserId:", LocalPlayer.UserId)
print("[0xVyrs Probe] Root:", root and pathOf(root) or "NOT FOUND", "score:", score)

local scanRoot = root or workspace
local counts = {
	TouchTransmitter = 0,
	ProximityPrompt = 0,
	ClickDetector = 0,
}
local samples = {}

for _, object in ipairs(scanRoot:GetDescendants()) do
	local kind = interactionType(object)
	if kind then
		counts[kind] = counts[kind] + 1
		if #samples < 40 then
			local price, pricePath = findNearbyPriceText(object)
			table.insert(samples, {
				kind = kind,
				path = pathOf(object),
				parent = object.Parent and object.Parent.Name or "?",
				grandparent = object.Parent and object.Parent.Parent and object.Parent.Parent.Name or "?",
				price = price,
				pricePath = pricePath,
			})
		end
	end
end

print(string.format(
	"[0xVyrs Probe] Interactions: touch=%d prompt=%d click=%d",
	counts.TouchTransmitter,
	counts.ProximityPrompt,
	counts.ClickDetector
))

for index, sample in ipairs(samples) do
	print(string.format(
		"[0xVyrs Probe] #%02d %s | parent=%s | grandparent=%s | price=%s | path=%s | pricePath=%s",
		index,
		sample.kind,
		sample.parent,
		sample.grandparent,
		tostring(sample.price or "none"),
		sample.path,
		tostring(sample.pricePath or "none")
	))
end

print("[0xVyrs Probe] ===== END PROBE =====")
