--[[
	MatchService — run lifecycle, wave scheduling, the curse bet, and run end.

	Phase machine:

	    build    -> player places towers, timer runs (skippable)
	    wave     -> spawn queue drains, enemies walk, towers fire
	    choosing -> the hook: bank, or take a curse for the next wave
	    dead     -> run over, rewards paid, profile saved

	Every phase has a deadline. An AFK player in "choosing" banks automatically
	rather than parking a server thread forever, and an AFK player in "build"
	starts the wave anyway. A run that can stall is a run that can hold a server
	slot indefinitely.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local Effects = require(script.Parent.Effects)
local EnemyService = require(script.Parent.EnemyService)
local MapService = require(script.Parent.MapService)
local MonetizationService = require(script.Parent.MonetizationService)
local RunState = require(script.Parent.RunState)
local Telemetry = require(script.Parent.Telemetry)
local TowerService = require(script.Parent.TowerService)

local MatchService = {}

local stateRemote: RemoteEvent? = nil
local runEventRemote: RemoteEvent? = nil

local CHOOSE_TIMEOUT_SECONDS = 20

-- ============================================================
-- Client state
-- ============================================================

function MatchService.buildState(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local run = RunState.get(player)

	return {
		coins = profile.coins,
		xp = profile.xp,
		level = profile.level,
		unlockedTowers = profile.unlockedTowers,

		inRun = run ~= nil and run.active,
		wave = run and run.wave or 0,
		baseHealth = run and run.baseHealth or 0,
		maxBaseHealth = run and run.maxBaseHealth or Config.Run.BaseHealth,
		cash = run and run.cash or 0,
		phase = run and run.phase or "idle",
		phaseEndsAt = run and run.phaseEndsAt or 0,

		towers = run and TowerService.buildViews(player) or {},
		curses = run and run.curses or {},
		payoutMultiplier = run and RunState.payoutMultiplier(run) or 1,
		curseOffers = run and run.curseOffers or {},

		passes = {
			starterCash = MonetizationService.hasPass(player, "StarterCash"),
			luckyCurse = MonetizationService.hasPass(player, "LuckyCurse"),
			secondChance = MonetizationService.hasPass(player, "SecondChance"),
		},
	}
end

function MatchService.pushState(player: Player)
	if not stateRemote then
		return
	end
	local state = MatchService.buildState(player)
	if state then
		stateRemote:FireClient(player, state)
	end
end

local function fireEvent(player: Player, payload)
	if runEventRemote then
		runEventRemote:FireClient(player, payload)
	end
end

-- ============================================================
-- Wave composition
-- ============================================================

--[[
	Builds the spawn queue for a wave.

	Composition is derived from scaling rules rather than hand-authored per wave.
	Forty hand-written waves would be forty chances to introduce a balance
	mistake; this retunes with two numbers in Config.
]]
local function buildSpawnQueue(wave: number, effects): { string }
	local queue = {}

	if wave % Config.Waves.BossEveryWaves == 0 then
		table.insert(queue, "boss")
	end

	local eligible = {}
	local totalWeight = 0
	for _, entry in Config.Waves.Unlocks do
		if wave >= entry.fromWave then
			table.insert(eligible, entry)
			totalWeight += entry.weight
		end
	end
	if #eligible == 0 then
		return queue
	end

	local count = math.floor(
		(Config.Waves.CountBase + Config.Waves.CountPerWave * (wave - 1)) * effects.countMultiplier
	)

	for _ = 1, count do
		local roll = math.random() * totalWeight
		local running = 0
		for _, entry in eligible do
			running += entry.weight
			if roll <= running then
				local def = Config.Enemies[entry.id]
				for _ = 1, (def.countMultiplier or 1) do
					table.insert(queue, entry.id)
				end
				break
			end
		end
	end

	return queue
end

-- ============================================================
-- Phase transitions
-- ============================================================

local function startWave(player: Player)
	local run = RunState.get(player)
	if not run or not run.active then
		return
	end

	run.wave += 1
	run.phase = "wave"
	run.phaseEndsAt = 0
	run.curseOffers = {}

	local effects = RunState.curseEffects(run)
	run.spawnQueue = buildSpawnQueue(run.wave, effects)
	run.nextSpawnAt = os.clock()

	Telemetry.custom(player, "WaveStarted", run.wave, {
		wave = run.wave,
		curses = #run.curses,
		payoutMultiplier = RunState.payoutMultiplier(run),
	})

	fireEvent(player, { kind = "waveStarted", wave = run.wave })
	MatchService.pushState(player)
end

--[[ Picks the curse options offered after a wave. ]]
local function rollCurseOffers(run): { any }
	if #run.curses >= Config.Curses.MaxStack then
		return {}
	end

	local pool = {}
	for _, option in Config.Curses.Options do
		local alreadyActive = false
		for _, active in run.curses do
			if active.id == option.id then
				alreadyActive = true
				break
			end
		end
		if not alreadyActive then
			table.insert(pool, option)
		end
	end

	local offers = {}
	for _ = 1, math.min(Config.Curses.OptionsOffered, #pool) do
		local pick = table.remove(pool, math.random(1, #pool))
		table.insert(offers, {
			id = pick.id,
			displayName = pick.displayName,
			description = pick.description,
			payout = pick.payout,
		})
	end
	return offers
end

local function enterChoosing(player: Player)
	local run = RunState.get(player)
	if not run or not run.active then
		return
	end

	run.curseOffers = rollCurseOffers(run)

	if #run.curseOffers == 0 then
		-- Nothing left to offer; skip straight to the build phase rather than
		-- showing an empty decision.
		run.phase = "build"
		run.phaseEndsAt = os.clock() + Config.Run.BuildTimeSeconds
	else
		run.phase = "choosing"
		run.phaseEndsAt = os.clock() + CHOOSE_TIMEOUT_SECONDS
	end

	MatchService.pushState(player)
end

local function endRun(player: Player, reason: string)
	local run = RunState.get(player)
	if not run then
		return
	end
	local profile = DataService.get(player)

	run.active = false
	run.phase = "dead"

	local wavesReached = run.wave
	local cursesTaken = #run.curses
	local diedCursed = cursesTaken > 0 and reason == "defeat"

	local coins = math.floor(
		wavesReached * Config.Economy.CoinsPerWaveReached
			+ cursesTaken * Config.Economy.CoinsPerCurseSurvived
	)
	local xp = wavesReached * Config.Progression.XpPerWaveReached
		+ cursesTaken * Config.Progression.XpPerCurseSurvived

	if profile then
		EconomyService.addCoins(player, coins, "RunReward")

		profile.xp += xp
		while
			profile.level < Config.Progression.MaxLevel
			and profile.xp >= Config.Progression.XpPerLevel * (profile.level + 1)
		do
			profile.xp -= Config.Progression.XpPerLevel * (profile.level + 1)
			profile.level += 1
			MatchService.syncUnlocks(profile)
			fireEvent(player, { kind = "levelUp", level = profile.level })
		end

		profile.stats.runsPlayed += 1
		if wavesReached > profile.stats.bestWave then
			profile.stats.bestWave = wavesReached
		end
		if coins > profile.stats.bestRunCoins then
			profile.stats.bestRunCoins = coins
		end
		profile.stats.totalCursesTaken += cursesTaken
		if diedCursed then
			profile.stats.deathsWhileCursed += 1
		end

		--[[
			The instrument that decides whether the hook is tuned. If nearly every
			run ends while cursed, the curse is a trap rather than a decision and
			players will correctly learn never to take it.
		]]
		Telemetry.custom(player, "RunEnded", wavesReached, {
			reason = reason,
			wave = wavesReached,
			curses = cursesTaken,
			diedCursed = diedCursed,
			coinsEarned = coins,
			towersPlaced = (function()
				local n = 0
				for _ in run.towers do
					n += 1
				end
				return n
			end)(),
		})

		task.spawn(DataService.save, player, false)
	end

	EnemyService.clearAll(player)
	TowerService.clearAll(player)

	fireEvent(player, {
		kind = "runEnded",
		reason = reason,
		wave = wavesReached,
		coins = coins,
		curses = cursesTaken,
	})

	RunState.clear(player)
	MatchService.pushState(player)
end

-- ============================================================
-- Unlocks
-- ============================================================

--[[
	Grants any tower the player's level now qualifies for.

	Additive only. A future balance change to unlockLevel must never take a tower
	away from someone who already earned it, which is why the list is stored
	rather than derived on read.
]]
function MatchService.syncUnlocks(profile)
	for towerType, def in Config.Towers do
		if profile.level >= def.unlockLevel then
			local has = false
			for _, id in profile.unlockedTowers do
				if id == towerType then
					has = true
					break
				end
			end
			if not has then
				table.insert(profile.unlockedTowers, towerType)
			end
		end
	end
end

-- ============================================================
-- Player actions
-- ============================================================

function MatchService.startRun(player: Player)
	if not EconomyService.allowAction(player) then
		return
	end
	local profile = DataService.get(player)
	if not profile or RunState.isActive(player) then
		return
	end

	local bonus = if MonetizationService.hasPass(player, "StarterCash") then 200 else 0
	RunState.create(player, bonus)

	Telemetry.onboardingStep(player, Telemetry.OnboardingStep.FirstRun)
	Telemetry.funnelStep(player, Telemetry.OnboardingStep.FirstRun)
	Telemetry.custom(player, "RunStarted", 1, { level = profile.level })

	fireEvent(player, { kind = "runStarted" })
	MatchService.pushState(player)
end

function MatchService.placeTower(player: Player, towerType: unknown, position: unknown)
	if not EconomyService.allowAction(player) then
		return
	end
	if type(towerType) ~= "string" or typeof(position) ~= "Vector3" then
		return
	end

	local profile = DataService.get(player)
	if not profile then
		return
	end

	-- Unlock check is server-side. The client hides locked towers, but hiding a
	-- button is not a permission check.
	local unlocked = false
	for _, id in profile.unlockedTowers do
		if id == towerType then
			unlocked = true
			break
		end
	end
	if not unlocked then
		return
	end

	if TowerService.place(player, towerType, position) then
		Telemetry.custom(player, "TowerPlaced", 1, { tower = towerType })
		MatchService.pushState(player)
	end
end

function MatchService.upgradeTower(player: Player, towerId: unknown)
	if not EconomyService.allowAction(player) or type(towerId) ~= "string" then
		return
	end
	if TowerService.upgrade(player, towerId) then
		MatchService.pushState(player)
	end
end

function MatchService.sellTower(player: Player, towerId: unknown)
	if not EconomyService.allowAction(player) or type(towerId) ~= "string" then
		return
	end
	if TowerService.sell(player, towerId) then
		MatchService.pushState(player)
	end
end

function MatchService.skipBuild(player: Player)
	if not EconomyService.allowAction(player) then
		return
	end
	local run = RunState.get(player)
	if run and run.active and run.phase == "build" then
		startWave(player)
	end
end

--[[
	The hook. `curseId` nil means bank.

	Curses are validated against what was actually offered, not against the full
	config table — otherwise a hooked client could pick Blight every wave and
	farm the 3x payout without it ever being on the menu.
]]
function MatchService.chooseCurse(player: Player, curseId: unknown)
	if not EconomyService.allowAction(player) then
		return
	end
	local run = RunState.get(player)
	if not run or not run.active or run.phase ~= "choosing" then
		return
	end

	if curseId ~= nil then
		if type(curseId) ~= "string" then
			return
		end
		local offered = nil
		for _, offer in run.curseOffers do
			if offer.id == curseId then
				offered = offer
				break
			end
		end
		if not offered then
			return
		end

		local payout = offered.payout
		if MonetizationService.hasPass(player, "LuckyCurse") then
			payout += 0.5
		end

		table.insert(run.curses, {
			id = offered.id,
			displayName = offered.displayName,
			payout = payout,
		})

		Telemetry.custom(player, "CurseTaken", #run.curses, {
			curse = offered.id,
			wave = run.wave,
			stack = #run.curses,
			payoutMultiplier = RunState.payoutMultiplier(run),
		})
		fireEvent(player, { kind = "curseTaken", displayName = offered.displayName })
	else
		Telemetry.custom(player, "CurseDeclined", 1, { wave = run.wave, stack = #run.curses })
	end

	run.curseOffers = {}
	run.phase = "build"
	run.phaseEndsAt = os.clock() + Config.Run.BuildTimeSeconds
	MatchService.pushState(player)
end

-- ============================================================
-- Tick
-- ============================================================

local function tickRun(player: Player, dt: number)
	local run = RunState.get(player)
	if not run or not run.active then
		return
	end
	local now = os.clock()

	if run.phase == "build" then
		if now >= run.phaseEndsAt then
			startWave(player)
		end
		return
	end

	if run.phase == "choosing" then
		if now >= run.phaseEndsAt then
			MatchService.chooseCurse(player, nil) -- AFK banks rather than stalling
		end
		return
	end

	if run.phase ~= "wave" then
		return
	end

	-- Drain the spawn queue.
	if #run.spawnQueue > 0 and now >= run.nextSpawnAt then
		local enemyType = table.remove(run.spawnQueue, 1)
		local healthMultiplier = Config.Waves.HealthScaling ^ (run.wave - 1)
		EnemyService.spawn(player, enemyType, healthMultiplier)
		run.nextSpawnAt = now + Config.Waves.SpawnIntervalSeconds
	end

	EnemyService.step(player, dt)
	TowerService.step(player, dt)

	-- Wave cleared.
	if #run.spawnQueue == 0 and EnemyService.count(player) == 0 then
		local multiplier = RunState.payoutMultiplier(run)
		local bonus = math.floor(
			(Config.Run.WaveClearBonusBase + Config.Run.WaveClearBonusPerWave * run.wave)
				* multiplier
		)
		run.cash += bonus

		Telemetry.custom(player, "WaveCleared", run.wave, {
			wave = run.wave,
			bonus = bonus,
			curses = #run.curses,
		})
		fireEvent(player, { kind = "waveCleared", wave = run.wave, bonus = bonus })

		if run.wave >= Config.Run.MaxWaves then
			endRun(player, "victory")
		else
			enterChoosing(player)
		end
	end
end

-- ============================================================
-- Lifecycle
-- ============================================================

function MatchService.start()
	stateRemote = Remotes.get("StateChanged") :: RemoteEvent
	runEventRemote = Remotes.get("RunEvent") :: RemoteEvent

	MonetizationService.setStateRefresh(MatchService.pushState)
	MonetizationService.registerProductHandler("InstantWave", function(player)
		local run = RunState.get(player)
		if run and run.active and run.phase == "build" then
			startWave(player)
			return true
		end
		return false -- nothing to skip; do not consume the purchase
	end)
	MonetizationService.registerProductHandler("ReviveNow", function(player)
		local run = RunState.get(player)
		if run and run.active and run.baseHealth < run.maxBaseHealth then
			run.baseHealth = run.maxBaseHealth
			MatchService.pushState(player)
			return true
		end
		return false
	end)
	-- Table-driven so adding a gameplay remote is one entry here and one in
	-- Remotes, rather than a wiring line that is easy to forget.
	local handlers: { [string]: (Player, ...any) -> () } = {
		StartRun = MatchService.startRun,
		PlaceTower = MatchService.placeTower,
		UpgradeTower = MatchService.upgradeTower,
		SellTower = MatchService.sellTower,
		SkipBuildPhase = MatchService.skipBuild,
		ChooseCurse = MatchService.chooseCurse,
	}
	for name, handler in handlers do
		local remote = Remotes.get(name) :: RemoteEvent
		remote.OnServerEvent:Connect(handler)
	end

	local getState = Remotes.get("GetState") :: RemoteFunction
	getState.OnServerInvoke = function(player: Player)
		local deadline = os.clock() + 20
		while not DataService.get(player) and os.clock() < deadline do
			task.wait(0.1)
		end
		return MatchService.buildState(player)
	end

	EnemyService.Killed.Event:Connect(function(player: Player)
		local run = RunState.get(player)
		if not run or not run.active then
			return
		end
		local reward = math.floor(
			Config.Run.CashPerKillBase
				* (Config.Run.CashPerKillScaling ^ (run.wave - 1))
				* RunState.payoutMultiplier(run)
		)
		run.cash += reward
	end)

	EnemyService.Leaked.Event:Connect(function(player: Player, enemy)
		local run = RunState.get(player)
		if not run or not run.active then
			return
		end
		local def = Config.Enemies[enemy.enemyType]
		local effects = RunState.curseEffects(run)
		local damage = math.ceil(def.damageToBase * effects.baseDamageMultiplier)

		run.baseHealth -= damage

		-- A leak is the only thing in the game that actively costs the player.
		-- It should be impossible to miss.
		local map = MapService.get(player)
		if map then
			Effects.shockwave(map.basePosition + Vector3.new(0, 2, 0), Color3.fromRGB(255, 80, 80))
			Effects.popup(
				map.basePosition + Vector3.new(0, 12, 0),
				string.format("-%d", damage),
				Color3.fromRGB(255, 90, 90)
			)
		end

		fireEvent(player, { kind = "leak", damage = damage, baseHealth = run.baseHealth })

		if run.baseHealth <= 0 then
			-- Second Chance absorbs one defeat per run rather than granting
			-- permanent immortality.
			if MonetizationService.hasPass(player, "SecondChance") and run.revivesUsed == 0 then
				run.revivesUsed = 1
				run.baseHealth = math.floor(run.maxBaseHealth * 0.5)
				fireEvent(player, { kind = "revived" })
				MatchService.pushState(player)
			else
				endRun(player, "defeat")
			end
		end
	end)

	DataService.ProfileLoaded.Event:Connect(function(player: Player, profile)
		MatchService.syncUnlocks(profile)
		MapService.build(player)
		MatchService.pushState(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		RunState.clear(player)
		MapService.destroy(player)
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, player in Players:GetPlayers() do
				tickRun(player, dt)
			end
		end
	end)

	-- State push is separate from the 10Hz tick: the client only needs cash,
	-- health and timers refreshed a few times a second, and pushing the full
	-- state ten times a second would be pure bandwidth waste.
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				if RunState.isActive(player) then
					MatchService.pushState(player)
				end
			end
		end
	end)
end

return MatchService
