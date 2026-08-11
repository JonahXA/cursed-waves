--[[
	TowerService — placement, upgrades, selling, and the firing loop.

	Every value the client sends is intent, never worth: "place a pea here",
	"upgrade tower X". Cost, damage, range and refund are all read from Config on
	the server. The one client-supplied number is a position, and that is
	validated against the build grid before anything is spent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Effects = require(script.Parent.Effects)
local EnemyService = require(script.Parent.EnemyService)
local MapService = require(script.Parent.MapService)
local RunState = require(script.Parent.RunState)

local TowerService = {}

local models: { [string]: Model } = {}

--[[
	Resolved stats for a tower at its current tier.

	Upgrade entries are multipliers applied cumulatively, so a tier is a stat
	transform on the base rather than a full stat block. That means rebalancing
	tier 3 is one number, not a copy-paste of every field.
]]
function TowerService.stats(towerType: string, tier: number)
	local def = Config.Towers[towerType]
	if not def then
		return nil
	end

	local stats = {
		damage = def.damage,
		range = def.range,
		fireRate = def.fireRate,
		splashRadius = def.splashRadius,
		slowFactor = def.slowFactor,
		ignoresArmour = def.ignoresArmour,
	}

	for level = 1, tier do
		local up = def.upgrades[level]
		if up then
			stats.damage *= up.damage or 1
			stats.range *= up.range or 1
			stats.fireRate *= up.fireRate or 1
			stats.splashRadius *= up.splashRadius or 1
			stats.slowFactor *= up.slowFactor or 1
		end
	end

	return stats
end

function TowerService.upgradeCost(towerType: string, tier: number): number?
	local def = Config.Towers[towerType]
	if not def then
		return nil
	end
	local next_ = def.upgrades[tier + 1]
	return next_ and next_.cost or nil
end

local function buildModel(player: Player, tower: any): Model?
	local map = MapService.get(player)
	if not map then
		return nil
	end
	local def = Config.Towers[tower.towerType]

	local model = Instance.new("Model")
	model.Name = tower.id

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(5, 1, 5)
	base.Position = tower.position
	base.Anchored = true
	base.Color = Color3.fromRGB(80, 80, 90)
	base.Material = Enum.Material.Metal
	base.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(3, 3 + tower.tier, 3)
	head.Position = tower.position + Vector3.new(0, 2 + tower.tier * 0.5, 0)
	head.Anchored = true
	head.Color = def.color
	head.Material = if tower.tier >= 2 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	head.Parent = model

	model.PrimaryPart = head
	model.Parent = map.towersFolder
	return model
end

local function refreshModel(player: Player, tower: any)
	local existing = models[tower.id]
	if existing then
		existing:Destroy()
	end
	local model = buildModel(player, tower)
	if model then
		models[tower.id] = model
		-- Placing something should feel like an action, not an appearance.
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				Effects.placePop(part)
			end
		end
	end
end

function TowerService.place(player: Player, towerType: string, position: Vector3): boolean
	local run = RunState.get(player)
	if not run or not run.active then
		return false
	end

	local def = Config.Towers[towerType]
	if not def then
		return false
	end
	if not MapService.isBuildable(player, position) then
		return false
	end

	-- Refuse to stack towers on the same spot.
	for _, existing in run.towers do
		if (existing.position - position).Magnitude < 6 then
			return false
		end
	end

	if run.cash < def.cost then
		return false
	end
	run.cash -= def.cost

	local tower = {
		id = RunState.newId(),
		towerType = towerType,
		tier = 0,
		position = position,
		spent = def.cost,
		lastFired = 0,
	}
	run.towers[tower.id] = tower
	refreshModel(player, tower)
	return true
end

function TowerService.upgrade(player: Player, towerId: string): boolean
	local run = RunState.get(player)
	if not run or not run.active then
		return false
	end
	local tower = run.towers[towerId]
	if not tower then
		return false
	end

	local cost = TowerService.upgradeCost(tower.towerType, tower.tier)
	if not cost or run.cash < cost then
		return false
	end

	run.cash -= cost
	tower.spent += cost
	tower.tier += 1
	refreshModel(player, tower)
	return true
end

function TowerService.sell(player: Player, towerId: string): boolean
	local run = RunState.get(player)
	if not run or not run.active then
		return false
	end
	local tower = run.towers[towerId]
	if not tower then
		return false
	end

	run.cash += math.floor(tower.spent * Config.Run.SellRefundRatio)
	run.towers[towerId] = nil

	local model = models[towerId]
	if model then
		model:Destroy()
	end
	models[towerId] = nil
	return true
end

function TowerService.clearAll(player: Player)
	local run = RunState.get(player)
	if not run then
		return
	end
	for id in run.towers do
		local model = models[id]
		if model then
			model:Destroy()
		end
		models[id] = nil
	end
	run.towers = {}
end

--[[
	The firing loop.

	Range is multiplied by the curse effect here rather than baked into stats, so
	Fog applies and lifts cleanly without having to rewrite every tower when the
	curse ends.
]]
function TowerService.step(player: Player, _dt: number)
	local run = RunState.get(player)
	if not run or not run.active then
		return
	end

	local effects = RunState.curseEffects(run)
	local now = os.clock()

	for _, tower in run.towers do
		local stats = TowerService.stats(tower.towerType, tower.tier)
		if stats then
			local interval = 1 / math.max(stats.fireRate, 0.01)
			if now - tower.lastFired >= interval then
				local range = stats.range * effects.rangeMultiplier
				local target = EnemyService.findTarget(player, tower.position, range)

				if target then
					tower.lastFired = now

					local def = Config.Towers[tower.towerType]
					local model = models[tower.id]
					local targetModel = EnemyService.modelOf(target.id)

					if model and model.PrimaryPart and targetModel then
						local from = model.PrimaryPart.Position
						local look =
							Vector3.new(targetModel.Position.X, from.Y, targetModel.Position.Z)
						model.PrimaryPart.CFrame = CFrame.lookAt(from, look)

						-- The shot itself. Without this, combat is invisible:
						-- towers deal damage and enemies silently lose health,
						-- which makes a working game read as a broken one.
						Effects.tracer(
							from,
							targetModel.Position,
							def.color,
							if stats.splashRadius > 0 then 1.2 else 0.55
						)
					end

					if stats.slowFactor > 0 then
						EnemyService.applySlow(player, target.id, stats.slowFactor, 1.5)
					end

					if stats.damage > 0 then
						if targetModel then
							Effects.popup(
								targetModel.Position + Vector3.new(0, 2, 0),
								tostring(math.floor(stats.damage)),
								def.color
							)
						end
						EnemyService.damage(player, target.id, stats.damage, stats.ignoresArmour)

						if stats.splashRadius > 0 and targetModel then
							for id in run.enemies do
								if id ~= target.id then
									local otherModel = EnemyService.modelOf(id)
									if
										otherModel
										and (otherModel.Position - targetModel.Position).Magnitude
											<= stats.splashRadius
									then
										EnemyService.damage(
											player,
											id,
											stats.damage * 0.6,
											stats.ignoresArmour
										)
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

function TowerService.buildViews(player: Player)
	local run = RunState.get(player)
	if not run then
		return {}
	end
	local views = {}
	for id, tower in run.towers do
		table.insert(views, {
			id = id,
			towerType = tower.towerType,
			tier = tower.tier,
			position = tower.position,
			upgradeCost = TowerService.upgradeCost(tower.towerType, tower.tier),
			sellValue = math.floor(tower.spent * Config.Run.SellRefundRatio),
		})
	end
	return views
end

return TowerService
