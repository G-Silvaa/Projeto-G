--!strict

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

local function getMoneyValue(leaderstats: Folder): IntValue
	local existing = leaderstats:FindFirstChild("Money")
	if existing then
		return existing :: IntValue
	end

	local value = Instance.new("IntValue")
	value.Name = "Money"
	value.Parent = leaderstats
	return value
end

local function syncDisplay(player: Player)
	local money = PlayerDataService:Get(player, "Money")
	if money == nil then
		return
	end

	local moneyValue = getMoneyValue(getLeaderstats(player))
	moneyValue.Value = money
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
