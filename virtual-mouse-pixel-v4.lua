-- BLOCK CLIENT / PIXEL VIRTUAL MOUSE V4
-- Touchpad-style relative control for Roblox mobile executors.
-- One finger: move cursor relatively (no teleport)
-- Double tap: left click
-- Hold 0.35s then drag: draw/drag; release: mouse up
-- Two fingers: scroll
-- SET: settings; ON/OFF: enable/disable touch capture

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Player = Players.LocalPlayer
if not Player then return end

local Env = (getgenv and getgenv()) or _G
pcall(function()
    if Env.__VM_PIXEL_CLEAN then Env.__VM_PIXEL_CLEAN() end
    if Env.__VM_CLEAN then Env.__VM_CLEAN() end
end)

local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)

local cfg = { size = 48, speed = 1.8, scroll = 1.0, offsetY = 0 }
local CFG_FILE = "vmouse_cfg.json"
pcall(function()
    if isfile and readfile and isfile(CFG_FILE) then
        local saved = HttpService:JSONDecode(readfile(CFG_FILE))
        if type(saved) == "table" then
            for k in pairs(cfg) do
                if type(saved[k]) == "number" then cfg[k] = saved[k] end
            end
        end
    end
end)
local function saveCfg()
    pcall(function() if writefile then writefile(CFG_FILE, HttpService:JSONEncode(cfg)) end end)
end

local HOLD_TIME, DOUBLE_TIME, TAP_MAX, MOVE_TOL = 0.35, 0.32, 0.25, 8
local function isTouch(input)
    return input and input.UserInputType == Enum.UserInputType.Touch
end
local function getParent()
    local ok, p = pcall(function() return gethui and gethui() end)
    if ok and p then return p end
    local ok2, cp = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and cp then return cp end
    return Player:WaitForChild("PlayerGui")
end

local gui = Instance.new("ScreenGui")
gui.Name = "BlockClientPixelMouse"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
gui.Parent = getParent()

