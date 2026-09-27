--!strict

-- Pergaminhos, chocagem e guerreiros. Cada jogador tem até SLOTS_PER_BASE slots,
-- colocados em qualquer ponto do próprio ringue. Um pergaminho entregue ocupa um
-- slot e choca por um tempo que depende da raridade; o início é salvo como
-- horário (os.time()), então a chocagem continua com o jogador offline. Ao
-- terminar, vira um guerreiro sorteado daquela raridade, que gera dinheiro por
-- segundo enquanto o dono está no jogo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local Warriors = require(Config:WaitForChild("Warriors"))

local BaseService = require(script.Parent.BaseService)
local CurrencyService = require(script.Parent.CurrencyService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local WarriorService = {}

-- Limite de slots por base; vira valor por jogador quando existirem upgrades.
local SLOTS_PER_BASE = 6
-- Distância mínima (studs, no chão) entre dois slots do mesmo jogador.
local MIN_SLOT_DISTANCE = 6
-- Folga da borda da área do ringue, pra não cair em cima das cordas.
local EDGE_MARGIN = 2
-- Faixa de altura aceita em relação ao piso do ringue (dos pés até um pulo).
local MAX_BELOW_FLOOR = 4
local MAX_ABOVE_FLOOR = 12
-- Os letreiros dos slots só aparecem de perto.
local LABEL_MAX_DISTANCE = 60

type Warrior = Warriors.Warrior

-- Como fica salvo em PlayerData.Slots, com a chave "1".."N".
-- OffsetX/OffsetZ: posição relativa ao centro da base (BaseService:GetBaseArea).
type SlotData = {
	Rarity: string,
	StartedAt: number,
	OffsetX: number,
	OffsetZ: number,
	WarriorId: string?,
}

type SlotsData = { [string]: SlotData }

export type SlotInfo = {
	Index: number,
	Rarity: string,
	StartedAt: number,
	ReadyAt: number,
	WarriorId: string?, -- nil enquanto choca
	Offset: Vector3, -- relativo ao centro da base; Y sempre 0
}

type SlotVisual = {
	part: Part,
	nameLabel: TextLabel,
	rarityLabel: TextLabel,
	statusLabel: TextLabel,
}

type PlayerVisuals = {
	folder: Folder,
	slots: { [string]: SlotVisual },
}

local warriorsById: { [string]: Warrior } = {}
local warriorsByRarity: { [string]: { Warrior } } = {}
local visualsByPlayer: { [Player]: PlayerVisuals } = {}
local warnedAbout: { [string]: boolean } = {}
local visualsRoot: Folder? = nil
local random = Random.new()

local function warnOnce(key: string, message: string)
	if warnedAbout[key] then
		return
	end
	warnedAbout[key] = true
	warn(message)
end

local function isFiniteVector(vector: Vector3): boolean
	for _, value in { vector.X, vector.Y, vector.Z } do
		if value ~= value or value == math.huge or value == -math.huge then
			return false
		end
	end
	return true
end

local function readyAt(slot: SlotData): number?
	local rarity = Rarities[slot.Rarity]
	if not rarity then
		warnOnce(`rarity:{slot.Rarity}`, `[WarriorService] Raridade desconhecida nos dados: '{slot.Rarity}'`)
		return nil
	end
	return slot.StartedAt + rarity.HatchSeconds
end

local function drawWarrior(rarityId: string): string?
	local pool = warriorsByRarity[rarityId]
	if not pool or #pool == 0 then
		return nil
	end
	return pool[random:NextInteger(1, #pool)].Id
end

local function getSlots(player: Player): SlotsData?
	return PlayerDataService:Get(player, "Slots")
end

local function getArea(player: Player): (CFrame?, Vector3?)
	local baseIndex = BaseService:GetBase(player)
	if baseIndex == nil then
		return nil, nil
	end
	return BaseService:GetBaseArea(baseIndex)
end

local function resolvePosition(player: Player, position: Vector3?): Vector3?
	if position then
		return position
	end
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- Posição no chão relativa ao centro da base, ou nil se estiver fora da área do ringue.
local function toOffset(areaCFrame: CFrame, areaSize: Vector3, position: Vector3): Vector3?
	local relative = areaCFrame:PointToObjectSpace(position)
	if math.abs(relative.X) > areaSize.X / 2 - EDGE_MARGIN or math.abs(relative.Z) > areaSize.Z / 2 - EDGE_MARGIN then
		return nil
	end
	if relative.Y < -MAX_BELOW_FLOOR or relative.Y > MAX_ABOVE_FLOOR then
		return nil
	end
	return Vector3.new(relative.X, 0, relative.Z)
end

-- Se a base desta sessão for menor que a da sessão em que o slot foi salvo,
-- traz o slot pra dentro dela.
local function clampOffset(areaSize: Vector3, x: number, z: number): (number, number)
	local limitX = math.max(areaSize.X / 2 - EDGE_MARGIN, 0)
	local limitZ = math.max(areaSize.Z / 2 - EDGE_MARGIN, 0)
	return math.clamp(x, -limitX, limitX), math.clamp(z, -limitZ, limitZ)
end

local function formatDuration(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local hours = math.floor(total / 3600)
	local minutes = math.floor((total % 3600) / 60)
	local secs = total % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%02d:%02d", minutes, secs)
end

local function newLabel(name: string, order: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.fromScale(1, 1 / 3)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.Parent = parent
	return label
end

local function createSlotVisual(key: string, parent: Instance): SlotVisual
	local part = Instance.new("Part")
	part.Name = `Slot{key}`
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Size = Vector3.new(3, 0.4, 3)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent

	-- Pequeno e só de perto: nada de letreiro gigante em cima da base.
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(170, 66)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.MaxDistance = LABEL_MAX_DISTANCE
	billboard.LightInfluence = 0
	billboard.Parent = part

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = billboard

	local rarityLabel = newLabel("Rarity", 2, billboard)
	-- Contorno claro pra ler bem em qualquer cor, inclusive o preto do Secreto.
	rarityLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
	rarityLabel.TextStrokeTransparency = 0.2

	return {
		part = part,
		nameLabel = newLabel("Name", 1, billboard),
		rarityLabel = rarityLabel,
		statusLabel = newLabel("Status", 3, billboard),
	}
end

local function getPlayerVisuals(player: Player): PlayerVisuals
	local existing = visualsByPlayer[player]
	if existing then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = tostring(player.UserId)
	folder.Parent = visualsRoot

	local created: PlayerVisuals = { folder = folder, slots = {} }
	visualsByPlayer[player] = created
	return created
end

local function clearVisuals(player: Player)
	local visuals = visualsByPlayer[player]
	if visuals then
		visuals.folder:Destroy()
		visualsByPlayer[player] = nil
	end
end

local function renderSlots(player: Player, slots: SlotsData, now: number)
	local areaCFrame, areaSize = getArea(player)
	if not areaCFrame or not areaSize then
		return
	end

	local visuals = getPlayerVisuals(player)

	for key, slot in slots do
		local visual = visuals.slots[key]
		if not visual then
			visual = createSlotVisual(key, visuals.folder)
			visuals.slots[key] = visual
		end

		local x, z = clampOffset(areaSize, slot.OffsetX, slot.OffsetZ)
		-- Placa apoiada no piso, um fio acima pra não dar z-fighting.
		visual.part.CFrame = areaCFrame * CFrame.new(x, visual.part.Size.Y / 2 + 0.02, z)

		local rarity = Rarities[slot.Rarity]
		local color = if rarity then rarity.Color else Color3.fromRGB(255, 255, 255)
		visual.part.Color = color
		visual.rarityLabel.Text = if rarity then rarity.DisplayName else slot.Rarity
		visual.rarityLabel.TextColor3 = color

		local warriorId = slot.WarriorId
		if warriorId then
			local warrior = warriorsById[warriorId]
			visual.nameLabel.Text = if warrior then warrior.Name else "?"
			visual.statusLabel.Text = `${if warrior then warrior.IncomePerSecond else 0}/s`
		else
			local ready = readyAt(slot)
			visual.nameLabel.Text = "Pergaminho"
			visual.statusLabel.Text = if ready then `Chocando {formatDuration(ready - now)}` else "Chocando"
		end
	end

	for key, visual in visuals.slots do
		if not slots[key] then
			visual.part:Destroy()
			visuals.slots[key] = nil
		end
	end
end

local function isDue(slot: SlotData, now: number): boolean
	if slot.WarriorId ~= nil then
		return false
	end
	local ready = readyAt(slot)
	return ready ~= nil and now >= ready
end

-- Termina as chocagens vencidas, inclusive as que venceram com o jogador offline.
local function completeHatching(player: Player, slots: SlotsData, now: number)
	local anyDue = false
	for _, slot in slots do
		if isDue(slot, now) then
			anyDue = true
			break
		end
	end
	if not anyDue then
		return
	end

	PlayerDataService:Update(player, "Slots", function(current: SlotsData): SlotsData
		for _, slot in current do
			if isDue(slot, now) then
				slot.WarriorId = drawWarrior(slot.Rarity)
			end
		end
		return current
	end)
end

local function incomeOf(slots: SlotsData): number
	local total = 0
	for _, slot in slots do
		local warriorId = slot.WarriorId
		if warriorId then
			local warrior = warriorsById[warriorId]
			if warrior then
				total += warrior.IncomePerSecond
			else
				warnOnce(`warrior:{warriorId}`, `[WarriorService] Guerreiro desconhecido nos dados: '{warriorId}'`)
			end
		end
	end
	return total
end

local function tickPlayer(player: Player, now: number)
	local before = getSlots(player)
	if before == nil then
		return
	end
	completeHatching(player, before, now)

	local slots = getSlots(player)
	if slots == nil then
		return
	end

	local income = incomeOf(slots)
	if income > 0 then
		CurrencyService:AddMoney(player, income)
	end

	renderSlots(player, slots, now)
end

function WarriorService:Init()
	for id, rarity in Rarities do
		assert(rarity.Id == id, `[WarriorService] Rarities.{id}.Id deveria ser '{id}'`)
		assert(rarity.HatchSeconds > 0, `[WarriorService] Rarities.{id}.HatchSeconds precisa ser > 0`)
		assert(rarity.IncomeMin <= rarity.IncomeMax, `[WarriorService] Rarities.{id}: IncomeMin > IncomeMax`)
		warriorsByRarity[id] = {}
	end

	for _, warrior in Warriors do
		assert(not warriorsById[warrior.Id], `[WarriorService] Id de guerreiro repetido: '{warrior.Id}'`)
		local rarity = Rarities[warrior.Rarity]
		assert(rarity, `[WarriorService] '{warrior.Id}' tem raridade inválida: '{warrior.Rarity}'`)
		local income = warrior.IncomePerSecond
		assert(
			income % 1 == 0 and income >= rarity.IncomeMin and income <= rarity.IncomeMax,
			`[WarriorService] '{warrior.Id}': renda {income} fora da faixa de {warrior.Rarity} ({rarity.IncomeMin}–{rarity.IncomeMax})`
		)
		warriorsById[warrior.Id] = warrior
		table.insert(warriorsByRarity[warrior.Rarity], warrior)
	end

	for id, pool in warriorsByRarity do
		assert(#pool > 0, `[WarriorService] Nenhum guerreiro com raridade '{id}'`)
	end

	local root = Instance.new("Folder")
	root.Name = "WarriorSlots"
	root.Parent = Workspace
	visualsRoot = root
end

function WarriorService:Start()
	Players.PlayerRemoving:Connect(clearVisuals)

	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for _, player in Players:GetPlayers() do
				if PlayerDataService:IsLoaded(player) then
					-- Erro com um jogador não pode parar o loop dos outros.
					local ok, err = pcall(function()
						tickPlayer(player, now)
					end)
					if not ok then
						warn(`[WarriorService] Erro no tick de {player.Name}: {err}`)
					end
				end
			end
		end
	end)
end

-- Coloca um pergaminho num slot livre do ringue do jogador. position = nil usa a
-- posição atual do jogador. Retorna (true) ou (false, motivo), com motivo sendo
-- "NotLoaded", "NoBase", "NoPosition", "OutsideBase", "TooClose" ou "NoFreeSlot".
function WarriorService:AddScroll(player: Player, rarity: string, position: Vector3?): (boolean, string?)
	if not Rarities[rarity] then
		error(`[WarriorService] Raridade inválida: '{rarity}'`, 2)
	end
	if not PlayerDataService:IsLoaded(player) then
		return false, "NotLoaded"
	end

	local areaCFrame, areaSize = getArea(player)
	if not areaCFrame or not areaSize then
		return false, "NoBase"
	end

	local target = resolvePosition(player, position)
	if target == nil then
		return false, "NoPosition"
	end
	if not isFiniteVector(target) then
		return false, "OutsideBase"
	end

	local offset = toOffset(areaCFrame, areaSize, target)
	if offset == nil then
		return false, "OutsideBase"
	end
	local offsetX, offsetZ = offset.X, offset.Z

	local reason: string? = nil
	local updated = PlayerDataService:Update(player, "Slots", function(slots: SlotsData): SlotsData
		for _, slot in slots do
			if Vector2.new(slot.OffsetX - offsetX, slot.OffsetZ - offsetZ).Magnitude < MIN_SLOT_DISTANCE then
				reason = "TooClose"
				return slots
			end
		end

		for index = 1, SLOTS_PER_BASE do
			local key = tostring(index)
			if not slots[key] then
				slots[key] = {
					Rarity = rarity,
					StartedAt = os.time(),
					OffsetX = offsetX,
					OffsetZ = offsetZ,
				}
				return slots
			end
		end

		reason = "NoFreeSlot"
		return slots
	end)

	if not updated then
		return false, "NotLoaded"
	end
	if reason then
		return false, reason
	end
	return true, nil
end

-- Slots ocupados do jogador, em ordem de índice; nil se os dados não estiverem carregados.
function WarriorService:GetSlots(player: Player): { SlotInfo }?
	local slots = getSlots(player)
	if slots == nil then
		return nil
	end

	local list: { SlotInfo } = {}
	for key, slot in slots do
		local index = tonumber(key)
		if index then
			table.insert(list, {
				Index = index,
				Rarity = slot.Rarity,
				StartedAt = slot.StartedAt,
				ReadyAt = readyAt(slot) or slot.StartedAt,
				WarriorId = slot.WarriorId,
				Offset = Vector3.new(slot.OffsetX, 0, slot.OffsetZ),
			})
		end
	end
	table.sort(list, function(a, b)
		return a.Index < b.Index
	end)
	return list
end

return WarriorService
