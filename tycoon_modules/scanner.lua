return function()
	-- v1.1 structural scanner: names are hints, not requirements.
	local MAX_ROOT_DEPTH = 7
	local MAX_INTERACTION_PARENT_DEPTH = 5
	local MAX_PRICE_SEARCH_DEPTH = 4
	local ROOT_MIN_SCORE = 12

	local knownRoot = nil
	local knownOwnerMisses = 0

	local PRICE_NAMES = {
		cost = true, price = true, amount = true, cash = true, money = true,
		value = true, required = true, requirement = true,
	}

	local ROOT_HINTS = { "tycoon", "plot", "base", "factory", "island", "zone", "land" }
	local PURCHASE_HINTS = { "button", "buy", "purchase", "upgrade", "unlock", "build", "pad", "dropper", "conveyor" }
	local COLLECTOR_HINTS = { "collect", "collector", "cashout", "cash out", "claim cash", "income", "bank" }
	local OWNED_HINTS = { "purchased", "bought", "owned", "completed", "built" }
	local BLOCKED_PHRASES = {
		"watch ad", "watch ads", "watch video", "video ad", "video ads", "rewarded ad",
		"rewarded video", "ad reward", "advertisement", "sponsor", "invite", "discord", "twitter",
		"starterpack", "starter pack", "gamepass", "game pass", "developer product", "dev product",
		"productid", "product id", "gamepassid", "game pass id", "passid", "pass id", "assetid",
		"asset id", "premium purchase", "premium", "robux", "r$", "rbx",
	}

	local function lower(value)
		return tostring(value or ""):lower()
	end

	local function trim(value)
		return tostring(value or ""):match("^%s*(.-)%s*$") or ""
	end

	local function hasAny(value, words)
		local text = lower(value)
		for _, word in ipairs(words) do
			if text:find(word, 1, true) then return true end
		end
		return false
	end

	local function hasStandaloneToken(text, token)
		local normalized = " " .. lower(text):gsub("[^%w]+", " ") .. " "
		return normalized:find(" " .. token .. " ", 1, true) ~= nil
	end

	local function textLooksBlocked(value)
		local text = lower(value)
		for _, phrase in ipairs(BLOCKED_PHRASES) do
			if text:find(phrase, 1, true) then return true end
		end
		return hasStandaloneToken(text, "ad") or hasStandaloneToken(text, "ads") or hasStandaloneToken(text, "advert")
	end

	local function isContainer(object)
		return object and (object:IsA("Model") or object:IsA("Folder"))
	end

	local function isInteraction(object)
		return object and (object:IsA("TouchTransmitter") or object:IsA("ProximityPrompt") or object:IsA("ClickDetector"))
	end

	local function getAttributes(object)
		local ok, attributes = pcall(function() return object:GetAttributes() end)
		return ok and type(attributes) == "table" and attributes or nil
	end

	local function isPriceName(name)
		local clean = lower(name):gsub("[%s_%-]", "")
		return PRICE_NAMES[clean]
			or clean:find("cost", 1, true) ~= nil
			or clean:find("price", 1, true) ~= nil
			or clean:find("require", 1, true) ~= nil
	end

	local function parseCompactNumber(value)
		if type(value) == "number" then return value >= 0 and value or nil end
		local text = lower(value):gsub(",", ""):gsub("_", " ")
		local scientific = text:match("([%d%.]+e[%+%-]?%d+)")
		if scientific then
			local n = tonumber(scientific)
			if n and n >= 0 then return n end
		end
		local numberText, suffix = text:match("([%d]+%.?[%d]*)%s*([kmbtq])")
		if not numberText then numberText = text:match("([%d]+%.?[%d]*)") suffix = "" end
		local number = tonumber(numberText)
		if not number or number < 0 then return nil end
		local multiplier = 1
		if suffix == "k" or text:find("thousand", 1, true) then multiplier = 1e3
		elseif suffix == "m" or text:find("million", 1, true) then multiplier = 1e6
		elseif suffix == "b" or text:find("billion", 1, true) then multiplier = 1e9
		elseif suffix == "t" or text:find("trillion", 1, true) then multiplier = 1e12
		elseif suffix == "q" or text:find("quadrillion", 1, true) then multiplier = 1e15
		elseif text:find("quintillion", 1, true) then multiplier = 1e18 end
		return number * multiplier
	end

	local function hasCurrencyContext(text)
		local clean = lower(text)
		return clean:find("$", 1, true) ~= nil or clean:find("£", 1, true) ~= nil
			or clean:find("€", 1, true) ~= nil or clean:find("¥", 1, true) ~= nil
			or clean:find("cash", 1, true) ~= nil or clean:find("money", 1, true) ~= nil
			or clean:find("coin", 1, true) ~= nil or clean:find("cost", 1, true) ~= nil
			or clean:find("price", 1, true) ~= nil or clean:find("require", 1, true) ~= nil
	end

	local function directPrice(object)
		if not object then return nil end
		local attributes = getAttributes(object)
		if attributes then
			for key, value in pairs(attributes) do
				if isPriceName(key) then
					local parsed = parseCompactNumber(value)
					if parsed ~= nil then return parsed end
				end
			end
		end
		if (object:IsA("IntValue") or object:IsA("NumberValue") or object:IsA("StringValue")) and isPriceName(object.Name) then
			return parseCompactNumber(object.Value)
		end
		if object:IsA("TextLabel") or object:IsA("TextButton") then
			if hasCurrencyContext(object.Text) then return parseCompactNumber(object.Text) end
		end
		if hasCurrencyContext(object.Name) then return parseCompactNumber(object.Name) end
		return nil
	end

	local function extractPrice(object, maxDepth)
		if not object then return nil end
		local immediate = directPrice(object)
		if immediate ~= nil then return immediate end
		maxDepth = maxDepth or MAX_PRICE_SEARCH_DEPTH
		local queue = { { object = object, depth = 0 } }
		local cursor = 1
		while cursor <= #queue do
			local item = queue[cursor]
			cursor = cursor + 1
			if item.depth < maxDepth then
				for _, child in ipairs(item.object:GetChildren()) do
					local price = directPrice(child)
					if price ~= nil then return price end
					if #child:GetChildren() > 0 then table.insert(queue, { object = child, depth = item.depth + 1 }) end
				end
			end
		end
		return nil
	end

	local function nearbyPrice(interaction, stopAt)
		local current = interaction and interaction.Parent
		local depth = 0
		while current and current ~= workspace and depth <= MAX_INTERACTION_PARENT_DEPTH do
			if not textLooksBlocked(current.Name) then
				local price = extractPrice(current, math.max(1, MAX_PRICE_SEARCH_DEPTH - depth))
				if price ~= nil then return price, current, depth end
			end
			if current == stopAt then break end
			current = current.Parent
			depth = depth + 1
		end
		return nil, nil, nil
	end

	local function instanceLooksBlocked(instance)
		if not instance then return false end
		if textLooksBlocked(instance.Name) then return true end
		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			if textLooksBlocked(instance.Text) then return true end
		elseif instance:IsA("ProximityPrompt") then
			if textLooksBlocked(instance.ActionText) or textLooksBlocked(instance.ObjectText) then return true end
		end
		local attributes = getAttributes(instance)
		if attributes then
			for key, value in pairs(attributes) do
				local k = lower(key)
				if textLooksBlocked(key) or k:find("productid", 1, true) or k:find("gamepass", 1, true)
					or k:find("rewardedad", 1, true) or (type(value) == "string" and textLooksBlocked(value)) then
					return true
				end
			end
		end
		return false
	end

	local function blockedAround(object, stopAt)
		local current = object
		local depth = 0
		while current and current ~= workspace and depth <= 4 do
			if instanceLooksBlocked(current) then return true end
			if current == stopAt then break end
			current = current.Parent
			depth = depth + 1
		end
		return false
	end

	local function partHasTouchInterest(part)
		if not part or not part:IsA("BasePart") then return false end
		for _, child in ipairs(part:GetChildren()) do if child:IsA("TouchTransmitter") then return true end end
		return false
	end

	local function getTouchPart(object)
		if not object then return nil end
		if object:IsA("BasePart") and partHasTouchInterest(object) then return object end
		if object:IsA("TouchTransmitter") and object.Parent and object.Parent:IsA("BasePart") then return object.Parent end
		if object:IsA("Model") and object.PrimaryPart and partHasTouchInterest(object.PrimaryPart) then return object.PrimaryPart end
		for _, descendant in ipairs(object:GetDescendants()) do
			if descendant:IsA("BasePart") and partHasTouchInterest(descendant) then return descendant end
		end
		return nil
	end

	local function getPrompt(object)
		if not object then return nil end
		if object:IsA("ProximityPrompt") then return object end
		return object:FindFirstChildWhichIsA("ProximityPrompt", true)
	end

	local function getClickDetector(object)
		if not object then return nil end
		if object:IsA("ClickDetector") then return object end
		return object:FindFirstChildWhichIsA("ClickDetector", true)
	end

	local function getInteraction(object)
		return getTouchPart(object), getPrompt(object), getClickDetector(object)
	end

	local function getReferencePart(object)
		if not object then return nil end
		local touch = getTouchPart(object)
		if touch then return touch end
		if object:IsA("BasePart") then return object end
		if object:IsA("ProximityPrompt") or object:IsA("ClickDetector") then
			local p = object.Parent
			if p and p:IsA("BasePart") then return p end
		end
		if object:IsA("Model") and object.PrimaryPart then return object.PrimaryPart end
		return object:FindFirstChildWhichIsA("BasePart", true)
	end

	local function ownerValueMatches(context, value)
		if typeof(value) == "Instance" then return value == context.LOCAL_PLAYER end
		if type(value) == "number" then return tonumber(value) == context.LOCAL_PLAYER.UserId end
		if type(value) == "string" then
			local clean = lower(trim(value))
			return clean == lower(context.LOCAL_PLAYER.Name) or clean == lower(context.LOCAL_PLAYER.DisplayName)
				or tonumber(clean) == context.LOCAL_PLAYER.UserId
		end
		return false
	end

	local function ownerSignalMatches(context, object)
		local attributes = getAttributes(object)
		if attributes then
			for key, value in pairs(attributes) do
				local k = lower(key)
				if (k:find("owner", 1, true) or k:find("player", 1, true) or k:find("userid", 1, true))
					and ownerValueMatches(context, value) then return true end
			end
		end
		local name = lower(object.Name)
		local parentName = object.Parent and lower(object.Parent.Name) or ""
		local labelled = name:find("owner", 1, true) or parentName:find("owner", 1, true)
			or name == "player" or parentName == "player" or name:find("userid", 1, true)
		if object:IsA("ObjectValue") then
			return labelled and object.Value == context.LOCAL_PLAYER
		elseif object:IsA("StringValue") or object:IsA("IntValue") or object:IsA("NumberValue") then
			return labelled and ownerValueMatches(context, object.Value)
		elseif object:IsA("TextLabel") or object:IsA("TextButton") then
			local text = lower(object.Text)
			return text:find(lower(context.LOCAL_PLAYER.Name), 1, true) ~= nil
				or text:find(lower(context.LOCAL_PLAYER.DisplayName), 1, true) ~= nil
		end
		return false
	end

	local function getRootBounds(root)
		if root:IsA("Model") then
			local ok, cframe, size = pcall(function() return root:GetBoundingBox() end)
			if ok and cframe and size then return { cframe = cframe, size = size } end
		end
		local minX, minY, minZ = math.huge, math.huge, math.huge
		local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
		local found = false
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("BasePart") then
				found = true
				local p, h = descendant.Position, descendant.Size * 0.5
				minX, minY, minZ = math.min(minX, p.X-h.X), math.min(minY, p.Y-h.Y), math.min(minZ, p.Z-h.Z)
				maxX, maxY, maxZ = math.max(maxX, p.X+h.X), math.max(maxY, p.Y+h.Y), math.max(maxZ, p.Z+h.Z)
			end
		end
		if found then return { minX=minX, minY=minY, minZ=minZ, maxX=maxX, maxY=maxY, maxZ=maxZ } end
		return nil
	end

	local function localPlayerInsideRoot(context, root, padding)
		local localRoot = context.getLocalRoot and context.getLocalRoot()
		if not localRoot or not root then return false end
		local bounds = getRootBounds(root)
		if not bounds then return false end
		padding = padding or 28
		if bounds.cframe and bounds.size then
			local p = bounds.cframe:PointToObjectSpace(localRoot.Position)
			return math.abs(p.X) <= bounds.size.X*0.5 + padding
				and math.abs(p.Y) <= bounds.size.Y*0.5 + padding
				and math.abs(p.Z) <= bounds.size.Z*0.5 + padding
		end
		local p = localRoot.Position
		return p.X >= bounds.minX-padding and p.X <= bounds.maxX+padding
			and p.Y >= bounds.minY-padding and p.Y <= bounds.maxY+padding
			and p.Z >= bounds.minZ-padding and p.Z <= bounds.maxZ+padding
	end

	local function directChildUnder(object, ancestor)
		local current = object
		local previous = object
		while current and current ~= ancestor do
			previous = current
			current = current.Parent
		end
		return current == ancestor and previous or nil
	end

	local function collectWorldEvidence(context)
		local descendants = workspace:GetDescendants()
		local interactions = {}
		local ownerSignals = {}
		for _, object in ipairs(descendants) do
			if isInteraction(object) then table.insert(interactions, object) end
			if ownerSignalMatches(context, object) then table.insert(ownerSignals, object) end
		end
		return descendants, interactions, ownerSignals
	end

	local function rootDepth(root)
		local depth = 0
		local current = root
		while current and current ~= workspace do depth = depth + 1 current = current.Parent end
		return depth
	end

	local function buildRootCandidates(context, interactions, ownerSignals)
		local stats = {}
		local function statFor(root)
			local s = stats[root]
			if not s then
				s = { root=root, interactions=0, priced=0, blocked=0, touch=0, prompt=0, click=0, families={}, ownerVerified=false }
				stats[root] = s
			end
			return s
		end

		for _, interaction in ipairs(interactions) do
			local price = nearbyPrice(interaction)
			local blocked = blockedAround(interaction)
			local current = interaction.Parent
			local depth = 0
			while current and current ~= workspace and depth < MAX_ROOT_DEPTH do
				if isContainer(current) then
					local s = statFor(current)
					s.interactions = s.interactions + 1
					if price ~= nil then s.priced = s.priced + 1 end
					if blocked then s.blocked = s.blocked + 1 end
					if interaction:IsA("TouchTransmitter") then s.touch = s.touch + 1
					elseif interaction:IsA("ProximityPrompt") then s.prompt = s.prompt + 1
					else s.click = s.click + 1 end
					local family = directChildUnder(interaction, current)
					if family then s.families[family] = (s.families[family] or 0) + 1 end
				end
				current = current.Parent
				depth = depth + 1
			end
		end

		for _, signal in ipairs(ownerSignals) do
			local current = signal
			local depth = 0
			while current and current ~= workspace and depth < MAX_ROOT_DEPTH + 2 do
				if stats[current] then stats[current].ownerVerified = true end
				current = current.Parent
				depth = depth + 1
			end
		end

		local candidates = {}
		for root, s in pairs(stats) do
			local familyCount, maxFamily = 0, 0
			for _, count in pairs(s.families) do familyCount = familyCount + 1 maxFamily = math.max(maxFamily, count) end
			local usablePriced = math.max(0, s.priced - s.blocked)
			local nameBonus = hasAny(root.Name, ROOT_HINTS) and 8 or 0
			local interactionBonus = math.min(12, s.interactions * 0.8)
			local priceBonus = math.min(20, usablePriced * 3)
			local familyBonus = math.min(12, maxFamily * 1.5)
			local mixedBonus = ((s.touch > 0 and s.prompt > 0) or (s.touch > 0 and s.click > 0)) and 2 or 0
			local blockedPenalty = math.min(15, s.blocked * 1.5)
			local depthPenalty = math.max(0, 2 - rootDepth(root)) * 8
			local inside = localPlayerInsideRoot(context, root, 30)
			local score = nameBonus + interactionBonus + priceBonus + familyBonus + mixedBonus - blockedPenalty - depthPenalty
				+ (s.ownerVerified and 1000 or 0) + (inside and 30 or 0)
			if score >= ROOT_MIN_SCORE and s.interactions >= 1 then
				table.insert(candidates, {
					root=root, rawScore=score, structuralScore=score - (s.ownerVerified and 1000 or 0) - (inside and 30 or 0),
					ownerVerified=s.ownerVerified, inside=inside, interactions=s.interactions,
					priced=usablePriced, blocked=s.blocked, familyCount=familyCount, maxFamily=maxFamily,
				})
			end
		end

		-- Generic spatial ownership inference: only when one strong sibling plot contains the player.
		local parentGroups = {}
		for _, c in ipairs(candidates) do
			local parent = c.root.Parent
			if parent and parent ~= workspace then
				parentGroups[parent] = parentGroups[parent] or {}
				table.insert(parentGroups[parent], c)
			end
		end
		for _, group in pairs(parentGroups) do
			if #group >= 2 then
				local insideCount, insideCandidate = 0, nil
				for _, c in ipairs(group) do
					if c.inside and c.structuralScore >= 12 and c.priced >= 1 then insideCount = insideCount + 1 insideCandidate = c end
				end
				if insideCount == 1 and not insideCandidate.ownerVerified then
					insideCandidate.spatialOwner = true
					insideCandidate.score = insideCandidate.score + 220
				end
			end
		end

		table.sort(candidates, function(a,b)
			if a.ownerVerified ~= b.ownerVerified then return a.ownerVerified end
			if (a.spatialOwner == true) ~= (b.spatialOwner == true) then return a.spatialOwner == true end
			if a.score ~= b.score then return a.score > b.score end
			return rootDepth(a.root) > rootDepth(b.root)
		end)
		return candidates
	end

	local function candidateHost(interaction, root)
		local current = interaction.Parent
		local depth = 0
		local best, bestPrice, bestDepth
		while current and current ~= workspace and depth <= MAX_INTERACTION_PARENT_DEPTH do
			if current == root.Parent then break end
			if (current:IsA("Model") or current:IsA("BasePart")) and not blockedAround(current, root) then
				local price = extractPrice(current, math.max(1, 3-depth))
				if price ~= nil then
					best, bestPrice, bestDepth = current, price, depth
					break
				end
			end
			if current == root then break end
			current = current.Parent
			depth = depth + 1
		end
		return best, bestPrice, bestDepth
	end

	local function nameFromCandidate(candidate, interaction)
		local options = { candidate and candidate.Name, interaction and interaction.Name }
		if interaction and interaction:IsA("ProximityPrompt") then
			table.insert(options, interaction.ObjectText)
			table.insert(options, interaction.ActionText)
		end
		if candidate then
			for _, child in ipairs(candidate:GetDescendants()) do
				if child:IsA("TextLabel") and child.Visible and not hasCurrencyContext(child.Text) and #trim(child.Text) >= 2 then
					table.insert(options, child.Text)
					if #options >= 6 then break end
				end
			end
		end
		for _, value in ipairs(options) do
			local text = trim(value)
			if text ~= "" and not textLooksBlocked(text) then return text end
		end
		return "Purchase"
	end

	local function makeButtonEntry(data, context, candidate, interaction, price)
		local touchPart, prompt, clickDetector = getInteraction(candidate)
		if interaction:IsA("TouchTransmitter") and interaction.Parent and interaction.Parent:IsA("BasePart") then touchPart = interaction.Parent end
		if interaction:IsA("ProximityPrompt") then prompt = interaction end
		if interaction:IsA("ClickDetector") then clickDetector = interaction end
		if not touchPart and not prompt and not clickDetector then return nil end
		local cash = tonumber(context.getCash()) or 0
		return {
			object=candidate, part=getReferencePart(candidate) or getReferencePart(interaction), touchPart=touchPart,
			prompt=prompt, clickDetector=clickDetector, price=price, affordable=price <= cash, locked=price > cash,
			paidPurchase=false, ownerMatch=data.ownerMatch, ownerVerified=data.ownerVerified,
			automationAllowed=data.automationAllowed, root=data.root, name=nameFromCandidate(candidate, interaction),
		}
	end

	local function isOwnedArea(candidate, root)
		local current = candidate and candidate.Parent
		while current and current ~= root and current ~= workspace do
			if hasAny(current.Name, OWNED_HINTS) then return true end
			current = current.Parent
		end
		return false
	end

	local function collectCandidates(root, descendants, data, context)
		local seenObjects = {}
		local interactionRecords = {}
		for _, interaction in ipairs(descendants) do
			if isInteraction(interaction) then
				local host, price, depth = candidateHost(interaction, root)
				local blocked = blockedAround(interaction, root)
				if host and price ~= nil and not blocked and not isOwnedArea(host, root) then
					table.insert(interactionRecords, { interaction=interaction, host=host, price=price, depth=depth or 0 })
				elseif blocked then
					data.paidSkipped = data.paidSkipped + 1
				end
			end
		end

		-- Prefer repeated sibling structures; this is the strongest generic sign of tycoon purchase pads.
		local familyCounts = {}
		for _, record in ipairs(interactionRecords) do
			local key = record.host.Parent or root
			familyCounts[key] = (familyCounts[key] or 0) + 1
		end
		table.sort(interactionRecords, function(a,b)
			local af, bf = familyCounts[a.host.Parent or root] or 0, familyCounts[b.host.Parent or root] or 0
			if af ~= bf then return af > bf end
			if a.depth ~= b.depth then return a.depth < b.depth end
			return a.price < b.price
		end)

		for _, record in ipairs(interactionRecords) do
			if #data.buttons >= context.CONFIG.maxButtons then break end
			if not seenObjects[record.host] then
				local familySize = familyCounts[record.host.Parent or root] or 1
				local hinted = hasAny(record.host.Name, PURCHASE_HINTS) or hasAny(record.host.Parent and record.host.Parent.Name or "", PURCHASE_HINTS)
				-- A lone unhinted priced interaction is suspicious; repeated structures are accepted generically.
				if familySize >= 2 or hinted or record.price == 0 then
					local entry = makeButtonEntry(data, context, record.host, record.interaction, record.price)
					if entry then
						seenObjects[record.host] = true
						entry.familySize = familySize
						table.insert(data.buttons, entry)
					end
				end
			end
		end

		-- Collectors are deliberately conservative: cash/collector semantics OR a non-priced touch pad
		-- sharing the same structural root as several purchase pads.
		local seenActivation = {}
		local purchaseParents = {}
		for _, button in ipairs(data.buttons) do if button.object and button.object.Parent then purchaseParents[button.object.Parent] = true end end
		for _, candidate in ipairs(descendants) do
			if #data.drops >= context.CONFIG.maxDrops then break end
			local semantic = hasAny(candidate.Name, COLLECTOR_HINTS)
			if candidate:IsA("TextLabel") or candidate:IsA("TextButton") then semantic = semantic or hasAny(candidate.Text, COLLECTOR_HINTS) end
			if semantic and not blockedAround(candidate, root) then
				local touchPart, prompt, clickDetector = getInteraction(candidate)
				local activation = touchPart or prompt or clickDetector
				if activation and not seenActivation[activation] then
					seenActivation[activation] = true
					table.insert(data.drops, {
						object=candidate, part=getReferencePart(candidate), touchPart=touchPart, prompt=prompt, clickDetector=clickDetector,
						ownerMatch=data.ownerMatch, ownerVerified=data.ownerVerified, automationAllowed=data.automationAllowed,
						root=data.root, name=candidate.Name,
					})
				end
			end
		end
	end

	local function finaliseData(data)
		local affordable, locked = 0, 0
		for _, button in ipairs(data.buttons) do
			if button.affordable then affordable = affordable + 1 elseif button.locked then locked = locked + 1 end
		end
		table.sort(data.buttons, function(a,b)
			if a.affordable ~= b.affordable then return a.affordable end
			if (a.familySize or 0) ~= (b.familySize or 0) then return (a.familySize or 0) > (b.familySize or 0) end
			return (a.price or math.huge) < (b.price or math.huge)
		end)
		data.affordableCount, data.lockedCount, data.totalButtons = affordable, locked, #data.buttons
		data.progressPercent = 0
		data.debug = {
			scanMode=data.scanMode, scanTimeMs=data.scanTimeMs, rootScore=data.rootScore,
			structuralScore=data.structuralScore, ownerSource=data.ownerSource,
			rootInteractions=data.rootInteractions, rootPriced=data.rootPriced,
			rootFamily=data.rootFamily, paidSkipped=data.paidSkipped,
		}
		return data
	end

	local function scanRoot(context, root, rootMeta, scanMode)
		local started = os.clock()
		local descendants = root:GetDescendants()
		local explicitOwner = false
		for _, object in ipairs(descendants) do if ownerSignalMatches(context, object) then explicitOwner = true break end end
		if not explicitOwner and ownerSignalMatches(context, root) then explicitOwner = true end
		local spatialOwner = rootMeta and rootMeta.spatialOwner == true
		local ownerVerified = explicitOwner or spatialOwner
		local ownerSource = explicitOwner and "owner" or (spatialOwner and "position-cluster" or "structure")
		local automationAllowed = ownerVerified or context.CONFIG.requireOwnerMatch == false
		local score = rootMeta and rootMeta.rawScore or 0
		local data = {
			root=root, rootName=root.Name, confidence=math.clamp(score, 0, 100), rootScore=score,
			structuralScore=rootMeta and rootMeta.structuralScore or score,
			ownerMatch=ownerVerified, ownerVerified=ownerVerified, ownerSource=ownerSource,
			selectedByPosition=spatialOwner, automationAllowed=automationAllowed, safeAutomation=automationAllowed,
			buttons={}, drops={}, cash=tonumber(context.getCash()) or 0, owned=ownerVerified,
			maxLabels=context.CONFIG.maxLabels or 16, paidSkipped=0, scanMode=scanMode or "root",
			rootInteractions=rootMeta and rootMeta.interactions or 0, rootPriced=rootMeta and rootMeta.priced or 0,
			rootFamily=rootMeta and rootMeta.maxFamily or 0,
		}
		if context.CONFIG.requireOwnerMatch and not ownerVerified then
			data.scanTimeMs=(os.clock()-started)*1000
			data.affordableCount,data.lockedCount,data.totalButtons,data.progressPercent=0,0,0,0
			data.debug={ scanMode=data.scanMode, scanTimeMs=data.scanTimeMs, reason="owner-unverified", rootScore=score }
			return data
		end
		collectCandidates(root, descendants, data, context)
		data.scanTimeMs=(os.clock()-started)*1000
		return finaliseData(data)
	end

	local function emptyData(context, elapsed, reason)
		return {
			root=workspace, rootName="Workspace", confidence=0, rootScore=0, structuralScore=0,
			ownerMatch=false, ownerVerified=false, ownerSource="none",
			automationAllowed=context.CONFIG.requireOwnerMatch == false, safeAutomation=context.CONFIG.requireOwnerMatch == false,
			buttons={}, drops={}, cash=tonumber(context.getCash()) or 0, owned=false,
			maxLabels=context.CONFIG.maxLabels or 16, paidSkipped=0, affordableCount=0, lockedCount=0,
			totalButtons=0, progressPercent=0, scanMode="structural-discovery", scanTimeMs=elapsed,
			debug={ scanMode="structural-discovery", scanTimeMs=elapsed, reason=reason or "no-root" },
		}
	end

	local function fullScan(context)
		local started = os.clock()
		local _, interactions, ownerSignals = collectWorldEvidence(context)
		local roots = buildRootCandidates(context, interactions, ownerSignals)
		local selected = roots[1]
		if not selected then
			knownRoot=nil knownOwnerMisses=0
			return emptyData(context, (os.clock()-started)*1000, "no-structural-root")
		end
		knownRoot=selected.root knownOwnerMisses=0
		return scanRoot(context, selected.root, selected, "structural-discovery")
	end

	local function scan(context)
		if knownRoot and knownRoot.Parent then
			-- Rebuild lightweight metadata for cached roots so spatial ownership does not disappear.
			local inside = localPlayerInsideRoot(context, knownRoot, 30)
			local meta = { root=knownRoot, rawScore=40, structuralScore=40, spatialOwner=inside, interactions=0, priced=0, maxFamily=0 }
			local data = scanRoot(context, knownRoot, meta, "cached-root")
			if data.ownerVerified or context.CONFIG.requireOwnerMatch == false then knownOwnerMisses=0 return data end
			knownOwnerMisses=knownOwnerMisses+1
			if knownOwnerMisses < 2 then return data end
			knownRoot=nil knownOwnerMisses=0
		end
		return fullScan(context)
	end

	local function invalidateRoot(root)
		if not root or root == knownRoot then knownRoot=nil knownOwnerMisses=0 end
	end

	return {
		scan=scan,
		parseCompactNumber=parseCompactNumber,
		invalidateRoot=invalidateRoot,
	}
end