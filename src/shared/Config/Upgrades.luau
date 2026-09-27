--!strict

-- Upgrades comprados com Money na loja da base (UpgradeService).
-- O Id (chave) é o que fica salvo nos dados: não renomeie.
-- Preço do próximo nível: floor(BaseCost * CostGrowth ^ nívelAtual).

export type Upgrade = {
	Id: string,
	DisplayName: string,
	Description: string,
	MaxLevel: number,
	BaseCost: number,
	CostGrowth: number,
	PerLevel: number, -- efeito por nível (slots, ou fração de multiplicador)
}

local function upgrade(
	id: string,
	displayName: string,
	description: string,
	maxLevel: number,
	baseCost: number,
	costGrowth: number,
	perLevel: number
): Upgrade
	return table.freeze({
		Id = id,
		DisplayName = displayName,
		Description = description,
		MaxLevel = maxLevel,
		BaseCost = baseCost,
		CostGrowth = costGrowth,
		PerLevel = perLevel,
	})
end

local List: { [string]: Upgrade } = {
	ExtraSlots = upgrade("ExtraSlots", "Mais espaço", "+1 guerreiro na base", 6, 2000, 3, 1),
	IncomeMultiplier = upgrade("IncomeMultiplier", "Renda", "+10% de dinheiro por segundo", 10, 1000, 2.2, 0.1),
	TrainingSpeed = upgrade("TrainingSpeed", "Treino", "+25% de ganho na esteira", 10, 500, 2, 0.25),
}

local function costFor(upgradeId: string, currentLevel: number): number?
	local info = List[upgradeId]
	if not info or currentLevel >= info.MaxLevel then
		return nil
	end
	return math.floor(info.BaseCost * info.CostGrowth ^ currentLevel)
end

return table.freeze({
	List = table.freeze(List),
	-- Ordem de exibição na loja.
	Order = table.freeze({ "ExtraSlots", "IncomeMultiplier", "TrainingSpeed" }),
	-- Preço do próximo nível, ou nil se não existe / já está no máximo.
	CostFor = costFor,
})
