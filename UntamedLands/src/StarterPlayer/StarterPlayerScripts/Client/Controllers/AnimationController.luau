--!nonstrict
--[[
	AnimationController
	Location : StarterPlayer/StarterPlayerScripts/Client/Controllers/AnimationController
	Purpose  : PROCEDURAL combat poses until real animations are authored.
	           Offsets the C0 of three R15 joints (RightShoulder, LeftShoulder,
	           Waist) through keyframed timelines: windup -> strike -> recover.
	           Also holds Block and Stagger poses driven by the replicated
	           "CombatState" attribute.
	           Works for every tagged Combatant (players and NPCs). Changes are
	           purely local to each client - every client animates everyone from
	           the AttackStarted remote, so nothing here replicates.

	Replacing with authored animations (Milestone 7): add animation IDs to the
	weapon definitions and play AnimationTracks in playAttack instead of building
	a timeline. The public API stays the same.
	Depends  : nothing
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local AnimationController = {}

local JOINTS = { "RightShoulder", "LeftShoulder", "Waist" }
local NEUTRAL = {}
local MAX_DISTANCE = 220

local rad = math.rad
local function angles(x, y, z)
	return CFrame.Angles(rad(x or 0), rad(y or 0), rad(z or 0))
end

-- Pose offsets are applied in each joint's C0 space.
-- RightShoulder: +X raises the arm forward, Y swings it sideways.
-- Waist: +Y twists the torso to the left, -X leans forward.
local POSES = {
	Attacks = {
		Overhead = {
			windup = { RightShoulder = angles(165, 0, 0), Waist = angles(8, 0, 0) },
			strike = { RightShoulder = angles(15, 0, 0), Waist = angles(-12, 0, 0) },
		},
		Right = {
			windup = { RightShoulder = angles(0, -80, 0) * angles(75, 0, 0), Waist = angles(0, -30, 0) },
			strike = { RightShoulder = angles(0, 55, 0) * angles(75, 0, 0), Waist = angles(0, 28, 0) },
		},
		Left = {
			windup = { RightShoulder = angles(0, 60, 0) * angles(80, 0, 0), Waist = angles(0, 28, 0) },
			strike = { RightShoulder = angles(0, -70, 0) * angles(70, 0, 0), Waist = angles(0, -26, 0) },
		},
		Thrust = {
			windup = { RightShoulder = CFrame.new(0, 0, 0.5) * angles(30, 0, 0), Waist = angles(0, -18, 0) },
			strike = { RightShoulder = CFrame.new(0, 0.2, -1.1) * angles(25, 0, 0), Waist = angles(-8, 14, 0) },
		},
	},
	Block = {
		RightShoulder = angles(0, 40, 0) * angles(75, 0, 0),
		LeftShoulder = angles(0, -20, 0) * angles(80, 0, 0),
		Waist = angles(-4, 0, 0),
	},
	Stagger = {
		RightShoulder = angles(30, 0, 20),
		LeftShoulder = angles(30, 0, -20),
		Waist = angles(16, 0, 0),
	},
}

local rigs = {} -- [Model] = rig
local candidates = {} -- [Model] = true (tagged, waiting for joints to stream in)

local function getMotor(model, partName, motorName)
	local part = model:FindFirstChild(partName)
	local motor = part and part:FindFirstChild(motorName)
	if motor and motor:IsA("Motor6D") then
		return motor
	end
	return nil
end

local function restore(rig)
	for name, motor in pairs(rig.motors) do
		if motor.Parent then
			motor.C0 = rig.base[name]
		end
	end
end

local function getRig(model)
	local rig = rigs[model]
	if rig then
		if rig.motors.RightShoulder.Parent and rig.motors.Waist.Parent then
			return rig
		end
		rigs[model] = nil
	end
	local motors = {
		RightShoulder = getMotor(model, "RightUpperArm", "RightShoulder"),
		LeftShoulder = getMotor(model, "LeftUpperArm", "LeftShoulder"),
		Waist = getMotor(model, "UpperTorso", "Waist"),
	}
	if not (motors.RightShoulder and motors.LeftShoulder and motors.Waist) then
		return nil
	end
	rig = { model = model, motors = motors, base = {}, current = {}, timeline = nil }
	for _, name in ipairs(JOINTS) do
		rig.base[name] = motors[name].C0
		rig.current[name] = CFrame.identity
	end
	rigs[model] = rig
	candidates[model] = nil
	return rig
end

local function poseValue(pose, joint)
	return pose[joint] or CFrame.identity
end

local function smooth(t)
	return t * t * (3 - 2 * t)
end

-- Scales a pose offset's rotation and translation (factor > 1 exaggerates it).
local function exaggerate(cframe, factor)
	local axis, angle = cframe:ToAxisAngle()
	local rotation = if math.abs(angle) > 1e-4 then CFrame.fromAxisAngle(axis, angle * factor) else CFrame.identity
	return CFrame.new(cframe.Position * factor) * rotation
end

function AnimationController.playAttack(model, kind, direction, windup, recovery)
	if typeof(model) ~= "Instance" then
		return
	end
	local rig = getRig(model)
	if not rig then
		return
	end
	local set = POSES.Attacks[direction] or POSES.Attacks.Right
	local strikeTime = math.min(0.14, recovery * 0.4)
	local snapshot = table.clone(rig.current)
	local windupPose = set.windup
	if kind == "Heavy" then
		-- Heavier wind-up: exaggerate the windup pose a little.
		windupPose = {}
		for _, joint in ipairs(JOINTS) do
			windupPose[joint] = exaggerate(poseValue(set.windup, joint), 1.15)
		end
	end
	rig.timeline = {
		start = os.clock(),
		keys = {
			{ t = 0, pose = snapshot },
			{ t = windup * 0.85, pose = windupPose },
			{ t = windup, pose = windupPose },
			{ t = windup + strikeTime, pose = set.strike },
			{ t = windup + recovery, pose = NEUTRAL },
		},
	}
end

local function stepRig(model, rig, dt, cameraPosition)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and (root.Position - cameraPosition).Magnitude > MAX_DISTANCE then
		return
	end
	local state = model:GetAttribute("CombatState")
	if state == "Staggered" or state == "Dead" then
		rig.timeline = nil
	end

	local timeline = rig.timeline
	if timeline then
		local t = os.clock() - timeline.start
		local keys = timeline.keys
		if t >= keys[#keys].t then
			rig.timeline = nil
		else
			for i = 1, #keys - 1 do
				local a, b = keys[i], keys[i + 1]
				if t >= a.t and t < b.t then
					local span = b.t - a.t
					local alpha = if span > 0 then smooth((t - a.t) / span) else 1
					for _, joint in ipairs(JOINTS) do
						rig.current[joint] = poseValue(a.pose, joint):Lerp(poseValue(b.pose, joint), alpha)
					end
					break
				end
			end
		end
	end

	if not rig.timeline then
		local target = NEUTRAL
		if state == "Blocking" then
			target = POSES.Block
		elseif state == "Staggered" then
			target = POSES.Stagger
		end
		local alpha = math.min(1, dt * 14)
		for _, joint in ipairs(JOINTS) do
			rig.current[joint] = rig.current[joint]:Lerp(poseValue(target, joint), alpha)
		end
	end

	for _, joint in ipairs(JOINTS) do
		rig.motors[joint].C0 = rig.base[joint] * rig.current[joint]
	end
end

local function onTagged(model)
	if model:IsA("Model") then
		candidates[model] = true
	end
end

local function onUntagged(model)
	candidates[model] = nil
	local rig = rigs[model]
	if rig then
		restore(rig)
		rigs[model] = nil
	end
end

function AnimationController.init()
	CollectionService:GetInstanceAddedSignal("Combatant"):Connect(onTagged)
	CollectionService:GetInstanceRemovedSignal("Combatant"):Connect(onUntagged)
	for _, model in ipairs(CollectionService:GetTagged("Combatant")) do
		onTagged(model)
	end

	RunService.RenderStepped:Connect(function(dt)
		for model in pairs(candidates) do
			if not model.Parent then
				candidates[model] = nil
			else
				getRig(model)
			end
		end
		local cameraPosition = workspace.CurrentCamera.CFrame.Position
		for model, rig in pairs(rigs) do
			if not model.Parent or not rig.motors.RightShoulder.Parent or not rig.motors.Waist.Parent then
				rigs[model] = nil
			else
				stepRig(model, rig, dt, cameraPosition)
			end
		end
	end)
end

-- Exposed so the local player's own swing can be predicted instantly.
function AnimationController.playLocalAttack(kind, direction, windup, recovery)
	if player.Character then
		AnimationController.playAttack(player.Character, kind, direction, windup, recovery)
	end
end

return AnimationController
