--!strict

-- Totens (no código ainda "scroll", o antigo pergaminho) no chão das fases: spawn
-- por fase (Config/Phases), evento lendário com aviso no chat, coleta pelo prompt
-- "Pegar" (validado no servidor), carregar 1 por vez e colocar na base clicando no
-- chão (remote PlaceScroll). O visual vem do TotemService. Os totens nascem em
-- volta do posto do guardião da fase (Config/Phases.GuardianSpawn).
--
-- Contagem por fase: um totem conta no MaxScrolls da fase de origem desde que
-- aparece até ser colocado numa base, inclusive enquanto alguém carrega. Se o
-- carregador morrer ou sair, ele volta para o chão da mesma fase sem mudar a
-- contagem. Totens do evento lendário nunca contam.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local PhasesConfig = require(Config:WaitForChild("Phases"))
local Rarities = require(Config:WaitForChild("Rarities"))
local TotemsConfig = require(Config:WaitForChild("Totems"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BaseService = require(script.Parent.BaseService)
local TotemService = require(script.Parent.TotemService)
local WarriorService = require(script.Parent.WarriorService)

local ScrollService = {}

-- Distância máxima real (studs) entre o personagem e a borda do totem pra valer a coleta.
local PICKUP_DISTANCE = 8
-- Segundos segurando a tecla do prompt "Pegar" (0 = só apertar).
local PICKUP_HOLD_SECONDS = 1
-- Intervalo mínimo entre duas chamadas de PlaceScroll do mesmo jogador.
local PLACE_COOLDOWN = 0.5
-- Tentativas de achar chão num ponto aleatório da fase antes de desistir do spawn.
local SPAWN_ATTEMPTS = 8
-- Folga da borda do volume da fase.
local SPAWN_EDGE = 0.9
-- Com guardião, o raio que acha o chão começa só um pouco acima do posto (e não no
-- topo do volume), pra não parar num telhado ou árvore em cima dele, e desce até
-- POST_RAY_BELOW abaixo.
local POST_RAY_ABOVE = 4
local POST_RAY_BELOW = 25
-- Peças que o raio atravessa (sem colisão ou invisíveis) antes de desistir.
local MAX_RAY_SKIPS = 8
-- Totem que cai (ou que o guardião solta): procura o chão entre um pouco acima e
-- bem abaixo do ponto.
local DROP_RAY_ABOVE = 4
local DROP_RAY_BELOW = 60
-- Segundos entre checagens de totens caídos que ninguém buscou.
local DROPPED_CHECK_INTERVAL = 1
-- Totem que acabou de cair não pode ser pego por jogador por este tempo (senão quem
-- foi pego pegaria de volta na hora, antes de ser arremessado).
local DROP_PICKUP_DELAY = 1.5

-- Mensagens do botão (motivos do WarriorService:AddScroll e daqui).
local MESSAGES: { [string]: string } = {
	NotLoaded = "Seus dados ainda estão carregando",
	NoBase = "Você não tem base",
	NoPosition = "Personagem não encontrado",
	OutsideBase = "Fora da sua base",
	NotInBase = "Entre na sua base para colocar",
	BadPosition = "Não foi possível colocar",
	TooClose = "Muito perto de outro totem ou guerreiro",
	NotCarrying = "Você não está carregando nenhum totem",
	RateLimited = "Calma, tente de novo",
	Gone = "Esse item não existe mais",
}

type GroundScroll = {
	rarity: string,
	phase: number,
	fromEvent: boolean,
	model: Model,
	droppedAt: number?, -- caiu da mão de alguém (os.clock); o guardião vem buscar
}

-- Totem que o guardião pegou do chão e está levando de volta (ver TakeDropped/PutBack).
export type TakenTotem = {
	rarity: string,
	phase: number,
	fromEvent: boolean,
}

-- onPlace: o que acontece ao clicar no chão da base, com o ponto clicado (true =
-- entregue; "Gone" = o item deixou de existir e a carga acaba). onLost: morreu,
-- foi pego ou saiu.
export type PlaceHandler = (player: Player, position: Vector3) -> (boolean, string?)

-- onDrop (só nos totens de fase): o guardião pegou quem carregava, e o totem cai no
-- chão em position. Sem onDrop (ex.: item roubado), vale o onLost.
type Carried = {
	rarity: string,
	phase: number?, -- fase de origem (só totens de fase; o guardião dela persegue)
	visual: Model,
	onPlace: PlaceHandler,
	onLost: () -> (),
	onDrop: ((position: Vector3) -> ())?,
}

-- Chave: a Hitbox do totem no chão (onde fica o prompt "Pegar").
local groundScrolls: { [BasePart]: GroundScroll } = {}
local countByPhase: { [number]: number } = {}
local carrying: { [Player]: Carried } = {}
local lastPlaceCall: { [Player]: number } = {}
local scrollsFolder: Folder? = nil
local random = Random.new()

local function pickWeighted(weights: { [string]: number }): string?
	local total = 0
	for id, weight in weights do
		if Rarities[id] and weight > 0 then
			total += weight
		end
	end
	if total <= 0 then
		return nil
	end

	local roll = random:NextNumber(0, total)
	local last: string? = nil
	for id, weight in weights do
		if Rarities[id] and weight > 0 then
			last = id
			roll -= weight
			if roll <= 0 then
				return id
			end
		end
	end
	return last
end

-- Ponto no plano do volume (coordenadas locais X, Z): em volta do posto do guardião
-- (área uniforme no anel entre MinDistance e Radius), ou em qualquer lugar da fase
-- se ela não tem guardião. Sempre dentro do volume.
local function randomSpawnSpot(phase: number, volume: BasePart): (number, number)
	local limitX = volume.Size.X / 2 * SPAWN_EDGE
	local limitZ = volume.Size.Z / 2 * SPAWN_EDGE
	local post = BaseService:GetGuardianPost(phase)
	if post == nil then
		return random:NextNumber(-limitX, limitX), random:NextNumber(-limitZ, limitZ)
	end

	local area = PhasesConfig.GuardianSpawn
	local angle = random:NextNumber(0, 2 * math.pi)
	local radius = math.sqrt(random:NextNumber(area.MinDistance ^ 2, area.Radius ^ 2))
	local point = post.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	-- Guardião perto da borda: o ponto é trazido pra dentro da fase, ainda perto dele.
	local relative = volume.CFrame:PointToObjectSpace(point)
	return math.clamp(relative.X, -limitX, limitX), math.clamp(relative.Z, -limitZ, limitZ)
end

-- Primeiro chão de verdade abaixo de origin: atravessa peças sem colisão ou
-- invisíveis (folhas, barreiras, áreas de toque), que não servem de chão.
local function floorBelow(origin: Vector3, length: number, params: RaycastParams): Vector3?
	local start = origin
	local remaining = length
	for _ = 1, MAX_RAY_SKIPS do
		local result = Workspace:Raycast(start, Vector3.new(0, -remaining, 0), params)
		if result == nil then
			return nil
		end
		local hit = result.Instance
		if hit.CanCollide and hit.Transparency < 1 then
			return result.Position
		end
		params:AddToFilter(hit)
		remaining -= start.Y - result.Position.Y
		start = result.Position
	end
	return nil
end

-- Raio que acha o chão ignorando totens, guardiões, jogadores e o que vier em extra.
local function floorParams(extra: { Instance }): RaycastParams
	local exclude: { Instance } = table.clone(extra)
	if scrollsFolder then
		table.insert(exclude, scrollsFolder)
	end
	-- Senão um totem pode nascer na cabeça de um guardião.
	local map = Workspace:FindFirstChild("Map")
	local guardians = if map then map:FindFirstChild("Guardians") else nil
	if guardians then
		table.insert(exclude, guardians)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	return params
end

local function randomFloorPoint(phase: number, volume: BasePart): Vector3?
	local params = floorParams({ volume })
	local half = volume.Size / 2
	local post = BaseService:GetGuardianPost(phase)
	for _ = 1, SPAWN_ATTEMPTS do
		local x, z = randomSpawnSpot(phase, volume)
		local origin: Vector3
		local length: number
		if post then
			local column = volume.CFrame * Vector3.new(x, 0, z)
			origin = Vector3.new(column.X, post.Position.Y + POST_RAY_ABOVE, column.Z)
			length = POST_RAY_ABOVE + POST_RAY_BELOW
		else
			origin = volume.CFrame * Vector3.new(x, half.Y, z)
			length = volume.Size.Y + 2
		end
		local floor = floorBelow(origin, length, params)
		if floor then
			return floor
		end
	end
	return nil
end

local tryPickup: (BasePart, Player) -> ()

-- Distância real máxima (até a borda do totem, porque um totem grande tem o centro
-- longe de quem está do lado).
local function pickupReach(hitbox: BasePart): number
	return PICKUP_DISTANCE + math.max(hitbox.Size.X, hitbox.Size.Z) / 2
end

-- Chão logo abaixo de um ponto qualquer (onde alguém foi pego, onde o guardião solta).
local function floorUnder(position: Vector3): Vector3?
	return floorBelow(position + Vector3.new(0, DROP_RAY_ABOVE, 0), DROP_RAY_ABOVE + DROP_RAY_BELOW, floorParams({}))
end

-- Cria o totem em pé no ponto do chão; quem chama cuida de countByPhase.
local function placeTotem(phase: number, rarity: string, fromEvent: boolean, point: Vector3, dropped: boolean)
	local model = TotemService:Create(rarity, TotemsConfig.GroundHeight, true)
	local hitbox = TotemService:AddHitbox(model)
	model:PivotTo(CFrame.new(point) * CFrame.Angles(0, random:NextNumber(0, 2 * math.pi), 0))
	model.Parent = scrollsFolder
	groundScrolls[hitbox] = {
		rarity = rarity,
		phase = phase,
		fromEvent = fromEvent,
		model = model,
		droppedAt = if dropped then os.clock() else nil,
	}

	-- "Pegar" (E no PC, X/quadrado no controle, botão na tela no celular). O
	-- alcance do prompt é só a dica visual: o servidor confere a distância de novo.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Pegar"
	prompt.ObjectText = `Totem {Rarities[rarity].DisplayName}`
	prompt.HoldDuration = PICKUP_HOLD_SECONDS
	prompt.MaxActivationDistance = pickupReach(hitbox)
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player: Player)
		tryPickup(hitbox, player)
	end)
	-- Totem que acabou de cair só pode ser pego depois de DROP_PICKUP_DELAY.
	if dropped then
		task.delay(DROP_PICKUP_DELAY, function()
			if hitbox.Parent then
				prompt.Parent = hitbox
			end
		end)
	else
		prompt.Parent = hitbox
	end
