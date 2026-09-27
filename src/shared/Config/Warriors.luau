--!strict

-- Guerreiros 100% originais, inspirados em arquétipos. Nunca use nomes,
-- visuais ou elementos reconhecíveis de animes reais.
-- O Id é o que fica salvo nos dados: não renomeie; o Name pode mudar à vontade.
-- IncomePerSecond precisa ser inteiro e ficar dentro da faixa da raridade (Config/Rarities).

export type Warrior = {
	Id: string,
	Name: string,
	Clan: string,
	Rarity: string,
	IncomePerSecond: number,
}

local function warrior(id: string, name: string, clan: string, rarity: string, incomePerSecond: number): Warrior
	return table.freeze({
		Id = id,
		Name = name,
		Clan = clan,
		Rarity = rarity,
		IncomePerSecond = incomePerSecond,
	})
end

local NINJA = "Ninja"
local PIRATA = "Pirata"
local CACADOR = "Caçador"
local FEITICEIRO = "Feiticeiro"
local LUTADOR = "Lutador de Energia"
local HEROI = "Herói"

local Warriors: { Warrior } = {
	-- Comum (1–3 $/s)
	warrior("tomaru", "Tomaru Passo-Leve", NINJA, "Common", 2),
	warrior("bento", "Bento Remo-Torto", PIRATA, "Common", 1),
	warrior("sanpo", "Sanpo Arco-Curto", CACADOR, "Common", 3),
	warrior("nori", "Nori Faísca-Tímida", FEITICEIRO, "Common", 1),
	warrior("tobu", "Tobu Punho-Firme", LUTADOR, "Common", 3),
	warrior("pip", "Pip Capa-Remendada", HEROI, "Common", 2),

	-- Raro (5–10 $/s)
	warrior("kaseri", "Kaseri Lâmina-Oculta", NINJA, "Rare", 7),
	warrior("doralice", "Doralice Olho-de-Maré", PIRATA, "Rare", 9),
	warrior("hanaye", "Hanaye Rastro-Frio", CACADOR, "Rare", 5),
	warrior("emiko", "Emiko Selo-Azul", FEITICEIRO, "Rare", 10),
	warrior("kiriya", "Kiriya Aura-Veloz", LUTADOR, "Rare", 6),
	warrior("kou", "Kou Escudo-Alegre", HEROI, "Rare", 8),

	-- Épico (20–40 $/s)
	warrior("nagiri", "Nagiri Névoa-Negra", NINJA, "Epic", 28),
	warrior("brasa_salgada", "Capitão Brasa-Salgada", PIRATA, "Epic", 20),
	warrior("rokubei", "Rokubei Lança-Uivante", CACADOR, "Epic", 36),
	warrior("kagen", "Kagen Runa-Partida", FEITICEIRO, "Epic", 24),
	warrior("toraki", "Toraki Chama-Interior", LUTADOR, "Epic", 40),
	warrior("sentaro", "Sentaro Coração-de-Aço", HEROI, "Epic", 32),

	-- Lendário (80–150 $/s)
	warrior("hisoru", "Hisoru Lua-Silenciosa", NINJA, "Legendary", 150),
	warrior("isla", "Isla Tempestade-Rubra", PIRATA, "Legendary", 108),
	warrior("mireya", "Mireya Presa-de-Prata", CACADOR, "Legendary", 94),
	warrior("sayo", "Sayo Espelho-Estelar", FEITICEIRO, "Legendary", 136),
	warrior("hakuro", "Hakuro, o Punho Celeste", LUTADOR, "Legendary", 80),
	warrior("aurora", "Aurora, Guardiã da Cidade", HEROI, "Legendary", 122),

	-- Mítico (300–600 $/s)
	warrior("zenmaru", "Zenmaru, o Vento das Sombras", NINJA, "Mythic", 420),
	warrior("coral_negro", "Rainha Coral-Negro", PIRATA, "Mythic", 600),
	warrior("kaguro", "Kaguro, Caçador de Dragões", CACADOR, "Mythic", 480),
	warrior("zenshi", "Zenshi, Tecelão do Vazio", FEITICEIRO, "Mythic", 300),
	warrior("tenkai", "Tenkai, o Trovão Interior", LUTADOR, "Mythic", 540),
	warrior("solaris", "Solaris, o Titã Radiante", HEROI, "Mythic", 360),

	-- Secreto (1200–2500 $/s)
	warrior("kurotsuki", "Kurotsuki, Mestre das Mil Sombras", NINJA, "Secret", 1980),
	warrior("leviata", "Leviatã, Rei do Abismo Azul", PIRATA, "Secret", 1460),
	warrior("umbra", "Umbra, a Última Caçada", CACADOR, "Secret", 2500),
	warrior("selene", "Selene, Senhora dos Mil Selos", FEITICEIRO, "Secret", 2240),
	warrior("astra", "Astra, a Estrela que Não Se Apaga", LUTADOR, "Secret", 1720),
	warrior("eon", "Eon, o Herói Sem Nome", HEROI, "Secret", 1200),
}

return table.freeze(Warriors)
