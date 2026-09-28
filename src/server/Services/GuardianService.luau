--!strict

-- Guardiões das fases: NPCs (R15 com Humanoid) montados no Studio em
-- Workspace.Map.Guardians.GuardianN, onde N é a fase. A posição inicial de cada um
-- é o posto. Comportamento, decidido no servidor a cada Config/Guardians.UpdateInterval:
--   - Posto: parado, olhando para a direção original.
--   - Alerta: jogador na fase, sem totem, a até AlertDistance: vira para ele e mostra "!".
--   - Perseguição: quem carrega totem dentro da fase dele. Acelera até Speeds[N].
--   - Captura: o totem volta para a fase de origem e o jogador é arremessado (sem dano).
--   - Volta: o alvo saiu da fase, foi pego ou morreu: anda de volta ao posto.
-- Animações de parado e corrida (as padrão do R15) tocadas pelo servidor no Animator,
-- trocadas conforme a velocidade real. Scripts que vierem dentro dos NPCs são removidos.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GuardiansConfig = require(Shared:WaitForChild("Config"):WaitForChild("Guardians"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BaseService = require(script.Parent.BaseService)
local ScrollService = require(script.Parent.ScrollService)

local GuardianService = {}

-- Quanto do giro é feito por atualização (1 = vira de uma vez).
local TURN_LERP = 0.5
-- Abaixo deste ângulo (cosseno) ele já está olhando para o lugar certo.
local FACING_DOT = 0.99
local ALERT_MAX_DISTANCE = 150
local ALERT_COLOR = Color3.fromRGB(255, 210, 40)
local CHASE_COLOR = Color3.fromRGB(255, 50, 50)

-- Animações padrão do R15 (as mesmas do script Animate do Roblox).
local IDLE_ANIMATION = "rbxassetid://507766666"
local RUN_ANIMATION = "rbxassetid://507767714"
-- Acima desta velocidade no plano (studs/s) ele está andando.
local MOVING_SPEED = 0.5
-- A corrida foi feita pra ~16 studs/s; mais rápido, as pernas aceleram até RUN_MAX_PLAYBACK×.
local RUN_BASE_SPEED = 16
local RUN_MAX_PLAYBACK = 3
local ANIMATION_FADE = 0.2

type AlertState = "None" | "Alert" | "Chase"

type Guardian = {
	phase: number,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	post: CFrame, -- CFrame inicial do HumanoidRootPart
	home: CFrame, -- pivot inicial do modelo (pra teleportar de volta)
	maxSpeed: number,
	returnSpeed: number,
	chaseStartedAt: number?,
	cooldownUntil: number,
	alertLabel: TextLabel,
	alertGui: BillboardGui,
	alertState: AlertState,
	idleTrack: AnimationTrack?,
	runTrack: AnimationTrack?,
	moving: boolean,
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
	guardian.alertLabel.Text = if state == "Chase" then "!!" else "!"
	guardian.alertLabel.TextColor3 = if state == "Chase" then CHASE_COLOR else ALERT_COLOR
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

local function loadTrack(animator: Animator, id: string, priority: Enum.AnimationPriority, path: string): AnimationTrack?
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
	track.Looped = true
	return track
end

-- Tracks de parado e corrida no Animator do Humanoid (criado se faltar). Tocadas no
-- servidor, replicam para todos.
local function setupAnimations(humanoid: Humanoid, path: string): (AnimationTrack?, AnimationTrack?)
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn(`[GuardianService] {path} não é R15; fica sem animação`)
		return nil, nil
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

	local idle = loadTrack(found, IDLE_ANIMATION, Enum.AnimationPriority.Idle, path)
	local run = loadTrack(found, RUN_ANIMATION, Enum.AnimationPriority.Movement, path)
	if idle then
		idle:Play()
	end
	return idle, run
end

-- Troca parado/corrida pela velocidade real (inclusive quando é empurrado).
local function updateAnimation(guardian: Guardian)
	local velocity = guardian.root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = speed > MOVING_SPEED
	local idle, run = guardian.idleTrack, guardian.runTrack

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

local function setupGuardian(phase: number, model: Model): Guardian?
	local path = `Workspace.Map.Guardians.{model.Name}`
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		warn(`[GuardianService] {path} precisa ter Humanoid e HumanoidRootPart; fase {phase} sem guardião`)
		return nil
	end
	local maxSpeed = GuardiansConfig.Speeds[phase]
	if maxSpeed == nil then
		warn(`[GuardianService] Config/Guardians não tem velocidade para a fase {phase}; fase sem guardião`)
		return nil
	end
	local volume = BaseService:GetPhasePart(phase)
	if volume == nil then
		warn(`[GuardianService] {path} existe, mas não há Workspace.Map.Phases.Phase{phase}; ignorado`)
		return nil
	end
	if BaseService:GetPhaseAt(root.Position) ~= phase then
		warn(`[GuardianService] {path} está fora do volume Phase{phase}; o posto fica onde ele está`)
	end
	removeScripts(model, path)

	-- No Studio as peças podem ficar ancoradas (pra não cair na edição); no jogo, não.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.BreakJointsOnDeath = false
	humanoid.WalkSpeed = maxSpeed
	-- Dá erro se o NPC estiver soldado a algo ancorado do mapa; aí só avisamos.
	local ok, err = pcall(function()
		root:SetNetworkOwner(nil)
	end)
	if not ok then
		warn(`[GuardianService] {path}: não deu para passar a física pro servidor ({err}); ele está preso a algo ancorado?`)
	end

	local alertGui, alertLabel = createAlertGui(model, root)
	local idleTrack, runTrack = setupAnimations(humanoid, path)

	return {
		phase = phase,
		model = model,
		humanoid = humanoid,
		root = root,
		post = root.CFrame,
		home = model:GetPivot(),
		maxSpeed = maxSpeed,
		returnSpeed = math.max(GuardiansConfig.ReturnMinSpeed, maxSpeed * GuardiansConfig.ReturnSpeedFactor),
		chaseStartedAt = nil,
		cooldownUntil = 0,
		alertLabel = alertLabel,
		alertGui = alertGui,
		alertState = "None",
		idleTrack = idleTrack,
		runTrack = runTrack,
		moving = false,
	}
end

local function loadGuardians()
	local map = Workspace:FindFirstChild("Map")
	local folder = if map then map:FindFirstChild("Guardians") else nil
	if folder == nil then
		warn("[GuardianService] 'Workspace.Map.Guardians' não encontrado — nenhuma fase tem guardião")
		return
	end

	local byPhase: { [number]: Guardian } = {}
	for _, child in folder:GetChildren() do
		local phase = tonumber(string.match(child.Name, "^Guardian(%d+)$"))
		if phase == nil then
			warn(`[GuardianService] Workspace.Map.Guardians.{child.Name}: nome esperado é GuardianN (N = fase); ignorado`)
		elseif not child:IsA("Model") then
			warn(`[GuardianService] Workspace.Map.Guardians.{child.Name} precisa ser um Model (é {child.ClassName}); ignorado`)
		elseif byPhase[phase] then
			warn(`[GuardianService] Mais de um Guardian{phase} em Workspace.Map.Guardians; só o primeiro vale`)
		else
			local guardian = setupGuardian(phase, child)
			if guardian then
				byPhase[phase] = guardian
				table.insert(guardians, guardian)
			end
		end
	end

	for phase = 1, BaseService:GetPhaseCount() do
		if BaseService:GetPhasePart(phase) and byPhase[phase] == nil then
			warn(`[GuardianService] Phase{phase} sem guardião (falta Workspace.Map.Guardians.Guardian{phase})`)
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

-- Jogador mais próximo, dentro da fase do guardião, entre os da lista.
local function nearestInPhase(guardian: Guardian, players: { Player }, maxDistance: number): BasePart?
	local best: BasePart? = nil
	local bestDistance = maxDistance
	for _, player in players do
		local root = aliveRoot(player)
		if root and BaseService:GetPhaseAt(root.Position) == guardian.phase then
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

local function chase(guardian: Guardian, targetRoot: BasePart, now: number)
	local startedAt = guardian.chaseStartedAt or now
	guardian.chaseStartedAt = startedAt

	local ramp = if GuardiansConfig.ChaseRampSeconds > 0
		then math.clamp((now - startedAt) / GuardiansConfig.ChaseRampSeconds, 0, 1)
		else 1
	local factor = GuardiansConfig.ChaseStartFactor + (1 - GuardiansConfig.ChaseStartFactor) * ramp
	local speed = guardian.maxSpeed * factor
	guardian.humanoid.WalkSpeed = speed
	setAlert(guardian, "Chase")

	-- Nas fases rápidas ele anda muito entre duas checagens: o raio cresce junto.
	local catchDistance = math.max(GuardiansConfig.CatchDistance, speed * GuardiansConfig.UpdateInterval * 0.5)
	if (targetRoot.Position - guardian.root.Position).Magnitude > catchDistance then
		guardian.humanoid:MoveTo(targetRoot.Position)
		return
	end

	local player = Players:GetPlayerFromCharacter(targetRoot.Parent)
	if player then
		ScrollService:DropCarried(player)
		knockback(guardian, targetRoot)
		Remotes.getEvent(Remotes.Events.Notify):FireClient(player, "O guardião te pegou! O totem voltou para a fase.")
	end
	guardian.cooldownUntil = now + GuardiansConfig.CatchCooldown
	guardian.chaseStartedAt = nil
end

local function updateGuardian(guardian: Guardian, now: number)
	updateAnimation(guardian)
	if resetIfLost(guardian) then
		return
	end

	if now >= guardian.cooldownUntil then
		local target = nearestInPhase(guardian, ScrollService:GetCarriers(), math.huge)
		if target then
			chase(guardian, target, now)
			return
		end
	end

	-- Sem alvo: volta ao posto e, de lá, vigia quem chega perto.
	guardian.chaseStartedAt = nil
	guardian.humanoid.WalkSpeed = guardian.returnSpeed

	local watched = nearestInPhase(guardian, Players:GetPlayers(), GuardiansConfig.AlertDistance)
	setAlert(guardian, if watched then "Alert" else "None")

	local offset = flat(guardian.root.Position - guardian.post.Position)
	if offset.Magnitude > GuardiansConfig.PostTolerance then
		guardian.humanoid:MoveTo(guardian.post.Position)
		return
	end

	guardian.humanoid:Move(Vector3.zero)
	if watched then
		turnTowards(guardian, watched.Position - guardian.root.Position)
	else
		turnTowards(guardian, guardian.post.LookVector)
	end
end

function GuardianService:Start()
	loadGuardians()

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
