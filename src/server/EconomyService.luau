--[[
	EconomyService — persistent coins, and the shared rate limiter for every
	gameplay remote.

	Note the split: this owns *persistent* coins, earned at run end and spent on
	unlocks. In-run cash lives in RunState and dies with the run. Keeping them in
	different places means a bug in the run economy can never mint permanent
	currency.

	The rate limiter is centralised here rather than per-remote so a new remote
	cannot accidentally ship without one, and so an exploiter alternating between
	two remotes does not get double the rate.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local DataService = require(script.Parent.DataService)
local Telemetry = require(script.Parent.Telemetry)

local EconomyService = {}

local lastAction: { [Player]: number } = {}
local rejectedActions: { [Player]: number } = {}
local suspicionLogged: { [Player]: boolean } = {}

--[[ Call at the top of every remote handler. False means drop the request. ]]
function EconomyService.allowAction(player: Player): boolean
	local now = os.clock()
	local previous = lastAction[player]
	if previous and (now - previous) < Config.Economy.ActionCooldownSeconds then
		local count = (rejectedActions[player] or 0) + 1
		rejectedActions[player] = count
		if count >= Config.Economy.SuspiciousRejectThreshold and not suspicionLogged[player] then
			suspicionLogged[player] = true
			Telemetry.custom(player, "SuspiciousActionRate", count)
			warn(
				string.format(
					"[Economy] %s exceeded action rate limit %d times",
					player.Name,
					count
				)
			)
		end
		return false
	end
	lastAction[player] = now
	return true
end

--[[
	The single mutation point for persistent currency.

	`reason` flows into the economy analytics event. Give every new source or
	sink a distinct string — otherwise you lose the ability to separate run
	rewards from purchased coins, which is exactly the split that tells you
	whether the loop or the shop is carrying the game.
]]
function EconomyService.addCoins(
	player: Player,
	amount: number,
	reason: string,
	sku: string?
): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	if amount == 0 then
		return true
	end
	if amount < 0 and profile.coins + amount < 0 then
		return false
	end

	profile.coins += amount
	if amount > 0 then
		profile.totalCoinsEarned += amount
	end

	Telemetry.economy(player, amount > 0, "Coins", amount, profile.coins, reason, sku)
	return true
end

function EconomyService.start()
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		rejectedActions[player] = nil
		suspicionLogged[player] = nil
	end)
end

return EconomyService
