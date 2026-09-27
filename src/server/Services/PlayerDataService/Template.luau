--!strict

-- Renomear, remover ou mudar o tipo de uma chave exige subir DataVersion e criar a migração em init.luau.
local Template: { [string]: any } = {
	DataVersion = 1,
	JoinCount = 0,
	Money = 0, -- inteiro; ver CurrencyService
}

return table.freeze(Template)
