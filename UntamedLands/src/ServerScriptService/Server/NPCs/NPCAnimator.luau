--!nonstrict
--[[
	NPCAnimator
	Location : ServerScriptService/Server/NPCs/NPCAnimator (ModuleScript)
	Purpose  : Minimal locomotion animation for server-owned NPCs (idle / walk /
	           run). Animations played through a server-side Animator replicate
	           to every client automatically.
	           Attack swings are NOT played here: clients animate all attacks from
	           the AttackStarted remote, for players and NPCs alike.

	ANIMATION IDS: the defaults below are the IDs used by Roblox's built-in R15
	"Animate" script. If any fail to load (check Output for warnings), play-test,
	open your character's Animate script and copy the current idle/walk/run IDs,
	or replace them with your own animations from the Animation Editor.
	Depends  : nothing
]]

local NPCAnimator = {}
NPCAnimator.__index = NPCAnimator

NPCAnimator.AnimationIds = {
	Idle = "rbxassetid://507766666",
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
}

local WALK_REFERENCE_SPEED = 12
local RUN_REFERENCE_SPEED = 22

function NPCAnimator.new(humanoid)
	local self = setmetatable({}, NPCAnimator)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	self.tracks = {}
	for name, id in pairs(NPCAnimator.AnimationIds) do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = true
			track.Priority = if name == "Idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
			self.tracks[name] = track
		else
			warn("[NPCAnimator] Failed to load " .. name .. " animation: " .. tostring(track))
		end
	end
	self.current = nil
	return self
end

function NPCAnimator:update(horizontalSpeed)
	local want
	if horizontalSpeed < 0.5 then
		want = "Idle"
	elseif horizontalSpeed > 16 then
		want = "Run"
	else
		want = "Walk"
	end

	if want ~= self.current then
		local old = self.current and self.tracks[self.current]
		if old then
			old:Stop(0.2)
		end
		local new = self.tracks[want]
		if new then
			new:Play(0.2)
		end
		self.current = want
	end

	local track = self.tracks[want]
	if track then
		if want == "Walk" then
			track:AdjustSpeed(horizontalSpeed / WALK_REFERENCE_SPEED)
		elseif want == "Run" then
			track:AdjustSpeed(horizontalSpeed / RUN_REFERENCE_SPEED)
		end
	end
end

function NPCAnimator:stopAll()
	for _, track in pairs(self.tracks) do
		track:Stop(0.1)
	end
	self.current = nil
end

return NPCAnimator
