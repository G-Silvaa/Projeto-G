--!strict

-- HUD básico: mensagens curtas vindas do servidor (Events.Notify).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local HudController = {}

local NOTIFY_SECONDS = 4

local player = Players.LocalPlayer

function HudController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

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

	local token = 0
	Remotes.getEvent(Remotes.Events.Notify).OnClientEvent:Connect(function(text: unknown)
		if typeof(text) ~= "string" then
			return
		end
		token += 1
		local current = token
		notice.Text = text
		notice.Visible = true
		task.delay(NOTIFY_SECONDS, function()
			if token == current then
				notice.Visible = false
			end
		end)
	end)
end

return HudController
