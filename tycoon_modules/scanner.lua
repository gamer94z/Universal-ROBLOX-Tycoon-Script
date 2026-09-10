return function()
	local MAX_ROOT_DEPTH = 7
	local MAX_PARENT_DEPTH = 5
	local MAX_LOCAL_INSPECT = 32
	local ROOT_MIN_SCORE = 12
	local HEAVY_SCAN_COOLDOWN = 1.35
	local EMPTY_SCAN_COOLDOWN = 2.5

	local knownRoot, knownMeta, lastResult
	local lastHeavyScan = -math.huge
	local lastEmptyScan = -math.huge

	local ROOT_HINTS = { "tycoon", "plot", "base", "factory", "island", "zone", "land" }
	local PURCHASE_HINTS = { "button", "buy", "purchase", "upgrade", "unlock", "build", "pad", "dropper", "conveyor" }
	local COLLECTOR_HINTS = { "collect", "collector", "cashout", "cash out", "claim cash", "income", "bank", "deposit", "till" }
	local OWNED_HINTS = { "purchased", "bought", "owned", "completed", "built" }
	local PRICE_NAMES = { cost=true, price=true, amount=true, cash=true, money=true, value=true, required=true, requirement=true }
	local BLOCKED = {
		"watch ad", "watch video", "video ad", "rewarded ad", "rewarded video", "advertisement", "sponsor",
		"starterpack", "starter pack", "gamepass", "game pass", "developer product", "dev product",
		"productid", "product id", "gamepassid", "game pass id", "passid", "pass id", "assetid", "asset id",
		"premium purchase", "premium", "robux", "r$", "rbx", "discord", "twitter",
	}

	local function lower(v) return tostring(v or ""):lower() end
	local function trim(v) return tostring(v or ""):match("^%s*(.-)%s*$") or "" end
	local function hasAny(v, words)
		local text = lower(v)
		for _, word in ipairs(words) do if text:find(word, 1, true) then return true end end
		return false
	end
	local function blockedText(v)
		local text = lower(v)
		for _, phrase in ipairs(BLOCKED) do if text:find(phrase, 1, true) then return true end end
		local tokenised = " " .. text:gsub("[^%w]+", " ") .. " "
		return tokenised:find(" ad ",1,true) ~= nil or tokenised:find(" ads ",1,true) ~= nil
	end
	local function isContainer(o) return o and (o:IsA("Model") or o:IsA("Folder")) end
	local function isInteraction(o) return o and (o:IsA("TouchTransmitter") or o:IsA("ProximityPrompt") or o:IsA("ClickDetector")) end
	local function attrs(o)
		local ok, result = pcall(function() return o:GetAttributes() end)
		return ok and type(result)=="table" and result or nil
	end

	local function parseNumber(v)
		if type(v)=="number" then return v>=0 and v or nil end
		local text = lower(v):gsub(",", ""):gsub("_", " ")
		local scientific = text:match("([%d%.]+e[%+%-]?%d+)")
		if scientific then local n=tonumber(scientific); if n and n>=0 then return n end end
		local numberText, suffix = text:match("([%d]+%.?[%d]*)%s*([kmbtq])")
		if not numberText then numberText=text:match("([%d]+%.?[%d]*)"); suffix="" end
		local n=tonumber(numberText); if not n or n<0 then return nil end
		local mult=1
		if suffix=="k" or text:find("thousand",1,true) then mult=1e3
		elseif suffix=="m" or text:find("million",1,true) then mult=1e6
		elseif suffix=="b" or text:find("billion",1,true) then mult=1e9
		elseif suffix=="t" or text:find("trillion",1,true) then mult=1e12
		elseif suffix=="q" or text:find("quadrillion",1,true) then mult=1e15
		elseif text:find("quintillion",1,true) then mult=1e18 end
		return n*mult
	end
	local function priceName(name)
		local clean=lower(name):gsub("[%s_%-]","")
		return PRICE_NAMES[clean] or clean:find("cost",1,true) or clean:find("price",1,true) or clean:find("require",1,true)
	end
	local function currencyText(text)
		local t=lower(text)
		return t:find("$",1,true) or t:find("£",1,true) or t:find("€",1,true) or t:find("¥",1,true)
			or t:find("cash",1,true) or t:find("money",1,true) or t:find("coin",1,true) or t:find("credit",1,true)
			or t:find("fund",1,true) or t:find("cost",1,true) or t:find("price",1,true) or t:find("require",1,true)
	end
	local function bareNumberText(text)
		local clean=trim(text):lower():gsub(",","")
		return clean~="" and #clean<=24 and not clean:find("%%",1,true)
			and clean:match("^[$£€¥]?%s*[%d%.]+%s*[kmbtq]?%s*$") ~= nil
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
			if currencyText(o.Text) or (allowBare and bareNumberText(o.Text)) then return parseNumber(o.Text) end
		end
		if currencyText(o.Name) then return parseNumber(o.Name) end
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

	local function instanceBlocked(o)
		if not o then return false end
		if blockedText(o.Name) then return true end
		if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then if blockedText(o.Text) then return true end end
		if o:IsA("ProximityPrompt") and (blockedText(o.ActionText) or blockedText(o.ObjectText)) then return true end
		local a=attrs(o)
		if a then
			for key,value in pairs(a) do
				local k=lower(key)
				if blockedText(key) or k:find("productid",1,true) or k:find("gamepass",1,true) or k:find("rewardedad",1,true)
					or (type(value)=="string" and blockedText(value)) then return true end
			end
		end
		return false
	end
	local function blockedAround(o, stopAt)
		local depth=0; local current=o
		while current and current~=workspace and depth<=4 do
			if instanceBlocked(current) then return true end
			if current==stopAt then break end
			current=current.Parent; depth=depth+1
		end
		return false
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
		if isInteraction(o) then return interactionPart(o) end
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

	local function ownerValue(context,value)
		if typeof(value)=="Instance" then return value==context.LOCAL_PLAYER end
		if type(value)=="number" then return tonumber(value)==context.LOCAL_PLAYER.UserId end
		if type(value)=="string" then
			local clean=lower(trim(value))
			return clean==lower(context.LOCAL_PLAYER.Name) or clean==lower(context.LOCAL_PLAYER.DisplayName) or tonumber(clean)==context.LOCAL_PLAYER.UserId
		end
		return false
	end
	local function ownerSignal(context,o)
		local a=attrs(o)
		if a then
			for key,value in pairs(a) do
				local k=lower(key)
				if (k:find("owner",1,true) or k:find("player",1,true) or k:find("userid",1,true)) and ownerValue(context,value) then return true end
			end
		end
		local name=lower(o.Name); local parentName=o.Parent and lower(o.Parent.Name) or ""
		local labelled=name:find("owner",1,true) or parentName:find("owner",1,true) or name=="player" or parentName=="player" or name:find("userid",1,true)
		if o:IsA("ObjectValue") then return labelled and o.Value==context.LOCAL_PLAYER end
		if o:IsA("StringValue") or o:IsA("IntValue") or o:IsA("NumberValue") then return labelled and ownerValue(context,o.Value) end
		if o:IsA("TextLabel") or o:IsA("TextButton") then
			local text=lower(o.Text)
			return text:find(lower(context.LOCAL_PLAYER.Name),1,true) or text:find(lower(context.LOCAL_PLAYER.DisplayName),1,true)
		end
		return false
	end
	local function directChildUnder(o,ancestor)
		local current=o; local previous=o
		while current and current~=ancestor do previous=current; current=current.Parent end
		return current==ancestor and previous or nil
	end
	local function rootDepth(root)
		local n=0; local current=root
		while current and current~=workspace do n=n+1; current=current.Parent end
		return n
	end
	local function nearPrice(interaction,stopAt)
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

	local function worldEvidence(context)
		local descendants=workspace:GetDescendants(); local interactions={}; local owners={}
		for _,o in ipairs(descendants) do
			if isInteraction(o) then table.insert(interactions,o) end
			if ownerSignal(context,o) then table.insert(owners,o) end
		end
		return descendants,interactions,owners
	end
	local function rootCandidates(context,interactions,owners)
		local playerRoot=context.getLocalRoot and context.getLocalRoot(); local playerPos=playerRoot and playerRoot.Position
		local stats={}
		local function stat(root)
			local s=stats[root]
			if not s then s={interactions=0,priced=0,blocked=0,families={},owner=false,nearest=math.huge}; stats[root]=s end
			return s
		end
		for _,interaction in ipairs(interactions) do
			local price=nearPrice(interaction); local isBlocked=blockedAround(interaction)
			local part=interactionPart(interaction); local dist=playerPos and part and (part.Position-playerPos).Magnitude or math.huge
			local current=interaction.Parent; local depth=0
			while current and current~=workspace and depth<MAX_ROOT_DEPTH do
				if isContainer(current) then
					local s=stat(current); s.interactions=s.interactions+1
					if price~=nil then s.priced=s.priced+1 end
					if isBlocked then s.blocked=s.blocked+1 end
					if dist<s.nearest then s.nearest=dist end
					local family=directChildUnder(interaction,current); if family then s.families[family]=(s.families[family] or 0)+1 end
				end
				current=current.Parent; depth=depth+1
			end
		end
		for _,signal in ipairs(owners) do
			local current=signal; local depth=0
			while current and current~=workspace and depth<MAX_ROOT_DEPTH+2 do if stats[current] then stats[current].owner=true end; current=current.Parent; depth=depth+1 end
		end
		local candidates={}
		for root,s in pairs(stats) do
			local maxFamily=0; for _,count in pairs(s.families) do maxFamily=math.max(maxFamily,count) end
			local usable=math.max(0,s.priced-s.blocked)
			local score=(hasAny(root.Name,ROOT_HINTS) and 8 or 0)+math.min(12,s.interactions*0.8)+math.min(22,usable*3)+math.min(14,maxFamily*1.5)
				+(s.nearest<=45 and 18 or (s.nearest<=90 and 8 or 0))-math.min(18,s.blocked*1.5)-math.max(0,2-rootDepth(root))*8+(s.owner and 1000 or 0)
			if score>=ROOT_MIN_SCORE and s.interactions>0 then
				table.insert(candidates,{root=root,rawScore=score,structuralScore=score-(s.owner and 1000 or 0),ownerVerified=s.owner,interactions=s.interactions,priced=usable,maxFamily=maxFamily,nearestDistance=s.nearest})
			end
		end
		local groups={}
		for _,c in ipairs(candidates) do local p=c.root.Parent; if p and p~=workspace then groups[p]=groups[p] or {}; table.insert(groups[p],c) end end
		for _,group in pairs(groups) do
			if #group>=2 then
				local best,second
				for _,c in ipairs(group) do
					if c.structuralScore>=12 and c.priced>=1 then
						if not best or c.nearestDistance<best.nearestDistance then second=best; best=c elseif not second or c.nearestDistance<second.nearestDistance then second=c end
					end
				end
				if best and not best.ownerVerified and best.nearestDistance<=70 and (not second or second.nearestDistance-best.nearestDistance>=18) then best.spatialOwner=true; best.rawScore=best.rawScore+220 end
			end
		end
		table.sort(candidates,function(a,b)
			if a.ownerVerified~=b.ownerVerified then return a.ownerVerified end
			if (a.spatialOwner==true)~=(b.spatialOwner==true) then return a.spatialOwner==true end
			if a.rawScore~=b.rawScore then return a.rawScore>b.rawScore end
			return a.nearestDistance<b.nearestDistance
		end)
		return candidates
	end

	local function ownedArea(host,root)
		local current=host and host.Parent
		while current and current~=root and current~=workspace do if hasAny(current.Name,OWNED_HINTS) then return true end; current=current.Parent end
		return false
	end
	local function hostFor(interaction,root)
		local price,host,depth=nearPrice(interaction,root); if price==nil or not host then return nil,nil,nil end
		local current=interaction.Parent; local d=0
		while current and current~=root and current~=workspace and d<=MAX_PARENT_DEPTH do
			if (current:IsA("Model") or current:IsA("BasePart")) and not blockedAround(current,root) then
				local localPrice=smallTreePrice(current,true); if localPrice~=nil then return current,localPrice,d end
			end
			current=current.Parent; d=d+1
		end
		return host,price,depth
	end
	local function entryName(host,interaction)
		if interaction:IsA("ProximityPrompt") then
			for _,v in ipairs({interaction.ObjectText,interaction.ActionText}) do local t=trim(v); if t~="" and not blockedText(t) and not bareNumberText(t) then return t end end
		end
		local name=host and trim(host.Name) or ""; return name~="" and name or "Purchase"
	end
	local function buttonEntry(data,context,host,interaction,price)
		local touch,prompt,click
		if interaction:IsA("TouchTransmitter") then touch=interactionPart(interaction) elseif interaction:IsA("ProximityPrompt") then prompt=interaction else click=interaction end
		local part=interactionPart(interaction) or referencePart(host); if not touch and not prompt and not click then return nil end
		local cash=tonumber(context.getCash())
		return {object=host,part=part,touchPart=touch,prompt=prompt,clickDetector=click,price=price,affordable=cash~=nil and price<=cash or price==0,locked=cash~=nil and price>cash or false,paidPurchase=false,ownerMatch=data.ownerMatch,ownerVerified=data.ownerVerified,automationAllowed=data.automationAllowed,root=data.root,name=entryName(host,interaction)}
	end
	local function collectorHost(interaction,root)
		local current=interaction.Parent; local depth=0
		while current and current~=workspace and depth<=4 do
			local semantic=hasAny(current.Name,COLLECTOR_HINTS)
			if interaction:IsA("ProximityPrompt") then semantic=semantic or hasAny(interaction.ActionText,COLLECTOR_HINTS) or hasAny(interaction.ObjectText,COLLECTOR_HINTS) end
			if semantic and not blockedAround(current,root) then return current end
			if current==root then break end
			current=current.Parent; depth=depth+1
		end
	end
	local function collectCandidates(root,descendants,data,context)
		local interactions={}; for _,o in ipairs(descendants) do if isInteraction(o) then table.insert(interactions,o) end end
		local records={}; local seen={}
		for _,interaction in ipairs(interactions) do
			if not blockedAround(interaction,root) then
				local host,price,depth=hostFor(interaction,root)
				if host and price~=nil and not ownedArea(host,root) then table.insert(records,{interaction=interaction,host=host,price=price,depth=depth or 0}) end
			else data.paidSkipped=data.paidSkipped+1 end
		end
		local families={}; for _,r in ipairs(records) do local key=r.host.Parent or root; families[key]=(families[key] or 0)+1 end
		table.sort(records,function(a,b) local af=families[a.host.Parent or root] or 0; local bf=families[b.host.Parent or root] or 0; if af~=bf then return af>bf end; if a.depth~=b.depth then return a.depth<b.depth end; return a.price<b.price end)
		for _,r in ipairs(records) do
			if #data.buttons>=context.CONFIG.maxButtons then break end
			if not seen[r.host] then
				local family=families[r.host.Parent or root] or 1; local hinted=hasAny(r.host.Name,PURCHASE_HINTS) or hasAny(r.host.Parent and r.host.Parent.Name or "",PURCHASE_HINTS)
				if family>=2 or hinted or r.price==0 then local entry=buttonEntry(data,context,r.host,r.interaction,r.price); if entry then entry.familySize=family; seen[r.host]=true; table.insert(data.buttons,entry) end end
			end
		end
		local seenCollector={}
		for _,interaction in ipairs(interactions) do
			if #data.drops>=context.CONFIG.maxDrops then break end
			local host=collectorHost(interaction,root)
			if host and not seenCollector[interaction] then
				seenCollector[interaction]=true; local touch,prompt,click
				if interaction:IsA("TouchTransmitter") then touch=interactionPart(interaction) elseif interaction:IsA("ProximityPrompt") then prompt=interaction else click=interaction end
				table.insert(data.drops,{object=host,part=interactionPart(interaction) or referencePart(host),touchPart=touch,prompt=prompt,clickDetector=click,ownerMatch=data.ownerMatch,ownerVerified=data.ownerVerified,automationAllowed=data.automationAllowed,root=data.root,name=host.Name})
			end
		end
	end

	local function refreshCash(context,data)
		local cash=tonumber(context.getCash()); if not data or cash==nil then return data end
		data.cash=cash; local affordable,locked=0,0
		for _,button in ipairs(data.buttons or {}) do
			if not button.paidPurchase and button.object and button.object.Parent then button.affordable=(tonumber(button.price) or math.huge)<=cash; button.locked=not button.affordable; if button.affordable then affordable=affordable+1 else locked=locked+1 end end
		end
		data.affordableCount=affordable; data.lockedCount=locked; return data
	end
	local function scanRoot(context,root,meta,mode)
		local started=os.clock(); local descendants=root:GetDescendants()
		local explicit=meta and meta.ownerVerified==true or ownerSignal(context,root)
		if not explicit then for _,o in ipairs(descendants) do if ownerSignal(context,o) then explicit=true; break end end end
		local spatial=meta and meta.spatialOwner==true; local verified=explicit or spatial; local allowed=verified or context.CONFIG.requireOwnerMatch==false
		local data={root=root,rootName=root.Name,confidence=math.clamp(meta and meta.rawScore or 0,0,100),rootScore=meta and meta.rawScore or 0,structuralScore=meta and meta.structuralScore or 0,ownerMatch=verified,ownerVerified=verified,ownerSource=explicit and "owner" or (spatial and "position-cluster" or "structure"),selectedByPosition=spatial,automationAllowed=allowed,safeAutomation=allowed,buttons={},drops={},cash=tonumber(context.getCash()),owned=verified,maxLabels=context.CONFIG.maxLabels or 16,paidSkipped=0,scanMode=mode or "root",rootInteractions=meta and meta.interactions or 0,rootPriced=meta and meta.priced or 0,rootFamily=meta and meta.maxFamily or 0}
		if allowed then collectCandidates(root,descendants,data,context) end
		local affordable,locked=0,0; for _,b in ipairs(data.buttons) do if b.affordable then affordable=affordable+1 elseif b.locked then locked=locked+1 end end
		table.sort(data.buttons,function(a,b) if a.affordable~=b.affordable then return a.affordable end; if (a.familySize or 0)~=(b.familySize or 0) then return (a.familySize or 0)>(b.familySize or 0) end; return (a.price or math.huge)<(b.price or math.huge) end)
		data.affordableCount=affordable; data.lockedCount=locked; data.totalButtons=#data.buttons; data.progressPercent=0; data.scanTimeMs=(os.clock()-started)*1000
		data.debug={scanMode=data.scanMode,scanTimeMs=data.scanTimeMs,snapshotSize=#descendants,rootScore=data.rootScore,structuralScore=data.structuralScore,ownerSource=data.ownerSource,rootInteractions=data.rootInteractions,rootPriced=data.rootPriced,rootFamily=data.rootFamily,paidSkipped=data.paidSkipped}
		return data
	end
	local function empty(context,elapsed,reason,size)
		return {root=workspace,rootName="Workspace",confidence=0,rootScore=0,structuralScore=0,ownerMatch=false,ownerVerified=false,ownerSource="none",automationAllowed=context.CONFIG.requireOwnerMatch==false,safeAutomation=context.CONFIG.requireOwnerMatch==false,buttons={},drops={},cash=tonumber(context.getCash()),owned=false,maxLabels=context.CONFIG.maxLabels or 16,paidSkipped=0,affordableCount=0,lockedCount=0,totalButtons=0,progressPercent=0,scanMode="structural-discovery",scanTimeMs=elapsed,debug={scanMode="structural-discovery",scanTimeMs=elapsed,reason=reason,snapshotSize=size or 0}}
	end
	local function fullScan(context)
		local now=os.clock(); if lastResult and lastResult.root==workspace and now-lastEmptyScan<EMPTY_SCAN_COOLDOWN then return refreshCash(context,lastResult) end
		local started=os.clock(); local descendants,interactions,owners=worldEvidence(context); local roots=rootCandidates(context,interactions,owners); local selected=roots[1]
		if not selected then knownRoot=nil; knownMeta=nil; lastEmptyScan=now; lastResult=empty(context,(os.clock()-started)*1000,"no-structural-root",#descendants); return lastResult end
		knownRoot=selected.root; knownMeta=selected; lastHeavyScan=now; lastResult=scanRoot(context,knownRoot,knownMeta,"structural-discovery")
		lastResult.debug.worldSnapshotSize=#descendants; lastResult.debug.worldInteractions=#interactions; return lastResult
	end
	local function scan(context)
		local now=os.clock()
		if knownRoot and knownRoot.Parent then
			if lastResult and now-lastHeavyScan<HEAVY_SCAN_COOLDOWN then lastResult.debug.scanMode="cached-throttle"; return refreshCash(context,lastResult) end
			lastHeavyScan=now; lastResult=scanRoot(context,knownRoot,knownMeta or {},"cached-root")
			if lastResult.ownerVerified or context.CONFIG.requireOwnerMatch==false then return lastResult end
			knownRoot=nil; knownMeta=nil
		end
		return fullScan(context)
	end
	local function invalidateRoot(root)
		if not root or root==knownRoot then knownRoot=nil; knownMeta=nil; lastResult=nil; lastHeavyScan=-math.huge; lastEmptyScan=-math.huge end
	end
	return { scan=scan, parseCompactNumber=parseNumber, invalidateRoot=invalidateRoot }
end