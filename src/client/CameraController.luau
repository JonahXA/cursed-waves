--[[
	CameraController — a fixed strategic camera over the player's arena.

	This is the single biggest change to how the game reads. Default Roblox
	third-person puts you behind an avatar on a green plane, which is the visual
	language of an unfinished baseplate. Every tower defense on the platform uses
	an elevated angled view, and adopting it changes "someone's test place" into
	"a game" before a single asset is added.

	It also fixes a real usability problem: placing towers accurately is
	impossible while the camera bobs behind a walking character.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CameraController = {}

local player = Players.LocalPlayer

local DEFAULT_HEIGHT = 130
local DEFAULT_BACK = 110
local MIN_ZOOM, MAX_ZOOM = 0.55, 1.8
local PAN_SPEED = 90

local zoom = 1
local panOffset = Vector3.zero
local origin: Vector3? = nil

--[[
	Finds this player's arena so the camera frames the right one.

	Maps are offset per player, so a camera hard-coded to the world origin would
	show the first player's arena to everyone else.
]]
local function findOrigin(): Vector3?
	local maps = Workspace:FindFirstChild("Maps")
	local mine = maps and maps:FindFirstChild(player.Name)
	if not mine then
		return nil
	end
	local ground = mine:FindFirstChild("Ground")
	return ground and (ground :: BasePart).Position or nil
end

local function apply(camera: Camera)
	if not origin then
		return
	end
	local focus = origin + panOffset
	local position = focus + Vector3.new(0, DEFAULT_HEIGHT * zoom, DEFAULT_BACK * zoom)
	camera.CFrame = CFrame.lookAt(position, focus)
end

function CameraController.start()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 55

	-- The character is irrelevant to a strategic view, and leaving it walking
	-- around invites players to try to move with WASD and find the camera
	-- ignoring them.
	local function hideCharacter(character: Model)
		task.wait(0.1)
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency = 1
				part.CanCollide = false
			elseif part:IsA("Decal") then
				part.Transparency = 1
			end
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end

	if player.Character then
		task.spawn(hideCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(hideCharacter, character)
	end)

	-- Mouse wheel zooms.
	UserInputService.InputChanged:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		zoom = math.clamp(zoom - input.Position.Z * 0.1, MIN_ZOOM, MAX_ZOOM)
	end)

	RunService.RenderStepped:Connect(function(dt)
		if not origin then
			origin = findOrigin()
			if not origin then
				return
			end
		end

		-- WASD pans the view rather than moving a character.
		local move = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			move += Vector3.new(0, 0, -1)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			move += Vector3.new(0, 0, 1)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			move += Vector3.new(-1, 0, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			move += Vector3.new(1, 0, 0)
		end
		if move.Magnitude > 0 then
			panOffset += move.Unit * PAN_SPEED * dt
			-- Clamped so a player cannot pan away and lose their own arena.
			panOffset =
				Vector3.new(math.clamp(panOffset.X, -70, 70), 0, math.clamp(panOffset.Z, -70, 70))
		end

		apply(Workspace.CurrentCamera)
	end)
end

--[[ A brief kick, used when the base takes a hit. ]]
function CameraController.shake(intensity: number)
	task.spawn(function()
		local remaining = 0.25
		while remaining > 0 do
			local dt = task.wait()
			remaining -= dt
			panOffset += Vector3.new(
				(math.random() - 0.5) * intensity,
				0,
				(math.random() - 0.5) * intensity
			)
		end
	end)
end

return CameraController
