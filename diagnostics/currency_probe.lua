-- 0xVyrs Tycoon generic currency probe
-- Read-only diagnostic: inspects local PlayerGui / Player value objects and reports numeric candidates.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
if not player then
	warn("[0xVyrs Currency Probe] LocalPlayer unavailable")
	return
end

local function lower(v)
	return tostring(v or ""):lower()
end

local function parseNumber(text)
	text = lower(text):gsub(",", ""):gsub("_", " ")
	local n, suffix = text:match("([%d]+%.?[%d]*)%s*([kmbtq])")
	if not n then n = text:match("([%d]+%.?[%d]*)"); suffix = "" end
	n = tonumber(n)
	if not n then return nil end
	local mult = 1
	if suffix == "k" then mult = 1e3
	elseif suffix == "m" then mult = 1e6
	elseif suffix == "b" then mult = 1e9
	elseif suffix == "t" then mult = 1e12
	elseif suffix == "q" then mult = 1e15 end
	return n * mult
end

local function contextPath(object)
	local pieces = {}
	local current = object
	local depth = 0
	while current and depth < 7 do
		table.insert(pieces, 1, current.Name)
		current = current.Parent
		depth = depth + 1
	end
	return table.concat(pieces, ".")
end

local candidates = {}
local gui = player:FindFirstChildOfClass("PlayerGui")
if gui then
	for _, object in ipairs(gui:GetDescendants()) do
		if object:IsA("TextLabel") or object:IsA("TextButton") then
			local text = tostring(object.Text or "")
			local value = parseNumber(text)
			if value ~= nil then
				local visible = object.Visible
				local okAbs, absPos, absSize = pcall(function()
					return object.AbsolutePosition, object.AbsoluteSize
				end)
				local colour = object.TextColor3
				table.insert(candidates, {
					object = object,
					kind = "GUI",
					value = value,
					text = text,
					visible = visible,
					path = object:GetFullName(),
					context = contextPath(object),
					pos = okAbs and string.format("%.0f,%.0f", absPos.X, absPos.Y) or "?",
					size = okAbs and string.format("%.0fx%.0f", absSize.X, absSize.Y) or "?",
					colour = string.format("%.2f,%.2f,%.2f", colour.R, colour.G, colour.B),
					last = value,
				})
			end
		end
	end
end

for _, object in ipairs(player:GetDescendants()) do
	if object:IsA("IntValue") or object:IsA("NumberValue") or object:IsA("StringValue") then
		local ok, raw = pcall(function() return object.Value end)
		local value = ok and tonumber(raw) or nil
		if value ~= nil then
			table.insert(candidates, {
				object = object,
				kind = "VALUE",
				value = value,
				text = tostring(raw),
				visible = true,
				path = object:GetFullName(),
				context = contextPath(object),
				pos = "-",
				size = "-",
				colour = "-",
				last = value,
			})
		end
	end
end

local function score(c)
	local s = 0
	local hay = lower(c.path .. " " .. c.context .. " " .. c.text)
	if hay:find("cash",1,true) or hay:find("money",1,true) or hay:find("balance",1,true) or hay:find("wallet",1,true) then s = s + 100 end
	if hay:find("coin",1,true) or hay:find("credit",1,true) or hay:find("fund",1,true) then s = s + 45 end
	if c.kind == "GUI" and c.visible then s = s + 12 end
	if c.kind == "GUI" and (c.text:find("$",1,true) or c.text:find("£",1,true)) then s = s + 35 end
	if hay:find("/s",1,true) or hay:find("rate",1,true) or hay:find("income",1,true) then s = s - 120 end
	if hay:find("ammo",1,true) or hay:find("health",1,true) or hay:find("level",1,true) or hay:find("xp",1,true) then s = s - 80 end
	if hay:find("gem",1,true) or hay:find("diamond",1,true) or hay:find("crystal",1,true) then s = s - 70 end
	return s
end

for _, c in ipairs(candidates) do c.score = score(c) end
table.sort(candidates, function(a,b)
	if a.score ~= b.score then return a.score > b.score end
	return a.value > b.value
end)

print("[0xVyrs Currency Probe] ===== INITIAL CANDIDATES =====")
print("[0xVyrs Currency Probe] total=" .. tostring(#candidates))
for i = 1, math.min(35, #candidates) do
	local c = candidates[i]
	print(string.format("[0xVyrs Currency Probe] #%02d %s score=%d value=%s text=%q visible=%s pos=%s size=%s colour=%s path=%s",
		i, c.kind, c.score, tostring(c.value), c.text, tostring(c.visible), c.pos, c.size, c.colour, c.path))
end

print("[0xVyrs Currency Probe] observing changes for 12 seconds...")
local changed = {}
local start = os.clock()
while os.clock() - start < 12 do
	if task and task.wait then task.wait(0.5) else wait(0.5) end
	for _, c in ipairs(candidates) do
		if c.object and c.object.Parent then
			local current
			if c.kind == "GUI" then
				current = parseNumber(c.object.Text)
			else
				local ok, raw = pcall(function() return c.object.Value end)
				current = ok and tonumber(raw) or nil
			end
			if current ~= nil and current ~= c.last then
				changed[c] = (changed[c] or 0) + 1
				print(string.format("[0xVyrs Currency Probe] CHANGE %s %s -> %s path=%s",
					c.kind, tostring(c.last), tostring(current), c.path))
				c.last = current
			end
		end
	end
end

print("[0xVyrs Currency Probe] ===== CHANGED CANDIDATES =====")
local changedList = {}
for c, count in pairs(changed) do table.insert(changedList, { c=c, count=count }) end
table.sort(changedList, function(a,b)
	if a.count ~= b.count then return a.count > b.count end
	return a.c.score > b.c.score
end)
if #changedList == 0 then
	print("[0xVyrs Currency Probe] no numeric candidate changed during observation")
else
	for i = 1, math.min(20, #changedList) do
		local item = changedList[i]
		print(string.format("[0xVyrs Currency Probe] #%02d changes=%d kind=%s score=%d final=%s path=%s",
			i, item.count, item.c.kind, item.c.score, tostring(item.c.last), item.c.path))
	end
end
print("[0xVyrs Currency Probe] done")