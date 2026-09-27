--!strict

-- Esqueleto do mapa em Workspace.Map: corredor com paredões e 4 biomas,
-- volumes das fases (Phase1..4), Lobby, KillZone e a pasta Bases vazia.
-- As bases (Map.Bases.Base1..Base5) são colocadas à mão: o ringue inteiro (Model) ou uma Part no centro dele.
--
-- Uso: com o jogo parado (modo edição), cole o arquivo inteiro em
-- View > Command Bar, aperte Enter e salve o place.
-- Não é um serviço e não roda no jogo; o Rojo não sincroniza a pasta tools/.

local Workspace = game:GetService("Workspace")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

-- ===== Medidas (ajuste antes de rodar) =====

-- Onde o corredor começa: no chão, no meio entre os dois grupos de ringues.
-- Dica: coloque uma Part nesse ponto e copie a Position dela.
local CORRIDOR_START = Vector3.new(0, 0, 0)
-- Direção do corredor, em graus: 0 = para -Z, 90 = para -X, 180 = para +Z, -90 = para +X.
local CORRIDOR_YAW = 0

local CORRIDOR_WIDTH = 36
local FLOOR_THICKNESS = 2
local WALL_HEIGHT = 30
local WALL_THICKNESS = 4
local GRASS_THICKNESS = 1.5

local STRIPE_WIDTH = 3
local NEON_LINE_WIDTH = 0.6
-- Faixas e linhas neon ficam um pouco acima do chão pra não dar z-fighting.
local SURFACE_LIFT = 0.02

-- Lobby: logo atrás da boca do corredor, entre os dois grupos de ringues.
local LOBBY_WIDTH = CORRIDOR_WIDTH
local LOBBY_DEPTH = 24

-- KillZone: invisível, KILLZONE_DEPTH abaixo do chão, com folga pros lados.
local KILLZONE_DEPTH = 40
local KILLZONE_MARGIN = 500
local KILLZONE_THICKNESS = 4

local WALL_COLOR = Color3.fromRGB(130, 115, 95)
local GRASS_COLOR = Color3.fromRGB(90, 180, 70)
local STRIPE_COLOR = Color3.fromRGB(255, 255, 255)
local LOBBY_COLOR = Color3.fromRGB(190, 180, 160)

type Biome = {
	Name: string,
	Length: number,
	Color: Color3,
	Material: Enum.Material,
	NeonColors: { Color3 }?,
}

-- Uma entrada por fase, a partir das bases (vira Phase1, Phase2, ...).
local BIOMES: { Biome } = {
	{
		Name = "VilaNinja",
		Length = 150,
		Color = Color3.fromRGB(150, 215, 110),
		Material = Enum.Material.Grass,
	},
	{
		Name = "DojoDaMontanha",
		Length = 150,
		Color = Color3.fromRGB(215, 222, 230),
		Material = Enum.Material.Slate,
	},
	{
		Name = "CidadeNeon",
		Length = 150,
		Color = Color3.fromRGB(25, 25, 35),
		Material = Enum.Material.Asphalt,
		NeonColors = {
			Color3.fromRGB(0, 230, 255),
			Color3.fromRGB(255, 60, 200),
			Color3.fromRGB(0, 230, 255),
		},
	},
	{
		Name = "MundoEspiritual",
		Length = 150,
		Color = Color3.fromRGB(60, 30, 90),
		Material = Enum.Material.Marble,
	},
}

-- ===== Fim das medidas =====

local MAX_PART_SIZE = 2048
local ORIGIN = CFrame.new(CORRIDOR_START) * CFrame.Angles(0, math.rad(CORRIDOR_YAW), 0)

local TOTAL_LENGTH = 0
for _, biome in BIOMES do
	TOTAL_LENGTH += biome.Length
end

-- Coordenadas locais: o corredor vai para -Z a partir de 0; o Lobby fica em +Z.
local function at(x: number, y: number, z: number): CFrame
	return ORIGIN * CFrame.new(x, y, z)
