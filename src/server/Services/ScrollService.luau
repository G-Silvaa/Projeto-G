--!strict

-- Pergaminhos no chão das fases: spawn por fase (Config/Phases), evento lendário
-- com aviso no chat, coleta encostando (validada no servidor), carregar 1 por vez
-- e colocar na base pelo remote PlaceScroll.
--
-- Contagem por fase: um pergaminho conta no MaxScrolls da fase de origem desde que
-- aparece até ser colocado numa base, inclusive enquanto alguém carrega. Se o
-- carregador morrer ou sair, ele volta para o chão da mesma fase sem mudar a
-- contagem. Pergaminhos do evento lendário nunca contam.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local PhasesConfig = require(Config:WaitForChild("Phases"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BaseService = require(script.Parent.BaseService)
local WarriorService = require(script.Parent.WarriorService)

local ScrollService = {}

-- Distância máxima real (studs) entre o personagem e o pergaminho pra valer a coleta.
local PICKUP_DISTANCE = 8
-- Intervalo mínimo entre duas chamadas de PlaceScroll do mesmo jogador.
local PLACE_COOLDOWN = 0.5
-- Frequência da checagem "está dentro do próprio ringue" (só pra mostrar o botão).
local BASE_CHECK_INTERVAL = 0.25
-- Tentativas de achar chão num ponto aleatório da fase antes de desistir do spawn.
local SPAWN_ATTEMPTS = 5
local SCROLL_HOVER = 1.5
local LABEL_MAX_DISTANCE = 80

-- Mensagens do botão (motivos do WarriorService:AddScroll e daqui).
local MESSAGES: { [string]: string } = {
	NotLoaded = "Seus dados ainda estão carregando",
	NoBase = "Você não tem base",
	NoPosition = "Personagem não encontrado",
	OutsideBase = "Fora da sua base",
	TooClose = "Muito perto de outro guerreiro",
	NotCarrying = "Você não está carregando pergaminho",
	RateLimited = "Calma, tente de novo",
}

type GroundScroll = {
	rarity: string,
	phase: number,
	fromEvent: boolean,
}

type Carried = {
	rarity: string,
	phase: number,
	fromEvent: boolean,
	visual: BasePart,
}

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

local function createScrollPart(rarity: string): Part
	local rarityInfo = Rarities[rarity]

	local part = Instance.new("Part")
	part.Name = "Scroll"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(2.4, 0.8, 0.8)
	part.Material = Enum.Material.Neon
	part.Color = rarityInfo.Color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 28)
	billboard.StudsOffset = Vector3.new(0, 1.6, 0)
	billboard.MaxDistance = LABEL_MAX_DISTANCE
	billboard.LightInfluence = 0
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = rarityInfo.DisplayName
	label.TextColor3 = rarityInfo.Color
	-- Contorno claro pra ler bem em qualquer cor, inclusive o preto do Secreto.
	label.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard

	return part
end

local function randomFloorPoint(volume: BasePart): Vector3?
	local exclude: { Instance } = { volume }
	if scrollsFolder then
		table.insert(exclude, scrollsFolder)
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

-- Só cria o pergaminho no chão; quem chama cuida de countByPhase.
local function spawnScroll(phase: number, rarity: string, fromEvent: boolean): boolean
	local volume = BaseService:GetPhasePart(phase)
	if volume == nil then
		return false
	end
	local point = randomFloorPoint(volume)
	if point == nil then
		return false
	end

	local part = createScrollPart(rarity)
	part.CFrame = CFrame.new(point + Vector3.new(0, SCROLL_HOVER, 0))
	part.Parent = scrollsFolder
	groundScrolls[part] = { rarity = rarity, phase = phase, fromEvent = fromEvent }
	part.Touched:Connect(function(hit: BasePart)
		onScrollTouched(part, hit)
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
	player:SetAttribute("InOwnBase", nil)
	return carried
end

-- Morreu, trocou de personagem ou saiu: o pergaminho volta para o chão da fase de origem.
local function loseCarried(player: Player)
	local carried = stopCarrying(player)
	if carried == nil then
		return
	end
	if not spawnScroll(carried.phase, carried.rarity, carried.fromEvent) and not carried.fromEvent then
		countByPhase[carried.phase] -= 1
	end
end

local function startCarrying(player: Player, character: Model, anchor: BasePart, scroll: GroundScroll)
	local visual = createScrollPart(scroll.rarity)
	visual.Name = "CarriedScroll"
	visual.Anchored = false
	visual.CanTouch = false
	visual.Massless = true
	visual.CFrame = anchor.CFrame * CFrame.new(0, 2.5, 0)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = visual
	weld.Parent = visual
	visual.Parent = character

	carrying[player] = {
		rarity = scroll.rarity,
		phase = scroll.phase,
		fromEvent = scroll.fromEvent,
		visual = visual,
	}
	player:SetAttribute("CarryingScroll", scroll.rarity)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Once(function()
			loseCarried(player)
		end)
	end
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

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	-- Um exploit consegue disparar Touched de longe: vale a distância real.
	if (root.Position - part.Position).Magnitude > PICKUP_DISTANCE then
		return
	end

	groundScrolls[part] = nil
	part:Destroy()

	local head = character:FindFirstChild("Head")
	local anchor = if head and head:IsA("BasePart") then head else root
	startCarrying(player, character, anchor, scroll)
end

local function onPlaceScroll(player: Player): (boolean, string)
	local now = os.clock()
	local last = lastPlaceCall[player]
	if last and now - last < PLACE_COOLDOWN then
		return false, MESSAGES.RateLimited
	end
	lastPlaceCall[player] = now

	local carried = carrying[player]
	if not carried then
		return false, MESSAGES.NotCarrying
	end

	local ok, reason = WarriorService:AddScroll(player, carried.rarity)
	if not ok then
		if reason == "NoFreeSlot" then
			local max = WarriorService:GetMaxSlots()
			return false, `Sem espaço na base ({max}/{max})`
		end
		return false, MESSAGES[reason or ""] or "Não foi possível colocar o pergaminho"
	end

	stopCarrying(player)
	if not carried.fromEvent then
		countByPhase[carried.phase] -= 1
	end
	return true, "Pergaminho colocado!"
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
			Remotes.getEvent(Remotes.Events.Announcement):FireAllClients(`Um pergaminho {name} apareceu na fase {phase}!`)
		end
	end
end

-- Só alimenta o botão "Colocar pergaminho" do cliente; quem decide é o PlaceScroll.
local function updateBaseAttributes()
	for player in carrying do
		player:SetAttribute("InOwnBase", WarriorService:IsInPlacementArea(player))
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

-- Tira o pergaminho do jogador e devolve para a fase de origem (ex.: guardião pegou).
function ScrollService:DropCarried(player: Player)
	loseCarried(player)
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
			warn(`[ScrollService] Config/Phases tem a fase {phase}, mas não existe Workspace.Map.Phases.Phase{phase}; ela não recebe pergaminhos`)
		end
	end
	for phase = #PhasesConfig.Phases + 1, BaseService:GetPhaseCount() do
		warn(`[ScrollService] Phase{phase} existe no mapa, mas não está em Config/Phases; ela não recebe pergaminhos`)
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
	task.spawn(function()
		while true do
			task.wait(BASE_CHECK_INTERVAL)
			updateBaseAttributes()
		end
	end)
end

return ScrollService
