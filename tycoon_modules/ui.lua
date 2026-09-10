return function(context)
    local CONFIG = context.CONFIG
    local CoreGui = context.CoreGui
    local UserInputService = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")
    local GuiService = game:GetService("GuiService")
    local autonomousMode = CONFIG.autopilotEnabled ~= nil

    local callbacks = {}
    local cycleCallbacks = {}
    local actionCallbacks = {}
    local connections = {}
    local controlObjects = {}
    local controlValues = {}
    local infoValues = {}
    local lineObjects = {}
    local latestPayload = {}
    local destroyed = false
    local folded = false
    local animating = false
    local activeCategory = "quick"
    local lineCount = 0

    local CYCLES = {
        buyMode = { "Nearest", "Cheapest", "Value" },
        collectMode = { "Nearby", "Tycoon", "Collectors" },
        touchMode = { "Virtual", "Teleport" },
        strategy = { "Fastest", "Income", "Rebirth" },
    }

    local THEME = {
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

    local function mono(parent, text, size, colour, alignment)
        return create("TextLabel", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Enum.Font.Code,
            Text = text or "",
            TextColor3 = colour or THEME.text,
            TextSize = size or 13,
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

    local function shortText(value, maxLength)
        local text = tostring(value or "--")
        if #text <= maxLength then return text end
        return text:sub(1, math.max(1, maxLength - 3)) .. "..."
    end

    local oldGui = CoreGui:FindFirstChild("TycoonCoreGUI")
    if oldGui then oldGui:Destroy() end

    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
    local width = math.min(920, math.max(620, viewport.X - 36))
    local height = math.min(550, math.max(420, viewport.Y - 54))
    width = math.min(width, math.max(520, viewport.X - 20))
    height = math.min(height, math.max(360, viewport.Y - 20))

    local initialX = math.clamp(tonumber(CONFIG.uiOffsetX) or math.floor((viewport.X - width) / 2), 0, math.max(0, viewport.X - width))
    local initialY = math.clamp(tonumber(CONFIG.uiOffsetY) or math.floor((viewport.Y - height) / 2), 0, math.max(0, viewport.Y - height))
    local fullSize = UDim2.fromOffset(width, height)
    local foldedSize = UDim2.fromOffset(width, 31)

    local gui = create("ScreenGui", {
        Name = "TycoonCoreGUI",
        IgnoreGuiInset = false,
        ResetOnSpawn = false,
        DisplayOrder = 999998,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = CoreGui,
    })

    local window = create("Frame", {
        Name = "ConsoleWindow",
        Active = true,
        BackgroundColor3 = THEME.window,
        BorderColor3 = THEME.border,
        BorderSizePixel = 1,
        ClipsDescendants = true,
        Position = UDim2.fromOffset(initialX, initialY),
        Size = fullSize,
        Parent = gui,
    })

    local titleBar = create("Frame", {
        Active = true,
        BackgroundColor3 = THEME.title,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 30),
        Parent = window,
    })

    local icon = mono(titleBar, ">_", 13, THEME.accent)
    icon.Position = UDim2.fromOffset(9, 0)
    icon.Size = UDim2.fromOffset(26, 30)

    local title = mono(titleBar, "0xVyrs Tycoon Console.exe  //  v" .. tostring(CONFIG.version), 13, THEME.text)
    title.Position = UDim2.fromOffset(38, 0)
    title.Size = UDim2.new(1, -150, 1, 0)

    local minimise = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        AutoButtonColor = false,
        BackgroundColor3 = THEME.title,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        Position = UDim2.new(1, -42, 0, 0),
        Size = UDim2.fromOffset(42, 30),
        Text = "_",
        TextColor3 = THEME.text,
        TextSize = 14,
        Parent = titleBar,
    })

    local close = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        AutoButtonColor = false,
        BackgroundColor3 = THEME.title,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(42, 30),
        Text = "X",
        TextColor3 = THEME.text,
        TextSize = 13,
        Parent = titleBar,
    })

    local body = create("Frame", {
        Active = true,
        BackgroundColor3 = THEME.terminal,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(4, 34),
        Size = UDim2.new(1, -8, 1, -38),
        Parent = window,
    })

    local statusBar = mono(body, " ENGINE: INITIALISING", 11, THEME.muted)
    statusBar.Active = true
    statusBar.BackgroundColor3 = Color3.fromRGB(13, 14, 14)
    statusBar.BackgroundTransparency = 0
    statusBar.Size = UDim2.new(1, 0, 0, 24)

    local terminalPane = create("Frame", {
        Active = true,
        BackgroundColor3 = THEME.terminal,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 25),
        Size = UDim2.new(0.55, -1, 1, -25),
        Parent = body,
    })

    create("Frame", {
        BackgroundColor3 = THEME.divider,
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
        BackgroundColor3 = THEME.terminal,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        Position = UDim2.fromOffset(8, 6),
        ScrollBarImageColor3 = THEME.border,
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
        BackgroundColor3 = THEME.terminal,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 8, 1, -40),
        Size = UDim2.new(1, -16, 0, 34),
        Parent = terminalPane,
    })

    local prompt = mono(inputRow, "C:\\0xVyrs\\Tycoon>", 13, THEME.accent)
    prompt.Size = UDim2.fromOffset(138, 34)

    local input = create("TextBox", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Font = Enum.Font.Code,
        MultiLine = false,
        PlaceholderText = "type 'help' for commands",
        PlaceholderColor3 = Color3.fromRGB(88, 94, 92),
        Position = UDim2.fromOffset(142, 0),
        Size = UDim2.new(1, -142, 1, 0),
        Text = "",
        TextColor3 = THEME.text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = inputRow,
    })

    local controlsHeader = mono(controlsPane, " QUICK CONTROLS", 12, THEME.cyan)
    controlsHeader.Active = true
    controlsHeader.Position = UDim2.fromOffset(8, 3)
    controlsHeader.Size = UDim2.new(1, -16, 0, 20)

    local categoryBar = create("Frame", {
        Active = true,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, 25),
        Size = UDim2.new(1, -16, 0, 50),
        Parent = controlsPane,
    })

    local controlsScroll = create("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        Position = UDim2.fromOffset(8, 79),
        ScrollBarImageColor3 = THEME.border,
        ScrollBarThickness = 4,
        Size = UDim2.new(1, -16, 1, -87),
        Parent = controlsPane,
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = controlsScroll,
    })

    local function writeLine(text, colour)
        lineCount = lineCount + 1
        local line = mono(output, tostring(text or ""), 13, colour or THEME.text)
        line.AutomaticSize = Enum.AutomaticSize.Y
        line.Size = UDim2.new(1, -8, 0, 18)
        line.TextWrapped = true
        line.TextYAlignment = Enum.TextYAlignment.Top
        line.LayoutOrder = lineCount
        table.insert(lineObjects, line)
        if #lineObjects > 140 then
            local first = table.remove(lineObjects, 1)
            if first then first:Destroy() end
        end
        task.defer(function()
            if output and output.Parent then
                output.CanvasPosition = Vector2.new(0, math.max(0, output.AbsoluteCanvasSize.Y - output.AbsoluteSize.Y))
            end
        end)
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

    local function configValueText(key)
        local value = CONFIG[key]
        if type(value) == "boolean" then return value and "[ ON ]" or "[ OFF ]" end
        return "[ " .. tostring(value) .. " ]"
    end

    local function applyToggle(key, value)
        if CONFIG[key] == nil then return false end
        CONFIG[key] = value == true
        if callbacks[key] then callbacks[key](CONFIG[key])
        elseif context.saveSettings then context.saveSettings() end
        return true
    end

    local function applyCycle(key, value)
        if CONFIG[key] == nil then return false end
        CONFIG[key] = value
        if cycleCallbacks[key] then cycleCallbacks[key](value)
        elseif context.saveSettings then context.saveSettings() end
        return true
    end

    local function addHeading(text)
        local heading = trackControl(mono(controlsScroll, "[ " .. text .. " ]", 11, THEME.cyan))
        heading.Size = UDim2.new(1, -4, 0, 24)
    end

    local function addToggle(key, text)
        local row = trackControl(create("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = THEME.row,
            BorderSizePixel = 0,
            Font = Enum.Font.Code,
            Size = UDim2.new(1, -4, 0, 29),
            Text = "  " .. text,
            TextColor3 = THEME.text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = controlsScroll,
        }))
        local value = mono(row, configValueText(key), 11, CONFIG[key] and THEME.accent or THEME.off, Enum.TextXAlignment.Right)
        value.AnchorPoint = Vector2.new(1, 0)
        value.Position = UDim2.new(1, -8, 0, 0)
        value.Size = UDim2.fromOffset(105, 29)
        controlValues[key] = value
        connect(row.MouseEnter, function() if row.Parent then row.BackgroundColor3 = THEME.rowHover end end)
        connect(row.MouseLeave, function() if row.Parent then row.BackgroundColor3 = THEME.row end end)
        connect(row.MouseButton1Click, function() applyToggle(key, not CONFIG[key]) end)
    end

    local function addCycle(key, text)
        local row = trackControl(create("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = THEME.row,
            BorderSizePixel = 0,
            Font = Enum.Font.Code,
            Size = UDim2.new(1, -4, 0, 29),
            Text = "  " .. text,
            TextColor3 = THEME.text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = controlsScroll,
        }))
        local value = mono(row, configValueText(key), 11, THEME.cyan, Enum.TextXAlignment.Right)
        value.AnchorPoint = Vector2.new(1, 0)
        value.Position = UDim2.new(1, -8, 0, 0)
        value.Size = UDim2.fromOffset(155, 29)
        controlValues[key] = value
        connect(row.MouseEnter, function() if row.Parent then row.BackgroundColor3 = THEME.rowHover end end)
        connect(row.MouseLeave, function() if row.Parent then row.BackgroundColor3 = THEME.row end end)
        connect(row.MouseButton1Click, function()
            local values = CYCLES[key] or {}
            if #values == 0 then return end
            local nextIndex = 1
            for index, item in ipairs(values) do
                if item == CONFIG[key] then nextIndex = (index % #values) + 1 break end
            end
            applyCycle(key, values[nextIndex])
        end)
    end

    local function addAction(text, key, danger)
        local row = trackControl(create("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = THEME.row,
            BorderSizePixel = 0,
            Font = Enum.Font.Code,
            Size = UDim2.new(1, -4, 0, 29),
            Text = "  > " .. text,
            TextColor3 = danger and THEME.error or THEME.accent,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = controlsScroll,
        }))
        connect(row.MouseEnter, function() if row.Parent then row.BackgroundColor3 = THEME.rowHover end end)
        connect(row.MouseLeave, function() if row.Parent then row.BackgroundColor3 = THEME.row end end)
        connect(row.MouseButton1Click, function()
            if actionCallbacks[key] then actionCallbacks[key]() end
        end)
    end

    local function addInfo(key, text)
        local row = trackControl(create("Frame", {
            BackgroundColor3 = THEME.row,
            BorderSizePixel = 0,
            Size = UDim2.new(1, -4, 0, 27),
            Parent = controlsScroll,
        }))
        local left = mono(row, "  " .. text, 11, THEME.muted)
        left.Size = UDim2.new(0.48, 0, 1, 0)
        local right = mono(row, "--", 11, THEME.text, Enum.TextXAlignment.Right)
        right.Position = UDim2.new(0.48, 0, 0, 0)
        right.Size = UDim2.new(0.52, -8, 1, 0)
        infoValues[key] = right
    end

    local categories = autonomousMode and {
        { "quick", "QUICK" }, { "brain", "BRAIN" }, { "world", "WORLD" }, { "diag", "DIAG" },
    } or {
        { "quick", "QUICK" }, { "world", "WORLD" }, { "diag", "DIAG" },
    }
    local categoryButtons = {}

    local function renderCategory(category)
        activeCategory = category
        clearControls()
        for key, button in pairs(categoryButtons) do
            local selected = key == category
            button.TextColor3 = selected and THEME.accent or THEME.muted
            button.BackgroundColor3 = selected and THEME.rowHover or THEME.terminal
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
            addInfo("buttons", "BUTTONS")
            addInfo("collectors", "COLLECTORS")
            addInfo("affordable", "AFFORDABLE")
            addHeading("RUNTIME")
            addInfo("scan", "SCAN")
            addInfo("cash", "CASH")
            addInfo("cpm", "CASH/MIN")
            if autonomousMode then
                addInfo("target", "TARGET")
                addInfo("bottleneck", "BOTTLENECK")
                addInfo("learning", "LEARNED")
            end
        end
    end

    local categoryWidth = 76
    for index, item in ipairs(categories) do
        local button = create("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = THEME.terminal,
            BorderColor3 = THEME.divider,
            BorderSizePixel = 1,
            Font = Enum.Font.Code,
            Position = UDim2.fromOffset((index - 1) * (categoryWidth + 3), 0),
            Size = UDim2.fromOffset(categoryWidth, 22),
            Text = item[2],
            TextColor3 = THEME.muted,
            TextSize = 10,
            Parent = categoryBar,
        })
        categoryButtons[item[1]] = button
        connect(button.MouseButton1Click, function() renderCategory(item[1]) end)
    end

    local function syncControls()
        for key, value in pairs(controlValues) do
            value.Text = configValueText(key)
            if type(CONFIG[key]) == "boolean" then
                value.TextColor3 = CONFIG[key] and THEME.accent or THEME.off
            else
                value.TextColor3 = THEME.cyan
            end
        end
    end

    local function setInfo(key, text, colour)
        local value = infoValues[key]
        if not value then return end
        value.Text = tostring(text or "--")
        value.TextColor3 = colour or THEME.text
    end

    local previous = { bought = 0, rewards = 0, target = nil, owner = nil }

    local function update(payload)
        if destroyed then return end
        latestPayload = payload or latestPayload
        local data = latestPayload.data or {}
        local stats = latestPayload.stats or {}
        local auto = latestPayload.autonomous or {}
        local brain = auto.brain or {}
        local debugInfo = data.debug or {}

        syncControls()

        local stateText
        local stateColour
        if not CONFIG.enabled then
            stateText, stateColour = "OFFLINE", THEME.muted
        elseif data.ownerVerified then
            stateText, stateColour = autonomousMode and "AUTONOMOUS" or "READY", THEME.accent
        elseif CONFIG.requireOwnerMatch then
            stateText, stateColour = "OWNER BLOCKED", THEME.error
        else
            stateText, stateColour = "RELAXED", THEME.warning
        end

        local targetName = brain.plan and brain.plan.name or "waiting"
        statusBar.Text = string.format(
            " ENGINE: %s  |  CASH: $%s  |  RATE: $%s/min  |  STRATEGY: %s  |  TARGET: %s",
            stateText,
            formatNumber(data.cash or auto.cash or stats.cash),
            formatNumber(stats.cashPerMinute or 0),
            tostring(auto.strategy or CONFIG.strategy or "--"),
            shortText(targetName, 26)
        )
        statusBar.TextColor3 = stateColour

        setInfo("root", shortText(data.rootName or auto.root or "--", 23))
        setInfo("owner", data.ownerVerified and "VERIFIED" or "NO", data.ownerVerified and THEME.accent or THEME.warning)
        setInfo("buttons", tostring(data.totalButtons or #(data.buttons or {})))
        setInfo("collectors", tostring(#(data.drops or {})))
        setInfo("affordable", tostring(data.affordableCount or 0))
        local scanMode = debugInfo.scanMode or "--"
        local scanMs = tonumber(debugInfo.scanTimeMs)
        setInfo("scan", scanMs and string.format("%s / %.1fms", scanMode, scanMs) or scanMode)
        setInfo("cash", "$" .. formatNumber(data.cash or auto.cash or stats.cash))
        setInfo("cpm", "$" .. formatNumber(stats.cashPerMinute or 0))
        setInfo("target", shortText(targetName, 20))
        setInfo("bottleneck", shortText(brain.bottleneck or "--", 20))
        setInfo("learning", string.format("%d nodes / %d links", brain.learnedNodes or 0, brain.learnedEdges or 0))

        local bought = tonumber(auto.bought or latestPayload.bought) or 0
        local rewards = tonumber(auto.rewardsActivated) or 0
        local owner = data.ownerVerified == true
        if previous.owner ~= nil and previous.owner ~= owner then
            writeLine(owner and "[owner] verification acquired" or "[owner] verification lost", owner and THEME.accent or THEME.warning)
        end
        if bought > previous.bought then writeLine(string.format("[buy] purchase confirmed // total=%d", bought), THEME.accent) end
        if rewards > previous.rewards then writeLine(string.format("[reward] free reward activated // total=%d", rewards), THEME.cyan) end
        if targetName ~= "waiting" and targetName ~= previous.target then writeLine("[brain] target -> " .. shortText(targetName, 48), THEME.cyan) end
        previous.bought = bought
        previous.rewards = rewards
        previous.target = targetName
        previous.owner = owner
    end

    local function executeCommand(raw)
        local text = tostring(raw or ""):match("^%s*(.-)%s*$") or ""
        if text == "" then return end
        writeLine("C:\\0xVyrs\\Tycoon> " .. text, THEME.text)
        local args = {}
        for token in text:gmatch("%S+") do table.insert(args, token) end
        local command = string.lower(args[1] or "")

        if command == "help" then
            writeLine("status | start | stop | clear | hide | reset", THEME.cyan)
            writeLine("strategy <fastest|income|rebirth>", THEME.cyan)
            writeLine("toggle <autobuy|autocollect|learning|burst|rewards|autorebirth|labels|waypoint|highlights|owner>", THEME.muted)
        elseif command == "status" then
            local data = latestPayload.data or {}
            local auto = latestPayload.autonomous or {}
            local brain = auto.brain or {}
            writeLine("root       : " .. tostring(data.rootName or auto.root or "--"))
            writeLine("owner      : " .. (data.ownerVerified and "VERIFIED" or "NO"), data.ownerVerified and THEME.accent or THEME.warning)
            writeLine("cash       : $" .. formatNumber(data.cash or auto.cash))
            writeLine("strategy   : " .. tostring(auto.strategy or CONFIG.strategy or "--"))
            writeLine("target     : " .. tostring(brain.plan and brain.plan.name or "waiting"))
        elseif command == "start" then
            if actionCallbacks.start then actionCallbacks.start() else applyToggle("enabled", true) end
            writeLine("autonomous run started", THEME.accent)
        elseif command == "stop" then
            if actionCallbacks.stop then actionCallbacks.stop() else applyToggle("enabled", false) end
            writeLine("automation stopped", THEME.warning)
        elseif command == "clear" then
            clearOutput()
        elseif command == "hide" then
            gui.Enabled = false
        elseif command == "reset" then
            if actionCallbacks.resetLearning then actionCallbacks.resetLearning() writeLine("learned route reset", THEME.warning) end
        elseif command == "strategy" then
            local map = { fastest = "Fastest", income = "Income", rebirth = "Rebirth" }
            local value = map[string.lower(args[2] or "")]
            if value then applyCycle("strategy", value) writeLine("strategy -> " .. value, THEME.accent)
            else writeLine("expected fastest | income | rebirth", THEME.error) end
        elseif command == "toggle" then
            local aliases = {
                autobuy = "autoBuy", autocollect = "autoCollect", learning = "learningEnabled",
                burst = "burstMode", rewards = "autoRewards", autorebirth = "autoRebirth",
                labels = "showLabels", waypoint = "showWaypoint", highlights = "highlightAffordable",
                owner = "requireOwnerMatch", system = "enabled",
            }
            local key = aliases[string.lower(args[2] or "")]
            if key and CONFIG[key] ~= nil then
                applyToggle(key, not CONFIG[key])
                writeLine(key .. " -> " .. tostring(CONFIG[key]), CONFIG[key] and THEME.accent or THEME.warning)
            else
                writeLine("unknown setting", THEME.error)
            end
        else
            writeLine("unknown command // type 'help'", THEME.error)
        end
        syncControls()
    end

    connect(input.FocusLost, function(enterPressed)
        if not enterPressed then return end
        local text = input.Text
        input.Text = ""
        executeCommand(text)
    end)

    local function setFolded(value)
        if animating or folded == value then return end
        animating = true
        if value then
            local tween = TweenService:Create(window, TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = foldedSize })
            tween:Play()
            tween.Completed:Wait()
            body.Visible = false
            folded = true
            minimise.Text = "□"
        else
            body.Visible = true
            local tween = TweenService:Create(window, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = fullSize })
            tween:Play()
            tween.Completed:Wait()
            folded = false
            minimise.Text = "_"
        end
        animating = false
    end

    connect(minimise.MouseButton1Click, function() task.spawn(function() setFolded(not folded) end) end)
    connect(minimise.MouseEnter, function() minimise.BackgroundColor3 = THEME.titleHover end)
    connect(minimise.MouseLeave, function() minimise.BackgroundColor3 = THEME.title end)
    connect(close.MouseEnter, function() close.BackgroundColor3 = Color3.fromRGB(170, 45, 45) end)
    connect(close.MouseLeave, function() close.BackgroundColor3 = THEME.title end)
    connect(close.MouseButton1Click, function() gui.Enabled = false end)

    -- Window dragging is intentionally handled globally instead of binding only
    -- the title bar. Any non-interactive surface can start a drag, while buttons,
    -- tabs and the command TextBox keep their normal behaviour.
    local dragging = false
    local dragStart = Vector2.zero
    local startPosition = Vector2.zero

    local function pointInsideWindow(position)
        local absolutePosition = window.AbsolutePosition
        local absoluteSize = window.AbsoluteSize
        return position.X >= absolutePosition.X
            and position.X <= absolutePosition.X + absoluteSize.X
            and position.Y >= absolutePosition.Y
            and position.Y <= absolutePosition.Y + absoluteSize.Y
    end

    local function isInteractiveObject(object)
        local current = object
        while current and current ~= window do
            if current:IsA("TextButton") or current:IsA("TextBox") then return true end
            current = current.Parent
        end
        return false
    end

    local function canStartDrag(position)
        if not pointInsideWindow(position) then return false end
        local ok, objects = pcall(function()
            return GuiService:GetGuiObjectsAtPosition(position.X, position.Y)
        end)
        if not ok or type(objects) ~= "table" then return true end
        for _, object in ipairs(objects) do
            if object == window or object:IsDescendantOf(window) then
                return not isInteractiveObject(object)
            end
        end
        return true
    end

    connect(UserInputService.InputBegan, function(inputObject, processed)
        if inputObject.KeyCode == Enum.KeyCode.RightShift and not processed then
            gui.Enabled = not gui.Enabled
            return
        end
        if not gui.Enabled then return end
        if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 and inputObject.UserInputType ~= Enum.UserInputType.Touch then return end
        local position = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
        if not canStartDrag(position) then return end
        dragging = true
        dragStart = position
        startPosition = Vector2.new(window.Position.X.Offset, window.Position.Y.Offset)
    end)

    connect(UserInputService.InputChanged, function(inputObject)
        if not dragging then return end
        if inputObject.UserInputType ~= Enum.UserInputType.MouseMovement and inputObject.UserInputType ~= Enum.UserInputType.Touch then return end
        local current = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
        local delta = current - dragStart
        local currentViewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or viewport
        local size = window.AbsoluteSize
        local maxX = math.max(0, currentViewport.X - size.X)
        local maxY = math.max(0, currentViewport.Y - size.Y)
        local x = math.clamp(startPosition.X + delta.X, 0, maxX)
        local y = math.clamp(startPosition.Y + delta.Y, 0, maxY)
        window.Position = UDim2.fromOffset(x, y)
    end)

    connect(UserInputService.InputEnded, function(inputObject)
        if not dragging then return end
        if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 and inputObject.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging = false
        CONFIG.uiOffsetX = window.Position.X.Offset
        CONFIG.uiOffsetY = window.Position.Y.Offset
        if context.saveSettings then context.saveSettings() end
    end)

    local function destroy()
        if destroyed then return end
        destroyed = true
        for _, connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
        end
        connections = {}
        if gui then gui:Destroy() end
    end

    renderCategory(activeCategory)
    writeLine("0xVyrs Tycoon Autonomous Console", THEME.accent)
    writeLine("v" .. tostring(CONFIG.version) .. " // .exe terminal interface", THEME.cyan)
    writeLine("drag from any empty/non-interactive part of the window", THEME.muted)
    writeLine("type 'help' for commands", THEME.muted)

    return {
        onToggle = function(key, callback) callbacks[key] = callback end,
        onCycle = function(key, callback) cycleCallbacks[key] = callback end,
        onAction = function(key, callback) actionCallbacks[key] = callback end,
        update = update,
        destroy = destroy,
    }
end
