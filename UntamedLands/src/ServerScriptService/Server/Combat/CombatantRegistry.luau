--!nonstrict
--[[
	CombatantRegistry
	Location : ServerScriptService/Server/Combat/CombatantRegistry (ModuleScript)
	Purpose  : Maps character models to Combatant objects. Tags registered models
	           with "Combatant" (CollectionService) so clients can discover them
	           for procedural animation without extra remotes.
	Depends  : Signal
	Public   : register(c), unregister(model), get(model), fromPart(part),
	           forPlayer(player), all(), Registered / Unregistered (Signals)
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local TAG = "Combatant"

local CombatantRegistry = {}
CombatantRegistry.Registered = Signal.new()
CombatantRegistry.Unregistered = Signal.new()

local byModel = {}

function CombatantRegistry.register(combatant)
	byModel[combatant.Model] = combatant
	CollectionService:AddTag(combatant.Model, TAG)
	CombatantRegistry.Registered:Fire(combatant)
end

function CombatantRegistry.unregister(model)
	local combatant = byModel[model]
	if not combatant then
		return
	end
	byModel[model] = nil
	if model.Parent then
		CollectionService:RemoveTag(model, TAG)
	end
	CombatantRegistry.Unregistered:Fire(combatant)
end

function CombatantRegistry.get(model)
	return byModel[model]
end

-- Walks up from a hit part to the registered character that owns it.
function CombatantRegistry.fromPart(part)
	local current = part
	while current and current ~= workspace do
		local combatant = byModel[current]
		if combatant then
			return combatant
		end
		current = current.Parent
	end
	return nil
end

function CombatantRegistry.forPlayer(player)
	local character = player.Character
	return character and byModel[character]
end

-- Returns the internal table: iterate with pairs, do not modify.
function CombatantRegistry.all()
	return byModel
end

return CombatantRegistry
