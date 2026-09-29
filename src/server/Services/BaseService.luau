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
-- Fases tiradas dos chãos (sem Map.Phases): folga abaixo e acima do chão, e até
-- quantos Chao_FaseN procurar.
local DERIVED_PHASE_BELOW = 5
local DERIVED_PHASE_ABOVE = 40
local MAX_PHASES = 50

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
-- Guardião de cada fase e o posto dele (CFrame do HumanoidRootPart, ou do tronco
-- numa estátua, lido no Init, antes de o GuardianService soltar o NPC).
local guardianModels: { [number]: Model } = {}
local guardianPosts: { [number]: CFrame } = {}

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

local function isInsidePart(part: BasePart, position: Vector3): boolean
	local relative = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(relative.X) <= half.X and math.abs(relative.Y) <= half.Y and math.abs(relative.Z) <= half.Z
end

-- Caixa alinhada aos eixos do mundo cobrindo todas as peças (a peça pode estar girada).
local function worldBox(instance: Instance): (Vector3?, Vector3?)
	local parts: { BasePart } = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	if #parts == 0 then
		return nil, nil
	end

	local low = Vector3.one * math.huge
	local high = -Vector3.one * math.huge
	for _, part in parts do
		local cframe, half = part.CFrame, part.Size / 2
		local extent = Vector3.new(
			math.abs(cframe.XVector.X) * half.X + math.abs(cframe.YVector.X) * half.Y + math.abs(cframe.ZVector.X) * half.Z,
			math.abs(cframe.XVector.Y) * half.X + math.abs(cframe.YVector.Y) * half.Y + math.abs(cframe.ZVector.Y) * half.Z,
			math.abs(cframe.XVector.Z) * half.X + math.abs(cframe.YVector.Z) * half.Y + math.abs(cframe.ZVector.Z) * half.Z
		)
		low = low:Min(cframe.Position - extent)
		high = high:Max(cframe.Position + extent)
	end
	return low, high
end

type FloorBox = { index: number, low: Vector3, high: Vector3 }

