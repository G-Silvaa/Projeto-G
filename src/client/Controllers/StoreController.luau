--!strict

-- Loja de Robux: botão "Robux" na coluna da esquerda e janela com Game Passes e
-- Developer Products. Item com Id 0 (placeholder) aparece como "Em breve". A compra
-- é aberta pelo servidor (Functions.PromptPurchase), que valida antes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared:WaitForChild("Config"):WaitForChild("Monetization"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Hud = require(UI:WaitForChild("Hud"))
local Style = require(UI:WaitForChild("Style"))

local StoreController = {}

local MESSAGE_SECONDS = 3
local BUTTON_ORDER = 2
local ROW_HEIGHT = 64
local ICONS: { [string]: string } = {
	DoubleIncome = "💰",
	DoubleTraining = "👟",
	ExtraSlots = "📦",
	SkipHatch = "⏩",
	MoneyPack = "💵",
}

local player = Players.LocalPlayer

function StoreController:Start()
	local regions = Hud.get()

	local open = Style.bigButton("💎", "Robux", Style.Colors.Blue)
	open.button.Name = "OpenStore"
	open.button.LayoutOrder = BUTTON_ORDER
	open.button.Parent = regions.left

	local entries: { { kind: string, key: string } } = {}
	for _, key in Monetization.PassOrder do
		table.insert(entries, { kind = "Pass", key = key })
	end
	for _, key in Monetization.ProductOrder do
		table.insert(entries, { kind = "Product", key = key })
	end

	local window = Style.window("Loja de Robux", "💎", Style.Colors.Blue, Vector2.new(520, 130 + #entries * (ROW_HEIGHT + 8)))
	window.frame.Name = "StoreWindow"
	window.frame.Parent = regions.windows
	Style.list(window.content, 8)

	local promptPurchase = Remotes.getFunction(Remotes.Functions.PromptPurchase)
	local messageToken = 0
	local function showMessage(text: string)
		messageToken += 1
		local token = messageToken
		window.message.Text = text
		window.message.TextColor3 = Style.Colors.Error
		task.delay(MESSAGE_SECONDS, function()
			if messageToken == token then
				window.message.Text = ""
			end
		end)
	end

	for index, entry in entries do
		local info = if entry.kind == "Pass"
			then Monetization.GamePasses[entry.key]
			else Monetization.Products[entry.key]
		local row = Style.row(`{ICONS[entry.key] or "⭐"} {info.DisplayName}`, info.Description, Style.Colors.Blue, ROW_HEIGHT)
		row.frame.LayoutOrder = index
		row.frame.Parent = window.content

		local function refresh()
			local owned = entry.kind == "Pass" and player:GetAttribute(`Pass_{entry.key}`) == true
			local available = info.Id ~= 0 and not owned
			Style.setButtonText(row.button, if info.Id == 0 then "Em breve" elseif owned then "Comprado" else "Comprar")
			Style.setButtonColor(row.button, if available then Style.Colors.Green else Style.Colors.Gray)
		end
		if entry.kind == "Pass" then
			player:GetAttributeChangedSignal(`Pass_{entry.key}`):Connect(refresh)
		end
		refresh()

		row.button.Activated:Connect(function()
			local ok, success, text = pcall(function()
				return promptPurchase:InvokeServer(entry.kind, entry.key)
			end)
			if not ok then
				showMessage("Não foi possível falar com o servidor")
			elseif success ~= true and typeof(text) == "string" and text ~= "" then
				showMessage(text)
			end
		end)
	end

	open.button.Activated:Connect(function()
		if window.frame.Visible then
			window.frame.Visible = false
		else
			Hud.openWindow(window.frame)
		end
	end)
	window.close.Activated:Connect(function()
		window.frame.Visible = false
	end)
end

return StoreController
