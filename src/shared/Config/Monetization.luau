--!strict

-- Game Passes e Developer Products (MonetizationService).
-- Id = 0 é placeholder: o item fica desligado ("Em breve") e nada quebra.
-- Troque pelo ID real depois de criar o item no Creator Dashboard.
-- A chave (ex.: "DoubleIncome") é usada no código e em ProcessedReceipts: não renomeie.

export type Item = {
	Id: number,
	DisplayName: string,
	Description: string,
}

local function item(id: number, displayName: string, description: string): Item
	return table.freeze({ Id = id, DisplayName = displayName, Description = description })
end

local GamePasses: { [string]: Item } = {
	DoubleIncome = item(0, "Renda x2", "Dobra o dinheiro dos seus guerreiros"),
	DoubleTraining = item(0, "Treino x2", "Dobra o ganho de velocidade na esteira"),
	ExtraSlots = item(0, "+2 espaços", "Mais 2 guerreiros na base"),
}

local Products: { [string]: Item } = {
	SkipHatch = item(0, "Pular chocagem", "Termina agora todas as chocagens"),
	MoneyPack = item(0, "Pacote de dinheiro", "Recebe $ 50K"),
}

return table.freeze({
	GamePasses = table.freeze(GamePasses),
	Products = table.freeze(Products),
	-- Ordem de exibição na loja de Robux.
	PassOrder = table.freeze({ "DoubleIncome", "DoubleTraining", "ExtraSlots" }),
	ProductOrder = table.freeze({ "SkipHatch", "MoneyPack" }),

	ExtraSlotsAmount = 2,
	MoneyPackAmount = 50_000,
})
