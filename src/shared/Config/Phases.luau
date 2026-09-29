--!strict

-- Spawn de totens (no código, "scroll") por fase. Phases[N] vale para Workspace.Map.Phases.PhaseN.
-- Weights: peso de cada raridade (Id de Config/Rarities); raridade ausente = nunca aparece.

export type PhaseConfig = {
	Weights: { [string]: number },
	MaxScrolls: number, -- máximo de totens no chão ao mesmo tempo
	SpawnInterval: number, -- segundos entre tentativas de spawn
}

export type LegendaryEventConfig = {
	IntervalSeconds: number,
	Phases: { number }, -- fases onde o totem do evento pode aparecer
	Weights: { [string]: number },
}

local function phase(maxScrolls: number, weights: { [string]: number }): PhaseConfig
	return table.freeze({
		Weights = table.freeze(weights),
		MaxScrolls = maxScrolls,
		SpawnInterval = 10,
	})
end

local Phases: { PhaseConfig } = {
	phase(8, { Common = 90, Rare = 10 }),
	phase(8, { Common = 75, Rare = 22, Epic = 3 }),
	phase(7, { Common = 60, Rare = 30, Epic = 9, Legendary = 1 }),
	phase(7, { Common = 45, Rare = 35, Epic = 16, Legendary = 4 }),
	phase(6, { Common = 30, Rare = 38, Epic = 24, Legendary = 7, Mythic = 1 }),
	phase(6, { Common = 20, Rare = 35, Epic = 30, Legendary = 12, Mythic = 3 }),
	phase(5, { Common = 10, Rare = 30, Epic = 35, Legendary = 18, Mythic = 6, Secret = 1 }),
	phase(5, { Common = 5, Rare = 20, Epic = 38, Legendary = 25, Mythic = 10, Secret = 2 }),
	phase(4, { Rare = 12, Epic = 35, Legendary = 33, Mythic = 16, Secret = 4 }),
	phase(4, { Rare = 5, Epic = 30, Legendary = 38, Mythic = 20, Secret = 7 }),
}

-- Totem lendário+ de tempos em tempos numa fase final, com aviso no chat.
-- Não conta no MaxScrolls da fase.
local LegendaryEvent: LegendaryEventConfig = table.freeze({
	IntervalSeconds = 5 * 60,
	Phases = table.freeze({ 8, 9, 10 }),
	Weights = table.freeze({ Legendary = 75, Mythic = 20, Secret = 5 }),
})

-- Os totens nascem em volta do posto do guardião da fase (Workspace.Map.Guardians.GuardianN),
-- entre MinDistance e Radius studs dele, pra ele ter o que defender. Fase sem
-- guardião: em qualquer ponto da fase.
local GuardianSpawn = table.freeze({
	MinDistance = 6,
	Radius = 25,
})

return table.freeze({
	Phases = table.freeze(Phases),
	LegendaryEvent = LegendaryEvent,
	GuardianSpawn = GuardianSpawn,
	-- Totem que caiu no chão (guardião pegou quem carregava) e ninguém buscou nesse
	-- tempo volta sozinho pra perto do guardião.
	DroppedTimeout = 30,
})
