--[[
	MovementController (ModuleScript) — CLIENT
	Emplacement : StarterPlayer > StarterPlayerScripts > Controllers > MovementController

	Sprint :
	  - clavier : maintenir Shift ; manette : clic L3 (bascule) ;
	    tactile : bouton "Sprint" (bascule).
	  - Le client DEMANDE, le serveur décide (attribut Player.IsSprinting).

	Esquive :
	  - Q / bouton B / bouton tactile "Esquive".
	  - Pré-vérification locale (cooldown, endurance, au sol) pour éviter
	    des requêtes inutiles, puis dash immédiat (LinearVelocity en mode
	    Plane : la gravité continue d'agir) et requête au serveur, qui
	    valide et accorde les frames d'invulnérabilité.
	  - Sans direction de déplacement : pas en arrière.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)
local Maid = require(Shared.Modules.Maid)

local SprintConfig = Config.Movement.Sprint
local DodgeConfig = Config.Movement.Dodge
local AnimationConfig = Config.Animations

local player = Players.LocalPlayer

local MovementController = {
	Dodged = Signal.new(), -- (cooldown)
	DodgeRefused = Signal.new(), -- (reason) "Stamina" | "Cooldown" | "Air" | "Stunned"
}

local CameraController
local InputController
local SprintRemote
local DodgeRemote

local lastDodgeTime = -math.huge
local characterMaid = Maid.new()
local animationTracks: { [string]: AnimationTrack } = {}

local function getCharacterParts(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function isServerSprinting(): boolean
	return player:GetAttribute("IsSprinting") == true
end

-- ── Sprint ────────────────────────────────────────────────────────────────

-- true entre l'envoi d'une demande de sprint et l'arrêt du sprint. On ne
-- peut pas se fier au seul attribut IsSprinting : il n'arrive qu'après un
-- aller-retour réseau. Sans ce drapeau, un appui bref sur Shift (relâché
-- avant la réponse du serveur) laissait le sprint actif indéfiniment.
local sprintRequested = false

local function isSprintActive(): boolean
	return sprintRequested or isServerSprinting()
end

local function requestSprint(active: boolean)
	if active then
		if isSprintActive() then
			return
		end
		if (player:GetAttribute("Stamina") or 0) < SprintConfig.MinStaminaToStart then
			return
		end
		sprintRequested = true
		SprintRemote:FireServer(true)
	else
		if not isSprintActive() then
			return
		end
		sprintRequested = false
		SprintRemote:FireServer(false)
	end
end

local function onSprintInput(isPressed: boolean, _inputObject: InputObject, mode: string)
	if mode == "Toggle" then
		-- En bascule, il n'y a pas de relâchement à rater : on se fie à
		-- l'état du serveur (une demande refusée n'exige pas deux appuis).
		if isPressed then
			if isServerSprinting() then
				requestSprint(false)
			else
				sprintRequested = false
				requestSprint(true)
			end
		end
	else
		requestSprint(isPressed)
	end
end

-- ── Animations ────────────────────────────────────────────────────────────

local function playAnimation(key: string, animationId: string)
	if animationId == "" then
		return -- animation pas encore créée
	end
	local _, humanoid = getCharacterParts()
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	local track = animationTracks[key]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		local ok, result = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok then
			warn("[MovementController] Animation invalide :", animationId, result)
			return
		end
		track = result
		animationTracks[key] = track
	end
	track:Play(0.05)
end

-- ── Esquive ───────────────────────────────────────────────────────────────

local function performDash(root: BasePart, direction: Vector3)
	local previous = root:FindFirstChild("DodgeVelocity")
	if previous then
		previous:Destroy()
	end

	local attachment = root:FindFirstChild("RootAttachment")
	local createdAttachment = false
	if not attachment or not attachment:IsA("Attachment") then
		attachment = Instance.new("Attachment")
		attachment.Name = "DodgeAttachment"
		attachment.Parent = root
		createdAttachment = true
	end

	local speed = DodgeConfig.Distance / DodgeConfig.Duration

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DodgeVelocity"
	velocity.Attachment0 = attachment :: Attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(direction.X * speed, direction.Z * speed)
	velocity.MaxForce = math.huge
	velocity.Parent = root

	task.delay(DodgeConfig.Duration, function()
		velocity:Destroy()
		if createdAttachment then
			(attachment :: Instance):Destroy()
		end
	end)
end

local function tryDodge()
	local character, humanoid, root = getCharacterParts()
	if not character or not humanoid or not root then
		return
	end

	if character:GetAttribute("Stunned") == true then
		MovementController.DodgeRefused:Fire("Stunned")
		return
	end

	local now = os.clock()
	if now - lastDodgeTime < DodgeConfig.Cooldown then
		MovementController.DodgeRefused:Fire("Cooldown")
		return
	end

	if (player:GetAttribute("Stamina") or 0) < DodgeConfig.StaminaCost then
		MovementController.DodgeRefused:Fire("Stamina")
		return
	end

	if not DodgeConfig.AllowInAir and humanoid.FloorMaterial == Enum.Material.Air then
		MovementController.DodgeRefused:Fire("Air")
		return
	end

	local move = humanoid.MoveDirection
	local flatMove = Vector3.new(move.X, 0, move.Z)
	local direction: Vector3
	local backward = false

	if flatMove.Magnitude > 0.1 then
		direction = flatMove.Unit
	else
		local look = root.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 0.01 then
			return
		end
		direction = -flatLook.Unit
		backward = true
	end

	lastDodgeTime = now
	DodgeRemote:FireServer(direction)
	performDash(root, direction)

	if backward then
		playAnimation("DodgeBackward", AnimationConfig.Dodge.Backward)
	else
		playAnimation("DodgeForward", AnimationConfig.Dodge.Forward)
	end

	if CameraController then
		CameraController:Kick()
	end
	MovementController.Dodged:Fire(DodgeConfig.Cooldown)
end

local function onDodgeInput(isPressed: boolean)
	if isPressed then
		tryDodge()
	end
end

-- ── Cycle de vie ──────────────────────────────────────────────────────────

local function onCharacterAdded(character: Model)
	characterMaid:Clean()
	table.clear(animationTracks)
	lastDodgeTime = -math.huge
	sprintRequested = false

	characterMaid:Give(character.AncestryChanged:Connect(function()
		if not character.Parent then
			characterMaid:Clean()
			table.clear(animationTracks)
		end
	end))
end

function MovementController:Init(controllers)
	CameraController = controllers.CameraController
	InputController = controllers.InputController
end

function MovementController:Start()
	SprintRemote = Net.Get("Movement_RequestSprint")
	DodgeRemote = Net.Get("Movement_RequestDodge")

	InputController:BindAction("Sprint", onSprintInput)
	InputController:BindAction("Dodge", onDodgeInput)

	-- Le serveur a coupé le sprint (endurance à 0, étourdissement, mort) :
	-- la demande en cours est terminée.
	player:GetAttributeChangedSignal("IsSprinting"):Connect(function()
		if not isServerSprinting() then
			sprintRequested = false
		end
	end)

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return MovementController
