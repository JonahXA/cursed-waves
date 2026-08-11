--!strict
--[[
	Config — every tunable and every Roblox asset ID lives here.

	Content is data on purpose. Towers, enemies, waves and curses are tables, so
	balancing this game is editing numbers rather than editing code — and so the
	art burden stays at "one mesh per tower, recoloured per tier" instead of one
	model per upgrade.
]]

local Config = {}

-- ============================================================
-- Identity
-- ============================================================

Config.GameName = "CursedWaves"

-- Bump this when you change the shape of saved player data. Any profile with an
-- older version runs through DataService's migration path on load.
Config.DataVersion = 1

-- Namespaced per game. DataStores are scoped to the experience, but a distinct
-- name means a place misconfiguration can't quietly read another project's
-- profiles.
Config.PlayerDataStore = "CursedWaves_PlayerData_v1"

-- Target experience: universe 10682103053, place 86245995403264.

-- ============================================================
-- Monetization — FILL THESE IN
--
-- Zeroed until created against this game's own universe. A pass or product ID
-- only works inside the experience that owns it, and cross-experience sales were
-- disabled platform-wide in May 2026.
--
-- Monetization is inert while these are 0 and logs a warning rather than
-- failing, so the game is fully playable before they exist.
-- ============================================================

Config.GamePasses = {
	-- Start every run with extra cash.
	StarterCash = 0, -- TODO
	-- Curse payouts increased.
	LuckyCurse = 0, -- TODO
	-- One free revive per run when the base would fall.
	SecondChance = 0, -- TODO
}

Config.DeveloperProducts = {
	CoinsSmall = 0, -- TODO
	InstantWave = 0, -- TODO — skip the build timer
	ReviveNow = 0, -- TODO — one-off revive, separate from the pass
}

-- Persistent coins granted by currency products. Non-currency products get their
-- own handlers registered by the systems that own the state.
Config.ProductGrants = {
	CoinsSmall = 500,
}

-- ============================================================
-- Run economy — in-match cash, spent on towers. Distinct from persistent coins.
-- ============================================================

Config.Run = {
	BaseHealth = 100,
	StartingCash = 150,

	-- Seconds of build time before wave 1, and between waves. Long enough to
	-- make a real decision, short enough that the game never feels idle.
	BuildTimeSeconds = 15,

	CashPerKillBase = 8,
	CashPerKillScaling = 1.10, -- per wave
	WaveClearBonusBase = 50,
	WaveClearBonusPerWave = 10,

	-- Selling refunds this share of everything spent on a tower.
	SellRefundRatio = 0.6,

	MaxWaves = 40, -- a run must be able to END; endless is bad for session shape
}

-- ============================================================
-- Persistent economy — coins earned per run, spent on unlocks.
-- ============================================================

Config.Economy = {
	StartingCoins = 0,

	-- Coins awarded at run end, scaled by how far you got.
	CoinsPerWaveReached = 12,
	CoinsPerCurseSurvived = 25,

	-- Shared rate limit across every gameplay remote. A hooked client can fire
	-- thousands of times a second; without a floor that is a free action printer.
	ActionCooldownSeconds = 0.15,
	SuspiciousRejectThreshold = 200,
}

-- ============================================================
-- Towers
--
-- Three upgrade tiers each. A tier is a stat multiplier, not a new model — the
-- same mesh scaled and recoloured, which is what keeps the art burden flat.
-- ============================================================

