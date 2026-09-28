--!strict

-- Guardiões das fases (NPCs montados no Studio em Workspace.Map.Guardians.GuardianN).
-- Speeds[N] é a velocidade MÁXIMA de perseguição do guardião da PhaseN: ele começa
-- mais devagar e acelera até ela (ChaseStartFactor, ChaseRampSeconds).
-- Referência: o jogador anda a 16 sem treino e no máximo a 350 (ver Config/Speed).
return table.freeze({
	Speeds = table.freeze({ 14, 18, 24, 32, 45, 60, 85, 120, 170, 250 }),

	-- Segundos entre atualizações (menor = mais preciso, mais caro).
	UpdateInterval = 0.15,

	-- Alerta: jogador na fase, sem totem, a até esta distância. O guardião vira para
	-- ele e mostra um "!" amarelo.
	AlertDistance = 30,

	-- Perseguição (só quem carrega totem dentro da fase dele): começa em
	-- ChaseStartFactor × Speeds[N] e chega em Speeds[N] depois de ChaseRampSeconds.
	ChaseStartFactor = 0.6,
	ChaseRampSeconds = 3,

	-- Distância mínima de captura; nas fases rápidas ela cresce com a velocidade.
	CatchDistance = 5,
	-- Arremesso: velocidade horizontal e vertical aplicadas por KnockbackDuration segundos.
	KnockbackSpeed = 120,
	KnockbackUp = 60,
	KnockbackDuration = 0.25,
	-- Depois de pegar alguém, o guardião volta ao posto e ignora alvos por este tempo.
	CatchCooldown = 2,

	-- Volta ao posto a ReturnSpeedFactor × Speeds[N], nunca abaixo de ReturnMinSpeed.
	ReturnSpeedFactor = 0.5,
	ReturnMinSpeed = 16,
	-- Distância do posto a partir da qual ele volta andando.
	PostTolerance = 2,
	-- Segurança: mais longe que isso do posto, ou caído mais que FallDistance abaixo
	-- dele, o guardião é teleportado de volta.
	ResetDistance = 400,
	FallDistance = 50,
})
