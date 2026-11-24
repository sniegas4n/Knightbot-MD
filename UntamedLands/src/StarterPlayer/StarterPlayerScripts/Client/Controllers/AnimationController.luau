--!nonstrict
--[[
	AnimationController
	Location : StarterPlayer/StarterPlayerScripts/Client/Controllers/AnimationController
	Purpose  : PROCEDURAL combat poses until real animations are authored.
	           Layers pose offsets onto three R15 joints (RightShoulder,
	           LeftShoulder, Waist) through keyframed timelines:
	           windup -> strike -> recover. Also holds Block and Stagger poses
	           driven by the replicated "CombatState" attribute.
	           Works for every tagged Combatant (players and NPCs). Changes are
	           purely local to each client - every client animates everyone from
	           the AttackStarted remote, so nothing here replicates.

	Joint types: Roblox's Avatar Joint Upgrade replaces R15 Motor6Ds with
	AnimationConstraints, whose C0 cannot be changed by scripts. This controller
	therefore writes each joint's Transform during RunService.PreSimulation
	(after the Animator has applied walk/idle animations), which works for BOTH
	Motor6D and AnimationConstraint rigs and stacks on top of normal animations.

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

-- Joint name -> the part that the joint MOVES (its child part).
local JOINT_PARTS = {
	RightShoulder = "RightUpperArm",
	LeftShoulder = "LeftUpperArm",
	Waist = "UpperTorso",
}
local JOINTS = { "RightShoulder", "LeftShoulder", "Waist" }
local NEUTRAL = {}
local MAX_DISTANCE = 220
local RETRY_INTERVAL = 0.5
local WARN_AFTER = 8

local rad = math.rad
local function angles(x, y, z)
	return CFrame.Angles(rad(x or 0), rad(y or 0), rad(z or 0))
end

-- Pose offsets are applied in each joint's parent space (equivalent to C0 * offset).
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
local candidates = {} -- [Model] = { nextTry, firstSeen, warned } (waiting for joints)

---------------------------------------------------------------------------
-- Joint discovery (Motor6D or AnimationConstraint)
---------------------------------------------------------------------------
local function isJoint(instance)
	return instance:IsA("Motor6D") or instance:IsA("AnimationConstraint")
end

local function childPartOf(joint)
	if joint:IsA("Motor6D") then
		return joint.Part1
	end
	local attachment = joint.Attachment1
	return attachment and attachment.Parent
end

local function findJoint(model, jointName)
	local part = model:FindFirstChild(JOINT_PARTS[jointName])
	if not part then
		return nil
	end
	local direct = part:FindFirstChild(jointName)
	if direct and isJoint(direct) then
		return direct
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if isJoint(descendant) and (descendant.Name == jointName or childPartOf(descendant) == part) then
			return descendant
		end
	end
	return nil
end

local function jointsValid(rig)
	for _, name in ipairs(JOINTS) do
		if not rig.joints[name].Parent then
			return false
		end
	end
	return true
end

local function restore(rig)
	for _, name in ipairs(JOINTS) do
		local joint = rig.joints[name]
		if joint.Parent and rig.animBase[name] then
			joint.Transform = rig.animBase[name]
		end
	end
end

local function getRig(model)
	local rig = rigs[model]
	if rig then
		if jointsValid(rig) then
			return rig
		end
		rigs[model] = nil
	end
	local joints = {}
	for _, name in ipairs(JOINTS) do
		local joint = findJoint(model, name)
		if not joint then
			return nil
		end
		joints[name] = joint
	end
	rig = { model = model, joints = joints, current = {}, animBase = {}, applied = {}, timeline = nil }
	for _, name in ipairs(JOINTS) do
		rig.current[name] = CFrame.identity
	end
	rigs[model] = rig
	candidates[model] = nil
	return rig
end

---------------------------------------------------------------------------
-- Poses
---------------------------------------------------------------------------
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

-- Writes offset on top of whatever the Animator produced this frame.
-- If the Animator did not touch the joint since our last write (no track
-- affects it), reuse the stored base so offsets never accumulate.
local function applyJoint(rig, name, offset)
	local joint = rig.joints[name]
	local current = joint.Transform
	local base
	local applied = rig.applied[name]
	if applied ~= nil and current == applied then
		base = rig.animBase[name] or CFrame.identity
	else
		base = current
	end
	rig.animBase[name] = base
	local final = offset * base
	joint.Transform = final
	rig.applied[name] = final
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
		applyJoint(rig, joint, rig.current[joint])
	end
end

---------------------------------------------------------------------------
-- Discovery & loop
---------------------------------------------------------------------------
local function onTagged(model)
	if model:IsA("Model") then
		candidates[model] = { nextTry = 0, firstSeen = os.clock(), warned = false }
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

-- Describes what a rig actually contains, so a warning tells us WHY it failed.
local function describeRig(model)
	local missing, counts = {}, {}
	for _, name in ipairs(JOINTS) do
		if not model:FindFirstChild(JOINT_PARTS[name]) then
			table.insert(missing, JOINT_PARTS[name])
		end
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("JointInstance") or descendant:IsA("Constraint") then
			counts[descendant.ClassName] = (counts[descendant.ClassName] or 0) + 1
		end
	end
	local parts = {}
	for className, n in pairs(counts) do
		table.insert(parts, className .. " x" .. n)
	end
	return ("missing parts: [%s]; joints present: [%s]"):format(table.concat(missing, ", "), table.concat(parts, ", "))
end

local function resolveCandidates(now)
	for model, info in pairs(candidates) do
		if not model.Parent then
			candidates[model] = nil
		elseif now >= info.nextTry then
			info.nextTry = now + RETRY_INTERVAL
			-- With StreamingEnabled the model can exist on this client before its
			-- body parts do (e.g. while you're in character creation). That is
			-- normal, so only start the warning timer once the parts have arrived.
			local streamedIn = model:FindFirstChild("UpperTorso")
				and model:FindFirstChild("RightUpperArm")
				and model:FindFirstChild("LeftUpperArm")
			if not streamedIn then
				info.firstSeen = now
			end
			if not getRig(model) and not info.warned and now - info.firstSeen > WARN_AFTER then
				info.warned = true
				warn(("[AnimationController] No R15 shoulder/waist joints found on %s; combat poses disabled for it. %s"):format(
					model:GetFullName(),
					describeRig(model)
				))
			end
		end
	end
end

function AnimationController.init()
	CollectionService:GetInstanceAddedSignal("Combatant"):Connect(onTagged)
	CollectionService:GetInstanceRemovedSignal("Combatant"):Connect(onUntagged)
	for _, model in ipairs(CollectionService:GetTagged("Combatant")) do
		onTagged(model)
	end

	-- PreSimulation runs after the Animator has written this frame's Transforms.
	RunService.PreSimulation:Connect(function(dt)
		resolveCandidates(os.clock())
		local cameraPosition = workspace.CurrentCamera.CFrame.Position
		for model, rig in pairs(rigs) do
			if not model.Parent or not jointsValid(rig) then
				rigs[model] = nil
				-- Parts streamed out but the model is still here: watch for them
				-- to stream back in, otherwise this NPC would never animate again.
				if model.Parent and CollectionService:HasTag(model, "Combatant") then
					onTagged(model)
				end
			else
				local ok, err = pcall(stepRig, model, rig, dt, cameraPosition)
				if not ok then
					warn("[AnimationController] " .. tostring(err))
					rigs[model] = nil
				end
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
