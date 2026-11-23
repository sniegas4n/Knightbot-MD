--!nonstrict
--[[
	CameraController
	Location : StarterPlayer/StarterPlayerScripts/Client/Controllers/CameraController
	Purpose  : Over-the-shoulder third-person camera.
	           - Mouse is locked to the centre; the character faces where you look
	             (so attacks and blocks go where you aim).
	           - Left Alt toggles a free cursor. Menus can also free the cursor
	             with setCursorFree(reason, true).
	           - Mouse wheel zoom, collision so the camera never clips into walls,
	             gamepad right-stick look, and a small hit-shake effect.
	           - Records recent mouse motion so CombatController can read the
	             direction of a swing.
	Depends  : nothing
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local CameraController = {}

local SETTINGS = {
	Sensitivity = 0.0035, -- radians per pixel at Roblox sensitivity 1
	GamepadSensitivity = 3.0, -- radians per second at full stick
	MinPitch = math.rad(-70),
	MaxPitch = math.rad(60),
	MinDistance = 4,
	MaxDistance = 18,
	DefaultDistance = 9,
	ShoulderOffset = Vector3.new(1.8, 0.6, 0),
	FocusHeight = 1.8,
	CollisionPadding = 0.6,
	MotionHistory = 0.35, -- seconds of mouse motion kept
}

local yaw, pitch = 0, math.rad(-12)
local targetDistance = SETTINGS.DefaultDistance
local distance = targetDistance
local enabled = false
local freeReasons = {}
local gamepadLook = Vector2.zero
local usingGamepad = false
local shakeUntil, shakeDuration, shakeIntensity = 0, 0, 0
local motionSamples = {}
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function userSensitivity()
	local ok, value = pcall(function()
		return UserSettings():GetService("UserGameSettings").MouseSensitivity
	end)
	return if ok and type(value) == "number" then value else 1
end

local function recordMotion(delta)
	local now = os.clock()
	if delta.Magnitude > 0 then
		table.insert(motionSamples, { time = now, delta = delta })
	end
	while motionSamples[1] and now - motionSamples[1].time > SETTINGS.MotionHistory do
		table.remove(motionSamples, 1)
	end
end

function CameraController.isCursorLocked()
	return enabled and next(freeReasons) == nil
end

function CameraController.setCursorFree(reason, free)
	freeReasons[reason] = if free then true else nil
end

function CameraController.setEnabled(value)
	enabled = value
	if not value then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	end
end

function CameraController.getYaw()
	return yaw
end

-- Sum of mouse movement over the last `window` seconds (pixels).
function CameraController.getRecentMotion(window)
	local now = os.clock()
	local sum = Vector2.zero
	for _, sample in ipairs(motionSamples) do
		if now - sample.time <= window then
			sum += sample.delta
		end
	end
	return sum
end

function CameraController.shake(intensity, duration)
	shakeIntensity = intensity
	shakeDuration = duration
	shakeUntil = os.clock() + duration
end

local function update(dt)
	if not enabled then
		return
	end
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable

	local locked = CameraController.isCursorLocked()
	if locked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		local delta = UserInputService:GetMouseDelta()
		local sensitivity = SETTINGS.Sensitivity * userSensitivity()
		yaw -= delta.X * sensitivity
		pitch -= delta.Y * sensitivity
		recordMotion(delta)
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		recordMotion(Vector2.zero)
	end

	if gamepadLook.Magnitude > 0.15 then
		yaw -= gamepadLook.X * SETTINGS.GamepadSensitivity * dt
		pitch += gamepadLook.Y * SETTINGS.GamepadSensitivity * dt
	end
	pitch = math.clamp(pitch, SETTINGS.MinPitch, SETTINGS.MaxPitch)
	distance += (targetDistance - distance) * math.min(1, dt * 10)

	local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local focus = root.Position + Vector3.new(0, SETTINGS.FocusHeight, 0)
	local desired = (CFrame.new(focus) * rotation * CFrame.new(SETTINGS.ShoulderOffset + Vector3.new(0, 0, distance))).Position
	local direction = desired - focus

	raycastParams.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(focus, direction, raycastParams)
	local position = desired
	if hit then
		position = focus + direction.Unit * math.max(0.5, hit.Distance - SETTINGS.CollisionPadding)
	end

	local cframe = CFrame.new(position) * rotation
	local now = os.clock()
	if now < shakeUntil and shakeDuration > 0 then
		local strength = shakeIntensity * ((shakeUntil - now) / shakeDuration)
		cframe *= CFrame.Angles((math.random() - 0.5) * strength, (math.random() - 0.5) * strength, 0)
	end
	camera.CFrame = cframe
	camera.Focus = CFrame.new(focus)

	-- Face the camera direction while aiming (mouse locked or gamepad).
	if humanoid.Health > 0 and (locked or usingGamepad) then
		humanoid.AutoRotate = false
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	else
		humanoid.AutoRotate = true
	end
end

function CameraController.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.Gamepad1 then
			usingGamepad = true
		elseif input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.MouseButton1 then
			usingGamepad = false
		end
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftAlt then
			CameraController.setCursorFree("Toggle", not freeReasons.Toggle)
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			targetDistance = math.clamp(targetDistance - input.Position.Z * 1.5, SETTINGS.MinDistance, SETTINGS.MaxDistance)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gamepadLook = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)

	RunService:BindToRenderStep("UntamedCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

function CameraController.onCharacterAdded(character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root then
		local _, currentYaw = root.CFrame:ToEulerAnglesYXZ()
		yaw = currentYaw
	end
	pitch = math.rad(-12)
	enabled = true
end

return CameraController
