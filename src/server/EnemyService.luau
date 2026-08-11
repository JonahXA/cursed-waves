--[[
	EnemyService — spawning, movement, damage and death.

	Enemies are simple anchored parts moved along a normalised 0..1 path
	progress. No physics, no humanoids, no pathfinding: with dozens of enemies
	alive at once, anything heavier is a performance problem, and none of it would
	change how the game plays.

	Outcomes are reported through BindableEvents rather than by calling
	MatchService directly. MatchService owns base health and the economy, and
	this module owning neither is what keeps the dependency arrows one-way.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Audio = require(ReplicatedStorage.Shared.Audio)
local Config = require(ReplicatedStorage.Shared.Config)

local Effects = require(script.Parent.Effects)
local MapService = require(script.Parent.MapService)
local RunState = require(script.Parent.RunState)

local EnemyService = {}

-- (player, enemy) — reached the base. MatchService applies the damage.
EnemyService.Leaked = Instance.new("BindableEvent")
-- (player, enemy) — killed by a tower. MatchService pays the bounty.
EnemyService.Killed = Instance.new("BindableEvent")

local models: { [string]: BasePart } = {}

local function enemyConfig(enemyType: string)
	return Config.Enemies[enemyType]
end

local function buildModel(player: Player, enemy: any, position: Vector3): BasePart?
	local map = MapService.get(player)
	if not map then
		return nil
	end
	local def = enemyConfig(enemy.enemyType)

	local part = Instance.new("Part")
	part.Name = enemy.id
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(def.size, def.size, def.size)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Color = def.color
	part.Material = Enum.Material.SmoothPlastic

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.fromScale(4, 0.6)
	billboard.StudsOffset = Vector3.new(0, def.size, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	back.BorderSizePixel = 0
	back.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = back

	part.Parent = map.enemiesFolder
	return part
end

function EnemyService.spawn(player: Player, enemyType: string, healthMultiplier: number)
	local run = RunState.get(player)
	local def = enemyConfig(enemyType)
	if not run or not def then
		return
	end

	local id = RunState.newId()
	local health = math.floor(def.health * healthMultiplier)

	local enemy = {
		id = id,
		enemyType = enemyType,
		health = health,
		maxHealth = health,
		pathProgress = 0,
		slowUntil = 0,
		slowFactor = 0,
	}
	run.enemies[id] = enemy

	local start = MapService.pointAtProgress(player, 0)
	if start then
		local model = buildModel(player, enemy, start)
		if model then
			models[id] = model
		end
	end
end

local function destroyModel(id: string)
	local model = models[id]
	if model then
		model:Destroy()
	end
	models[id] = nil
end

function EnemyService.remove(player: Player, enemyId: string)
	local run = RunState.get(player)
	if run then
		run.enemies[enemyId] = nil
	end
	destroyModel(enemyId)
end

--[[
	Applies damage. Returns true if this killed the enemy.

	Armour is a flat proportional reduction and the Armour curse adds to it, so
	stacking armour makes Sniper (which ignores it) the correct answer rather
	than making the run unwinnable. That is the intended shape: curses should
	change which tower is right, not delete the possibility of winning.
]]
function EnemyService.damage(
	player: Player,
	enemyId: string,
	amount: number,
	ignoresArmour: boolean
): boolean
	local run = RunState.get(player)
	if not run then
		return false
	end
	local enemy = run.enemies[enemyId]
	if not enemy then
		return false
	end

	local def = enemyConfig(enemy.enemyType)
	local effective = amount
	if not ignoresArmour then
		local armour = math.clamp(def.armour + RunState.curseEffects(run).armourBonus, 0, 0.9)
		effective = amount * (1 - armour)
	end

	enemy.health -= effective

	local model = models[enemyId]
	if model then
		local fill = model:FindFirstChild("HealthBar")
			and model.HealthBar:FindFirstChild("Frame")
			and model.HealthBar.Frame:FindFirstChild("Fill")
		if fill then
			local ratio = math.clamp(enemy.health / enemy.maxHealth, 0, 1)
			fill.Size = UDim2.fromScale(ratio, 1)
			fill.BackgroundColor3 = if ratio > 0.5
				then Color3.fromRGB(90, 220, 90)
				elseif ratio > 0.25 then Color3.fromRGB(240, 200, 80)
				else Color3.fromRGB(230, 80, 80)
		end
	end

	if enemy.health <= 0 then
		-- Capture the position before removal — the model is gone immediately
		-- after, and a burst at the origin would look like a bug.
		if model then
			Effects.burst(model.Position, def.color, def.size / 2.5)
			Audio.playAt(
				if enemy.enemyType == "boss" then "bossDeath" else "enemyDeath",
				model.Position
			)
		end
		EnemyService.remove(player, enemyId)
		EnemyService.Killed:Fire(player, enemy)
		return true
	end
	return false
end

function EnemyService.applySlow(player: Player, enemyId: string, factor: number, duration: number)
	local run = RunState.get(player)
	if not run then
		return
	end
	local enemy = run.enemies[enemyId]
	if not enemy then
		return
	end
	local def = enemyConfig(enemy.enemyType)
	if def.immuneToSlow then
		return
	end
	-- Strongest slow wins rather than stacking; stacked slows trivially reach
	-- zero movement, which turns Frost from utility into a win button.
	if factor > enemy.slowFactor or os.clock() > enemy.slowUntil then
		enemy.slowFactor = factor
	end
	enemy.slowUntil = os.clock() + duration
end

function EnemyService.step(player: Player, dt: number)
	local run = RunState.get(player)
	local map = MapService.get(player)
	if not run or not map then
		return
	end

	local effects = RunState.curseEffects(run)
	local now = os.clock()

	for id, enemy in run.enemies do
		local def = enemyConfig(enemy.enemyType)
		local speed = def.speed * effects.speedMultiplier
		if now < enemy.slowUntil then
			speed *= (1 - enemy.slowFactor)
		end

		enemy.pathProgress += (speed * dt) / map.totalLength

		if enemy.pathProgress >= 1 then
			EnemyService.remove(player, id)
			EnemyService.Leaked:Fire(player, enemy)
		else
			local model = models[id]
			if model then
				local point = MapService.pointAtProgress(player, enemy.pathProgress)
				if point then
					model.Position = point + Vector3.new(0, def.size * 0.5, 0)
				end
			end
		end
	end
end

function EnemyService.count(player: Player): number
	local run = RunState.get(player)
	if not run then
		return 0
	end
	local n = 0
	for _ in run.enemies do
		n += 1
	end
	return n
end

function EnemyService.clearAll(player: Player)
	local run = RunState.get(player)
	if not run then
		return
	end
	for id in run.enemies do
		destroyModel(id)
	end
	run.enemies = {}
end

--[[ Nearest enemy to a point within range, by furthest path progress.

	Targeting the furthest-along enemy rather than the closest is the standard TD
	convention and the correct one: the enemy nearest your base is the one about
	to cost you health.
]]
function EnemyService.findTarget(player: Player, position: Vector3, range: number): any?
	local run = RunState.get(player)
	if not run then
		return nil
	end

	local best, bestProgress = nil, -1
	for id, enemy in run.enemies do
		local model = models[id]
		if model then
			local flatDistance = (Vector3.new(model.Position.X, 0, model.Position.Z) - Vector3.new(
				position.X,
				0,
				position.Z
			)).Magnitude
			if flatDistance <= range and enemy.pathProgress > bestProgress then
				best = enemy
				bestProgress = enemy.pathProgress
			end
		end
	end
	return best
end

function EnemyService.modelOf(enemyId: string): BasePart?
	return models[enemyId]
end

return EnemyService
