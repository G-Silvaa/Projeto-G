--!strict

-- Lado do cliente dos pergaminhos: botão "Colocar pergaminho" (só aparece carregando
-- e dentro do próprio ringue), mensagem do resultado, aviso no chat e o giro dos
-- pergaminhos no chão. Quem decide tudo é o servidor (ScrollService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local ScrollController = {}

local MESSAGE_SECONDS = 3
local SPIN_SPEED = 2 -- radianos por segundo

local player = Players.LocalPlayer

local function buildGui(): (TextButton, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ScrollGui"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local button = Instance.new("TextButton")
	button.Name = "PlaceButton"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -40)
	button.Size = UDim2.fromOffset(240, 56)
	button.BackgroundColor3 = Color3.fromRGB(40, 170, 90)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Text = "Colocar pergaminho"
	button.Visible = false
	button.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = button

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.AnchorPoint = Vector2.new(0.5, 1)
	message.Position = UDim2.new(0.5, 0, 1, -104)
	message.Size = UDim2.fromOffset(420, 32)
	message.BackgroundTransparency = 1
	message.Font = Enum.Font.GothamBold
	message.TextScaled = true
	message.TextStrokeTransparency = 0.3
	message.Visible = false
	message.Parent = gui

	return button, message
end

local function showAnnouncement(text: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = if channels then channels:FindFirstChild("RBXGeneral") else nil
	if general and general:IsA("TextChannel") then
		general:DisplaySystemMessage(text)
	end
end

function ScrollController:Start()
	local button, message = buildGui()
	local placeScroll = Remotes.getFunction(Remotes.Functions.PlaceScroll)
	local busy = false
	local messageToken = 0

	local function refreshButton()
		button.Visible = player:GetAttribute("CarryingScroll") ~= nil and player:GetAttribute("InOwnBase") == true
	end
	player:GetAttributeChangedSignal("CarryingScroll"):Connect(refreshButton)
	player:GetAttributeChangedSignal("InOwnBase"):Connect(refreshButton)
	refreshButton()

	local function showMessage(text: string, success: boolean)
		messageToken += 1
		local token = messageToken
		message.Text = text
		message.TextColor3 = if success then Color3.fromRGB(120, 255, 140) else Color3.fromRGB(255, 110, 110)
		message.Visible = true
		task.delay(MESSAGE_SECONDS, function()
			if messageToken == token then
				message.Visible = false
			end
		end)
	end

	button.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		local ok, success, text = pcall(function()
			return placeScroll:InvokeServer()
		end)
		busy = false
		if ok then
			showMessage(if typeof(text) == "string" then text else "", success == true)
		else
			showMessage("Não foi possível falar com o servidor", false)
		end
	end)

	Remotes.getEvent(Remotes.Events.Announcement).OnClientEvent:Connect(function(text: unknown)
		if typeof(text) == "string" then
			showAnnouncement(text)
		end
	end)

	-- Giro só local: girar no servidor mandaria a posição de todos os pergaminhos pela rede.
	local scrolls = Workspace:WaitForChild("PhaseScrolls")
	RunService.RenderStepped:Connect(function(dt: number)
		local spin = CFrame.Angles(0, dt * SPIN_SPEED, 0)
		for _, scroll in scrolls:GetChildren() do
			if scroll:IsA("BasePart") then
				scroll.CFrame = CFrame.new(scroll.Position) * spin * scroll.CFrame.Rotation
			end
		end
	end)
end

return ScrollController
