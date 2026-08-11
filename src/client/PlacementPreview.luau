--[[
	PlacementPreview — a ghost tower and range ring under the cursor.

	Placement is the core interaction of a tower defense, and without a preview
	it is blind: you cannot see whether a spot is legal until you have already
	spent the money, and you cannot see what a tower will cover until it exists.
	That turns the central decision into guesswork.

	The legality check here is a client-side approximation used only to colour
	the ghost. The server validates independently and is the only authority — if
	the two ever disagree, the player sees a green ghost and the placement is
	refused, which is a cosmetic bug rather than an exploit.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local PlacementPreview = {}

local player = Players.LocalPlayer

local VALID = Color3.fromRGB(110, 240, 140)
local INVALID = Color3.fromRGB(255, 100, 100)

local ghost: Part? = nil
local ring: Part? = nil
local selected: string? = nil
local lastValid = false
local lastPosition: Vector3? = nil

local function ensureParts()
	if ghost and ghost.Parent then
		return
	end

	local folder = Workspace:FindFirstChild("PlacementPreview")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "PlacementPreview"
		folder.Parent = Workspace
	end

	ghost = Instance.new("Part")
	ghost.Name = "Ghost"
	ghost.Size = Vector3.new(5, 5, 5)
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.Material = Enum.Material.Neon
	ghost.Transparency = 0.55
	ghost.Parent = folder

	-- A flat cylinder reads as a range circle from an overhead camera without
	-- needing a decal or a mesh.
	ring = Instance.new("Part")
	ring.Name = "RangeRing"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.86
	ring.Parent = folder
end

--[[ Approximate legality: away from path geometry and inside the arena. ]]
local function isLikelyBuildable(position: Vector3): boolean
	local maps = Workspace:FindFirstChild("Maps")
	local mine = maps and maps:FindFirstChild(player.Name)
	if not mine then
		return false
	end

	local ground = mine:FindFirstChild("Ground") :: BasePart?
	if not ground then
		return false
	end
	local relative = position - ground.Position
	if
		math.abs(relative.X) > (ground.Size.X / 2 - 6)
		or math.abs(relative.Z) > (ground.Size.Z / 2 - 6)
	then
		return false
	end

	for _, child in mine:GetChildren() do
		if child:IsA("BasePart") then
			local isPath = child.Name:match("^PathSegment") or child.Name == "PathJoint"
			if isPath then
				local flat =
					Vector3.new(position.X - child.Position.X, 0, position.Z - child.Position.Z)
				-- Compare against the segment's own footprint rather than a fixed
				-- radius, so long segments are not treated as points.
				local reach = math.max(child.Size.X, child.Size.Z) / 2
				if flat.Magnitude < math.min(reach, 10) then
					return false
				end
			elseif child.Name == "BasePlinth" then
				local flat =
					Vector3.new(position.X - child.Position.X, 0, position.Z - child.Position.Z)
				if flat.Magnitude < 18 then
					return false
				end
			end
		end
	end

	-- Existing towers.
	local towers = mine:FindFirstChild("Towers")
	if towers then
		for _, model in towers:GetChildren() do
			local primary = model:IsA("Model") and model.PrimaryPart
			if primary then
				local flat =
					Vector3.new(position.X - primary.Position.X, 0, position.Z - primary.Position.Z)
				if flat.Magnitude < 6 then
					return false
				end
			end
		end
	end

	return true
end

function PlacementPreview.setSelected(towerType: string?)
	selected = towerType
	if not towerType then
		if ghost then
			ghost.Transparency = 1
		end
		if ring then
			ring.Transparency = 1
		end
	end
end

--[[ Where the ghost currently sits, or nil. Lets the click handler place at the
	previewed spot rather than re-raycasting and risking a one-frame mismatch. ]]
function PlacementPreview.currentPosition(): (Vector3?, boolean)
	return lastPosition, lastValid
end

function PlacementPreview.start()
	ensureParts()

	RunService.RenderStepped:Connect(function()
		if not selected then
			return
		end
		ensureParts()

		local def = Config.Towers[selected]
		if not def then
			return
		end

		local mouse = UserInputService:GetMouseLocation()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end

		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {
			Workspace:FindFirstChild("PlacementPreview"),
			Workspace:FindFirstChild("Effects"),
			player.Character,
		}

		local result = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
		if not result then
			return
		end

		local position = result.Position + Vector3.new(0, 0.5, 0)
		lastPosition = position
		lastValid = isLikelyBuildable(position)

		local colour = if lastValid then VALID else INVALID

		if ghost then
			ghost.Size = Vector3.new(5, 5, 5)
			ghost.Position = position + Vector3.new(0, 2.5, 0)
			ghost.Color = colour
			ghost.Transparency = 0.55
		end

		if ring then
			local diameter = def.range * 2
			ring.Size = Vector3.new(0.4, diameter, diameter)
			ring.CFrame = CFrame.new(position + Vector3.new(0, 0.6, 0))
				* CFrame.Angles(0, 0, math.rad(90))
			ring.Color = colour
			ring.Transparency = 0.86
		end
	end)
end

return PlacementPreview
