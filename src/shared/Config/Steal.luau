--!strict

-- Roubo entre jogadores (StealService).
return table.freeze({
	-- Segundos em que um slot recém-colocado não pode ser roubado.
	ProtectionSeconds = 30,
	-- Segundos entre dois roubos iniciados pelo mesmo jogador.
	CooldownSeconds = 20,
	-- Intervalo mínimo entre tentativas de roubo (rate limit do prompt).
	AttemptRateLimit = 1,
	-- Distância máxima real (studs) entre o ladrão e o slot ao roubar.
	MaxStealDistance = 12,
	-- Se o dono chegar a esta distância do ladrão, o item volta.
	CatchDistance = 6,
	-- Tempo segurando o botão do prompt "Roubar".
	PromptHoldSeconds = 1,
})