Config.Towers = {
	pea = {
		displayName = "Pea",
		cost = 100,
		unlockLevel = 0, -- always available
		damage = 10,
		range = 22,
		fireRate = 1.2, -- shots per second
		splashRadius = 0,
		slowFactor = 0,
		ignoresArmour = false,
		color = Color3.fromRGB(120, 200, 110),
		upgrades = {
			{ cost = 120, damage = 1.6, range = 1.1, fireRate = 1.2 },
			{ cost = 300, damage = 2.4, range = 1.2, fireRate = 1.4 },
		},
	},
	frost = {
		displayName = "Frost",
		cost = 200,
		unlockLevel = 2,
		damage = 0, -- pure utility; the slow IS the contribution
		range = 20,
		fireRate = 0.8,
		splashRadius = 8,
		slowFactor = 0.35,
		ignoresArmour = false,
		color = Color3.fromRGB(140, 210, 240),
		upgrades = {
			{ cost = 220, slowFactor = 1.3, range = 1.15, fireRate = 1.2 },
			{ cost = 480, slowFactor = 1.5, range = 1.3, fireRate = 1.4 },
		},
	},
	splash = {
		displayName = "Splash",
		cost = 250,
		unlockLevel = 4,
		damage = 14,
		range = 18,
		fireRate = 0.7,
		splashRadius = 10,
		slowFactor = 0,
		ignoresArmour = false, -- deliberately weak into armour; Sniper answers Tanks
		color = Color3.fromRGB(240, 160, 80),
		upgrades = {
			{ cost = 280, damage = 1.7, splashRadius = 1.2, fireRate = 1.15 },
			{ cost = 620, damage = 2.5, splashRadius = 1.4, fireRate = 1.3 },
		},
	},
	sniper = {
		displayName = "Sniper",
		cost = 400,
		unlockLevel = 7,
		damage = 65,
		range = 55,
		fireRate = 0.35,
		splashRadius = 0,
		slowFactor = 0,
		ignoresArmour = true,
		color = Color3.fromRGB(200, 120, 220),
		upgrades = {
			{ cost = 450, damage = 1.8, range = 1.1, fireRate = 1.25 },
			{ cost = 900, damage = 2.6, range = 1.2, fireRate = 1.4 },
		},
	},
}

Config.TowerOrder = { "pea", "frost", "splash", "sniper" }

-- ============================================================
-- Enemies
-- ============================================================

Config.Enemies = {
	grunt = {
		displayName = "Grunt",
		health = 40,
		speed = 10,
		armour = 0,
		damageToBase = 1,
		color = Color3.fromRGB(200, 80, 80),
		size = 2.5,
	},
	runner = {
		displayName = "Runner",
		health = 22,
		speed = 20,
		armour = 0,
		damageToBase = 1,
		color = Color3.fromRGB(240, 220, 90),
		size = 2,
	},
	tank = {
		displayName = "Tank",
		health = 220,
		speed = 6,
		armour = 0.35, -- flat damage reduction, ignored by Sniper
		damageToBase = 4,
		color = Color3.fromRGB(120, 120, 140),
		size = 4,
	},
	swarm = {
		displayName = "Swarm",
		health = 14,
		speed = 13,
		armour = 0,
		damageToBase = 1,
		color = Color3.fromRGB(180, 100, 220),
		size = 1.6,
		countMultiplier = 3, -- spawns in packs
	},
	boss = {
		displayName = "Boss",
		health = 2200,
		speed = 7,
		armour = 0.25,
		damageToBase = 20,
		immuneToSlow = true,
		color = Color3.fromRGB(255, 60, 60),
		size = 6,
	},
}

-- ============================================================
-- Waves
--
-- Composition is derived rather than hand-authored per wave: 40 hand-written
-- waves would be 40 places to introduce a balance mistake, and derived scaling
-- can be retuned with two numbers.
-- ============================================================

Config.Waves = {
	HealthScaling = 1.18, -- per wave, compounding
	CountBase = 6,
	CountPerWave = 2,

	BossEveryWaves = 10,

	-- Which enemy types are eligible from which wave, and their relative weight.
	Unlocks = {
		{ id = "grunt", fromWave = 1, weight = 50 },
		{ id = "runner", fromWave = 3, weight = 30 },
		{ id = "swarm", fromWave = 6, weight = 25 },
		{ id = "tank", fromWave = 8, weight = 20 },
	},

	SpawnIntervalSeconds = 0.7,
}

-- ============================================================
-- Curses — the hook.
--
-- Payout stacks multiplicatively while difficulty stacks additively. That gap is
-- deliberately in the player's favour so that pushing is genuinely tempting; if
-- it were the other way round nobody would ever take the bet twice.
--
-- The tuning goal: players should curse *sometimes*. A distribution spiking at
-- zero means the reward is too low; spiking at max means it is free money.
-- ============================================================

