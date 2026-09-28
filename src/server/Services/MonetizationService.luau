--!strict

-- Game Passes e Developer Products (Config/Monetization). Id = 0 é placeholder:
-- o item fica desligado, nunca é consultado nem oferecido, e nada quebra.
--
-- Developer Products: ProcessReceipt idempotente. Um PurchaseId já entregue
-- responde PurchaseGranted sem entregar de novo. Jogador fora do servidor ou
-- dados não carregados responde NotProcessedYet, e o Roblox tenta de novo depois.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared:WaitForChild("Config"):WaitForChild("Monetization"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local CurrencyService = require(script.Parent.CurrencyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local SpeedService = require(script.Parent.SpeedService)
local WarriorService = require(script.Parent.WarriorService)

local MonetizationService = {}

local PROMPT_COOLDOWN = 1
-- Quantos PurchaseId guardar por jogador (os mais antigos saem).
local MAX_RECEIPTS = 200

type Receipts = { [string]: number }

local ownedPasses: { [Player]: { [string]: boolean } } = {}
local lastPrompt: { [Player]: number } = {}
local passKeyById: { [number]: string } = {}
local productKeyById: { [number]: string } = {}

local function notify(player: Player, text: string)
	Remotes.getEvent(Remotes.Events.Notify):FireClient(player, text)
end

local function setOwned(player: Player, key: string, owned: boolean)
	local passes = ownedPasses[player]
	if passes == nil then
		passes = {}
		ownedPasses[player] = passes
	end
	passes[key] = owned
	-- Só para a UI mostrar "Comprado"; o servidor usa ownedPasses.
	player:SetAttribute(`Pass_{key}`, owned)
end

local function loadPasses(player: Player)
	for key, pass in Monetization.GamePasses do
		if pass.Id == 0 then
			continue
		end
		local ok, owned = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
		end)
		if ok then
			setOwned(player, key, owned == true)
		else
			warn(`[MonetizationService] Falha ao consultar o Game Pass {key} de {player.Name}: {owned}`)
		end
	end
end

-- Entrega de cada Developer Product. Não pode yieldar: a entrega e a marcação do
-- PurchaseId acontecem juntas, na memória.
local productHandlers: { [string]: (Player) -> boolean } = {
	SkipHatch = function(player: Player): boolean
		local skipped = WarriorService:SkipHatching(player)
		if skipped == 0 then
			warn(`[MonetizationService] {player.Name} comprou "Pular chocagem" sem nada chocando`)
		end
		notify(player, `Chocagem pulada ({skipped})!`)
		return true
	end,
	MoneyPack = function(player: Player): boolean
		local ok = CurrencyService:AddMoney(player, Monetization.MoneyPackAmount)
		if ok then
			notify(player, `Você recebeu $ {Format.number(Monetization.MoneyPackAmount)}!`)
		end
		return ok
	end,
}

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local productKey = productKeyById[receipt.ProductId]
	local handler = if productKey then productHandlers[productKey] else nil
	if productKey == nil or handler == nil then
		warn(`[MonetizationService] Produto desconhecido: {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil or not PlayerDataService:IsLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receipt.PurchaseId)
	local receipts = PlayerDataService:Get(player, "ProcessedReceipts") :: Receipts?
	if receipts and receipts[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local ok, granted = pcall(handler, player)
	if not ok or not granted then
		warn(`[MonetizationService] Falha ao entregar {productKey} para {player.Name}: {granted}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	PlayerDataService:Update(player, "ProcessedReceipts", function(current: Receipts): Receipts
		current[purchaseId] = os.time()

		local count = 0
		local oldestId: string? = nil
		local oldestTime = math.huge
		for id, time in current do
			count += 1
			if time < oldestTime then
				oldestTime = time
				oldestId = id
			end
		end
		if count > MAX_RECEIPTS and oldestId then
			current[oldestId] = nil
		end
		return current
	end)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function onPromptPurchase(player: Player, kind: unknown, key: unknown): (boolean, string)
	local now = os.clock()
	local last = lastPrompt[player]
	if last and now - last < PROMPT_COOLDOWN then
		return false, "Calma, tente de novo"
	end
	lastPrompt[player] = now

	if typeof(kind) ~= "string" or typeof(key) ~= "string" then
		return false, "Pedido inválido"
	end

	if kind == "Pass" then
		local pass = Monetization.GamePasses[key]
		if not pass then
			return false, "Pedido inválido"
		end
		if pass.Id == 0 then
			return false, "Em breve"
		end
		if MonetizationService:HasPass(player, key) then
			return false, "Você já tem esse Game Pass"
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
		return true, ""
	elseif kind == "Product" then
		local product = Monetization.Products[key]
		if not product then
			return false, "Pedido inválido"
		end
		if product.Id == 0 then
			return false, "Em breve"
		end
		if key == "SkipHatch" and not WarriorService:HasHatching(player) then
			return false, "Nenhum totem chocando"
		end
		MarketplaceService:PromptProductPurchase(player, product.Id)
		return true, ""
	end
	return false, "Pedido inválido"
end

function MonetizationService:HasPass(player: Player, key: string): boolean
	local passes = ownedPasses[player]
	return passes ~= nil and passes[key] == true
end

function MonetizationService:Start()
	for key, pass in Monetization.GamePasses do
		if pass.Id ~= 0 then
			passKeyById[pass.Id] = key
		end
	end
	for key, product in Monetization.Products do
		if product.Id ~= 0 then
			productKeyById[product.Id] = key
		end
	end

	WarriorService:AddIncomeMultiplier(function(player: Player): number
		return if MonetizationService:HasPass(player, "DoubleIncome") then 2 else 1
	end)
	SpeedService:AddTrainingMultiplier(function(player: Player): number
		return if MonetizationService:HasPass(player, "DoubleTraining") then 2 else 1
	end)
	WarriorService:AddSlotBonus(function(player: Player): number
		return if MonetizationService:HasPass(player, "ExtraSlots") then Monetization.ExtraSlotsAmount else 0
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local key = passKeyById[passId]
		if key and purchased then
			setOwned(player, key, true)
			notify(player, `{Monetization.GamePasses[key].DisplayName} ativado!`)
		end
	end)
	MarketplaceService.ProcessReceipt = processReceipt

	Remotes.getFunction(Remotes.Functions.PromptPurchase).OnServerInvoke = onPromptPurchase

	Players.PlayerAdded:Connect(loadPasses)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPasses, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		ownedPasses[player] = nil
		lastPrompt[player] = nil
	end)
end

return MonetizationService