end

local function newFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function makePart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Faixa fina rente ao chão, sem colisão.
local function makeSurfaceStrip(
	name: string,
	sizeX: number,
	sizeZ: number,
	x: number,
	z: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance
)
	local part = makePart(name, Vector3.new(sizeX, 0.2, sizeZ), at(x, SURFACE_LIFT + 0.1, z), color, material, parent)
	part.CanCollide = false
	part.CastShadow = false
end

-- Marcador invisível e sem colisão. canTouch só na KillZone.
local function makeMarker(name: string, size: Vector3, cframe: CFrame, canTouch: boolean, parent: Instance)
	local part = makePart(name, size, cframe, Color3.fromRGB(255, 0, 0), Enum.Material.SmoothPlastic, parent)
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = canTouch
	part.CanQuery = false
	part.CastShadow = false
end

-- Parent = nil em vez de Destroy() pra continuar dando pra desfazer com Ctrl+Z.
local function removeTemplateParts()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("Part") then
		baseplate.Parent = nil
		print("[BuildMap] Baseplate do template removido")
	end

	local defaultSpawn = Workspace:FindFirstChild("SpawnLocation")
	if defaultSpawn and defaultSpawn:IsA("SpawnLocation") then
		defaultSpawn.Parent = nil
		print("[BuildMap] SpawnLocation do template removido")
	end
end

