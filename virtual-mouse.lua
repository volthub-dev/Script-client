--[[
  CHUỘT ẢO CẢM ỨNG cho executor (Delta / Arceus X / Codex / Hydrogen ...)
  - Vuốt 1 ngón  : di chuyển chuột (kiểu touchpad, KHÔNG tele tới chỗ chạm)
  - Chạm 2 lần   : click
  - Chạm giữ rồi vuốt : nhấn giữ + kéo (thả tay = nhả chuột)
  - Vuốt 2 ngón  : lăn chuột (cuộn / zoom)
  - Nút ⚙ (góc trái)  : chỉnh kích thước, tốc độ chuột, tốc độ cuộn, ẩn/hiện, tắt hẳn
  Chạy lại script lần nữa sẽ tự xoá bản cũ.
]]

if getgenv and getgenv().__VM_CLEAN then pcall(getgenv().__VM_CLEAN) end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local VIM = game:GetService("VirtualInputManager")

----------------------------------------------------------------
-- Cấu hình
----------------------------------------------------------------
local FILE = "vmouse_cfg.json"
local cfg = { size = 56, speed = 1.8, scroll = 1.0, offsetY = 0 }
-- offsetY: nếu click bị lệch theo chiều dọc, thử đặt 36 (hoặc -36)

pcall(function()
	if readfile and isfile and isfile(FILE) then
		for k, v in pairs(HttpService:JSONDecode(readfile(FILE))) do cfg[k] = v end
	end
end)
local function saveCfg()
	pcall(function() if writefile then writefile(FILE, HttpService:JSONEncode(cfg)) end end)
end

local HOLD, DOUBLE, TAP_MAX, TOL = 0.35, 0.32, 0.25, 10

----------------------------------------------------------------
-- GUI
----------------------------------------------------------------
local function getParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local gui = Instance.new("ScreenGui")
gui.Name = "VirtualMouse"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
gui.Parent = getParent()

-- Lớp phủ bắt toàn bộ cảm ứng (chặn không cho chạm thẳng vào game)
local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundTransparency = 1
overlay.Active = true
overlay.ZIndex = 1
overlay.Parent = gui

