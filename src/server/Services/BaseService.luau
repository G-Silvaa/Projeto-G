--!strict

-- Lê os marcadores de Workspace.Map (montado à mão no Studio) e cuida das
-- bases: atribui quando os dados carregam, libera ao sair e faz o jogador
-- nascer (e renascer) dentro do próprio ringue. Não gera geometria nenhuma.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PlayerDataService = require(script.Parent.PlayerDataService)

local BaseService = {}

-- O mapa precisa ter Workspace.Map.Bases.Base1..Base5 (máximo de 5 jogadores por servidor).
local BASE_COUNT = 5
-- Altura do centro do corpo acima do chão ao nascer; 3 deixa os pés praticamente no chão.
local SPAWN_HEIGHT = 3

type SpawnPoint = {
	location: SpawnLocation,
	cframe: CFrame,
}

-- Centro do piso da base (girado só no eixo vertical, como o ringue) e o tamanho da área.
type BaseArea = {
	cframe: CFrame,
	size: Vector3,
}

type BaseRecord = {
	index: number,
	spawn: SpawnPoint,
	area: BaseArea,
	marker: Instance,
	owner: Player?,
}

local bases: { [number]: BaseRecord } = {}
local ownerToBase: { [Player]: BaseRecord } = {}
local lobby: SpawnPoint? = nil
local killZone: BasePart? = nil
local phaseParts: { [number]: BasePart } = {}
local phaseCount = 0

local function findMarker(parent: Instance, name: string, path: string, impact: string): BasePart?
	local child = parent:FindFirstChild(name)
	if child == nil then
		warn(`[BaseService] Marcador '{path}.{name}' não encontrado — {impact}`)
		return nil
	end
	if not child:IsA("BasePart") then
		warn(`[BaseService] '{path}.{name}' precisa ser uma Part (é {child.ClassName}) — {impact}`)
		return nil
	end
	return child
end

-- SpawnLocation invisível com o topo rente ao chão, só pra o Roblox já criar o
-- personagem no lugar certo. Neutral = true: um jogador sem time só usa
-- SpawnLocation neutro. CanTouch = false: encostar nele não faz nada.
-- A posição final é garantida pelo teleporte em spawnCharacter.
local function newSpawnPoint(floor: Vector3, parent: Instance): SpawnPoint
	local location = Instance.new("SpawnLocation")
	location.Name = "SpawnPoint"
	location.Anchored = true
	location.CanCollide = false
	location.CanTouch = false
	location.CanQuery = false
	location.Transparency = 1
	location.Neutral = true
	location.Duration = 0
	location.Size = Vector3.new(4, 1, 4)
	location.CFrame = CFrame.new(floor - Vector3.new(0, 0.5, 0))
	location.Parent = parent

	return {
		location = location,
		cframe = CFrame.new(floor + Vector3.new(0, SPAWN_HEIGHT, 0)),
	}
end

local function partFloor(part: BasePart): Vector3
	return part.Position + Vector3.new(0, part.Size.Y / 2, 0)
end

-- Só a rotação no eixo vertical: a área da base fica sempre na horizontal,
-- mesmo que o pivot do modelo esteja inclinado.
local function yawOnly(cframe: CFrame): CFrame
	local look = Vector3.new(cframe.LookVector.X, 0, cframe.LookVector.Z)
	if look.Magnitude < 1e-3 then
		return CFrame.identity
	end
	return CFrame.lookAt(Vector3.zero, look)
end

-- Chão do ringue no centro do modelo: um raio de cima pra baixo que só enxerga
-- o próprio ringue. Usa o centro da caixa do modelo em vez do pivot, porque o
-- pivot pode estar em qualquer lugar (ex.: num poste, se ele for o PrimaryPart).
local function modelFloor(model: Model, boxCFrame: CFrame, boxSize: Vector3, path: string): Vector3
	local center = boxCFrame.Position
	local top = center.Y + boxSize.Y / 2

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }

	local result = Workspace:Raycast(Vector3.new(center.X, top + 1, center.Z), Vector3.new(0, -(boxSize.Y + 2), 0), params)
	if result then
		return result.Position
	end

	warn(`[BaseService] Não achei o chão no centro de '{path}'; usando o centro do modelo`)
	return center
