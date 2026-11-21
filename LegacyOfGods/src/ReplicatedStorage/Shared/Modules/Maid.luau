--[[
	Maid (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Modules > Maid

	Regroupe des ressources à nettoyer ensemble (connexions, instances,
	threads, fonctions). Indispensable pour éviter les fuites mémoire quand un
	personnage réapparaît.

	local maid = Maid.new()
	maid:Give(humanoid.Died:Connect(...))
	maid:Give(someInstance)
	maid:Give(function() print("nettoyage") end)
	maid:Clean()
]]

local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid:Give<T>(item: T): T
	if item ~= nil then
		table.insert(self._tasks, item)
	end
	return item
end

local function cleanItem(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" then
			pcall(task.cancel, item)
		end
	elseif kind == "table" then
		if type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Clean) == "function" then
			item:Clean()
		end
	end
end

function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	for _, item in tasks do
		local ok, err = pcall(cleanItem, item)
		if not ok then
			warn("[Maid] Erreur pendant le nettoyage :", err)
		end
	end
end

Maid.Destroy = Maid.Clean

return Maid
