--!strict

-- Velocidade do jogador. Speed (salvo no PlayerData) é o NÍVEL de velocidade: o
-- número que aparece na tela, que chega a bilhões. A velocidade real (WalkSpeed, em
-- studs/s) sai do nível por RealSpeed, numa escala logarítmica, a mesma dos
-- guardiões (Config/Guardians.Levels): nível maior = mais rápido de verdade, e a
-- física nunca passa de MaxWalkSpeed.
-- Speed só cresce treinando na esteira da própria base (SpeedService).

local Speed = {
	-- Velocidade real com nível 0.
	BaseWalkSpeed = 16,
	-- Quanto a velocidade real sobe cada vez que o nível fica 10x maior.
	WalkSpeedPerDecade = 28,
	-- Suaviza o começo: com nível LevelScale, a velocidade real sobe ~8.
	LevelScale = 10,
	-- Teto de segurança da velocidade real (acima disso a física do Roblox fica instável).
	MaxWalkSpeed = 400,

	-- Treino: por segundo em cima da esteira ganha max(MinGainPerSecond, nível ×
	-- GainPercentPerSecond), vezes os multiplicadores (upgrades, Game Pass). Como o
	-- ganho é uma porcentagem do nível, ele cresce cada vez mais rápido.
	MinGainPerSecond = 1,
	GainPercentPerSecond = 0.01,
	-- Nível máximo (só pra nunca virar infinito).
	MaxLevel = 1e18,
	-- Segundos entre checagens de quem está na esteira.
	TrainingTick = 0.5,

	-- Esteira criada pelo servidor quando o Model BaseN não tem um marcador "Treadmill".
	TreadmillSize = Vector3.new(6, 0.4, 10),
	TreadmillColor = Color3.fromRGB(45, 45, 55),
	-- Altura acima do topo da esteira em que o jogador ainda conta como "em cima".
	TreadmillHeight = 7,
}

-- Velocidade real (studs/s) de um nível. Nível 900 → ~71, 10K → ~100, 20B → ~276.
function Speed.RealSpeed(level: number): number
	local decades = math.log10(1 + math.max(level, 0) / Speed.LevelScale)
	return math.min(Speed.BaseWalkSpeed + Speed.WalkSpeedPerDecade * decades, Speed.MaxWalkSpeed)
end

return table.freeze(Speed)
