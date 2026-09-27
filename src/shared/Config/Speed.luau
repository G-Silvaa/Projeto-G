--!strict

-- Velocidade do jogador. WalkSpeed = min(MaxWalkSpeed, BaseWalkSpeed + Speed * WalkSpeedPerPoint).
-- Speed só cresce treinando na esteira da própria base (SpeedService).
return table.freeze({
	BaseWalkSpeed = 16,
	WalkSpeedPerPoint = 0.5,
	MaxWalkSpeed = 350,

	-- Pontos de Speed por segundo em cima da esteira (antes de multiplicadores).
	GainPerSecond = 1,
	-- Segundos entre checagens de quem está na esteira.
	TrainingTick = 0.5,

	-- Esteira criada pelo servidor quando o Model BaseN não tem um marcador "Treadmill".
	TreadmillSize = Vector3.new(6, 0.4, 10),
	TreadmillColor = Color3.fromRGB(45, 45, 55),
	-- Altura acima do topo da esteira em que o jogador ainda conta como "em cima".
	TreadmillHeight = 7,
})
