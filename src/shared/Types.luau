--!strict
--[[
	Types — the saved-data schema and the state shapes pushed to clients.

	Note what is NOT persisted: the run itself. Towers placed, cash in hand, wave
	number and active curses all live in server memory and die with the run. That
	is deliberate — a run is meant to be lost, and persisting it would turn a
	death into a save-scum problem.

	Profile is what lives in the DataStore. Every field must be JSON-serializable
	(no Instances, no mixed-key tables, no NaN). Adding a field means bumping
	Config.DataVersion and handling it in DataService.migrate().
]]

export type Profile = {
	version: number,

	-- Persistent currency, earned at run end and spent on unlocks.
	coins: number,
	totalCoinsEarned: number,

	xp: number,
	level: number,

	--[[
		Tower ids the player has unlocked. Levelling grants these, but storing the
		list explicitly rather than deriving it from level means a future balance
		change to unlock levels cannot retroactively take a tower away from
		someone who already had it.
	]]
	unlockedTowers: { string },

	stats: {
		runsPlayed: number,
		bestWave: number,
		bestRunCoins: number,
		totalCursesTaken: number,
		--[[
			The instrument that decides whether the hook is tuned. If nearly every
			run ends on a cursed wave, the curse is a trap rather than a decision,
			and players will correctly learn never to take it.
		]]
		deathsWhileCursed: number,
	},

	-- Retention primitives. Unix seconds, server clock (os.time()).
	firstJoinTime: number,
	lastJoinTime: number,
	sessionCount: number,
	totalPlaytimeSeconds: number,
	daysSeen: { string },
	retentionReported: { [string]: boolean },

	-- Monetization
	robuxSpent: number,
	purchaseCount: number,
	processedReceipts: { [string]: boolean },
	receiptOrder: { string },
}

-- ============================================================
-- Run state (server memory only)
-- ============================================================

export type Tower = {
	id: string, -- unique instance id
	towerType: string,
	tier: number, -- 0-based; 0 is the base tier
	position: Vector3,
	spent: number, -- total cash sunk, for sell refunds
	lastFired: number,
}

export type Enemy = {
	id: string,
	enemyType: string,
	health: number,
	maxHealth: number,
	pathProgress: number, -- 0..1 along the path
	slowUntil: number,
	slowFactor: number,
}

export type ActiveCurse = {
	id: string,
	displayName: string,
	payout: number,
}

export type Run = {
	active: boolean,
	wave: number,
	baseHealth: number,
	cash: number,
	towers: { [string]: Tower },
	enemies: { [string]: Enemy },
	curses: { ActiveCurse },
	phase: string, -- "build" | "wave" | "choosing" | "dead"
	phaseEndsAt: number,
	revivesUsed: number,
}

-- ============================================================
-- Client views
-- ============================================================

export type TowerView = {
	id: string,
	towerType: string,
	tier: number,
	position: Vector3,
	upgradeCost: number?, -- nil when maxed
	sellValue: number,
}

export type CurseOffer = {
	id: string,
	displayName: string,
	description: string,
	payout: number,
}

export type ClientState = {
	coins: number,
	xp: number,
	level: number,
	unlockedTowers: { string },

	inRun: boolean,
	wave: number,
	baseHealth: number,
	maxBaseHealth: number,
	cash: number,
	phase: string,
	phaseEndsAt: number,

	towers: { TowerView },
	curses: { ActiveCurse },
	--[[
		Precomputed by the server. The client is shown the multiplier, never the
		formula — shipping the payout math would let a hooked client disagree with
		the server about what a wave is worth.
	]]
	payoutMultiplier: number,
	curseOffers: { CurseOffer },

	passes: {
		starterCash: boolean,
		luckyCurse: boolean,
		secondChance: boolean,
	},
}

return {}
