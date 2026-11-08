--[[
	CHILL SHADER v1.0  |  Tối ưu cho iPhone 11 (mobile executor)
	- Chỉ thay đổi hình ảnh phía client (chỉ mình bạn thấy)
	- Chạy lại script để đổi cấu hình, bản cũ tự được dọn và khôi phục
	- Muốn tắt hẳn: chạy dòng này  ->  getgenv().ChillShader.Destroy()
]]

----------------------------------------------------------------
-- CẤU HÌNH (sửa ở đây)
----------------------------------------------------------------
local CONFIG = {
	PRESET = "MAX",        -- "MAX" | "BALANCED" | "LITE"   (lag thì hạ xuống)
	THEME  = "SUNSET",     -- "SUNSET" | "DREAMY" | "FRESH" | "NIGHT"
	TECH   = "ShadowMap",  -- "Voxel" | "ShadowMap" | "Future" (Future rất nặng, iPhone 11 dễ tụt FPS)
	WATER  = true,         -- chỉnh nước trong veo, phản chiếu đẹp hơn
	NOTIFY = true,         -- hiện thông báo khi bật xong
}

----------------------------------------------------------------
-- DỊCH VỤ
----------------------------------------------------------------
local Lighting   = game:GetService("Lighting")
local Workspace  = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local env = (getgenv and getgenv()) or _G
if env.ChillShader and env.ChillShader.Destroy then
	pcall(env.ChillShader.Destroy)
end

----------------------------------------------------------------
-- THEME MÀU
----------------------------------------------------------------
local THEMES = {
	SUNSET = { -- hoàng hôn vàng cam, ấm áp
		clock = 17.7, brightness = 2.4, exposure = 0.15,
		ambient = Color3.fromRGB(80, 65, 85),
		outdoor = Color3.fromRGB(125, 105, 115),
		shiftTop = Color3.fromRGB(255, 185, 120),
		shiftBottom = Color3.fromRGB(70, 45, 80),
		tint = Color3.fromRGB(255, 232, 210),
		saturation = 0.22, contrast = 0.12, cbright = 0.0,
		atmoColor = Color3.fromRGB(255, 195, 160),
		atmoDecay = Color3.fromRGB(255, 125, 95),
		density = 0.36, offset = 0.28, glare = 0.7, haze = 1.9,
		bloom = 0.5, bloomThreshold = 0.88, sunrays = 0.16,
		stars = 0, water = Color3.fromRGB(40, 120, 140),
	},
	DREAMY = { -- tím hồng lofi, mơ màng
		clock = 18.3, brightness = 2.2, exposure = 0.1,
		ambient = Color3.fromRGB(90, 70, 110),
		outdoor = Color3.fromRGB(135, 110, 150),
		shiftTop = Color3.fromRGB(255, 170, 200),
		shiftBottom = Color3.fromRGB(80, 50, 120),
		tint = Color3.fromRGB(255, 222, 240),
		saturation = 0.28, contrast = 0.1, cbright = 0.01,
		atmoColor = Color3.fromRGB(235, 185, 230),
		atmoDecay = Color3.fromRGB(170, 120, 225),
		density = 0.4, offset = 0.3, glare = 0.55, haze = 2.1,
		bloom = 0.65, bloomThreshold = 0.85, sunrays = 0.12,
		stars = 800, water = Color3.fromRGB(70, 110, 170),
	},
	FRESH = { -- ban ngày trong trẻo, xanh mát
		clock = 14.5, brightness = 3.0, exposure = 0.05,
		ambient = Color3.fromRGB(85, 95, 110),
		outdoor = Color3.fromRGB(140, 150, 165),
		shiftTop = Color3.fromRGB(255, 245, 225),
		shiftBottom = Color3.fromRGB(40, 55, 80),
		tint = Color3.fromRGB(238, 247, 255),
		saturation = 0.25, contrast = 0.14, cbright = 0.0,
		atmoColor = Color3.fromRGB(190, 215, 255),
		atmoDecay = Color3.fromRGB(120, 165, 225),
		density = 0.28, offset = 0.2, glare = 0.3, haze = 1.3,
		bloom = 0.35, bloomThreshold = 0.92, sunrays = 0.1,
		stars = 0, water = Color3.fromRGB(25, 130, 150),
	},
	NIGHT = { -- đêm trăng xanh, nhiều sao
		clock = 0.6, brightness = 1.4, exposure = 0.35,
		ambient = Color3.fromRGB(45, 55, 95),
		outdoor = Color3.fromRGB(65, 80, 130),
		shiftTop = Color3.fromRGB(150, 180, 255),
		shiftBottom = Color3.fromRGB(20, 25, 60),
		tint = Color3.fromRGB(205, 220, 255),
		saturation = 0.12, contrast = 0.15, cbright = 0.01,
		atmoColor = Color3.fromRGB(70, 90, 150),
		atmoDecay = Color3.fromRGB(40, 55, 110),
		density = 0.34, offset = 0.1, glare = 0.2, haze = 1.6,
		bloom = 0.75, bloomThreshold = 0.8, sunrays = 0.0,
		stars = 3000, water = Color3.fromRGB(20, 55, 100),
	},
}

