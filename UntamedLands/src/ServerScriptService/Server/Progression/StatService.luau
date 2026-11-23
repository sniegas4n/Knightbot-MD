--!nonstrict
--[[
	StatService
	Location : ServerScriptService/Server/Progression/StatService (ModuleScript)
	Purpose  : Use-based progression. Every stat rises by doing the activity
	           (hitting with a blade trains Blades, sprinting trains Athletics...).
	           Gains have diminishing returns. Changed stats are pushed to the
	           owning client in batches (not every hit).
	           NPCs do not progress in Milestone 1.
	Depends  : PlayerDataService, StatDefinitions, StatMath, Net, Signal
	Public   : addExperience(combatant, statId, amount),
	           addExperienceToPlayer(player, statId, amount),
	           pushStats(player), LevelUp (Signal: player, statId, newLevel)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local StatDefinitions = require(Shared.Config.StatDefinitions)
local StatMath = require(Shared.Modules.StatMath)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)

local PlayerDataService = require(script.Parent.Parent.PlayerData.PlayerDataService)

local PUSH_INTERVAL = 1.5

local StatService = {}
StatService.LevelUp = Signal.new()

local dirty = {} -- [Player] = true

function StatService.addExperienceToPlayer(player, statId, amount)
	local info = StatDefinitions.Info[statId]
	if not info or type(amount) ~= "number" or amount <= 0 then
		return
	end
	local data = PlayerDataService.getData(player)
	if not data then
		return
	end
	local stats = data.stats
	local old = stats[statId] or info.start
	if old >= StatDefinitions.MaxLevel then
		return
	end
	local new = math.min(StatDefinitions.MaxLevel, old + StatMath.experienceGain(old, amount))
	stats[statId] = new
	dirty[player] = true

	if math.floor(new) > math.floor(old) then
		local newLevel = math.floor(new)
		StatService.LevelUp:Fire(player, statId, newLevel)
		Net.fireClient("Notify", player, ("%s increased to %d"):format(info.displayName, newLevel))
	end
end

function StatService.addExperience(combatant, statId, amount)
	if combatant and combatant.Player then
		StatService.addExperienceToPlayer(combatant.Player, statId, amount)
	end
end

function StatService.pushStats(player)
	local data = PlayerDataService.getData(player)
	if data then
		dirty[player] = nil
		Net.fireClient("StatsUpdated", player, table.clone(data.stats))
	end
end

function StatService.init() end

function StatService.start()
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(PUSH_INTERVAL)
			for player in pairs(dirty) do
				if player.Parent then
					StatService.pushStats(player)
				else
					dirty[player] = nil
				end
			end
		end
	end)
end

return StatService
