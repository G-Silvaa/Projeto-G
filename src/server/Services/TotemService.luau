--!strict

-- Monta o visual dos totens a partir dos modelos do ServerStorage (ver
-- Config/Totems). Quem posiciona é quem chama: ScrollService (chão das fases e
-- carregando) e WarriorService (chocando na base). Só visual: nada aqui decide
-- regra de jogo.
--
-- Todo totem sai com o pivot no centro da base do modelo, alinhado aos eixos do
-- mundo: PivotTo(CFrame.new(pontoNoChão)) deixa ele em pé no chão.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local TotemsConfig = require(Config:WaitForChild("Totems"))

local TotemService = {}

local TEMPLATE_NAME = "TotemTemplate"
local TINT_ATTRIBUTE = "RarityTint"
local HEIGHT_ATTRIBUTE = "TotemHeight"
local LABEL_MAX_DISTANCE = 80
-- Espaço entre o topo do totem e o letreiro.
local LABEL_GAP = 0.8
-- Hitbox mínima pra pegar no chão, mesmo com um totem fino.
local MIN_HITBOX = 2

type Template = {
	model: Model,
	tint: boolean, -- TotemTemplate: pinta pela raridade; Totem_<Rarity>: usa como está
}

local templates: { [string]: Template } = {}
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

local function findTemplate(name: string): Model?
	local instance = ServerStorage:FindFirstChild(name)
	if instance == nil then
		return nil
	end
	if not instance:IsA("Model") then
		warn(`[TotemService] ServerStorage.{name} precisa ser um Model (é {instance.ClassName}); ignorado`)
		return nil
	end
	if instance:FindFirstChildWhichIsA("BasePart", true) == nil then
		warn(`[TotemService] ServerStorage.{name} não tem nenhuma peça; ignorado`)
		return nil
	end
	return instance
end

local function parts(model: Model): { BasePart }
	local list: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

local function largestPart(model: Model): BasePart?
	local best: BasePart? = nil
	local bestVolume = -1
	for _, part in parts(model) do
		local volume = part.Size.X * part.Size.Y * part.Size.Z
		if volume > bestVolume then
			best = part
			bestVolume = volume
		end
	end
	return best
end

-- Pinta a peça. Peça de acessório (SpecialMesh com textura) ignora a cor da peça:
-- nela, a textura é tingida pelo VertexColor.
local function tint(part: BasePart, color: Color3)
	part.Color = color
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		mesh.VertexColor = Vector3.new(color.R, color.G, color.B)
	end
end

local function tintedParts(model: Model): { BasePart }
	local list: { BasePart } = {}
	for _, part in parts(model) do
		if part:GetAttribute(TINT_ATTRIBUTE) == true then
			table.insert(list, part)
		end
	end
	return list
end

-- Modelo da Loja pode trazer script (até malicioso), e script clonado pro Workspace roda.
local function stripScripts(model: Model, sourceName: string)
	local removed: { string } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
			table.insert(removed, descendant.Name)
			descendant:Destroy()
		end
	end
	if #removed > 0 then
		warnOnce(
			`scripts:{sourceName}`,
			`[TotemService] ServerStorage.{sourceName} tem scripts ({table.concat(removed, ", ")}); eles são removidos dos totens`
		)
	end
end

-- Meia-extensão da caixa nos eixos do mundo (a caixa pode vir girada).
local function worldHalfExtents(cframe: CFrame, size: Vector3): Vector3
	local x = cframe.XVector * (size.X / 2)
	local y = cframe.YVector * (size.Y / 2)
	local z = cframe.ZVector * (size.Z / 2)
	return Vector3.new(
		math.abs(x.X) + math.abs(y.X) + math.abs(z.X),
		math.abs(x.Y) + math.abs(y.Y) + math.abs(z.Y),
		math.abs(x.Z) + math.abs(y.Z) + math.abs(z.Z)
	)
end

-- Põe o pivot no centro da base do modelo e devolve o tamanho (eixos do mundo).
local function normalizePivot(model: Model): Vector3
	local boxCFrame, boxSize = model:GetBoundingBox()
	local half = worldHalfExtents(boxCFrame, boxSize)
	model.WorldPivot = CFrame.new(boxCFrame.Position - Vector3.new(0, half.Y, 0))
	return half * 2
end

-- O visual antigo (cilindro neon), quando não há template.
local function fallbackModel(rarity: string): Model
	local model = Instance.new("Model")
	local part = Instance.new("Part")
	part.Name = "Totem"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(2.4, 0.8, 0.8)
	part.Material = Enum.Material.Neon
	part.Color = Rarities[rarity].Color
	part.CastShadow = false
	part.Parent = model
	model.PrimaryPart = part
	return model
end

local function addLabel(model: Model, primary: BasePart, rarity: string, height: number)
	local info = Rarities[rarity]

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Adornee = primary
	billboard.Size = UDim2.fromOffset(120, 28)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, model.WorldPivot.Y + height - primary.Position.Y + LABEL_GAP, 0)
	billboard.MaxDistance = LABEL_MAX_DISTANCE
	billboard.LightInfluence = 0
	billboard.Parent = primary

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = info.DisplayName
	label.TextColor3 = info.Color
	-- Contorno claro pra ler bem em qualquer cor, inclusive o preto do Secreto.
	label.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard
end