-- Sem Map.Phases: um volume por Map.Corredor.Chao_FaseN, cobrindo o chão (de
-- DERIVED_PHASE_BELOW abaixo até DERIVED_PHASE_ABOVE acima dele). Onde dois chãos
-- vizinhos se sobrepõem, a divisa fica no meio. As Parts não vão pro Workspace:
-- só servem pra GetPhaseAt e pro spawn dos totens.
local function derivePhasesFromFloors(map: Instance): boolean
	local corridor = map:FindFirstChild("Corredor")
	if corridor == nil then
		return false
	end

	local boxes: { FloorBox } = {}
	for index = 1, MAX_PHASES do
		local floor = corridor:FindFirstChild(`Chao_Fase{index}`)
		if floor then
			local low, high = worldBox(floor)
			if low and high then
				table.insert(boxes, { index = index, low = low, high = high })
			end
		end
	end
	if #boxes == 0 then
		return false
	end

	-- Eixo do corredor: o que mais varia entre a primeira e a última fase.
	local first = (boxes[1].low + boxes[1].high) / 2
	local last = (boxes[#boxes].low + boxes[#boxes].high) / 2
	local axis = if math.abs(last.X - first.X) >= math.abs(last.Z - first.Z) then Vector3.xAxis else Vector3.zAxis
	local function along(vector: Vector3): number
		return vector:Dot(axis)
	end
	local function withAlong(vector: Vector3, value: number): Vector3
		return vector + axis * (value - along(vector))
	end

	for i = 1, #boxes - 1 do
		local a, b = boxes[i], boxes[i + 1]
		if along(a.low + a.high) < along(b.low + b.high) then
			if along(a.high) > along(b.low) then
				local cut = (along(a.high) + along(b.low)) / 2
				a.high, b.low = withAlong(a.high, cut), withAlong(b.low, cut)
			end
		elseif along(b.high) > along(a.low) then
			local cut = (along(b.high) + along(a.low)) / 2
			b.high, a.low = withAlong(b.high, cut), withAlong(a.low, cut)
		end
	end

	for _, box in boxes do
		local low = box.low - Vector3.new(0, DERIVED_PHASE_BELOW, 0)
		local high = box.high + Vector3.new(0, DERIVED_PHASE_ABOVE, 0)
		local volume = Instance.new("Part")
		volume.Name = `Phase{box.index}`
		volume.Anchored = true
		volume.CanCollide = false
		volume.CanTouch = false
		volume.CanQuery = false
		volume.Transparency = 1
		volume.Size = high - low
		volume.CFrame = CFrame.new((low + high) / 2)
		phaseParts[box.index] = volume
		phaseCount = math.max(phaseCount, box.index)
	end
	warn(
		`[BaseService] Sem 'Workspace.Map.Phases': usando os chãos Map.Corredor.Chao_Fase1..{phaseCount} como fases `
			.. "(volume = chão + folga pra cima)"
	)
	return true
end

local function setupPhases(map: Instance)
	local folder = map:FindFirstChild("Phases")
	if folder then
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
	end

	if phaseCount == 0 and not derivePhasesFromFloors(map) then
		warn("[BaseService] Nem 'Workspace.Map.Phases.PhaseN' nem 'Workspace.Map.Corredor.Chao_FaseN' — o jogo fica sem fases")
		return
	end
	for index = 1, phaseCount do
		if not phaseParts[index] then
			warn(`[BaseService] Fase {index} não encontrada no mapa — essa fase nunca é detectada`)
		end
	end
end

local function phaseAt(position: Vector3): number?
	for index = 1, phaseCount do
		local part = phaseParts[index]
		if part and isInsidePart(part, position) then
			return index
		end
	end
	return nil
end

-- Parte central do corpo do NPC: o HumanoidRootPart ou, numa estátua sem ele, o tronco.
local function guardianBody(model: Model): BasePart?
	for _, name in { "HumanoidRootPart", "Torso", "UpperTorso" } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- A fase de um guardião é a do volume onde ele está (o número do nome só vale se
-- ele estiver fora de todas). Nome trocado gera warn, mas funciona.
local function setupGuardians(map: Instance)
	local folder = map:FindFirstChild("Guardians")
	if folder == nil then
		warn("[BaseService] 'Workspace.Map.Guardians' não encontrado — nenhuma fase tem guardião")
		return
	end

	for _, child in folder:GetChildren() do
		local path = `Workspace.Map.Guardians.{child.Name}`
		if not child:IsA("Model") then
			warn(`[BaseService] '{path}' precisa ser um Model (é {child.ClassName}); ignorado`)
			continue
		end
		local body = guardianBody(child)
		if body == nil then
			warn(`[BaseService] '{path}' não tem HumanoidRootPart nem Torso; ignorado`)
			continue
		end

		local digits = child.Name:match("^Guardian(%d+)$")
		local named = if digits then tonumber(digits) else nil
		local index = phaseAt(body.Position)
		if index == nil then
			index = named
			if index then
				warn(`[BaseService] '{path}' está fora de todas as fases; usando o número do nome (fase {index})`)
			end
		elseif named ~= index then
			warn(`[BaseService] '{path}' está na fase {index}; ele vira o guardião da fase {index} (renomeie para Guardian{index})`)
		end
		if index == nil or not phaseParts[index] then
			warn(`[BaseService] '{path}' não está em nenhuma fase e o nome não é GuardianN de uma fase existente; ignorado`)
			continue
		end
		if guardianModels[index] then
			warn(`[BaseService] Dois guardiões na fase {index}; '{path}' ignorado`)
			continue
		end
		guardianModels[index] = child
		guardianPosts[index] = body.CFrame
	end

	for index = 1, phaseCount do
		if phaseParts[index] and not guardianModels[index] then
			warn(`[BaseService] Fase {index} sem guardião`)
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
	setupGuardians(map)

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

-- NPC guardião da fase (o que está no volume dela), ou nil se a fase não tem guardião.
function BaseService:GetGuardian(index: number): Model?
	return guardianModels[index]
end

-- Posto do guardião da fase: CFrame do HumanoidRootPart (ou do tronco, numa estátua)
-- como estava no Studio.
function BaseService:GetGuardianPost(index: number): CFrame?
	return guardianPosts[index]
end

function BaseService:GetPhaseAt(position: Vector3): number?
	return phaseAt(position)
end

-- Se a posição já passou do começo da fase 1, do lado das bases (quem carrega
-- totem e chega aqui escapou do guardião). A direção do corredor é do centro da
-- fase 1 pro da fase 2; sem as duas, vale "fora de todas as fases".
function BaseService:IsBeforeFirstPhase(position: Vector3): boolean
	local first, second = phaseParts[1], phaseParts[2]
	local direction = if first and second then second.Position - first.Position else Vector3.zero
	direction = Vector3.new(direction.X, 0, direction.Z)
	if first == nil or direction.Magnitude < 1e-3 then
		return phaseAt(position) == nil
	end
	local axis = direction.Unit
	-- Meia-extensão da fase 1 ao longo do corredor (a Part pode estar girada).
	local cframe, half = first.CFrame, first.Size / 2
	local extent = math.abs(cframe.XVector:Dot(axis)) * half.X
		+ math.abs(cframe.YVector:Dot(axis)) * half.Y
		+ math.abs(cframe.ZVector:Dot(axis)) * half.Z
	return (position - first.Position):Dot(axis) < -extent
end

return BaseService
