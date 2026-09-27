--!strict

-- Guardiões das fases. Speeds[N] é o WalkSpeed do guardião da PhaseN.
-- Referência: o jogador anda a 16 sem treino (ver Config/Speed).
return table.freeze({
	Speeds = table.freeze({ 14, 18, 24, 32, 45, 60, 85, 120, 170, 250 }),

	-- Segundos entre atualizações de perseguição (menor = mais preciso, mais caro).
	UpdateInterval = 0.15,
	-- Distância mínima de captura; nas fases rápidas ela cresce com a velocidade.
	CatchDistance = 5,
	-- Arremesso: velocidade horizontal e vertical aplicadas por KnockbackDuration segundos.
	KnockbackSpeed = 120,
	KnockbackUp = 60,
	KnockbackDuration = 0.25,
	-- Depois de pegar alguém, o guardião volta ao posto e ignora alvos por este tempo.
	CatchCooldown = 2,
	-- Distância do posto a partir da qual ele volta andando.
	PostTolerance = 2,
})
