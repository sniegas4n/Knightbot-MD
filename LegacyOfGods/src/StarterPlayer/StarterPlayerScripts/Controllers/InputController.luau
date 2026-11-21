--[[
	InputController (ModuleScript) — CLIENT
	Emplacement : StarterPlayer > StarterPlayerScripts > Controllers > InputController

	Couche unique au-dessus de ContextActionService. Les touches viennent de
	Config.Input.Actions : clavier, manette et bouton tactile pour chaque action.

	InputController:BindAction("Dodge", function(isPressed, inputObject, mode) end)
	  - isPressed : true à l'appui, false au relâchement
	  - mode      : "Hold" ou "Toggle" selon le périphérique utilisé

	ContextActionService n'envoie rien quand une zone de texte (chat) a le
	focus : taper "q" dans le chat ne déclenche pas d'esquive.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Actions = Config.Input.Actions
local ACTION_PREFIX = "LOG_"

local InputController = {}

local GAMEPAD_TYPES = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
	[Enum.UserInputType.Gamepad5] = true,
	[Enum.UserInputType.Gamepad6] = true,
	[Enum.UserInputType.Gamepad7] = true,
	[Enum.UserInputType.Gamepad8] = true,
}

-- true si l'appareil principal est tactile (téléphone / tablette sans clavier).
function InputController:IsTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function InputController:IsGamepadInput(inputObject: InputObject): boolean
	return GAMEPAD_TYPES[inputObject.UserInputType] == true
end

local function resolveMode(definition, inputObject: InputObject): string
	if inputObject.UserInputType == Enum.UserInputType.Touch then
		return (definition.Touch and definition.Touch.Mode) or "Hold"
	elseif GAMEPAD_TYPES[inputObject.UserInputType] then
		return definition.GamepadMode or "Hold"
	end
	return definition.KeyboardMode or "Hold"
end

function InputController:BindAction(actionId: string, callback: (boolean, InputObject, string) -> ())
	local definition = Actions[actionId]
	assert(definition, ("[InputController] Action inconnue : %s"):format(actionId))

	local inputs = {}
	for _, key in definition.Keyboard or {} do
		table.insert(inputs, key)
	end
	for _, key in definition.Gamepad or {} do
		table.insert(inputs, key)
	end

	local touch = definition.Touch
	local createTouchButton = touch ~= nil and touch.Enabled == true
	local actionName = ACTION_PREFIX .. actionId

	ContextActionService:BindAction(actionName, function(_, inputState, inputObject)
		if inputState == Enum.UserInputState.Begin then
			callback(true, inputObject, resolveMode(definition, inputObject))
			return Enum.ContextActionResult.Sink
		elseif inputState == Enum.UserInputState.End then
			callback(false, inputObject, resolveMode(definition, inputObject))
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, createTouchButton, table.unpack(inputs))

	if createTouchButton then
		ContextActionService:SetTitle(actionName, touch.Title)
		ContextActionService:SetPosition(actionName, touch.Position)
	end
end

function InputController:UnbindAction(actionId: string)
	ContextActionService:UnbindAction(ACTION_PREFIX .. actionId)
end

-- Libellé de touche à afficher dans le HUD (ex. "Z").
function InputController:GetKeyLabel(actionId: string): string
	local definition = Actions[actionId]
	if not definition then
		return "?"
	end
	if definition.Label then
		return definition.Label
	end
	local first = definition.Keyboard and definition.Keyboard[1]
	if typeof(first) == "EnumItem" then
		return first.Name
	end
	return "?"
end

return InputController