local QUALITY = {
	MAX      = { bloomSize = 40, sunrays = true,  dof = true,  shadowSoft = 0.12 },
	BALANCED = { bloomSize = 28, sunrays = true,  dof = false, shadowSoft = 0.25 },
	LITE     = { bloomSize = 20, sunrays = false, dof = false, shadowSoft = 0.4  },
}

local T = THEMES[string.upper(tostring(CONFIG.THEME))] or THEMES.SUNSET
local Q = QUALITY[string.upper(tostring(CONFIG.PRESET))] or QUALITY.MAX

----------------------------------------------------------------
-- LƯU TRẠNG THÁI GỐC (để khôi phục khi tắt)
----------------------------------------------------------------
local LIGHT_PROPS = {
	"Brightness", "ClockTime", "Ambient", "OutdoorAmbient",
	"ColorShift_Top", "ColorShift_Bottom", "ExposureCompensation",
	"EnvironmentDiffuseScale", "EnvironmentSpecularScale", "GlobalShadows",
	"FogStart", "FogEnd", "FogColor", "ShadowSoftness",
}

local saved = {}
for _, p in ipairs(LIGHT_PROPS) do
	local ok, v = pcall(function() return Lighting[p] end)
	if ok then saved[p] = v end
end

local origTech
pcall(function()
	if gethiddenproperty then
		origTech = gethiddenproperty(Lighting, "Technology")
	end
end)

local terrain = Workspace:FindFirstChildOfClass("Terrain")
local savedWater
if terrain then
	pcall(function()
		savedWater = {
			WaterColor = terrain.WaterColor,
			WaterReflectance = terrain.WaterReflectance,
			WaterTransparency = terrain.WaterTransparency,
			WaterWaveSize = terrain.WaterWaveSize,
			WaterWaveSpeed = terrain.WaterWaveSpeed,
		}
	end)
end

-- Tắt hiệu ứng có sẵn của game để không bị chồng lên nhau
local disabledFx, removedAtmos = {}, {}
for _, c in ipairs(Lighting:GetChildren()) do
	if c:IsA("PostEffect") and c.Enabled then
		c.Enabled = false
		table.insert(disabledFx, c)
	elseif c:IsA("Atmosphere") then
		table.insert(removedAtmos, c)
		c.Parent = nil
	end
end

----------------------------------------------------------------
-- TẠO HIỆU ỨNG
----------------------------------------------------------------
local created = {}

local function make(class, name, props)
	local o = Instance.new(class)
	o.Name = name
	for k, v in pairs(props) do
		pcall(function() o[k] = v end)
	end
	o.Parent = Lighting
	table.insert(created, o)
	return o
end