end

local function setupBases(map: Instance)
	local folder = map:FindFirstChild("Bases")
	if folder == nil then
		warn("[BaseService] 'Workspace.Map.Bases' não encontrado — ninguém recebe base")
		return
	end

	for index = 1, BASE_COUNT do
		local path = `Workspace.Map.Bases.Base{index}`
		local marker = folder:FindFirstChild(`Base{index}`)
		local area: BaseArea? = nil

		if marker == nil then
			warn(`[BaseService] Marcador '{path}' não encontrado — essa base fica fora do jogo`)
		elseif marker:IsA("Model") then
			local boxCFrame, boxSize = marker:GetBoundingBox()
			local floor = modelFloor(marker, boxCFrame, boxSize, path)
			area = { cframe = CFrame.new(floor) * yawOnly(boxCFrame), size = boxSize }
		elseif marker:IsA("BasePart") then
			area = { cframe = CFrame.new(partFloor(marker)) * yawOnly(marker.CFrame), size = marker.Size }
		else
			warn(`[BaseService] '{path}' precisa ser um Model ou uma Part (é {marker.ClassName}) — essa base fica fora do jogo`)
		end

		if area and marker then
			bases[index] = {
				index = index,
				spawn = newSpawnPoint(area.cframe.Position, marker),
				area = area,
				marker = marker,
				owner = nil,
			}
		end
	end
end

local function setupPhases(map: Instance)
	local folder = map:FindFirstChild("Phases")
	if folder == nil then
		warn("[BaseService] 'Workspace.Map.Phases' não encontrado — GetPhaseAt sempre retorna nil")
		return
	end

	for _, child in folder:GetChildren() do
		local digits = child.Name:match("^Phase(%d+)$")
		local index = if digits then tonumber(digits) else nil
		if index == nil or index < 1 then
			continue
		end
		if not child:IsA("BasePart") then
			warn(`[BaseService] 'Workspace.Map.Phases.{child.Name}' precisa ser uma Part (é {child.ClassName})`)
			continue
		end
		phaseParts[index] = child
		phaseCount = math.max(phaseCount, index)
	end

	if phaseCount == 0 then
		warn("[BaseService] Nenhum 'PhaseN' em Workspace.Map.Phases — GetPhaseAt sempre retorna nil")
	end
	for index = 1, phaseCount do
		if not phaseParts[index] then
			warn(`[BaseService] Marcador 'Workspace.Map.Phases.Phase{index}' não encontrado — essa fase nunca é detectada`)
		end
	end
end

-- Em ordem de índice: Base1 é a primeira a ser ocupada.
local function findFreeBase(): BaseRecord?
	for index = 1, BASE_COUNT do
		local base = bases[index]
		if base and base.owner == nil then
			return base
		end
	end
	return nil
end

local function spawnPointFor(player: Player): SpawnPoint?
	local base = ownerToBase[player]
	if base then
		return base.spawn
	end
	return lobby
end

local function spawnCharacter(player: Player)
	local point = spawnPointFor(player)
	if point then
		player.RespawnLocation = point.location
	end

	local ok, err = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok then
		warn(`[BaseService] Falha ao carregar o character de {player.Name}: {err}`)
		return
	end

	local character = player.Character
	if character == nil then
		return
	end

	if point then
		character:PivotTo(point.cframe)
	end

	-- Com CharacterAutoLoads = false o Roblox não renasce ninguém sozinho.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Once(function()
			task.wait(Players.RespawnTime)
			if player.Parent == Players then
				spawnCharacter(player)
			end
		end)
	end
end

