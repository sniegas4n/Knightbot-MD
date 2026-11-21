--[[
	EconomyService (ModuleScript) — SERVEUR
	Emplacement : ServerScriptService > Services > EconomyService

	Seul service autorisé à modifier les monnaies.
	Tous les montants sont des entiers positifs ; tout le reste est refusé.
	Chaque opération est journalisée (en mémoire en Phase 1, persistée en
	Phase 2 pour l'historique des transactions).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared.Modules.Signal)
local Validate = require(ServerScriptService.Modules.Validate)

local Currencies = Config.Economy.Currencies
local MAX_LOG_ENTRIES = 200

local EconomyService = {
	BalanceChanged = Signal.new(), -- (player, currencyId, newBalance, delta, reason)
}

local PlayerStateService
local transactionLog: { any } = {}

local function log(player: Player, currencyId: string, delta: number, balance: number, reason: string)
	table.insert(transactionLog, {
		Time = os.time(),
		UserId = player.UserId,
		Currency = currencyId,
		Delta = delta,
		Balance = balance,
		Reason = reason,
	})
	if #transactionLog > MAX_LOG_ENTRIES then
		table.remove(transactionLog, 1)
	end
end

local function isValidAmount(currencyId: string, amount: any): boolean
	return Currencies[currencyId] ~= nil and Validate.Integer(amount, 1, Currencies[currencyId].MaxAmount)
end

function EconomyService:GetBalance(player: Player, currencyId: string): number
	local profile = PlayerStateService:GetProfile(player)
	return profile and profile.Currencies[currencyId] or 0
end

function EconomyService:CanAfford(player: Player, currencyId: string, amount: number): boolean
	return isValidAmount(currencyId, amount) and self:GetBalance(player, currencyId) >= amount
end

-- Ajoute `amount` (entier > 0). Plafonné à MaxAmount. Renvoie true si appliqué.
function EconomyService:Add(player: Player, currencyId: string, amount: number, reason: string): boolean
	local profile = PlayerStateService:GetProfile(player)
	if not profile or not isValidAmount(currencyId, amount) then
		return false
	end

	local before = profile.Currencies[currencyId] or 0
	local after = math.min(before + amount, Currencies[currencyId].MaxAmount)
	profile.Currencies[currencyId] = after

	PlayerStateService:Replicate(player, "Currencies")
	log(player, currencyId, after - before, after, reason)
	self.BalanceChanged:Fire(player, currencyId, after, after - before, reason)
	return true
end

-- Retire `amount` si le joueur peut payer. Renvoie true si appliqué.
function EconomyService:Spend(player: Player, currencyId: string, amount: number, reason: string): boolean
	local profile = PlayerStateService:GetProfile(player)
	if not profile or not self:CanAfford(player, currencyId, amount) then
		return false
	end

	local after = profile.Currencies[currencyId] - amount
	profile.Currencies[currencyId] = after

	PlayerStateService:Replicate(player, "Currencies")
	log(player, currencyId, -amount, after, reason)
	self.BalanceChanged:Fire(player, currencyId, after, -amount, reason)
	return true
end

function EconomyService:GetRecentTransactions(): { any }
	return table.clone(transactionLog)
end

function EconomyService:Init(services)
	PlayerStateService = services.PlayerStateService
end

return EconomyService
