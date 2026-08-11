--[[
	Effects — the visual feedback layer.

	Combat was invisible before this existed: towers dealt damage and enemies
	silently lost health, which made a working game read as a broken one. Seeing
	the shot land is most of what makes a tower defense feel alive.

	Everything here is server-created and short-lived, so it replicates to every
	client without a remote per shot. Debris handles cleanup, which means an
	effect can never leak even if the run ends mid-animation.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Effects = {}

local effectsFolder: Folder? = nil

local function folder(): Folder
	if effectsFolder and effectsFolder.Parent then
		return effectsFolder
	end
	local existing = Workspace:FindFirstChild("Effects")
	if existing then
		effectsFolder = existing :: Folder
		return effectsFolder
	end
	local f = Instance.new("Folder")
	f.Name = "Effects"
	f.Parent = Workspace
	effectsFolder = f
	return f
end

--[[
	A tracer from tower to target.

	Stretched part rather than a projectile: a real projectile would need to
	travel, miss, and be reconciled against an enemy that may already be dead.
	The tracer communicates the same thing and cannot desync.
]]
function Effects.tracer(from: Vector3, to: Vector3, color: Color3, thickness: number)
	local delta = to - from
	local distance = delta.Magnitude
	if distance < 0.1 then
		return
	end

	local beam = Instance.new("Part")
	beam.Name = "Tracer"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Size = Vector3.new(thickness, thickness, distance)
	beam.CFrame = CFrame.lookAt(from + delta * 0.5, to)
	beam.Parent = folder()

	TweenService:Create(beam, TweenInfo.new(0.12), {
		Transparency = 1,
		Size = Vector3.new(thickness * 0.2, thickness * 0.2, distance),
	}):Play()
	Debris:AddItem(beam, 0.2)
end

--[[ A short burst of shards at a point — used for kills. ]]
function Effects.burst(position: Vector3, color: Color3, scale: number)
	local origin = Instance.new("Part")
	origin.Name = "Burst"
	origin.Anchored = true
	origin.CanCollide = false
	origin.CanQuery = false
	origin.Transparency = 1
	origin.Size = Vector3.one
	origin.Position = position
	origin.Parent = folder()

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.4 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.25, 0.5)
	emitter.Speed = NumberRange.new(10 * scale, 20 * scale)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.LightEmission = 0.6
	emitter.Parent = origin
	emitter:Emit(math.floor(12 * scale))

	Debris:AddItem(origin, 1)
end

--[[
	A floating number.

	Damage numbers are the cheapest way to make hits legible. Without them a
	player cannot tell a Sniper from a Pea except by watching a health bar move,
	which is exactly the kind of invisible feedback that makes a game feel cheap.
]]
function Effects.popup(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Name = "Popup"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = folder()

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(4, 1.4)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard

	TweenService
		:Create(anchor, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = position + Vector3.new(0, 8, 0),
		})
		:Play()
	TweenService
		:Create(label, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 })
		:Play()

	Debris:AddItem(anchor, 1)
end

--[[ A quick scale-up on placement so building something feels like an action. ]]
function Effects.placePop(part: BasePart)
	local target = part.Size
	part.Size = target * 0.4
	TweenService
		:Create(part, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = target,
		})
		:Play()
end

--[[ A ring that expands and fades — used for the base taking damage. ]]
function Effects.shockwave(position: Vector3, color: Color3)
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Size = Vector3.new(0.6, 6, 6)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder()

	TweenService
		:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.6, 60, 60),
			Transparency = 1,
		})
		:Play()
	Debris:AddItem(ring, 0.6)
end

return Effects
