--!strict

-- Placar no canto de cima à direita: jogadores do servidor com $/s e velocidade,
-- ordenados pela velocidade. Substitui a lista de jogadores padrão do Roblox. Lê os
-- atributos Income e Speed que o servidor marca em cada Player (só para exibir).
-- O botão "–" recolhe o placar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Hud = require(UI:WaitForChild("Hud"))
local Style = require(UI:WaitForChild("Style"))

local LeaderboardController = {}

local ROW_HEIGHT = 34
local HEADER_HEIGHT = 34
local NAME_WIDTH = 0.46
local INCOME_WIDTH = 0.27

local localPlayer = Players.LocalPlayer

local function numberAttribute(player: Player, name: string): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function cell(text: string, x: number, width: number, font: Enum.Font, parent: Instance): TextLabel
	local label = Style.label(text, font, 1.5)
	label.Position = UDim2.new(x, 6, 0, 4)
	label.Size = UDim2.new(width, -12, 1, -8)
	label.TextXAlignment = if x == 0 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
	label.Parent = parent
	return label
end

function LeaderboardController:Start()
	-- A lista padrão mostraria os mesmos dados de novo, do lado.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)

	local panel = Instance.new("Frame")
	panel.Name = "Leaderboard"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.fromScale(1, 0)
	panel.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Style.Colors.Panel
	panel.BackgroundTransparency = 0.15
	panel.Parent = Hud.get().topRight
	Style.corner(panel, 12)
	Style.stroke(panel, Style.Colors.Ink, 3)
	Style.list(panel, 0)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 0
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.BackgroundTransparency = 1
	header.Parent = panel
	local nameHeader = cell("👥 Jogadores", 0, NAME_WIDTH, Style.TitleFont, header)
	nameHeader.TextColor3 = Style.Colors.Muted
	local incomeHeader = cell("$/s", NAME_WIDTH, INCOME_WIDTH, Style.TitleFont, header)
	incomeHeader.TextColor3 = Style.Colors.Green
	local speedHeader = cell("⚡", NAME_WIDTH + INCOME_WIDTH, 1 - NAME_WIDTH - INCOME_WIDTH - 0.08, Style.TitleFont, header)
	speedHeader.TextColor3 = Style.Colors.Pink

	local collapse = Style.smallButton("–", Style.Colors.Gray)
	collapse.AnchorPoint = Vector2.new(1, 0.5)
	collapse.Position = UDim2.new(1, -4, 0.5, 0)
	collapse.Size = UDim2.fromOffset(26, 24)
	collapse.Parent = header

	local body = Instance.new("Frame")
	body.Name = "Rows"
	body.LayoutOrder = 1
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.Parent = panel
	Style.list(body, 0)

	collapse.Activated:Connect(function()
		body.Visible = not body.Visible
		Style.setButtonText(collapse, if body.Visible then "–" else "+")
	end)

	local function rebuild()
		for _, child in body:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local players = Players:GetPlayers()
		table.sort(players, function(a, b)
			return numberAttribute(a, "Speed") > numberAttribute(b, "Speed")
		end)

		for index, player in players do
			local row = Instance.new("Frame")
			row.LayoutOrder = index
			row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
			row.BackgroundColor3 = Style.Colors.PanelLight
			row.BackgroundTransparency = if player == localPlayer then 0.2 else 1
			row.Parent = body
			Style.corner(row, 8)

			local medal = if index == 1 then "🥇 " elseif index == 2 then "🥈 " elseif index == 3 then "🥉 " else ""
			local name = cell(`{medal}{player.DisplayName}`, 0, NAME_WIDTH, Style.BodyFont, row)
			name.TextColor3 = if player == localPlayer then Style.Colors.Yellow else Style.Colors.White
			local income = cell(Format.number(numberAttribute(player, "Income")), NAME_WIDTH, INCOME_WIDTH, Style.BodyFont, row)
			income.TextColor3 = Style.Colors.Green
			local speed = cell(
				Format.number(numberAttribute(player, "Speed")),
				NAME_WIDTH + INCOME_WIDTH,
				1 - NAME_WIDTH - INCOME_WIDTH,
				Style.BodyFont,
				row
			)
			speed.TextColor3 = Style.Colors.Pink
		end
	end

	-- Atributos mudam toda hora (renda a cada segundo): junta num rebuild por intervalo.
	local dirty = true
	local function markDirty()
		dirty = true
	end
	local function watch(player: Player)
		player:GetAttributeChangedSignal("Income"):Connect(markDirty)
		player:GetAttributeChangedSignal("Speed"):Connect(markDirty)
		markDirty()
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(markDirty)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	task.spawn(function()
		while true do
			if dirty then
				dirty = false
				rebuild()
			end
			task.wait(1)
		end
	end)
end

return LeaderboardController
