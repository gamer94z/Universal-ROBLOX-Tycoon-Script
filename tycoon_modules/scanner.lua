-- Performance-hardening scanner wrapper.
-- Reuses the structural scanner pinned at a known-good commit, then adds
-- generic ownership recognition for player-named plot containers.

local BASE_URL = "https://raw.githubusercontent.com/gamer94z/Universal-ROBLOX-Tycoon-Script/07768b7b71e3999b9fdd065004b278803b3dff5e/tycoon_modules/scanner.lua"

return function(context)
	local source = game:HttpGet(BASE_URL)
	local chunk = loadstring(source)
	if type(chunk) ~= "function" then
		return nil
	end

	local factory = chunk()
	if type(factory) ~= "function" then
		return nil
	end

	local base = factory(context)
	if type(base) ~= "table" or type(base.scan) ~= "function" then
		return nil
	end

	local function lower(value)
		return tostring(value or ""):lower()
	end

	local function clean(value)
		return lower(value):gsub("[^%w]", "")
	end

	local function playerNameMatches(instance)
		if not instance or not context.LOCAL_PLAYER then
			return false
		end

		local name = clean(instance.Name)
		local username = clean(context.LOCAL_PLAYER.Name)
		local displayName = clean(context.LOCAL_PLAYER.DisplayName)
		local userId = tostring(context.LOCAL_PLAYER.UserId)

		if name ~= username and name ~= displayName and name ~= userId then
			return false
		end

		local parent = instance.Parent
		local parentName = parent and lower(parent.Name) or ""
		return parentName:find("tycoon", 1, true) ~= nil
			or parentName:find("plot", 1, true) ~= nil
			or parentName:find("base", 1, true) ~= nil
			or parentName:find("player", 1, true) ~= nil
			or parentName:find("land", 1, true) ~= nil
	end

	local function rootHasPlayerOwnership(root)
		local current = root
		local depth = 0
		while current and current ~= workspace and depth <= 8 do
			if playerNameMatches(current) then
				return true
			end
			current = current.Parent
			depth = depth + 1
		end
		return false
	end

	local function applyOwnership(data, required)
		if not data then
			return data
		end

		local namedOwner = rootHasPlayerOwnership(data.root)
		local verified = data.ownerVerified == true
			or data.selectedByPosition == true
			or namedOwner
		local allowed = required == false or verified

		data.ownerMatch = verified
		data.ownerVerified = verified
		data.automationAllowed = allowed
		data.safeAutomation = allowed
		if namedOwner then
			data.ownerSource = "player-named-plot"
		end

		if data.debug then
			data.debug.ownerSource = data.ownerSource
			data.debug.playerNamedOwner = namedOwner
		end

		for _, list in ipairs({ data.buttons or {}, data.drops or {} }) do
			for _, entry in ipairs(list) do
				entry.ownerMatch = verified
				entry.ownerVerified = verified
				entry.automationAllowed = allowed
			end
		end

		return data
	end

	local function scan(scanContext)
		scanContext = scanContext or context
		local required = scanContext.CONFIG.requireOwnerMatch

		-- Allow the structural scanner to build candidate entries first. We then
		-- apply the stricter generic ownership rules above before automation can run.
		scanContext.CONFIG.requireOwnerMatch = false
		local data = base.scan(scanContext)
		scanContext.CONFIG.requireOwnerMatch = required

		return applyOwnership(data, required)
	end

	return {
		scan = scan,
		parseCompactNumber = base.parseCompactNumber,
		invalidateRoot = base.invalidateRoot,
	}
end
