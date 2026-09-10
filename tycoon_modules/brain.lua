-- 0xVyrs adaptive tycoon planner v3
-- Bounded classification, finite target selection and decaying compatibility failures.

return function(context)
    local HttpService=context.HttpService
    local CONFIG=context.CONFIG
    local PROFILE_FILE="tycoon_brain_v3.json"
    local PROFILE_VERSION=3
    local placeKey=tostring(game.PlaceId)

    local WEIGHTS={
        Fastest={income=118,upgrader=116,generator=112,conveyor=72,unlock=105,utility=48,unknown=38,structure=12,cosmetic=-8},
        Income={income=150,upgrader=148,generator=142,conveyor=92,unlock=58,utility=38,unknown=25,structure=-8,cosmetic=-28},
        Rebirth={income=112,upgrader=108,generator=106,conveyor=66,unlock=125,utility=55,unknown=45,structure=28,cosmetic=6},
    }
    local UNLOCK_VALUE={income=34,upgrader=32,generator=31,conveyor=18,unlock=28,utility=10,unknown=8,structure=3,cosmetic=0}
    local INCOME={"dropper","miner","mine","generator","printer","farm","oil","cash","money","income","factory","producer"}
    local UPGRADER={"upgrader","upgrade","multiplier","multiply","enhancer","processor","refiner","furnace","converter"}
    local CONVEYOR={"conveyor","belt","ore track","oretrack"}
    local UNLOCK={"stairs","stair","floor","unlock","bridge","elevator","lift","extension","expand","gate","area","room"}
    local STRUCTURE={"wall","window","door","roof","fence","railing","pillar","ceiling","path"}
    local COSMETIC={"decor","decoration","sign","poster","plant","tree","chair","table","light","lamp","statue","colour","color","paint"}

    local store={version=PROFILE_VERSION,places={}}
    local profile=nil
    local latestData=nil
    local latestStats={}
    local pendingEffects={}
    local currentRun=nil
    local lastPlan=nil
    local noButtonsSince=nil
    local lastEconomyAt=nil
    local lastCash=nil
    local observedIncomePerSecond=0

    local function lower(v) return tostring(v or ""):lower() end
    local function hasAny(text,words)
        text=lower(text)
        for _,word in ipairs(words) do if text:find(word,1,true) then return true end end
        return false
    end
    local function canFile()
        return type(isfile)=="function" and type(readfile)=="function" and type(writefile)=="function"
    end
    local function loadStore()
        if not canFile() or not isfile(PROFILE_FILE) then return end
        pcall(function()
            local decoded=HttpService:JSONDecode(readfile(PROFILE_FILE))
            if type(decoded)=="table" and type(decoded.places)=="table" then store=decoded end
        end)
    end
    local function saveStore()
        if not canFile() then return end
        pcall(function() writefile(PROFILE_FILE,HttpService:JSONEncode(store)) end)
    end
    local function ensureProfile()
        store.version=PROFILE_VERSION
        store.places=store.places or {}
        store.places[placeKey]=store.places[placeKey] or {}
        profile=store.places[placeKey]
        profile.runs=profile.runs or 0
        profile.nodes=profile.nodes or {}
        profile.edges=profile.edges or {}
        profile.runHistory=profile.runHistory or {}
        profile.bestRoute=profile.bestRoute or {}
        return profile
    end

    local function normaliseName(v)
        local text=lower(v)
        text=text:gsub("%b[]"," "):gsub("%$[%d%.,]+[%a]*"," "):gsub("[%d%.,]+%s*[kmbtq]?"," ")
        text=text:gsub("[^%w]+"," "):gsub("%s+"," ")
        text=text:match("^%s*(.-)%s*$") or text
        return text~="" and text or "unnamed"
    end
    local function parentHint(button)
        local object=button and button.object
        local root=button and button.root
        if not object then return "" end
        local parts={}
        local current=object.Parent
        local depth=0
        while current and current~=root and current~=workspace and depth<2 do
            table.insert(parts,1,normaliseName(current.Name))
            current=current.Parent
            depth=depth+1
        end
        return table.concat(parts,"/")
    end
    local function signature(button)
        if not button then return nil end
        return normaliseName(button.name or (button.object and button.object.Name)).."|"..parentHint(button)
    end
    local function classify(button)
        local text=lower(table.concat({button and button.name or "",button and button.object and button.object.Name or "",parentHint(button)}," "))
        if hasAny(text,UPGRADER) then return "upgrader" end
        if hasAny(text,INCOME) then return text:find("generator",1,true) and "generator" or "income" end
        if hasAny(text,CONVEYOR) then return "conveyor" end
        if hasAny(text,UNLOCK) then return "unlock" end
        if hasAny(text,COSMETIC) then return "cosmetic" end
        if hasAny(text,STRUCTURE) then return "structure" end
        return "unknown"
    end
    local function nodeFor(button)
        ensureProfile()
        local key=signature(button)
        if not key then return nil,nil end
        local node=profile.nodes[key]
        if not node then
            node={name=button.name or key,category=classify(button),seen=0,purchased=0,failures=0,avgPrice=0,avgIncomeDelta=0,roiSamples=0,avgPaybackSeconds=nil,unlockCount=0,unlockSamples=0}
            profile.nodes[key]=node
        end
        node.category=node.category or classify(button)
        node.failures=math.max(0,tonumber(node.failures) or 0)
        return key,node
    end
    local function snapshot(data)
        local result={}
        for _,button in ipairs(data and data.buttons or {}) do
            if not button.paidPurchase then
                local key=signature(button)
                if key then result[key]=true end
            end
        end
        return result
    end
    local function edgeInfo(sourceKey,childKey)
        local children=profile.edges[sourceKey]
        if not children then return nil end
        local edge=children[childKey]
        if type(edge)=="number" then edge={count=edge}; children[childKey]=edge end
        if type(edge)~="table" then return nil end
        edge.count=tonumber(edge.count) or 0
        return edge
    end
    local function addEdge(sourceKey,childKey)
        profile.edges[sourceKey]=profile.edges[sourceKey] or {}
        local edge=edgeInfo(sourceKey,childKey)
        if not edge then edge={count=0}; profile.edges[sourceKey][childKey]=edge end
        edge.count=edge.count+1
    end

    local function beginRun(strategy)
        currentRun={startedAt=os.clock(),strategy=strategy or CONFIG.strategy or "Fastest",purchases=0,spent=0,failures=0,sequence={},purchasedKeys={},categoryCounts={},waitingForCashSeconds=0,peakCashPerMinute=0}
        pendingEffects={}
        lastPlan=nil
        noButtonsSince=nil
    end
    local function ensureRun()
        if not currentRun then beginRun(CONFIG.strategy) end
        return currentRun
    end
    local function ratePerSecond(stats)
        local cpm=stats and tonumber(stats.cashPerMinute) or 0
        if cpm>0 then return cpm/60 end
        return observedIncomePerSecond
    end
    local function observeEconomy(cash,stats)
        latestStats=stats or latestStats
        local now=os.clock()
        cash=tonumber(cash)
        if cash and lastCash and lastEconomyAt and now>lastEconomyAt then
            local elapsed=now-lastEconomyAt
            local delta=cash-lastCash
            if delta>0 and elapsed>=0.4 then
                local direct=delta/elapsed
                if observedIncomePerSecond<=0 then observedIncomePerSecond=direct
                else observedIncomePerSecond=observedIncomePerSecond*0.75+direct*0.25 end
            end
        end
        local statsRate=latestStats and tonumber(latestStats.cashPerMinute)
        if statsRate and statsRate>0 then
            local direct=statsRate/60
            if observedIncomePerSecond<=0 then observedIncomePerSecond=direct
            else observedIncomePerSecond=observedIncomePerSecond*0.75+direct*0.25 end
        end
        if cash then lastCash=cash end
        lastEconomyAt=now

        local currentRate=ratePerSecond(latestStats)
        for i=#pendingEffects,1,-1 do
            local effect=pendingEffects[i]
            if now-effect.at>=2.5 then
                local node=profile.nodes[effect.key]
                if node then
                    local delta=math.max(0,currentRate-(effect.baselineRate or 0))
                    if delta>0 then
                        local samples=tonumber(node.roiSamples) or 0
                        local alpha=samples<2 and 0.55 or 0.28
                        node.avgIncomeDelta=(tonumber(node.avgIncomeDelta) or 0)*(1-alpha)+delta*alpha
                        node.roiSamples=samples+1
                        if effect.price>0 then
                            local payback=effect.price/delta
                            node.avgPaybackSeconds=node.avgPaybackSeconds and node.avgPaybackSeconds*0.7+payback*0.3 or payback
                        end
                    end
                end
                table.remove(pendingEffects,i)
            end
        end
    end

    local function observe(data,stats)
        ensureProfile()
        latestData=data
        latestStats=stats or latestStats
        local current=snapshot(data)
        for _,button in ipairs(data and data.buttons or {}) do
            local _,node=nodeFor(button)
            if node then
                node.seen=(tonumber(node.seen) or 0)+1
                local price=math.max(0,tonumber(button.price) or 0)
                node.avgPrice=(tonumber(node.avgPrice) or 0)==0 and price or node.avgPrice*0.86+price*0.14
            end
        end
        for _,effect in ipairs(pendingEffects) do
            if not effect.unlockResolved then
                local unlocked={}
                for key in pairs(current) do if not effect.beforeSnapshot[key] then table.insert(unlocked,key) end end
                local node=profile.nodes[effect.key]
                if node then
                    node.unlockSamples=(tonumber(node.unlockSamples) or 0)+1
                    node.unlockCount=(tonumber(node.unlockCount) or 0)*0.7+#unlocked*0.3
                end
                for _,child in ipairs(unlocked) do addEdge(effect.key,child) end
                effect.unlockResolved=true
            end
        end
        if data and data.ownerVerified and (data.totalButtons or 0)==0 then noButtonsSince=noButtonsSince or os.clock() else noButtonsSince=nil end
    end

    local function notePurchase(button,data,stats)
        local run=ensureRun()
        local key,node=nodeFor(button)
        if not key or not node then return end
        local price=math.max(0,tonumber(button.price) or 0)
        node.purchased=(tonumber(node.purchased) or 0)+1
        node.failures=math.max(0,(tonumber(node.failures) or 0)-1)
        run.purchases=run.purchases+1
        run.spent=run.spent+price
        run.purchasedKeys[key]=true
        run.categoryCounts[node.category]=(run.categoryCounts[node.category] or 0)+1
        table.insert(run.sequence,key)
        table.insert(pendingEffects,{key=key,price=price,beforeSnapshot=snapshot(data),baselineRate=ratePerSecond(stats or latestStats),at=os.clock(),unlockResolved=false})
        while #pendingEffects>8 do table.remove(pendingEffects,1) end
    end
    local function noteFailure(button)
        local run=ensureRun()
        local _,node=nodeFor(button)
        if node then node.failures=math.min(8,(tonumber(node.failures) or 0)+1) end
        run.failures=run.failures+1
    end

    local function edgePotential(key,depth,visited)
        if depth<=0 then return 0 end
        visited=visited or {}
        if visited[key] then return 0 end
        visited[key]=true
        local total=0
        for childKey in pairs(profile.edges[key] or {}) do
            local edge=edgeInfo(key,childKey)
            local child=profile.nodes[childKey]
            if edge and child then
                local parent=profile.nodes[key]
                local reliability=math.min(1,edge.count/math.max(1,tonumber(parent and parent.purchased) or 1))
                total=total+(UNLOCK_VALUE[child.category or "unknown"] or 6)*(0.45+reliability*0.55)
                if depth>1 then total=total+edgePotential(childKey,depth-1,visited)*0.35 end
            end
        end
        visited[key]=nil
        return total
    end
    local function bestRouteBonus(key)
        if not currentRun or not profile.bestRoute then return 0 end
        for _,routeKey in ipairs(profile.bestRoute) do
            if not currentRun.purchasedKeys[routeKey] then return routeKey==key and 95 or 0 end
        end
        return 0
    end
    local function actionable(button)
        return button and button.automationAllowed==true and button.affordable==true and not button.paidPurchase
            and button.object and button.object.Parent and not (button.blockedUntil and button.blockedUntil>os.clock())
    end
    local function scoreButton(button,data)
        if not actionable(button) then return nil end
        local key,node=nodeFor(button)
        if not key or not node then return nil end
        local strategy=CONFIG.strategy or "Fastest"
        local weights=WEIGHTS[strategy] or WEIGHTS.Fastest
        local category=node.category or "unknown"
        local score=weights[category] or weights.unknown
        local price=math.max(0,tonumber(button.price) or 0)
        local cash=math.max(0,tonumber(data and data.cash) or 0)
        score=score+math.min(150,edgePotential(key,2))+math.min(70,(tonumber(node.unlockCount) or 0)*18)
        if (tonumber(node.roiSamples) or 0)>0 then
            score=score+math.min(120,math.log(1+math.max(0,tonumber(node.avgIncomeDelta) or 0))*22)
            local payback=tonumber(node.avgPaybackSeconds)
            if payback then
                if payback<=12 then score=score+95 elseif payback<=25 then score=score+70 elseif payback<=60 then score=score+42 elseif payback<=120 then score=score+18 else score=score-12 end
            end
        end
        if price==0 then score=score+42 elseif cash>0 then
            local ratio=price/cash
            if ratio<=0.12 then score=score+30 elseif ratio<=0.35 then score=score+21 elseif ratio<=0.7 then score=score+10 elseif ratio>0.96 then score=score-8 end
        end
        if strategy=="Fastest" then score=score+bestRouteBonus(key) end
        if strategy=="Income" and (category=="income" or category=="upgrader" or category=="generator") then score=score+38 end
        if strategy=="Rebirth" and category=="unlock" then score=score+30 end
        if data and (data.totalButtons or 0)<=4 and (category=="structure" or category=="cosmetic" or category=="unknown") then score=score+65 end
        score=score-math.min(40,(tonumber(node.failures) or 0)*8)-math.min(30,(tonumber(button.failureCount) or 0)*6)
        return score
    end
    local function choosePurchase(data)
        if not data or not data.buttons then lastPlan=nil return nil,nil end
        local best,bestScore=nil,nil
        for _,button in ipairs(data.buttons) do
            local score=scoreButton(button,data)
            if type(score)=="number" and score==score and score~=math.huge and score~=-math.huge then
                if bestScore==nil or score>bestScore then best,bestScore=button,score end
            end
        end
        if best then
            local key,node=nodeFor(best)
            lastPlan={key=key,name=best.name,category=node and node.category or "unknown",price=best.price,score=bestScore,paybackSeconds=node and node.avgPaybackSeconds or nil,incomeDelta=node and node.avgIncomeDelta or 0,strategy=CONFIG.strategy or "Fastest",at=os.clock()}
        else lastPlan=nil end
        return best,bestScore
    end

    local function getBottleneck(data,stats)
        if not data or not data.ownerVerified then return "waiting for tycoon" end
        if (data.totalButtons or 0)==0 then return noButtonsSince and "verifying completion" or "waiting for unlock" end
        local affordable={}
        for _,button in ipairs(data.buttons or {}) do if actionable(button) then table.insert(affordable,button) end end
        if #affordable==0 then
            if ratePerSecond(stats)<=0 then return "no income detected" end
            if #(data.drops or {})>0 then return "waiting for collector" end
            return "waiting for cash"
        end
        local economic,unlocks,cleanup=0,0,0
        for _,button in ipairs(affordable) do
            local _,node=nodeFor(button)
            local category=node and node.category or "unknown"
            if category=="income" or category=="upgrader" or category=="generator" then economic=economic+1
            elseif category=="unlock" then unlocks=unlocks+1
            elseif category=="structure" or category=="cosmetic" then cleanup=cleanup+1 end
        end
        if economic>0 then return "scaling income" end
        if unlocks>0 then return "unlocking progression" end
        if cleanup==#affordable then return "cleanup purchases" end
        return "buying upgrades"
    end
    local function isLikelyComplete(data)
        return data and data.ownerVerified and (data.totalButtons or 0)==0 and noButtonsSince and os.clock()-noButtonsSince>=3
    end
    local function markRunComplete(seconds)
        ensureProfile()
        local run=ensureRun()
        seconds=tonumber(seconds) or (os.clock()-run.startedAt)
        profile.runs=(profile.runs or 0)+1
        profile.lastCompletionSeconds=seconds
        local record={seconds=seconds,purchases=run.purchases,spent=run.spent,failures=run.failures,peakCashPerMinute=run.peakCashPerMinute,strategy=run.strategy,categoryCounts=run.categoryCounts,at=os.time and os.time() or 0}
        table.insert(profile.runHistory,record)
        while #profile.runHistory>12 do table.remove(profile.runHistory,1) end
        profile.lastRun=record
        if not profile.bestCompletionSeconds or seconds<profile.bestCompletionSeconds then
            profile.bestCompletionSeconds=seconds
            profile.bestRoute={}
            for _,key in ipairs(run.sequence) do table.insert(profile.bestRoute,key) end
        end
        saveStore()
        beginRun(CONFIG.strategy)
    end
    local function resetPlaceProfile()
        store.places[placeKey]=nil
        profile=nil
        latestData=nil
        pendingEffects={}
        currentRun=nil
        lastPlan=nil
        ensureProfile()
        saveStore()
        return true
    end
    local function getStatus(data,stats)
        ensureProfile()
        data=data or latestData
        stats=stats or latestStats
        local nodes,edges=0,0
        for _ in pairs(profile.nodes) do nodes=nodes+1 end
        for _,children in pairs(profile.edges) do for _ in pairs(children) do edges=edges+1 end end
        return {placeId=game.PlaceId,strategy=CONFIG.strategy or "Fastest",runs=profile.runs or 0,learnedNodes=nodes,learnedEdges=edges,plan=lastPlan,bottleneck=getBottleneck(data,stats),complete=isLikelyComplete(data),observedIncomePerSecond=observedIncomePerSecond,bestCompletionSeconds=profile.bestCompletionSeconds,lastCompletionSeconds=profile.lastCompletionSeconds,bestRouteLength=#(profile.bestRoute or {}),lastRun=profile.lastRun,currentRun=currentRun}
    end

    loadStore()
    ensureProfile()
    return {observe=observe,observeEconomy=observeEconomy,beginRun=beginRun,notePurchase=notePurchase,noteFailure=noteFailure,classify=classify,scoreButton=scoreButton,choosePurchase=choosePurchase,getBottleneck=getBottleneck,isLikelyComplete=isLikelyComplete,markRunComplete=markRunComplete,resetPlaceProfile=resetPlaceProfile,getStatus=getStatus,save=saveStore}
end