end

-- Num ponto sorteado da fase (em volta do guardião); quem chama cuida de countByPhase.
local function spawnScroll(phase: number, rarity: string, fromEvent: boolean): boolean
	local volume = BaseService:GetPhasePart(phase)
	if volume == nil then
		return false
	end
	local point = randomFloorPoint(phase, volume)
	if point == nil then
		return false
	end
	placeTotem(phase, rarity, fromEvent, point, false)
	return true
end

-- Volta pra fase sem mudar a contagem; se não houver onde, sai da contagem.
local function respawnInPhase(phase: number, rarity: string, fromEvent: boolean)
	if not spawnScroll(phase, rarity, fromEvent) and not fromEvent then
		countByPhase[phase] -= 1
	end
end

local function stopCarrying(player: Player): Carried?
	local carried = carrying[player]
	if carried == nil then
		return nil
	end
	carrying[player] = nil
	carried.visual:Destroy()
	player:SetAttribute("CarryingScroll", nil)
	return carried
end

-- Morreu, trocou de personagem, foi pego ou saiu: quem criou a carga decide o destino.
local function loseCarried(player: Player)
	local carried = stopCarrying(player)
	if carried then
		carried.onLost()
	end
end

-- Personagem vivo, ou nil.
local function aliveCharacter(player: Player): Model?
	local character = player.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return character
