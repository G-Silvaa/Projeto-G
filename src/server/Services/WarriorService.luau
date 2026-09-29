--!strict

-- Totens (no código, "scroll"), chocagem e guerreiros. Cada jogador tem um número
-- de slots (SLOTS_PER_BASE + bônus de upgrades/Game Pass), colocados em qualquer
-- ponto do próprio ringue. Um totem entregue ocupa um slot e choca por um tempo que
-- depende da raridade; o início é salvo como horário (os.time()), então a
-- chocagem continua com o jogador offline. Ao terminar, vira um guerreiro
-- sorteado daquela raridade, que gera dinheiro por segundo enquanto o dono está
-- no jogo.
--
-- Roubo: um slot pode ser travado em memória enquanto alguém o carrega. Travado,
-- ele some do ringue e não rende, mas continua nos dados do dono até a entrega
-- (TransferSlot) ou até ser destravado (UnlockSlot).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local Warriors = require(Config:WaitForChild("Warriors"))
local StealConfig = require(Config:WaitForChild("Steal"))
local TotemsConfig = require(Config:WaitForChild("Totems"))

local BaseService = require(script.Parent.BaseService)
local CurrencyService = require(script.Parent.CurrencyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local TotemService = require(script.Parent.TotemService)

local WarriorService = {}

-- Slots de todo jogador; upgrades e Game Pass somam por AddSlotBonus.
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
-- Altura do letreiro acima da placa (sem totem) e acima do topo do totem.
local LABEL_OFFSET = 2.5
local LABEL_ABOVE_TOTEM = 1.5
-- Checagem de "está no próprio ringue" (atributo InOwnBase, só pra UI).
local BASE_CHECK_INTERVAL = 0.25

type Warrior = Warriors.Warrior

-- Como fica salvo em PlayerData.Slots, com a chave "1".."N".
-- OffsetX/OffsetZ: posição relativa ao centro da base (BaseService:GetBaseArea).
-- PlacedAt: quando foi colocado nesta base (proteção contra roubo); ausente em slots antigos.
type SlotData = {
	Rarity: string,
	StartedAt: number,
	OffsetX: number,
	OffsetZ: number,
	WarriorId: string?,
	PlacedAt: number?,
}

type SlotsData = { [string]: SlotData }

export type SlotInfo = {
	Index: number,
	Key: string,
	Rarity: string,
	StartedAt: number,
	ReadyAt: number,
	PlacedAt: number,
	WarriorId: string?, -- nil enquanto choca
	Offset: Vector3, -- relativo ao centro da base; Y sempre 0
}

export type StealHandler = (thief: Player, owner: Player, key: string) -> ()

-- Enquanto choca, o totem fica em pé no slot e a placa fica invisível (ela continua
-- segurando o letreiro e o prompt "Roubar"). Guerreiro nascido: placa colorida.
type SlotVisual = {
	part: Part,
	totem: Model?,
	totemRarity: string?,
	totemCFrame: CFrame?,
	billboard: BillboardGui,
	prompt: ProximityPrompt,
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
local lockedSlots: { [Player]: { [string]: boolean } } = {}
local slotBonusProviders: { (Player) -> number } = {}
local incomeMultiplierProviders: { (Player) -> number } = {}
local stealHandlers: { StealHandler } = {}
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

local function isLocked(owner: Player, key: string): boolean
	local locks = lockedSlots[owner]
	return locks ~= nil and locks[key] == true
end

local function maxSlots(player: Player): number
	local total = SLOTS_PER_BASE
	for _, provider in slotBonusProviders do
		total += provider(player)
	end
	return total
end

local function incomeMultiplier(player: Player): number
	local multiplier = 1
	for _, provider in incomeMultiplierProviders do
		multiplier *= provider(player)
	end
	return multiplier
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

local function toInfo(key: string, slot: SlotData): SlotInfo?
	local index = tonumber(key)
	if index == nil then
		return nil
	end
	return {
		Index = index,
		Key = key,
		Rarity = slot.Rarity,
		StartedAt = slot.StartedAt,
		ReadyAt = readyAt(slot) or slot.StartedAt,
		PlacedAt = slot.PlacedAt or 0,
		WarriorId = slot.WarriorId,
		Offset = Vector3.new(slot.OffsetX, 0, slot.OffsetZ),
	}
end

-- Valida a posição e grava um slot novo no primeiro espaço livre.
-- makeRecord recebe o offset validado e devolve o registro a salvar.
-- Retorna (true, nil, chave) ou (false, motivo).
local function placeRecord(
	player: Player,
	position: Vector3?,
	makeRecord: (offsetX: number, offsetZ: number) -> SlotData
): (boolean, string?, string?)
	if not PlayerDataService:IsLoaded(player) then
		return false, "NotLoaded", nil
	end

	local areaCFrame, areaSize = getArea(player)
	if not areaCFrame or not areaSize then
		return false, "NoBase", nil
	end

	local target = resolvePosition(player, position)
	if target == nil then
		return false, "NoPosition", nil
	end
	if not isFiniteVector(target) then
		return false, "OutsideBase", nil
	end

	local offset = toOffset(areaCFrame, areaSize, target)
	if offset == nil then
		return false, "OutsideBase", nil
	end
	local offsetX, offsetZ = offset.X, offset.Z
	local limit = maxSlots(player)

	local reason: string? = nil
	local placedKey: string? = nil
	local updated = PlayerDataService:Update(player, "Slots", function(slots: SlotsData): SlotsData
		for _, slot in slots do
			if Vector2.new(slot.OffsetX - offsetX, slot.OffsetZ - offsetZ).Magnitude < MIN_SLOT_DISTANCE then
				reason = "TooClose"
				return slots
			end
		end

		for index = 1, limit do
			local key = tostring(index)
			if not slots[key] then
				slots[key] = makeRecord(offsetX, offsetZ)
				placedKey = key
				return slots
			end
		end

		reason = "NoFreeSlot"
		return slots
	end)

	if not updated then
		return false, "NotLoaded", nil
	end
	if reason then
		return false, reason, nil
	end
	return true, nil, placedKey
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

local function createSlotVisual(owner: Player, key: string, parent: Instance): SlotVisual
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
	billboard.StudsOffset = Vector3.new(0, LABEL_OFFSET, 0)
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

	-- O cliente esconde este prompt nos slots do próprio jogador (OwnerUserId).
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Roubar"
	prompt.HoldDuration = StealConfig.PromptHoldSeconds
	prompt.MaxActivationDistance = StealConfig.MaxStealDistance
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OwnerUserId", owner.UserId)
	prompt.Parent = part
	prompt.Triggered:Connect(function(thief: Player)
		for _, handler in stealHandlers do
			task.spawn(handler, thief, owner, key)
		end
	end)

	return {
		part = part,
		billboard = billboard,
		prompt = prompt,
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

local function removeTotem(visual: SlotVisual)
	if visual.totem then
		visual.totem:Destroy()
	end
	visual.totem = nil
	visual.totemRarity = nil
	visual.totemCFrame = nil
end

-- Totem em pé no slot enquanto choca (se a raridade tiver modelo; senão fica a placa).
local function renderTotem(visual: SlotVisual, slot: SlotData, floorCFrame: CFrame, parent: Instance)
	if visual.totem and visual.totemRarity ~= slot.Rarity then
		removeTotem(visual)
	end
	if visual.totem == nil then
		if not Rarities[slot.Rarity] or not TotemService:HasTemplate(slot.Rarity) then
			return
		end
		local totem = TotemService:Create(slot.Rarity, TotemsConfig.GroundHeight, false)
		totem.Parent = parent
		visual.totem = totem
		visual.totemRarity = slot.Rarity
	end

	local totem = visual.totem :: Model
	if visual.totemCFrame ~= floorCFrame then
		totem:PivotTo(floorCFrame)
		visual.totemCFrame = floorCFrame
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
			visual = createSlotVisual(player, key, visuals.folder)
			visuals.slots[key] = visual
		end

		local x, z = clampOffset(areaSize, slot.OffsetX, slot.OffsetZ)
		-- Placa apoiada no piso, um fio acima pra não dar z-fighting.
		visual.part.CFrame = areaCFrame * CFrame.new(x, visual.part.Size.Y / 2 + 0.02, z)

		-- Travado (sendo roubado): some do ringue até voltar ou ser entregue.
		local locked = isLocked(player, key)
		if locked or slot.WarriorId ~= nil then
			removeTotem(visual)
		else
			renderTotem(visual, slot, areaCFrame * CFrame.new(x, 0, z), visuals.folder)
		end
		local totem = visual.totem
		visual.part.Transparency = if locked or totem then 1 else 0
		visual.billboard.Enabled = not locked
		visual.billboard.StudsOffset = Vector3.new(
			0,
			if totem then TotemService:GetHeight(totem) + LABEL_ABOVE_TOTEM else LABEL_OFFSET,
			0
		)
		visual.prompt.Enabled = not locked

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
			visual.prompt.ObjectText = if warrior then warrior.Name else "Guerreiro"
		else
			local ready = readyAt(slot)
			visual.nameLabel.Text = "Totem"
			visual.statusLabel.Text = if ready then `Chocando {formatDuration(ready - now)}` else "Chocando"
			visual.prompt.ObjectText = "Totem"
		end
	end

	for key, visual in visuals.slots do
		if not slots[key] then
			removeTotem(visual)
			visual.part:Destroy()
			visuals.slots[key] = nil
		end
	end
end

-- Redesenha já, sem esperar o próximo tick (ex.: totem aparece na hora do clique).
-- Chamado depois de gravar: um erro aqui não pode chegar em quem chamou (o item
-- já está salvo; se o erro subisse, o jogador continuaria carregando e duplicaria).
local function renderNow(player: Player)
	local slots = getSlots(player)
	if slots == nil then
		return
	end
	local ok, err = pcall(renderSlots, player, slots, os.time())
	if not ok then
		warn(`[WarriorService] Erro ao desenhar os slots de {player.Name}: {err}`)
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

local function incomeOf(player: Player, slots: SlotsData): number
	local total = 0
	for key, slot in slots do
		local warriorId = slot.WarriorId
		if warriorId and not isLocked(player, key) then
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

	local income = math.floor(incomeOf(player, slots) * incomeMultiplier(player))
	-- Só pra UI (placar); o servidor nunca lê de volta.
	player:SetAttribute("Income", income)
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
	Players.PlayerRemoving:Connect(function(player: Player)
		clearVisuals(player)
		lockedSlots[player] = nil
	end)

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

	-- Atributo InOwnBase: só alimenta a UI (botões da base); o servidor não confia nele.
	task.spawn(function()
		while true do
			task.wait(BASE_CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				player:SetAttribute("InOwnBase", WarriorService:IsInPlacementArea(player))
			end
		end
	end)
end

-- Coloca um totem num slot livre do ringue do jogador. position = nil usa a
-- posição atual do jogador. Retorna (true) ou (false, motivo), com motivo sendo
-- "NotLoaded", "NoBase", "NoPosition", "OutsideBase", "TooClose" ou "NoFreeSlot".
function WarriorService:AddScroll(player: Player, rarity: string, position: Vector3?): (boolean, string?)
	if not Rarities[rarity] then
		error(`[WarriorService] Raridade inválida: '{rarity}'`, 2)
	end
	local ok, reason = placeRecord(player, position, function(offsetX: number, offsetZ: number): SlotData
		local now = os.time()
		return { Rarity = rarity, StartedAt = now, OffsetX = offsetX, OffsetZ = offsetZ, PlacedAt = now }
	end)
	if ok then
		renderNow(player)
	end
	return ok, reason
end

function WarriorService:GetMaxSlots(player: Player): number
	return maxSlots(player)
end

-- Se a posição (ou a posição atual do jogador) está na área do próprio ringue onde
-- o AddScroll aceitaria colocar. Não olha distância nem espaço livre.
function WarriorService:IsInPlacementArea(player: Player, position: Vector3?): boolean
	local areaCFrame, areaSize = getArea(player)
	local target = resolvePosition(player, position)
	if not areaCFrame or not areaSize or target == nil or not isFiniteVector(target) then
		return false
	end
	return toOffset(areaCFrame, areaSize, target) ~= nil
end

-- Slots ocupados do jogador, em ordem de índice; nil se os dados não estiverem carregados.
function WarriorService:GetSlots(player: Player): { SlotInfo }?
	local slots = getSlots(player)
	if slots == nil then
		return nil
	end

	local list: { SlotInfo } = {}
	for key, slot in slots do
		local info = toInfo(key, slot)
		if info then
			table.insert(list, info)
		end
	end
	table.sort(list, function(a, b)
		return a.Index < b.Index
	end)
	return list
end

function WarriorService:GetSlotInfo(owner: Player, key: string): SlotInfo?
	local slots = getSlots(owner)
	local slot = if slots then slots[key] else nil
	return if slot then toInfo(key, slot) else nil
end

-- Posição no mundo do slot (como aparece no ringue), ou nil.
function WarriorService:GetSlotWorldPosition(owner: Player, key: string): Vector3?
	local slots = getSlots(owner)
	local slot = if slots then slots[key] else nil
	local areaCFrame, areaSize = getArea(owner)
	if slot == nil or not areaCFrame or not areaSize then
		return nil
	end
	local x, z = clampOffset(areaSize, slot.OffsetX, slot.OffsetZ)
	return areaCFrame * Vector3.new(x, 0, z)
end

-- Trava o slot para roubo (some e não rende). false se não existe ou já está travado.
function WarriorService:LockSlot(owner: Player, key: string): boolean
	local slots = getSlots(owner)
	if slots == nil or not slots[key] or isLocked(owner, key) then
		return false
	end
	local locks = lockedSlots[owner]
	if locks == nil then
		locks = {}
		lockedSlots[owner] = locks
	end
	locks[key] = true
	return true
end

function WarriorService:UnlockSlot(owner: Player, key: string)
	local locks = lockedSlots[owner]
	if locks then
		locks[key] = nil
	end
end

-- Entrega um slot travado do dono para o ladrão, em position (nil = posição atual
-- do ladrão). Primeiro cria no ladrão (com as validações de sempre) e só então
-- remove do dono. Retorna (true) ou (false, motivo); "Gone" = o slot não existe mais.
function WarriorService:TransferSlot(owner: Player, key: string, thief: Player, position: Vector3?): (boolean, string?)
	local ownerSlots = getSlots(owner)
	local record = if ownerSlots then ownerSlots[key] else nil
	if record == nil then
		WarriorService:UnlockSlot(owner, key)
		return false, "Gone"
	end

	local ok, reason, thiefKey = placeRecord(thief, position, function(offsetX: number, offsetZ: number): SlotData
		return {
			Rarity = record.Rarity,
			StartedAt = record.StartedAt,
			WarriorId = record.WarriorId,
			OffsetX = offsetX,
			OffsetZ = offsetZ,
			PlacedAt = os.time(),
		}
	end)
	if not ok then
		return false, reason
	end

	local removed = PlayerDataService:Update(owner, "Slots", function(slots: SlotsData): SlotsData
		slots[key] = nil
		return slots
	end)
	if not removed then
		-- Dono saiu no meio: desfaz no ladrão pra não duplicar o item.
		PlayerDataService:Update(thief, "Slots", function(slots: SlotsData): SlotsData
			if thiefKey then
				slots[thiefKey] = nil
			end
			return slots
		end)
		return false, "Gone"
	end

	WarriorService:UnlockSlot(owner, key)
	renderNow(thief)
	return true, nil
end

-- Rebirth: apaga todos os slots do jogador (e as travas de roubo deles).
function WarriorService:ResetSlots(player: Player): boolean
	lockedSlots[player] = nil
	return PlayerDataService:Set(player, "Slots", {})
end

function WarriorService:HasHatching(player: Player): boolean
	local slots = getSlots(player)
	if slots == nil then
		return false
	end
	for _, slot in slots do
		if slot.WarriorId == nil then
			return true
		end
	end
	return false
end

-- Termina agora todas as chocagens em andamento (produto "Pular chocagem").
-- O sorteio acontece no próximo tick, como em qualquer chocagem vencida.
-- Retorna quantas foram adiantadas.
function WarriorService:SkipHatching(player: Player): number
	local skipped = 0
	local now = os.time()
	PlayerDataService:Update(player, "Slots", function(slots: SlotsData): SlotsData
		for _, slot in slots do
			local rarity = Rarities[slot.Rarity]
			if slot.WarriorId == nil and rarity then
				slot.StartedAt = math.min(slot.StartedAt, now - rarity.HatchSeconds)
				skipped += 1
			end
		end
		return slots
	end)
	return skipped
end

-- Chamado quando alguém ativa o prompt "Roubar" de um slot (quem valida é o handler).
function WarriorService:OnStealAttempt(handler: StealHandler)
	table.insert(stealHandlers, handler)
end

-- Bônus de slots por jogador (upgrades, Game Pass).
function WarriorService:AddSlotBonus(provider: (Player) -> number)
	table.insert(slotBonusProviders, provider)
end

-- Multiplicador de renda por jogador (upgrades, rebirth, Game Pass).
function WarriorService:AddIncomeMultiplier(provider: (Player) -> number)
	table.insert(incomeMultiplierProviders, provider)
end

return WarriorService
