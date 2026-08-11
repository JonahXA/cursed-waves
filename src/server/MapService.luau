--[[
	MapService — the arena geometry, generated in code.

	Each player gets their own map at an offset, because runs are solo and two
	players sharing a lane would mean one player's leak damages the other's base.
	Offsetting is cheaper and clearer than instancing separate places.

	The arena is deliberately over-built relative to what the gameplay strictly
	needs: raised borders, a sunken path with rails, a layered base, a spawn
	portal and scattered rock. None of it affects the simulation. All of it is
	the difference between "a green slab with a brown line" and somewhere a
	player believes they are defending — and at zero art cost, since it is all
	primitives placed by rules.

	Pure geometry, no gameplay state and no dependencies on other services, so
	nothing here can create a require cycle.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MapService = {}

local MAPS_ROOT = "Maps"
local MAP_SPACING = 400

local GROUND_X, GROUND_Z = 200, 170

-- Path shape in map-local space. A zigzag rather than a straight line so that a
-- single well-placed tower can cover two lanes — which is what makes placement a
-- decision instead of a queue.
local PATH_SHAPE = {
	Vector3.new(-78, 2, -46),
	Vector3.new(-20, 2, -46),
	Vector3.new(-20, 2, 12),
	Vector3.new(22, 2, 12),
	Vector3.new(22, 2, -28),
	Vector3.new(58, 2, -28),
	Vector3.new(58, 2, 46),
	Vector3.new(0, 2, 46),
}

local PALETTE = {
	grass = Color3.fromRGB(86, 122, 78),
	grassAlt = Color3.fromRGB(74, 108, 68),
	stone = Color3.fromRGB(112, 108, 104),
	stoneDark = Color3.fromRGB(78, 74, 72),
	rail = Color3.fromRGB(58, 54, 58),
	baseCore = Color3.fromRGB(96, 190, 255),
	baseShell = Color3.fromRGB(52, 62, 86),
	portal = Color3.fromRGB(230, 70, 90),
	rock = Color3.fromRGB(96, 92, 96),
}

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

local function part(props): Part
	local p = Instance.new("Part")
	p.Name = props.name or "Part"
	p.Size = props.size
	p.Anchored = true
	p.CanCollide = props.collide ~= false
	p.CanQuery = props.query ~= false
	p.Color = props.color or PALETTE.stone
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.cframe then
		p.CFrame = props.cframe
	else
		p.Position = props.position
	end
	if props.shape then
		p.Shape = props.shape
	end
	if props.transparency then
		p.Transparency = props.transparency
	end
	p.Parent = props.parent
	return p
end

-- ============================================================
-- Arena pieces
-- ============================================================

--[[ Ground, plus a raised border so the arena reads as a contained place
	rather than a slab floating in sky. ]]
local function buildGround(origin: Vector3, parent: Instance)
	part({
		name = "Ground",
		size = Vector3.new(GROUND_X, 4, GROUND_Z),
		position = origin + Vector3.new(0, 0, 0),
		color = PALETTE.grass,
		material = Enum.Material.Grass,
		parent = parent,
	})

	-- Checkerboard patches. Two tones of grass at low contrast give the eye
	-- something to read scale against; a single flat colour reads as untextured.
	for x = -4, 4 do
		for z = -3, 3 do
			if (x + z) % 2 == 0 then
				part({
					name = "GrassPatch",
					size = Vector3.new(20, 0.2, 22),
					position = origin + Vector3.new(x * 20, 2.1, z * 22),
					color = PALETTE.grassAlt,
					material = Enum.Material.Grass,
					collide = false,
					query = false,
					parent = parent,
				})
			end
		end
	end

	local halfX, halfZ = GROUND_X / 2, GROUND_Z / 2
	local walls = {
		{ Vector3.new(GROUND_X + 8, 10, 6), Vector3.new(0, 4, -halfZ - 3) },
		{ Vector3.new(GROUND_X + 8, 10, 6), Vector3.new(0, 4, halfZ + 3) },
		{ Vector3.new(6, 10, GROUND_Z), Vector3.new(-halfX - 3, 4, 0) },
		{ Vector3.new(6, 10, GROUND_Z), Vector3.new(halfX + 3, 4, 0) },
	}
	for index, wall in walls do
		part({
			name = "Border" .. tostring(index),
			size = wall[1],
			position = origin + wall[2],
			color = PALETTE.stoneDark,
			material = Enum.Material.Slate,
			parent = parent,
		})
	end
end

--[[ The path: sunken stone with rails either side, so the lane is legible from
	the strategic camera without needing a colour that fights the towers. ]]
local function buildPath(waypoints: { Vector3 }, parent: Instance)
	for index = 1, #waypoints - 1 do
		local a, b = waypoints[index], waypoints[index + 1]
		local delta = b - a
		local length = delta.Magnitude
		local mid = a + delta * 0.5
		local look = CFrame.lookAt(mid, b)

		part({
			name = "PathSegment" .. tostring(index),
			size = Vector3.new(12, 1.2, length + 12),
			cframe = look,
			color = PALETTE.stone,
			material = Enum.Material.Concrete,
			collide = false,
			query = false,
			parent = parent,
		})

		for _, side in { -1, 1 } do
			part({
				name = "PathRail",
				size = Vector3.new(1.2, 2.2, length + 12),
				cframe = look * CFrame.new(side * 6.4, 0.6, 0),
				color = PALETTE.rail,
				material = Enum.Material.Slate,
				collide = false,
				query = false,
				parent = parent,
			})
		end
	end

	-- Corner caps, so the rails do not visibly gap at every turn.
	for index = 2, #waypoints - 1 do
		part({
			name = "PathJoint",
			size = Vector3.new(13.6, 1.2, 13.6),
			position = waypoints[index],
			color = PALETTE.stone,
			material = Enum.Material.Concrete,
			collide = false,
			query = false,
			parent = parent,
		})
	end
end

--[[ The base: a layered plinth with a glowing core and a slowly turning ring.
	Motion matters — a static object reads as scenery, and this is the thing the
	player is protecting. ]]
local function buildBase(position: Vector3, parent: Instance): BasePart
	part({
		name = "BasePlinth",
		size = Vector3.new(26, 3, 26),
		position = position + Vector3.new(0, 1.5, 0),
		color = PALETTE.stoneDark,
		material = Enum.Material.Slate,
		parent = parent,
	})
	part({
		name = "BaseShell",
		size = Vector3.new(18, 8, 18),
		position = position + Vector3.new(0, 6, 0),
		color = PALETTE.baseShell,
		material = Enum.Material.Metal,
		parent = parent,
	})

	for _, corner in
		{
			Vector3.new(1, 0, 1),
			Vector3.new(-1, 0, 1),
			Vector3.new(1, 0, -1),
			Vector3.new(-1, 0, -1),
		}
	do
		part({
			name = "BasePillar",
			size = Vector3.new(3, 16, 3),
			position = position + Vector3.new(corner.X * 11, 8, corner.Z * 11),
			color = PALETTE.stoneDark,
			material = Enum.Material.Slate,
			parent = parent,
		})
	end

	local core = part({
		name = "Base",
		size = Vector3.new(9, 9, 9),
		position = position + Vector3.new(0, 14, 0),
		color = PALETTE.baseCore,
		material = Enum.Material.Neon,
		shape = Enum.PartType.Ball,
		collide = false,
		parent = parent,
	})

	local light = Instance.new("PointLight")
	light.Color = PALETTE.baseCore
	light.Brightness = 3
	light.Range = 42
	light.Parent = core

	local ring = part({
		name = "BaseRing",
		size = Vector3.new(20, 0.8, 20),
		position = position + Vector3.new(0, 14, 0),
		color = PALETTE.baseCore,
		material = Enum.Material.Neon,
		collide = false,
		query = false,
		transparency = 0.4,
		parent = parent,
	})

	-- Rotation is driven by a tween loop rather than a heartbeat connection, so
	-- it costs nothing per frame and dies with the instance.
	task.spawn(function()
		while ring.Parent do
			local spin = TweenService:Create(
				ring,
				TweenInfo.new(6, Enum.EasingStyle.Linear),
				{ CFrame = ring.CFrame * CFrame.Angles(0, math.pi, 0) }
			)
			spin:Play()
			spin.Completed:Wait()
		end
	end)

	return core
end

--[[ Spawn portal — an arch with an emitter, so enemies enter from somewhere
	rather than materialising on a red square. ]]
local function buildSpawn(position: Vector3, parent: Instance)
	part({
		name = "SpawnPad",
		size = Vector3.new(18, 1.4, 18),
		position = position + Vector3.new(0, 1, 0),
		color = PALETTE.stoneDark,
		material = Enum.Material.Slate,
		collide = false,
		query = false,
		parent = parent,
	})

	for _, side in { -1, 1 } do
		part({
			name = "PortalPost",
			size = Vector3.new(2.5, 18, 2.5),
			position = position + Vector3.new(0, 9, side * 7),
			color = PALETTE.stoneDark,
			material = Enum.Material.Slate,
			parent = parent,
		})
	end

	local arch = part({
		name = "PortalArch",
		size = Vector3.new(2.5, 2.5, 16),
		position = position + Vector3.new(0, 18, 0),
		color = PALETTE.portal,
		material = Enum.Material.Neon,
		collide = false,
		parent = parent,
	})

	local glow = Instance.new("PointLight")
	glow.Color = PALETTE.portal
	glow.Brightness = 2.5
	glow.Range = 34
	glow.Parent = arch

	local veil = part({
		name = "PortalVeil",
		size = Vector3.new(0.6, 16, 14),
		position = position + Vector3.new(0, 9, 0),
		color = PALETTE.portal,
		material = Enum.Material.Neon,
		collide = false,
		query = false,
		transparency = 0.65,
		parent = parent,
	})

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(PALETTE.portal)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Rate = 14
	emitter.Speed = NumberRange.new(2, 6)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.LightEmission = 0.8
	emitter.Parent = veil
end

--[[ Scattered rock, skipped anywhere near the path or the buildable margin.
	Deterministic per map so a player's arena looks the same each session — a
	world that rearranges itself between joins feels unstable. ]]
local function buildScatter(origin: Vector3, waypoints: { Vector3 }, parent: Instance)
	local rng = Random.new(1337)

	local function nearPath(point: Vector3, margin: number): boolean
		for i = 1, #waypoints - 1 do
			local a, b = waypoints[i], waypoints[i + 1]
			local ab = b - a
			local lengthSq = ab:Dot(ab)
			local t = if lengthSq > 0 then math.clamp((point - a):Dot(ab) / lengthSq, 0, 1) else 0
			local closest = a + ab * t
			local flat = Vector3.new(point.X - closest.X, 0, point.Z - closest.Z)
			if flat.Magnitude < margin then
				return true
			end
		end
		return false
	end

	for _ = 1, 46 do
		local candidate = origin
			+ Vector3.new(
				rng:NextNumber(-GROUND_X / 2 + 8, GROUND_X / 2 - 8),
				2,
				rng:NextNumber(-GROUND_Z / 2 + 8, GROUND_Z / 2 - 8)
			)
		if not nearPath(candidate, 12) then
			local scale = rng:NextNumber(1.4, 4.2)
			local rock = part({
				name = "Rock",
				size = Vector3.new(scale, scale * rng:NextNumber(0.7, 1.6), scale),
				cframe = CFrame.new(candidate + Vector3.new(0, scale * 0.4, 0)) * CFrame.Angles(
					rng:NextNumber(-0.2, 0.2),
					rng:NextNumber(0, math.pi * 2),
					rng:NextNumber(-0.2, 0.2)
				),
				color = PALETTE.rock,
				material = Enum.Material.Rock,
				collide = false,
				query = false,
				parent = parent,
			})
			rock.Color = PALETTE.rock:Lerp(PALETTE.grassAlt, rng:NextNumber(0, 0.4))
		end
	end
end

-- ============================================================
-- Build
-- ============================================================

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

	local waypoints = {}
	for _, point in PATH_SHAPE do
		table.insert(waypoints, origin + point)
	end

	buildGround(origin, folder)
	buildPath(waypoints, folder)
	buildScatter(origin, waypoints, folder)
	buildSpawn(waypoints[1], folder)

	local totalLength = 0
	for i = 1, #waypoints - 1 do
		totalLength += (waypoints[i + 1] - waypoints[i]).Magnitude
	end

	local basePosition = waypoints[#waypoints]
	local baseCore = buildBase(basePosition, folder)

	local playerSpawn = Instance.new("SpawnLocation")
	playerSpawn.Name = "PlayerSpawn"
	playerSpawn.Size = Vector3.new(8, 1, 8)
	playerSpawn.Position = origin + Vector3.new(0, 3, -70)
	playerSpawn.Anchored = true
	playerSpawn.Neutral = true
	playerSpawn.Transparency = 1
	playerSpawn.CanCollide = false
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
	Whether a build position is legal: inside the arena, and clear of the path so
	towers cannot be parked on the road.
]]
function MapService.isBuildable(player: Player, position: Vector3): boolean
	local map = maps[player]
	if not map then
		return false
	end

	local relative = position - map.origin
	if math.abs(relative.X) > (GROUND_X / 2 - 6) or math.abs(relative.Z) > (GROUND_Z / 2 - 6) then
		return false
	end

	-- Clear of the base plinth, so towers cannot be stacked inside it.
	local toBase = Vector3.new(position.X - map.basePosition.X, 0, position.Z - map.basePosition.Z)
	if toBase.Magnitude < 18 then
		return false
	end

	for i = 1, #map.waypoints - 1 do
		local a = map.waypoints[i]
		local b = map.waypoints[i + 1]
		local ab = b - a
		local lengthSq = ab:Dot(ab)
		local t = if lengthSq > 0 then math.clamp((position - a):Dot(ab) / lengthSq, 0, 1) else 0
		local closest = a + ab * t
		local flat = Vector3.new(position.X - closest.X, 0, position.Z - closest.Z)
		if flat.Magnitude < 9 then
			return false
		end
	end

	return true
end

return MapService
