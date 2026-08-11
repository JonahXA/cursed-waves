--[[
	HUD — run status, tower shop, the curse prompt, and feedback.

	The curse prompt is deliberately the loudest thing on screen. It is the one
	decision that makes this game not a generic tower defense, and burying it in
	a corner would waste the entire differentiator.

	The HUD renders state it is given. It never computes cash, damage, payout or
	rot odds — the server owns those, and shipping the formulas here would let a
	hooked client disagree about what a wave is worth.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local HUD = {}
HUD.__index = HUD

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(props): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = props.size or UDim2.fromOffset(200, 40)
	l.Position = props.position or UDim2.fromOffset(0, 0)
	l.BackgroundColor3 = props.bg or Color3.fromRGB(22, 24, 30)
	l.BackgroundTransparency = props.transparency or 0.15
	l.BorderSizePixel = 0
	l.Text = props.text or ""
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = props.color or Color3.new(1, 1, 1)
	if props.bg == nil and props.transparency == nil then
		corner(l, 8)
	end
	return l
end

local function button(text: string, color: Color3, size: UDim2, position: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Text = text
	b.TextScaled = true
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	corner(b, 8)
	return b
end

function HUD.new()
	local self = setmetatable({}, HUD)
	self.selectedTower = nil
	self.selectedPlacedTower = nil
	self.toastCounter = 0

	local gui = Instance.new("ScreenGui")
	gui.Name = "CursedWavesHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	-- ---------- top-left: persistent ----------
	self.coins = label({
		text = "loading...",
		size = UDim2.fromOffset(200, 44),
		position = UDim2.fromOffset(16, 16),
		color = Color3.fromRGB(255, 214, 66),
	})
	self.coins.Parent = gui

	self.level = label({
		text = "",
		size = UDim2.fromOffset(200, 32),
		position = UDim2.fromOffset(16, 66),
		color = Color3.fromRGB(180, 210, 255),
	})
	self.level.Parent = gui

	-- ---------- top-centre: run status ----------
	self.waveLabel = label({
		text = "",
		size = UDim2.fromOffset(240, 44),
		position = UDim2.new(0.5, -120, 0, 16),
		color = Color3.fromRGB(255, 255, 255),
	})
	self.waveLabel.Parent = gui

	self.phaseLabel = label({
		text = "",
		size = UDim2.fromOffset(240, 30),
		position = UDim2.new(0.5, -120, 0, 66),
		color = Color3.fromRGB(200, 220, 255),
	})
	self.phaseLabel.Parent = gui

	self.healthLabel = label({
		text = "",
		size = UDim2.fromOffset(200, 40),
		position = UDim2.new(0.5, -100, 0, 104),
		color = Color3.fromRGB(255, 140, 140),
	})
	self.healthLabel.Parent = gui

	-- ---------- top-right: cash + curses ----------
	self.cash = label({
		text = "",
		size = UDim2.fromOffset(200, 44),
		position = UDim2.new(1, -216, 0, 16),
		color = Color3.fromRGB(140, 240, 160),
	})
	self.cash.Parent = gui

	self.curseLabel = label({
		text = "",
		size = UDim2.fromOffset(200, 34),
		position = UDim2.new(1, -216, 0, 66),
		color = Color3.fromRGB(220, 150, 255),
	})
	self.curseLabel.Parent = gui

	-- ---------- centre: start / skip ----------
	self.startButton = button(
		"START RUN",
		Color3.fromRGB(60, 150, 90),
		UDim2.fromOffset(260, 70),
		UDim2.new(0.5, -130, 0.5, -35)
	)
	self.startButton.Parent = gui

	self.skipButton = button(
		"START WAVE",
		Color3.fromRGB(200, 140, 40),
		UDim2.fromOffset(200, 46),
		UDim2.new(0.5, -100, 0, 152)
	)
	self.skipButton.Visible = false
	self.skipButton.Parent = gui

	-- ---------- bottom: tower bar ----------
	local bar = Instance.new("Frame")
	bar.Name = "TowerBar"
	bar.Size = UDim2.fromOffset(560, 84)
	bar.Position = UDim2.new(0.5, -280, 1, -100)
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	self.towerBar = bar

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = bar

	self.towerButtons = {}
	for _, towerType in Config.TowerOrder do
		local def = Config.Towers[towerType]
		local b = button(
			string.format("%s\n%d", def.displayName, def.cost),
			def.color,
			UDim2.fromOffset(126, 80),
			UDim2.fromOffset(0, 0)
		)
		b.Parent = bar
		self.towerButtons[towerType] = b
	end

	-- ---------- selected placed tower ----------
	local towerPanel = Instance.new("Frame")
	towerPanel.Name = "TowerPanel"
	towerPanel.Size = UDim2.fromOffset(220, 110)
	towerPanel.Position = UDim2.new(1, -236, 1, -230)
	towerPanel.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
	towerPanel.BackgroundTransparency = 0.1
	towerPanel.BorderSizePixel = 0
	towerPanel.Visible = false
	corner(towerPanel, 10)
	towerPanel.Parent = gui
	self.towerPanel = towerPanel

	self.upgradeButton = button(
		"Upgrade",
		Color3.fromRGB(70, 130, 200),
		UDim2.new(1, -20, 0, 40),
		UDim2.fromOffset(10, 10)
	)
	self.upgradeButton.Parent = towerPanel

	self.sellButton = button(
		"Sell",
		Color3.fromRGB(150, 70, 70),
		UDim2.new(1, -20, 0, 40),
		UDim2.fromOffset(10, 58)
	)
	self.sellButton.Parent = towerPanel

	-- ---------- the hook: curse prompt ----------
	local cursePanel = Instance.new("Frame")
	cursePanel.Name = "CursePrompt"
	cursePanel.Size = UDim2.fromOffset(520, 260)
	cursePanel.Position = UDim2.new(0.5, -260, 0.5, -130)
	cursePanel.BackgroundColor3 = Color3.fromRGB(28, 18, 34)
	cursePanel.BackgroundTransparency = 0.05
	cursePanel.BorderSizePixel = 0
	cursePanel.Visible = false
	corner(cursePanel, 14)
	cursePanel.Parent = gui
	self.cursePanel = cursePanel

	local title = label({
		text = "PUSH YOUR LUCK?",
		size = UDim2.new(1, -20, 0, 44),
		position = UDim2.fromOffset(10, 12),
		bg = Color3.fromRGB(0, 0, 0),
		transparency = 1,
		color = Color3.fromRGB(230, 170, 255),
	})
	title.Parent = cursePanel

	self.curseTimer = label({
		text = "",
		size = UDim2.new(1, -20, 0, 24),
		position = UDim2.fromOffset(10, 58),
		bg = Color3.fromRGB(0, 0, 0),
		transparency = 1,
		color = Color3.fromRGB(180, 180, 200),
	})
	self.curseTimer.Parent = cursePanel

	self.curseButtons = {}
	for i = 1, 2 do
		local b = button(
			"",
			Color3.fromRGB(120, 60, 150),
			UDim2.new(0.5, -18, 0, 86),
			UDim2.fromOffset(12 + (i - 1) * (260 - 6), 90)
		)
		b.Parent = cursePanel
		self.curseButtons[i] = b
	end

	self.bankButton = button(
		"BANK IT — play it safe",
		Color3.fromRGB(60, 140, 90),
		UDim2.new(1, -24, 0, 48),
		UDim2.fromOffset(12, 190)
	)
	self.bankButton.Parent = cursePanel

	-- ---------- shop ----------
	self.shopToggle = button(
		"SHOP",
		Color3.fromRGB(58, 92, 190),
		UDim2.fromOffset(110, 40),
		UDim2.new(1, -126, 0, 110)
	)
	self.shopToggle.Parent = gui

	local shop = Instance.new("Frame")
	shop.Name = "Shop"
	shop.Size = UDim2.fromOffset(300, 320)
	shop.Position = UDim2.new(1, -316, 0, 158)
	shop.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
	shop.BackgroundTransparency = 0.08
	shop.BorderSizePixel = 0
	shop.Visible = false
	corner(shop, 12)
	shop.Parent = gui
	self.shop = shop

	self.passStarterCash = button(
		"Starter Cash",
		Color3.fromRGB(150, 90, 60),
		UDim2.new(1, -20, 0, 42),
		UDim2.fromOffset(10, 12)
	)
	self.passStarterCash.Parent = shop
	self.passLuckyCurse = button(
		"Lucky Curse",
		Color3.fromRGB(150, 90, 60),
		UDim2.new(1, -20, 0, 42),
		UDim2.fromOffset(10, 62)
	)
	self.passLuckyCurse.Parent = shop
	self.passSecondChance = button(
		"Second Chance",
		Color3.fromRGB(150, 90, 60),
		UDim2.new(1, -20, 0, 42),
		UDim2.fromOffset(10, 112)
	)
	self.passSecondChance.Parent = shop
	self.buyCoins = button(
		"Coin Pack",
		Color3.fromRGB(58, 92, 190),
		UDim2.new(1, -20, 0, 42),
		UDim2.fromOffset(10, 174)
	)
	self.buyCoins.Parent = shop
	self.buyInstantWave = button(
		"Instant Wave",
		Color3.fromRGB(58, 92, 190),
		UDim2.new(1, -20, 0, 42),
		UDim2.fromOffset(10, 224)
	)
	self.buyInstantWave.Parent = shop
	self.buyRevive = button(
		"Revive",
		Color3.fromRGB(58, 92, 190),
		UDim2.new(1, -20, 0, 42),
		UDim2.fromOffset(10, 274)
	)
	self.buyRevive.Parent = shop

	self.shopToggle.Activated:Connect(function()
		shop.Visible = not shop.Visible
	end)

	--[[
		Onboarding hint.

		A single contextual line rather than a tutorial sequence. New players do
		not read modals, and a game that opens with a wall of instructions loses
		them before the first action. This says exactly one thing, always the
		next thing, and disappears once they clearly know what they are doing.

		Time-to-first-action is the pattern every breakout game on the platform
		shares, and this is what protects it.
	]]
	self.hint = Instance.new("TextLabel")
	self.hint.Name = "Hint"
	self.hint.Size = UDim2.fromOffset(620, 46)
	self.hint.Position = UDim2.new(0.5, -310, 1, -170)
	self.hint.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	self.hint.BackgroundTransparency = 0.15
	self.hint.BorderSizePixel = 0
	self.hint.Text = ""
	self.hint.TextScaled = true
	self.hint.Font = Enum.Font.GothamBold
	self.hint.TextColor3 = Color3.fromRGB(255, 226, 150)
	self.hint.Visible = false
	corner(self.hint, 10)
	self.hint.Parent = gui

	-- ---------- toasts ----------
	local toasts = Instance.new("Frame")
	toasts.Name = "Toasts"
	toasts.Size = UDim2.fromOffset(320, 200)
	toasts.Position = UDim2.new(0, 16, 1, -320)
	toasts.BackgroundTransparency = 1
	toasts.Parent = gui

	local tl = Instance.new("UIListLayout")
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	tl.Padding = UDim.new(0, 4)
	tl.Parent = toasts
	self.toasts = toasts

	return self
end

function HUD:toast(text: string, color: Color3)
	self.toastCounter += 1
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 32)
	l.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
	l.BackgroundTransparency = 0.2
	l.BorderSizePixel = 0
	l.Text = text
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color
	l.LayoutOrder = self.toastCounter
	corner(l, 6)
	l.Parent = self.toasts
	task.delay(4, function()
		if l.Parent then
			l:Destroy()
		end
	end)
end

function HUD:render(state)
	if not state then
		self.coins.Text = "loading..."
		return
	end
	self.state = state

	self.coins.Text = string.format("%d coins", state.coins)
	self.level.Text = string.format("Level %d", state.level)

	local inRun = state.inRun
	self.startButton.Visible = not inRun
	self.towerBar.Visible = inRun
	self.waveLabel.Visible = inRun
	self.phaseLabel.Visible = inRun
	self.healthLabel.Visible = inRun
	self.cash.Visible = inRun
	self.curseLabel.Visible = inRun

	if not inRun then
		self.skipButton.Visible = false
		self.cursePanel.Visible = false
		self.towerPanel.Visible = false
		self.hint.Visible = state.level <= 1 and (state.coins or 0) == 0
		self.hint.Text = "Press START RUN to defend your base"
		return
	end

	--[[
		One hint, always the next thing, and it stops once the player has clearly
		understood. Hints keyed off actual state rather than a step counter, so
		a player who works something out early is never told to do it.
	]]
	local hint = nil
	if state.phase == "build" and #state.towers == 0 then
		hint = "Pick a tower below, then click the grass to place it"
	elseif state.phase == "build" and state.wave == 0 then
		hint = "Place more, or press START WAVE when you're ready"
	elseif state.phase == "wave" and state.wave <= 1 then
		hint = "Towers fire on their own — don't let anything reach the base"
	elseif state.phase == "choosing" and #state.curses == 0 then
		hint = "Take a curse for a bigger payout, or bank it and stay safe"
	end
	self.hint.Visible = hint ~= nil
	if hint then
		self.hint.Text = hint
	end

	self.waveLabel.Text = string.format("Wave %d", state.wave)
	self.healthLabel.Text = string.format("Base  %d / %d", state.baseHealth, state.maxBaseHealth)
	self.cash.Text = string.format("$%d", state.cash)

	if state.payoutMultiplier > 1 then
		self.curseLabel.Text =
			string.format("%d curses  ·  x%.1f", #state.curses, state.payoutMultiplier)
	else
		self.curseLabel.Text = "no curses"
	end

	local remaining = math.max(0, math.floor(state.phaseEndsAt - os.clock()))
	if state.phase == "build" then
		self.phaseLabel.Text = string.format("Build  %ds", remaining)
		self.skipButton.Visible = true
	elseif state.phase == "wave" then
		self.phaseLabel.Text = "Wave incoming"
		self.skipButton.Visible = false
	else
		self.phaseLabel.Text = ""
		self.skipButton.Visible = false
	end

	-- Tower buttons reflect unlocks and affordability, but the server checks
	-- both again — hiding a button is not a permission check.
	for towerType, b in self.towerButtons do
		local def = Config.Towers[towerType]
		local unlocked = false
		for _, id in state.unlockedTowers do
			if id == towerType then
				unlocked = true
				break
			end
		end
		b.Visible = unlocked
		local affordable = state.cash >= def.cost
		b.BackgroundTransparency = if affordable then 0 else 0.6
		b.Text = string.format(
			"%s\n%d%s",
			def.displayName,
			def.cost,
			if self.selectedTower == towerType then "  ✓" else ""
		)
	end

	-- The curse prompt.
	if state.phase == "choosing" and #state.curseOffers > 0 then
		self.cursePanel.Visible = true
		self.curseTimer.Text = string.format("banking automatically in %ds", remaining)
		for i, b in self.curseButtons do
			local offer = state.curseOffers[i]
			if offer then
				b.Visible = true
				b.Text = string.format(
					"%s\n%s\n\nx%.1f payout",
					offer.displayName,
					offer.description,
					offer.payout
				)
				b:SetAttribute("CurseId", offer.id)
			else
				b.Visible = false
			end
		end
	else
		self.cursePanel.Visible = false
	end

	-- Selected placed tower.
	local selected = nil
	if self.selectedPlacedTower then
		for _, view in state.towers do
			if view.id == self.selectedPlacedTower then
				selected = view
				break
			end
		end
	end
	if selected then
		self.towerPanel.Visible = true
		self.upgradeButton.Text = if selected.upgradeCost
			then string.format("Upgrade  $%d", selected.upgradeCost)
			else "Max tier"
		self.upgradeButton.BackgroundTransparency = if selected.upgradeCost then 0 else 0.6
		self.sellButton.Text = string.format("Sell  +$%d", selected.sellValue)
	else
		self.towerPanel.Visible = false
		self.selectedPlacedTower = nil
	end

	local passes = state.passes or {}
	self.passStarterCash.Text = passes.starterCash and "Starter Cash ✓" or "Starter Cash"
	self.passLuckyCurse.Text = passes.luckyCurse and "Lucky Curse ✓" or "Lucky Curse"
	self.passSecondChance.Text = passes.secondChance and "Second Chance ✓" or "Second Chance"
end

return HUD
