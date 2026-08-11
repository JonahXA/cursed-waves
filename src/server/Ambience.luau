--[[
	Ambience — lighting, atmosphere and post-processing.

	Roblox's default lighting is deliberately neutral, which reads as "unfinished
	baseplate" to a player. Almost none of the perceived quality gap between a
	prototype and a shipped game is geometry; a large part of it is that shipped
	games set their lighting.

	This is about sixty lines and it is the highest visual return per line in the
	whole project.
]]

local Lighting = game:GetService("Lighting")

local Ambience = {}

local function clearExisting()
	for _, className in
		{ "Atmosphere", "Sky", "BloomEffect", "ColorCorrectionEffect", "SunRaysEffect" }
	do
		local existing = Lighting:FindFirstChildOfClass(className)
		while existing do
			existing:Destroy()
			existing = Lighting:FindFirstChildOfClass(className)
		end
	end
end

function Ambience.apply()
	clearExisting()

	-- Late-afternoon sun: long shadows give flat geometry visible form, which
	-- matters more here than anywhere because the towers ARE flat geometry.
	Lighting.ClockTime = 16.5
	Lighting.GeographicLatitude = 20
	Lighting.Brightness = 2.2
	Lighting.ExposureCompensation = 0.1
	Lighting.GlobalShadows = true
	Lighting.Technology = Enum.Technology.Future
	Lighting.Ambient = Color3.fromRGB(70, 66, 84)
	Lighting.OutdoorAmbient = Color3.fromRGB(112, 108, 132)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 226, 190)
	Lighting.ColorShift_Bottom = Color3.fromRGB(80, 70, 110)
	Lighting.FogEnd = 100000

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(199, 190, 206)
	atmosphere.Decay = Color3.fromRGB(92, 60, 106)
	atmosphere.Glare = 0.35
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 12
	sky.MoonAngularSize = 8
	sky.StarCount = 1200
	sky.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.55
	bloom.Size = 24
	bloom.Threshold = 1.1
	bloom.Parent = Lighting

	-- A slight cool tint and lifted contrast. Deliberately subtle: the point is
	-- that the scene looks graded rather than that anyone notices a filter.
	local colour = Instance.new("ColorCorrectionEffect")
	colour.Brightness = 0.02
	colour.Contrast = 0.14
	colour.Saturation = 0.12
	colour.TintColor = Color3.fromRGB(238, 236, 255)
	colour.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.08
	rays.Spread = 0.6
	rays.Parent = Lighting
end

return Ambience
