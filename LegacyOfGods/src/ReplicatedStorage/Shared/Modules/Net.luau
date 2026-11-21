--[[
	Net (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Modules > Net

	Accès centralisé aux Remotes déclarés dans Config.Network.

	Serveur : Net.Setup() crée le dossier ReplicatedStorage.Remotes et tous les
	          Remotes déclarés. Appelé UNE fois par ServerMain.
	Client  : Net.Get(nom) attend le Remote (WaitForChild avec délai).

	Demander un Remote non déclaré dans la config lève une erreur explicite :
	cela évite les fautes de frappe silencieuses.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Parent:WaitForChild("Config"))

local IS_SERVER = RunService:IsServer()
local IS_STUDIO = RunService:IsStudio()
local WAIT_TIMEOUT = 20

local NetworkConfig = Config.Network

local Net = {}

local cache: { [string]: Instance } = {}

local function getDefinition(name: string)
	local definition = NetworkConfig.Remotes[name]
	if not definition then
		error(("[Net] Remote inconnu '%s' : déclarez-le dans Config.Network.Remotes"):format(tostring(name)), 3)
	end
	return definition
end

local function isAvailable(definition): boolean
	return not definition.StudioOnly or IS_STUDIO
end

-- SERVEUR uniquement : crée tous les Remotes.
function Net.Setup()
	assert(IS_SERVER, "[Net] Setup() ne peut être appelé que côté serveur")

	local folder = ReplicatedStorage:FindFirstChild(NetworkConfig.FolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = NetworkConfig.FolderName
		folder.Parent = ReplicatedStorage
	end

	for name, definition in NetworkConfig.Remotes do
		if isAvailable(definition) then
			local existing = folder:FindFirstChild(name)
			if existing and existing.ClassName ~= definition.Type then
				warn(("[Net] '%s' existe avec le mauvais type (%s), remplacement"):format(name, existing.ClassName))
				existing:Destroy()
				existing = nil
			end
			if not existing then
				local remote = Instance.new(definition.Type)
				remote.Name = name
				remote.Parent = folder
			end
		end
	end
end

-- Renvoie le RemoteEvent / RemoteFunction demandé.
-- Côté client, peut renvoyer nil pour un Remote StudioOnly hors Studio.
function Net.Get(name: string): any
	local cached = cache[name]
	if cached then
		return cached
	end

	local definition = getDefinition(name)
	if not isAvailable(definition) then
		return nil
	end

	local remote: Instance?
	if IS_SERVER then
		local folder = ReplicatedStorage:FindFirstChild(NetworkConfig.FolderName)
		remote = folder and folder:FindFirstChild(name)
		if not remote then
			error(("[Net] Remote '%s' introuvable : Net.Setup() a-t-il été appelé ?"):format(name), 2)
		end
	else
		local folder = ReplicatedStorage:WaitForChild(NetworkConfig.FolderName, WAIT_TIMEOUT)
		remote = folder and folder:WaitForChild(name, WAIT_TIMEOUT)
		if not remote then
			error(("[Net] Remote '%s' non reçu après %ds"):format(name, WAIT_TIMEOUT), 2)
		end
	end

	cache[name] = remote :: Instance
	return remote
end

function Net.GetDefinition(name: string)
	return getDefinition(name)
end

return Net