end

-- false se o personagem não tem onde prender o totem.
local function startCarrying(
	player: Player,
	character: Model,
	rarity: string,
	phase: number?,
	onPlace: PlaceHandler,
	onLost: () -> (),
	onDrop: ((position: Vector3) -> ())?
): boolean
	local visual = TotemService:Create(rarity, TotemsConfig.CarryHeight, true)
	visual.Name = "CarriedTotem"
	if not TotemService:MountOn(visual, character) then
		visual:Destroy()
		return false
	end
	visual.Parent = character

	carrying[player] = {
		rarity = rarity,
		phase = phase,
		visual = visual,
		onPlace = onPlace,
		onLost = onLost,
		onDrop = onDrop,
	}
	player:SetAttribute("CarryingScroll", rarity)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Once(function()
			loseCarried(player)
		end)
	end
	return true
end

-- Prompt "Pegar" ativado. O servidor confere tudo de novo: personagem vivo, mãos
-- livres, distância real e o tempo depois de cair.
tryPickup = function(part: BasePart, player: Player)
	local scroll = groundScrolls[part]
	if not scroll or carrying[player] then
		return
	end

	local character = aliveCharacter(player)
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if character == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	local droppedAt = scroll.droppedAt
	if droppedAt and os.clock() - droppedAt < DROP_PICKUP_DELAY then
		return
	end
	if (root.Position - part.Position).Magnitude > pickupReach(part) then
		return
	end

	local rarity, phase, fromEvent = scroll.rarity, scroll.phase, scroll.fromEvent
	local carried = startCarrying(player, character, rarity, phase, function(placer: Player, position: Vector3): (boolean, string?)
		local ok, reason = WarriorService:AddScroll(placer, rarity, position)
		if ok and not fromEvent then
			countByPhase[phase] -= 1
		end
		return ok, reason
	end, function()
		-- Volta para o chão da fase de origem sem mudar a contagem.
		respawnInPhase(phase, rarity, fromEvent)
	end, function(position: Vector3)
		-- O guardião pegou quem carregava: cai no chão ali (ainda conta na fase).
		local floor = floorUnder(position)
		if floor then
			placeTotem(phase, rarity, fromEvent, floor, true)
		else
			respawnInPhase(phase, rarity, fromEvent)
		end
	end)
	if carried then
		groundScrolls[part] = nil
		scroll.model:Destroy()
	end