-- Novo totem da raridade, ancorado, sem colisão, sem toque e invisível pra raios.
-- height: altura final em studs (nil ou 0 = tamanho do template). withLabel: letreiro
-- com a raridade acima do totem. Sem parent: quem chama posiciona e parenteia.
function TotemService:Create(rarity: string, height: number?, withLabel: boolean): Model
	if not Rarities[rarity] then
		error(`[TotemService] Raridade inválida: '{rarity}'`, 2)
	end

	local template = templates[rarity]
	local model: Model
	if template then
		model = template.model:Clone()
		stripScripts(model, template.model.Name)
	else
		model = fallbackModel(rarity)
	end
	model.Name = "Totem"

	local primary = model.PrimaryPart or largestPart(model)
	assert(primary, "[TotemService] Totem sem peças")
	model.PrimaryPart = primary

	for _, part in parts(model) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
	end

	if template and template.tint then
		local color = Rarities[rarity].Color
		local tinted = tintedParts(model)
		if #tinted == 0 then
			tinted = { primary }
		end
		for _, part in tinted do
			tint(part, color)
		end
	end

	if TotemsConfig.LightRange > 0 then
		local light = Instance.new("PointLight")
		light.Color = Rarities[rarity].Color
		light.Range = TotemsConfig.LightRange
		light.Brightness = 1
		light.Shadows = false
		light.Parent = primary
	end

	local size = normalizePivot(model)
	if height and height > 0 and size.Y > 0 then
		model:ScaleTo(model:GetScale() * height / size.Y)
		size = normalizePivot(model)
	end
	model:SetAttribute(HEIGHT_ATTRIBUTE, size.Y)

	if withLabel then
		addLabel(model, primary, rarity, size.Y)
	end
	return model
end

-- Altura do totem (studs), do chão ao topo.
function TotemService:GetHeight(model: Model): number
	local height = model:GetAttribute(HEIGHT_ATTRIBUTE)
	return if typeof(height) == "number" then height else 0
end

-- Se a raridade tem modelo (TotemTemplate ou Totem_<Rarity>); false = visual antigo.
function TotemService:HasTemplate(rarity: string): boolean
	return templates[rarity] ~= nil
end

-- Part invisível do tamanho do totem, no centro dele (segura o prompt "Pegar" e
-- serve de medida da distância). Chame antes de mover o totem: ela vai junto no PivotTo.
function TotemService:AddHitbox(model: Model): BasePart
	local boxCFrame, boxSize = model:GetBoundingBox()
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox.CanTouch = false
	hitbox.CastShadow = false
	hitbox.Size = boxSize:Max(Vector3.one * MIN_HITBOX)
	hitbox.CFrame = boxCFrame
	hitbox.Parent = model
	return hitbox
end

local function bodyPart(character: Model, name: string): BasePart?
	local part = character:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

-- Prende o totem no personagem (costas ou acima da cabeça, Config/Totems.CarryMount),
-- sem colisão e sem massa, pra não atrapalhar o movimento. Chame logo depois do
-- Create, antes de girar o totem. false se o personagem não tem onde prender.
function TotemService:MountOn(model: Model, character: Model): boolean
	local anchor: BasePart? = nil
	local offset = CFrame.identity
	if TotemsConfig.CarryMount == "Head" then
		local head = bodyPart(character, "Head")
		if head then
			anchor = head
			offset = CFrame.new(0, head.Size.Y / 2 + 0.3, 0)
		end
	else
		local torso = bodyPart(character, "UpperTorso") or bodyPart(character, "Torso")
		if torso then
			local boxCFrame, boxSize = model:GetBoundingBox()
			local depth = worldHalfExtents(boxCFrame, boxSize).Z * 2
			anchor = torso
			-- Costas = +Z local do tronco (a frente é o LookVector, -Z).
			offset = CFrame.new(0, -torso.Size.Y / 2, torso.Size.Z / 2 + depth / 2 + 0.1)
		end
	end
	if anchor == nil then
		anchor = bodyPart(character, "HumanoidRootPart")
		offset = CFrame.new(0, 3, 0)
	end
	if anchor == nil then
		return false
	end
	return TotemService:AttachTo(model, anchor, offset)
end

-- Prende o totem numa peça (ex.: a mão do guardião), com o pivot (centro da base do
-- totem) em anchor.CFrame * offset. Sem colisão e sem massa. false se o totem não
-- tem peça principal.
function TotemService:AttachTo(model: Model, anchor: BasePart, offset: CFrame): boolean
	local primary = model.PrimaryPart
	if primary == nil then
		return false
	end

	model:PivotTo(anchor.CFrame * offset)
	for _, part in parts(model) do
		if part ~= primary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = part
			weld.Parent = part
		end
		part.Massless = true
		part.Anchored = false
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = primary
	weld.Parent = primary
	return true
end

function TotemService:Init()
	local generic = findTemplate(TEMPLATE_NAME)
	if generic == nil then
		warn(`[TotemService] ServerStorage.{TEMPLATE_NAME} não encontrado; raridades sem Totem_<Rarity> usam o visual antigo`)
	elseif #tintedParts(generic) == 0 then
		warn(
			`[TotemService] Nenhuma peça de {TEMPLATE_NAME} tem o atributo {TINT_ATTRIBUTE} = true; a cor da raridade vai na peça principal`
		)
	end

	for id in Rarities do
		local specific = findTemplate(`Totem_{id}`)
		if specific then
			templates[id] = { model = specific, tint = false }
		elseif generic then
			templates[id] = { model = generic, tint = true }
		end
	end

	-- Ajuda a achar erro de digitação (ex.: Totem_Lendario em vez de Totem_Legendary).
	for _, child in ServerStorage:GetChildren() do
		local suffix = string.match(child.Name, "^Totem_(.+)$")
		if suffix and not Rarities[suffix] then
			warn(`[TotemService] ServerStorage.{child.Name}: '{suffix}' não é um Id de raridade (use Common, Rare, Epic, Legendary, Mythic ou Secret)`)
		end
	end
end

return TotemService
