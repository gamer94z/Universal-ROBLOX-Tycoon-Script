-- 0xVyrs universal tycoon currency resolver.
-- Read-only: observes local replicated values/UI and learns which one behaves like spendable cash.

return function(context)
    context = context or {}
    local player = context.LOCAL_PLAYER or game:GetService("Players").LocalPlayer
    local playerGui = player and player:FindFirstChildOfClass("PlayerGui")

    local candidates = {}
    local selected
    local lastDiscovery = -math.huge
    local lastRefresh = -math.huge
    local DISCOVERY_COOLDOWN = 8
    local REFRESH_INTERVAL = 0.18
    local MAX_CANDIDATES = 180
    local pendingEvents = {}
    local lastPrinted

    local function lower(v) return tostring(v or ""):lower() end
    local function compact(v) return lower(v):gsub("[^%w]", "") end
    local function hasAny(text, words)
        text = lower(text)
        for _, word in ipairs(words) do
            if text:find(word, 1, true) then return true end
        end
        return false
    end

    local RATE_WORDS = { "/s", "/sec", "per sec", "per second", "income", "rate", "cps", "rpm" }
    local PRICE_WORDS = { "price", "cost", "purchase", "buybutton", "purchasebutton", "shop", "store", "gamepass", "robux", "rebirthprice", "cashboost" }
    local BAD_WORDS = { "ammo", "health", "level", "experience", "xp", "serverstats", "ping", "fps", "timer", "countdown" }
    local CASH_WORDS = { "cash", "money", "balance", "wallet", "fund", "coin", "credit", "currency", "gold" }

    local function parseNumber(v)
        if type(v) == "number" then return v >= 0 and v or nil end
        local text = lower(v):gsub(",", ""):gsub("_", " ")
        if hasAny(text, RATE_WORDS) or text:find("%%", 1, true) then return nil end
        local sci = text:match("([%d%.]+e[%+%-]?%d+)")
        if sci then
            local n = tonumber(sci)
            if n and n >= 0 then return n end
        end
        local ntext, suffix = text:match("([%d]+%.?[%d]*)%s*([kmbtq])")
        if not ntext then ntext = text:match("([%d]+%.?[%d]*)"); suffix = "" end
        local n = tonumber(ntext)
        if not n or n < 0 then return nil end
        local mult = ({ k=1e3, m=1e6, b=1e9, t=1e12, q=1e15 })[suffix] or 1
        return n * mult
    end

    local function pathText(object, depth)
        local pieces = {}
        local current = object
        local count = 0
        while current and count < (depth or 8) do
            table.insert(pieces, 1, tostring(current.Name or ""))
            current = current.Parent
            count = count + 1
        end
        return lower(table.concat(pieces, "."))
    end

    local function rowFor(object)
        local current = object and object.Parent
        local previous = object
        local depth = 0
        while current and current ~= playerGui and depth < 12 do
            if current:IsA("ScrollingFrame") then return previous end
            local parentName = current.Parent and lower(current.Parent.Name) or ""
            if parentName:find("scroll",1,true) or parentName:find("playerlist",1,true) or parentName:find("leaderboard",1,true) then
                return current
            end
            previous = current
            current = current.Parent
            depth = depth + 1
        end
        return nil
    end

    local function localIdentityScore(row)
        if not row or not player then return 0 end
        local username = compact(player.Name)
        local display = compact(player.DisplayName)
        local userId = tostring(player.UserId)
        local best = 0

        local function scoreText(v)
            local c = compact(v)
            if c == "" then return 0 end
            if c == username then return 700 end
            if display ~= "" and c == display then return 620 end
            if c == userId then return 720 end
            if #username >= 4 and c:find(username,1,true) then return 440 end
            if display ~= "" and #display >= 4 and c:find(display,1,true) then return 360 end
            return 0
        end

        local nodes = { row }
        local ok, descendants = pcall(function() return row:GetDescendants() end)
        if ok and type(descendants) == "table" then
            for _, node in ipairs(descendants) do table.insert(nodes, node) end
        end
        for _, node in ipairs(nodes) do
            best = math.max(best, scoreText(node.Name))
            if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
                best = math.max(best, scoreText(node.Text))
            elseif node:IsA("ImageLabel") or node:IsA("ImageButton") then
                local image = tostring(node.Image or "")
                if image:find(userId,1,true) then best = math.max(best, 700) end
            elseif node:IsA("ObjectValue") and node.Value == player then
                best = math.max(best, 720)
            elseif node:IsA("StringValue") or node:IsA("IntValue") or node:IsA("NumberValue") then
                local okValue, value = pcall(function() return node.Value end)
                if okValue then best = math.max(best, scoreText(value)) end
            end
            local okAttrs, attrs = pcall(function() return node:GetAttributes() end)
            if okAttrs and type(attrs) == "table" then
                for key, value in pairs(attrs) do
                    local k = lower(key)
                    if k:find("user",1,true) or k:find("player",1,true) or k:find("owner",1,true) or k:find("name",1,true) then
                        best = math.max(best, scoreText(value))
                    end
                end
            end
            if best >= 700 then break end
        end
        return best
    end

    local function visible(object)
        local current = object
        local depth = 0
        while current and depth < 10 do
            if current:IsA("GuiObject") and current.Visible == false then return false end
            if current:IsA("LayerCollector") and current.Enabled == false then return false end
            current = current.Parent
            depth = depth + 1
        end
        return true
    end

    local function readCandidate(c)
        if not c or not c.object or not c.object.Parent then return nil end
        if c.kind == "gui" then
            local ok, text = pcall(function() return c.object.Text end)
            return ok and parseNumber(text) or nil
        elseif c.kind == "value" then
            local ok, value = pcall(function() return c.object.Value end)
            return ok and parseNumber(value) or nil
        elseif c.kind == "attribute" then
            local ok, value = pcall(function() return c.object:GetAttribute(c.key) end)
            return ok and parseNumber(value) or nil
        end
        return nil
    end

    local function addCandidate(kind, object, key, score, source, rowScore)
        local c = {
            kind = kind, object = object, key = key,
            staticScore = score or 0, source = source or "unknown", rowScore = rowScore or 0,
            correlation = 0, changes = 0, last = nil, lastChange = -math.huge,
        }
        c.last = readCandidate(c)
        if c.last ~= nil then table.insert(candidates, c) end
    end

    local function discover()
        if not player then return end
        candidates = {}
        selected = nil
        playerGui = player:FindFirstChildOfClass("PlayerGui")

        local playerNodes = { player }
        local okPlayer, playerDesc = pcall(function() return player:GetDescendants() end)
        if okPlayer and type(playerDesc) == "table" then
            for _, node in ipairs(playerDesc) do table.insert(playerNodes, node) end
        end
        for _, node in ipairs(playerNodes) do
            if node:IsA("IntValue") or node:IsA("NumberValue") or node:IsA("StringValue") then
                local path = pathText(node, 7)
                local name = lower(node.Name)
                if hasAny(name, CASH_WORDS) or hasAny(path, CASH_WORDS) then
                    local score = hasAny(name, {"cash","money","balance","wallet"}) and 300 or 180
                    if lower(node.Parent and node.Parent.Name) == "leaderstats" then score = score + 120 end
                    if not hasAny(path, BAD_WORDS) then addCandidate("value", node, nil, score, "player-data", 0) end
                end
            end
            local okAttrs, attrs = pcall(function() return node:GetAttributes() end)
            if okAttrs and type(attrs) == "table" then
                for key, value in pairs(attrs) do
                    if parseNumber(value) ~= nil and hasAny(key, CASH_WORDS) then
                        addCandidate("attribute", node, key, 260, "attribute", 0)
                    end
                end
            end
        end

        if playerGui then
            local okGui, guiDesc = pcall(function() return playerGui:GetDescendants() end)
            if okGui and type(guiDesc) == "table" then
                for _, object in ipairs(guiDesc) do
                    if (object:IsA("TextLabel") or object:IsA("TextButton")) and visible(object) then
                        local text = tostring(object.Text or "")
                        local value = parseNumber(text)
                        if value ~= nil then
                            local path = pathText(object, 10)
                            local name = lower(object.Name)
                            local playerList = path:find("playerlist",1,true) or path:find("leaderboard",1,true)
                            local symbol = text:find("$",1,true) or text:find("£",1,true) or text:find("€",1,true) or text:find("¥",1,true)
                            local cashish = hasAny(name, CASH_WORDS) or hasAny(path, CASH_WORDS) or symbol
                            if cashish and not hasAny(lower(text), RATE_WORDS) and not hasAny(path, BAD_WORDS) then
                                local priceLike = hasAny(path, PRICE_WORDS)
                                if not priceLike or playerList then
                                    local score = 0
                                    if hasAny(name, {"cash","money","balance","wallet"}) then score = score + 240 end
                                    if symbol then score = score + 90 end
                                    if hasAny(path, {"cash","money","balance","wallet"}) then score = score + 100 end
                                    local rowScore = 0
                                    if playerList then
                                        local row = rowFor(object)
                                        rowScore = localIdentityScore(row)
                                        score = score + 50 + rowScore
                                    end
                                    addCandidate("gui", object, nil, score, playerList and "player-list" or "hud", rowScore)
                                end
                            end
                        end
                    end
                end
            end
        end

        table.sort(candidates, function(a,b)
            if a.staticScore ~= b.staticScore then return a.staticScore > b.staticScore end
            return (a.last or 0) > (b.last or 0)
        end)
        while #candidates > MAX_CANDIDATES do table.remove(candidates) end
        lastDiscovery = os.clock()
    end

    local function chooseSource()
        local best, bestRank
        for _, c in ipairs(candidates) do
            local value = readCandidate(c)
            if value ~= nil then
                local rank = c.staticScore + c.correlation * 90
                if c.rowScore >= 400 then rank = rank + 800 end
                if value == 0 and c.correlation <= 0 and c.rowScore < 400 then rank = rank - 140 end
                if not bestRank or rank > bestRank then best, bestRank = c, rank end
            end
        end
        if best then
            if best.rowScore >= 400 or best.correlation >= 6 or best.staticScore >= 420 then
                selected = best
            elseif not selected and best.kind ~= "gui" and best.staticScore >= 300 then
                selected = best
            end
        end
    end

    local function evaluateEvents(now)
        for index = #pendingEvents, 1, -1 do
            local event = pendingEvents[index]
            if now - event.at >= 0.18 then
                local matches = {}
                for c, before in pairs(event.before) do
                    local current = readCandidate(c)
                    if current ~= nil and before ~= nil then
                        local delta = current - before
                        local match = (event.kind == "collect" and delta > 0) or (event.kind == "buy" and delta < 0)
                        if match and not event.matched[c] then
                            event.matched[c] = true
                            table.insert(matches, { c=c, delta=delta })
                        end
                    end
                end
                if #matches > 0 then
                    local award = #matches == 1 and 8 or 3
                    for _, item in ipairs(matches) do
                        local extra = 0
                        if event.kind == "buy" and event.amount and event.amount > 0 then
                            local spent = -item.delta
                            local tolerance = math.max(2, event.amount * 0.2)
                            if math.abs(spent - event.amount) <= tolerance then extra = 4 end
                        end
                        item.c.correlation = math.min(30, item.c.correlation + award + extra)
                    end
                end
            end
            if now - event.at > 1.35 then table.remove(pendingEvents, index) end
        end
    end

    local function refresh()
        local now = os.clock()
        if #candidates == 0 or (not selected and now - lastDiscovery >= DISCOVERY_COOLDOWN) then discover() end
        if now - lastRefresh < REFRESH_INTERVAL then return end
        lastRefresh = now
        for _, c in ipairs(candidates) do
            local value = readCandidate(c)
            if value ~= nil and c.last ~= nil and value ~= c.last then
                c.changes = c.changes + 1
                c.lastChange = now
            end
            if value ~= nil then c.last = value end
        end
        evaluateEvents(now)
        chooseSource()
    end

    local function get()
        refresh()
        if selected then
            local value = readCandidate(selected)
            if value ~= nil then
                if selected ~= lastPrinted then
                    lastPrinted = selected
                    print("[0xVyrs Tycoon] currency locked -> " .. selected.object:GetFullName() .. " = " .. tostring(value) .. " // " .. selected.source)
                end
                return value
            end
            selected = nil
        end
        return nil
    end

    local function mark(kind, amount)
        refresh()
        if kind ~= "collect" and kind ~= "buy" then return end
        local before = {}
        for _, c in ipairs(candidates) do before[c] = readCandidate(c) end
        table.insert(pendingEvents, { kind=kind, amount=tonumber(amount), at=os.clock(), before=before, matched={} })
        while #pendingEvents > 6 do table.remove(pendingEvents, 1) end
    end

    local function status()
        refresh()
        local top = {}
        local ranked = {}
        for _, c in ipairs(candidates) do
            local value = readCandidate(c)
            if value ~= nil then
                table.insert(ranked, { c=c, value=value, rank=c.staticScore + c.correlation*90 + (c.rowScore>=400 and 800 or 0) })
            end
        end
        table.sort(ranked, function(a,b) return a.rank>b.rank end)
        for i=1,math.min(5,#ranked) do
            local item=ranked[i]
            table.insert(top,{value=item.value,source=item.c.source,score=item.c.staticScore,correlation=item.c.correlation,rowScore=item.c.rowScore,path=item.c.object and item.c.object:GetFullName() or "?"})
        end
        return {value=selected and readCandidate(selected) or nil,source=selected and selected.source or nil,path=selected and selected.object and selected.object:GetFullName() or nil,candidates=#candidates,top=top}
    end

    local function invalidate()
        selected=nil; candidates={}; pendingEvents={}; lastDiscovery=-math.huge; lastPrinted=nil
    end

    discover()
    chooseSource()
    return {get=get,mark=mark,status=status,invalidate=invalidate,parseNumber=parseNumber}
end