end

local function isFiniteVector(vector: Vector3): boolean
	for _, value in { vector.X, vector.Y, vector.Z } do
		if value ~= value or value == math.huge or value == -math.huge then
			return false
		end
	end
	return true
end

-- position: ponto do chão onde o jogador clicou. Não confiamos nele: o jogador
-- precisa estar no próprio ringue e o AddScroll confere se o ponto está na área.
local function onPlaceScroll(player: Player, position: unknown): (boolean, string)
	local now = os.clock()
	local last = lastPlaceCall[player]
	if last and now - last < PLACE_COOLDOWN then
		return false, MESSAGES.RateLimited
	end
	lastPlaceCall[player] = now

	if typeof(position) ~= "Vector3" or not isFiniteVector(position) then
		return false, MESSAGES.BadPosition
	end
	local carried = carrying[player]
	if not carried then
		return false, MESSAGES.NotCarrying
	end
	if not WarriorService:IsInPlacementArea(player) then
		return false, MESSAGES.NotInBase
	end

	local ok, reason = carried.onPlace(player, position)
	if ok then
		stopCarrying(player)
		return true, "Colocado na sua base!"
	end
	if reason == "Gone" then
		stopCarrying(player)
		return false, MESSAGES.Gone
	end
	if reason == "NoFreeSlot" then
		local max = WarriorService:GetMaxSlots(player)
		return false, `Sem espaço na base ({max}/{max})`
	end
	return false, MESSAGES[reason or ""] or "Não foi possível colocar"
