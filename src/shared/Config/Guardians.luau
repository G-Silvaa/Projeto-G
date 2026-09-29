--!strict

-- Guardiões das fases (NPCs montados no Studio em Workspace.Map.Guardians).
-- Levels[N] é a VELOCIDADE do guardião da fase N: o mesmo número que o jogador vê e
-- treina na esteira (Config/Speed). Pra levar um totem da fase N, o jogador precisa
-- ter velocidade >= Levels[N]; com menos, o guardião corre ChaseAdvantage × mais
-- rápido que ele e sempre alcança. A velocidade real (studs/s) sai de
-- Speed.RealSpeed: 900 ≈ 71, 10K ≈ 100, 3M ≈ 169, 20B ≈ 276.
-- O guardião só persegue quem pegou totem da fase dele, até a pessoa passar do
-- começo da fase 1.
return table.freeze({
	Levels = table.freeze({
		900,
		10_000,
		40_000,
		170_000,
		700_000,
		3_000_000,
		18_000_000,
		700_000_000,
		7_000_000_000,
		20_000_000_000,
	}),

	-- Segundos entre atualizações (menor = mais preciso, mais caro).
	UpdateInterval = 0.15,

	-- Descanso: no posto, sem nada pra fazer, ele senta no chão (animação Sit) com um
	-- 💤 na cabeça e ninguém o acorda chegando perto. Quando aparece alguém com totem
	-- na fase dele, o 💤 vira "!" e ele levanta WakeDelay segundos depois.
	WakeDelay = 0.5,
	-- Ajuste fino da altura sentado (studs; positivo = mais baixo), se ficar flutuando
	-- ou afundando no chão.
	RestExtraDrop = 0,

	-- Alvo mais lento que o guardião (velocidade menor que Levels[N]): ele corre
	-- ChaseAdvantage × a velocidade real do alvo, desde o começo.
	ChaseAdvantage = 2,
	-- Alvo tão rápido quanto ou mais: ele corre na própria velocidade real, começando
	-- em ChaseStartFactor dela e chegando nela em ChaseRampSeconds.
	ChaseStartFactor = 0.6,
	ChaseRampSeconds = 3,

	-- Distância mínima de captura; nas fases rápidas ela cresce com a velocidade.
	CatchDistance = 5,
	-- Ao pegar alguém, o totem cai no chão onde a pessoa estava. O guardião vai
	-- buscar (qualquer jogador pode pegar antes), faz a animação de pegar por
	-- PickupSeconds, leva na mão até o posto e coloca no chão a PlaceDistance studs
	-- na frente dele. Totem caído há mais de Config/Phases.DroppedTimeout volta sozinho.
	PickupSeconds = 0.6,
	PlaceDistance = 8,
	-- Alcance pra pegar/soltar: metade da largura do tronco + isto.
	PickupReach = 4,
	-- Velocidade indo buscar o totem caído (fração da velocidade real máxima).
	FetchSpeedFactor = 0.8,
	-- Altura do totem na mão do guardião.
	HandTotemHeight = 5,
	-- Arremesso: velocidade horizontal e vertical aplicadas por KnockbackDuration segundos.
	KnockbackSpeed = 120,
	KnockbackUp = 60,
	KnockbackDuration = 0.25,
	-- Depois de pegar alguém, o guardião volta ao posto e ignora alvos por este tempo.
	CatchCooldown = 2,

	-- Volta ao posto a ReturnSpeedFactor × a velocidade real máxima, nunca abaixo de ReturnMinSpeed.
	ReturnSpeedFactor = 0.5,
	ReturnMinSpeed = 16,
	-- Distância do posto a partir da qual ele volta andando.
	PostTolerance = 2,
	-- Segurança: mais longe que isso do posto, ou caído mais que FallDistance abaixo
	-- dele, o guardião é teleportado de volta.
	-- (maior que o corredor inteiro: ele persegue da fase dele até o começo da fase 1).
	ResetDistance = 8000,
	FallDistance = 50,

	-- Animações tocadas pelo servidor, por tipo de rig (padrão do Roblox). Pickup é o
	-- golpe de ferramenta (parece pegar do chão); Hold é "segurando ferramenta". Pra
	-- usar animações próprias, faça no Animation Editor, publique e troque o ID.
	Animations = table.freeze({
		R15 = table.freeze({
			Idle = "rbxassetid://507766666",
			Run = "rbxassetid://507767714",
			Pickup = "rbxassetid://522635514",
			Hold = "rbxassetid://507768375",
			Sit = "rbxassetid://2506281703",
		}),
		R6 = table.freeze({
			Idle = "rbxassetid://180435571",
			Run = "rbxassetid://180426354",
			Pickup = "rbxassetid://129967390",
			Hold = "rbxassetid://182393478",
			Sit = "rbxassetid://178130996",
		}),
	}),
})
