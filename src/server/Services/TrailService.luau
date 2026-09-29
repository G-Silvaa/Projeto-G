--!strict

-- Rastro atrás do jogador quando ele corre (Config/Trails). Só visual: o Trail é
-- criado pelo servidor no HumanoidRootPart, então todo mundo vê. O rastro depende do
-- nível de velocidade treinado (SpeedService:GetSpeed); quando sobe de rastro, o
-- jogador recebe um Notify. Nos rastros com faíscas, elas só ligam enquanto o
-- jogador está correndo de verdade (velocidade no plano).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TrailsConfig = require(Config:WaitForChild("Trails"))
local StudioTest = require(Config:WaitForChild("StudioTest"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerDataService = require(script.Parent.PlayerDataService)
local SpeedService = require(script.Parent.SpeedService)

local TrailService = {}

-- Modo de teste do Studio: rastro mínimo forçado (0 = nenhum).
local STUDIO_TIER = if RunService:IsStudio() and StudioTest.Enabled
	then math.clamp(StudioTest.TrailTier, 0, #TrailsConfig.Tiers)
	else 0
-- Perna do R6 (o R6 não usa HipHeight).
local R6_LEG_HEIGHT = 2
-- Folga do rastro acima do chão.
local FLOOR_GAP = 0.2

type Visual = {
	tier: number,
	instances: { Instance },
	particles: ParticleEmitter?,
}

local visuals: { [Model]: Visual } = {}
-- Último rastro visto de cada jogador; nil = ainda não visto (sem aviso na entrada).
local knownTier: { [Player]: number } = {}

local function notify(player: Player, text: string)
	if player.Parent == Players then
		Remotes.getEvent(Remotes.Events.Notify):FireClient(player, text)
	end
end

local function colorSequence(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keypoints = {}
	for index, color in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keypoints)
end

-- Distância do centro do HumanoidRootPart até o chão.
local function groundOffset(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return root.Size.Y / 2 + R6_LEG_HEIGHT
end

local function clear(visual: Visual)
	for _, instance in visual.instances do
		instance:Destroy()
	end
end

-- Faixa vertical atrás das costas, dos pés até Height: o Trail liga as duas
-- pontas e desenha a faixa por onde o corpo passou.
local function build(character: Model, tierIndex: number): Visual?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return nil
	end
	local info = TrailsConfig.Tiers[tierIndex]

	local bottomY = -groundOffset(humanoid, root) + FLOOR_GAP
	-- Costas = +Z local (a frente é o LookVector, -Z).
	local backZ = root.Size.Z / 2

	local bottom = Instance.new("Attachment")
	bottom.Name = "SpeedTrailBottom"
	bottom.Position = Vector3.new(0, bottomY, backZ)
	bottom.Parent = root

	local top = Instance.new("Attachment")
	top.Name = "SpeedTrailTop"
	top.Position = Vector3.new(0, bottomY + info.Height, backZ)
	top.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "SpeedTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = colorSequence(info.Colors)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- Afina no fim.
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	trail.Lifetime = info.Lifetime
	trail.LightEmission = info.LightEmission
	trail.LightInfluence = 0
	trail.MinLength = 0.1
	trail.Parent = root

	local particles: ParticleEmitter? = nil
	if info.Particles then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "SpeedTrailSparks"
		emitter.Color = ColorSequence.new(info.Particles)
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4 + tierIndex * 0.03),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Lifetime = NumberRange.new(0.3, 0.6)
		emitter.Rate = 20 + tierIndex * 5
		emitter.Speed = NumberRange.new(2, 5)
		emitter.SpreadAngle = Vector2.new(50, 50)
		emitter.Acceleration = Vector3.new(0, 4, 0)
		emitter.EmissionDirection = Enum.NormalId.Back
		emitter.Enabled = false
		emitter.Parent = bottom
		particles = emitter
	end

	return { tier = tierIndex, instances = { trail, top, bottom }, particles = particles }
end

local function tierOf(player: Player): number
	return math.max(TrailsConfig.TierFor(SpeedService:GetSpeed(player)), STUDIO_TIER)
end

local function planarSpeed(character: Model): number
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return 0
	end
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function update(player: Player)
	if not PlayerDataService:IsLoaded(player) then
		return
	end
	local tierIndex = tierOf(player)

	local known = knownTier[player]
	if known and tierIndex > known then
		notify(player, `✨ Novo rastro: {TrailsConfig.Tiers[tierIndex].Name}!`)
	end
	knownTier[player] = tierIndex

	local character = player.Character
	if character == nil then
		return
	end
	local visual = visuals[character]
	if visual == nil or visual.tier ~= tierIndex then
		if visual then
			clear(visual)
		end
		visual = if tierIndex > 0 then build(character, tierIndex) else nil
		visuals[character] = visual
	end

	if visual and visual.particles then
		visual.particles.Enabled = planarSpeed(character) >= TrailsConfig.ParticlesMinSpeed
	end
end

function TrailService:Start()
	local function watch(player: Player)
		player.CharacterRemoving:Connect(function(character: Model)
			visuals[character] = nil
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		knownTier[player] = nil
		if player.Character then
			visuals[player.Character] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(TrailsConfig.UpdateInterval)
			for _, player in Players:GetPlayers() do
				update(player)
			end
		end
	end)
end

return TrailService
