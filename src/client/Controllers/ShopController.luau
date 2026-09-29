--!strict

-- Loja da base: botão "Loja" na coluna da esquerda (só aparece dentro do próprio
-- ringue) e janela com os upgrades. Preços calculados com a mesma fórmula do
-- servidor (Config/Upgrades); quem decide a compra é o UpgradeService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UpgradesConfig = require(Shared:WaitForChild("Config"):WaitForChild("Upgrades"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Hud = require(UI:WaitForChild("Hud"))
local Style = require(UI:WaitForChild("Style"))

local ShopController = {}

local MESSAGE_SECONDS = 3
local BUTTON_ORDER = 1
local ROW_HEIGHT = 74
local ICONS: { [string]: string } = {
	ExtraSlots = "📦",
	IncomeMultiplier = "💰",
	TrainingSpeed = "👟",
}

local player = Players.LocalPlayer

function ShopController:Start()
	local regions = Hud.get()

	local open = Style.bigButton("🛒", "Loja", Style.Colors.Green)
	open.button.Name = "OpenShop"
	open.button.LayoutOrder = BUTTON_ORDER
	open.button.Visible = false
	open.button.Parent = regions.left

	local rowCount = #UpgradesConfig.Order
	local window = Style.window("Loja da base", "🛒", Style.Colors.Green, Vector2.new(520, 130 + rowCount * (ROW_HEIGHT + 10)))
	window.frame.Name = "ShopWindow"
	window.frame.Parent = regions.windows
	Style.list(window.content, 10)

	local buyUpgrade = Remotes.getFunction(Remotes.Functions.BuyUpgrade)
	local refreshers: { () -> () } = {}
	local messageToken = 0

	local function showMessage(text: string, success: boolean)
		messageToken += 1
		local token = messageToken
		window.message.Text = text
		window.message.TextColor3 = if success then Style.Colors.Success else Style.Colors.Error
		task.delay(MESSAGE_SECONDS, function()
			if messageToken == token then
				window.message.Text = ""
			end
		end)
	end

	for index, upgradeId in UpgradesConfig.Order do
		local info = UpgradesConfig.List[upgradeId]
		local row = Style.row(`{ICONS[upgradeId] or "⭐"} {info.DisplayName}`, "", Style.Colors.Green, ROW_HEIGHT)
		row.frame.LayoutOrder = index
		row.frame.Parent = window.content

		local function refresh()
			local level = player:GetAttribute(`Upgrade_{upgradeId}`)
			local current = if typeof(level) == "number" then level else 0
			local cost = UpgradesConfig.CostFor(upgradeId, current)
			row.detail.Text = `{info.Description} · nível {current}/{info.MaxLevel}`
			Style.setButtonText(row.button, if cost then `${Format.number(cost)}` else "Máximo")
			Style.setButtonColor(row.button, if cost then Style.Colors.Green else Style.Colors.Gray)
		end
		table.insert(refreshers, refresh)
		player:GetAttributeChangedSignal(`Upgrade_{upgradeId}`):Connect(refresh)
		refresh()

		local busy = false
		row.button.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			local ok, success, text = pcall(function()
				return buyUpgrade:InvokeServer(upgradeId)
			end)
			busy = false
			if ok then
				showMessage(if typeof(text) == "string" then text else "", success == true)
				if success == true then
					Style.pop(row.frame)
				end
			else
				showMessage("Não foi possível falar com o servidor", false)
			end
		end)
	end

	local function refreshOpenButton()
		local inBase = player:GetAttribute("InOwnBase") == true
		open.button.Visible = inBase
		if not inBase then
			window.frame.Visible = false
		end
	end
	player:GetAttributeChangedSignal("InOwnBase"):Connect(refreshOpenButton)
	refreshOpenButton()

	open.button.Activated:Connect(function()
		if window.frame.Visible then
			window.frame.Visible = false
			return
		end
		for _, refresh in refreshers do
			refresh()
		end
		Hud.openWindow(window.frame)
	end)
	window.close.Activated:Connect(function()
		window.frame.Visible = false
	end)
end

return ShopController
