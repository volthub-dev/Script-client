-- BLOCK CLIENT / PIXEL VIRTUAL MOUSE V5
-- Persistent pixel cursor + relative touchpad + hold-drag drawing.
-- Delta iOS compatibility depends on whether VirtualInputManager mouse events are accepted.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Player = Players.LocalPlayer
if not Player then return end

local Env = (getgenv and getgenv()) or _G
pcall(function()
    if Env.__VM_PIXEL_CLEAN then Env.__VM_PIXEL_CLEAN() end
end)

local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)
local config = { size = 42, speed = 1.8, scroll = 1.0 }
local CFG_FILE = "vmouse_cfg.json"
pcall(function()
    if isfile and readfile and isfile(CFG_FILE) then
        local saved = HttpService:JSONDecode(readfile(CFG_FILE))
        if type(saved) == "table" then
            for key in pairs(config) do
                if type(saved[key]) == "number" then config[key] = saved[key] end
            end
        end
    end
end)
local function saveConfig()
    pcall(function()
        if writefile then writefile(CFG_FILE, HttpService:JSONEncode(config)) end
    end)
end

local function getParent()
    local ok, parent = pcall(function() return gethui and gethui() end)
    if ok and parent then return parent end
    local ok2, core = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and core then return core end
    return Player:WaitForChild("PlayerGui")
end

local oldMouseIcon
pcall(function()
    oldMouseIcon = UIS.MouseIconEnabled
    UIS.MouseIconEnabled = false
end)

local gui = Instance.new("ScreenGui")
gui.Name = "BlockClientPixelMouseV5"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
gui.Parent = getParent()