make("Atmosphere", "CS_Atmosphere", {
	Density = T.density, Offset = T.offset,
	Color = T.atmoColor, Decay = T.atmoDecay,
	Glare = T.glare, Haze = T.haze,
})

make("BloomEffect", "CS_Bloom", {
	Intensity = T.bloom, Size = Q.bloomSize, Threshold = T.bloomThreshold,
})

make("ColorCorrectionEffect", "CS_Color", {
	Brightness = T.cbright, Contrast = T.contrast,
	Saturation = T.saturation, TintColor = T.tint,
})

if Q.sunrays and T.sunrays > 0 then
	make("SunRaysEffect", "CS_SunRays", { Intensity = T.sunrays, Spread = 0.85 })
end

if Q.dof then
	make("DepthOfFieldEffect", "CS_DOF", {
		FarIntensity = 0.1, NearIntensity = 0,
		FocusDistance = 50, InFocusRadius = 70,
	})
end

if not Lighting:FindFirstChildOfClass("Sky") then
	make("Sky", "CS_Sky", { StarCount = T.stars })
elseif T.stars > 0 then
	local sky = Lighting:FindFirstChildOfClass("Sky")
	pcall(function() sky.StarCount = T.stars end)
end

----------------------------------------------------------------
-- ÁP DỤNG ÁNH SÁNG (lặp nhẹ để chống game reset)
----------------------------------------------------------------
local function setL(prop, value)
	pcall(function() Lighting[prop] = value end)
end

local function applyLighting()
	setL("Brightness", T.brightness)
	setL("ClockTime", T.clock)
	setL("Ambient", T.ambient)
	setL("OutdoorAmbient", T.outdoor)
	setL("ColorShift_Top", T.shiftTop)
	setL("ColorShift_Bottom", T.shiftBottom)
	setL("ExposureCompensation", T.exposure)
	setL("EnvironmentDiffuseScale", 1)
	setL("EnvironmentSpecularScale", 1)
	setL("GlobalShadows", true)
	setL("ShadowSoftness", Q.shadowSoft)
	setL("FogStart", 0)
	setL("FogEnd", 100000)

	for _, o in ipairs(created) do
		if o.Parent ~= Lighting then
			pcall(function() o.Parent = Lighting end)
		end
	end
end

pcall(function()
	if sethiddenproperty then
		sethiddenproperty(Lighting, "Technology", Enum.Technology[CONFIG.TECH])
	end
end)

applyLighting()

if CONFIG.WATER and terrain then
	pcall(function()
		terrain.WaterColor = T.water
		terrain.WaterReflectance = 0.85
		terrain.WaterTransparency = 0.9
		terrain.WaterWaveSize = 0.15
		terrain.WaterWaveSpeed = 12
	end)
end

local alive = true
task.spawn(function()
	while alive do
		task.wait(2)
		if alive then applyLighting() end
	end
end)

----------------------------------------------------------------
-- TẮT / KHÔI PHỤC
----------------------------------------------------------------
local function destroy()
	alive = false

	for _, o in ipairs(created) do
		pcall(function() o:Destroy() end)
	end
	for _, fx in ipairs(disabledFx) do
		pcall(function() fx.Enabled = true end)
	end
	for _, a in ipairs(removedAtmos) do
		pcall(function() a.Parent = Lighting end)
	end
	for p, v in pairs(saved) do
		setL(p, v)
	end
	if origTech then
		pcall(function() sethiddenproperty(Lighting, "Technology", origTech) end)
	end
	if terrain and savedWater then
		for p, v in pairs(savedWater) do
			pcall(function() terrain[p] = v end)
		end
	end
	env.ChillShader = nil
end

env.ChillShader = { Destroy = destroy }

if CONFIG.NOTIFY then
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Chill Shader",
			Text = string.format("%s | %s", string.upper(CONFIG.THEME), string.upper(CONFIG.PRESET)),
			Duration = 4,
		})
	end)
end
