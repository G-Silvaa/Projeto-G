--!strict

-- Rebirth: com Money suficiente, zera Money, guerreiros e upgrades em troca de um
-- multiplicador permanente de renda (Config/Rebirth). Speed não é zerado.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RebirthConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rebirth"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local CurrencyService = require(script.Parent.CurrencyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local UpgradeService = require(script.Parent.UpgradeService)
local WarriorService = require(script.Parent.WarriorService)

local RebirthService = {}

local REBIRTH_COOLDOWN = 1

local lastCall: { [Player]: number } = {}

local function getRebirths(player: Player): number
	local rebirths = PlayerDataService:Get(player, "Rebirths")
	return if typeof(rebirths) == "number" then rebirths else 0
end

-- Atributo Rebirths: só para a UI mostrar o contador e o custo do próximo.
local function syncAttribute(player: Player)
	player:SetAttribute("Rebirths", getRebirths(player))
end

local function onRebirth(player: Player): (boolean, string)
	local now = os.clock()
	local last = lastCall[player]
	if last and now - last < REBIRTH_COOLDOWN then
		return false, "Calma, tente de novo"
	end
	lastCall[player] = now

	if not PlayerDataService:IsLoaded(player) then
		return false, "Seus dados ainda estão carregando"
	end

	local rebirths = getRebirths(player)
	local cost = RebirthConfig.CostFor(rebirths)
	local money = CurrencyService:GetMoney(player) or 0
	if money < cost then
		return false, `Precisa de $ {Format.number(cost)} para o rebirth`
	end

	-- Tira o saldo inteiro (inclui o que passou do custo).
	if not CurrencyService:RemoveMoney(player, money) then
		return false, "Não foi possível fazer o rebirth"
	end
	WarriorService:ResetSlots(player)
	UpgradeService:ResetAll(player)
	PlayerDataService:Set(player, "Rebirths", rebirths + 1)
	syncAttribute(player)

	local multiplier = RebirthConfig.MultiplierFor(rebirths + 1)
	return true, `Rebirth {rebirths + 1}! Renda x{multiplier}`
end

function RebirthService:GetRebirths(player: Player): number
	return getRebirths(player)
end

function RebirthService:Start()
	WarriorService:AddIncomeMultiplier(function(player: Player): number
		return RebirthConfig.MultiplierFor(getRebirths(player))
	end)

	Remotes.getFunction(Remotes.Functions.Rebirth).OnServerInvoke = onRebirth
	PlayerDataService:OnPlayerLoaded(syncAttribute)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastCall[player] = nil
	end)
end

return RebirthService
