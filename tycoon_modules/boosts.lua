return function(context)
    local LOCAL_PLAYER=context.LOCAL_PLAYER
    local FREE_WORDS={"free reward","claim reward","daily reward","daily bonus","free bonus","free boost","free cash","free money","free coins","gift","reward chest","claim gift","collect reward","group reward","free multiplier"}
    local BOOST_WORDS={"2x cash","2x money","double cash","double money","cash boost","money boost","income boost","production boost","speed boost","multiplier"}
    local CLAIM_WORDS={"claim","collect","redeem","activate","use","open"}
    local BLOCKED_WORDS={"robux","r$","gamepass","game pass","premium","developer product","dev product","watch ad","watch video","rewarded ad","rewarded video","advert","purchase","buy now","shop","store","subscribe"}

    local DISCOVERY_INTERVAL=35
    local SWEEP_INTERVAL=6
    local PLAYER_GUI_BUDGET=260
    local TYCOON_BUDGET=320
    local MAX_CANDIDATES=12
    local cooldowns=setmetatable({}, {__mode="k"})
    local cachedCandidates={}
    local cachedRoot
    local lastDiscovery=-math.huge
    local lastSweep=0
    local lastActivated
    local activated=0
    local skipped=0

    local function lower(v) return tostring(v or ""):lower() end
    local function hasAny(text,words)
        text=lower(text)
        for _,word in ipairs(words) do if text:find(word,1,true) then return true end end
        return false
    end
    local function objectText(object)
        if not object then return "" end
        local parts={object.Name}
        if object:IsA("TextButton") or object:IsA("TextLabel") or object:IsA("TextBox") then table.insert(parts,object.Text)
        elseif object:IsA("ProximityPrompt") then table.insert(parts,object.ActionText); table.insert(parts,object.ObjectText) end
        return lower(table.concat(parts," "))
    end
    local function contextText(object)
        local parts={objectText(object)}
        local parent=object and object.Parent
        if parent then
            table.insert(parts,objectText(parent))
            local n=0
            for _,sibling in ipairs(parent:GetChildren()) do n=n+1; if n>8 then break end; table.insert(parts,objectText(sibling)) end
        end
        return lower(table.concat(parts," "))
    end
    local function safeCandidate(object)
        if not object or not object.Parent then return false end
        if object:IsA("TextButton") and object.Visible==false then return false end
        local text=contextText(object)
        if hasAny(text,BLOCKED_WORDS) then return false end
        return hasAny(text,FREE_WORDS) or (hasAny(text,BOOST_WORDS) and hasAny(text,CLAIM_WORDS))
    end
    local function interactive(object)
        return object:IsA("TextButton") or object:IsA("ProximityPrompt") or object:IsA("ClickDetector")
    end
    local function activate(object)
        if object:IsA("TextButton") and type(firesignal)=="function" then
            return pcall(function() firesignal(object.MouseButton1Click) end)
        elseif object:IsA("ProximityPrompt") and type(fireproximityprompt)=="function" then
            return pcall(function() fireproximityprompt(object) end)
        elseif object:IsA("ClickDetector") and type(fireclickdetector)=="function" then
            return pcall(function() fireclickdetector(object) end)
        end
        return false
    end
    local function gatherBounded(container,list,seen,budget)
        if not container then return end
        local queue={container}; local cursor=1; local inspected=0
        while cursor<=#queue and inspected<budget and #list<MAX_CANDIDATES do
            local current=queue[cursor]; cursor=cursor+1
            if current~=container and interactive(current) and not seen[current] and safeCandidate(current) then
                seen[current]=true; table.insert(list,current)
            end
            for _,child in ipairs(current:GetChildren()) do
                inspected=inspected+1
                if inspected<=budget then table.insert(queue,child) end
                if inspected>=budget then break end
            end
        end
    end
    local function discover(data)
        local root=data and data.ownerVerified and data.root~=workspace and data.root or nil
        local now=os.clock()
        if root==cachedRoot and now-lastDiscovery<DISCOVERY_INTERVAL then return end
        cachedRoot=root; lastDiscovery=now
        local found,seen={},{}
        gatherBounded(LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui"),found,seen,PLAYER_GUI_BUDGET)
        if root and #found<MAX_CANDIDATES then gatherBounded(root,found,seen,TYCOON_BUDGET) end
        cachedCandidates=found
    end
    local function sweep(data)
        local now=os.clock()
        if now-lastSweep<SWEEP_INTERVAL then return 0 end
        lastSweep=now; discover(data)
        local count=0
        for i=#cachedCandidates,1,-1 do
            local c=cachedCandidates[i]
            if not c or not c.Parent then table.remove(cachedCandidates,i)
            elseif now>=(cooldowns[c] or 0) and safeCandidate(c) then
                cooldowns[c]=now+30
                if activate(c) then count=count+1; activated=activated+1; lastActivated=contextText(c) else skipped=skipped+1 end
            end
            if count>=2 then break end
        end
        return count
    end
    local function invalidate() cachedRoot=nil; lastDiscovery=-math.huge; cachedCandidates={} end
    local function getStatus() return {activated=activated,skipped=skipped,lastActivated=lastActivated,candidateCount=#cachedCandidates,lastSweep=lastSweep} end
    return {sweep=sweep,invalidate=invalidate,getStatus=getStatus}
end