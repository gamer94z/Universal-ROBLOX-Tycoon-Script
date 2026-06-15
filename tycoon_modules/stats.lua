return function(context)
	local state = {
		lastCash = context.getCash() or 0,
		lastAt = os.clock(),
		samples = {},
		cashPerMinute = 0,
	}

	local function update()
		local now = os.clock()
		local cash = context.getCash() or state.lastCash
		local elapsed = math.max(0.01, now - state.lastAt)
		local delta = cash - state.lastCash

		if elapsed >= 1 then
			table.insert(state.samples, {
				at = now,
				rate = (delta / elapsed) * 60,
			})
			state.lastCash = cash
			state.lastAt = now
		end

		local total = 0
		local count = 0
		for index = #state.samples, 1, -1 do
			local sample = state.samples[index]
			if now - sample.at > 60 then
				table.remove(state.samples, index)
			else
				total = total + sample.rate
				count = count + 1
			end
		end
		state.cashPerMinute = count > 0 and (total / count) or 0
	end

	local function get()
		return {
			cash = context.getCash() or 0,
			cashPerMinute = math.max(0, math.floor(state.cashPerMinute + 0.5)),
		}
	end

	return {
		update = update,
		get = get,
	}
end
