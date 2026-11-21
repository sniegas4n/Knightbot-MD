--[[
	Format (ModuleScript) — CLIENT
	Emplacement : StarterPlayer > StarterPlayerScripts > UI > Format

	Mise en forme des nombres pour l'affichage.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "Md", "B" } -- K = mille, M = million, Md = milliard, B = billion

-- 1520 -> "1.52K", 3400000 -> "3.4M"
function Format.Compact(value: number): string
	if type(value) ~= "number" or value ~= value then
		return "0"
	end
	local negative = value < 0
	value = math.abs(value)

	local index = 1
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end

	local text
	if index == 1 then
		text = tostring(math.floor(value))
	elseif value >= 100 then
		text = string.format("%d", math.floor(value))
	elseif value >= 10 then
		text = string.format("%.1f", math.floor(value * 10) / 10)
	else
		text = string.format("%.2f", math.floor(value * 100) / 100)
	end

	-- Retire les zéros décimaux inutiles : "1.50" -> "1.5", "2.00" -> "2"
	-- (uniquement s'il y a une partie décimale : "100" doit rester "100")
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end

	return (negative and "-" or "") .. text .. SUFFIXES[index]
end

-- 1234567 -> "1 234 567" (séparateur de milliers à la française)
function Format.Thousands(value: number): string
	local text = tostring(math.floor(value))
	local result = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1 ")))
	return (string.gsub(result, "^(%-?) ", "%1"))
end

return Format
