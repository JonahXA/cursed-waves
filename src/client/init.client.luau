--[[
	Client bootstrap — HUD wiring and placement input.

	Responsibilities, and nothing beyond them: build the HUD, render what the
	server pushes, and forward intent. It does not track cash, decide whether a
	tower is affordable, or resolve a wave. Every one of those is a server answer.

	Placement is the only place the client supplies a number — a world position
	from a raycast — and the server validates it against the build grid before
	spending anything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Audio = require(ReplicatedStorage.Shared.Audio)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CameraController = require(script.CameraController)
local HUD = require(script.HUD)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Before the HUD. A strategic camera is the single biggest reason this reads as
-- a game rather than a baseplate, and it also makes accurate tower placement
-- possible at all.
CameraController.start()

local startRun = Remotes.get("StartRun") :: RemoteEvent
local placeTower = Remotes.get("PlaceTower") :: RemoteEvent
local upgradeTower = Remotes.get("UpgradeTower") :: RemoteEvent
local sellTower = Remotes.get("SellTower") :: RemoteEvent
local skipBuild = Remotes.get("SkipBuildPhase") :: RemoteEvent
local chooseCurse = Remotes.get("ChooseCurse") :: RemoteEvent
local requestPurchase = Remotes.get("RequestPurchase") :: RemoteEvent
local stateRemote = Remotes.get("StateChanged") :: RemoteEvent
local runEventRemote = Remotes.get("RunEvent") :: RemoteEvent
local getState = Remotes.get("GetState") :: RemoteFunction

local hud = HUD.new()
hud:render(nil)

stateRemote.OnClientEvent:Connect(function(state)
	hud:render(state)
end)

-- ============================================================
-- Feedback
-- ============================================================

local WHITE = Color3.fromRGB(240, 240, 240)
local GREEN = Color3.fromRGB(150, 240, 160)
local RED = Color3.fromRGB(255, 120, 120)
local PURPLE = Color3.fromRGB(220, 150, 255)
local GOLD = Color3.fromRGB(255, 214, 66)

runEventRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind == "waveStarted" then
		hud:toast(string.format("Wave %d incoming", payload.wave), WHITE)
		Audio.play("waveStart")
	elseif payload.kind == "waveCleared" then
		hud:toast(string.format("Wave %d cleared  +$%d", payload.wave, payload.bonus), GREEN)
		Audio.play("waveCleared")
	elseif payload.kind == "leak" then
		hud:toast(string.format("Leak! -%d base", payload.damage), RED)
		CameraController.shake(math.min(payload.damage, 6))
		Audio.play("leak")
	elseif payload.kind == "curseTaken" then
		hud:toast(string.format("%s accepted", payload.displayName), PURPLE)
		Audio.play("curseTaken")
	elseif payload.kind == "revived" then
		hud:toast("Second Chance saved your base", GOLD)
	elseif payload.kind == "levelUp" then
		hud:toast(string.format("Level %d!", payload.level), GOLD)
		Audio.play("levelUp")
	elseif payload.kind == "runEnded" then
		local verb = if payload.reason == "victory" then "Victory" else "Defeated"
		hud:toast(
			string.format("%s on wave %d  ·  +%d coins", verb, payload.wave, payload.coins),
			if payload.reason == "victory" then GOLD else RED
		)
		Audio.play(if payload.reason == "victory" then "victory" else "defeat")
	end
end)

-- ============================================================
-- Buttons
-- ============================================================

hud.startButton.Activated:Connect(function()
	startRun:FireServer()
end)

hud.skipButton.Activated:Connect(function()
	skipBuild:FireServer()
end)

for towerType, b in hud.towerButtons do
	b.Activated:Connect(function()
		-- Toggle: clicking the selected tower again cancels placement mode.
		hud.selectedTower = if hud.selectedTower == towerType then nil else towerType
		hud.selectedPlacedTower = nil
		hud:render(hud.state)
	end)
end

hud.upgradeButton.Activated:Connect(function()
	if hud.selectedPlacedTower then
		upgradeTower:FireServer(hud.selectedPlacedTower)
	end
end)

hud.sellButton.Activated:Connect(function()
	if hud.selectedPlacedTower then
		sellTower:FireServer(hud.selectedPlacedTower)
		hud.selectedPlacedTower = nil
	end
end)

for _, b in hud.curseButtons do
	b.Activated:Connect(function()
		local id = b:GetAttribute("CurseId")
		if id then
			chooseCurse:FireServer(id)
		end
	end)
end

hud.bankButton.Activated:Connect(function()
	chooseCurse:FireServer(nil)
	Audio.play("bank")
end)

hud.passStarterCash.Activated:Connect(function()
	requestPurchase:FireServer("gamepass", "StarterCash")
end)
hud.passLuckyCurse.Activated:Connect(function()
	requestPurchase:FireServer("gamepass", "LuckyCurse")
end)
hud.passSecondChance.Activated:Connect(function()
	requestPurchase:FireServer("gamepass", "SecondChance")
end)
hud.buyCoins.Activated:Connect(function()
	requestPurchase:FireServer("product", "CoinsSmall")
end)
hud.buyInstantWave.Activated:Connect(function()
	requestPurchase:FireServer("product", "InstantWave")
end)
hud.buyRevive.Activated:Connect(function()
	requestPurchase:FireServer("product", "ReviveNow")
end)

-- ============================================================
-- World click — place a tower, or select a placed one
-- ============================================================

local function worldRaycast(screenPosition: Vector2)
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = player.Character
	params.FilterDescendantsInstances = if character then { character } else {}
	return Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
end

--[[
	Walks up from a hit part to find the tower model it belongs to.

	Tower models are named with their server-side id, so the model name IS the
	handle the server expects — no lookup table to drift out of sync.
]]
local function towerIdFromHit(instance: Instance?): string?
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") and current.Parent and current.Parent.Name == "Towers" then
			return current.Name
		end
		current = current.Parent
	end
	return nil
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return -- click landed on the HUD, not the world
	end
	if
		input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch
	then
		return
	end

	local result = worldRaycast(Vector2.new(input.Position.X, input.Position.Y))
	if not result then
		return
	end

	local towerId = towerIdFromHit(result.Instance)
	if towerId then
		hud.selectedPlacedTower = towerId
		hud.selectedTower = nil
		hud:render(hud.state)
		return
	end

	if hud.selectedTower then
		placeTower:FireServer(hud.selectedTower, result.Position + Vector3.new(0, 0.5, 0))
	else
		hud.selectedPlacedTower = nil
		hud:render(hud.state)
	end
end)

-- Timers count down locally off server-provided deadlines, so the display stays
-- smooth without a remote firing every frame.
task.spawn(function()
	while true do
		task.wait(0.25)
		if hud.state then
			hud:render(hud.state)
		end
	end
end)

task.spawn(function()
	local ok, state = pcall(function()
		return getState:InvokeServer()
	end)
	if ok then
		hud:render(state)
	else
		warn("[CursedWaves] initial state fetch failed: " .. tostring(state))
	end
end)