local function releaseBase(player: Player)
	local base = ownerToBase[player]
	if base == nil then
		return
	end
	base.owner = nil
	ownerToBase[player] = nil
end

local function assignBase(player: Player)
	if ownerToBase[player] then
		return
	end

	local base = findFreeBase()
	if base then
		base.owner = player
		ownerToBase[player] = base
	elseif lobby then
		warn(`[BaseService] Sem base livre: {player.Name} vai para o lobby`)
	else
		warn(`[BaseService] Sem base livre e sem lobby: {player.Name} nasce num ponto padrão`)
	end

	spawnCharacter(player)
end

-- Quem encosta na KillZone morre e renasce no próprio ringue (ou no lobby).
local function onKillZoneTouched(hit: BasePart)
	local character = hit.Parent
	if character == nil or not character:IsA("Model") then
		return
	end
	if Players:GetPlayerFromCharacter(character) == nil then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

local function isInsidePart(part: BasePart, position: Vector3): boolean
	local relative = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(relative.X) <= half.X and math.abs(relative.Y) <= half.Y and math.abs(relative.Z) <= half.Z
end

function BaseService:Init()
	-- Cedo, antes de qualquer PlayerAdded: o BaseService é quem cria o
	-- personagem, depois que os dados carregam e a base é atribuída.
	Players.CharacterAutoLoads = false

	local map = Workspace:FindFirstChild("Map")
	if map == nil then
		warn("[BaseService] 'Workspace.Map' não encontrado — monte o mapa no Studio (veja o CLAUDE.md)")
		return
	end

	setupBases(map)
	setupPhases(map)

	local lobbyMarker = findMarker(map, "Lobby", "Workspace.Map", "quem não tiver base nasce num ponto padrão")
	lobby = if lobbyMarker then newSpawnPoint(partFloor(lobbyMarker), lobbyMarker) else nil

	killZone = findMarker(map, "KillZone", "Workspace.Map", "quem cair do mapa não volta sozinho")
end

function BaseService:Start()
	Players.PlayerRemoving:Connect(releaseBase)
	PlayerDataService:OnPlayerLoaded(assignBase)

	local zone = killZone
	if zone then
		-- Sem isso o Touched nunca dispara.
		zone.CanTouch = true
		zone.Touched:Connect(onKillZoneTouched)
	end
end

function BaseService:GetBase(player: Player): number?
	local base = ownerToBase[player]
	return if base then base.index else nil
end

function BaseService:GetOwner(baseIndex: number): Player?
	local record = bases[baseIndex]
	return if record then record.owner else nil
end

-- Centro do piso da base (girado como o ringue) e o tamanho da área, pra
-- posicionar coisas dentro da base. nil se a base não existe.
function BaseService:GetBaseArea(baseIndex: number): (CFrame?, Vector3?)
	local record = bases[baseIndex]
	if record then
		return record.area.cframe, record.area.size
	end
	return nil, nil
end

-- Número da fase cujo volume PhaseN contém a posição (funciona com a Part
-- rotacionada), ou nil se estiver fora de todas.
function BaseService:GetBaseCount(): number
	return BASE_COUNT
end

-- O marcador BaseN do mapa (Model do ringue ou Part), ou nil se a base não existe.
function BaseService:GetBaseInstance(baseIndex: number): Instance?
	local record = bases[baseIndex]
	return if record then record.marker else nil
end

-- Maior N entre os PhaseN encontrados no mapa (pode haver buracos; ver GetPhasePart).
function BaseService:GetPhaseCount(): number
	return phaseCount
end

-- Volume invisível da fase, ou nil se esse PhaseN não existe no mapa.
function BaseService:GetPhasePart(index: number): BasePart?
	return phaseParts[index]
end

function BaseService:GetPhaseAt(position: Vector3): number?
	for index = 1, phaseCount do
		local part = phaseParts[index]
		if part and isInsidePart(part, position) then
			return index
		end
	end
	return nil
end

return BaseService
