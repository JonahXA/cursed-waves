--[[
	MapService — the arena geometry, generated in code.

	Each player gets their own map at an offset, because runs are solo and two
	players sharing a lane would mean one player's leak damages the other's base.
	Offsetting is cheaper and clearer than instancing separate places.

	Pure geometry, no gameplay state and no dependencies on other services, so
	nothing here can create a require cycle.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local MapService = {}

local MAPS_ROOT = "Maps"
local MAP_SPACING = 400

-- Path shape in map-local space. A zigzag rather than a straight line so that a
-- single well-placed tower can cover two lanes — which is what makes placement a
-- decision instead of a queue.
local PATH_SHAPE = {
	Vector3.new(-60, 2, -40),
	Vector3.new(-20, 2, -40),
	Vector3.new(-20, 2, 10),
	Vector3.new(20, 2, 10),
	Vector3.new(20, 2, -25),
	Vector3.new(55, 2, -25),
	Vector3.new(55, 2, 40),
	Vector3.new(0, 2, 40),
}

-- player -> { origin, waypoints, totalLength, basePosition }
local maps: { [Player]: any } = {}

local function mapsRoot(): Folder
	local existing = Workspace:FindFirstChild(MAPS_ROOT)
	if existing then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = MAPS_ROOT
	folder.Parent = Workspace
	return folder
end

local function makePart(
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	parent: Instance
)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = color
	part.Parent = parent
	return part
end

--[[ Lays path segments between consecutive waypoints as flat slabs. ]]
local function buildPathVisual(waypoints: { Vector3 }, parent: Instance)
	for index = 1, #waypoints - 1 do
		local a = waypoints[index]
		local b = waypoints[index + 1]
		local delta = b - a
		local length = delta.Magnitude

		local segment = Instance.new("Part")
		segment.Name = "PathSegment" .. tostring(index)
		segment.Anchored = true
		segment.CanCollide = false
		segment.Size = Vector3.new(8, 0.4, length + 8)
		segment.CFrame = CFrame.lookAt(a + delta * 0.5, b)
		segment.Color = Color3.fromRGB(90, 80, 70)
		segment.Material = Enum.Material.Slate
		segment.TopSurface = Enum.SurfaceType.Smooth
		segment.Parent = parent
	end
end

function MapService.build(player: Player)
	local root = mapsRoot()
	local existing = root:FindFirstChild(player.Name)
	if existing then
		existing:Destroy()
	end

	local index = 0
	for _, other in Players:GetPlayers() do
		if other == player then
			break
		end
		index += 1
	end
	local origin = Vector3.new(index * MAP_SPACING, 0, 0)

	local folder = Instance.new("Folder")
	folder.Name = player.Name
	folder.Parent = root

	makePart(
		"Ground",
		Vector3.new(200, 2, 160),
		origin + Vector3.new(0, 0, 0),
		Color3.fromRGB(70, 110, 70),
		folder
	)

	local waypoints = {}
	for _, point in PATH_SHAPE do
		table.insert(waypoints, origin + point)
	end
	buildPathVisual(waypoints, folder)

	local totalLength = 0
	for i = 1, #waypoints - 1 do
		totalLength += (waypoints[i + 1] - waypoints[i]).Magnitude
	end

	local basePosition = waypoints[#waypoints]
	local baseCore = makePart(
		"Base",
		Vector3.new(12, 10, 12),
		basePosition + Vector3.new(0, 5, 0),
		Color3.fromRGB(90, 160, 240),
		folder
	)
	baseCore.Material = Enum.Material.Neon

	local spawnPad = makePart(
		"EnemySpawn",
		Vector3.new(10, 1, 10),
		waypoints[1],
		Color3.fromRGB(180, 60, 60),
		folder
	)
	spawnPad.Material = Enum.Material.Neon

	local playerSpawn = Instance.new("SpawnLocation")
	playerSpawn.Name = "PlayerSpawn"
	playerSpawn.Size = Vector3.new(8, 1, 8)
	playerSpawn.Position = origin + Vector3.new(0, 1.5, -10)
	playerSpawn.Anchored = true
	playerSpawn.Neutral = true
	playerSpawn.Color = Color3.fromRGB(240, 240, 240)
	playerSpawn.Parent = folder

	local towersFolder = Instance.new("Folder")
	towersFolder.Name = "Towers"
	towersFolder.Parent = folder

	local enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "Enemies"
	enemiesFolder.Parent = folder

	maps[player] = {
		origin = origin,
		folder = folder,
		waypoints = waypoints,
		totalLength = totalLength,
		basePosition = basePosition,
		baseCore = baseCore,
		towersFolder = towersFolder,
		enemiesFolder = enemiesFolder,
	}
	return maps[player]
end

function MapService.get(player: Player): any?
	return maps[player]
end

function MapService.destroy(player: Player)
	local map = maps[player]
	if map and map.folder then
		map.folder:Destroy()
	end
	maps[player] = nil
end

--[[
	World position at a normalised distance along the path.

	Enemies store progress as 0..1 rather than a waypoint index plus offset,
	because a single scalar survives speed changes mid-wave — which is exactly
	what the Haste curse does.
]]
function MapService.pointAtProgress(player: Player, progress: number): Vector3?
	local map = maps[player]
	if not map then
		return nil
	end

	local target = math.clamp(progress, 0, 1) * map.totalLength
	local travelled = 0

	for i = 1, #map.waypoints - 1 do
		local a = map.waypoints[i]
		local b = map.waypoints[i + 1]
		local segment = (b - a).Magnitude
		if travelled + segment >= target then
			local alpha = if segment > 0 then (target - travelled) / segment else 0
			return a:Lerp(b, alpha)
		end
		travelled += segment
	end

	return map.waypoints[#map.waypoints]
end

--[[
	Whether a build position is legal: inside the ground, and far enough from the
	path that towers cannot be parked on the road.
]]
function MapService.isBuildable(player: Player, position: Vector3): boolean
	local map = maps[player]
	if not map then
		return false
	end

	local local_ = position - map.origin
	if math.abs(local_.X) > 95 or math.abs(local_.Z) > 75 then
		return false
	end

	for i = 1, #map.waypoints - 1 do
		local a = map.waypoints[i]
		local b = map.waypoints[i + 1]
		local ab = b - a
		local lengthSq = ab:Dot(ab)
		local t = if lengthSq > 0 then math.clamp((position - a):Dot(ab) / lengthSq, 0, 1) else 0
		local closest = a + ab * t
		if
			(Vector3.new(position.X, 0, position.Z) - Vector3.new(closest.X, 0, closest.Z)).Magnitude
			< 7
		then
			return false
		end
	end

	return true
end

return MapService
