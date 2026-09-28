--!strict

-- Totens (no código ainda "scroll", o antigo pergaminho) no chão das fases: spawn
-- por fase (Config/Phases), evento lendário com aviso no chat, coleta encostando
-- (validada no servidor), carregar 1 por vez e colocar na base clicando no chão
-- (remote PlaceScroll). O visual vem do TotemService.
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
-- Intervalo mínimo entre duas chamadas de PlaceScroll do mesmo jogador.
local PLACE_COOLDOWN = 0.5
-- Tentativas de achar chão num ponto aleatório da fase antes de desistir do spawn.
local SPAWN_ATTEMPTS = 5

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
}

-- onPlace: o que acontece ao clicar no chão da base, com o ponto clicado (true =
-- entregue; "Gone" = o item deixou de existir e a carga acaba). onLost: morreu,
-- foi pego ou saiu.
export type PlaceHandler = (player: Player, position: Vector3) -> (boolean, string?)

type Carried = {
	rarity: string,
	visual: Model,
	onPlace: PlaceHandler,
	onLost: () -> (),
}

-- Chave: a Hitbox do totem no chão.
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

local function randomFloorPoint(volume: BasePart): Vector3?
	local exclude: { Instance } = { volume }
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

	local half = volume.Size / 2
	for _ = 1, SPAWN_ATTEMPTS do
		local x = random:NextNumber(-half.X, half.X) * 0.9
		local z = random:NextNumber(-half.Z, half.Z) * 0.9
		local origin = volume.CFrame * Vector3.new(x, half.Y, z)
		local result = Workspace:Raycast(origin, Vector3.new(0, -(volume.Size.Y + 2), 0), params)
		if result then
			return result.Position
		end
	end
	return nil
end

local onScrollTouched: (BasePart, BasePart) -> ()

-- Só cria o totem no chão; quem chama cuida de countByPhase.
local function spawnScroll(phase: number, rarity: string, fromEvent: boolean): boolean
	local volume = BaseService:GetPhasePart(phase)
	if volume == nil then
		return false
	end
	local point = randomFloorPoint(volume)
	if point == nil then
		return false
	end

	local model = TotemService:Create(rarity, nil, true)
	local hitbox = TotemService:AddHitbox(model)
	model:PivotTo(CFrame.new(point) * CFrame.Angles(0, random:NextNumber(0, 2 * math.pi), 0))
	model.Parent = scrollsFolder
	groundScrolls[hitbox] = { rarity = rarity, phase = phase, fromEvent = fromEvent, model = model }
	hitbox.Touched:Connect(function(hit: BasePart)
		onScrollTouched(hitbox, hit)
	end)
	return true
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
	onPlace: PlaceHandler,
	onLost: () -> ()
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
		visual = visual,
		onPlace = onPlace,
		onLost = onLost,
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

onScrollTouched = function(part: BasePart, hit: BasePart)
	local scroll = groundScrolls[part]
	if not scroll then
		return
	end

	local character = hit.Parent
	if character == nil or not character:IsA("Model") then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player == nil or carrying[player] then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if aliveCharacter(player) ~= character or root == nil or not root:IsA("BasePart") then
		return
	end
	-- Um exploit consegue disparar Touched de longe: vale a distância real (até a
	-- borda do totem, porque um totem grande tem o centro longe de quem encosta).
	local reach = PICKUP_DISTANCE + math.max(part.Size.X, part.Size.Z) / 2
	if (root.Position - part.Position).Magnitude > reach then
		return
	end

	local rarity, phase, fromEvent = scroll.rarity, scroll.phase, scroll.fromEvent
	local carried = startCarrying(player, character, rarity, function(placer: Player, position: Vector3): (boolean, string?)
		local ok, reason = WarriorService:AddScroll(placer, rarity, position)
		if ok and not fromEvent then
			countByPhase[phase] -= 1
		end
		return ok, reason
	end, function()
		-- Volta para o chão da fase de origem sem mudar a contagem.
		if not spawnScroll(phase, rarity, fromEvent) and not fromEvent then
			countByPhase[phase] -= 1
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

-- Tira o item do jogador como se ele tivesse perdido (ex.: guardião ou dono pegou).
function ScrollService:DropCarried(player: Player)
	loseCarried(player)
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
	return startCarrying(player, character, rarity, onPlace, onLost)
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
		task.spawn(function()
			while true do
				task.wait(config.SpawnInterval)
				trySpawnInPhase(phase)
			end
		end)
	end

	task.spawn(runLegendaryEvent)
end

return ScrollService
