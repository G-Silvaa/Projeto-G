--!strict

-- Loja da base: botão "Loja" (só aparece dentro do próprio ringue) e painel com os
-- upgrades. Preços calculados com a mesma fórmula do servidor (Config/Upgrades);
-- quem decide a compra é o UpgradeService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UpgradesConfig = require(Shared:WaitForChild("Config"):WaitForChild("Upgrades"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ShopController = {}

local MESSAGE_SECONDS = 3

local player = Players.LocalPlayer

local function makeButton(text: string, color: Color3, parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = color
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Text = text
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	return button
end

local function makeLabel(text: string, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

function ShopController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopGui"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local openButton = makeButton("Loja", Color3.fromRGB(230, 150, 40), gui)
	openButton.Name = "OpenShop"
	openButton.AnchorPoint = Vector2.new(1, 1)
	openButton.Position = UDim2.new(1, -20, 1, -40)
	openButton.Size = UDim2.fromOffset(130, 50)
	openButton.Visible = false

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(440, 330)
	panel.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = gui
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local title = makeLabel("Loja da base", panel)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 32)

	local closeButton = makeButton("X", Color3.fromRGB(200, 60, 60), panel)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 10)
	closeButton.Size = UDim2.fromOffset(36, 32)

	local message = makeLabel("", panel)
	message.AnchorPoint = Vector2.new(0, 1)
	message.Position = UDim2.new(0, 16, 1, -10)
	message.Size = UDim2.new(1, -32, 0, 24)
	message.TextXAlignment = Enum.TextXAlignment.Center

	local buyUpgrade = Remotes.getFunction(Remotes.Functions.BuyUpgrade)
	local rows: { () -> () } = {}
	local messageToken = 0

	local function showMessage(text: string, success: boolean)
		messageToken += 1
		local token = messageToken
		message.Text = text
		message.TextColor3 = if success then Color3.fromRGB(120, 255, 140) else Color3.fromRGB(255, 110, 110)
		task.delay(MESSAGE_SECONDS, function()
			if messageToken == token then
				message.Text = ""
			end
		end)
	end

	for index, upgradeId in UpgradesConfig.Order do
		local info = UpgradesConfig.List[upgradeId]
		local rowY = 52 + (index - 1) * 80

		local name = makeLabel(info.DisplayName, panel)
		name.Position = UDim2.fromOffset(16, rowY)
		name.Size = UDim2.new(1, -170, 0, 26)

		local detail = makeLabel("", panel)
		detail.Position = UDim2.fromOffset(16, rowY + 28)
		detail.Size = UDim2.new(1, -170, 0, 20)
		detail.TextColor3 = Color3.fromRGB(190, 190, 200)

		local buy = makeButton("", Color3.fromRGB(40, 170, 90), panel)
		buy.AnchorPoint = Vector2.new(1, 0)
		buy.Position = UDim2.new(1, -16, 0, rowY + 4)
		buy.Size = UDim2.fromOffset(140, 44)

		local function refresh()
			local level = player:GetAttribute(`Upgrade_{upgradeId}`)
			local current = if typeof(level) == "number" then level else 0
			local cost = UpgradesConfig.CostFor(upgradeId, current)
			detail.Text = `{info.Description} · nível {current}/{info.MaxLevel}`
			buy.Text = if cost then `$ {Format.number(cost)}` else "Máximo"
			buy.AutoButtonColor = cost ~= nil
			buy.BackgroundColor3 = if cost then Color3.fromRGB(40, 170, 90) else Color3.fromRGB(90, 90, 100)
		end
		table.insert(rows, refresh)
		player:GetAttributeChangedSignal(`Upgrade_{upgradeId}`):Connect(refresh)
		refresh()

		local busy = false
		buy.Activated:Connect(function()
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
			else
				showMessage("Não foi possível falar com o servidor", false)
			end
		end)
	end

	local function refreshOpenButton()
		local inBase = player:GetAttribute("InOwnBase") == true
		openButton.Visible = inBase
		if not inBase then
			panel.Visible = false
		end
	end
	player:GetAttributeChangedSignal("InOwnBase"):Connect(refreshOpenButton)
	refreshOpenButton()

	openButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
		for _, refresh in rows do
			refresh()
		end
	end)
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)
end

return ShopController
