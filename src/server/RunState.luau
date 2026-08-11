--[[
	RunState — storage for in-progress runs, and nothing else.

	Deliberately logic-free. MatchService, TowerService and EnemyService all need
	to read and mutate the same run, and any of them owning it would make the
	other two require it — a cycle. Parking the state in a module with no
	dependencies of its own keeps every arrow pointing one way.

	Runs live in memory and die with the run. Nothing here is persisted: a run is
	meant to be lost, and saving it would turn death into a save-scum problem.
]]

local HttpService = game:GetService("HttpService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local RunState = {}

local runs: { [Player]: any } = {}

function RunState.newId(): string
	return HttpService:GenerateGUID(false)
end

function RunState.get(player: Player): any?
	return runs[player]
end

function RunState.isActive(player: Player): boolean
	local run = runs[player]
	return run ~= nil and run.active
end

function RunState.create(player: Player, startingCashBonus: number): any
	local run = {
		active = true,
		wave = 0,
		baseHealth = Config.Run.BaseHealth,
		maxBaseHealth = Config.Run.BaseHealth,
		cash = Config.Run.StartingCash + startingCashBonus,
		towers = {},
		enemies = {},
		curses = {},
		phase = "build",
		phaseEndsAt = os.clock() + Config.Run.BuildTimeSeconds,
		revivesUsed = 0,
		curseOffers = {},
		-- Accumulated coins for this run, paid out at the end.
		earnedCoins = 0,
		spawnQueue = {},
		nextSpawnAt = 0,
	}
	runs[player] = run
	return run
end

function RunState.clear(player: Player)
	runs[player] = nil
end

function RunState.all(): { [Player]: any }
	return runs
end

--[[
	Payout multiplier from stacked curses. Multiplicative on purpose — the
	difficulty of stacked curses adds up, so the reward has to outpace it or
	nobody takes the bet twice.
]]
function RunState.payoutMultiplier(run: any): number
	local multiplier = 1
	for _, curse in run.curses do
		multiplier *= curse.payout
	end
	return multiplier
end

--[[ Summed curse effects, resolved once per wave rather than per enemy. ]]
function RunState.curseEffects(run: any)
	local effects = {
		speedMultiplier = 1,
		armourBonus = 0,
		countMultiplier = 1,
		rangeMultiplier = 1,
		baseDamageMultiplier = 1,
	}
	for _, active in run.curses do
		for _, option in Config.Curses.Options do
			if option.id == active.id then
				effects.speedMultiplier *= option.speedMultiplier or 1
				effects.armourBonus += option.armourBonus or 0
				effects.countMultiplier *= option.countMultiplier or 1
				effects.rangeMultiplier *= option.rangeMultiplier or 1
				effects.baseDamageMultiplier *= option.baseDamageMultiplier or 1
			end
		end
	end
	return effects
end

return RunState
