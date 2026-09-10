return function(context)
    local CONFIG = context.CONFIG
    local CoreGui = context.CoreGui
    local UserInputService = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")
    local autonomousMode = CONFIG.autopilotEnabled ~= nil

    local callbacks = {}
    local cycleCallbacks = {}
    local actionCallbacks = {}
    local connections = {}
    local controlObjects = {}
    local controlValues = {}
    local infoValues = {}
    local destroyed = false
    local folded = false
    local animating = false
    local currentCategory = "quick"
    local latestPayload = {}
    local lineObjects = {}
    local lineCount = 0
    local previous = {
        bought = 0,
        collected = 0,
        rewards = 0,
        plan = nil,
        owner = nil,
        collectorAttempts = 0,
        collectorConfirmed = 0,
    }
    local lastCollectorWarningAt = -math.huge

    local CYCLES = {
        buyMode = { "Nearest", "Cheapest", "Value" },
        collectMode = { "Nearby", "Tycoon", "Collectors" },
        touchMode = { "Virtual", "Teleport" },
        strategy = { "Fastest", "Income", "Rebirth" },
    }

    local theme = {
        window = Color3.fromRGB(8, 8, 8),
        terminal = Color3.fromRGB(2, 3, 3),
        title = Color3.fromRGB(22, 22, 22),
        titleHover = Color3.fromRGB(35, 35, 35),
        border = Color3.fromRGB(74, 74, 74),
        divider = Color3.fromRGB(39, 43, 42),
        row = Color3.fromRGB(8, 10, 10),
        rowHover = Color3.fromRGB(17, 21, 20),
        text = Color3.fromRGB(229, 232, 230),
        muted = Color3.fromRGB(132, 140, 137),
        accent = Color3.fromRGB(91, 221, 137),
        cyan = Color3.fromRGB(89, 198, 226),
        warning = Color3.fromRGB(238, 193, 84),
        error = Color3.fromRGB(238, 103, 103),
        off = Color3.fromRGB(151, 157, 155),
    }

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    local function create(className, props)
        local object = Instance.new(className)
        for key, value in pairs(props or {}) do
            object[key] = value
        end
        return object
    end

    local function mono(parent, text, size, color, alignment)
        return create("TextLabel", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Enum.Font.Code,
            Text = text or "",
            TextColor3 = color or theme.text,
            TextSize = size or 13,
            TextWrapped = false,
            TextXAlignment = alignment or Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            Parent = parent,
        })
    end

    local function formatNumber(value)
        local n = tonumber(value)
        if not n then return "--" end
        local a = math.abs(n)
        if a >= 1e15 then return string.format("%.2fQ", n / 1e15) end
        if a >= 1e12 then return string.format("%.2fT", n / 1e12) end
        if a >= 1e9 then return string.format("%.2fB", n / 1e9) end
        if a >= 1e6 then return string.format("%.2fM", n / 1e6) end
        if a >= 1e3 then return string.format("%.1fK", n / 1e3) end
        return tostring(math.floor(n + 0.5))
    end

    local function formatDuration(seconds)
        seconds = tonumber(seconds)
        if not seconds or seconds < 0 or seconds == math.huge then return "--" end
        if seconds < 60 then return string.format("%.1fs", seconds) end
        local minutes = math.floor(seconds / 60)
        local remaining = math.floor(seconds % 60)
        if minutes < 60 then return string.format("%dm %02ds", minutes, remaining) end
        return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
    end

    local function shortText(value, maxLength)
        local text = tostring(value or "--")
        if #text <= maxLength then return text end
        return text:sub(1, math.max(1, maxLength - 3)) .. "..."
    end

    local function rootPosition(root)
        if not root or not root.Parent then return nil end
        if root:IsA("BasePart") then return root.Position end
        if root:IsA("Model") then
            local ok, pivot = pcall(function() return root:GetPivot() end)
            if ok and pivot then return pivot.Position end
        end
        local part = root:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    local function playerDistance(data)
        local localRoot = context.getLocalRoot and context.getLocalRoot()
        local plotPosition = data and rootPosition(data.root)
        if not localRoot or not plotPosition then return nil end
        return (localRoot.Position - plotPosition).Magnitude
    end

    local oldGui = CoreGui:FindFirstChild("TycoonCoreGUI")
    if oldGui then oldGui:Destroy() end

    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
    local width = math.min(920, math.max(620, viewport.X - 36))
    local height = math.min(550, math.max(420, viewport.Y - 54))
    if width > viewport.X - 20 then width = math.max(520, viewport.X - 20) end
    if height > viewport.Y - 20 then height = math.max(360, viewport.Y - 20) end

    local fullSize = UDim2.new(0, width, 0, height)
    local foldedSize = UDim2.new(0, width, 0, 31)

    local gui = create("ScreenGui", {
        Name = "TycoonCoreGUI",
        IgnoreGuiInset = false,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 999998,
        Parent = CoreGui,
    })

    local window = create("Frame", {
        Name = "ConsoleWindow",
        Active = true,
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = theme.window,
        BorderColor3 = theme.border,
        BorderSizePixel = 1,
        ClipsDescendants = true,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = fullSize,
        Parent = gui,
    })

    local titleBar = create("Frame", {
        Active = true,
        BackgroundColor3 = theme.title,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 30),
        Parent = window,
    })

    local icon = mono(titleBar, ">_", 13, theme.accent)
    icon.Position = UDim2.new(0, 9, 0, 0)
    icon.Size = UDim2.new(0, 26, 1, 0)

    local title = mono(titleBar, "0xVyrs Tycoon Console.exe", 13, theme.text)
    title.Position = UDim2.new(0, 38, 0, 0)
    title.Size = UDim2.new(1, -150, 1, 0)

    local minimize = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        AutoButtonColor = false,
        BackgroundColor3 = theme.title,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        Position = UDim2.new(1, -42, 0, 0),
        Size = UDim2.new(0, 42, 1, 0),
        Text = "_",
        TextColor3 = theme.text,
        TextSize = 14,
        Parent = titleBar,
    })

    local close = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        AutoButtonColor = false,
        BackgroundColor3 = theme.title,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0, 42, 1, 0),
        Text = "X",
        TextColor3 = theme.text,
        TextSize = 13,
        Parent = titleBar,
    })

    local body = create("Frame", {
        Active = true,
        BackgroundColor3 = theme.terminal,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 4, 0, 34),
        Size = UDim2.new(1, -8, 1, -38),
        Parent = window,
    })

    local statusBar = mono(body, " ENGINE: INITIALISING", 11, theme.muted)
    statusBar.BackgroundColor3 = Color3.fromRGB(13, 14, 14)
    statusBar.BackgroundTransparency = 0
    statusBar.Size = UDim2.new(1, 0, 0, 24)

    local terminalPane = create("Frame", {
        Active = true,
        BackgroundColor3 = theme.terminal,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 25),
        Size = UDim2.new(0.55, -1, 1, -25),
        Parent = body,
    })

    create("Frame", {
        BackgroundColor3 = theme.divider,
        BorderSizePixel = 0,
        Position = UDim2.new(0.55, 0, 0, 25),
        Size = UDim2.new(0, 1, 1, -25),
        Parent = body,
    })

    local controlsPane = create("Frame", {
        Active = true,
        BackgroundColor3 = Color3.fromRGB(5, 6, 6),
        BorderSizePixel = 0,
        Position = UDim2.new(0.55, 1, 0, 25),
        Size = UDim2.new(0.45, -1, 1, -25),
        Parent = body,
    })

    local output = create("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.terminal,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        Position = UDim2.new(0, 8, 0, 6),
        ScrollBarImageColor3 = theme.border,
        ScrollBarThickness = 4,
        Size = UDim2.new(1, -16, 1, -52),
        Parent = terminalPane,
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 1),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = output,
    })

    local inputRow = create("Frame", {
        Active = true,
        BackgroundColor3 = theme.terminal,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 8, 1, -40),
        Size = UDim2.new(1, -16, 0, 34),
        Parent = terminalPane,
    })

    local prompt = mono(inputRow, "C:\\0xVyrs\\Tycoon>", 13, theme.accent)
    prompt.Size = UDim2.new(0, 138, 1, 0)

    local input = create("TextBox", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Font = Enum.Font.Code,
        MultiLine = false,
        PlaceholderText = "type 'help' for commands",
        PlaceholderColor3 = Color3.fromRGB(88, 94, 92),
        Position = UDim2.new(0, 142, 0, 0),
        Size = UDim2.new(1, -142, 1, 0),
        Text = "",
        TextColor3 = theme.text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = inputRow,
    })

    local controlsHeader = mono(controlsPane, " QUICK CONTROLS", 12, theme.cyan)
    controlsHeader.Position = UDim2.new(0, 8, 0, 3)
    controlsHeader.Size = UDim2.new(1, -16, 0, 20)

    local categoryBar = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 8, 0, 25),
        Size = UDim2.new(1, -16, 0, 50),
        Parent = controlsPane,
    })

    local controlsScroll = create("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        Position = UDim2.new(0, 8, 0, 79),
        ScrollBarImageColor3 = theme.border,
        ScrollBarThickness = 4,
        Size = UDim2.new(1, -16, 1, -87),
        Parent = controlsPane,
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = controlsScroll,
    })

    local function scrollBottom()
        task.defer(function()
            if output and output.Parent then
                output.CanvasPosition = Vector2.new(0, math.max(0, output.AbsoluteCanvasSize.Y - output.AbsoluteSize.Y))
            end
        end)
    end

    local function writeLine(text, color)
        lineCount = lineCount + 1
        local line = mono(output, tostring(text or ""), 13, color or theme.text)
        line.AutomaticSize = Enum.AutomaticSize.Y
        line.Size = UDim2.new(1, -8, 0, 18)
        line.TextWrapped = true
        line.TextYAlignment = Enum.TextYAlignment.Top
        line.LayoutOrder = lineCount
        table.insert(lineObjects, line)
        if #lineObjects > 160 then
            local first = table.remove(lineObjects, 1)
            if first then first:Destroy() end
        end
        scrollBottom()
        return line
    end

    local function clearOutput()
        for _, line in ipairs(lineObjects) do
            if line then line:Destroy() end
        end
        lineObjects = {}
    end

    local function clearControls()
        for _, object in ipairs(controlObjects) do
            if object and object.Parent then object:Destroy() end
        end
        controlObjects = {}
        controlValues = {}
        infoValues = {}
    end

    local function trackControl(object)
        table.insert(controlObjects, object)
        return object
    end

    local function addHeading(text)
        local heading = trackControl(mono(controlsScroll, "[ " .. text .. " ]", 11, theme.cyan))
        heading.Size = UDim2.new(1, -4, 0, 24)
        return heading
    end

    local function configValueText(key)
        local value = CONFIG[key]
        if type(value) == "boolean" then
            return value and "[ ON ]" or "[ OFF ]"
        end
        return "[ " .. tostring(value) .. " ]"
    end

    local function applyToggle(key, value)
        if CONFIG[key] == nil then return false end
        CONFIG[key] = value == true
        if callbacks[key] then
            callbacks[key](CONFIG[key])
        elseif context.saveSettings then
            context.saveSettings()
        end
        return true
    end

    local function applyCycle(key, value)
        if CONFIG[key] == nil then return false end
        CONFIG[key] = value
        if cycleCallbacks[key] then
            cycleCallbacks[key](value)
        elseif context.saveSettings then
            context.saveSettings()
        end
        return true
    end

    local function addToggle(key, labelText)
        local row = trackControl(create("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = theme.row,
            BorderSizePixel = 0,
            Font = Enum.Font.Code,
            Size = UDim2.new(1, -4, 0, 29),
            Text = "  " .. labelText,
            TextColor3 = theme.text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = controlsScroll,
        }))
        local value = mono(row, configValueText(key), 11, CONFIG[key] and theme.accent or theme.off, Enum.TextXAlignment.Right)
        value.AnchorPoint = Vector2.new(1, 0)
        value.Position = UDim2.new(1, -8, 0, 0)
        value.Size = UDim2.new(0, 105, 1, 0)
        controlValues[key] = value
        connect(row.MouseEnter, function() if row.Parent then row.BackgroundColor3 = theme.rowHover end end)
        connect(row.MouseLeave, function() if row.Parent then row.BackgroundColor3 = theme.row end end)
        connect(row.MouseButton1Click, function() applyToggle(key, not CONFIG[key]) end)
        return row
    end

    local function addCycle(key, labelText)
        local row = trackControl(create("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = theme.row,
            BorderSizePixel = 0,
            Font = Enum.Font.Code,
            Size = UDim2.new(1, -4, 0, 29),
            Text = "  " .. labelText,
            TextColor3 = theme.text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = controlsScroll,
        }))
        local value = mono(row, configValueText(key), 11, theme.cyan, Enum.TextXAlignment.Right)
        value.AnchorPoint = Vector2.new(1, 0)
        value.Position = UDim2.new(1, -8, 0, 0)
        value.Size = UDim2.new(0, 155, 1, 0)
        controlValues[key] = value
        connect(row.MouseEnter, function() if row.Parent then row.BackgroundColor3 = theme.rowHover end end)
        connect(row.MouseLeave, function() if row.Parent then row.BackgroundColor3 = theme.row end end)
        connect(row.MouseButton1Click, function()
            local values = CYCLES[key] or {}
            if #values == 0 then return end
            local nextIndex = 1
            for index, item in ipairs(values) do
                if item == CONFIG[key] then nextIndex = (index % #values) + 1 break end
            end
            applyCycle(key, values[nextIndex])
        end)
        return row
    end

    local function addAction(labelText, key, danger)
        local row = trackControl(create("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = theme.row,
            BorderSizePixel = 0,
            Font = Enum.Font.Code,
            Size = UDim2.new(1, -4, 0, 29),
            Text = "  > " .. labelText,
            TextColor3 = danger and theme.error or theme.accent,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = controlsScroll,
        }))
        connect(row.MouseEnter, function() if row.Parent then row.BackgroundColor3 = theme.rowHover end end)
        connect(row.MouseLeave, function() if row.Parent then row.BackgroundColor3 = theme.row end end)
        connect(row.MouseButton1Click, function() if actionCallbacks[key] then actionCallbacks[key]() end end)
        return row
    end

    local function addInfo(key, labelText)
        local row = trackControl(create("Frame", {
            BackgroundColor3 = theme.row,
            BorderSizePixel = 0,
            Size = UDim2.new(1, -4, 0, 27),
            Parent = controlsScroll,
        }))
        local left = mono(row, "  " .. labelText, 11, theme.muted)
        left.Size = UDim2.new(0.48, 0, 1, 0)
        local right = mono(row, "--", 11, theme.text, Enum.TextXAlignment.Right)
        right.Position = UDim2.new(0.48, 0, 0, 0)
        right.Size = UDim2.new(0.52, -8, 1, 0)
        infoValues[key] = right
        return row
    end

    local categoryButtons = {}
    local categories = autonomousMode and {
        { key = "quick", text = "QUICK" },
        { key = "brain", text = "BRAIN" },
        { key = "world", text = "WORLD" },
        { key = "diag", text = "DIAG" },
    } or {
        { key = "quick", text = "QUICK" },
        { key = "world", text = "WORLD" },
        { key = "diag", text = "DIAG" },
    }

    local function renderCategory(category)
        currentCategory = category
        clearControls()
        for key, button in pairs(categoryButtons) do
            local active = key == category
            button.TextColor3 = active and theme.accent or theme.muted
            button.BackgroundColor3 = active and theme.rowHover or theme.terminal
        end

        if category == "quick" then
            addHeading("AUTOMATION")
            addToggle("enabled", "SYSTEM")
            addToggle("autoBuy", "AUTO BUY")
            addToggle("autoCollect", "AUTO COLLECT")
            if autonomousMode then addCycle("strategy", "STRATEGY") end
            if autonomousMode then
                addHeading("RUN")
                addAction("START RUN", "start", false)
                addAction("STOP", "stop", true)
            end
        elseif category == "brain" and autonomousMode then
            addHeading("SPEEDRUN BRAIN")
            addToggle("autopilotEnabled", "AUTOPILOT")
            addToggle("learningEnabled", "LEARNING")
            addToggle("burstMode", "HYPER BUY")
            addToggle("autoRewards", "FREE REWARDS")
            addToggle("autoRebirth", "AUTO REBIRTH")
            addCycle("strategy", "STRATEGY")
            addHeading("LEARNING")
            addAction("RESET LEARNED ROUTE", "resetLearning", true)
        elseif category == "world" then
            addHeading("WORLD HUD")
            addToggle("highlightAffordable", "HIGHLIGHTS")
            addToggle("showWaypoint", "TARGET MARKER")
            addToggle("showLabels", "PURCHASE LABELS")
            addHeading("INTERACTION")
            addCycle("collectMode", "COLLECT MODE")
            addCycle("buyMode", "BUY MODE")
            if not autonomousMode then addCycle("touchMode", "TOUCH MODE") end
            addHeading("SAFETY")
            addToggle("requireOwnerMatch", "OWNER SAFE")
            if CONFIG.autoLoadGamePreset ~= nil then addToggle("autoLoadGamePreset", "GAME PROFILE") end
        elseif category == "diag" then
            addHeading("TYCOON")
            addInfo("root", "ROOT")
            addInfo("owner", "OWNER")
            addInfo("distance", "DISTANCE")
            addInfo("buttons", "BUTTONS")
            addInfo("collectors", "COLLECTORS")
            addInfo("affordable", "AFFORDABLE")
            addHeading("RUNTIME")
            addInfo("scan", "SCAN")
            addInfo("cash", "CASH")
            addInfo("cpm", "CASH/MIN")
            if autonomousMode then
                addInfo("plan", "TARGET")
                addInfo("bottleneck", "BOTTLENECK")
                addInfo("learning", "LEARNED")
                addHeading("COLLECTOR HEALTH")
                addInfo("collectAttempts", "ATTEMPTS")
                addInfo("collectConfirmed", "CASH CONFIRMED")
                addInfo("collectRetries", "LIMB RETRIES")
                addInfo("collectFallbacks", "ROOT FALLBACKS")
                addInfo("collectStale", "STALE REFRESH")
                addInfo("collectFailed", "FAILED")
            end
        end
    end

    local buttonWidth = 76
    for index, item in ipairs(categories) do
        local x = (index - 1) * (buttonWidth + 3)
        local button = create("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = theme.terminal,
            BorderColor3 = theme.divider,
            BorderSizePixel = 1,
            Font = Enum.Font.Code,
            Position = UDim2.new(0, x, 0, 0),
            Size = UDim2.new(0, buttonWidth, 0, 22),
            Text = item.text,
            TextColor3 = theme.muted,
            TextSize = 10,
            Parent = categoryBar,
        })
        categoryButtons[item.key] = button
        connect(button.MouseButton1Click, function() renderCategory(item.key) end)
    end

    local function setInfo(key, text, color)
        local item = infoValues[key]
        if item then item.Text = tostring(text or "--") item.TextColor3 = color or theme.text end
    end

    local function syncControlValues()
        for key, item in pairs(controlValues) do
            item.Text = configValueText(key)
            if type(CONFIG[key]) == "boolean" then item.TextColor3 = CONFIG[key] and theme.accent or theme.off else item.TextColor3 = theme.cyan end
        end
    end

    local function updateDiagnostics(payload)
        local data = payload.data or {}
        local stats = payload.stats or {}
        local auto = payload.autonomous or {}
        local brain = auto.brain or {}
        local collector = auto.collector or {}
        local debugInfo = data.debug or {}
        local distance = playerDistance(data)

        setInfo("root", shortText(data.rootName or auto.root or "--", 23))
        setInfo("owner", data.ownerVerified and "VERIFIED" or "NO", data.ownerVerified and theme.accent or theme.warning)
        setInfo("distance", distance and string.format("%.0f studs", distance) or "--", distance and distance > (CONFIG.collectRange or 90) and theme.warning or theme.text)
        setInfo("buttons", tostring(data.totalButtons or #(data.buttons or {})))
        setInfo("collectors", tostring(#(data.drops or {})))
        setInfo("affordable", tostring(data.affordableCount or 0))
        local scanMode = debugInfo.scanMode or "--"
        local scanMs = tonumber(debugInfo.scanTimeMs)
        setInfo("scan", scanMs and string.format("%s / %.1fms", scanMode, scanMs) or scanMode)
        setInfo("cash", "$" .. formatNumber(data.cash or auto.cash or stats.cash))
        setInfo("cpm", "$" .. formatNumber(stats.cashPerMinute or 0))
        setInfo("plan", brain.plan and shortText(brain.plan.name, 20) or "WAITING")
        setInfo("bottleneck", shortText(brain.bottleneck or "--", 20))
        setInfo("learning", string.format("%d nodes / %d links", brain.learnedNodes or 0, brain.learnedEdges or 0))
        setInfo("collectAttempts", tostring(collector.attempts or 0))
        setInfo("collectConfirmed", tostring(collector.cashConfirmed or 0), theme.accent)
        setInfo("collectRetries", tostring(collector.actorRetries or 0))
        setInfo("collectFallbacks", tostring(collector.rootFallbacks or 0))
        setInfo("collectStale", tostring(collector.staleRefreshes or 0))
        setInfo("collectFailed", tostring(collector.failed or 0), (collector.failed or 0) > 0 and theme.warning or theme.text)
    end

    local function updateFeed(payload)
        local data = payload.data or {}
        local auto = payload.autonomous or {}
        local brain = auto.brain or {}
        local collector = auto.collector or {}
        local bought = tonumber(auto.bought or payload.bought) or 0
        local collected = tonumber(auto.collected or payload.collected) or 0
        local rewards = tonumber(auto.rewardsActivated) or 0
        local planName = brain.plan and brain.plan.name or nil
        local owner = data.ownerVerified == true

        if previous.owner ~= nil and previous.owner ~= owner then writeLine(owner and "[owner] verification acquired" or "[owner] verification lost", owner and theme.accent or theme.warning) end
        if bought > previous.bought then writeLine(string.format("[buy] purchase confirmed // total=%d", bought), theme.accent) end
        if rewards > previous.rewards then writeLine(string.format("[reward] free reward activated // total=%d", rewards), theme.cyan) end
        if planName and planName ~= previous.plan then writeLine("[brain] target -> " .. shortText(planName, 48), theme.cyan) end
        if collected >= previous.collected + 10 then writeLine(string.format("[collect] activations=%d", collected), theme.muted) previous.collected = collected end

        local attempts = tonumber(collector.attempts) or 0
        local confirmed = tonumber(collector.cashConfirmed) or 0
        local distance = playerDistance(data)
        if attempts >= previous.collectorAttempts + 8 and confirmed <= previous.collectorConfirmed and CONFIG.autoCollect then
            local now = os.clock()
            if now - lastCollectorWarningAt >= 5 then
                lastCollectorWarningAt = now
                local suffix = distance and string.format(" // %.0f studs from plot", distance) or ""
                writeLine("[collector] touch fired but cash not confirmed" .. suffix, theme.warning)
            end
        end

        previous.bought = bought
        previous.rewards = rewards
        previous.plan = planName
        previous.owner = owner
        previous.collectorAttempts = attempts
        previous.collectorConfirmed = confirmed
    end

    local function engineStatus(payload)
        local data = payload.data or {}
        local stats = payload.stats or {}
        local auto = payload.autonomous or {}
        local brain = auto.brain or {}
        local state
        local color
        if not CONFIG.enabled then state = "OFFLINE" color = theme.muted
        elseif data.ownerVerified then state = autonomousMode and "AUTONOMOUS" or "READY" color = theme.accent
        elseif CONFIG.requireOwnerMatch then state = "OWNER BLOCKED" color = theme.error
        else state = "RELAXED" color = theme.warning end
        local target = brain.plan and shortText(brain.plan.name, 25) or "waiting"
        statusBar.Text = string.format(" ENGINE: %s  |  CASH: $%s  |  RATE: $%s/min  |  STRATEGY: %s  |  TARGET: %s", state, formatNumber(data.cash or auto.cash or stats.cash), formatNumber(stats.cashPerMinute or 0), tostring(auto.strategy or CONFIG.strategy or "--"), target)
        statusBar.TextColor3 = color
    end

    local function printStatus()
        local payload = latestPayload or {}
        local data = payload.data or {}
        local stats = payload.stats or {}
        local auto = payload.autonomous or {}
        local brain = auto.brain or {}
        local collector = auto.collector or {}
        writeLine("--- TYCOON STATUS ---", theme.cyan)
        writeLine("root        : " .. tostring(data.rootName or auto.root or "--"))
        writeLine("owner       : " .. (data.ownerVerified and "VERIFIED" or "NO"), data.ownerVerified and theme.accent or theme.warning)
        writeLine("cash        : $" .. formatNumber(data.cash or auto.cash or stats.cash))
        writeLine("cash/min    : $" .. formatNumber(stats.cashPerMinute or 0))
        writeLine("buttons     : " .. tostring(data.totalButtons or 0) .. " // affordable=" .. tostring(data.affordableCount or 0))
        if autonomousMode then
            writeLine("strategy    : " .. tostring(auto.strategy or CONFIG.strategy))
            writeLine("target      : " .. tostring(brain.plan and brain.plan.name or "waiting"))
            writeLine("bottleneck  : " .. tostring(brain.bottleneck or "--"))
            writeLine("eta         : " .. formatDuration(brain.etaSeconds))
            writeLine("collector   : attempts=" .. tostring(collector.attempts or 0) .. " confirmed=" .. tostring(collector.cashConfirmed or 0))
        end
    end

    local function parseBool(value)
        value = string.lower(tostring(value or ""))
        if value == "on" or value == "true" or value == "1" or value == "yes" then return true end
        if value == "off" or value == "false" or value == "0" or value == "no" then return false end
        return nil
    end

    local function executeCommand(raw)
        local text = tostring(raw or "")
        text = text:match("^%s*(.-)%s*$") or ""
        if text == "" then return end
        writeLine("C:\\0xVyrs\\Tycoon> " .. text, theme.text)
        local args = {}
        for token in text:gmatch("%S+") do table.insert(args, token) end
        local command = string.lower(args[1] or "")

        if command == "help" then
            writeLine("commands: status | start | stop | clear | hide", theme.cyan)
            writeLine("strategy <fastest|income|rebirth>", theme.cyan)
            writeLine("set <key> <on|off> | toggle <key> | reset", theme.cyan)
            writeLine("keys: autobuy autocollect learning burst rewards autorebirth labels waypoint highlights owner", theme.muted)
        elseif command == "status" then printStatus()
        elseif command == "start" then if actionCallbacks.start then actionCallbacks.start() else applyToggle("enabled", true) end writeLine("autonomous run started", theme.accent)
        elseif command == "stop" then if actionCallbacks.stop then actionCallbacks.stop() else applyToggle("enabled", false) end writeLine("automation stopped", theme.warning)
        elseif command == "clear" then clearOutput()
        elseif command == "hide" then gui.Enabled = false
        elseif command == "reset" then
            if actionCallbacks.resetLearning then actionCallbacks.resetLearning() writeLine("learned route reset", theme.warning) else writeLine("reset unavailable in this runtime", theme.error) end
        elseif command == "strategy" then
            local wanted = string.lower(args[2] or "")
            local map = { fastest = "Fastest", income = "Income", rebirth = "Rebirth" }
            if map[wanted] and applyCycle("strategy", map[wanted]) then writeLine("strategy -> " .. map[wanted], theme.accent) else writeLine("expected: fastest | income | rebirth", theme.error) end
        elseif command == "toggle" or command == "set" then
            local aliases = {
                system = "enabled", enabled = "enabled", autobuy = "autoBuy", autocollect = "autoCollect",
                autopilot = "autopilotEnabled", learning = "learningEnabled", burst = "burstMode", rewards = "autoRewards", autorebirth = "autoRebirth",
                labels = "showLabels", waypoint = "showWaypoint", highlights = "highlightAffordable", owner = "requireOwnerMatch",
            }
            local key = aliases[string.lower(args[2] or "")]
            if not key or CONFIG[key] == nil then writeLine("unknown setting", theme.error)
            elseif command == "toggle" then applyToggle(key, not CONFIG[key]) writeLine(key .. " -> " .. tostring(CONFIG[key]), CONFIG[key] and theme.accent or theme.warning)
            else
                if type(CONFIG[key]) == "boolean" then
                    local value = parseBool(args[3])
                    if value == nil then writeLine("expected on/off", theme.error) else applyToggle(key, value) writeLine(key .. " -> " .. tostring(value), value and theme.accent or theme.warning) end
                else writeLine("setting is not boolean", theme.error) end
            end
        else writeLine("unknown command // type 'help'", theme.error) end
        syncControlValues()
    end

    connect(input.FocusLost, function(enterPressed)
        if not enterPressed then return end
        local text = input.Text
        input.Text = ""
        executeCommand(text)
    end)

    local function tweenWindow(size, duration, direction)
        local tween = TweenService:Create(window, TweenInfo.new(duration, Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), { Size = size })
        tween:Play()
        return tween
    end

    local function setFolded(value)
        if animating or folded == value then return end
        animating = true
        if value then
            local tween = tweenWindow(foldedSize, 0.11, Enum.EasingDirection.In)
            tween.Completed:Wait()
            folded = true
            body.Visible = false
            minimize.Text = "□"
        else
            body.Visible = true
            local tween = tweenWindow(fullSize, 0.12, Enum.EasingDirection.Out)
            tween.Completed:Wait()
            folded = false
            minimize.Text = "_"
        end
        animating = false
    end

    connect(minimize.MouseButton1Click, function() task.spawn(function() setFolded(not folded) end) end)
    connect(minimize.MouseEnter, function() minimize.BackgroundColor3 = theme.titleHover end)
    connect(minimize.MouseLeave, function() minimize.BackgroundColor3 = theme.title end)
    connect(close.MouseEnter, function() close.BackgroundColor3 = Color3.fromRGB(170, 45, 45) end)
    connect(close.MouseLeave, function() close.BackgroundColor3 = theme.title end)
    connect(close.MouseButton1Click, function() gui.Enabled = false end)

    connect(UserInputService.InputBegan, function(inputObject, processed)
        if processed then return end
        if inputObject.KeyCode == Enum.KeyCode.RightShift then gui.Enabled = not gui.Enabled end
    end)

    local dragging = false
    local dragStart
    local startPosition
    connect(titleBar.InputBegan, function(inputObject)
        if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 and inputObject.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging = true
        dragStart = inputObject.Position
        startPosition = window.Position
        local endConnection
        endConnection = inputObject.Changed:Connect(function()
            if inputObject.UserInputState == Enum.UserInputState.End then dragging = false if endConnection then endConnection:Disconnect() end end
        end)
    end)
    connect(UserInputService.InputChanged, function(inputObject)
        if not dragging then return end
        if inputObject.UserInputType ~= Enum.UserInputType.MouseMovement and inputObject.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = inputObject.Position - dragStart
        window.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
    end)

    local function update(payload)
        if destroyed then return end
        latestPayload = payload or latestPayload
        syncControlValues()
        updateDiagnostics(latestPayload)
        updateFeed(latestPayload)
        engineStatus(latestPayload)
    end

    local function destroy()
        if destroyed then return end
        destroyed = true
        for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
        connections = {}
        if gui then gui:Destroy() end
    end

    renderCategory("quick")
    writeLine("0xVyrs Tycoon Autonomous Console", theme.accent)
    writeLine("runtime interface: .exe terminal mode", theme.cyan)
    writeLine("type 'help' for commands", theme.muted)

    return {
        onToggle = function(key, callback) callbacks[key] = callback end,
        onCycle = function(key, callback) cycleCallbacks[key] = callback end,
        onAction = function(key, callback) actionCallbacks[key] = callback end,
        update = update,
        destroy = destroy,
    }
end
