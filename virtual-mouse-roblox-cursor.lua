--[=[
  VIRTUAL MOUSE - ROBLOX NATIVE CURSOR EDITION
  Based on the user's virtual-mouse (1).lua source.

  Controls:
    - Tap ON: capture touchscreen input and request Roblox's native mouse cursor.
    - One-finger swipe anywhere: move the emulated mouse relatively (no teleport).
    - Double tap: left click at the current emulated mouse position.
    - Hold for 0.35s, then drag: hold left mouse button; release finger to release.
    - Two-finger swipe: mouse wheel.
    - OFF: stop capturing touch so normal game/executor touch works.
    - Settings: adjust cursor movement speed and scroll speed.

  Important:
    Roblox/iOS may not render a desktop mouse pointer on a touch-only device.
    VirtualInputManager methods may also be unavailable/blocked by an executor.
]=]

-- Stop a previous copy cleanly.
local Env = (getgenv and getgenv()) or _G
pcall(function()
    if type(Env.__VM_ROBLOX_CLEAN) == "function" then
        Env.__VM_ROBLOX_CLEAN()
    end
    -- Remove the previous version's custom pixel cursor and overlay too.
    if type(Env.__VM_CLEAN) == "function" then
        Env.__VM_CLEAN()
    end
end)

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Player = Players.LocalPlayer
if not Player then return end

local VIM
pcall(function()
    VIM = game:GetService("VirtualInputManager")
end)

-- Save Roblox cursor state so cleanup can restore it.
local originalMouseIconEnabled
local originalMouseBehavior
local originalMouseIcon
pcall(function() originalMouseIconEnabled = UIS.MouseIconEnabled end)
pcall(function() originalMouseBehavior = UIS.MouseBehavior end)
pcall(function() originalMouseIcon = UIS.MouseIcon end)

local function setNativeCursor(enabled)
    if enabled then
        -- Empty icon asks Roblox to use its default arrow.
        pcall(function() UIS.MouseIcon = "" end)
        pcall(function() Player:GetMouse().Icon = "" end)
        pcall(function() UIS.MouseBehavior = Enum.MouseBehavior.Default end)
        pcall(function() UIS.MouseIconEnabled = true end)
    else
        if originalMouseIcon ~= nil then
            pcall(function() UIS.MouseIcon = originalMouseIcon end)
        end
        if originalMouseBehavior ~= nil then
            pcall(function() UIS.MouseBehavior = originalMouseBehavior end)
        end
        if originalMouseIconEnabled ~= nil then
            pcall(function() UIS.MouseIconEnabled = originalMouseIconEnabled end)
        end
    end
end

-- Settings
local CONFIG_FILE = "vmouse_cfg.json"
local cfg = {
    speed = 1.8,
    scroll = 1.0,
    offsetY = 0,
}
pcall(function()
    if readfile and isfile and isfile(CONFIG_FILE) then
        local saved = HttpService:JSONDecode(readfile(CONFIG_FILE))
        if type(saved) == "table" then
            for key, value in pairs(saved) do
                if cfg[key] ~= nil and type(value) == "number" then
                    cfg[key] = value
                end
            end
        end
    end
end)
local function saveConfig()
    pcall(function()
        if writefile then
            writefile(CONFIG_FILE, HttpService:JSONEncode(cfg))
        end
    end)
end

local HOLD_TIME = 0.35
local DOUBLE_TAP_TIME = 0.32
local TAP_MAX_TIME = 0.25
local MOVE_THRESHOLD = 10

-- GUI parent
local function getGuiParent()
    local ok, parent = pcall(function()
        return gethui and gethui()
    end)
    if ok and parent then return parent end

    ok, parent = pcall(function()
        return game:GetService("CoreGui")
    end)
    if ok and parent then return parent end

    return Player:WaitForChild("PlayerGui")
end

local gui = Instance.new("ScreenGui")
gui.Name = "VirtualMouseRobloxNative"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(gui) end
end)
gui.Parent = getGuiParent()

