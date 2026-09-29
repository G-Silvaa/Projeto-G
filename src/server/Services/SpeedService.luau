--!strict

-- Velocidade do jogador: treino na esteira da própria base, Speed (o nível de
-- velocidade) salvo no PlayerData, WalkSpeed = Config/Speed.RealSpeed(Speed)
-- aplicado ao personagem e o nível formatado no leaderstats.
--
-- A esteira é uma Part ancorada com AssemblyLinearVelocity (esteira rolante) que
-- empurra no sentido do LookVector dela, na mesma velocidade que o dono anda.
-- Parado, o jogador é levado para fora dela; só fica em cima quem corre contra.
-- Por isso "estar em cima da esteira" basta para treinar, sem confiar no cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Config = Shared:WaitForChild("Config")
local SpeedConfig = require(Config:WaitForChild("Speed"))
local StudioTest = require(Config:WaitForChild("StudioTest"))

local BaseService = require(script.Parent.BaseService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local SpeedService = {}

-- Modo de teste do Studio: só mexe no WalkSpeed, nunca no Speed salvo.
local STUDIO_OVERRIDE = RunService:IsStudio() and StudioTest.Enabled
-- Folga da borda do ringue para a esteira criada pelo servidor.
local TREADMILL_EDGE_MARGIN = 2

local treadmills: { [number]: BasePart } = {}
local trainingMultiplierProviders: { (Player) -> number } = {}

local function getSpeed(player: Player): number
	local speed = PlayerDataService:Get(player, "Speed")
	return if typeof(speed) == "number" then speed else 0
end

local function currentWalkSpeed(player: Player): number
	local walkSpeed = SpeedConfig.RealSpeed(getSpeed(player))
	if STUDIO_OVERRIDE then
		walkSpeed = math.max(walkSpeed, StudioTest.WalkSpeed)
	end
	return walkSpeed
end

local function trainingMultiplier(player: Player): number
	local multiplier = 1
	for _, provider in trainingMultiplierProviders do
		multiplier *= provider(player)
	end
	return multiplier
end

local function getLeaderstats(player: Player): Folder
	local existing = player:FindFirstChild("leaderstats")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	folder.Parent = player
	return folder
end

-- StringValue formatado ("10K", "7B"...): o nível passa do limite de um IntValue.
local function getSpeedValue(player: Player): StringValue
	local leaderstats = getLeaderstats(player)
	local existing = leaderstats:FindFirstChild("Speed")
	if existing and existing:IsA("StringValue") then
		return existing
	end
	local value = Instance.new("StringValue")
	value.Name = "Speed"
	value.Parent = leaderstats
	return value
end

local function applySpeed(player: Player)
	if not PlayerDataService:IsLoaded(player) then
		return
	end
	getSpeedValue(player).Value = Format.number(getSpeed(player))
	-- Só para o HUD; o servidor nunca lê de volta.
	player:SetAttribute("Speed", math.floor(getSpeed(player)))

	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid.WalkSpeed = currentWalkSpeed(player)
	end
end

local function createTreadmill(baseIndex: number, parent: Instance): BasePart?
	local areaCFrame, areaSize = BaseService:GetBaseArea(baseIndex)
	if not areaCFrame or not areaSize then
		return nil
	end

	local size = SpeedConfig.TreadmillSize
	local edgeZ = math.max(areaSize.Z / 2 - TREADMILL_EDGE_MARGIN - size.Z / 2, 0)

	-- Na borda +Z da área; o LookVector (local -Z) aponta para o centro do ringue.
	local part = Instance.new("Part")
	part.Name = "Treadmill"
	part.Anchored = true
	part.Size = size
	part.CFrame = areaCFrame * CFrame.new(0, size.Y / 2 + 0.02, edgeZ)
	part.Color = SpeedConfig.TreadmillColor
	part.Material = Enum.Material.DiamondPlate
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function setupTreadmills()
	for index = 1, BaseService:GetBaseCount() do
		local marker = BaseService:GetBaseInstance(index)
		if marker == nil then
			continue
		end
		local existing = marker:FindFirstChild("Treadmill", true)
		if existing and existing:IsA("BasePart") then
			treadmills[index] = existing
		else
			local created = createTreadmill(index, marker)
			if created then
				treadmills[index] = created
			end
		end
	end
end

local function isOnTreadmill(player: Player, treadmill: BasePart): boolean
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	local relative = treadmill.CFrame:PointToObjectSpace(root.Position)
	local half = treadmill.Size / 2
	return math.abs(relative.X) <= half.X
		and math.abs(relative.Z) <= half.Z
		and relative.Y >= 0
		and relative.Y <= half.Y + SpeedConfig.TreadmillHeight
end

local function trainingTick()
	for baseIndex, treadmill in treadmills do
		local owner = BaseService:GetOwner(baseIndex)
		local beltSpeed = if owner then currentWalkSpeed(owner) else SpeedConfig.BaseWalkSpeed
		treadmill.AssemblyLinearVelocity = treadmill.CFrame.LookVector * beltSpeed

		if owner and PlayerDataService:IsLoaded(owner) and isOnTreadmill(owner, treadmill) then
			local multiplier = SpeedConfig.TrainingTick * trainingMultiplier(owner)
			PlayerDataService:Update(owner, "Speed", function(old: number): number
				local perSecond = math.max(SpeedConfig.MinGainPerSecond, old * SpeedConfig.GainPercentPerSecond)
				return math.min(old + perSecond * multiplier, SpeedConfig.MaxLevel)
			end)
			applySpeed(owner)
		end
	end
end

-- Outros serviços (upgrades, Game Pass) registram multiplicadores do treino.
function SpeedService:AddTrainingMultiplier(provider: (Player) -> number)
	table.insert(trainingMultiplierProviders, provider)
end

function SpeedService:GetSpeed(player: Player): number
	return getSpeed(player)
end

function SpeedService:Start()
	if STUDIO_OVERRIDE then
		warn(`[SpeedService] Modo de teste do Studio: WalkSpeed mínimo {StudioTest.WalkSpeed} (não é salvo como Speed)`)
	end

	setupTreadmills()

	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			character:WaitForChild("Humanoid", 5)
			applySpeed(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	PlayerDataService:OnPlayerLoaded(applySpeed)

	task.spawn(function()
		while true do
			task.wait(SpeedConfig.TrainingTick)
			trainingTick()
		end
	end)
end

return SpeedService
