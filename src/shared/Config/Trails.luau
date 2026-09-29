--!strict

-- Rastro atrás do jogador quando ele corre (TrailService). O rastro muda com o nível
-- de velocidade treinado (Speed no PlayerData): Tiers[N] vale a partir da velocidade
-- do guardião da fase N (Config/Guardians.Levels), então cada fase que o jogador
-- consegue passar libera um rastro novo. Abaixo de Levels[1], sem rastro.

local Guardians = require(script.Parent:WaitForChild("Guardians"))

export type Tier = {
	Name: string,
	MinSpeed: number, -- nível de velocidade (preenchido com Guardians.Levels)
	Colors: { Color3 }, -- degradê do começo (perto do corpo) ao fim do rastro
	Height: number, -- altura da faixa, a partir dos pés (studs)
	Lifetime: number, -- segundos que cada pedaço do rastro dura (= comprimento)
	LightEmission: number, -- 0..1: quanto brilha
	Particles: Color3?, -- faíscas nos pés enquanto corre (nil = sem)
}

local function tier(
	name: string,
	colors: { Color3 },
	height: number,
	lifetime: number,
	lightEmission: number,
	particles: Color3?
): Tier
	return {
		Name = name,
		MinSpeed = 0,
		Colors = colors,
		Height = height,
		Lifetime = lifetime,
		LightEmission = lightEmission,
		Particles = particles,
	}
end

local rgb = Color3.fromRGB

local Tiers: { Tier } = {
	tier("Vento Branco", { rgb(255, 255, 255), rgb(200, 210, 230) }, 1.2, 0.25, 0.3),
	tier("Folha Verde", { rgb(120, 255, 120), rgb(30, 160, 60) }, 1.5, 0.3, 0.4),
	tier("Correnteza", { rgb(120, 240, 255), rgb(20, 120, 255) }, 1.8, 0.35, 0.5),
	tier("Relâmpago Azul", { rgb(255, 255, 255), rgb(80, 180, 255), rgb(40, 60, 255) }, 2.1, 0.4, 0.7, rgb(150, 220, 255)),
	tier("Chama Violeta", { rgb(255, 150, 255), rgb(170, 60, 255), rgb(80, 0, 160) }, 2.4, 0.45, 0.7, rgb(220, 120, 255)),
	tier("Fogo Solar", { rgb(255, 240, 120), rgb(255, 140, 0), rgb(220, 30, 0) }, 2.7, 0.5, 0.8, rgb(255, 170, 40)),
	tier("Rubi Carmesim", { rgb(255, 120, 120), rgb(230, 0, 40), rgb(90, 0, 20) }, 3, 0.55, 0.8, rgb(255, 60, 80)),
	tier("Aurora", { rgb(120, 255, 170), rgb(60, 220, 255), rgb(170, 80, 255) }, 3.3, 0.6, 0.9, rgb(140, 255, 220)),
	tier("Tempestade Dourada", { rgb(255, 255, 220), rgb(255, 215, 60), rgb(200, 130, 0) }, 3.6, 0.7, 1, rgb(255, 220, 80)),
	tier(
		"Arco-Íris Espiritual",
		{ rgb(255, 60, 60), rgb(255, 160, 40), rgb(255, 240, 60), rgb(60, 255, 100), rgb(60, 200, 255), rgb(150, 80, 255) },
		4,
		0.8,
		1,
		rgb(255, 255, 255)
	),
}

assert(#Tiers == #Guardians.Levels, "Config/Trails: precisa de um rastro por fase (Config/Guardians.Levels)")
for index, info in Tiers do
	info.MinSpeed = Guardians.Levels[index]
	table.freeze(info.Colors)
	table.freeze(info)
end

-- Índice do rastro para um nível de velocidade (0 = sem rastro).
local function tierFor(speed: number): number
	local result = 0
	for index, info in Tiers do
		if speed >= info.MinSpeed then
			result = index
		end
	end
	return result
end

return table.freeze({
	Tiers = table.freeze(Tiers),
	TierFor = tierFor,
	-- Segundos entre checagens (troca de rastro e faíscas liga/desliga).
	UpdateInterval = 0.2,
	-- Velocidade no plano (studs/s) a partir da qual as faíscas aparecem.
	ParticlesMinSpeed = 20,
})
