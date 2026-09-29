--!strict

-- HUD principal: velocidade e dinheiro em números grandes no canto de baixo, linha
-- de rebirth, botão "Rebirth" na coluna da esquerda (confirmação em dois cliques) e
-- os avisos do servidor (Events.Notify). Os números vêm de atributos que o servidor
-- marca no Player só para exibir.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RebirthConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rebirth"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Hud = require(UI:WaitForChild("Hud"))
local Style = require(UI:WaitForChild("Style"))

local HudController = {}

local CONFIRM_SECONDS = 3
-- Ordem dos botões na coluna da esquerda (os outros controllers usam 1 e 2).
local REBIRTH_ORDER = 3

local player = Players.LocalPlayer

local function numberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

-- Linha grande: ícone + número com degradê e contorno grosso.
local function bigStat(order: number, icon: string, top: Color3, bottom: Color3, parent: Instance): TextLabel
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 62)
	row.Parent = parent

	local iconLabel = Instance.new("TextLabel")
	iconLabel.BackgroundTransparency = 1
	iconLabel.Size = UDim2.fromOffset(62, 62)
	iconLabel.Font = Style.BodyFont
	iconLabel.TextScaled = true
	iconLabel.Text = icon
	iconLabel.Parent = row

	local value = Style.label("0", Style.TitleFont, 4)
	value.Position = UDim2.fromOffset(70, 0)
	value.Size = UDim2.new(1, -70, 1, 0)
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Parent = row
	Style.gradient(value, top, bottom)
	return value
end

function HudController:Start()
	local regions = Hud.get()

	Remotes.getEvent(Remotes.Events.Notify).OnClientEvent:Connect(function(text: unknown)
		if typeof(text) == "string" then
			Hud.notify(text)
		end
	end)

	-- Canto de baixo: rebirth (pequeno), velocidade e dinheiro (grandes).
	local rebirthLine = Style.label("", Style.TitleFont, 2)
	rebirthLine.LayoutOrder = 1
	rebirthLine.Size = UDim2.new(1, 0, 0, 26)
	rebirthLine.TextXAlignment = Enum.TextXAlignment.Left
	rebirthLine.TextColor3 = Style.Colors.Muted
	rebirthLine.Parent = regions.bottomLeft

	local speedValue = bigStat(2, "⚡", Color3.fromRGB(255, 120, 230), Color3.fromRGB(190, 60, 255), regions.bottomLeft)
	local moneyValue = bigStat(3, "💵", Color3.fromRGB(150, 255, 110), Color3.fromRGB(40, 200, 70), regions.bottomLeft)

	local rebirth = Style.bigButton("🔁", "Rebirth", Style.Colors.Purple)
	rebirth.button.Name = "Rebirth"
	rebirth.button.LayoutOrder = REBIRTH_ORDER
	rebirth.button.Parent = regions.left

	local confirming = false
	local confirmToken = 0
	local busy = false
	local lastSpeed = numberAttribute("Speed")

	local function refresh()
		local rebirths = numberAttribute("Rebirths")
		speedValue.Text = Format.number(numberAttribute("Speed"))
		moneyValue.Text = `${Format.number(numberAttribute("Money"))}`
		rebirthLine.Text = `🔁 Rebirth {rebirths} · renda x{RebirthConfig.MultiplierFor(rebirths)}`
		if not confirming then
			rebirth.text.Text = "Rebirth"
			rebirth.setColor(Style.Colors.Purple)
		end
	end
	for _, name in { "Money", "Speed", "Rebirths" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	-- A velocidade "pula" quando sobe (treinando na esteira).
	player:GetAttributeChangedSignal("Speed"):Connect(function()
		local speed = numberAttribute("Speed")
		if Format.number(speed) ~= Format.number(lastSpeed) then
			Style.pop(speedValue)
		end
		lastSpeed = speed
	end)
	refresh()

	local rebirthRemote = Remotes.getFunction(Remotes.Functions.Rebirth)
	rebirth.button.Activated:Connect(function()
		if busy then
			return
		end
		if not confirming then
			confirming = true
			confirmToken += 1
			local current = confirmToken
			local cost = RebirthConfig.CostFor(numberAttribute("Rebirths"))
			rebirth.text.Text = "Confirmar?"
			rebirth.setColor(Style.Colors.Red)
			Hud.notify(`Rebirth custa ${Format.number(cost)} e zera dinheiro, guerreiros e upgrades`, Style.Colors.Orange)
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
			return rebirthRemote:InvokeServer()
		end)
		busy = false
		refresh()
		if ok then
			Hud.notify(if typeof(text) == "string" then text else "", if success == true then Style.Colors.Success else Style.Colors.Error)
		else
			Hud.notify("Não foi possível falar com o servidor", Style.Colors.Error)
		end
	end)
end

return HudController
