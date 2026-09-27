--!strict

-- Loja de Robux: botão "Robux" e painel com Game Passes e Developer Products.
-- Item com Id 0 (placeholder) aparece como "Em breve". A compra é aberta pelo
-- servidor (Functions.PromptPurchase), que valida antes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared:WaitForChild("Config"):WaitForChild("Monetization"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local StoreController = {}

local MESSAGE_SECONDS = 3
local ROW_HEIGHT = 58

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

function StoreController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "StoreGui"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local openButton = makeButton("Robux", Color3.fromRGB(40, 150, 90), gui)
	openButton.AnchorPoint = Vector2.new(1, 1)
	openButton.Position = UDim2.new(1, -20, 1, -100)
	openButton.Size = UDim2.fromOffset(130, 50)

	local entries: { { kind: string, key: string } } = {}
	for _, key in Monetization.PassOrder do
		table.insert(entries, { kind = "Pass", key = key })
	end
	for _, key in Monetization.ProductOrder do
		table.insert(entries, { kind = "Product", key = key })
	end

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(440, 90 + #entries * ROW_HEIGHT)
	panel.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = gui
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local title = makeLabel("Loja de Robux", panel)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 32)

	local closeButton = makeButton("X", Color3.fromRGB(200, 60, 60), panel)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 10)
	closeButton.Size = UDim2.fromOffset(36, 32)

	local message = makeLabel("", panel)
	message.AnchorPoint = Vector2.new(0, 1)
	message.Position = UDim2.new(0, 16, 1, -8)
	message.Size = UDim2.new(1, -32, 0, 22)
	message.TextXAlignment = Enum.TextXAlignment.Center

	local promptPurchase = Remotes.getFunction(Remotes.Functions.PromptPurchase)
	local messageToken = 0
	local function showMessage(text: string)
		messageToken += 1
		local token = messageToken
		message.Text = text
		message.TextColor3 = Color3.fromRGB(255, 110, 110)
		task.delay(MESSAGE_SECONDS, function()
			if messageToken == token then
				message.Text = ""
			end
		end)
	end

	for index, entry in entries do
		local info = if entry.kind == "Pass"
			then Monetization.GamePasses[entry.key]
			else Monetization.Products[entry.key]
		local rowY = 50 + (index - 1) * ROW_HEIGHT

		local name = makeLabel(info.DisplayName, panel)
		name.Position = UDim2.fromOffset(16, rowY)
		name.Size = UDim2.new(1, -170, 0, 24)

		local detail = makeLabel(info.Description, panel)
		detail.Position = UDim2.fromOffset(16, rowY + 26)
		detail.Size = UDim2.new(1, -170, 0, 18)
		detail.TextColor3 = Color3.fromRGB(190, 190, 200)

		local buy = makeButton("", Color3.fromRGB(40, 150, 90), panel)
		buy.AnchorPoint = Vector2.new(1, 0)
		buy.Position = UDim2.new(1, -16, 0, rowY + 4)
		buy.Size = UDim2.fromOffset(140, 40)

		local function refresh()
			local owned = entry.kind == "Pass" and player:GetAttribute(`Pass_{entry.key}`) == true
			local available = info.Id ~= 0 and not owned
			buy.Text = if info.Id == 0 then "Em breve" elseif owned then "Comprado" else "Comprar"
			buy.AutoButtonColor = available
			buy.BackgroundColor3 = if available then Color3.fromRGB(40, 150, 90) else Color3.fromRGB(90, 90, 100)
		end
		if entry.kind == "Pass" then
			player:GetAttributeChangedSignal(`Pass_{entry.key}`):Connect(refresh)
		end
		refresh()

		buy.Activated:Connect(function()
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

	openButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)
end

return StoreController
