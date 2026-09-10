-- 0xVyrs universal tycoon currency resolver.
-- Read-only: finds the local player's spendable currency without allowing
-- another player's replicated leaderboard/player-list cash to take over.

return function(context)
    context = context or {}
    local player = context.LOCAL_PLAYER or game:GetService("Players").LocalPlayer
    local playerGui = player and player:FindFirstChildOfClass("PlayerGui")

    local candidates = {}
    local selected
    local selectedReason
    local strictPlayerListCount = 0
    local lastDiscovery = -math.huge
    local lastRefresh = -math.huge
    local lastPrinted
    local pendingEvents = {}

    local DISCOVERY_COOLDOWN = 8
    local REFRESH_INTERVAL = 0.18
    local MAX_CANDIDATES = 180
    local IDENTITY_THRESHOLD = 400

    local RATE_WORDS = { "/s", "/sec", "per sec", "per second", "income", "rate", "cps", "rpm" }
    local PRICE_WORDS = { "price", "cost", "purchase", "buybutton", "purchasebutton", "shop", "store", "gamepass", "robux", "rebirthprice", "cashboost" }
    local BAD_WORDS = { "ammo", "health", "level", "experience", "xp", "serverstats", "ping", "fps", "timer", "countdown" }
    local CASH_WORDS = { "cash", "money", "balance", "wallet", "fund", "coin", "credit", "currency", "gold" }

    local function lower(v) return tostring(v or ""):lower() end
    local function compact(v) return lower(v):gsub("[^%w]", "") end
    local function hasAny(text, words)
        text = lower(text)
        for _, word in ipairs(words) do
            if text:find(word, 1, true) then return true end
        end
        return false
    end

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
        return n * (({ k=1e3, m=1e6, b=1e9, t=1e12, q=1e15 })[suffix] or 1)
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

    -- Return the actual direct player row under the scrolling list. This is
    -- important because many games clone every row with the same name "Template".
    local function rowFor(object)
        local current = object and object.Parent
        local previous = object
        local depth = 0
        while current and current ~= playerGui and depth < 14 do
            if current:IsA("ScrollingFrame") then return previous end
            local parent = current.Parent
            local parentName = parent and lower(parent.Name) or ""
            if parentName:find("scroll",1,true) or parentName:find("playerlist",1,true) or parentName:find("leaderboard",1,true) then
                return current
            end
            previous = current
            current = parent
            depth = depth + 1
        end
        return nil
    end

    local function localIdentityScore(row)
        if not row or not player then return 0 end
        local username = compact(player.Name)
        local displayName = compact(player.DisplayName)
        local userId = tostring(player.UserId)
        local best = 0

        local function scoreText(v)
            local c = compact(v)
            if c == "" then return 0 end
            if c == userId then return 1000 end
            if c == username then return 980 end
            if displayName ~= "" and c == displayName then return 900 end
            if #username >= 4 and c:find(username,1,true) then return 720 end
            if displayName ~= "" and #displayName >= 4 and c:find(displayName,1,true) then return 620 end
            return 0
        end

        local queue = { row }
        local cursor = 1
        local inspected = 0
        while cursor <= #queue and inspected < 140 do
            local node = queue[cursor]
            cursor = cursor + 1
            best = math.max(best, scoreText(node.Name))

            if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
                best = math.max(best, scoreText(node.Text))
            elseif node:IsA("ImageLabel") or node:IsA("ImageButton") then
                local image = tostring(node.Image or "")
                if image:find(userId,1,true) then best = math.max(best, 960) end
            elseif node:IsA("ObjectValue") and node.Value == player then
                best = math.max(best, 1000)
            elseif node:IsA("StringValue") or node:IsA("IntValue") or node:IsA("NumberValue") then
                local okValue, value = pcall(function() return node.Value end)
                if okValue then best = math.max(best, scoreText(value)) end
            end

            local okAttrs, attributes = pcall(function() return node:GetAttributes() end)
            if okAttrs and type(attributes) == "table" then
                for key, value in pairs(attributes) do
                    local k = lower(key)
                    if k:find("user",1,true) or k:find("player",1,true) or k:find("owner",1,true) or k:find("name",1,true) then
                        best = math.max(best, scoreText(value))
                    end
                end
            end

            if best >= 980 then return best end
            for _, child in ipairs(node:GetChildren()) do
                inspected = inspected + 1
                if inspected <= 140 then table.insert(queue, child) end
                if inspected >= 140 then break end
            end
        end
        return best
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
        local candidate = {
            kind = kind,
            object = object,
            key = key,
            staticScore = score or 0,
            source = source or "unknown",
            rowScore = rowScore or 0,
            correlation = 0,
            changes = 0,
            last = nil,
            lastChange = -math.huge,
            eligible = true,
        }
        candidate.last = readCandidate(candidate)
        if candidate.last ~= nil then table.insert(candidates, candidate) end
    end

    local function scanDataTree(root, limit)
        if not root then return end
        local queue = { root }
        local cursor = 1
        local inspected = 0
        while cursor <= #queue and inspected < limit do
            local node = queue[cursor]
            cursor = cursor + 1

            if node:IsA("IntValue") or node:IsA("NumberValue") or node:IsA("StringValue") then
                local path = pathText(node, 7)
                local name = lower(node.Name)
                if (hasAny(name, CASH_WORDS) or hasAny(path, CASH_WORDS)) and not hasAny(path, BAD_WORDS) then
                    local score = hasAny(name,{"cash","money","balance","wallet"}) and 340 or 190
                    if lower(node.Parent and node.Parent.Name) == "leaderstats" then score = score + 180 end
                    addCandidate("value",node,nil,score,"player-data",0)
                end
            end

            local okAttrs, attributes = pcall(function() return node:GetAttributes() end)
            if okAttrs and type(attributes) == "table" then
                for key, value in pairs(attributes) do
                    if parseNumber(value) ~= nil and hasAny(key,CASH_WORDS) then
                        addCandidate("attribute",node,key,330,"attribute",0)
                    end
                end
            end

            for _, child in ipairs(node:GetChildren()) do
                inspected = inspected + 1
                if inspected <= limit then table.insert(queue,child) end
                if inspected >= limit then break end
            end
        end
    end

    local function discover()
        if not player then return end
        local oldSelectedObject = selected and selected.object or nil
        candidates = {}
        selected = nil
        selectedReason = nil
        strictPlayerListCount = 0
        playerGui = player:FindFirstChildOfClass("PlayerGui")

        for _, child in ipairs(player:GetChildren()) do
            if not child:IsA("PlayerGui") and not child:IsA("PlayerScripts") then
                scanDataTree(child,700)
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
                            local path = pathText(object,10)
                            local name = lower(object.Name)
                            local playerList = path:find("playerlist",1,true) ~= nil or path:find("leaderboard",1,true) ~= nil
                            local symbol = text:find("$",1,true) or text:find("£",1,true) or text:find("€",1,true) or text:find("¥",1,true)
                            local cashish = hasAny(name,CASH_WORDS) or hasAny(path,CASH_WORDS) or symbol
                            local blocked = hasAny(lower(text),RATE_WORDS) or hasAny(path,BAD_WORDS)
                            if cashish and not blocked then
                                local priceLike = hasAny(path,PRICE_WORDS)
                                if not priceLike or playerList then
                                    local score = 0
                                    if hasAny(name,{"cash","money","balance","wallet"}) then score = score + 260 end
                                    if symbol then score = score + 100 end
                                    if hasAny(path,{"cash","money","balance","wallet"}) then score = score + 110 end
                                    local rowScore = 0
                                    if playerList then
                                        rowScore = localIdentityScore(rowFor(object))
                                        score = score + 40
                                        if rowScore >= IDENTITY_THRESHOLD then
                                            strictPlayerListCount = strictPlayerListCount + 1
                                            score = score + rowScore
                                        end
                                    end
                                    addCandidate("gui",object,nil,score,playerList and "player-list" or "hud",rowScore)
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Critical safety rule: if at least one player-list cash label can be
        -- tied to LocalPlayer, every anonymous player-list cash label is banned.
        -- Correlation can never make another player's row eligible again.
        if strictPlayerListCount > 0 then
            for _, c in ipairs(candidates) do
                if c.source == "player-list" and c.rowScore < IDENTITY_THRESHOLD then
                    c.eligible = false
                end
            end
        end

        table.sort(candidates,function(a,b)
            if a.eligible ~= b.eligible then return a.eligible end
            if a.rowScore ~= b.rowScore then return a.rowScore > b.rowScore end
            if a.staticScore ~= b.staticScore then return a.staticScore > b.staticScore end
            return (a.last or 0) > (b.last or 0)
        end)
        while #candidates > MAX_CANDIDATES do table.remove(candidates) end

        -- Preserve the exact same GUI object across rediscovery when possible.
        if oldSelectedObject then
            for _, c in ipairs(candidates) do
                if c.object == oldSelectedObject and c.eligible then
                    selected = c
                    selectedReason = c.rowScore >= IDENTITY_THRESHOLD and "local-player-row" or "preserved"
                    break
                end
            end
        end
        lastDiscovery = os.clock()
    end

    local function selectedAlive()
        return selected and selected.eligible and readCandidate(selected) ~= nil
    end

    local function chooseSource()
        -- A verified local-player row is absolute. Never replace it because
        -- another player's cash happened to change near one of our events.
        if selectedAlive() and selected.rowScore >= IDENTITY_THRESHOLD then return end

        local bestLocal
        for _, c in ipairs(candidates) do
            if c.eligible and c.source == "player-list" and c.rowScore >= IDENTITY_THRESHOLD and readCandidate(c) ~= nil then
                if not bestLocal or c.rowScore > bestLocal.rowScore or (c.rowScore == bestLocal.rowScore and c.staticScore > bestLocal.staticScore) then
                    bestLocal = c
                end
            end
        end
        if bestLocal then
            selected = bestLocal
            selectedReason = "local-player-row"
            return
        end

        -- Direct data owned by LocalPlayer is safer than any anonymous GUI row.
        if selectedAlive() and (selected.source == "player-data" or selected.source == "attribute") then return end
        local bestData
        for _, c in ipairs(candidates) do
            if c.eligible and (c.source == "player-data" or c.source == "attribute") and readCandidate(c) ~= nil then
                if not bestData or c.staticScore > bestData.staticScore then bestData = c end
            end
        end
        if bestData and bestData.staticScore >= 300 then
            selected = bestData
            selectedReason = "local-player-data"
            return
        end

        -- Prefer a strong non-player-list HUD source next.
        if selectedAlive() and selected.source ~= "player-list" then return end
        local bestHud
        for _, c in ipairs(candidates) do
            if c.eligible and c.source ~= "player-list" and readCandidate(c) ~= nil then
                local rank = c.staticScore + c.correlation*90
                if not bestHud or rank > bestHud.rank then bestHud = {c=c,rank=rank} end
            end
        end
        if bestHud and (bestHud.c.staticScore >= 420 or bestHud.c.correlation >= 8) then
            selected = bestHud.c
            selectedReason = "hud"
            return
        end

        -- Last resort for games whose only replicated currency is an anonymous
        -- player list: require a large, unique correlation lead, then pin it.
        -- This path is disabled whenever a verified local row exists.
        if strictPlayerListCount == 0 and not selectedAlive() then
            local first, second
            for _, c in ipairs(candidates) do
                if c.eligible and c.source == "player-list" and readCandidate(c) ~= nil then
                    if not first or c.correlation > first.correlation then
                        second = first
                        first = c
                    elseif not second or c.correlation > second.correlation then
                        second = c
                    end
                end
            end
            local runnerUp = second and second.correlation or 0
            if first and first.correlation >= 18 and first.correlation - runnerUp >= 8 then
                selected = first
                selectedReason = "correlation-fallback"
            end
        end
    end

    local function evaluateEvents(now)
        for index=#pendingEvents,1,-1 do
            local event = pendingEvents[index]
            if now-event.at >= 0.16 then
                local matches = {}
                for c,before in pairs(event.before) do
                    if c.eligible then
                        local current = readCandidate(c)
                        if current ~= nil and before ~= nil then
                            local delta = current-before
                            local match = (event.kind=="collect" and delta>0) or (event.kind=="buy" and delta<0)
                            if match and not event.matched[c] then
                                event.matched[c] = true
                                table.insert(matches,{c=c,delta=delta})
                            end
                        end
                    end
                end
                if #matches > 0 then
                    local award = #matches==1 and 8 or 2
                    for _,item in ipairs(matches) do
                        local extra = 0
                        if event.kind=="buy" and event.amount and event.amount>0 then
                            local spent = -item.delta
                            local tolerance = math.max(2,event.amount*0.2)
                            if math.abs(spent-event.amount)<=tolerance then extra=4 end
                        end
                        item.c.correlation = math.min(30,item.c.correlation+award+extra)
                    end
                end
            end
            if now-event.at > 1.2 then table.remove(pendingEvents,index) end
        end
    end

    local function refresh()
        local now=os.clock()
        if #candidates==0 or (not selectedAlive() and now-lastDiscovery>=DISCOVERY_COOLDOWN) then discover() end
        if now-lastRefresh < REFRESH_INTERVAL then return end
        lastRefresh=now

        for _,c in ipairs(candidates) do
            if c.eligible then
                local value=readCandidate(c)
                if value~=nil and c.last~=nil and value~=c.last then
                    c.changes=c.changes+1
                    c.lastChange=now
                end
                if value~=nil then c.last=value end
            end
        end
        evaluateEvents(now)
        chooseSource()
    end

    local function get()
        refresh()
        if selectedAlive() then
            local value=readCandidate(selected)
            if selected~=lastPrinted then
                lastPrinted=selected
                print("[0xVyrs Tycoon] currency pinned -> "..selected.object:GetFullName().." = "..tostring(value).." // "..tostring(selectedReason or selected.source).." // identity="..tostring(selected.rowScore or 0))
            end
            return value
        end
        selected=nil
        selectedReason=nil
        return nil
    end

    local function mark(kind,amount)
        refresh()
        if kind~="collect" and kind~="buy" then return end
        local before={}
        for _,c in ipairs(candidates) do
            if c.eligible then before[c]=readCandidate(c) end
        end
        table.insert(pendingEvents,{kind=kind,amount=tonumber(amount),at=os.clock(),before=before,matched={}})
        while #pendingEvents>6 do table.remove(pendingEvents,1) end
    end

    local function status()
        refresh()
        local top={}
        local ranked={}
        for _,c in ipairs(candidates) do
            if c.eligible then
                local value=readCandidate(c)
                if value~=nil then
                    local rank=c.staticScore+c.correlation*90+(c.rowScore>=IDENTITY_THRESHOLD and 100000 or 0)
                    table.insert(ranked,{c=c,value=value,rank=rank})
                end
            end
        end
        table.sort(ranked,function(a,b) return a.rank>b.rank end)
        for i=1,math.min(5,#ranked) do
            local item=ranked[i]
            table.insert(top,{value=item.value,source=item.c.source,score=item.c.staticScore,correlation=item.c.correlation,rowScore=item.c.rowScore,path=item.c.object and item.c.object:GetFullName() or "?"})
        end
        return {
            value=selectedAlive() and readCandidate(selected) or nil,
            source=selected and selected.source or nil,
            reason=selectedReason,
            path=selected and selected.object and selected.object:GetFullName() or nil,
            candidates=#candidates,
            strictPlayerListCount=strictPlayerListCount,
            identityScore=selected and selected.rowScore or 0,
            top=top,
        }
    end

    local function invalidate()
        selected=nil
        selectedReason=nil
        candidates={}
        pendingEvents={}
        strictPlayerListCount=0
        lastDiscovery=-math.huge
        lastPrinted=nil
    end

    discover()
    chooseSource()
    return {get=get,mark=mark,status=status,invalidate=invalidate,parseNumber=parseNumber}
end