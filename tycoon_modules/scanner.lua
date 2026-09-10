-- 0xVyrs universal tycoon structural scanner.
-- Standalone hardening build: no nested module downloads, bounded local searches,
-- specific-plot preference, cached root scans and generic owner verification.

return function(context)
    local CONFIG = context.CONFIG
    local player = context.LOCAL_PLAYER

    local MAX_PARENT_DEPTH = 5
    local MAX_LOCAL_INSPECT = 36
    local ROOT_SCAN_COOLDOWN = 1.15
    local EMPTY_SCAN_COOLDOWN = 4.5
    local ROOT_MIN_SCORE = 13

    local knownRoot
    local knownMeta
    local lastResult
    local lastRootScan = -math.huge
    local lastEmptyScan = -math.huge

    local ROOT_HINTS = { "tycoon", "plot", "base", "factory", "island", "zone", "land" }
    local PURCHASE_HINTS = { "button", "buy", "purchase", "upgrade", "unlock", "build", "pad", "dropper", "conveyor" }
    local COLLECT_HINTS = { "collect", "collector", "cashout", "cash out", "claim cash", "deposit", "till" }
    local OWNED_HINTS = { "purchased", "bought", "owned", "completed", "built" }
    local BLOCKED = {
        "watch ad", "watch video", "video ad", "rewarded ad", "rewarded video", "advertisement",
        "starter pack", "starterpack", "gamepass", "game pass", "developer product", "dev product",
        "productid", "gamepassid", "premium", "robux", "r$", "rbx", "discord", "twitter",
    }
    local PRICE_NAMES = { cost=true, price=true, amount=true, cash=true, money=true, value=true, required=true, requirement=true }

    local function lower(v) return tostring(v or ""):lower() end
    local function trim(v) return tostring(v or ""):match("^%s*(.-)%s*$") or "" end
    local function compact(v) return lower(v):gsub("[^%w]", "") end
    local function hasAny(v, words)
        local text = lower(v)
        for _, word in ipairs(words) do if text:find(word,1,true) then return true end end
        return false
    end
    local function isContainer(o) return o and (o:IsA("Model") or o:IsA("Folder")) end
    local function isInteraction(o) return o and (o:IsA("TouchTransmitter") or o:IsA("ProximityPrompt") or o:IsA("ClickDetector")) end
    local function attrs(o)
        local ok, result = pcall(function() return o:GetAttributes() end)
        return ok and type(result)=="table" and result or nil
    end

    local function parseNumber(v)
        if type(v)=="number" then return v>=0 and v or nil end
        local text=lower(v):gsub(",",""):gsub("_"," ")
        local scientific=text:match("([%d%.]+e[%+%-]?%d+)")
        if scientific then local n=tonumber(scientific); if n and n>=0 then return n end end
        local ntext,suffix=text:match("([%d]+%.?[%d]*)%s*([kmbtq])")
        if not ntext then ntext=text:match("([%d]+%.?[%d]*)"); suffix="" end
        local n=tonumber(ntext); if not n or n<0 then return nil end
        local mult=({k=1e3,m=1e6,b=1e9,t=1e12,q=1e15})[suffix] or 1
        if text:find("thousand",1,true) then mult=1e3
        elseif text:find("million",1,true) then mult=1e6
        elseif text:find("billion",1,true) then mult=1e9
        elseif text:find("trillion",1,true) then mult=1e12
        elseif text:find("quadrillion",1,true) then mult=1e15
        elseif text:find("quintillion",1,true) then mult=1e18 end
        return n*mult
    end

    local function blockedText(v)
        local text=lower(v)
        for _, phrase in ipairs(BLOCKED) do if text:find(phrase,1,true) then return true end end
        local tokens=" "..text:gsub("[^%w]+"," ").." "
        return tokens:find(" ad ",1,true)~=nil or tokens:find(" ads ",1,true)~=nil
    end

    local function instanceBlocked(o)
        if not o then return false end
        if blockedText(o.Name) then return true end
        if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
            if blockedText(o.Text) then return true end
        elseif o:IsA("ProximityPrompt") then
            if blockedText(o.ActionText) or blockedText(o.ObjectText) then return true end
        end
        local a=attrs(o)
        if a then
            for key,value in pairs(a) do
                local k=lower(key)
                if blockedText(key) or k:find("productid",1,true) or k:find("gamepass",1,true)
                    or (type(value)=="string" and blockedText(value)) then return true end
            end
        end
        return false
    end

    local function blockedAround(o, stopAt)
        local current=o; local depth=0
        while current and current~=workspace and depth<=4 do
            if instanceBlocked(current) then return true end
            if current==stopAt then break end
            current=current.Parent; depth=depth+1
        end
        return false
    end

    local function priceName(name)
        local key=lower(name):gsub("[%s_%-]","")
        return PRICE_NAMES[key] or key:find("cost",1,true) or key:find("price",1,true) or key:find("require",1,true)
    end

    local function bareNumberText(text)
        local clean=trim(text):lower():gsub(",","")
        return clean~="" and #clean<=26 and not clean:find("%%",1,true)
            and clean:match("^[$£€¥]?%s*[%d%.]+%s*[kmbtq]?%s*$")~=nil
    end

    local function directPrice(o, allowBare)
        if not o then return nil end
        local a=attrs(o)
        if a then
            for key,value in pairs(a) do
                if priceName(key) then local n=parseNumber(value); if n~=nil then return n end end
            end
        end
        if (o:IsA("IntValue") or o:IsA("NumberValue") or o:IsA("StringValue")) and priceName(o.Name) then
            return parseNumber(o.Value)
        end
        if o:IsA("TextLabel") or o:IsA("TextButton") then
            local text=tostring(o.Text or "")
            local currency=hasAny(text,{"$","£","€","¥","cash","money","coin","cost","price","require"})
            if currency or (allowBare and bareNumberText(text)) then return parseNumber(text) end
        end
        return nil
    end

    local function smallTreePrice(root, allowBare)
        local n=directPrice(root,allowBare); if n~=nil then return n end
        local queue={root}; local cursor=1; local inspected=0
        while cursor<=#queue and inspected<MAX_LOCAL_INSPECT do
            local current=queue[cursor]; cursor=cursor+1
            for _,child in ipairs(current:GetChildren()) do
                inspected=inspected+1
                local value=directPrice(child,allowBare); if value~=nil then return value end
                if inspected<MAX_LOCAL_INSPECT and #child:GetChildren()>0 then table.insert(queue,child) end
                if inspected>=MAX_LOCAL_INSPECT then break end
            end
        end
        return nil
    end

    local function interactionPart(interaction)
        if not interaction then return nil end
        local p=interaction.Parent
        if p and p:IsA("BasePart") then return p end
        if p and p:IsA("Attachment") and p.Parent and p.Parent:IsA("BasePart") then return p.Parent end
        return nil
    end

    local function referencePart(o)
        if not o then return nil end
        if o:IsA("BasePart") then return o end
        if o:IsA("Model") and o.PrimaryPart then return o.PrimaryPart end
        local queue={o}; local cursor=1; local inspected=0
        while cursor<=#queue and inspected<MAX_LOCAL_INSPECT do
            local current=queue[cursor]; cursor=cursor+1
            for _,child in ipairs(current:GetChildren()) do
                inspected=inspected+1
                if child:IsA("BasePart") then return child end
                if inspected<MAX_LOCAL_INSPECT and #child:GetChildren()>0 then table.insert(queue,child) end
                if inspected>=MAX_LOCAL_INSPECT then break end
            end
        end
        return nil
    end

    local function ownerValue(value)
        if not player then return false end
        if typeof(value)=="Instance" then return value==player end
        if type(value)=="number" then return tonumber(value)==player.UserId end
        if type(value)=="string" then
            local v=compact(value)
            return v==compact(player.Name) or v==compact(player.DisplayName) or v==tostring(player.UserId)
        end
        return false
    end

    local function namedPlayerContainer(o)
        if not isContainer(o) or not player then return false end
        local name=compact(o.Name)
        if name~=compact(player.Name) and name~=compact(player.DisplayName) and name~=tostring(player.UserId) then return false end
        local current=o.Parent; local depth=0
        while current and current~=workspace and depth<4 do
            if hasAny(current.Name,{"tycoon","plot","base","player","land","factory"}) then return true end
            current=current.Parent; depth=depth+1
        end
        return false
    end

    local function ownerSignal(o)
        if not o then return false end
        if namedPlayerContainer(o) then return true end
        local a=attrs(o)
        if a then
            for key,value in pairs(a) do
                local k=lower(key)
                if (k:find("owner",1,true) or k:find("player",1,true) or k:find("userid",1,true)) and ownerValue(value) then return true end
            end
        end
        local name=lower(o.Name)
        local labelled=name:find("owner",1,true) or name:find("player",1,true) or name:find("userid",1,true)
        if o:IsA("ObjectValue") then return labelled and o.Value==player end
        if o:IsA("StringValue") or o:IsA("IntValue") or o:IsA("NumberValue") then return labelled and ownerValue(o.Value) end
        if o:IsA("TextLabel") or o:IsA("TextButton") then
            local text=compact(o.Text)
            return text~="" and (text:find(compact(player.Name),1,true)~=nil or text:find(compact(player.DisplayName),1,true)~=nil)
        end
        return false
    end

    local function interactionCount(root, limit)
        local count=0
        local ok, descendants=pcall(function() return root:GetDescendants() end)
        if not ok then return 0 end
        for _,o in ipairs(descendants) do
            if isInteraction(o) then count=count+1; if count>=(limit or 3) then break end end
        end
        return count
    end

    local function nearPrice(interaction, stopAt)
        local current=interaction and interaction.Parent; local depth=0
        while current and current~=workspace and depth<=MAX_PARENT_DEPTH do
            if not blockedAround(current,stopAt) then
                local price=smallTreePrice(current,true)
                if price~=nil then return price,current,depth end
            end
            if current==stopAt then break end
            current=current.Parent; depth=depth+1
        end
        return nil,nil,nil
    end

    local function directChildUnder(o, ancestor)
        local current=o; local previous=o
        while current and current~=ancestor do previous=current; current=current.Parent end
        return current==ancestor and previous or nil
    end

    local function discoverRoot()
        local started=os.clock()
        local descendants=workspace:GetDescendants()
        local interactions={}
        local named={}
        for _,o in ipairs(descendants) do
            if isInteraction(o) then table.insert(interactions,o) end
            if namedPlayerContainer(o) then table.insert(named,o) end
        end

        local bestNamed
        local bestNamedCount=0
        for _,root in ipairs(named) do
            local count=interactionCount(root,4)
            if count>bestNamedCount then bestNamed,bestNamedCount=root,count end
        end
        if bestNamed and bestNamedCount>0 then
            return bestNamed, {
                score=2000+bestNamedCount, structuralScore=100, ownerVerified=true,
                ownerSource="player-named-plot", selectedByPosition=false,
                worldSize=#descendants, interactions=bestNamedCount,
            }, (os.clock()-started)*1000
        end

        local stats={}
        local function stat(root)
            local s=stats[root]
            if not s then s={interactions=0,priced=0,blocked=0,families={},owner=false,nearest=math.huge}; stats[root]=s end
            return s
        end
        local playerRoot=context.getLocalRoot and context.getLocalRoot()
        local playerPos=playerRoot and playerRoot.Position

        for _,interaction in ipairs(interactions) do
            local price=nearPrice(interaction)
            local blocked=blockedAround(interaction)
            local part=interactionPart(interaction)
            local distance=playerPos and part and (part.Position-playerPos).Magnitude or math.huge
            local current=interaction.Parent; local depth=0
            while current and current~=workspace and depth<7 do
                if isContainer(current) then
                    local s=stat(current)
                    s.interactions=s.interactions+1
                    if price~=nil then s.priced=s.priced+1 end
                    if blocked then s.blocked=s.blocked+1 end
                    if distance<s.nearest then s.nearest=distance end
                    local family=directChildUnder(interaction,current)
                    if family then s.families[family]=(s.families[family] or 0)+1 end
                end
                current=current.Parent; depth=depth+1
            end
        end

        for _,o in ipairs(descendants) do
            if ownerSignal(o) then
                local current=o; local depth=0
                while current and current~=workspace and depth<7 do
                    if stats[current] then stats[current].owner=true end
                    current=current.Parent; depth=depth+1
                end
            end
        end

        local candidates={}
        for root,s in pairs(stats) do
            local maxFamily=0
            for _,count in pairs(s.families) do maxFamily=math.max(maxFamily,count) end
            local usable=math.max(0,s.priced-s.blocked)
            local score=(hasAny(root.Name,ROOT_HINTS) and 8 or 0)
                +math.min(14,s.interactions*0.9)+math.min(24,usable*3.2)+math.min(14,maxFamily*1.7)
                +(s.nearest<=40 and 18 or (s.nearest<=90 and 8 or 0))
                -math.min(18,s.blocked*1.5)+(s.owner and 900 or 0)
            local lname=lower(root.Name)
            if lname:find("tycoons",1,true) or lname:find("plots",1,true) or lname:find("bases",1,true) then score=score-30 end
            if score>=ROOT_MIN_SCORE then
                table.insert(candidates,{root=root,score=score,structuralScore=score-(s.owner and 900 or 0),ownerVerified=s.owner,ownerSource=s.owner and "owner" or "structure",nearest=s.nearest,interactions=s.interactions,priced=usable,maxFamily=maxFamily})
            end
        end
        table.sort(candidates,function(a,b)
            if a.ownerVerified~=b.ownerVerified then return a.ownerVerified end
            if a.score~=b.score then return a.score>b.score end
            if a.nearest~=b.nearest then return a.nearest<b.nearest end
            return #a.root:GetFullName()>#b.root:GetFullName()
        end)

        local selected=candidates[1]
        if not selected then return nil,nil,(os.clock()-started)*1000,#descendants end

        local childBest, childDistance
        if selected.root and isContainer(selected.root) then
            for _,child in ipairs(selected.root:GetChildren()) do
                if isContainer(child) and interactionCount(child,2)>0 then
                    local part=referencePart(child)
                    local distance=playerPos and part and (part.Position-playerPos).Magnitude or math.huge
                    if not childDistance or distance<childDistance then childBest,childDistance=child,distance end
                end
            end
        end
        if childBest and childDistance and childDistance<=70 and (selected.nearest==math.huge or childDistance<=selected.nearest+20) then
            selected={root=childBest,score=selected.score+25,structuralScore=selected.structuralScore,ownerVerified=selected.ownerVerified,ownerSource=selected.ownerVerified and selected.ownerSource or "position-cluster",selectedByPosition=not selected.ownerVerified,nearest=childDistance,interactions=interactionCount(childBest,20),priced=0,maxFamily=0}
        end

        selected.worldSize=#descendants
        return selected.root,selected,(os.clock()-started)*1000,#descendants
    end

    local function ownedArea(host, root)
        local current=host and host.Parent
        while current and current~=root and current~=workspace do
            if hasAny(current.Name,OWNED_HINTS) then return true end
            current=current.Parent
        end
        return false
    end

    local function hostFor(interaction, root)
        local price,host,depth=nearPrice(interaction,root)
        if price==nil or not host then return nil,nil,nil end
        local current=interaction.Parent; local d=0
        while current and current~=root and current~=workspace and d<=MAX_PARENT_DEPTH do
            if (current:IsA("Model") or current:IsA("BasePart")) and not blockedAround(current,root) then
                local localPrice=smallTreePrice(current,true)
                if localPrice~=nil then return current,localPrice,d end
            end
            current=current.Parent; d=d+1
        end
        return host,price,depth
    end

    local function entryName(host, interaction)
        if interaction:IsA("ProximityPrompt") then
            for _,v in ipairs({interaction.ObjectText,interaction.ActionText}) do
                local text=trim(v)
                if text~="" and not blockedText(text) and not bareNumberText(text) then return text end
            end
        end
        local name=host and trim(host.Name) or ""
        return name~="" and name or "Purchase"
    end

    local function collectorHost(interaction, root)
        local current=interaction.Parent; local depth=0
        while current and current~=workspace and depth<=5 do
            local semantic=hasAny(current.Name,COLLECT_HINTS)
            if interaction:IsA("ProximityPrompt") then semantic=semantic or hasAny(interaction.ActionText,COLLECT_HINTS) or hasAny(interaction.ObjectText,COLLECT_HINTS) end
            if semantic and not blockedAround(current,root) then return current end
            if current==root then break end
            current=current.Parent; depth=depth+1
        end
        return nil
    end

    local function scanRoot(root, meta, mode)
        local started=os.clock()
        local descendants=root:GetDescendants()
        local interactions={}
        for _,o in ipairs(descendants) do if isInteraction(o) then table.insert(interactions,o) end end

        local explicit=(meta and meta.ownerVerified==true) or namedPlayerContainer(root) or ownerSignal(root)
        if not explicit then
            for _,o in ipairs(descendants) do if ownerSignal(o) then explicit=true; break end end
        end
        local spatial=meta and meta.selectedByPosition==true
        local verified=explicit or spatial
        local allowed=verified or CONFIG.requireOwnerMatch==false
        local cash=tonumber(context.getCash())
        local data={
            root=root, rootName=root.Name,
            confidence=math.clamp(tonumber(meta and meta.score) or 0,0,100),
            rootScore=tonumber(meta and meta.score) or 0,
            structuralScore=tonumber(meta and meta.structuralScore) or 0,
            ownerMatch=verified, ownerVerified=verified,
            ownerSource=explicit and (meta and meta.ownerSource or "owner") or (spatial and "position-cluster" or "structure"),
            selectedByPosition=spatial, automationAllowed=allowed, safeAutomation=allowed,
            buttons={}, drops={}, cash=cash, owned=verified,
            maxLabels=CONFIG.maxLabels or 12, paidSkipped=0, scanMode=mode or "root",
        }

        if allowed then
            local records={}; local familyCounts={}; local seenHost={}; local purchaseInteractions={}
            for _,interaction in ipairs(interactions) do
                if not blockedAround(interaction,root) then
                    local host,price,depth=hostFor(interaction,root)
                    if host and price~=nil and not ownedArea(host,root) and not collectorHost(interaction,root) then
                        local family=host.Parent or root
                        familyCounts[family]=(familyCounts[family] or 0)+1
                        table.insert(records,{interaction=interaction,host=host,price=price,depth=depth or 0,family=family})
                    end
                else data.paidSkipped=data.paidSkipped+1 end
            end
            table.sort(records,function(a,b)
                local af=familyCounts[a.family] or 0; local bf=familyCounts[b.family] or 0
                if af~=bf then return af>bf end
                if a.depth~=b.depth then return a.depth<b.depth end
                return a.price<b.price
            end)
            for _,r in ipairs(records) do
                if #data.buttons>=CONFIG.maxButtons then break end
                if not seenHost[r.host] then
                    local familySize=familyCounts[r.family] or 1
                    local hinted=hasAny(r.host.Name,PURCHASE_HINTS) or hasAny(r.family and r.family.Name or "",PURCHASE_HINTS)
                    if familySize>=2 or hinted or r.price==0 or (verified and (r.depth or 99)<=2) then
                        local touch,prompt,click
                        if r.interaction:IsA("TouchTransmitter") then touch=interactionPart(r.interaction)
                        elseif r.interaction:IsA("ProximityPrompt") then prompt=r.interaction
                        else click=r.interaction end
                        local part=interactionPart(r.interaction) or referencePart(r.host)
                        if part or prompt or click then
                            local affordable=(cash~=nil and r.price<=cash) or r.price==0
                            table.insert(data.buttons,{object=r.host,part=part,touchPart=touch,prompt=prompt,clickDetector=click,price=r.price,affordable=affordable,locked=cash~=nil and r.price>cash or false,paidPurchase=false,ownerMatch=verified,ownerVerified=verified,automationAllowed=allowed,root=root,name=entryName(r.host,r.interaction),familySize=familySize})
                            seenHost[r.host]=true; purchaseInteractions[r.interaction]=true
                        end
                    end
                end
            end

            local seenCollectors={}
            for _,interaction in ipairs(interactions) do
                if #data.drops>=CONFIG.maxDrops then break end
                if not purchaseInteractions[interaction] then
                    local host=collectorHost(interaction,root)
                    if host then
                        local key=interactionPart(interaction) or interaction
                        if not seenCollectors[key] then
                            seenCollectors[key]=true
                            local touch,prompt,click
                            if interaction:IsA("TouchTransmitter") then touch=interactionPart(interaction)
                            elseif interaction:IsA("ProximityPrompt") then prompt=interaction
                            else click=interaction end
                            table.insert(data.drops,{object=host,part=interactionPart(interaction) or referencePart(host),touchPart=touch,prompt=prompt,clickDetector=click,ownerMatch=verified,ownerVerified=verified,automationAllowed=allowed,root=root,name=host.Name})
                        end
                    end
                end
            end
        end

        local affordable,locked=0,0
        for _,button in ipairs(data.buttons) do if button.affordable then affordable=affordable+1 elseif button.locked then locked=locked+1 end end
        data.affordableCount=affordable; data.lockedCount=locked; data.totalButtons=#data.buttons; data.progressPercent=0
        data.scanTimeMs=(os.clock()-started)*1000
        data.debug={scanMode=data.scanMode,scanTimeMs=data.scanTimeMs,snapshotSize=#descendants,rootScore=data.rootScore,structuralScore=data.structuralScore,ownerSource=data.ownerSource,rootInteractions=#interactions,paidSkipped=data.paidSkipped,rootSpecific=(root~=workspace and root.Parent~=workspace)}
        return data
    end

    local function refreshCash(data)
        if not data then return data end
        local cash=tonumber(context.getCash())
        if cash==nil then return data end
        data.cash=cash
        local affordable,locked=0,0
        for _,button in ipairs(data.buttons or {}) do
            if not button.paidPurchase and button.object and button.object.Parent then
                local price=tonumber(button.price)
                if price~=nil then
                    button.affordable=price<=cash; button.locked=price>cash
                    if button.affordable then affordable=affordable+1 else locked=locked+1 end
                end
            end
        end
        data.affordableCount=affordable; data.lockedCount=locked
        if data.debug then data.debug.scanMode="cached-cash" end
        return data
    end

    local function emptyData(elapsed, size)
        return {root=workspace,rootName="Workspace",confidence=0,rootScore=0,structuralScore=0,ownerMatch=false,ownerVerified=false,ownerSource="none",automationAllowed=CONFIG.requireOwnerMatch==false,safeAutomation=CONFIG.requireOwnerMatch==false,buttons={},drops={},cash=tonumber(context.getCash()),owned=false,maxLabels=CONFIG.maxLabels or 12,paidSkipped=0,affordableCount=0,lockedCount=0,totalButtons=0,progressPercent=0,scanMode="structural-discovery",scanTimeMs=elapsed,debug={scanMode="structural-discovery",scanTimeMs=elapsed,reason="no-structural-root",worldSnapshotSize=size or 0}}
    end

    local function fullScan()
        local now=os.clock()
        if lastResult and lastResult.root==workspace and now-lastEmptyScan<EMPTY_SCAN_COOLDOWN then return refreshCash(lastResult) end
        local root,meta,elapsed,size=discoverRoot()
        if not root then knownRoot=nil; knownMeta=nil; lastEmptyScan=now; lastResult=emptyData(elapsed,size); return lastResult end
        knownRoot=root; knownMeta=meta; lastRootScan=now
        lastResult=scanRoot(root,meta,"structural-discovery")
        if lastResult.debug then lastResult.debug.worldSnapshotSize=meta and meta.worldSize or size end
        return lastResult
    end

    local function scan()
        local now=os.clock()
        if knownRoot and knownRoot.Parent then
            if lastResult and now-lastRootScan<ROOT_SCAN_COOLDOWN then return refreshCash(lastResult) end
            lastRootScan=now
            lastResult=scanRoot(knownRoot,knownMeta or {},"cached-root")
            if lastResult.ownerVerified or CONFIG.requireOwnerMatch==false then return lastResult end
            knownRoot=nil; knownMeta=nil
        end
        return fullScan()
    end

    local function invalidateRoot(root)
        if not root or root==knownRoot then knownRoot=nil; knownMeta=nil; lastResult=nil; lastRootScan=-math.huge; lastEmptyScan=-math.huge end
    end

    return {scan=scan,parseCompactNumber=parseNumber,invalidateRoot=invalidateRoot}
end