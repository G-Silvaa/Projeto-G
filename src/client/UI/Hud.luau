--!strict

-- Tela única do HUD, com as regiões onde cada controller põe suas peças:
--   left        coluna de botões grandes, no meio da esquerda (abaixo do chat)
--   bottomLeft  números grandes (velocidade, dinheiro)
--   topRight    placar
--   bottomRight contagem do evento
--   bottomCenter dicas (ex.: "Clique no chão da sua base...")
--   notices     avisos no alto, no centro
--   windows     janelas (loja etc.), no centro
-- A escala acompanha o tamanho da tela (celular fica menor, tela grande maior).
-- Criada na primeira chamada de Hud.get(); os controllers só pegam as regiões.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Style = require(script.Parent.Style)

local Hud = {}

-- Tamanho de tela em que a escala é 1.
local REFERENCE_SIZE = Vector2.new(1280, 720)
local MIN_SCALE = 0.55
local MAX_SCALE = 1.25

export type Regions = {
	gui: ScreenGui,
	left: Frame,
	bottomLeft: Frame,
	topRight: Frame,
	bottomRight: Frame,
	bottomCenter: Frame,
	notices: Frame,
	windows: Frame,
}

local regions: Regions? = nil

local function region(name: string, anchor: Vector2, position: UDim2, size: UDim2, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = anchor
	frame.Position = position
	frame.Size = size
	frame.Parent = parent
	return frame
end

local function watchScale(scale: UIScale)
	local function update()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local viewport = camera.ViewportSize
		local ratio = math.min(viewport.X / REFERENCE_SIZE.X, viewport.Y / REFERENCE_SIZE.Y)
		scale.Scale = math.clamp(ratio, MIN_SCALE, MAX_SCALE)
	end
	local function watchCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
		update()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
end

function Hud.get(): Regions
	local existing = regions
	if existing then
		return existing
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Tudo dentro de um quadro que escala junto (UIScale só vale pros filhos).
	local root = region("Root", Vector2.zero, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), gui)
	local scale = Instance.new("UIScale")
	scale.Parent = root
	watchScale(scale)
	-- Com UIScale, o quadro também encolhe; compensa pra ele continuar cobrindo a tela.
	scale:GetPropertyChangedSignal("Scale"):Connect(function()
		root.Size = UDim2.fromScale(1 / scale.Scale, 1 / scale.Scale)
	end)
	root.Size = UDim2.fromScale(1 / scale.Scale, 1 / scale.Scale)

	local left = region("Left", Vector2.new(0, 0.5), UDim2.new(0, 14, 0.5, 40), UDim2.fromOffset(200, 300), root)
	Style.list(left, 10)

	local bottomLeft = region("BottomLeft", Vector2.new(0, 1), UDim2.new(0, 14, 1, -14), UDim2.fromOffset(420, 170), root)
	local bottomLayout = Style.list(bottomLeft, 4)
	bottomLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom

	local topRight = region("TopRight", Vector2.new(1, 0), UDim2.new(1, -14, 0, 64), UDim2.fromOffset(330, 320), root)
	local bottomRight = region("BottomRight", Vector2.new(1, 1), UDim2.new(1, -14, 1, -14), UDim2.fromOffset(340, 60), root)
	local bottomCenter =
		region("BottomCenter", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -90), UDim2.fromOffset(560, 50), root)
	local notices = region("Notices", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 90), UDim2.fromOffset(640, 120), root)
	local noticeLayout = Style.list(notices, 6)
	noticeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local windows = region("Windows", Vector2.zero, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), root)
	windows.ZIndex = 10

	local created: Regions = {
		gui = gui,
		left = left,
		bottomLeft = bottomLeft,
		topRight = topRight,
		bottomRight = bottomRight,
		bottomCenter = bottomCenter,
		notices = notices,
		windows = windows,
	}
	regions = created
	return created
end

-- Aviso no alto da tela, que some sozinho. Mais novo embaixo; no máximo MAX_NOTICES.
local NOTICE_SECONDS = 3.5
local MAX_NOTICES = 3
local noticeOrder = 0

function Hud.notify(text: string, color: Color3?)
	if text == "" then
		return
	end
	local notices = Hud.get().notices
	noticeOrder += 1

	local label = Style.label(text, Style.TitleFont, 3)
	label.LayoutOrder = noticeOrder
	label.Size = UDim2.new(1, 0, 0, 34)
	label.TextColor3 = color or Style.Colors.Yellow
	label.Parent = notices
	Style.pop(label)

	local shown: { TextLabel } = {}
	for _, child in notices:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(shown, child)
		end
	end
	table.sort(shown, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = 1, #shown - MAX_NOTICES do
		shown[index]:Destroy()
	end

	task.delay(NOTICE_SECONDS, function()
		label:Destroy()
	end)
end

-- Só uma janela aberta por vez: abrir uma fecha as outras.
function Hud.openWindow(window: Frame)
	local current = Hud.get()
	for _, child in current.windows:GetChildren() do
		if child:IsA("GuiObject") and child ~= window then
			child.Visible = false
		end
	end
	window.Visible = true
	Style.pop(window)
end

return Hud