local function build(existingMap: Instance?)
	removeTemplateParts()

	local map: Instance = existingMap or newFolder("Map", Workspace)
	if map:FindFirstChild("Bases") == nil then
		newFolder("Bases", map)
	end
	local corridor = newFolder("Corridor", map)
	local phases = newFolder("Phases", map)

	local cursor = 0
	for index, biome in BIOMES do
		local centerZ = -(cursor + biome.Length / 2)

		makePart(
			biome.Name,
			Vector3.new(CORRIDOR_WIDTH, FLOOR_THICKNESS, biome.Length),
			at(0, -FLOOR_THICKNESS / 2, centerZ),
			biome.Color,
			biome.Material,
			corridor
		)

		local neonColors = biome.NeonColors
		if neonColors then
			for i, color in neonColors do
				local x = -CORRIDOR_WIDTH / 2 + i * CORRIDOR_WIDTH / (#neonColors + 1)
				-- Mais curta que a fase pra não encostar nas faixas de transição.
				makeSurfaceStrip(
					`{biome.Name}Neon{i}`,
					NEON_LINE_WIDTH,
					biome.Length - STRIPE_WIDTH,
					x,
					centerZ,
					color,
					Enum.Material.Neon,
					corridor
				)
			end
		end

		if index > 1 then
			makeSurfaceStrip(
				`Stripe{index - 1}`,
				CORRIDOR_WIDTH,
				STRIPE_WIDTH,
				0,
				-cursor,
				STRIPE_COLOR,
				Enum.Material.SmoothPlastic,
				corridor
			)
		end

		-- Do chão até o topo dos paredões, cobrindo exatamente o bioma.
		makeMarker(
			`Phase{index}`,
			Vector3.new(CORRIDOR_WIDTH, WALL_HEIGHT, biome.Length),
			at(0, WALL_HEIGHT / 2, centerZ),
			false,
			phases
		)

		cursor += biome.Length
	end

	-- Paredões descem até a base do chão e os laterais cobrem os cantos do fundo,
	-- assim nenhuma peça se sobrepõe a outra.
	local wallTall = WALL_HEIGHT + FLOOR_THICKNESS
	local wallCenterY = (WALL_HEIGHT - FLOOR_THICKNESS) / 2
	local sideLength = TOTAL_LENGTH + WALL_THICKNESS
	local grassY = WALL_HEIGHT + GRASS_THICKNESS / 2

	for _, side in { -1, 1 } do
		local sideName = if side < 0 then "Left" else "Right"
		local x = side * (CORRIDOR_WIDTH / 2 + WALL_THICKNESS / 2)
		makePart(
			`Wall{sideName}`,
			Vector3.new(WALL_THICKNESS, wallTall, sideLength),
			at(x, wallCenterY, -sideLength / 2),
			WALL_COLOR,
			Enum.Material.Rock,
			corridor
		)
		makePart(
			`Grass{sideName}`,
			Vector3.new(WALL_THICKNESS, GRASS_THICKNESS, sideLength),
			at(x, grassY, -sideLength / 2),
			GRASS_COLOR,
			Enum.Material.Grass,
			corridor
		)
	end

	local endZ = -(TOTAL_LENGTH + WALL_THICKNESS / 2)
	makePart(
		"WallEnd",
		Vector3.new(CORRIDOR_WIDTH, wallTall, WALL_THICKNESS),
		at(0, wallCenterY, endZ),
		WALL_COLOR,
		Enum.Material.Rock,
		corridor
	)
	makePart(
		"GrassEnd",
		Vector3.new(CORRIDOR_WIDTH, GRASS_THICKNESS, WALL_THICKNESS),
		at(0, grassY, endZ),
		GRASS_COLOR,
		Enum.Material.Grass,
		corridor
	)

	-- Encostado na boca do corredor: quem nasce aqui entra direto na pista.
	makePart(
		"Lobby",
		Vector3.new(LOBBY_WIDTH, FLOOR_THICKNESS, LOBBY_DEPTH),
		at(0, -FLOOR_THICKNESS / 2, LOBBY_DEPTH / 2),
		LOBBY_COLOR,
		Enum.Material.Slate,
		map
	)

	local killWidth = CORRIDOR_WIDTH + 2 * WALL_THICKNESS + 2 * KILLZONE_MARGIN
	local killLength = LOBBY_DEPTH + TOTAL_LENGTH + WALL_THICKNESS + 2 * KILLZONE_MARGIN
	if killWidth > MAX_PART_SIZE or killLength > MAX_PART_SIZE then
		warn(`[BuildMap] KillZone passou de {MAX_PART_SIZE} studs e foi cortada; reduza KILLZONE_MARGIN`)
	end
	makeMarker(
		"KillZone",
		Vector3.new(math.min(killWidth, MAX_PART_SIZE), KILLZONE_THICKNESS, math.min(killLength, MAX_PART_SIZE)),
		at(0, -KILLZONE_DEPTH, (LOBBY_DEPTH - TOTAL_LENGTH - WALL_THICKNESS) / 2),
		true,
		map
	)
end

local function main()
	-- Workspace.Map pode já existir (ex.: com os ringues dentro): só recusa se
	-- alguma das coisas que este script cria já estiver lá.
	local existingMap = Workspace:FindFirstChild("Map")
	if existingMap then
		for _, name in { "Corridor", "Phases", "Lobby", "KillZone" } do
			if existingMap:FindFirstChild(name) then
				warn(`[BuildMap] Workspace.Map.{name} já existe — nada foi criado nem apagado.`)
				return
			end
		end
	end

	-- Tudo numa etapa só de Ctrl+Z, se o Studio deixar gravar pela Barra de comandos.
	local recordingOk, recording = pcall(function()
		return ChangeHistoryService:TryBeginRecording("BuildMap")
	end)
	local recordingId = if recordingOk then recording else nil

	local ok, err = pcall(function()
		build(existingMap)
	end)

	if recordingId then
		ChangeHistoryService:FinishRecording(
			recordingId,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end

	if not ok then
		warn(`[BuildMap] Erro: {err}`)
		if recordingId == nil then
			warn("[BuildMap] Pode ter ficado algo pela metade em Workspace.Map; apague antes de rodar de novo.")
		end
		return
	end

	print(`[BuildMap] Pronto: {#BIOMES} fases, corredor de {TOTAL_LENGTH} studs.`)
	print("[BuildMap] Agora coloque Base1..Base5 em Workspace.Map.Bases (o ringue inteiro como Model, ou uma Part no centro dele) e salve o place.")
end

main()