-- Fullscreen transparent touchpad. No cursor graphic is drawn by this script.
local overlay = Instance.new("Frame")
overlay.Name = "Touchpad"
overlay.Size = UDim2.fromScale(1, 1)
overlay.Position = UDim2.fromScale(0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Active = true
overlay.ZIndex = 1
overlay.Parent = gui

local viewport = gui.AbsoluteSize
local mouseX = math.clamp(viewport.X * 0.5, 0, math.max(0, viewport.X - 1))
local mouseY = math.clamp(viewport.Y * 0.5, 0, math.max(0, viewport.Y - 1))

local enabled = true
local dragging = false
local scrolling = false
local sliding = nil
local touches = {}
local touchCount = 0
local scrollAccumulator = 0
local lastTapTime = 0
local connections = {}
local cleaned = false

local function addConnection(connection)
    table.insert(connections, connection)
    return connection
end

-- Send input through Roblox's virtual mouse API.
-- pcall is used because executor/platform support varies.
local function sendMove()
    if not VIM then return false end
    local ok = pcall(function()
        VIM:SendMouseMoveEvent(
            math.floor(mouseX + 0.5),
            math.floor(mouseY + cfg.offsetY + 0.5),
            game
        )
    end)
    return ok
end

local function sendButton(isDown)
    if not VIM then return false end
    local ok = pcall(function()
        VIM:SendMouseButtonEvent(
            math.floor(mouseX + 0.5),
            math.floor(mouseY + cfg.offsetY + 0.5),
            0,
            isDown,
            game,
            0
        )
    end)
    return ok
end

local function sendWheel(direction)
    if not VIM then return false end
    local ok = pcall(function()
        VIM:SendMouseWheelEvent(
            math.floor(mouseX + 0.5),
            math.floor(mouseY + cfg.offsetY + 0.5),
            direction,
            game
        )
    end)
    return ok
end

local function moveMouse(dx, dy)
    local size = gui.AbsoluteSize
    mouseX = math.clamp(mouseX + dx, 0, math.max(0, size.X - 1))
    mouseY = math.clamp(mouseY + dy, 0, math.max(0, size.Y - 1))
    sendMove()
end

local function clickMouse()
    sendMove()
    if sendButton(true) then
        task.wait(0.045)
        sendButton(false)
    end
end

local function startDrag()
    if dragging or not enabled then return end
    dragging = true
    sendMove()
    sendButton(true)
end

local function stopDrag()
    if not dragging then return end
    dragging = false
    sendButton(false)
end

local function isTouch(input)
    return input and input.UserInputType == Enum.UserInputType.Touch
end

-- Native mouse cursor is requested when ON. On iOS this may remain invisible
-- because Roblox reports a touch-only device with no physical mouse.
setNativeCursor(true)

-- Control panel helpers
local function round(instance, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = instance
end

local function makeFloat(text, position, size, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(size, size)
    button.Position = position
    button.BackgroundColor3 = Color3.fromRGB(30, 31, 36)
    button.BackgroundTransparency = 0.08
    button.Text = text
    button.TextColor3 = Color3.new(1, 1, 1)
    button.TextSize = 16
    button.Font = Enum.Font.GothamBold
    button.AutoButtonColor = true
    button.Active = true
    button.ZIndex = 30
    button.Parent = gui
    round(button, size)

    local downInput
    local startPosition
    local buttonOrigin
    local wasDragged = false

    button.InputBegan:Connect(function(input)
        if isTouch(input) or input.UserInputType == Enum.UserInputType.MouseButton1 then
            downInput = input
            startPosition = Vector2.new(input.Position.X, input.Position.Y)
            buttonOrigin = button.AbsolutePosition
            wasDragged = false
        end
    end)

    addConnection(UIS.InputChanged:Connect(function(input)
        if not downInput then return end
        if input == downInput or input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - startPosition
            if delta.Magnitude > 8 then wasDragged = true end
            if wasDragged then
                local screen = gui.AbsoluteSize
                button.Position = UDim2.fromOffset(
                    math.clamp(buttonOrigin.X + delta.X, 0, math.max(0, screen.X - size)),
                    math.clamp(buttonOrigin.Y + delta.Y, 0, math.max(0, screen.Y - size))
                )
            end
        end
    end))

    addConnection(UIS.InputEnded:Connect(function(input)
        if downInput and (input == downInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
            downInput = nil
            if not wasDragged then callback() end
        end
    end))

    return button
end

local panel = Instance.new("Frame")
panel.Name = "SettingsPanel"
panel.Size = UDim2.fromOffset(250, 250)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 29)
panel.BackgroundTransparency = 0.04
panel.BorderSizePixel = 0
panel.Active = true
panel.Visible = false
panel.ZIndex = 20
panel.Parent = gui
round(panel, 12)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(75, 78, 88)
panelStroke.Thickness = 1
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 32)
title.BackgroundColor3 = Color3.fromRGB(36, 37, 43)
title.BorderSizePixel = 0
title.Text = "VIRTUAL MOUSE  /  SETTINGS"
title.TextColor3 = Color3.fromRGB(240, 240, 245)
title.Font = Enum.Font.GothamBold
title.TextSize = 11
title.ZIndex = 21
title.Parent = panel
round(title, 10)

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(12, 38)
status.Size = UDim2.new(1, -24, 0, 36)
status.BackgroundTransparency = 1
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Center
status.TextWrapped = true
status.Font = Enum.Font.Gotham
status.TextSize = 10
status.TextColor3 = Color3.fromRGB(205, 210, 220)
status.ZIndex = 21
status.Parent = panel

local function refreshStatus()
    local mouseAvailable = false
    pcall(function() mouseAvailable = UIS.MouseEnabled end)
    local inputStatus = VIM and "VIM: available" or "VIM: unavailable"
    local cursorStatus = mouseAvailable and "Roblox mouse: device detected" or "Touch-only: native arrow may not show"
    status.Text = inputStatus .. "\n" .. cursorStatus
end
refreshStatus()

local function makeSlider(y, labelText, minimum, maximum, key, formatString)
    local label = Instance.new("TextLabel")
    label.Position = UDim2.fromOffset(12, y)
    label.Size = UDim2.new(1, -24, 0, 20)
    label.BackgroundTransparency = 1
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextSize = 13
    label.Font = Enum.Font.GothamMedium
    label.ZIndex = 21
    label.Parent = panel

    local track = Instance.new("Frame")
    track.Position = UDim2.fromOffset(16, y + 29)
    track.Size = UDim2.new(1, -32, 0, 8)
    track.BackgroundColor3 = Color3.fromRGB(70, 70, 76)
    track.BorderSizePixel = 0
    track.Active = true
    track.ZIndex = 21
    track.Parent = panel
    round(track, 8)

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Size = UDim2.fromOffset(20, 20)
    knob.BackgroundColor3 = Color3.fromRGB(65, 130, 245)
    knob.BorderSizePixel = 0
    knob.ZIndex = 22
    knob.Parent = track
    round(knob, 10)

    local function setValue(value)
        value = math.floor(value * 10 + 0.5) / 10
        cfg[key] = value
        local alpha = (value - minimum) / (maximum - minimum)
        knob.Position = UDim2.new(math.clamp(alpha, 0, 1), 0, 0.5, 0)
        label.Text = labelText .. string.format(formatString, value)
    end

    setValue(math.clamp(cfg[key], minimum, maximum))

    local function updateFromInput(input)
        local width = math.max(1, track.AbsoluteSize.X)
        local alpha = math.clamp((input.Position.X - track.AbsolutePosition.X) / width, 0, 1)
        setValue(minimum + alpha * (maximum - minimum))
    end

    local sliderId = {}
    track.InputBegan:Connect(function(input)
        if isTouch(input) or input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = sliderId
            updateFromInput(input)
        end
    end)
    addConnection(UIS.InputChanged:Connect(function(input)
        if sliding == sliderId and (isTouch(input) or input.UserInputType == Enum.UserInputType.MouseMovement) then
            updateFromInput(input)
        end
    end))
    addConnection(UIS.InputEnded:Connect(function()
        if sliding == sliderId then
            sliding = nil
            saveConfig()
        end
    end))
end

makeSlider(82, "Movement speed: ", 0.5, 6, "speed", "%.1fx")
makeSlider(142, "Scroll speed: ", 0.5, 5, "scroll", "%.1fx")

local function makePanelButton(text, position, color, callback)
    local button = Instance.new("TextButton")
    button.Position = position
    button.Size = UDim2.new(0.5, -18, 0, 30)
    button.BackgroundColor3 = color
    button.BorderSizePixel = 0
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Text = text
    button.TextSize = 12
    button.Font = Enum.Font.GothamBold
    button.ZIndex = 21
    button.Parent = panel
    round(button, 8)
    button.Activated:Connect(callback)
    return button
end

local toggleButton
local hideButton

local function setEnabled(value)
    enabled = value
    overlay.Visible = value
    if not value then
        -- Release any held synthetic button before handing touch back to Roblox.
        stopDrag()
        touches = {}
        touchCount = 0
        scrolling = false
        sliding = nil
        setNativeCursor(false)
    else
        setNativeCursor(true)
        sendMove()
    end

    if toggleButton then
        toggleButton.Text = value and "ON" or "OFF"
        toggleButton.BackgroundColor3 = value
            and Color3.fromRGB(38, 155, 82)
            or Color3.fromRGB(190, 55, 55)
    end
    if hideButton then
        hideButton.Text = value and "Turn OFF" or "Turn ON"
    end
end

local gearButton
gearButton = makeFloat("SET", UDim2.new(0, 10, 0.58, 0), 46, function()
    panel.Visible = not panel.Visible
    if panel.Visible then
        local screen = gui.AbsoluteSize
        local origin = gearButton.AbsolutePosition
        panel.Position = UDim2.fromOffset(
            math.clamp(origin.X + 54, 0, math.max(0, screen.X - 250)),
            math.clamp(origin.Y - 110, 0, math.max(0, screen.Y - 250))
        )
        refreshStatus()
    end
end)

toggleButton = makeFloat("ON", UDim2.new(0, 10, 0.58, 54), 46, function()
    setEnabled(not enabled)
end)
toggleButton.TextSize = 13
toggleButton.BackgroundColor3 = Color3.fromRGB(38, 155, 82)

hideButton = makePanelButton("Turn OFF", UDim2.new(0, 12, 1, -40), Color3.fromRGB(55, 110, 210), function()
    setEnabled(not enabled)
end)
local closeButton = makePanelButton("Close script", UDim2.new(0.5, 6, 1, -40), Color3.fromRGB(190, 55, 55), function()
    if Env.__VM_ROBLOX_CLEAN then Env.__VM_ROBLOX_CLEAN() end
end)

-- Touchpad input: positions are relative deltas, never absolute finger positions.
addConnection(overlay.InputBegan:Connect(function(input)
    if not enabled or not isTouch(input) then return end

    local state = {
        startTime = os.clock(),
        startX = input.Position.X,
        startY = input.Position.Y,
        lastX = input.Position.X,
        lastY = input.Position.Y,
        moved = false,
    }
    touches[input] = state
    touchCount += 1

    if touchCount >= 2 then
        scrolling = true
        scrollAccumulator = 0
        for _, touchState in pairs(touches) do
            touchState.moved = true
        end
        stopDrag()
        return
    end

    scrolling = false
    task.delay(HOLD_TIME, function()
        if enabled and touches[input] == state and not state.moved and touchCount == 1 and not scrolling then
            startDrag()
        end
    end)
end))

addConnection(UIS.InputChanged:Connect(function(input)
    if not enabled or not isTouch(input) then return end
    local state = touches[input]
    if not state then return end

    local currentX = input.Position.X
    local currentY = input.Position.Y
    local deltaX = currentX - state.lastX
    local deltaY = currentY - state.lastY
    state.lastX = currentX
    state.lastY = currentY

    if touchCount >= 2 or scrolling then
        scrollAccumulator += deltaY * cfg.scroll
        while scrollAccumulator >= 12 do
            scrollAccumulator -= 12
            sendWheel(1)
        end
        while scrollAccumulator <= -12 do
            scrollAccumulator += 12
            sendWheel(-1)
        end
        state.moved = true
        return
    end

    if not state.moved then
        local distance = (Vector2.new(currentX, currentY) - Vector2.new(state.startX, state.startY)).Magnitude
        if distance > MOVE_THRESHOLD then
            state.moved = true
            -- Apply the whole accumulated movement, including the threshold distance.
            moveMouse((currentX - state.startX) * cfg.speed, (currentY - state.startY) * cfg.speed)
            return
        end
    else
        moveMouse(deltaX * cfg.speed, deltaY * cfg.speed)
    end
end))

addConnection(UIS.InputEnded:Connect(function(input)
    if not isTouch(input) then return end
    local state = touches[input]
    if not state then return end

    touches[input] = nil
    touchCount = math.max(0, touchCount - 1)

    if touchCount > 0 then return end

    if dragging then
        stopDrag()
        scrolling = false
        return
    end

    if scrolling then
        scrolling = false
        return
    end

    local now = os.clock()
    local duration = now - state.startTime
    if not state.moved and duration <= TAP_MAX then
        if now - lastTapTime <= DOUBLE_TAP_TIME then
            lastTapTime = 0
            task.spawn(clickMouse)
        else
            lastTapTime = now
        end
    end
end))

-- Keep the native cursor request active while enabled, in case the game changes it.
addConnection(UIS:GetPropertyChangedSignal("MouseIconEnabled"):Connect(function()
    if enabled then
        pcall(function() UIS.MouseIconEnabled = true end)
    end
end))

local function cleanup()
    if cleaned then return end
    cleaned = true
    enabled = false
    pcall(stopDrag)
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    connections = {}
    setNativeCursor(false)
    pcall(function() gui:Destroy() end)
    if Env.__VM_ROBLOX_CLEAN then Env.__VM_ROBLOX_CLEAN = nil end
end

Env.__VM_ROBLOX_CLEAN = cleanup

-- Start at screen center; don't reset to GetMouseLocation() because iOS can report (0, 0).
sendMove()
print("[Virtual Mouse] Loaded. Native Roblox cursor requested; iOS may not display a desktop pointer.")