end

local function trySpawnInPhase(phase: number): boolean
	local config = PhasesConfig.Phases[phase]
	if countByPhase[phase] >= config.MaxScrolls then
		return false
	end
	local rarity = pickWeighted(config.Weights)
	if rarity == nil or not spawnScroll(phase, rarity, false) then
		return false
	end
	countByPhase[phase] += 1
	return true
end

local function runLegendaryEvent()
	local event = PhasesConfig.LegendaryEvent
	while true do
		-- Só pra UI (contagem regressiva); em horário do servidor (GetServerTimeNow).
		ReplicatedStorage:SetAttribute("NextLegendaryAt", Workspace:GetServerTimeNow() + event.IntervalSeconds)
		task.wait(event.IntervalSeconds)

		local candidates: { number } = {}
		for _, phase in event.Phases do
			if BaseService:GetPhasePart(phase) then
				table.insert(candidates, phase)
			end
		end
		if #candidates == 0 and BaseService:GetPhaseCount() > 0 then
			table.insert(candidates, BaseService:GetPhaseCount())
		end
		if #candidates == 0 then
			continue
		end

		local phase = candidates[random:NextInteger(1, #candidates)]
		local rarity = pickWeighted(event.Weights)
		if rarity and spawnScroll(phase, rarity, true) then
			local name = Rarities[rarity].DisplayName
			Remotes.getEvent(Remotes.Events.Announcement):FireAllClients(`Um totem {name} apareceu na fase {phase}!`)
		end
	end
end

function ScrollService:IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

function ScrollService:GetCarriers(): { Player }
	local list: { Player } = {}
	for player in carrying do
		table.insert(list, player)
	end
	return list
end

-- Fase de onde veio o totem que o jogador carrega (nil se não carrega ou se é item roubado).
function ScrollService:GetCarriedPhase(player: Player): number?
	local carried = carrying[player]
	return if carried then carried.phase else nil
end

-- Tira o item do jogador como se ele tivesse perdido (ex.: o dono pegou o ladrão).
function ScrollService:DropCarried(player: Player)
	loseCarried(player)
end

-- O guardião pegou o jogador: totem de fase cai no chão em position (o guardião vem
-- buscar); item roubado volta pro dono como no DropCarried.
function ScrollService:KnockDrop(player: Player, position: Vector3)
	local carried = stopCarrying(player)
	if carried == nil then
		return
	end
	if carried.onDrop then
		carried.onDrop(position)
	else
		carried.onLost()
	end
end

-- Hitboxes dos totens caídos na fase (pra o guardião ir buscar).
function ScrollService:GetDropped(phase: number): { BasePart }
	local list: { BasePart } = {}
	for hitbox, scroll in groundScrolls do
		if scroll.phase == phase and scroll.droppedAt then
			table.insert(list, hitbox)
		end
	end
	return list
end

-- O guardião pega o totem caído: some do chão e ele leva. nil se alguém pegou antes.
function ScrollService:TakeDropped(hitbox: BasePart): TakenTotem?
	local scroll = groundScrolls[hitbox]
	if scroll == nil or scroll.droppedAt == nil then
		return nil
	end
	groundScrolls[hitbox] = nil
	scroll.model:Destroy()
	return { rarity = scroll.rarity, phase = scroll.phase, fromEvent = scroll.fromEvent }
end

-- O guardião solta o totem que levou, no chão perto de position (nil = qualquer
-- ponto da fase). Continua contando na fase.
function ScrollService:PutBack(taken: TakenTotem, position: Vector3?)
	local floor = if position then floorUnder(position) else nil
	if floor then
		placeTotem(taken.phase, taken.rarity, taken.fromEvent, floor, false)
	else
		respawnInPhase(taken.phase, taken.rarity, taken.fromEvent)
	end
end

-- Faz o jogador carregar um item qualquer (ex.: roubado), com as regras de quem chama.
-- false se ele já carrega algo ou não tem personagem vivo.
function ScrollService:CarryItem(player: Player, rarity: string, onPlace: PlaceHandler, onLost: () -> ()): boolean
	if carrying[player] or not Rarities[rarity] then
		return false
	end
	local character = aliveCharacter(player)
	if character == nil then
		return false
	end
	return startCarrying(player, character, rarity, nil, onPlace, onLost)
end

function ScrollService:Init()
	local function checkWeights(weights: { [string]: number }, where: string)
		for id in weights do
			assert(Rarities[id], `[ScrollService] {where}: raridade inválida '{id}'`)
		end
	end
	for phase, config in PhasesConfig.Phases do
		checkWeights(config.Weights, `Phases[{phase}]`)
	end
	checkWeights(PhasesConfig.LegendaryEvent.Weights, "LegendaryEvent")
	local spawnArea = PhasesConfig.GuardianSpawn
	assert(
		spawnArea.MinDistance >= 0 and spawnArea.MinDistance <= spawnArea.Radius,
		"[ScrollService] Config/Phases.GuardianSpawn: precisa de 0 <= MinDistance <= Radius"
	)

	for phase = 1, #PhasesConfig.Phases do
		if BaseService:GetPhasePart(phase) == nil then
			warn(`[ScrollService] Config/Phases tem a fase {phase}, mas não existe Workspace.Map.Phases.Phase{phase}; ela não recebe totens`)
		end
	end
	for phase = #PhasesConfig.Phases + 1, BaseService:GetPhaseCount() do
		warn(`[ScrollService] Phase{phase} existe no mapa, mas não está em Config/Phases; ela não recebe totens`)
	end

	local folder = Instance.new("Folder")
	folder.Name = "PhaseScrolls"
	folder.Parent = Workspace
	scrollsFolder = folder
end

function ScrollService:Start()
	Remotes.getFunction(Remotes.Functions.PlaceScroll).OnServerInvoke = onPlaceScroll

	Players.PlayerRemoving:Connect(function(player: Player)
		loseCarried(player)
		lastPlaceCall[player] = nil
	end)
	local function watchCharacter(player: Player)
		player.CharacterRemoving:Connect(function()
			loseCarried(player)
		end)
	end
	Players.PlayerAdded:Connect(watchCharacter)
	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end

	for phase, config in PhasesConfig.Phases do
		if BaseService:GetPhasePart(phase) == nil then
			continue
		end
		countByPhase[phase] = 0
		-- Começa com a fase cheia; depois repõe um por intervalo.
		while trySpawnInPhase(phase) do
		end
		if countByPhase[phase] == 0 then
			local near = if BaseService:GetGuardianPost(phase) then " em volta do guardião" else ""
			warn(
				`[ScrollService] Nenhum totem conseguiu nascer na Phase{phase}: não achei chão{near}. `
					.. "Confira se há chão visível e com colisão perto do posto."
			)
		end
		task.spawn(function()
			while true do
				task.wait(config.SpawnInterval)
				trySpawnInPhase(phase)
			end
		end)
	end

	task.spawn(runLegendaryEvent)

	-- Totem caído que ninguém buscou (ex.: caiu onde o guardião não chega) volta sozinho.
	task.spawn(function()
		while true do
			task.wait(DROPPED_CHECK_INTERVAL)
			local now = os.clock()
			-- Separa antes: o respawn põe totens novos na tabela que está sendo percorrida.
			local expired: { BasePart } = {}
			for hitbox, scroll in groundScrolls do
				local droppedAt = scroll.droppedAt
				if droppedAt and now - droppedAt > PhasesConfig.DroppedTimeout then
					table.insert(expired, hitbox)
				end
			end
			for _, hitbox in expired do
				local scroll = groundScrolls[hitbox]
				groundScrolls[hitbox] = nil
				scroll.model:Destroy()
				respawnInPhase(scroll.phase, scroll.rarity, scroll.fromEvent)
			end
		end
	end)
end

return ScrollService
