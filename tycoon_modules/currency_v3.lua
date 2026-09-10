-- 0xVyrs universal tycoon currency resolver v3
-- Never trusts another player's replicated player-list balance.

return function(context)
    local player=context.LOCAL_PLAYER
    local playerGui=player and player:FindFirstChildOfClass("PlayerGui")

    local selected=nil
    local candidates={}
    local lastDiscovery=-math.huge
    local lastIdentityCheck=-math.huge
    local lastPrinted=nil
    local DISCOVERY_INTERVAL=5
    local IDENTITY_RECHECK=0.75
    local IDENTITY_THRESHOLD=400
    local MAX_CANDIDATES=160

    local CASH_WORDS={"cash","money","balance","wallet","fund","coin","credit","currency","gold"}
    local RATE_WORDS={"/s","/sec","per sec","per second","income","rate","cps","rpm"}
    local BAD_WORDS={"ammo","health","level","experience","xp","serverstats","ping","fps","timer","countdown"}
    local PRICE_WORDS={"price","cost","purchase","buybutton","purchasebutton","shop","store","gamepass","robux","rebirthprice","cashboost"}

    local function lower(v) return tostring(v or ""):lower() end
    local function compact(v) return lower(v):gsub("[^%w]","") end
    local function hasAny(text,words)
        text=lower(text)
        for _,word in ipairs(words) do if text:find(word,1,true) then return true end end
        return false
    end
    local function parseNumber(v)
        if type(v)=="number" then return v>=0 and v or nil end
        local text=lower(v):gsub(",",""):gsub("_"," ")
        if hasAny(text,RATE_WORDS) or text:find("%%",1,true) then return nil end
        local sci=text:match("([%d%.]+e[%+%-]?%d+)")
        if sci then local n=tonumber(sci); if n and n>=0 then return n end end
        local number,suffix=text:match("([%d]+%.?[%d]*)%s*([kmbtq])")
        if not number then number=text:match("([%d]+%.?[%d]*)"); suffix="" end
        local n=tonumber(number)
        if not n or n<0 then return nil end
        return n*(({k=1e3,m=1e6,b=1e9,t=1e12,q=1e15})[suffix] or 1)
    end
    local function visible(o)
        local current=o
        local depth=0
        while current and depth<12 do
            if current:IsA("GuiObject") and current.Visible==false then return false end
            if current:IsA("LayerCollector") and current.Enabled==false then return false end
            current=current.Parent
            depth=depth+1
        end
        return true
    end
    local function pathText(o,depth)
        local parts={}
        local current=o
        local count=0
        while current and count<(depth or 10) do
            table.insert(parts,1,tostring(current.Name or ""))
            current=current.Parent
            count=count+1
        end
        return lower(table.concat(parts,"."))
    end
    local function rowFor(o)
        local current=o and o.Parent
        local previous=o
        local depth=0
        while current and current~=playerGui and depth<16 do
            if current:IsA("ScrollingFrame") then return previous end
            local parent=current.Parent
            local pname=parent and lower(parent.Name) or ""
            if pname:find("playerlist",1,true) or pname:find("leaderboard",1,true) then return current end
            previous=current
            current=parent
            depth=depth+1
        end
        return nil
    end
    local function identityScore(row)
        if not row or not player then return 0 end
        local username=compact(player.Name)
        local display=compact(player.DisplayName)
        local userId=tostring(player.UserId)
        local function score(v)
            local c=compact(v)
            if c=="" then return 0 end
            if c==userId then return 1000 end
            if c==username then return 980 end
            if display~="" and c==display then return 900 end
            if #username>=4 and c:find(username,1,true) then return 720 end
            if display~="" and #display>=4 and c:find(display,1,true) then return 620 end
            return 0
        end
        local best=score(row.Name)
        local queue={row}
        local cursor=1
        local inspected=0
        while cursor<=#queue and inspected<120 do
            local node=queue[cursor]
            cursor=cursor+1
            best=math.max(best,score(node.Name))
            if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then best=math.max(best,score(node.Text))
            elseif node:IsA("ImageLabel") or node:IsA("ImageButton") then
                if tostring(node.Image or ""):find(userId,1,true) then best=math.max(best,960) end
            elseif node:IsA("ObjectValue") and node.Value==player then best=math.max(best,1000)
            elseif node:IsA("StringValue") or node:IsA("IntValue") or node:IsA("NumberValue") then
                local ok,value=pcall(function() return node.Value end)
                if ok then best=math.max(best,score(value)) end
            end
            local ok,attrs=pcall(function() return node:GetAttributes() end)
            if ok and type(attrs)=="table" then
                for key,value in pairs(attrs) do
                    local k=lower(key)
                    if k:find("user",1,true) or k:find("player",1,true) or k:find("owner",1,true) or k:find("name",1,true) then best=math.max(best,score(value)) end
                end
            end
            if best>=980 then return best end
            for _,child in ipairs(node:GetChildren()) do
                inspected=inspected+1
                if inspected<=120 then table.insert(queue,child) end
                if inspected>=120 then break end
            end
        end
        return best
    end
    local function read(c)
        if not c or not c.object or not c.object.Parent then return nil end
        if c.kind=="gui" then
            if not visible(c.object) then return nil end
            local ok,text=pcall(function() return c.object.Text end)
            return ok and parseNumber(text) or nil
        elseif c.kind=="value" then
            local ok,value=pcall(function() return c.object.Value end)
            return ok and parseNumber(value) or nil
        elseif c.kind=="attribute" then
            local ok,value=pcall(function() return c.object:GetAttribute(c.key) end)
            return ok and parseNumber(value) or nil
        end
        return nil
    end
    local function add(kind,object,key,score,source,row,rowScore)
        local c={kind=kind,object=object,key=key,score=score or 0,source=source,row=row,rowScore=rowScore or 0}
        if read(c)~=nil then table.insert(candidates,c) end
    end
    local function scanData(root,limit)
        local queue={root}
        local cursor=1
        local inspected=0
        while cursor<=#queue and inspected<limit do
            local node=queue[cursor]
            cursor=cursor+1
            if node:IsA("IntValue") or node:IsA("NumberValue") or node:IsA("StringValue") then
                local path=pathText(node,8)
                local name=lower(node.Name)
                if (hasAny(name,CASH_WORDS) or hasAny(path,CASH_WORDS)) and not hasAny(path,BAD_WORDS) then
                    local score=hasAny(name,{"cash","money","balance","wallet"}) and 430 or 260
                    if lower(node.Parent and node.Parent.Name)=="leaderstats" then score=score+220 end
                    add("value",node,nil,score,"player-data",nil,0)
                end
            end
            local ok,attrs=pcall(function() return node:GetAttributes() end)
            if ok and type(attrs)=="table" then
                for key,value in pairs(attrs) do
                    if parseNumber(value)~=nil and hasAny(key,CASH_WORDS) then add("attribute",node,key,440,"player-data",nil,0) end
                end
            end
            for _,child in ipairs(node:GetChildren()) do
                inspected=inspected+1
                if inspected<=limit then table.insert(queue,child) end
                if inspected>=limit then break end
            end
        end
    end

    local function discover()
        candidates={}
        selected=nil
        playerGui=player and player:FindFirstChildOfClass("PlayerGui")
        if player then
            for _,child in ipairs(player:GetChildren()) do
                if not child:IsA("PlayerGui") and not child:IsA("PlayerScripts") then scanData(child,650) end
            end
        end
        local verifiedRows={}
        if playerGui then
            local ok,descendants=pcall(function() return playerGui:GetDescendants() end)
            if ok then
                for _,o in ipairs(descendants) do
                    if (o:IsA("TextLabel") or o:IsA("TextButton")) and visible(o) then
                        local text=tostring(o.Text or "")
                        local value=parseNumber(text)
                        if value~=nil then
                            local path=pathText(o,11)
                            local playerList=path:find("playerlist",1,true) or path:find("leaderboard",1,true)
                            local cashish=hasAny(o.Name,CASH_WORDS) or hasAny(path,CASH_WORDS) or text:find("$",1,true) or text:find("£",1,true) or text:find("€",1,true) or text:find("¥",1,true)
                            local blocked=hasAny(text,RATE_WORDS) or hasAny(path,BAD_WORDS)
                            local priceLike=hasAny(path,PRICE_WORDS)
                            if cashish and not blocked and (not priceLike or playerList) then
                                if playerList then
                                    local row=rowFor(o)
                                    local rowScore=identityScore(row)
                                    if rowScore>=IDENTITY_THRESHOLD then
                                        verifiedRows[row]=true
                                        add("gui",o,nil,1000+rowScore,"player-list",row,rowScore)
                                    end
                                else
                                    local score=250
                                    if hasAny(o.Name,{"cash","money","balance","wallet"}) then score=score+220 end
                                    if hasAny(path,{"cash","money","balance","wallet"}) then score=score+130 end
                                    if text:find("$",1,true) or text:find("£",1,true) then score=score+80 end
                                    add("gui",o,nil,score,"hud",nil,0)
                                end
                            end
                        end
                    end
                end
            end
        end
        table.sort(candidates,function(a,b)
            if a.source~=b.source then
                local rank={ ["player-list"]=3,["player-data"]=2,["hud"]=1 }
                return (rank[a.source] or 0)>(rank[b.source] or 0)
            end
            return a.score>b.score
        end)
        while #candidates>MAX_CANDIDATES do table.remove(candidates) end
        selected=candidates[1]
        lastDiscovery=os.clock()
        lastIdentityCheck=lastDiscovery
    end

    local function selectedValid()
        if not selected or read(selected)==nil then return false end
        if selected.source=="player-list" then
            local now=os.clock()
            if now-lastIdentityCheck>=IDENTITY_RECHECK then
                lastIdentityCheck=now
                local score=identityScore(selected.row)
                selected.rowScore=score
                if score<IDENTITY_THRESHOLD then return false end
            end
        end
        return true
    end
    local function refresh()
        local now=os.clock()
        if not selectedValid() or now-lastDiscovery>=DISCOVERY_INTERVAL then discover() end
        if not selectedValid() then selected=nil end
    end
    local function get()
        refresh()
        if not selected then return nil end
        local value=read(selected)
        if selected~=lastPrinted then
            lastPrinted=selected
            print("[0xVyrs Tycoon] currency pinned -> "..selected.object:GetFullName().." = "..tostring(value).." // "..selected.source.." // identity="..tostring(selected.rowScore or 0))
        end
        return value
    end
    local function status()
        refresh()
        return {value=selected and read(selected) or nil,source=selected and selected.source or nil,path=selected and selected.object and selected.object:GetFullName() or nil,identityScore=selected and selected.rowScore or 0,candidates=#candidates}
    end
    local function invalidate()
        selected=nil
        candidates={}
        lastDiscovery=-math.huge
        lastIdentityCheck=-math.huge
        lastPrinted=nil
    end
    local function mark() end

    discover()
    return {get=get,status=status,invalidate=invalidate,mark=mark,parseNumber=parseNumber}
end