-- Con trỏ vẽ bằng pixel
local MAP = {
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
local COLS, ROWS = #MAP[1], #MAP

local cursor = Instance.new("Frame")
cursor.Name = "Cursor"
cursor.BackgroundTransparency = 1
cursor.Active = false
cursor.ZIndex = 50
cursor.Parent = gui

local whiteCells = {}
for r = 1, ROWS do
	local row = MAP[r]
	local c = 1
	while c <= COLS do
		local ch = row:sub(c, c)
		if ch ~= "." then
			local e = c
			while e < COLS and row:sub(e + 1, e + 1) == ch do e = e + 1 end
			local cell = Instance.new("Frame")
			cell.BorderSizePixel = 0
			cell.BackgroundColor3 = (ch == "B") and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
			cell.Position = UDim2.fromScale((c - 1) / COLS, (r - 1) / ROWS)
			cell.Size = UDim2.fromScale((e - c + 1) / COLS, 1 / ROWS)
			cell.ZIndex = 50
			cell.Active = false
			cell.Parent = cursor
			if ch == "W" then table.insert(whiteCells, cell) end
			c = e + 1
		else
			c += 1
		end
	end
end

local function setDragColor(on)
	for _, cell in ipairs(whiteCells) do
		cell.BackgroundColor3 = on and Color3.fromRGB(255, 213, 74) or Color3.new(1, 1, 1)
	end
end

-- vị trí chuột
local vp = gui.AbsoluteSize
local cx, cy = vp.X / 2, vp.Y / 2

local function updateCursor()
	cursor.Size = UDim2.fromOffset(cfg.size * COLS / ROWS, cfg.size)
	cursor.Position = UDim2.fromOffset(cx, cy)
end
updateCursor()

----------------------------------------------------------------
-- Gửi sự kiện chuột giả
----------------------------------------------------------------
local function sendMove()
	pcall(function() VIM:SendMouseMoveEvent(cx, cy + cfg.offsetY, game) end)
end
local function sendButton(isDown)
	pcall(function() VIM:SendMouseButtonEvent(cx, cy + cfg.offsetY, 0, isDown, game, 0) end)
end
local function sendWheel(forward)
	pcall(function() VIM:SendMouseWheelEvent(cx, cy + cfg.offsetY, forward, game) end)
end

local function moveCursor(dx, dy)
	local s = gui.AbsoluteSize
	cx = math.clamp(cx + dx, 0, s.X - 1)
	cy = math.clamp(cy + dy, 0, s.Y - 1)
	updateCursor()
	sendMove()
end

local function click()
	overlay.Active = false -- cho click xuyên qua lớp phủ
	task.wait()
	sendMove()
	sendButton(true)
	task.wait(0.04)
	sendButton(false)
	task.wait()
	overlay.Active = true
end

local dragging = false
local function startDrag()
	dragging = true
	overlay.Active = false
	task.wait()
	sendMove()
	sendButton(true)
	setDragColor(true)
	pcall(function() game:GetService("HapticService") end)
end
local function stopDrag()
	if not dragging then return end
	dragging = false
	sendButton(false)
	setDragColor(false)
	task.wait()
	overlay.Active = true
end

----------------------------------------------------------------
-- Xử lý cảm ứng
----------------------------------------------------------------
local conns = {}
local touches, count = {}, 0
local scrolling, enabled = false, true
local lastTap, scrollAcc = 0, 0

local function isTouch(i) return i.UserInputType == Enum.UserInputType.Touch end

-- chỉ nhận cảm ứng bắt đầu trên vùng trống (không phải trên nút ⚙/bảng)
table.insert(conns, overlay.InputBegan:Connect(function(input)
	if not isTouch(input) or not enabled then return end
	local st = {
		start = os.clock(),
		sx = input.Position.X,
		sy = input.Position.Y,
		moved = false,
	}
	touches[input] = st
	count += 1

	if count >= 2 then
		scrolling = true
		scrollAcc = 0
		for _, t in pairs(touches) do t.moved = true end
		if dragging then stopDrag() end
		return
	end
	if scrolling then return end

	task.delay(HOLD, function()
		if touches[input] == st and not st.moved and not scrolling and not dragging then
			startDrag()
		end
	end)
end))

table.insert(conns, UIS.InputChanged:Connect(function(input)
	if not isTouch(input) then return end
	local st = touches[input]
	if not st then return end

	if count >= 2 then
		scrollAcc += input.Delta.Y * cfg.scroll
		while scrollAcc >= 12 do scrollAcc -= 12; sendWheel(true) end
		while scrollAcc <= -12 do scrollAcc += 12; sendWheel(false) end
		return
	end
	if scrolling then return end

	if not st.moved then
		local d = Vector2.new(input.Position.X - st.sx, input.Position.Y - st.sy)
		if d.Magnitude > TOL then st.moved = true end
	end
	if st.moved or dragging then
		moveCursor(input.Delta.X * cfg.speed, input.Delta.Y * cfg.speed)
	end
end))

table.insert(conns, UIS.InputEnded:Connect(function(input)
	if not isTouch(input) then return end
	local st = touches[input]
	if not st then return end
	touches[input] = nil
	count -= 1
	if count > 0 then return end
	count = 0

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
	if not st.moved and (now - st.start) < TAP_MAX then
		if now - lastTap < DOUBLE then
			lastTap = 0
			task.spawn(click)
		else
			lastTap = now
		end
	end
end))

----------------------------------------------------------------
-- Bảng cài đặt
----------------------------------------------------------------
local gear = Instance.new("TextButton")
gear.Size = UDim2.fromOffset(44, 44)
gear.Position = UDim2.new(0, 10, 0.6, 0)
gear.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
gear.BackgroundTransparency = 0.15
gear.Text = "⚙"
gear.TextColor3 = Color3.new(1, 1, 1)
gear.TextSize = 24
gear.ZIndex = 20
gear.Parent = gui
Instance.new("UICorner", gear).CornerRadius = UDim.new(1, 0)

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(250, 250)
panel.Position = UDim2.new(0, 60, 0.6, -100)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
panel.BackgroundTransparency = 0.05
panel.Active = true
panel.Visible = false
panel.ZIndex = 20
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

gear.Activated:Connect(function() panel.Visible = not panel.Visible end)

local sliding -- slider đang kéo
local function makeSlider(y, label, min, max, key, fmt, integer)
	local lab = Instance.new("TextLabel")
	lab.BackgroundTransparency = 1
	lab.Position = UDim2.fromOffset(12, y)
	lab.Size = UDim2.new(1, -24, 0, 20)
	lab.TextXAlignment = Enum.TextXAlignment.Left
	lab.TextColor3 = Color3.new(1, 1, 1)
	lab.TextSize = 14
	lab.Font = Enum.Font.GothamMedium
	lab.ZIndex = 21
	lab.Parent = panel

	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(16, y + 34)
	track.Size = UDim2.new(1, -32, 0, 8)
	track.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
	track.Active = true
	track.ZIndex = 21
	track.Parent = panel
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(24, 24)
	knob.BackgroundColor3 = Color3.fromRGB(59, 130, 246)
	knob.ZIndex = 22
	knob.Parent = track
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local function set(v)
		if integer then v = math.floor(v + 0.5) else v = math.floor(v * 10 + 0.5) / 10 end
		cfg[key] = v
		knob.Position = UDim2.new((v - min) / (max - min), 0, 0.5, 0)
		lab.Text = label .. string.format(fmt, v)
		if key == "size" then updateCursor() end
	end
	set(cfg[key])

	local function upd(input)
		local a = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		set(min + a * (max - min))
	end
	local me = {}
	track.InputBegan:Connect(function(input)
		if isTouch(input) or input.UserInputType == Enum.UserInputType.MouseButton1 then
			sliding = me
			upd(input)
		end
	end)
	table.insert(conns, UIS.InputChanged:Connect(function(input)
		if sliding == me and (isTouch(input) or input.UserInputType == Enum.UserInputType.MouseMovement) then
			upd(input)
		end
	end))
	table.insert(conns, UIS.InputEnded:Connect(function(input)
		if sliding == me then sliding = nil; saveCfg() end
	end))
end

makeSlider(8, "Kích thước: ", 16, 160, "size", "%d", true)
makeSlider(68, "Tốc độ chuột: ", 0.5, 6, "speed", "%.1fx", false)
makeSlider(128, "Tốc độ cuộn: ", 0.5, 5, "scroll", "%.1fx", false)

local function makeButton(y, text, color, cb)
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(0, 12, 0, y)
	b.Size = UDim2.new(0.5, -18, 0, 34)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.TextSize = 14
	b.Font = Enum.Font.GothamBold
	b.ZIndex = 21
	b.Parent = panel
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	b.Activated:Connect(function() cb(b) end)
	return b
end

local hideBtn = makeButton(200, "Ẩn chuột", Color3.fromRGB(59, 130, 246), function(b)
	enabled = not enabled
	overlay.Visible = enabled
	cursor.Visible = enabled
	b.Text = enabled and "Ẩn chuột" or "Hiện chuột"
	if not enabled then stopDrag() end
end)

local function cleanup()
	pcall(stopDrag)
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	pcall(function() gui:Destroy() end)
	if getgenv then getgenv().__VM_CLEAN = nil end
end
local closeBtn = makeButton(200, "Tắt hẳn", Color3.fromRGB(220, 60, 60), cleanup)
closeBtn.Position = UDim2.new(0.5, 6, 0, 200)

if getgenv then getgenv().__VM_CLEAN = cleanup end
