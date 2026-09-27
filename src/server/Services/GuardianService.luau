--!strict

-- Um guardião (NPC R15) por fase. Fica no posto, no centro do chão da fase, e só
-- persegue quem carrega pergaminho dentro da fase dele. Se alcançar, o pergaminho
-- volta para a fase de origem e o jogador é arremessado (sem dano).
-- Tudo decidido no servidor, em intervalos (Config/Guardians.UpdateInterval).

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

local GUARDIAN_COLOR = Color3.fromRGB(90, 20, 30)

type Guardian = {
	phase: number,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	post: Vector3,
	speed: number,
	cooldownUntil: number,
}

local guardians: { Guardian } = {}
local guardianFolder: Folder? = nil

local function floorAtCenter(volume: BasePart): Vector3?
	local exclude: { Instance } = { volume }
	if guardianFolder then
		table.insert(exclude, guardianFolder)
	end
	local scrolls = Workspace:FindFirstChild("PhaseScrolls")
	if scrolls then
		table.insert(exclude, scrolls)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude

	local top = volume.CFrame * Vector3.new(0, volume.Size.Y / 2, 0)
	local result = Workspace:Raycast(top, Vector3.new(0, -(volume.Size.Y + 2), 0), params)
	return if result then result.Position else nil
end

local function createGuardian(phase: number, volume: BasePart, speed: number): Guardian?
	local post = floorAtCenter(volume)
	if post == nil then
		warn(`[GuardianService] Não achei o chão no centro da Phase{phase}; fase sem guardião`)
		return nil
	end

	local description = Instance.new("HumanoidDescription")
	description.HeadColor = GUARDIAN_COLOR
	description.TorsoColor = GUARDIAN_COLOR
	description.LeftArmColor = GUARDIAN_COLOR
	description.RightArmColor = GUARDIAN_COLOR
	description.LeftLegColor = GUARDIAN_COLOR
	description.RightLegColor = GUARDIAN_COLOR

	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or result == nil then
		warn(`[GuardianService] Falha ao criar o guardião da Phase{phase}: {result}`)
		return nil
	end

	local model = result :: Model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		model:Destroy()
		warn(`[GuardianService] Guardião da Phase{phase} veio sem Humanoid/HumanoidRootPart`)
		return nil
	end

	model.Name = `Guardian{phase}`
	humanoid.DisplayName = `Guardião da fase {phase}`
	humanoid.WalkSpeed = speed
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.BreakJointsOnDeath = false
	model:PivotTo(CFrame.new(post + Vector3.new(0, 3, 0)))
	model.Parent = guardianFolder
	root:SetNetworkOwner(nil)

	return {
		phase = phase,
		model = model,
		humanoid = humanoid,
		root = root,
		post = post,
		speed = speed,
		cooldownUntil = 0,
	}
end

local function findTarget(guardian: Guardian): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, player in ScrollService:GetCarriers() do
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			if BaseService:GetPhaseAt(root.Position) == guardian.phase then
				local distance = (root.Position - guardian.root.Position).Magnitude
				if distance < bestDistance then
					best = root
					bestDistance = distance
				end
			end
		end
	end
	return best
end

-- O LinearVelocity replica e quem simula o personagem (o cliente dono) aplica o empurrão.
local function knockback(guardian: Guardian, targetRoot: BasePart)
	local away = targetRoot.Position - guardian.root.Position
	away = Vector3.new(away.X, 0, away.Z)
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

local function updateGuardian(guardian: Guardian, now: number)
	if now >= guardian.cooldownUntil then
		local targetRoot = findTarget(guardian)
		if targetRoot then
			-- Nas fases rápidas ele anda muito entre duas checagens: o raio cresce junto.
			local catchDistance = math.max(
				GuardiansConfig.CatchDistance,
				guardian.speed * GuardiansConfig.UpdateInterval * 0.5
			)
			if (targetRoot.Position - guardian.root.Position).Magnitude <= catchDistance then
				local player = Players:GetPlayerFromCharacter(targetRoot.Parent)
				if player then
					ScrollService:DropCarried(player)
					knockback(guardian, targetRoot)
					Remotes.getEvent(Remotes.Events.Notify):FireClient(player, "O guardião te pegou! O pergaminho voltou para a fase.")
				end
				guardian.cooldownUntil = now + GuardiansConfig.CatchCooldown
			else
				guardian.humanoid:MoveTo(targetRoot.Position)
				return
			end
		end
	end

	local offset = guardian.root.Position - guardian.post
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > GuardiansConfig.PostTolerance then
		guardian.humanoid:MoveTo(guardian.post)
	end
end

function GuardianService:Init()
	local folder = Instance.new("Folder")
	folder.Name = "Guardians"
	folder.Parent = Workspace
	guardianFolder = folder
end

function GuardianService:Start()
	for phase = 1, BaseService:GetPhaseCount() do
		local volume = BaseService:GetPhasePart(phase)
		local speed = GuardiansConfig.Speeds[phase]
		if volume == nil then
			continue
		end
		if speed == nil then
			warn(`[GuardianService] Config/Guardians não tem velocidade para a fase {phase}; fase sem guardião`)
			continue
		end
		local guardian = createGuardian(phase, volume, speed)
		if guardian then
			table.insert(guardians, guardian)
		end
	end

	task.spawn(function()
		while true do
			task.wait(GuardiansConfig.UpdateInterval)
			local now = os.clock()
			for _, guardian in guardians do
				updateGuardian(guardian, now)
			end
		end
	end)
end

return GuardianService
