--!strict

-- Upgrades comprados com Money na loja da base (Config/Upgrades). Os efeitos são
-- registrados nos serviços que os aplicam (WarriorService, SpeedService), então
-- nenhum deles depende deste serviço.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UpgradesConfig = require(Shared:WaitForChild("Config"):WaitForChild("Upgrades"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local CurrencyService = require(script.Parent.CurrencyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local SpeedService = require(script.Parent.SpeedService)
local WarriorService = require(script.Parent.WarriorService)

local UpgradeService = {}

local BUY_COOLDOWN = 0.3

local lastBuy: { [Player]: number } = {}

local function getLevels(player: Player): { [string]: number }
	local levels = PlayerDataService:Get(player, "Upgrades")
	return if typeof(levels) == "table" then levels else {}
end

local function levelOf(player: Player, upgradeId: string): number
	local level = getLevels(player)[upgradeId]
	return if typeof(level) == "number" then level else 0
end

-- Atributos Upgrade_<Id>: só para a UI mostrar níveis e preços.
local function syncAttributes(player: Player)
	for id in UpgradesConfig.List do
		player:SetAttribute(`Upgrade_{id}`, levelOf(player, id))
	end
end

local function onBuyUpgrade(player: Player, upgradeId: unknown): (boolean, string)
	local now = os.clock()
	local last = lastBuy[player]
	if last and now - last < BUY_COOLDOWN then
		return false, "Calma, tente de novo"
	end
	lastBuy[player] = now

	if typeof(upgradeId) ~= "string" or not UpgradesConfig.List[upgradeId] then
		return false, "Upgrade inválido"
	end
	if not PlayerDataService:IsLoaded(player) then
		return false, "Seus dados ainda estão carregando"
	end
	if not WarriorService:IsInPlacementArea(player) then
		return false, "A loja só funciona dentro da sua base"
	end

	local info = UpgradesConfig.List[upgradeId]
	local level = levelOf(player, upgradeId)
	local cost = UpgradesConfig.CostFor(upgradeId, level)
	if cost == nil then
		return false, `{info.DisplayName} já está no máximo`
	end
	if not CurrencyService:RemoveMoney(player, cost) then
		return false, "Dinheiro insuficiente"
	end

	PlayerDataService:Update(player, "Upgrades", function(levels: { [string]: number }): { [string]: number }
		levels[upgradeId] = level + 1
		return levels
	end)
	syncAttributes(player)
	return true, `{info.DisplayName} nível {level + 1}!`
end

function UpgradeService:GetLevel(player: Player, upgradeId: string): number
	return levelOf(player, upgradeId)
end

-- Rebirth: zera todos os upgrades.
function UpgradeService:ResetAll(player: Player)
	PlayerDataService:Set(player, "Upgrades", {})
	syncAttributes(player)
end

function UpgradeService:Start()
	local slots = UpgradesConfig.List.ExtraSlots
	local income = UpgradesConfig.List.IncomeMultiplier
	local training = UpgradesConfig.List.TrainingSpeed

	WarriorService:AddSlotBonus(function(player: Player): number
		return levelOf(player, slots.Id) * slots.PerLevel
	end)
	WarriorService:AddIncomeMultiplier(function(player: Player): number
		return 1 + levelOf(player, income.Id) * income.PerLevel
	end)
	SpeedService:AddTrainingMultiplier(function(player: Player): number
		return 1 + levelOf(player, training.Id) * training.PerLevel
	end)

	Remotes.getFunction(Remotes.Functions.BuyUpgrade).OnServerInvoke = onBuyUpgrade
	PlayerDataService:OnPlayerLoaded(syncAttributes)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastBuy[player] = nil
	end)
end

return UpgradeService
