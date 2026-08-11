--[[
	Audio — every sound in the game goes through here.

	Shared rather than server-only because the two kinds of sound want different
	homes: world events (a tower firing, an enemy dying) are positional and
	created server-side so they replicate, while interface sounds are flat and
	played locally so they are not delayed by a round trip.

	Two properties worth keeping:

	  1. An unset id is skipped silently. Sounds are wired into gameplay before
	     the ids exist, so the game is fully playable while Config.Sounds is
	     blank and gains audio the moment ids are filled in — no code change and
	     no risk of a half-wired audio pass.

	  2. Pitch is randomised within a per-sound range. A tower firing twice a
	     second at exactly one pitch becomes machine-gun tinnitus within about
	     ten seconds; small variation is the difference between texture and
	     irritation.
]]

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Audio = {}

local function definition(name: string)
	local def = Config.Sounds[name]
	if not def or def.id == "" then
		return nil
	end
	return def
end

local function configure(sound: Sound, def)
	sound.SoundId = def.id
	sound.Volume = def.volume or 0.5
	local range = def.pitchRange
	if range then
		sound.PlaybackSpeed = range[1] + math.random() * (range[2] - range[1])
	end
end

--[[
	Stops a sound early when the source clip is longer than the moment it marks.

	This matters more than it sounds. The library clips available are 1–4 seconds,
	while a Pea tower fires up to 1.2 times a second — so a 4-second sample would
	stack five copies deep and turn into noise. Trimming at playback keeps a long
	clip usable as a short effect without needing a differently-edited asset for
	every use.
]]
local function trim(sound: Sound, def)
	local limit = def.maxDuration
	if not limit then
		return
	end
	task.delay(limit, function()
		if sound and sound.Parent then
			sound:Stop()
		end
	end)
end

--[[ A positional sound at a world point. Server-side so it replicates. ]]
function Audio.playAt(name: string, position: Vector3, parent: Instance?)
	local def = definition(name)
	if not def then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = parent or workspace

	local sound = Instance.new("Sound")
	configure(sound, def)
	sound.RollOffMaxDistance = 220
	sound.Parent = anchor
	sound:Play()
	trim(sound, def)

	Debris:AddItem(anchor, 6)
end

--[[ A flat sound with no position — interface and stingers. Client-side. ]]
function Audio.play(name: string)
	local def = definition(name)
	if not def then
		return
	end

	local sound = Instance.new("Sound")
	configure(sound, def)
	sound.Parent = SoundService
	sound:Play()
	trim(sound, def)

	Debris:AddItem(sound, 8)
end

return Audio
