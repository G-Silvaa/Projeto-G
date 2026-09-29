--!strict

-- Lado do cliente dos totens: carregando e dentro do próprio ringue, o jogador
-- clica (ou toca) no chão da base e o totem é colocado ali. Esconde o "Pegar" dos
-- totens enquanto carrega. Mostra um aviso, um
-- disco no ponto sob o mouse, a mensagem do resultado e o aviso do evento no chat.
-- Quem decide tudo é o servidor (ScrollService); o disco é só uma dica.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Hud = require(UI:WaitForChild("Hud"))
local Style = require(UI:WaitForChild("Style"))

local ScrollController = {}

local RAY_LENGTH = 500
local PREVIEW_SIZE = 3

local player = Players.LocalPlayer

-- Dica embaixo, no centro: faixa verde com texto de contorno grosso.
local function buildHint(): Frame
	local hint = Instance.new("Frame")
	hint.Name = "PlaceHint"
	hint.Size = UDim2.fromScale(1, 1)
	hint.BackgroundColor3 = Style.Colors.Green
	hint.Visible = false
	hint.Parent = Hud.get().bottomCenter
	Style.corner(hint, 14)
	Style.stroke(hint, Style.darker(Style.Colors.Green, 0.45), 3)
	Style.gradient(hint, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 190))

	local text = Style.label(
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled
			then "👆 Toque no chão da sua base para colocar o totem"
			else "👆 Clique no chão da sua base para colocar o totem",
		Style.TitleFont,
		2.5
	)
	text.Size = UDim2.new(1, -24, 1, -12)
	text.Position = UDim2.fromOffset(12, 6)
	text.Parent = hint
	return hint
end

-- Disco translúcido deitado no chão, só neste cliente.
local function buildPreview(): Part
	local preview = Instance.new("Part")
	preview.Name = "TotemPlacePreview"
	preview.Shape = Enum.PartType.Cylinder
	preview.Size = Vector3.new(0.2, PREVIEW_SIZE, PREVIEW_SIZE)
	preview.Material = Enum.Material.Neon
	preview.Color = Color3.fromRGB(120, 255, 140)
	preview.Transparency = 0.5
	preview.Anchored = true
	preview.CanCollide = false
	preview.CanTouch = false
	preview.CanQuery = false
	preview.CastShadow = false
	return preview
end

-- Ponto do mundo sob a tela, ignorando o próprio personagem e os itens.
-- inset = true: a posição conta a barra do topo (GetMouseLocation); false: não conta
-- (InputObject.Position, TouchTap).
local function pointUnder(screenPosition: Vector2, inset: boolean, ignore: { Instance }): Vector3?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local ray = if inset
		then camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
		else camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	local exclude = table.clone(ignore)
	if player.Character then
		table.insert(exclude, player.Character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)
	return if result then result.Position else nil
end

local function showAnnouncement(text: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = if channels then channels:FindFirstChild("RBXGeneral") else nil
	if general and general:IsA("TextChannel") then
		general:DisplaySystemMessage(text)
	end
end

function ScrollController:Start()
	local hint = buildHint()
	local preview = buildPreview()
	local placeScroll = Remotes.getFunction(Remotes.Functions.PlaceScroll)
	local warriorSlots = Workspace:WaitForChild("WarriorSlots")
	local phaseScrolls = Workspace:WaitForChild("PhaseScrolls")
	local ignore: { Instance } = { preview, warriorSlots, phaseScrolls }
	local busy = false

	local function canPlace(): boolean
		return player:GetAttribute("CarryingScroll") ~= nil and player:GetAttribute("InOwnBase") == true
	end

	local function refreshHint()
		local visible = canPlace()
		if visible and not hint.Visible then
			Style.pop(hint)
		end
		hint.Visible = visible
	end
	player:GetAttributeChangedSignal("CarryingScroll"):Connect(refreshHint)
	player:GetAttributeChangedSignal("InOwnBase"):Connect(refreshHint)
	refreshHint()

	local function showMessage(text: string, success: boolean)
		Hud.notify(text, if success then Style.Colors.Success else Style.Colors.Error)
	end

	local function placeAt(screenPosition: Vector2, inset: boolean)
		if busy or not canPlace() then
			return
		end
		local point = pointUnder(screenPosition, inset, ignore)
		if point == nil then
			return
		end
		busy = true
		local ok, success, text = pcall(function()
			return placeScroll:InvokeServer(point)
		end)
		busy = false
		if ok then
			showMessage(if typeof(text) == "string" then text else "", success == true)
		else
			showMessage("Não foi possível falar com o servidor", false)
		end
	end

	-- gameProcessed = o clique foi num botão da tela (ou no controle do celular).
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			placeAt(UserInputService:GetMouseLocation(), true)
		end
	end)
	-- No celular, só toque rápido: arrastar pra girar a câmera não coloca nada.
	UserInputService.TouchTap:Connect(function(positions: { Vector2 }, gameProcessed: boolean)
		if not gameProcessed and positions[1] then
			placeAt(positions[1], false)
		end
	end)

	-- Disco no ponto sob o mouse (no celular não há mouse: só aparece a dica).
	RunService.RenderStepped:Connect(function()
		local point = if canPlace() and UserInputService.MouseEnabled
			then pointUnder(UserInputService:GetMouseLocation(), true, ignore)
			else nil
		if point then
			preview.CFrame = CFrame.new(point + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			preview.Parent = Workspace
		else
			preview.Parent = nil
		end
	end)

	Remotes.getEvent(Remotes.Events.Announcement).OnClientEvent:Connect(function(text: unknown)
		if typeof(text) == "string" then
			showAnnouncement(text)
		end
	end)

	-- Prompt "Roubar" nos próprios slots não faz sentido: some só na tela do dono.
	-- (O servidor recusaria de qualquer jeito.)
	local function hideIfOwn(instance: Instance)
		if not instance:IsA("ProximityPrompt") or instance:GetAttribute("OwnerUserId") ~= player.UserId then
			return
		end
		instance.Enabled = false
		instance:GetPropertyChangedSignal("Enabled"):Connect(function()
			if instance.Enabled then
				instance.Enabled = false
			end
		end)
	end
	warriorSlots.DescendantAdded:Connect(hideIfOwn)
	for _, descendant in warriorSlots:GetDescendants() do
		hideIfOwn(descendant)
	end

	-- Com as mãos ocupadas, o "Pegar" dos totens some (o servidor recusaria de qualquer jeito).
	local function refreshPickup(instance: Instance)
		if instance:IsA("ProximityPrompt") and instance.Name == "PickupPrompt" then
			instance.Enabled = player:GetAttribute("CarryingScroll") == nil
		end
	end
	phaseScrolls.DescendantAdded:Connect(refreshPickup)
	player:GetAttributeChangedSignal("CarryingScroll"):Connect(function()
		for _, descendant in phaseScrolls:GetDescendants() do
			refreshPickup(descendant)
		end
	end)
	for _, descendant in phaseScrolls:GetDescendants() do
		refreshPickup(descendant)
	end
end

return ScrollController
