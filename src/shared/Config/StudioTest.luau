--!strict

-- Modo de teste: só vale dentro do Studio (RunService:IsStudio()).
-- No jogo publicado é sempre ignorado, mesmo com Enabled = true.
return table.freeze({
	Enabled = true,
	-- Velocidade real (studs/s), não nível: 100 equivale a um nível de ~10K.
	WalkSpeed = 100,
	-- Força um rastro (1..10, Config/Trails) para ver como fica; 0 = pelo Speed treinado.
	TrailTier = 0,
})
