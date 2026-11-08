-- TSB STATUS HUD v3
-- FPS | PING | HEAD | TOTAL KILLS | CURRENT KILLS
-- Fixed position | Compact transparent grey HUD
-- Kill reader: local player's replicated leaderboard stats

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Player = Players.LocalPlayer

local Config = {
    Width = 273,
    Height = 153,
    X = 95,
    Y = 110,
    BackgroundTransparency = 0.28,
    UpdateRate = 0.5
}

-- GUI PARENT
local function getParent()
    if typeof(gethui) == "function" then
        return gethui()
    end
    return Player:WaitForChild("PlayerGui")
end

local Parent = getParent()

-- REMOVE OLD HUD
local old = Parent:FindFirstChild("TSB_STATUS_HUD")
if old then
    old:Destroy()
end

-- CREATE GUI
local Gui = Instance.new("ScreenGui")
Gui.Name = "TSB_STATUS_HUD"
Gui.ResetOnSpawn = false
Gui.DisplayOrder = 999
Gui.IgnoreGuiInset = true
Gui.Parent = Parent

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(Config.Width, Config.Height)
Main.Position = UDim2.fromOffset(Config.X, Config.Y)
Main.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
Main.BackgroundTransparency = Config.BackgroundTransparency
Main.BorderSizePixel = 0
Main.Parent = Gui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 9)
Corner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(145, 145, 145)
Stroke.Transparency = 0.55
Stroke.Thickness = 0.7
Stroke.Parent = Main

local function Label(name, content, x, y, w, h, size, bold)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(x, y)
    label.Size = UDim2.fromOffset(w, h)
    label.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
    label.Text = content
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.TextSize = size or 15
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = Main
    return label
end

-- TITLE
Label("Title", "TSB / STATUS", 14, 8, 210, 18, 11, true)

-- FPS / PING
local FPS = Label("FPS", "FPS  |  --", 14, 36, 123, 16, 11)
local Ping = Label("PING", "PING  |  --", 147, 36, 123, 16, 11)

-- LOCAL PLAYER HEALTH
local Health = Label("HEAD", "HEAD  |  -- / --", 14, 64, 245, 16, 11)

local BarBG = Instance.new("Frame")
BarBG.Position = UDim2.fromOffset(14, 86)
BarBG.Size = UDim2.fromOffset(245, 4)
BarBG.BackgroundColor3 = Color3.fromRGB(85, 85, 85)
BarBG.BorderSizePixel = 0
BarBG.Parent = Main

local BarBGCorner = Instance.new("UICorner")
BarBGCorner.CornerRadius = UDim.new(1, 0)
BarBGCorner.Parent = BarBG

local Bar = Instance.new("Frame")
Bar.Size = UDim2.fromScale(1, 1)
Bar.BackgroundColor3 = Color3.fromRGB(205, 205, 205)
Bar.BorderSizePixel = 0
Bar.Parent = BarBG

local BarCorner = Instance.new("UICorner")
BarCorner.CornerRadius = UDim.new(1, 0)
BarCorner.Parent = Bar

-- KILL COUNTERS
local Total = Label("TOTAL", "TOTAL KILLS  |  --", 14, 102, 245, 15, 11)
local Current = Label("CURRENT", "CURRENT KILLS  |  --", 14, 126, 245, 15, 11)

-- FPS COUNTER
local frames = 0
local elapsed = 0

RunService.RenderStepped:Connect(function(dt)
    frames += 1
    elapsed += dt

    if elapsed >= Config.UpdateRate then
        FPS.Text = "FPS  |  " .. math.floor(frames / elapsed)
        frames = 0
        elapsed = 0
    end
end)

-- PING COUNTER
task.spawn(function()
    while Gui.Parent do
        local pingText = "--"

        pcall(function()
            local item = Stats.Network.ServerStatsItem["Data Ping"]
            pingText = item:GetValueString()
        end)

        Ping.Text = "PING  |  " .. pingText
        task.wait(Config.UpdateRate)
    end
end)

-- HEALTH: LOCAL PLAYER ONLY
local function UpdateHealth()
    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if not humanoid then
        Health.Text = "HEAD  |  -- / --"
        Bar.Size = UDim2.fromScale(0, 1)
        return
    end

    local hp = math.floor(humanoid.Health)
    local maxHP = math.floor(humanoid.MaxHealth)

    Health.Text = "HEAD  |  " .. hp .. " / " .. maxHP
    Bar.Size = UDim2.fromScale(
        math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1),
        1
    )
end

-- READ THE LOCAL PLAYER'S REPLICATED LEADERBOARD STATS
local function ReadLeaderboard()
    local total, current

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.UserId == Player.UserId then
            local stats = plr:FindFirstChild("leaderstats")

            if stats then
                for _, stat in ipairs(stats:GetChildren()) do
                    if stat:IsA("ValueBase") then
                        local name = stat.Name:lower()
                        local value = tonumber(stat.Value)

                        if value then
                            if name:find("total")
                            or name:find("lifetime")
                            or name:find("alltime") then
                                total = value
                            elseif name:find("monthly")
                            or name:find("current") then
                                current = value
                            end
                        end
                    end
                end
            end
        end
    end

    return total, current
end

-- UPDATE LEADERBOARD KILLS + HEALTH
task.spawn(function()
    while Gui.Parent do
        local total, current = ReadLeaderboard()

        Total.Text = "TOTAL KILLS  |  " ..
            (total and tostring(total) or "--")

        Current.Text = "CURRENT KILLS  |  " ..
            (current and tostring(current) or "--")

        UpdateHealth()
        task.wait(1)
    end
end)

-- RESPAWN SUPPORT
Player.CharacterAdded:Connect(function()
    task.wait(0.5)
    UpdateHealth()
end)

print("[TSB STATUS HUD v3] Loaded")
