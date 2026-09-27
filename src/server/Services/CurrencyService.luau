--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))
local PlayerDataService = require(script.Parent.PlayerDataService)

local CurrencyService = {}

-- Money é sempre um inteiro >= 0.
local function isValidAmount(amount: number): boolean
	return amount == amount -- rejeita NaN
		and amount ~= math.huge
		and amount ~= -math.huge
		and amount >= 0
		and amount % 1 == 0
end

local function getLeaderstats(player: Player): Folder
	local existing = player:FindFirstChild("leaderstats")
	if existing then
		return existing :: Folder
	end

	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	folder.Parent = player
	return folder
end

-- StringValue formatado ("1.5K", "2.3M"...): um IntValue estoura em ~2,1 bilhões.
local function getMoneyValue(leaderstats: Folder): StringValue
	local existing = leaderstats:FindFirstChild("Money")
	if existing and existing:IsA("StringValue") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local value = Instance.new("StringValue")
	value.Name = "Money"
	value.Parent = leaderstats
	return value
end

local function syncDisplay(player: Player)
	local money = PlayerDataService:Get(player, "Money")
	if money == nil then
		return
	end

	getMoneyValue(getLeaderstats(player)).Value = Format.number(money)
	-- Número exato só para o HUD mostrar; o servidor nunca lê de volta.
	player:SetAttribute("Money", money)
end

function CurrencyService:Start()
	PlayerDataService:OnPlayerLoaded(syncDisplay)
end

function CurrencyService:GetMoney(player: Player): number?
	return PlayerDataService:Get(player, "Money")
end

function CurrencyService:AddMoney(player: Player, amount: number): boolean
	if not isValidAmount(amount) then
		error(`[CurrencyService] Quantia inválida: {amount}`, 2)
	end

	local updated = PlayerDataService:Update(player, "Money", function(old: number): number
		return old + amount
	end)

	if updated then
		syncDisplay(player)
	end
	return updated
end

function CurrencyService:RemoveMoney(player: Player, amount: number): boolean
	if not isValidAmount(amount) then
		error(`[CurrencyService] Quantia inválida: {amount}`, 2)
	end

	local success = false
	PlayerDataService:Update(player, "Money", function(old: number): number
		if old >= amount then
			success = true
			return old - amount
		end
		return old
	end)

	if success then
		syncDisplay(player)
	end
	return success
end

return CurrencyService
