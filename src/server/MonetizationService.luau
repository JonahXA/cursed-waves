--[[
	MonetizationService — game passes and developer products.

	The ProcessReceipt callback is the highest-stakes code here. Two rules:

	  1. IDEMPOTENT. Roblox re-delivers a receipt until you return
	     PurchaseGranted, across server restarts and rejoins. Without a durable
	     record of honored receipts, one purchase during a hiccup gets granted
	     repeatedly.

	  2. NotProcessedYet on ANY uncertainty. Returning PurchaseGranted when the
	     grant did not durably persist means the player paid and got nothing, and
	     Roblox will not re-deliver.

	Both are satisfied by keeping the receipt marker in the player's own profile,
	so the grant and the marker are one DataStore write with no window between
	them. There is deliberately no second store and no UpdateAsync — an earlier
	version of this file put a yielding save inside an UpdateAsync transform,
	which throws at runtime because transforms may not yield.

	This exact design was verified against production in phase0: three live
	purchases, each granted exactly once.

	Non-currency products register their own handlers via registerProductHandler,
	so this file never learns what a tower or a wave is.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local Telemetry = require(script.Parent.Telemetry)

local MonetizationService = {}

local productLookup: { [number]: string } = {}
local shopOpened: { [Player]: boolean } = {}
local ownedPasses: { [Player]: { [string]: boolean } } = {}
local productHandlers: { [string]: (Player) -> boolean } = {}
local stateRefresh: ((Player) -> ())? = nil

local function isConfigured(id: number?): boolean
	return type(id) == "number" and id > 0
end

function MonetizationService.registerProductHandler(key: string, handler: (Player) -> boolean)
	productHandlers[key] = handler
end

function MonetizationService.setStateRefresh(fn: (Player) -> ())
	stateRefresh = fn
end

local function refresh(player: Player)
	if stateRefresh then
		stateRefresh(player)
	end
end

function MonetizationService.hasPass(player: Player, passKey: string): boolean
	local owned = ownedPasses[player]
	return owned ~= nil and owned[passKey] == true
end

local function resolvePasses(player: Player)
	local owned = {}
	for passKey, passId in Config.GamePasses do
		if isConfigured(passId) then
			for attempt = 1, 3 do
				local ok, result = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
				end)
				if ok then
					owned[passKey] = result
					break
				end
				warn(
					string.format(
						"[Monetization] pass check %d for %s (%s) failed: %s",
						attempt,
						player.Name,
						passKey,
						tostring(result)
					)
				)
				task.wait(attempt)
			end
		else
			owned[passKey] = false
		end
	end
	ownedPasses[player] = owned
	refresh(player)
end

--[[
	Applies a product and returns its undo, or nil on failure.

	Returning the reversal rather than a boolean is what lets the durability gate
	below work identically for currency and gameplay grants — the caller can
	reverse whatever happened without knowing what it was.
]]
local function applyGrant(player: Player, configKey: string): (() -> ())?
	local coins = Config.ProductGrants[configKey]
	if coins then
		if not EconomyService.addCoins(player, coins, "ProductPurchase", configKey) then
			return nil
		end
		return function()
			EconomyService.addCoins(player, -coins, "ProductRollback", configKey)
		end
	end

	local handler = productHandlers[configKey]
	if not handler then
		warn(string.format("[Monetization] no grant defined for %q", configKey))
		return nil
	end
	if not handler(player) then
		return nil
	end

	--[[
		Gameplay grants have no clean inverse — un-starting a wave the player has
		already watched begin would be worse than the duplicate it prevents. The
		durability gate still covers the common case, and this fails in the
		direction of the player keeping something we could not record.
	]]
	return function() end
end

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = DataService.get(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local configKey = productLookup[receiptInfo.ProductId]
	if not configKey then
		warn(string.format("[Monetization] unmapped ProductId %d", receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)
	if profile.processedReceipts[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local undo = applyGrant(player, configKey)
	if not undo then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	profile.robuxSpent += receiptInfo.CurrencySpent
	profile.purchaseCount += 1
	DataService.rememberReceipt(profile, purchaseId)

	if not DataService.save(player, false) then
		undo()
		profile.robuxSpent -= receiptInfo.CurrencySpent
		profile.purchaseCount -= 1
		DataService.forgetReceipt(profile, purchaseId)
		warn(string.format("[Monetization] receipt %s not durable; will retry", purchaseId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	Telemetry.onboardingStep(player, Telemetry.OnboardingStep.FirstPurchase)
	Telemetry.funnelStep(player, Telemetry.OnboardingStep.FirstPurchase)
	Telemetry.custom(player, "PurchaseCompleted", receiptInfo.CurrencySpent, {
		product = configKey,
		robux = receiptInfo.CurrencySpent,
	})

	refresh(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function onPurchaseRequest(player: Player, kind: unknown, key: unknown)
	if type(kind) ~= "string" or type(key) ~= "string" then
		return
	end

	if not shopOpened[player] then
		shopOpened[player] = true
		Telemetry.onboardingStep(player, Telemetry.OnboardingStep.FirstShopOpen)
		Telemetry.funnelStep(player, Telemetry.OnboardingStep.FirstShopOpen)
	end

	if kind == "gamepass" then
		local id = Config.GamePasses[key]
		if not isConfigured(id) then
			warn(string.format("[Monetization] game pass %q is not configured (id 0)", key))
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, id)
	elseif kind == "product" then
		local id = Config.DeveloperProducts[key]
		if not isConfigured(id) then
			warn(string.format("[Monetization] product %q is not configured (id 0)", key))
			return
		end
		MarketplaceService:PromptProductPurchase(player, id)
	end
end

function MonetizationService.start()
	for key, id in Config.DeveloperProducts do
		if isConfigured(id) then
			productLookup[id] = key
		end
	end

	-- Must be assigned exactly once, on the server, for the whole game.
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then
			return
		end
		for passKey, configured in Config.GamePasses do
			if isConfigured(configured) and passId == configured then
				local owned = ownedPasses[player]
				if not owned then
					owned = {}
					ownedPasses[player] = owned
				end
				owned[passKey] = true
				Telemetry.custom(player, "GamePassPurchased", 1, { pass = passKey })
				Telemetry.onboardingStep(player, Telemetry.OnboardingStep.FirstPurchase)
				refresh(player)
				break
			end
		end
	end)

	local requestRemote = Remotes.get("RequestPurchase") :: RemoteEvent
	requestRemote.OnServerEvent:Connect(onPurchaseRequest)

	DataService.ProfileLoaded.Event:Connect(function(player)
		task.spawn(resolvePasses, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		shopOpened[player] = nil
		ownedPasses[player] = nil
	end)
end

return MonetizationService