-- Transparent input layer. The cursor is a separate, persistent GUI object.
local overlay = Instance.new("Frame")
overlay.Name = "TouchSurface"
overlay.Size = UDim2.fromScale(1, 1)
overlay.Position = UDim2.fromOffset(0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Active = true
overlay.ZIndex = 1
overlay.Parent = gui

local PIXEL_MAP = {
    "B...........", "BB..........", "BWB.........", "BWWB........",
    "BWWWB.......", "BWWWWB......", "BWWWWWB.....", "BWWWWWWB....",
    "BWWWWWWWB...", "BWWWWWWWWB..", "BWWWWWBBBBB.", "BWWBWWB.....",
    "BWB.BWWB....", "BB..BWWB....", "B....BWWB...", ".....BWWB...",
    "......BB....",
}
local ROWS, COLS = #PIXEL_MAP, #PIXEL_MAP[1]
local cursor = Instance.new("Frame")
cursor.Name = "PersistentPixelCursor"
cursor.BackgroundTransparency = 1
cursor.BorderSizePixel = 0
cursor.AnchorPoint = Vector2.new(0, 0)
cursor.Active = false
cursor.Visible = true
cursor.ZIndex = 40
cursor.Parent = gui
for rowIndex, row in ipairs(PIXEL_MAP) do
    local col = 1
    while col <= COLS do
        local ch = row:sub(col, col)
        if ch == "." then
            col += 1
        else
            local last = col
            while last < COLS and row:sub(last + 1, last + 1) == ch do
                last += 1
            end
            local pixel = Instance.new("Frame")
            pixel.Name = ch == "B" and "BlackPixel" or "WhitePixel"
            pixel.BorderSizePixel = 0
            pixel.BackgroundColor3 = ch == "B" and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
            pixel.Position = UDim2.fromScale((col - 1) / COLS, (rowIndex - 1) / ROWS)
            pixel.Size = UDim2.fromScale((last - col + 1) / COLS, 1 / ROWS)
            pixel.ZIndex = 41
            pixel.Active = false
            pixel.Parent = cursor
            col = last + 1
        end
    end
end

local size = gui.AbsoluteSize
local cx, cy = math.floor(size.X * 0.5), math.floor(size.Y * 0.5)
local enabled, dragging, scrolling, cleaned = true, false, false, false
local touches, touchCount = {}, 0
local lastTap, scrollAcc = 0, 0
local connections = {}
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function cursorHeight()
    return math.clamp(config.size, 16, 100)
end
local function updateCursor()
    local screen = gui.AbsoluteSize
    local h = cursorHeight()
    local w = h * COLS / ROWS
    cursor.Size = UDim2.fromOffset(w, h)
    cx = math.clamp(cx, 0, math.max(0, screen.X - w))
    cy = math.clamp(cy, 0, math.max(0, screen.Y - h))
    cursor.Position = UDim2.fromOffset(cx, cy)
    cursor.Visible = enabled
end

local function sendMove()
    if not VIM then return false end
    return pcall(function()
        VIM:SendMouseMoveEvent(math.floor(cx), math.floor(cy), game)
    end)
end
local function sendButton(isDown)
    if not VIM then return false end
    return pcall(function()
        VIM:SendMouseButtonEvent(math.floor(cx), math.floor(cy), 0, isDown, game, 0)
    end)
end
local function sendWheel(direction)
    if not VIM then return false end
    return pcall(function()
        VIM:SendMouseWheelEvent(math.floor(cx), math.floor(cy), direction, game)
    end)
end
local function moveCursor(dx, dy)
    local screen = gui.AbsoluteSize
    local h = cursorHeight()
    local w = h * COLS / ROWS
    cx = math.clamp(cx + dx, 0, math.max(0, screen.X - w))
    cy = math.clamp(cy + dy, 0, math.max(0, screen.Y - h))
    updateCursor()
    sendMove()
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
local function clickMouse()
    sendMove()
    sendButton(true)
    task.wait(0.045)
    sendButton(false)
end

local function round(object, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = object
end
local function makeButton(label, position, color, callback, width)
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(width or 48, 42)
    button.Position = position
    button.BackgroundColor3 = color
    button.BackgroundTransparency = 0.05
    button.BorderSizePixel = 0
    button.Text = label
    button.TextColor3 = Color3.new(1, 1, 1)
    button.TextSize = 13
    button.Font = Enum.Font.GothamBold
    button.AutoButtonColor = true
    button.Active = true
    button.ZIndex = 100
    button.Parent = gui
    round(button, 12)
    button.Activated:Connect(callback)
    return button
end

local panel = Instance.new("Frame")
panel.Name = "PixelMouseSettings"
panel.Size = UDim2.fromOffset(220, 164)
panel.Position = UDim2.new(0, 64, 0.58, 0)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Active = true
panel.ZIndex = 80
panel.Parent = gui
round(panel, 12)
local panelTitle = Instance.new("TextLabel")
panelTitle.Size = UDim2.new(1, -12, 0, 28)
panelTitle.Position = UDim2.fromOffset(8, 4)
panelTitle.BackgroundTransparency = 1
panelTitle.Text = "PIXEL MOUSE SETTINGS"
panelTitle.TextColor3 = Color3.new(1, 1, 1)
panelTitle.TextSize = 11
panelTitle.Font = Enum.Font.GothamBold
panelTitle.ZIndex = 81
panelTitle.Parent = panel
local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 24)
status.Position = UDim2.fromOffset(8, 32)
status.BackgroundTransparency = 1
status.Text = VIM and "Mouse API: found (not validated)" or "Mouse API: unavailable"
status.TextColor3 = Color3.fromRGB(210, 210, 220)
status.TextSize = 10
status.Font = Enum.Font.Gotham
status.ZIndex = 81
status.Parent = panel

local function panelAction(label, x, y, color, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(92, 30)
    button.Position = UDim2.fromOffset(x, y)
    button.BackgroundColor3 = color
    button.BorderSizePixel = 0
    button.Text = label
    button.TextColor3 = Color3.new(1, 1, 1)
    button.TextSize = 11
    button.Font = Enum.Font.GothamBold
    button.ZIndex = 82
    button.Parent = panel
    round(button, 7)
    button.Activated:Connect(callback)
end
panelAction("Size -", 10, 66, Color3.fromRGB(65, 95, 145), function()
    config.size = math.max(16, config.size - 4); updateCursor(); saveConfig()
end)
panelAction("Size +", 116, 66, Color3.fromRGB(65, 95, 145), function()
    config.size = math.min(100, config.size + 4); updateCursor(); saveConfig()
end)
panelAction("Speed -", 10, 106, Color3.fromRGB(115, 75, 150), function()
    config.speed = math.max(0.5, config.speed - 0.2); saveConfig()
end)
panelAction("Speed +", 116, 106, Color3.fromRGB(115, 75, 150), function()
    config.speed = math.min(6, config.speed + 0.2); saveConfig()
end)

local settingsButton = makeButton("SET", UDim2.new(0, 12, 0.60, 0), Color3.fromRGB(35, 35, 42), function()
    panel.Visible = not panel.Visible
end)
local toggleButton
local function setEnabled(value)
    enabled = value
    overlay.Visible = value
    cursor.Visible = value
    if not value then
        stopDrag()
        touches, touchCount, scrolling = {}, 0, false
        lastTap = 0
    end
    toggleButton.Text = value and "ON" or "OFF"
    toggleButton.BackgroundColor3 = value and Color3.fromRGB(35, 155, 80) or Color3.fromRGB(190, 55, 55)
end
toggleButton = makeButton("ON", UDim2.new(0, 12, 0.60, 50), Color3.fromRGB(35, 155, 80), function()
    setEnabled(not enabled)
end)

-- Touch start is captured by the full-screen surface; the cursor itself never follows the finger.
connect(overlay.InputBegan, function(input)
    if not enabled or input.UserInputType ~= Enum.UserInputType.Touch then return end
    local now = os.clock()
    local state = {
        startedAt = now,
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
        scrollAcc = 0
        stopDrag()
        for _, touchState in pairs(touches) do touchState.moved = true end
        return
    end
    scrolling = false
    -- Important: do NOT cancel this timer just because the finger moved a little.
    task.delay(0.35, function()
        if enabled and touches[input] == state and touchCount == 1 and not scrolling then
            startDrag()
        end
    end)
end)

connect(UIS.TouchMoved, function(input)
    if not enabled then return end
    local state = touches[input]
    if not state then return end
    local x, y = input.Position.X, input.Position.Y
    local dx, dy = x - state.lastX, y - state.lastY
    state.lastX, state.lastY = x, y

    if touchCount >= 2 or scrolling then
        scrollAcc += dy * config.scroll
        while scrollAcc >= 12 do scrollAcc -= 12; sendWheel(true) end
        while scrollAcc <= -12 do scrollAcc += 12; sendWheel(false) end
        state.moved = true
        return
    end

    local distance = (Vector2.new(x, y) - Vector2.new(state.startX, state.startY)).Magnitude
    if distance > 5 then state.moved = true end
    if state.moved then
        -- After the hold threshold, movement is sent while the mouse button is down.
        if os.clock() - state.startedAt >= 0.35 then startDrag() end
        if distance > 5 and not state.hasMovedCursor then
            state.hasMovedCursor = true
            moveCursor((x - state.startX) * config.speed, (y - state.startY) * config.speed)
        else
            moveCursor(dx * config.speed, dy * config.speed)
        end
    end
end)

connect(UIS.TouchEnded, function(input)
    local state = touches[input]
    if not state then return end
    touches[input] = nil
    touchCount = math.max(0, touchCount - 1)
    if touchCount > 0 then return end
    if dragging then stopDrag(); scrolling = false; return end
    if scrolling then scrolling = false; return end
    local elapsed = os.clock() - state.startedAt
    if not state.moved and elapsed <= 0.25 then
        local now = os.clock()
        if now - lastTap <= 0.32 then
            lastTap = 0
            task.spawn(clickMouse)
        else
            lastTap = now
        end
    end
end)

-- Reassert visibility and position each frame so the pixel pointer remains on screen
-- after the user's finger is lifted. It is not a temporary touch indicator.
connect(RunService.RenderStepped, function()
    if cleaned or not gui.Parent then return end
    gui.Enabled = true
    cursor.Visible = enabled
    if enabled then
        cursor.Position = UDim2.fromOffset(cx, cy)
    end
end)

local function cleanup()
    if cleaned then return end
    cleaned = true
    enabled = false
    pcall(stopDrag)
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    connections = {}
    pcall(function() gui:Destroy() end)
    pcall(function()
        if oldMouseIcon ~= nil then UIS.MouseIconEnabled = oldMouseIcon end
    end)
    if Env.__VM_PIXEL_CLEAN == cleanup then Env.__VM_PIXEL_CLEAN = nil end
end
Env.__VM_PIXEL_CLEAN = cleanup

-- Ensure a valid screen size before placing the initial cursor.
task.defer(function()
    if cleaned or not gui.Parent then return end
    local screen = gui.AbsoluteSize
    cx, cy = math.floor(screen.X * 0.5), math.floor(screen.Y * 0.5)
    updateCursor()
    sendMove()
end)
