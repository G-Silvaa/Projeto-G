--!strict

-- HUD básico: Money / Speed / Rebirths no canto, botão de rebirth e mensagens
-- curtas vindas do servidor (Events.Notify). Os números vêm de atributos que o
-- servidor marca no Player só para exibir.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RebirthConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rebirth"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local HudController = {}

local NOTIFY_SECONDS = 4
local CONFIRM_SECONDS = 3

local player = Players.LocalPlayer

local function numberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function makeStat(order: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 28)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Parent = parent
	return label
end

function HudController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Mensagens do servidor.
	local notice = Instance.new("TextLabel")
	notice.Name = "Notice"
	notice.AnchorPoint = Vector2.new(0.5, 0)
	notice.Position = UDim2.new(0.5, 0, 0, 70)
	notice.Size = UDim2.fromOffset(520, 34)
	notice.BackgroundTransparency = 1
	notice.Font = Enum.Font.GothamBold
	notice.TextScaled = true
	notice.TextColor3 = Color3.fromRGB(255, 230, 120)
	notice.TextStrokeTransparency = 0.3
	notice.Visible = false
	notice.Parent = gui

	local noticeToken = 0
	local function showNotice(text: string, color: Color3?)
		noticeToken += 1
		local current = noticeToken
		notice.Text = text
		notice.TextColor3 = color or Color3.fromRGB(255, 230, 120)
		notice.Visible = true
		task.delay(NOTIFY_SECONDS, function()
			if noticeToken == current then
				notice.Visible = false
			end
		end)
	end

	Remotes.getEvent(Remotes.Events.Notify).OnClientEvent:Connect(function(text: unknown)
		if typeof(text) == "string" then
			showNotice(text)
		end
	end)

	-- Painel de números.
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.Position = UDim2.fromOffset(16, 60)
	stats.Size = UDim2.fromOffset(220, 96)
	stats.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	stats.BackgroundTransparency = 0.35
	stats.Parent = gui
	local statsCorner = Instance.new("UICorner")
	statsCorner.CornerRadius = UDim.new(0, 10)
	statsCorner.Parent = stats
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 4)
	padding.Parent = stats
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = stats

	local moneyLabel = makeStat(1, stats)
	local speedLabel = makeStat(2, stats)
	local rebirthLabel = makeStat(3, stats)

	-- Botão de rebirth (confirmação em dois cliques).
	local rebirthButton = Instance.new("TextButton")
	rebirthButton.Name = "Rebirth"
	rebirthButton.Position = UDim2.fromOffset(16, 164)
	rebirthButton.Size = UDim2.fromOffset(220, 40)
	rebirthButton.BackgroundColor3 = Color3.fromRGB(140, 60, 200)
	rebirthButton.Font = Enum.Font.GothamBold
	rebirthButton.TextScaled = true
	rebirthButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	rebirthButton.Parent = gui
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 10)
	buttonCorner.Parent = rebirthButton

	local confirming = false
	local confirmToken = 0
	local busy = false

	local function refresh()
		local rebirths = numberAttribute("Rebirths")
		moneyLabel.Text = `$ {Format.number(numberAttribute("Money"))}`
		speedLabel.Text = `Velocidade {numberAttribute("Speed")}`
		rebirthLabel.Text = `Rebirths {rebirths} (renda x{RebirthConfig.MultiplierFor(rebirths)})`
		if not confirming then
			rebirthButton.Text = `Rebirth ($ {Format.number(RebirthConfig.CostFor(rebirths))})`
		end
	end
	for _, name in { "Money", "Speed", "Rebirths" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	refresh()

	local rebirth = Remotes.getFunction(Remotes.Functions.Rebirth)
	rebirthButton.Activated:Connect(function()
		if busy then
			return
		end
		if not confirming then
			confirming = true
			confirmToken += 1
			local current = confirmToken
			rebirthButton.Text = "Zera dinheiro, guerreiros e upgrades. Confirmar?"
			task.delay(CONFIRM_SECONDS, function()
				if confirmToken == current and confirming then
					confirming = false
					refresh()
				end
			end)
			return
		end

		confirming = false
		busy = true
		local ok, success, text = pcall(function()
			return rebirth:InvokeServer()
		end)
		busy = false
		refresh()
		if ok then
			local color = if success == true then Color3.fromRGB(120, 255, 140) else Color3.fromRGB(255, 110, 110)
			showNotice(if typeof(text) == "string" then text else "", color)
		else
			showNotice("Não foi possível falar com o servidor", Color3.fromRGB(255, 110, 110))
		end
	end)
end

return HudController
