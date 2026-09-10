return function(context)
	local state = {
		hasBaseline = false,
		lastCash = nil,
		lastSource = nil,
		lastAt = os.clock(),
		samples = {},
		cashPerMinute = 0,
		peakCashPerMinute = 0,
		pendingSpend = 0,
		totalSpend = 0,
		totalPositiveIncome = 0,
	}

	local function sourceKey()
		if type(context.getCashSourceKey) ~= "function" then return nil end
		local ok, value = pcall(context.getCashSourceKey)
		return ok and value or nil
	end

	local function resetBaseline(cash, source, now)
		state.hasBaseline = cash ~= nil
		state.lastCash = cash
		state.lastSource = source
		state.lastAt = now or os.clock()
		state.pendingSpend = 0
	end

	local function noteSpend(amount)
		amount = tonumber(amount)
		if not amount or amount <= 0 then return end
		state.pendingSpend = state.pendingSpend + amount
		state.totalSpend = state.totalSpend + amount
	end

	local function update()
		local now = os.clock()
		local cash = tonumber(context.getCash())
		if cash == nil then return end
		local source = sourceKey()

		if not state.hasBaseline or (source and state.lastSource and source ~= state.lastSource) then
			resetBaseline(cash, source, now)
			return
		end

		local elapsed = math.max(0.01, now - state.lastAt)
		if elapsed < 0.75 then return end

		local rawDelta = cash - (state.lastCash or cash)
		local adjustedDelta = rawDelta + state.pendingSpend
		state.pendingSpend = 0
		local positiveDelta = math.max(0, adjustedDelta)
		state.totalPositiveIncome = state.totalPositiveIncome + positiveDelta
		table.insert(state.samples, { at = now, rate = (positiveDelta / elapsed) * 60 })

		state.lastCash = cash
		state.lastSource = source or state.lastSource
		state.lastAt = now

		local weightedTotal, weightTotal = 0, 0
		for index = #state.samples, 1, -1 do
			local sample = state.samples[index]
			local age = now - sample.at
			if age > 45 then
				table.remove(state.samples, index)
			else
				local weight = age <= 8 and 3 or (age <= 20 and 2 or 1)
				weightedTotal = weightedTotal + sample.rate * weight
				weightTotal = weightTotal + weight
			end
		end
		state.cashPerMinute = weightTotal > 0 and (weightedTotal / weightTotal) or 0
		state.peakCashPerMinute = math.max(state.peakCashPerMinute, state.cashPerMinute)
	end

	local function get()
		local cash = tonumber(context.getCash())
		return {
			cash = cash or state.lastCash or 0,
			cashPerMinute = math.max(0, math.floor(state.cashPerMinute + 0.5)),
			peakCashPerMinute = math.max(0, math.floor(state.peakCashPerMinute + 0.5)),
			totalSpend = state.totalSpend,
			totalPositiveIncome = state.totalPositiveIncome,
			hasBaseline = state.hasBaseline,
		}
	end

	return {
		update = update,
		get = get,
		noteSpend = noteSpend,
		resetBaseline = function()
			resetBaseline(tonumber(context.getCash()), sourceKey(), os.clock())
		end,
	}
end