Config.Curses = {
	MaxStack = 5,

	Options = {
		{
			id = "haste",
			displayName = "Haste",
			description = "Enemies move 40% faster",
			payout = 2.0,
			speedMultiplier = 1.4,
		},
		{
			id = "armour",
			displayName = "Armour",
			description = "Enemies take 30% less damage",
			payout = 2.0,
			armourBonus = 0.30,
		},
		{
			id = "horde",
			displayName = "Horde",
			description = "60% more enemies",
			payout = 2.5,
			countMultiplier = 1.6,
		},
		{
			id = "fog",
			displayName = "Fog",
			description = "Tower range reduced 25%",
			payout = 2.5,
			rangeMultiplier = 0.75,
		},
		{
			id = "blight",
			displayName = "Blight",
			description = "Leaks deal double damage to your base",
			payout = 3.0,
			baseDamageMultiplier = 2.0,
		},
	},

	-- How many curse options to offer between waves. Offering a choice rather
	-- than a single take-it-or-leave-it keeps the decision interesting even when
	-- the answer is "yes".
	OptionsOffered = 2,
}

-- ============================================================
-- Sound
--
-- IDs are filled in from the Creator Store once picked. Everything is wired and
-- called already; an empty id is skipped silently, so the game is fully playable
-- while these are blank and gains audio the moment they are set — no code change.
--
-- Format: "rbxassetid://123456789"
-- ============================================================

Config.Sounds = {
	-- Combat
	towerFire = { id = "", volume = 0.25, pitchRange = { 0.92, 1.08 } },
	towerFireHeavy = { id = "", volume = 0.35, pitchRange = { 0.9, 1.05 } },
	enemyDeath = { id = "", volume = 0.3, pitchRange = { 0.9, 1.15 } },
	bossDeath = { id = "", volume = 0.6, pitchRange = { 0.95, 1.05 } },

	-- Stakes
	leak = { id = "", volume = 0.6, pitchRange = { 0.95, 1.05 } },
	defeat = { id = "", volume = 0.7, pitchRange = { 1, 1 } },
	victory = { id = "", volume = 0.7, pitchRange = { 1, 1 } },

	-- Interface
	place = { id = "", volume = 0.4, pitchRange = { 0.97, 1.03 } },
	upgrade = { id = "", volume = 0.45, pitchRange = { 1, 1 } },
	sell = { id = "", volume = 0.35, pitchRange = { 1, 1 } },
	click = { id = "", volume = 0.3, pitchRange = { 1, 1 } },

	-- The hook. These two carry the emotional weight of the whole game and
	-- deserve the most distinctive sounds in the set.
	curseTaken = { id = "", volume = 0.7, pitchRange = { 1, 1 } },
	bank = { id = "", volume = 0.5, pitchRange = { 1, 1 } },

	waveStart = { id = "", volume = 0.5, pitchRange = { 1, 1 } },
	waveCleared = { id = "", volume = 0.5, pitchRange = { 1, 1 } },
	levelUp = { id = "", volume = 0.6, pitchRange = { 1, 1 } },
}

-- ============================================================
-- Progression
-- ============================================================

Config.Progression = {
	XpPerWaveReached = 10,
	XpPerCurseSurvived = 20,
	-- Level N requires this much cumulative XP times N.
	XpPerLevel = 120,
	MaxLevel = 30,
}

-- ============================================================
-- Persistence
-- ============================================================

Config.Data = {
	AutosaveIntervalSeconds = 120,
	MaxLoadRetries = 4,
	RetryBaseDelaySeconds = 1, -- exponential: 1, 2, 4, 8
}

-- ============================================================
-- Analytics
-- ============================================================

Config.Analytics = {
	SessionHeartbeatSeconds = 60,
	RetentionDaysTracked = { 1, 2, 3, 7, 14, 28 },
	OnboardingFunnelName = "Onboarding",
}

-- ============================================================
-- Kill criteria. Nothing reads these at runtime; they live here so the bar is
-- written down before building, not rationalized after.
-- ============================================================

Config.KillCriteria = {
	-- Gate 0, first 72 hours. A community heuristic rather than documented
	-- Roblox policy — what Roblox has officially announced is only that
	-- Recommended For You scores D1, D2-7 and D8-28 over a 28-day window. Right
	-- shape, not a hard line.
	MinLikeRatioPercent = 80,
	MinAvgSessionMinutes = 8,

	MinD1RetentionPercent = 20,
	EvaluateAfterOrganicVisits = 5000,
	MinCCUWithinTwoWeeks = 50,
}

return Config
