--!nonstrict
--[[
	Net
	Location : ReplicatedStorage/Shared/Modules/Net (ModuleScript)
	Purpose  : The single definition of every RemoteEvent / RemoteFunction.
	           - On the server, requiring this module CREATES the remotes in
	             ReplicatedStorage/Remotes, so clients never race against them.
	           - Every client->server remote has a per-player rate limit
	             (calls per second). Excess calls are silently dropped.
	           - Handlers run inside pcall so a malformed request can never break
	             the listener for everyone else.
	           Handlers must still validate argument TYPES and VALUES themselves
	           (see Validate). Never trust anything that comes from a client.
	Depends  : nothing
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local FOLDER_NAME = "Remotes"

local Net = {}

-- kind: "Event" or "Function". rate: max calls per second per player (client->server only).
Net.Definitions = {
	-- Client -> Server
	GetSessionState = { kind = "Function", rate = 2 },
	SubmitCharacter = { kind = "Function", rate = 1 },
	RequestAttack = { kind = "Event", rate = 8 },
	SetBlocking = { kind = "Event", rate = 10 },
	RequestDodge = { kind = "Event", rate = 4 },
	SetSprinting = { kind = "Event", rate = 10 },
	EquipSlot = { kind = "Event", rate = 4 },
	ToggleOffhand = { kind = "Event", rate = 3 },

	-- Server -> Client
	AttackStarted = { kind = "Event" },
	CombatFeedback = { kind = "Event" },
	StatsUpdated = { kind = "Event" },
	Notify = { kind = "Event" },
}

local folder = nil
local remotes = {}

if IS_SERVER then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for name, def in pairs(Net.Definitions) do
		local className = if def.kind == "Function" then "RemoteFunction" else "RemoteEvent"
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
		remotes[name] = remote
	end
end

local function getRemote(name)
	assert(Net.Definitions[name], "[Net] Unknown remote: " .. tostring(name))
	local remote = remotes[name]
	if remote then
		return remote
	end
	if not folder then
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end
	remote = folder:WaitForChild(name, 30)
	assert(remote, "[Net] Timed out waiting for remote " .. name)
	remotes[name] = remote
	return remote
end

---------------------------------------------------------------------------
-- Server-side rate limiting
---------------------------------------------------------------------------
local usage = {} -- [Player] = { [remoteName] = { windowStart, count, warned } }

local function allow(player, name)
	local limit = Net.Definitions[name].rate
	if not limit then
		return true
	end
	local perPlayer = usage[player]
	if not perPlayer then
		perPlayer = {}
		usage[player] = perPlayer
	end
	local now = os.clock()
	local entry = perPlayer[name]
	if not entry or now - entry.windowStart >= 1 then
		entry = { windowStart = now, count = 0, warned = false }
		perPlayer[name] = entry
	end
	entry.count += 1
	if entry.count > limit then
		if not entry.warned then
			entry.warned = true
			warn(("[Net] Rate limit hit: %s -> %s"):format(player.Name, name))
		end
		return false
	end
	return true
end

if IS_SERVER then
	Players.PlayerRemoving:Connect(function(player)
		usage[player] = nil
	end)
end

---------------------------------------------------------------------------
-- Server API
---------------------------------------------------------------------------
function Net.connect(name, handler)
	assert(IS_SERVER, "Net.connect is server-only")
	local remote = getRemote(name)
	assert(remote:IsA("RemoteEvent"), name .. " is not a RemoteEvent")
	return remote.OnServerEvent:Connect(function(player, ...)
		if not allow(player, name) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(("[Net] %s handler error (%s): %s"):format(name, player.Name, tostring(err)))
		end
	end)
end

function Net.handle(name, handler)
	assert(IS_SERVER, "Net.handle is server-only")
	local remote = getRemote(name)
	assert(remote:IsA("RemoteFunction"), name .. " is not a RemoteFunction")
	remote.OnServerInvoke = function(player, ...)
		if not allow(player, name) then
			return nil
		end
		local results = table.pack(pcall(handler, player, ...))
		if not results[1] then
			warn(("[Net] %s invoke error (%s): %s"):format(name, player.Name, tostring(results[2])))
			return nil
		end
		return table.unpack(results, 2, results.n)
	end
end

function Net.fireClient(name, player, ...)
	getRemote(name):FireClient(player, ...)
end

function Net.fireAll(name, ...)
	getRemote(name):FireAllClients(...)
end

-- Sends only to players whose character is within radius of position.
function Net.fireNearby(name, position, radius, ...)
	local remote = getRemote(name)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - position).Magnitude <= radius then
			remote:FireClient(player, ...)
		end
	end
end

---------------------------------------------------------------------------
-- Client API
---------------------------------------------------------------------------
function Net.fireServer(name, ...)
	getRemote(name):FireServer(...)
end

function Net.invoke(name, ...)
	return getRemote(name):InvokeServer(...)
end

function Net.on(name, handler)
	return getRemote(name).OnClientEvent:Connect(handler)
end

return Net