-- Full-screen touch surface. Cursor and controls are layered above it.
local overlay = Instance.new("Frame")
overlay.Name = "TouchSurface"
overlay.Size = UDim2.fromScale(1, 1)
overlay.Position = UDim2.fromOffset(0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Active = true
overlay.ZIndex = 1
overlay.Parent = gui

-- Pixel arrow cursor, recreated from the source script's pixel map.
local PIXEL_MAP = {
    "B...........",
    "BB..........",
    "BWB.........",
    "BWWB........",
    "BWWWB.......",
    "BWWWWB......",
    "BWWWWWB.....",
    "BWWWWWWB....",
    "BWWWWWWWB...",
    "BWWWWWWWWB..",
    "BWWWWWBBBBB.",
    "BWWBWWB.....",
    "BWB.BWWB....",
    "BB..BWWB....",
    "B....BWWB...",
    ".....BWWB...",
    "......BB....",
}
local ROWS, COLS = #PIXEL_MAP, #PIXEL_MAP[1]
local cursor = Instance.new("Frame")
cursor.Name = "PixelCursor"
cursor.BackgroundTransparency = 1
cursor.BorderSizePixel = 0
cursor.Active = false
cursor.Visible = true
cursor.ZIndex = 50
cursor.Parent = gui
local whitePixels = {}
for r = 1, ROWS do
    local row = PIXEL_MAP[r]
    local c = 1
    while c <= COLS do
        local ch = row:sub(c, c)
        if ch == "." then
            c += 1
        else
            local last = c
            while last < COLS and row:sub(last + 1, last + 1) == ch do last += 1 end
            local pixel = Instance.new("Frame")
            pixel.Name = ch == "B" and "BlackPixel" or "WhitePixel"
            pixel.BorderSizePixel = 0
            pixel.BackgroundColor3 = ch == "B" and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
            pixel.Position = UDim2.fromScale((c - 1) / COLS, (r - 1) / ROWS)
            pixel.Size = UDim2.fromScale((last - c + 1) / COLS, 1 / ROWS)
            pixel.ZIndex = 51
            pixel.Active = false
            pixel.Parent = cursor
            if ch == "W" then table.insert(whitePixels, pixel) end
            c = last + 1
        end
    end
end

local screen = gui.AbsoluteSize
local cx, cy = math.floor(screen.X * 0.5), math.floor(screen.Y * 0.5)
local enabled, dragging, scrolling, cleaned = true, false, false, false
local touches, touchCount = {}, 0
local lastTap, scrollAcc = 0, 0
local connections = {}
local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end
local function cursorSize()
    return math.max(12, cfg.size)
end
local function updateCursor()
    local size = cursorSize()
    cursor.Size = UDim2.fromOffset(size * COLS / ROWS, size)
    cursor.Position = UDim2.fromOffset(cx, cy)
    cursor.Visible = enabled
end
local function setDrawColor(on)
    for _, p in ipairs(whitePixels) do
        p.BackgroundColor3 = on and Color3.fromRGB(255, 210, 70) or Color3.new(1, 1, 1)
    end
end
local function sendMove()
    if not VIM then return false end
    return pcall(function()
        VIM:SendMouseMoveEvent(math.floor(cx), math.floor(cy + cfg.offsetY), game)
    end)
end
local function sendButton(down)
    if not VIM then return false end
    return pcall(function()
        VIM:SendMouseButtonEvent(math.floor(cx), math.floor(cy + cfg.offsetY), 0, down, game, 0)
    end)
end
local function sendWheel(direction)
    if not VIM then return false end
    return pcall(function()
        VIM:SendMouseWheelEvent(math.floor(cx), math.floor(cy + cfg.offsetY), direction, game)
    end)
end
local function moveCursor(dx, dy)
    local s = gui.AbsoluteSize
    local w = cursor.AbsoluteSize.X
    local h = cursor.AbsoluteSize.Y
    cx = math.clamp(cx + dx, 0, math.max(0, s.X - w))
    cy = math.clamp(cy + dy, 0, math.max(0, s.Y - h))
    updateCursor()
    sendMove()
end
local function startDrag()
    if dragging or not enabled then return end
    dragging = true
    sendMove()
    sendButton(true)
    setDrawColor(true)
end
local function stopDrag()
    if not dragging then return end
    dragging = false
    sendButton(false)
    setDrawColor(false)
end
local function clickMouse()
    sendMove()
    sendButton(true)
    task.wait(0.045)
    sendButton(false)
end

-- Small helpers for the floating controls.
local function round(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = obj
end
local function makeFloat(text, position, size, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(size, size)
    b.Position = position
    b.BackgroundColor3 = Color3.fromRGB(30, 31, 36)
    b.BackgroundTransparency = 0.08
    b.Text = text
    b.TextColor3 = Color3.new(1, 1, 1)
    b.TextSize = 14
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = true
    b.Active = true
    b.ZIndex = 80
    b.Parent = gui
    round(b, size)
    local down, startPos, origin, moved
    b.InputBegan:Connect(function(input)
        if isTouch(input) or input.UserInputType == Enum.UserInputType.MouseButton1 then
            down = input
            startPos = Vector2.new(input.Position.X, input.Position.Y)
            origin = b.AbsolutePosition
            moved = false
        end
    end)
    connect(UIS.InputChanged, function(input)
        if not down then return end
        if input == down or input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - startPos
            if delta.Magnitude > 8 then moved = true end
            if moved then
                local s = gui.AbsoluteSize
                b.Position = UDim2.fromOffset(
                    math.clamp(origin.X + delta.X, 0, math.max(0, s.X - size)),
                    math.clamp(origin.Y + delta.Y, 0, math.max(0, s.Y - size))
                )
            end
        end
    end)
    connect(UIS.InputEnded, function(input)
        if down and (input == down or input.UserInputType == Enum.UserInputType.MouseButton1) then
            down = nil
            if not moved then callback() end
        end
    end)
    return b
end

local panel = Instance.new("Frame")
panel.Name = "SettingsPanel"
panel.Size = UDim2.fromOffset(250, 250)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 29)
panel.BorderSizePixel = 0
panel.Active = true
panel.Visible = false
panel.ZIndex = 60
panel.Parent = gui
round(panel, 12)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(75, 78, 88)
panelStroke.Thickness = 1
panelStroke.Parent = panel
local header = Instance.new("TextLabel")
header.Size = UDim2.new(1, 0, 0, 32)
header.BackgroundColor3 = Color3.fromRGB(38, 40, 47)
header.BorderSizePixel = 0
header.Text = "BLOCK CLIENT  /  PIXEL MOUSE"
header.TextColor3 = Color3.new(1, 1, 1)
header.Font = Enum.Font.GothamBold
header.TextSize = 11
header.ZIndex = 61
header.Parent = panel
round(header, 10)
local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(12, 38)
status.Size = UDim2.new(1, -24, 0, 28)
status.BackgroundTransparency = 1
status.Text = VIM and "Mouse input: API found" or "Mouse input: API unavailable"
status.TextColor3 = Color3.fromRGB(210, 210, 220)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Font = Enum.Font.Gotham
status.TextSize = 10
status.ZIndex = 61
status.Parent = panel

local sliding
local function makeSlider(y, labelText, min, max, key, fmt)
    local label = Instance.new("TextLabel")
    label.Position = UDim2.fromOffset(12, y)
    label.Size = UDim2.new(1, -24, 0, 20)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 12
    label.ZIndex = 61
    label.Parent = panel
    local track = Instance.new("Frame")
    track.Position = UDim2.fromOffset(16, y + 27)
    track.Size = UDim2.new(1, -32, 0, 8)
    track.BackgroundColor3 = Color3.fromRGB(75, 75, 82)
    track.BorderSizePixel = 0
    track.Active = true
    track.ZIndex = 61
    track.Parent = panel
    round(track, 8)
    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Size = UDim2.fromOffset(18, 18)
    knob.BackgroundColor3 = Color3.fromRGB(65, 130, 245)
    knob.BorderSizePixel = 0
    knob.ZIndex = 62
    knob.Parent = track
    round(knob, 9)
    local function set(v)
        v = math.floor(v * 10 + 0.5) / 10
        cfg[key] = v
        knob.Position = UDim2.new(math.clamp((v - min) / (max - min), 0, 1), 0, 0.5, 0)
        label.Text = labelText .. string.format(fmt, v)
        if key == "size" then updateCursor() end
    end
    set(math.clamp(cfg[key], min, max))
    local function update(input)
        local width = math.max(1, track.AbsoluteSize.X)
        local alpha = math.clamp((input.Position.X - track.AbsolutePosition.X) / width, 0, 1)
        set(min + alpha * (max - min))
    end
    local id = {}
    track.InputBegan:Connect(function(input)
        if isTouch(input) or input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = id
            update(input)
        end
    end)
    connect(UIS.InputChanged, function(input)
        if sliding == id and (isTouch(input) or input.UserInputType == Enum.UserInputType.MouseMovement) then update(input) end
    end)
    connect(UIS.InputEnded, function()
        if sliding == id then sliding = nil; saveCfg() end
    end)
end

makeSlider(76, "Cursor size: ", 16, 100, "size", "%d")
makeSlider(136, "Movement speed: ", 0.5, 6, "speed", "%.1fx")

local function panelButton(text, x, callback, color)
    local b = Instance.new("TextButton")
    b.Position = UDim2.new(x, x == 0 and 12 or 6, 1, -40)
    b.Size = UDim2.new(0.5, -18, 0, 30)
    b.BackgroundColor3 = color
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.ZIndex = 62
    b.Parent = panel
    round(b, 7)
    b.Activated:Connect(callback)
    return b
end

local toggleButton
local function setEnabled(value)
    enabled = value
    overlay.Visible = value
    cursor.Visible = value
    if not value then
        stopDrag()
        touches, touchCount, scrolling = {}, 0, false
        sliding = nil
    end
    if toggleButton then
        toggleButton.Text = value and "ON" or "OFF"
        toggleButton.BackgroundColor3 = value and Color3.fromRGB(35, 155, 80) or Color3.fromRGB(190, 55, 55)
    end
end
local gearButton = makeFloat("SET", UDim2.new(0, 10, 0.60, 0), 44, function()
    panel.Visible = not panel.Visible
    if panel.Visible then
        local s, p = gui.AbsoluteSize, gearButton.AbsolutePosition
        panel.Position = UDim2.fromOffset(math.clamp(p.X + 52, 0, math.max(0, s.X - 250)), math.clamp(p.Y - 110, 0, math.max(0, s.Y - 250)))
    end
end)
toggleButton = makeFloat("ON", UDim2.new(0, 10, 0.60, 52), 44, function() setEnabled(not enabled) end)
toggleButton.BackgroundColor3 = Color3.fromRGB(35, 155, 80)
panelButton("Hide / show", 0, function() setEnabled(not enabled) end, Color3.fromRGB(55, 110, 210))
local closeButton = panelButton("Close script", 0.5, function()
    if Env.__VM_PIXEL_CLEAN then Env.__VM_PIXEL_CLEAN() end
end, Color3.fromRGB(190, 55, 55))

-- Relative touchpad input. A touch starting far from the cursor never teleports it.
connect(overlay.InputBegan, function(input)
    if not enabled or not isTouch(input) then return end
    local st = {
        start = os.clock(),
        lastX = input.Position.X,
        lastY = input.Position.Y,
        startX = input.Position.X,
        startY = input.Position.Y,
        moved = false,
    }
    touches[input] = st
    touchCount += 1
    if touchCount >= 2 then
        scrolling = true
        scrollAcc = 0
        for _, t in pairs(touches) do t.moved = true end
        stopDrag()
        return
    end
    scrolling = false
    task.delay(HOLD_TIME, function()
        if enabled and touches[input] == st and not st.moved and touchCount == 1 and not scrolling then
            startDrag()
        end
    end)
end)

connect(UIS.InputChanged, function(input)
    if not enabled or not isTouch(input) then return end
    local st = touches[input]
    if not st then return end
    local x, y = input.Position.X, input.Position.Y
    local dx, dy = x - st.lastX, y - st.lastY
    st.lastX, st.lastY = x, y
    if touchCount >= 2 or scrolling then
        scrollAcc += dy * cfg.scroll
        while scrollAcc >= 12 do scrollAcc -= 12; sendWheel(true) end
        while scrollAcc <= -12 do scrollAcc += 12; sendWheel(false) end
        st.moved = true
        return
    end
    if not st.moved then
        local distance = (Vector2.new(x, y) - Vector2.new(st.startX, st.startY)).Magnitude
        if distance > MOVE_TOL then
            st.moved = true
            moveCursor((x - st.startX) * cfg.speed, (y - st.startY) * cfg.speed)
        end
    else
        moveCursor(dx * cfg.speed, dy * cfg.speed)
    end
end)

connect(UIS.InputEnded, function(input)
    if not isTouch(input) then return end
    local st = touches[input]
    if not st then return end
    touches[input] = nil
    touchCount = math.max(0, touchCount - 1)
    if touchCount > 0 then return end
    if dragging then stopDrag(); scrolling = false; return end
    if scrolling then scrolling = false; return end
    local now = os.clock()
    if not st.moved and now - st.start <= TAP_MAX then
        if now - lastTap <= DOUBLE_TIME then
            lastTap = 0
            task.spawn(clickMouse)
        else
            lastTap = now
        end
    end
end)

local function cleanup()
    if cleaned then return end
    cleaned = true
    enabled = false
    pcall(stopDrag)
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections = {}
    pcall(function() gui:Destroy() end)
    if Env.__VM_PIXEL_CLEAN then Env.__VM_PIXEL_CLEAN = nil end
end
Env.__VM_PIXEL_CLEAN = cleanup

-- Wait one frame so AbsoluteSize is valid before first cursor render.
task.defer(function()
    if not gui.Parent then return end
    local s = gui.AbsoluteSize
    cx, cy = math.floor(s.X * 0.5), math.floor(s.Y * 0.5)
    updateCursor()
    sendMove()
end)
print("[Block Client] Pixel virtual mouse loaded")
