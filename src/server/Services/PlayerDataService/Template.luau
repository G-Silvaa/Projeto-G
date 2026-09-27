--!strict

-- Renomear, remover ou mudar o tipo de uma chave exige subir DataVersion e criar a migração em init.luau.
local Template: { [string]: any } = {
	DataVersion = 1,
	JoinCount = 0,
	Money = 0, -- inteiro; ver CurrencyService
	-- Slots da base: chave "1".."N" -> { Rarity, StartedAt, OffsetX, OffsetZ, WarriorId? }; ver WarriorService.
	Slots = {},
}

return table.freeze(Template)
