--!strict

-- Renomear, remover ou mudar o tipo de uma chave exige subir DataVersion e criar a migração em init.luau.
local Template: { [string]: any } = {
	DataVersion = 1,
	JoinCount = 0,
	Money = 0, -- inteiro; ver CurrencyService
	-- Slots da base: chave "1".."N" -> { Rarity, StartedAt, OffsetX, OffsetZ, WarriorId? }; ver WarriorService.
	Slots = {},
	-- Pontos de velocidade treinados na esteira (pode ser fracionário); ver SpeedService.
	Speed = 0,
	-- Níveis dos upgrades: { [Id]: nível } (Id de Config/Upgrades); ver UpgradeService.
	Upgrades = {},
	-- Quantos rebirths o jogador fez; ver RebirthService.
	Rebirths = 0,
}

return table.freeze(Template)
