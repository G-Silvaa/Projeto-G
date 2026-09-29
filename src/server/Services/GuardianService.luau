--!strict

-- Guardiões das fases: NPCs montados no Studio em Workspace.Map.Guardians (a fase de
-- cada um é a do volume onde ele está; ver BaseService). A posição inicial é o posto.
-- Cada guardião tem um nível de velocidade (Config/Guardians.Levels), na mesma escala
-- do jogador: a velocidade real sai de Config/Speed.RealSpeed.
-- Comportamento, decidido no servidor a cada Config/Guardians.UpdateInterval:
--   - Descanso: no posto, sem nada pra fazer, senta no chão com 💤 na cabeça.
--   - Acordando: apareceu alguém com totem na fase dele: "!" e, WakeDelay segundos
--     depois, levanta.
--   - Perseguição: quem carrega um totem DA FASE DELE, por todo o corredor, até a
--     pessoa passar do começo da fase 1 (lá ela escapou). Quem tem velocidade menor
--     que a do guardião é perseguido a ChaseAdvantage × a velocidade real dela (não
--     escapa); quem tem igual ou maior, na velocidade real do guardião (escapa).
--   - Captura: o jogador é arremessado (sem dano) e o totem cai no chão ali.
--   - Busca: vai até o totem caído, pega (animação), leva na mão até o posto e
--     coloca no chão na frente dele. Qualquer jogador pode pegar o totem caído antes.
--   - Volta: sem nada pra fazer, anda de volta ao posto e descansa de novo.
-- Animações (Config/Guardians.Animations) tocadas pelo servidor no Animator.
-- Scripts e letreiros que vierem dentro dos NPCs são removidos.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GuardiansConfig = require(Config:WaitForChild("Guardians"))
local SpeedConfig = require(Config:WaitForChild("Speed"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BaseService = require(script.Parent.BaseService)
local ScrollService = require(script.Parent.ScrollService)
local SpeedService = require(script.Parent.SpeedService)
local TotemService = require(script.Parent.TotemService)

local GuardianService = {}

-- Quanto do giro é feito por atualização (1 = vira de uma vez).
local TURN_LERP = 0.5
-- Abaixo deste ângulo (cosseno) ele já está olhando para o lugar certo.
local FACING_DOT = 0.99
local ALERT_MAX_DISTANCE = 150
local ALERT_COLOR = Color3.fromRGB(255, 210, 40)
local CHASE_COLOR = Color3.fromRGB(255, 50, 50)
local SLEEP_COLOR = Color3.fromRGB(190, 220, 255)

-- Acima desta velocidade no plano (studs/s) ele está andando.
local MOVING_SPEED = 0.5
-- A corrida foi feita pra ~16 studs/s; mais rápido, as pernas aceleram até RUN_MAX_PLAYBACK×.
local RUN_BASE_SPEED = 16
local RUN_MAX_PLAYBACK = 3
local ANIMATION_FADE = 0.2

-- Orientação das juntas do R6 padrão do Roblox, relativa ao tronco: centro (raiz e
-- pescoço), lado direito e lado esquerdo. As animações R6 giram em torno delas.
local R6_CENTER = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
local R6_RIGHT = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local R6_LEFT = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
local R6_BODY = { "Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }

type AlertState = "None" | "Sleep" | "Alert" | "Chase"

type Tracks = {
	idle: AnimationTrack?,
	run: AnimationTrack?,
	pickup: AnimationTrack?,
	hold: AnimationTrack?,
	sit: AnimationTrack?,
}

-- Totem que o guardião está levando de volta ao posto.
type Held = {
	taken: ScrollService.TakenTotem,
	model: Model,
}

type Guardian = {
	phase: number,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	post: CFrame, -- CFrame inicial do HumanoidRootPart
	home: CFrame, -- pivot inicial do modelo (pra teleportar de volta)
	level: number, -- velocidade do guardião (o número da tela, ex.: 7M)
	maxSpeed: number, -- velocidade real (studs/s) correspondente
	returnSpeed: number,
	fetchSpeed: number,
	chaseStartedAt: number?,
	cooldownUntil: number,
	alertLabel: TextLabel,
	alertGui: BillboardGui,
	alertState: AlertState,
	tracks: Tracks,
	moving: boolean,
	hand: BasePart, -- onde o totem fica quando ele carrega
	held: Held?,
	-- Pegando ou soltando um totem: fica parado até actionUntil e então roda onActionDone.
	actionUntil: number,
	onActionDone: (() -> ())?,
	resting: boolean,
	wakeAt: number?, -- acordando: levanta nesse horário
	restDrop: number, -- quanto o corpo desce ao sentar no chão
	bodyRadius: number, -- metade da largura do tronco (guardião grande alcança mais longe)
	bodyHeight: number, -- altura do modelo (tolerância vertical da captura)
}

local guardians: { Guardian } = {}

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function createAlertGui(model: Model, root: BasePart): (BillboardGui, TextLabel)
	local head = model:FindFirstChild("Head")
	local adornee = if head and head:IsA("BasePart") then head else root

	local gui = Instance.new("BillboardGui")
	gui.Name = "GuardianAlert"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(40, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, adornee.Size.Y / 2 + 2, 0)
	gui.MaxDistance = ALERT_MAX_DISTANCE
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = "!"
	label.TextColor3 = ALERT_COLOR
	label.TextStrokeTransparency = 0
	label.Parent = gui

	return gui, label
end

local function setAlert(guardian: Guardian, state: AlertState)
	if guardian.alertState == state then
		return
	end
	guardian.alertState = state
	guardian.alertGui.Enabled = state ~= "None"
	guardian.alertLabel.Text = if state == "Chase" then "!!" elseif state == "Sleep" then "💤" else "!"
	guardian.alertLabel.TextColor3 = if state == "Chase"
		then CHASE_COLOR
		elseif state == "Sleep" then SLEEP_COLOR
		else ALERT_COLOR
end

-- Modelo da Loja pode trazer script (até malicioso), e o Animate dele brigaria com
-- as animações daqui. Scripts no Workspace já rodam quando o jogo abre, antes deste
-- serviço: o warn pede pra apagar no Studio também.
local function removeScripts(model: Model, path: string)
	local names: { string } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
			table.insert(names, `{descendant.Name} ({descendant.ClassName})`)
			descendant:Destroy()
		end
	end
	if #names > 0 then
		warn(
			`[GuardianService] Scripts removidos de {path}: {table.concat(names, ", ")}. `
				.. "Eles chegaram a rodar ao abrir o jogo; apague-os no Studio."
		)
	end
end

-- Letreiro de nome que veio com o modelo (ex.: nome de personagem de outro jogo).
-- O nome do guardião é o DisplayName do Humanoid, definido aqui.
local function removeLabels(model: Model, path: string)
	local texts: { string } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BillboardGui") then
			local label = descendant:FindFirstChildWhichIsA("TextLabel", true)
			table.insert(texts, if label then `'{label.Text}'` else descendant.Name)
			descendant:Destroy()
		end
	end
	if #texts > 0 then
		warn(`[GuardianService] Letreiros removidos de {path}: {table.concat(texts, ", ")}; apague-os no Studio também`)
	end
end

local function bodyPart(model: Model, name: string): BasePart?
	local part = model:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

-- Estátua R6 (peças soltas ou soldadas, sem HumanoidRootPart): monta o rig do jeito
-- do R6 padrão, na pose em que ela está. Chapéu, barba e outras peças extras ficam
-- presas na cabeça (ou no tronco), sem colisão e sem massa. Devolve o
-- HumanoidRootPart, ou nil se não der.
local function rigStatue(model: Model, humanoid: Humanoid, path: string): BasePart?
	local existing = bodyPart(model, "HumanoidRootPart")
	if existing then
		return existing
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		warn(`[GuardianService] {path} não tem HumanoidRootPart e não é R6; fase sem guardião`)
		return nil
	end
	local body: { [string]: BasePart } = {}
	for _, name in R6_BODY do
		local part = bodyPart(model, name)
		if part == nil then
			warn(`[GuardianService] {path} não tem HumanoidRootPart nem a peça '{name}'; não dá pra montar o rig`)
			return nil
		end
		body[name] = part
	end
	local torso, head = body.Torso, body.Head

	-- Soldas antigas travariam o corpo (ou prenderiam peças no lugar errado).
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		end
	end

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = torso.Size
	root.CFrame = torso.CFrame
	root.Transparency = 1
	root.CanCollide = false
	root.Parent = model
	model.PrimaryPart = root

	-- pivot: onde fica a junta, no espaço de part0. C1 sai da pose atual de part1.
	local function joint(name: string, part0: BasePart, part1: BasePart, pivot: CFrame)
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = pivot
		motor.C1 = part1.CFrame:ToObjectSpace(part0.CFrame * pivot)
		motor.Parent = part0
	end
	local halfX, halfY = torso.Size.X / 2, torso.Size.Y / 2
	joint("RootJoint", root, torso, R6_CENTER)
	joint("Neck", torso, head, CFrame.new(0, halfY, 0) * R6_CENTER)
	joint("Right Shoulder", torso, body["Right Arm"], CFrame.new(halfX, halfY / 2, 0) * R6_RIGHT)
	joint("Left Shoulder", torso, body["Left Arm"], CFrame.new(-halfX, halfY / 2, 0) * R6_LEFT)
	joint("Right Hip", torso, body["Right Leg"], CFrame.new(halfX, -halfY, 0) * R6_RIGHT)
	joint("Left Hip", torso, body["Left Leg"], CFrame.new(-halfX, -halfY, 0) * R6_LEFT)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root and not table.find(R6_BODY, descendant.Name) then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = if descendant.Position.Y > torso.Position.Y + halfY then head else torso
			weld.Part1 = descendant
			weld.Parent = descendant
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end

	warn(`[GuardianService] {path} era uma estátua (sem HumanoidRootPart); o servidor montou o rig R6 dele`)
	return root
end

local function loadTrack(
	animator: Animator,
	id: string,
	priority: Enum.AnimationPriority,
	looped: boolean,
	path: string
): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, result = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		warn(`[GuardianService] {path}: não deu pra carregar a animação {id} ({result})`)
		return nil
	end
	local track = result :: AnimationTrack
	track.Priority = priority
	track.Looped = looped
	return track
end

-- Tracks no Animator do Humanoid (criado se faltar), com as animações do tipo de rig
-- (Config/Guardians.Animations). Tocadas no servidor, replicam para todos.
local function setupAnimations(humanoid: Humanoid, path: string): Tracks
	local ids = GuardiansConfig.Animations[humanoid.RigType.Name]
	if ids == nil then
		warn(`[GuardianService] {path}: rig {humanoid.RigType.Name} sem animação em Config/Guardians.Animations`)
		return {}
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local found = animator :: Animator
	-- Algo que o script removido tenha deixado tocando.
	for _, playing in found:GetPlayingAnimationTracks() do
		playing:Stop(0)
	end

	local tracks: Tracks = {
		idle = loadTrack(found, ids.Idle, Enum.AnimationPriority.Idle, true, path),
		run = loadTrack(found, ids.Run, Enum.AnimationPriority.Movement, true, path),
		pickup = loadTrack(found, ids.Pickup, Enum.AnimationPriority.Action, false, path),
		hold = loadTrack(found, ids.Hold, Enum.AnimationPriority.Action, true, path),
		sit = loadTrack(found, ids.Sit, Enum.AnimationPriority.Movement, true, path),
	}
	if tracks.idle then
		tracks.idle:Play()
	end
	return tracks
end

-- Troca parado/corrida pela velocidade real (inclusive quando é empurrado).
local function updateAnimation(guardian: Guardian)
	if guardian.resting then
		return
	end
	local velocity = guardian.root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = speed > MOVING_SPEED
	local idle, run = guardian.tracks.idle, guardian.tracks.run

	if moving ~= guardian.moving then
		guardian.moving = moving
		if moving then
			if idle then
				idle:Stop(ANIMATION_FADE)
			end
			if run then
				run:Play(ANIMATION_FADE)
			end
		else
			if run then
				run:Stop(ANIMATION_FADE)
			end
			if idle then
				idle:Play(ANIMATION_FADE)
			end
		end
	end
	if moving and run then
		run:AdjustSpeed(math.clamp(speed / RUN_BASE_SPEED, 1, RUN_MAX_PLAYBACK))
	end
end

local function setupGuardian(phase: number, model: Model, post: CFrame): Guardian?
	local path = `Workspace.Map.Guardians.{model.Name}`
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		warn(`[GuardianService] {path} precisa ter Humanoid; fase {phase} sem guardião`)
		return nil
	end
	local level = GuardiansConfig.Levels[phase]
	if level == nil then
		warn(`[GuardianService] Config/Guardians.Levels não tem nível para a fase {phase}; fase sem guardião`)
		return nil
	end
	local maxSpeed = SpeedConfig.RealSpeed(level)
	removeScripts(model, path)
	removeLabels(model, path)
	local root = rigStatue(model, humanoid, path)
	if root == nil then
		return nil
	end

	-- No Studio as peças podem ficar ancoradas (pra não cair na edição); no jogo, não.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.BreakJointsOnDeath = false
	-- NPC da Loja pode vir com nome de personagem de anime; o jogo só usa nomes próprios.
	-- O nível fica à mostra pra o jogador saber quanto precisa treinar.
	humanoid.DisplayName = `Guardião da fase {phase} · ⚡ {Format.number(level)}`
	humanoid.WalkSpeed = maxSpeed
	-- Dá erro se o NPC estiver soldado a algo ancorado do mapa; aí só avisamos.
	local ok, err = pcall(function()
		root:SetNetworkOwner(nil)
	end)
	if not ok then
		warn(`[GuardianService] {path}: não deu para passar a física pro servidor ({err}); ele está preso a algo ancorado?`)
	end

	local alertGui, alertLabel = createAlertGui(model, root)
	local tracks = setupAnimations(humanoid, path)
	local _, boxSize = model:GetBoundingBox()
	local hand = bodyPart(model, "RightHand") or bodyPart(model, "Right Arm") or root
	-- Sentado, o quadril fica na altura da espessura da perna deitada: desce o
	-- comprimento da perna menos metade da espessura (no R15, ~80% da HipHeight).
	local leg = bodyPart(model, "Right Leg")
	local restDrop = if leg then leg.Size.Y - leg.Size.Z / 2 else humanoid.HipHeight * 0.8

	return {
		phase = phase,
		model = model,
		humanoid = humanoid,
		root = root,
		post = post,
		home = model:GetPivot(),
		level = level,
		maxSpeed = maxSpeed,
		returnSpeed = math.max(GuardiansConfig.ReturnMinSpeed, maxSpeed * GuardiansConfig.ReturnSpeedFactor),
		fetchSpeed = maxSpeed * GuardiansConfig.FetchSpeedFactor,
		chaseStartedAt = nil,
		cooldownUntil = 0,
		alertLabel = alertLabel,
		alertGui = alertGui,
		alertState = "None",
		tracks = tracks,
		moving = false,
		hand = hand,
		held = nil,
		actionUntil = 0,
		onActionDone = nil,
		resting = false,
		wakeAt = nil,
		restDrop = restDrop + GuardiansConfig.RestExtraDrop,
		bodyRadius = root.Size.X / 2,
		bodyHeight = boxSize.Y,
	}
end

-- Os NPCs e os postos vêm do BaseService, que lê Workspace.Map.Guardians (e avisa
-- sobre nome errado ou fase sem guardião).
local function loadGuardians()
	for phase = 1, BaseService:GetPhaseCount() do
		local model = BaseService:GetGuardian(phase)
		local post = BaseService:GetGuardianPost(phase)
		if model and post then
			local guardian = setupGuardian(phase, model, post)
			if guardian then
				table.insert(guardians, guardian)
			end
		end
	end
end

local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Quem carrega um totem da fase do guardião e ainda não passou do começo da fase 1
-- (o mais perto dele), ou nil.
local function nearestThief(guardian: Guardian): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, player in ScrollService:GetCarriers() do
		local root = aliveRoot(player)
		if
			root
			and ScrollService:GetCarriedPhase(player) == guardian.phase
			and not BaseService:IsBeforeFirstPhase(root.Position)
		then
			local distance = (root.Position - guardian.root.Position).Magnitude
			if distance <= bestDistance then
				best = root
				bestDistance = distance
			end
		end
	end
	return best
end

-- Gira aos poucos, sem mexer na posição.
local function turnTowards(guardian: Guardian, direction: Vector3)
	local look = flat(direction)
	if look.Magnitude < 1e-3 then
		return
	end
	look = look.Unit
	local current = flat(guardian.root.CFrame.LookVector)
	if current.Magnitude > 1e-3 and current.Unit:Dot(look) >= FACING_DOT then
		return
	end
	local position = guardian.root.Position
	guardian.root.CFrame = guardian.root.CFrame:Lerp(CFrame.lookAt(position, position + look), TURN_LERP)
end

-- O LinearVelocity replica e quem simula o personagem (o cliente dono) aplica o empurrão.
local function knockback(guardian: Guardian, targetRoot: BasePart)
	local away = flat(targetRoot.Position - guardian.root.Position)
	if away.Magnitude < 0.1 then
		away = -guardian.root.CFrame.LookVector
	end
	local velocity = away.Unit * GuardiansConfig.KnockbackSpeed + Vector3.new(0, GuardiansConfig.KnockbackUp, 0)

	local attachment = Instance.new("Attachment")
	attachment.Name = "GuardianKnockback"
	attachment.Parent = targetRoot

	local push = Instance.new("LinearVelocity")
	push.Name = "GuardianKnockback"
	push.Attachment0 = attachment
	-- Força grande e finita: infinito em física pode dar problema.
	push.MaxForce = 1e7
	push.VectorVelocity = velocity
	push.Parent = targetRoot

	Debris:AddItem(push, GuardiansConfig.KnockbackDuration)
	Debris:AddItem(attachment, GuardiansConfig.KnockbackDuration)
end

-- Caiu do mapa ou foi arrastado pra longe demais: volta pro posto na hora.
local function resetIfLost(guardian: Guardian): boolean
	local position = guardian.root.Position
	local post = guardian.post.Position
	if position.Y > post.Y - GuardiansConfig.FallDistance and (position - post).Magnitude < GuardiansConfig.ResetDistance then
		return false
	end
	guardian.model:PivotTo(guardian.home)
	guardian.root.AssemblyLinearVelocity = Vector3.zero
	guardian.root.AssemblyAngularVelocity = Vector3.zero
	guardian.humanoid:MoveTo(post)
	guardian.chaseStartedAt = nil
	return true
end

-- Velocidade de perseguição. Alvo com velocidade (o número) menor que a do guardião:
-- ChaseAdvantage × a velocidade real dele, na hora (não escapa). Senão, a do
-- guardião, acelerando de ChaseStartFactor até ela em ChaseRampSeconds.
local function chaseSpeed(guardian: Guardian, targetRoot: BasePart, now: number): number
	local player = Players:GetPlayerFromCharacter(targetRoot.Parent)
	local humanoid = if targetRoot.Parent then targetRoot.Parent:FindFirstChildOfClass("Humanoid") else nil
	if player and humanoid and SpeedService:GetSpeed(player) < guardian.level then
		return math.max(guardian.maxSpeed, humanoid.WalkSpeed * GuardiansConfig.ChaseAdvantage)
	end

	local startedAt = guardian.chaseStartedAt or now
	local ramp = if GuardiansConfig.ChaseRampSeconds > 0
		then math.clamp((now - startedAt) / GuardiansConfig.ChaseRampSeconds, 0, 1)
		else 1
	return guardian.maxSpeed * (GuardiansConfig.ChaseStartFactor + (1 - GuardiansConfig.ChaseStartFactor) * ramp)
end

local function chase(guardian: Guardian, targetRoot: BasePart, now: number)
	guardian.chaseStartedAt = guardian.chaseStartedAt or now
	local speed = chaseSpeed(guardian, targetRoot, now)
	guardian.humanoid.WalkSpeed = speed
	setAlert(guardian, "Chase")

	-- Nas fases rápidas ele anda muito entre duas checagens: o raio cresce junto.
	-- Medido no chão (a partir da borda do tronco) e com tolerância da altura dele:
	-- num guardião grande, o centro do corpo fica bem acima do jogador.
	local catchDistance = math.max(GuardiansConfig.CatchDistance, speed * GuardiansConfig.UpdateInterval * 0.5)
	local offset = targetRoot.Position - guardian.root.Position
	if flat(offset).Magnitude > catchDistance + guardian.bodyRadius or math.abs(offset.Y) > guardian.bodyHeight then
		guardian.humanoid:MoveTo(targetRoot.Position)
		return
	end

	local player = Players:GetPlayerFromCharacter(targetRoot.Parent)
	if player then
		ScrollService:KnockDrop(player, targetRoot.Position)
		knockback(guardian, targetRoot)
		Remotes.getEvent(Remotes.Events.Notify):FireClient(player, "O guardião te pegou e derrubou o totem!")
	end
	guardian.cooldownUntil = now + GuardiansConfig.CatchCooldown
	guardian.chaseStartedAt = nil
end

-- Senta no chão do posto (ancorado, pra ninguém empurrar) com 💤 na cabeça.
local function rest(guardian: Guardian)
	if guardian.resting then
		return
	end
	guardian.resting = true
	guardian.wakeAt = nil
	guardian.moving = false
	guardian.humanoid:Move(Vector3.zero)
	local tracks = guardian.tracks
	for _, track in { tracks.idle, tracks.run } do
		if track then
			track:Stop(ANIMATION_FADE)
		end
	end
	if tracks.sit then
		tracks.sit:Play(ANIMATION_FADE)
	end
	guardian.root.Anchored = true
	guardian.model:PivotTo(CFrame.new(0, -guardian.restDrop, 0) * guardian.home)
	setAlert(guardian, "Sleep")
end

-- Levanta no posto e volta a ter física (do servidor).
local function wakeUp(guardian: Guardian)
	guardian.resting = false
	guardian.wakeAt = nil
	local tracks = guardian.tracks
	if tracks.sit then
		tracks.sit:Stop(ANIMATION_FADE)
	end
	if tracks.idle then
		tracks.idle:Play(ANIMATION_FADE)
	end
	guardian.model:PivotTo(guardian.home)
	guardian.root.Anchored = false
	pcall(function()
		guardian.root:SetNetworkOwner(nil)
	end)
	setAlert(guardian, "None")
end

-- Tem motivo pra acordar: alguém levando um totem da fase dele, ou totem dela caído.
local function hasWork(guardian: Guardian): boolean
	return nearestThief(guardian) ~= nil or #ScrollService:GetDropped(guardian.phase) > 0
end

-- Para e toca a animação de pegar/soltar; done roda quando ela termina.
local function startAction(guardian: Guardian, now: number, done: () -> ())
	guardian.humanoid:Move(Vector3.zero)
	local pickup = guardian.tracks.pickup
	if pickup then
		pickup:Play(0.1)
	end
	guardian.actionUntil = now + GuardiansConfig.PickupSeconds
	guardian.onActionDone = done
end

local function holdTotem(guardian: Guardian, taken: ScrollService.TakenTotem)
	local model = TotemService:Create(taken.rarity, GuardiansConfig.HandTotemHeight, false)
	-- Na mão, em pé quando o braço está esticado pra frente (pose de segurar).
	local offset = CFrame.new(0, -guardian.hand.Size.Y / 2, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	if not TotemService:AttachTo(model, guardian.hand, offset) then
		model:Destroy()
		ScrollService:PutBack(taken, nil)
		return
	end
	model.Parent = guardian.model
	guardian.held = { taken = taken, model = model }
	if guardian.tracks.hold then
		guardian.tracks.hold:Play(ANIMATION_FADE)
	end
end

local function releaseTotem(guardian: Guardian)
	local held = guardian.held
	if held == nil then
		return
	end
	guardian.held = nil
	held.model:Destroy()
	if guardian.tracks.hold then
		guardian.tracks.hold:Stop(ANIMATION_FADE)
	end
	local post = guardian.post
	ScrollService:PutBack(held.taken, post.Position + post.LookVector * GuardiansConfig.PlaceDistance)
end

local function reach(guardian: Guardian): number
	return guardian.bodyRadius + GuardiansConfig.PickupReach
end

-- Totem caído mais perto na fase dele, ou nil.
local function nearestDropped(guardian: Guardian): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, hitbox in ScrollService:GetDropped(guardian.phase) do
		local distance = (hitbox.Position - guardian.root.Position).Magnitude
		if distance < bestDistance then
			best = hitbox
			bestDistance = distance
		end
	end
	return best
end

-- Vai até o totem caído e, perto, pega (se ninguém tiver pegado antes).
local function fetch(guardian: Guardian, hitbox: BasePart, now: number)
	guardian.humanoid.WalkSpeed = guardian.fetchSpeed
	setAlert(guardian, "None")
	if flat(hitbox.Position - guardian.root.Position).Magnitude > reach(guardian) then
		guardian.humanoid:MoveTo(hitbox.Position)
		return
	end
	startAction(guardian, now, function()
		local taken = ScrollService:TakeDropped(hitbox)
		if taken then
			holdTotem(guardian, taken)
		end
	end)
end

local function updateGuardian(guardian: Guardian, now: number)
	-- Descansando: só olha se há motivo pra acordar; levanta WakeDelay depois.
	if guardian.resting then
		local wakeAt = guardian.wakeAt
		if wakeAt == nil then
			if hasWork(guardian) then
				guardian.wakeAt = now + GuardiansConfig.WakeDelay
				setAlert(guardian, "Alert")
			end
			return
		end
		if now < wakeAt then
			return
		end
		wakeUp(guardian)
	end

	updateAnimation(guardian)
	if resetIfLost(guardian) then
		return
	end

	-- Pegando ou soltando: espera a animação.
	if now < guardian.actionUntil then
		guardian.humanoid:Move(Vector3.zero)
		return
	end
	local done = guardian.onActionDone
	if done then
		guardian.onActionDone = nil
		done()
	end

	if now >= guardian.cooldownUntil then
		local target = nearestThief(guardian)
		if target then
			chase(guardian, target, now)
			return
		end
	end

	guardian.chaseStartedAt = nil

	-- De mãos livres, busca o totem caído mais perto.
	if guardian.held == nil then
		local dropped = nearestDropped(guardian)
		if dropped then
			fetch(guardian, dropped, now)
			return
		end
	end

	-- Sem alvo: volta ao posto (levando o totem, se tiver) e lá descansa.
	guardian.humanoid.WalkSpeed = guardian.returnSpeed
	setAlert(guardian, "None")

	local offset = flat(guardian.root.Position - guardian.post.Position)
	if offset.Magnitude > GuardiansConfig.PostTolerance then
		guardian.humanoid:MoveTo(guardian.post.Position)
		return
	end

	-- No posto com o totem na mão: coloca no chão na frente dele.
	if guardian.held then
		turnTowards(guardian, guardian.post.LookVector)
		startAction(guardian, now, function()
			releaseTotem(guardian)
		end)
		return
	end

	rest(guardian)
end

function GuardianService:Start()
	loadGuardians()
	-- Todos começam descansando no posto.
	for _, guardian in guardians do
		rest(guardian)
	end

	task.spawn(function()
		while true do
			task.wait(GuardiansConfig.UpdateInterval)
			local now = os.clock()
			for _, guardian in guardians do
				-- Erro com um guardião não pode parar os outros.
				local ok, err = pcall(updateGuardian, guardian, now)
				if not ok then
					warn(`[GuardianService] Erro no guardião da fase {guardian.phase}: {err}`)
				end
			end
		end
	end)
end

return GuardianService
