--[[
	Validate (ModuleScript) — SERVEUR
	Emplacement : ServerScriptService > Modules > Validate

	Vérifications strictes des arguments reçus des clients.
	RÈGLE : tout argument venant d'un RemoteEvent est suspect. Un exploiteur
	peut envoyer n'importe quel type, NaN, l'infini, des tables énormes...
]]

local Validate = {}

function Validate.IsFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.Boolean(value: any): boolean
	return type(value) == "boolean"
end

function Validate.Number(value: any, min: number?, max: number?): boolean
	if not Validate.IsFiniteNumber(value) then
		return false
	end
	if min and value < min then
		return false
	end
	if max and value > max then
		return false
	end
	return true
end

function Validate.Integer(value: any, min: number?, max: number?): boolean
	return Validate.Number(value, min, max) and value % 1 == 0
end

function Validate.String(value: any, maxLength: number): boolean
	return type(value) == "string" and #value <= maxLength and utf8.len(value) ~= nil
end

function Validate.Vector3(value: any, maxMagnitude: number?): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	if not (Validate.IsFiniteNumber(value.X) and Validate.IsFiniteNumber(value.Y) and Validate.IsFiniteNumber(value.Z)) then
		return false
	end
	if maxMagnitude and value.Magnitude > maxMagnitude then
		return false
	end
	return true
end

-- Vérifie que `value` est l'un des éléments de `allowed` (liste).
function Validate.OneOf(value: any, allowed: { any }): boolean
	return table.find(allowed, value) ~= nil
end

return Validate
