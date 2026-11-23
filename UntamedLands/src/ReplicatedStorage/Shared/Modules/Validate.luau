--!nonstrict
--[[
	Validate
	Location : ReplicatedStorage/Shared/Modules/Validate (ModuleScript)
	Purpose  : Small, strict type checks for data arriving through remotes.
	           Exploiters can send any value (NaN, inf, huge strings, Instances
	           they don't own, tables with metatables...). Check everything.
	Depends  : nothing
]]

local Validate = {}

function Validate.isFiniteNumber(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.isInteger(value, min, max)
	if not Validate.isFiniteNumber(value) or value % 1 ~= 0 then
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

function Validate.isBoolean(value)
	return type(value) == "boolean"
end

function Validate.isString(value, maxLength)
	return type(value) == "string" and (maxLength == nil or #value <= maxLength)
end

-- set is a dictionary { key = true/anything }
function Validate.isKeyOf(value, set)
	return type(value) == "string" and set[value] ~= nil
end

function Validate.isVector3(value, maxMagnitude)
	if typeof(value) ~= "Vector3" then
		return false
	end
	if not (Validate.isFiniteNumber(value.X) and Validate.isFiniteNumber(value.Y) and Validate.isFiniteNumber(value.Z)) then
		return false
	end
	return maxMagnitude == nil or value.Magnitude <= maxMagnitude
end

-- Returns a clamped number, or fallback if the value is not a finite number.
function Validate.clampNumber(value, min, max, fallback)
	if not Validate.isFiniteNumber(value) then
		return fallback
	end
	return math.clamp(value, min, max)
end

-- Plain table: no metatable, not an Instance.
function Validate.isPlainTable(value)
	return type(value) == "table" and getmetatable(value) == nil
end

return Validate
