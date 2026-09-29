--!strict

-- Contagem regressiva do próximo totem lendário, no canto de baixo à direita:
-- "🌟 Lendário em 4m 26s". Lê o atributo NextLegendaryAt que o ScrollService marca
-- no ReplicatedStorage (horário do servidor, comparado com GetServerTimeNow).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local UI = script.Parent.Parent:WaitForChild("UI")
local Hud = require(UI:WaitForChild("Hud"))
local Style = require(UI:WaitForChild("Style"))

local EventTimerController = {}

local UPDATE_SECONDS = 0.5

local function formatRemaining(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local minutes = math.floor(total / 60)
	local secs = total % 60
	return if minutes > 0 then `{minutes}m {secs}s` else `{secs}s`
end

function EventTimerController:Start()
	local box = Instance.new("Frame")
	box.Name = "EventTimer"
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = Style.Colors.Panel
	box.BackgroundTransparency = 0.2
	box.Visible = false
	box.Parent = Hud.get().bottomRight
	Style.corner(box, 14)
	Style.stroke(box, Style.Colors.Ink, 3)

	local text = Style.label("", Style.TitleFont, 3)
	text.Size = UDim2.new(1, -20, 1, -12)
	text.Position = UDim2.fromOffset(10, 6)
	text.TextXAlignment = Enum.TextXAlignment.Right
	text.Parent = box
	Style.gradient(text, Color3.fromRGB(255, 240, 140), Color3.fromRGB(255, 170, 30))

	while true do
		local nextAt = ReplicatedStorage:GetAttribute("NextLegendaryAt")
		if typeof(nextAt) == "number" then
			box.Visible = true
			text.Text = `🌟 Lendário em {formatRemaining(nextAt - Workspace:GetServerTimeNow())}`
		else
			box.Visible = false
		end
		task.wait(UPDATE_SECONDS)
	end
end

return EventTimerController
