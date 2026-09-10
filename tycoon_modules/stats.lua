return function(context)
	local state = {
		lastCash = context.getCash() or 0,
		lastAt = os.clock(),
		samples = {},
		cashPerMinute = 0,
		peakCashPerMinute = 0,
		pendingSpend = 0,
		totalSpend = 0,
		totalPositiveIncome = 0,
	}

	local function noteSpend(amount)
		amount = tonumber(amount)
		if not amount or amount <= 0 then
			return
		end
		state.pendingSpend = state.pendingSpend + amount
		state.totalSpend = state.totalSpend + amount
	end

	local function update()
		local now = os.clock()
		local cash = context.getCash()
		if cash == nil then
			cash = state.lastCash
		end

		local elapsed = math.max(0.01, now - state.lastAt)
		if elapsed < 0.75 then
			return
		end

		-- Purchases are real cash outflow, not negative production. Add known
		-- purchase spend back before estimating the economy's earning rate.
		local rawDelta = cash - state.lastCash
		local adjustedDelta = rawDelta + state.pendingSpend
		state.pendingSpend = 0

		local positiveDelta = math.max(0, adjustedDelta)
		state.totalPositiveIncome = state.totalPositiveIncome + positiveDelta
		table.insert(state.samples, {
			at = now,
			rate = (positiveDelta / elapsed) * 60,
		})

		state.lastCash = cash
		state.lastAt = now

		local weightedTotal = 0
		local weightTotal = 0
		for index = #state.samples, 1, -1 do
			local sample = state.samples[index]
			local age = now - sample.at
			if age > 45 then
				table.remove(state.samples, index)
			else
				-- Recent samples matter more so ROI changes become visible quickly.
				local weight = age <= 8 and 3 or (age <= 20 and 2 or 1)
				weightedTotal = weightedTotal + sample.rate * weight
				weightTotal = weightTotal + weight
			end
		end

		state.cashPerMinute = weightTotal > 0 and (weightedTotal / weightTotal) or 0
		state.peakCashPerMinute = math.max(state.peakCashPerMinute, state.cashPerMinute)
	end

	local function get()
		return {
			cash = context.getCash() or 0,
			cashPerMinute = math.max(0, math.floor(state.cashPerMinute + 0.5)),
			peakCashPerMinute = math.max(0, math.floor(state.peakCashPerMinute + 0.5)),
			totalSpend = state.totalSpend,
			totalPositiveIncome = state.totalPositiveIncome,
		}
	end

	return {
		update = update,
		get = get,
		noteSpend = noteSpend,
	}
end
