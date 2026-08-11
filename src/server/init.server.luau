--[[
	Server bootstrap.

	Start order matters and is not arbitrary:
	  1. Remotes.init()  — instances must exist before any client asks for them.
	  2. DataService     — connects PlayerAdded; everything else depends on
	                       profiles existing, so it must be listening first.
	  3. EconomyService  — owns the shared action rate limiter.
	  4. Monetization    — resolves pass ownership on ProfileLoaded, and must
	                       start before MatchService, which registers its product
	                       grant handlers into it.
	  5. MatchService    — the game. Builds each player's map on ProfileLoaded.
	  6. Session hooks   — telemetry for join/leave.

	If you add a service, give it an explicit .start() and put it in this list
	rather than letting module require order decide. Implicit init order is how
	"works in Studio, breaks in production" bugs get in.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Ambience = require(script.Ambience)
local DataService = require(script.DataService)
local EconomyService = require(script.EconomyService)
local MatchService = require(script.MatchService)
local MonetizationService = require(script.MonetizationService)
local Telemetry = require(script.Telemetry)

Remotes.init()

-- Before anything else visual. Roblox's default lighting reads as "unfinished
-- baseplate", and no amount of geometry recovers from that first impression.
Ambience.apply()

DataService.start()
EconomyService.start()
MonetizationService.start()
MatchService.start()

-- ============================================================
-- Session + retention telemetry
-- ============================================================

DataService.ProfileLoaded.Event:Connect(function(player: Player, profile: any, unsaved: boolean)
	Telemetry.beginSession(player)
	Telemetry.onboardingStep(player, Telemetry.OnboardingStep.Joined)
	Telemetry.onboardingStep(player, Telemetry.OnboardingStep.DataLoaded)
	Telemetry.funnelStep(player, Telemetry.OnboardingStep.Joined)
	Telemetry.funnelStep(player, Telemetry.OnboardingStep.DataLoaded)

	if unsaved then
		-- Watch this one. A nonzero rate means retention numbers are polluted by
		-- players whose progress silently vanishes.
		Telemetry.custom(player, "DataLoadFailed", 1)
	end

	local isNew = profile.sessionCount <= 1
	Telemetry.custom(player, if isNew then "NewPlayer" else "ReturningPlayer", 1, {
		sessionCount = profile.sessionCount,
		distinctDays = #profile.daysSeen,
		level = profile.level,
		bestWave = profile.stats.bestWave,
	})

	--[[
		Returning players are reported with their curse history attached.

		This is the question that decides whether the hook works: do players who
		lost a run to a curse come back? A cursed defeat is the only moment the
		game actively punishes a decision it encouraged, and if the punished
		churn, the payout curve is wrong regardless of how the aggregates look.
	]]
	if not isNew then
		Telemetry.custom(player, "ReturnedAfterCurses", profile.stats.deathsWhileCursed, {
			runsPlayed = profile.stats.runsPlayed,
			totalCursesTaken = profile.stats.totalCursesTaken,
			deathsWhileCursed = profile.stats.deathsWhileCursed,
		})
	end

	local bucket = Telemetry.reportRetention(player, profile)
	if bucket then
		print(string.format("[CursedWaves] %s returned on D%d bucket", player.Name, bucket))
	end
end)

-- Heartbeat so a server crash still leaves a session-length floor on the
-- dashboard rather than losing the session entirely.
task.spawn(function()
	while true do
		task.wait(Config.Analytics.SessionHeartbeatSeconds)
		for _, player in Players:GetPlayers() do
			if DataService.get(player) then
				Telemetry.custom(player, "SessionHeartbeat", 1)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local profile = DataService.get(player)
	if profile then
		Telemetry.custom(player, "SessionEnd", 1, {
			coins = profile.coins,
			level = profile.level,
			runsPlayed = profile.stats.runsPlayed,
			bestWave = profile.stats.bestWave,
		})
	end
	Telemetry.endSession(player)
end)

print(string.format("[CursedWaves] server up (data v%d)", Config.DataVersion))
