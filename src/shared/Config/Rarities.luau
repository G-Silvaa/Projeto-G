--!strict

-- A chave (Id) é o que fica salvo nos dados: não renomeie. DisplayName é o que aparece na tela.
export type Rarity = {
	Id: string,
	DisplayName: string,
	Order: number,
	Color: Color3,
	HatchSeconds: number,
	IncomeMin: number,
	IncomeMax: number,
}

local function rarity(
	id: string,
	displayName: string,
	order: number,
	color: Color3,
	hatchSeconds: number,
	incomeMin: number,
	incomeMax: number
): Rarity
	return table.freeze({
		Id = id,
		DisplayName = displayName,
		Order = order,
		Color = color,
		HatchSeconds = hatchSeconds,
		IncomeMin = incomeMin,
		IncomeMax = incomeMax,
	})
end

local MINUTE = 60
local HOUR = 60 * MINUTE

local Rarities: { [string]: Rarity } = {
	Common = rarity("Common", "Comum", 1, Color3.fromRGB(170, 170, 170), 30, 1, 3),
	Rare = rarity("Rare", "Raro", 2, Color3.fromRGB(60, 140, 255), 3 * MINUTE, 5, 10),
	Epic = rarity("Epic", "Épico", 3, Color3.fromRGB(160, 70, 255), 15 * MINUTE, 20, 40),
	Legendary = rarity("Legendary", "Lendário", 4, Color3.fromRGB(255, 180, 0), HOUR, 80, 150),
	Mythic = rarity("Mythic", "Mítico", 5, Color3.fromRGB(230, 40, 60), 4 * HOUR, 300, 600),
	Secret = rarity("Secret", "Secreto", 6, Color3.fromRGB(20, 20, 20), 12 * HOUR, 1200, 2500),
}

return table.freeze(Rarities)
