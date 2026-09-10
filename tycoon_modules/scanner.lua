-- 0xVyrs universal tycoon scanner v4
-- Canonical scanner: explicit ownership, bounded price evidence, no stale button cache.

return function(context)
    local CONFIG=context.CONFIG or {}
    local player=context.LOCAL_PLAYER

    local MAX_PARENT_DEPTH=6
    local MAX_PRICE_INSPECT=32
    local MAX_PAID_INSPECT=28
    local EMPTY_DISCOVERY_COOLDOWN=2.5
    local ROOT_MIN_SCORE=10

    local knownRoot=nil
    local knownMeta=nil
    local lastEmptyAt=-math.huge
    local lastEmpty=nil

    local ROOT_HINTS={"tycoon","plot","base","factory","island","zone","land"}
    local COLLECT_HINTS={"collect","collector","cashout","cash out","claim cash","deposit","till"}
    local OWNED_HINTS={"purchased","bought","owned","completed","built"}
    local PRICE_KEYS={cost=true,price=true,amount=true,required=true,requirement=true}

    local function lower(v) return tostring(v or ""):lower() end
    local function trim(v) return tostring(v or ""):match("^%s*(.-)%s*$") or "" end
    local function compact(v) return lower(v):gsub("[^%w]","") end
    local function hasAny(text,words)
        text=lower(text)
        for _,word in ipairs(words) do if text:find(word,1,true) then return true end end
        return false
    end
    local function isContainer(o) return o and (o:IsA("Model") or o:IsA("Folder")) end
    local function isInteraction(o) return o and (o:IsA("TouchTransmitter") or o:IsA("ProximityPrompt") or o:IsA("ClickDetector")) end

    local function parseNumber(v)
        if type(v)=="number" then return v>=0 and v or nil end
        local text=lower(v):gsub(",",""):gsub("_"," ")
        if text:find("%%",1,true) or text:find("/s",1,true) or text:find("/sec",1,true) or text:find("per second",1,true) then return nil end
        local sci=text:match("([%d%.]+e[%+%-]?%d+)")
        if sci then local n=tonumber(sci); if n and n>=0 then return n end end
        local number,suffix=text:match("([%d]+%.?[%d]*)%s*([kmbtq])")
        if not number then number=text:match("([%d]+%.?[%d]*)"); suffix="" end
        local n=tonumber(number)
        if not n or n<0 then return nil end
        local mult=({k=1e3,m=1e6,b=1e9,t=1e12,q=1e15})[suffix] or 1
        if text:find("thousand",1,true) then mult=1e3
        elseif text:find("million",1,true) then mult=1e6
        elseif text:find("billion",1,true) then mult=1e9
        elseif text:find("trillion",1,true) then mult=1e12
        elseif text:find("quadrillion",1,true) then mult=1e15 end
        return n*mult
    end

    local function explicitPaidText(value)
        local text=lower(value)
        if text=="" then return false end
        if text:find("rbxasset",1,true) or text:find("rbxthumb",1,true) then return false end
        return text:find("robux",1,true)~=nil
            or text:find("gamepass",1,true)~=nil
            or text:find("game pass",1,true)~=nil
            or text:find("developer product",1,true)~=nil
            or text:find("dev product",1,true)~=nil
            or text:find("watch ad",1,true)~=nil
            or text:find("watch video",1,true)~=nil
            or text:find("rewarded ad",1,true)~=nil
            or text:find("rewarded video",1,true)~=nil
            or text:find("premium purchase",1,true)~=nil
            or text:find("premium only",1,true)~=nil
            or text:match("%f[%w]r%$%s*%d")~=nil
    end

    local function truthyPaidValue(value)
        if value==true then return true end
        if type(value)=="number" then return value>0 end
        if type(value)=="string" then
            local c=compact(value)
            return c=="true" or c=="yes" or c=="paid" or c=="premium" or c=="robux"
        end
        return false
    end

    local function paidEvidenceObject(o)
        if not o then return nil end
        if explicitPaidText(o.Name) then return "name:"..tostring(o.Name) end
        if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
            if explicitPaidText(o.Text) then return "text:"..tostring(o.Text) end
        elseif o:IsA("ProximityPrompt") then
            if explicitPaidText(o.ActionText) then return "prompt-action:"..tostring(o.ActionText) end
            if explicitPaidText(o.ObjectText) then return "prompt-object:"..tostring(o.ObjectText) end
        elseif o:IsA("IntValue") or o:IsA("NumberValue") or o:IsA("StringValue") or o:IsA("BoolValue") then
            local key=compact(o.Name)
            local ok,value=pcall(function() return o.Value end)
            if ok then
                if (key=="gamepassid" or key=="productid" or key=="developerproductid" or key=="devproductid") and tonumber(value) and tonumber(value)>0 then
                    return o.Name.."="..tostring(value)
                end
                if (key=="gamepass" or key=="paid" or key=="robux" or key=="premiumonly") and truthyPaidValue(value) then
                    return o.Name.."="..tostring(value)
                end
                if type(value)=="string" and explicitPaidText(value) then return o.Name.."="..value end
            end
        end
        local ok,attrs=pcall(function() return o:GetAttributes() end)
        if ok and type(attrs)=="table" then
            for key,value in pairs(attrs) do
                local k=compact(key)
                if (k=="gamepassid" or k=="productid" or k=="developerproductid" or k=="devproductid") and tonumber(value) and tonumber(value)>0 then
                    return "attr:"..tostring(key).."="..tostring(value)
                end
                if (k=="gamepass" or k=="paid" or k=="robux" or k=="premiumonly") and truthyPaidValue(value) then
                    return "attr:"..tostring(key).."="..tostring(value)
                end
                if type(value)=="string" and explicitPaidText(value) then return "attr:"..tostring(key).."="..value end
            end
        end
        return nil
    end

    local function paidAround(interaction,root)
        local current=interaction
        local depth=0
        while current and current~=workspace and depth<=MAX_PARENT_DEPTH do
            local evidence=paidEvidenceObject(current)
            if evidence then return evidence end
            if current==root then break end
            current=current.Parent
            depth=depth+1
        end
        local origin=interaction and interaction.Parent
        if not origin then return nil end
        local queue={origin}
        local cursor=1
        local inspected=0
        while cursor<=#queue and inspected<MAX_PAID_INSPECT do
            local node=queue[cursor]
            cursor=cursor+1
            if node~=origin then
                local evidence=paidEvidenceObject(node)
                if evidence then return evidence end
            end
            for _,child in ipairs(node:GetChildren()) do
                inspected=inspected+1
                if inspected<=MAX_PAID_INSPECT then table.insert(queue,child) end
                if inspected>=MAX_PAID_INSPECT then break end
            end
        end
        return nil
    end

    local function attributes(o)
        local ok,result=pcall(function() return o:GetAttributes() end)
        return ok and type(result)=="table" and result or nil
    end

    local function ownerValue(v)
        if not player then return false end
        if typeof(v)=="Instance" then return v==player end
        if type(v)=="number" then return tonumber(v)==player.UserId end
        if type(v)=="string" then
            local c=compact(v)
            return c==compact(player.Name) or c==compact(player.DisplayName) or c==tostring(player.UserId)
        end
        return false
    end

    local function namedPlayerContainer(o)
        if not isContainer(o) or not player then return false end
        local n=compact(o.Name)
        if n~=compact(player.Name) and n~=compact(player.DisplayName) and n~=tostring(player.UserId) then return false end
        local current=o.Parent
        local depth=0
        while current and current~=workspace and depth<4 do
            if hasAny(current.Name,{"tycoon","plot","base","player","land","factory"}) then return true end
            current=current.Parent
            depth=depth+1
        end
        return false
    end

    local function ownerSignal(o)
        if not o then return false end
        if namedPlayerContainer(o) then return true end
        local a=attributes(o)
        if a then
            for key,value in pairs(a) do
                local k=lower(key)
                if (k:find("owner",1,true) or k:find("player",1,true) or k:find("userid",1,true)) and ownerValue(value) then return true end
            end
        end
        local n=lower(o.Name)
        local labelled=n:find("owner",1,true) or n:find("player",1,true) or n:find("userid",1,true)
        if o:IsA("ObjectValue") then return labelled and o.Value==player end
        if o:IsA("StringValue") or o:IsA("IntValue") or o:IsA("NumberValue") then return labelled and ownerValue(o.Value) end
        if o:IsA("TextLabel") or o:IsA("TextButton") then
            local t=compact(o.Text)
            local username=compact(player and player.Name)
            local display=compact(player and player.DisplayName)
            return t~="" and ((username~="" and t:find(username,1,true)) or (display~="" and t:find(display,1,true)))~=nil
        end
        return false
    end

    local function interactionPart(interaction)
        local parent=interaction and interaction.Parent
        if parent and parent:IsA("BasePart") then return parent end
        if parent and parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then return parent.Parent end
        return nil
    end

    local function nearestPart(o)
        if not o then return nil end
        if o:IsA("BasePart") then return o end
        if o:IsA("Model") and o.PrimaryPart then return o.PrimaryPart end
        local queue={o}
        local cursor=1
        local inspected=0
        while cursor<=#queue and inspected<24 do
            local current=queue[cursor]
            cursor=cursor+1
            for _,child in ipairs(current:GetChildren()) do
                inspected=inspected+1
                if child:IsA("BasePart") then return child end
                if inspected<24 and #child:GetChildren()>0 then table.insert(queue,child) end
                if inspected>=24 then break end
            end
        end
        return nil
    end

    local function priceKey(name)
        local key=lower(name):gsub("[%s_%-]","")
        return PRICE_KEYS[key] or key:find("price",1,true) or key:find("cost",1,true) or key:find("require",1,true)
    end

    local function candidateFromObject(o,depth)
        if not o or paidEvidenceObject(o) then return nil end
        local best=nil
        local function offer(value,score,label)
            value=parseNumber(value)
            if value==nil then return end
            score=score-(depth or 0)*8
            if not best or score>best.score then best={value=value,score=score,label=label} end
        end
        local a=attributes(o)
        if a then
            for key,value in pairs(a) do if priceKey(key) then offer(value,125,key) end end
        end
        if o:IsA("IntValue") or o:IsA("NumberValue") or o:IsA("StringValue") then
            if priceKey(o.Name) then offer(o.Value,118,o.Name) end
        elseif o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
            local text=tostring(o.Text or "")
            local l=lower(text)
            if not l:find("/s",1,true) and not l:find("/sec",1,true) and not l:find("per second",1,true) then
                local symbol=text:find("$",1,true) or text:find("£",1,true) or text:find("€",1,true) or text:find("¥",1,true)
                local named=priceKey(o.Name) or l:find("cost",1,true) or l:find("price",1,true) or l:find("requires",1,true)
                if symbol then offer(text,100,text) elseif named then offer(text,88,text) end
            end
        end
        return best
    end

    local function priceEvidence(interaction,root)
        local current=interaction and interaction.Parent
        local depth=0
        local globalBest=nil
        while current and current~=workspace and depth<=4 do
            if paidAround(current,root) then break end
            local nodes={current}
            local cursor=1
            local inspected=0
            while cursor<=#nodes and inspected<MAX_PRICE_INSPECT do
                local node=nodes[cursor]
                cursor=cursor+1
                local evidence=candidateFromObject(node,depth)
                if evidence and (not globalBest or evidence.score>globalBest.score) then
                    globalBest={value=evidence.value,score=evidence.score,label=evidence.label,host=current,source=node,depth=depth}
                end
                for _,child in ipairs(node:GetChildren()) do
                    inspected=inspected+1
                    if inspected<=MAX_PRICE_INSPECT then table.insert(nodes,child) end
                    if inspected>=MAX_PRICE_INSPECT then break end
                end
            end
            if current==root then break end
            current=current.Parent
            depth=depth+1
        end
        if globalBest and globalBest.score>=60 then return globalBest end
        return nil
    end

    local function collectorSemantic(interaction,root)
        local current=interaction and interaction.Parent
        local depth=0
        while current and current~=workspace and depth<=5 do
            if hasAny(current.Name,COLLECT_HINTS) then return true,current end
            if interaction:IsA("ProximityPrompt") and (hasAny(interaction.ActionText,COLLECT_HINTS) or hasAny(interaction.ObjectText,COLLECT_HINTS)) then return true,current end
            if current==root then break end
            current=current.Parent
            depth=depth+1
        end
        return false,nil
    end

    local function ownedArea(host,root)
        local current=host and host.Parent
        while current and current~=root and current~=workspace do
            if hasAny(current.Name,OWNED_HINTS) then return true end
            current=current.Parent
        end
        return false
    end

    local function meaningfulHost(evidence,interaction,root)
        local part=interactionPart(interaction)
        local host=evidence and evidence.host or part
        if host and host:IsA("BasePart") and host.Parent and host.Parent~=root and (host.Parent:IsA("Model") or host.Parent:IsA("Folder")) then
            local n=lower(host.Name)
            if n=="button" or n=="main" or n=="pad" or n=="part" or n=="primary" then host=host.Parent end
        end
        return host or part
    end

    local function entryName(host,interaction,evidence)
        if interaction:IsA("ProximityPrompt") then
            for _,v in ipairs({interaction.ObjectText,interaction.ActionText}) do
                local text=trim(v)
                if text~="" and not explicitPaidText(text) and parseNumber(text)==nil then return text end
            end
        end
        if evidence and type(evidence.label)=="string" then
            local text=evidence.label:gsub("[$£€¥]"," "):gsub("[%d%.,]+%s*[kmbtqKMBTQ]?"," "):gsub("%s+"," ")
            text=trim(text)
            if #text>=2 and text:match("%a") then return text end
        end
        return host and host.Name or "Purchase"
    end

    local function discoverRoot()
        local started=os.clock()
        local descendants=workspace:GetDescendants()
        local interactions={}
        local stats={}
        local function rootStat(root)
            local s=stats[root]
            if not s then s={interactions=0,priced=0,blocked=0,owner=false,nearest=math.huge}; stats[root]=s end
            return s
        end
        local localRoot=context.getLocalRoot and context.getLocalRoot()
        local playerPos=localRoot and localRoot.Position
        for _,o in ipairs(descendants) do if isInteraction(o) then table.insert(interactions,o) end end
        for _,interaction in ipairs(interactions) do
            local blocked=paidAround(interaction,nil)~=nil
            local evidence=blocked and nil or priceEvidence(interaction,nil)
            local part=interactionPart(interaction)
            local dist=playerPos and part and (part.Position-playerPos).Magnitude or math.huge
            local current=interaction.Parent
            local depth=0
            while current and current~=workspace and depth<7 do
                if isContainer(current) then
                    local s=rootStat(current)
                    s.interactions=s.interactions+1
                    if evidence then s.priced=s.priced+1 end
                    if blocked then s.blocked=s.blocked+1 end
                    if dist<s.nearest then s.nearest=dist end
                    if namedPlayerContainer(current) then s.owner=true end
                end
                current=current.Parent
                depth=depth+1
            end
        end
        for _,o in ipairs(descendants) do
            if ownerSignal(o) then
                local current=o
                local depth=0
                while current and current~=workspace and depth<7 do
                    if stats[current] then stats[current].owner=true end
                    current=current.Parent
                    depth=depth+1
                end
            end
        end
        local candidates={}
        for root,s in pairs(stats) do
            if s.interactions>0 then
                local usable=math.max(0,s.priced-s.blocked)
                local score=(hasAny(root.Name,ROOT_HINTS) and 10 or 0)+math.min(22,s.interactions*1.2)+math.min(35,usable*5)
                    +(s.nearest<=45 and 16 or (s.nearest<=100 and 7 or 0))+(s.owner and 1000 or 0)-math.min(18,s.blocked*2)
                local lname=lower(root.Name)
                if lname=="tycoons" or lname=="plots" or lname=="bases" or lname=="playertycoons" then score=score-45 end
                if score>=ROOT_MIN_SCORE then
                    table.insert(candidates,{root=root,score=score,ownerVerified=s.owner,ownerSource=s.owner and (namedPlayerContainer(root) and "player-named-plot" or "owner-signal") or "structure",nearest=s.nearest,interactions=s.interactions,priced=usable})
                end
            end
        end
        table.sort(candidates,function(a,b)
            if a.ownerVerified~=b.ownerVerified then return a.ownerVerified end
            if a.score~=b.score then return a.score>b.score end
            if a.nearest~=b.nearest then return a.nearest<b.nearest end
            return #a.root:GetFullName()>#b.root:GetFullName()
        end)
        local chosen=candidates[1]
        if not chosen then return nil,nil,(os.clock()-started)*1000,#descendants end
        chosen.worldSize=#descendants
        return chosen.root,chosen,(os.clock()-started)*1000,#descendants
    end

    local function scanRoot(root,meta,mode)
        local started=os.clock()
        local descendants=root:GetDescendants()
        local explicit=namedPlayerContainer(root) or ownerSignal(root)
        if not explicit then
            for _,o in ipairs(descendants) do if ownerSignal(o) then explicit=true break end end
        end
        local allowed=explicit or CONFIG.requireOwnerMatch==false
        local cash=tonumber(context.getCash())
        local data={root=root,rootName=root.Name,ownerMatch=explicit,ownerVerified=explicit,
            ownerSource=explicit and (meta and meta.ownerSource or "owner-signal") or "unverified-structure",
            selectedByPosition=false,automationAllowed=allowed,safeAutomation=allowed,owned=explicit,
            cash=cash,buttons={},drops={},maxLabels=CONFIG.maxLabels or 12,paidSkipped=0,
            scanMode=mode or "root",rootScore=tonumber(meta and meta.score) or 0}
        if allowed then
            local seenActivation={}
            local seenHost={}
            for _,interaction in ipairs(descendants) do
                if isInteraction(interaction) then
                    local paidEvidence=paidAround(interaction,root)
                    if paidEvidence then
                        data.paidSkipped=data.paidSkipped+1
                    else
                        local isCollector,collectorHost=collectorSemantic(interaction,root)
                        if isCollector then
                            if not seenActivation[interaction] and #data.drops<(CONFIG.maxDrops or 60) then
                                seenActivation[interaction]=true
                                local part=interactionPart(interaction) or nearestPart(collectorHost)
                                local touch,prompt,click
                                if interaction:IsA("TouchTransmitter") then touch=interactionPart(interaction)
                                elseif interaction:IsA("ProximityPrompt") then prompt=interaction
                                else click=interaction end
                                table.insert(data.drops,{object=collectorHost or interaction.Parent,part=part,touchPart=touch,prompt=prompt,clickDetector=click,activation=interaction,ownerVerified=explicit,automationAllowed=allowed,root=root,name=(collectorHost and collectorHost.Name) or "Collector"})
                            end
                        else
                            local evidence=priceEvidence(interaction,root)
                            if evidence and #data.buttons<(CONFIG.maxButtons or 80) then
                                local host=meaningfulHost(evidence,interaction,root)
                                if host and not seenHost[host] and not ownedArea(host,root) then
                                    local part=interactionPart(interaction) or nearestPart(host)
                                    if part then
                                        local touch,prompt,click
                                        if interaction:IsA("TouchTransmitter") then touch=interactionPart(interaction)
                                        elseif interaction:IsA("ProximityPrompt") then prompt=interaction
                                        else click=interaction end
                                        local price=evidence.value
                                        local affordable=(cash~=nil and price<=cash) or price==0
                                        table.insert(data.buttons,{object=host,part=part,touchPart=touch,prompt=prompt,clickDetector=click,activation=interaction,price=price,priceConfidence=evidence.score,priceSource=evidence.source,affordable=affordable,locked=cash~=nil and price>cash or false,paidPurchase=false,ownerMatch=explicit,ownerVerified=explicit,automationAllowed=allowed,root=root,name=entryName(host,interaction,evidence)})
                                        seenHost[host]=true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        local affordable,locked=0,0
        for _,button in ipairs(data.buttons) do if button.affordable then affordable=affordable+1 elseif button.locked then locked=locked+1 end end
        data.totalButtons=#data.buttons
        data.affordableCount=affordable
        data.lockedCount=locked
        data.progressPercent=0
        data.scanTimeMs=(os.clock()-started)*1000
        data.debug={scanMode=data.scanMode,scanTimeMs=data.scanTimeMs,snapshotSize=#descendants,rootScore=data.rootScore,ownerSource=data.ownerSource,paidSkipped=data.paidSkipped,moduleVersion="4"}
        return data
    end

    local function emptyData(elapsed,size)
        return {root=workspace,rootName="Workspace",ownerMatch=false,ownerVerified=false,ownerSource="none",selectedByPosition=false,
            automationAllowed=CONFIG.requireOwnerMatch==false,safeAutomation=CONFIG.requireOwnerMatch==false,owned=false,
            cash=tonumber(context.getCash()),buttons={},drops={},affordableCount=0,lockedCount=0,totalButtons=0,progressPercent=0,
            scanMode="structural-discovery",scanTimeMs=elapsed,debug={scanMode="structural-discovery",scanTimeMs=elapsed,reason="no-root",worldSnapshotSize=size or 0,moduleVersion="4"}}
    end

    local function scan()
        if knownRoot and knownRoot.Parent then return scanRoot(knownRoot,knownMeta or {},"known-root") end
        local now=os.clock()
        if lastEmpty and now-lastEmptyAt<EMPTY_DISCOVERY_COOLDOWN then
            lastEmpty.cash=tonumber(context.getCash())
            return lastEmpty
        end
        local root,meta,elapsed,size=discoverRoot()
        if not root then
            knownRoot=nil
            knownMeta=nil
            lastEmptyAt=now
            lastEmpty=emptyData(elapsed,size)
            return lastEmpty
        end
        knownRoot=root
        knownMeta=meta
        lastEmpty=nil
        return scanRoot(root,meta,"structural-discovery")
    end

    local function invalidateRoot(root)
        if not root or root==knownRoot then knownRoot=nil; knownMeta=nil; lastEmpty=nil; lastEmptyAt=-math.huge end
    end

    return {scan=scan,invalidateRoot=invalidateRoot,parseCompactNumber=parseNumber,moduleVersion="4"}
end
