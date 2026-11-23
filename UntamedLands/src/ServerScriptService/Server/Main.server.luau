--!nonstrict
--[[
	Main (Script)
	Location : ServerScriptService/Server/Main
	Purpose  : The ONLY server Script. Creates the workspace/asset folders, then
	           initialises and starts every service in dependency order.
	           init()  : connect remotes/signals, no yielding, no world changes
	           start() : begin loops, generation, player handling
	All other server code lives in ModuleScripts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Must be false before anyone spawns; also set in default.project.json.
Players.CharacterAutoLoads = false

-- Requiring Net on the server creates ReplicatedStorage/Remotes.
require(ReplicatedStorage.Shared.Modules.Net)

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

for _, name in ipairs({ "World", "NPCs", "Resources", "PlayerBuildings" }) do
	ensureFolder(workspace, name)
end
ensureFolder(ReplicatedStorage, "Assets")

local Server = script.Parent
local services = {
	require(Server.PlayerData.PlayerDataService),
	require(Server.Progression.StatService),
	require(Server.WorldGeneration.WorldGenService),
	require(Server.Core.EnvironmentService),
	require(Server.Combat.CombatService),
	require(Server.Combat.VitalsService),
	require(Server.Core.CharacterService),
	require(Server.NPCs.NPCService),
}

for _, service in ipairs(services) do
	service.init()
end
for _, service in ipairs(services) do
	service.start()
end

print("[UntamedLands] Server started")
