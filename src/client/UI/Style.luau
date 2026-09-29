--!strict

-- Kit visual do HUD: cores, fontes e peças prontas (botão grande com ícone, janela,
-- texto com contorno grosso), pra toda a interface ter a mesma cara. Só cria
-- instâncias; quem usa decide onde colocar e o que fazer no clique.
-- Ícones são emojis (não dá pra subir imagens pelo código); trocar por ImageLabel
-- com asset próprio é só mudar iconLabel.

local TweenService = game:GetService("TweenService")

local Style = {}

Style.TitleFont = Enum.Font.LuckiestGuy
Style.BodyFont = Enum.Font.FredokaOne

Style.Colors = table.freeze({
	White = Color3.fromRGB(255, 255, 255),
	Ink = Color3.fromRGB(20, 16, 34), -- contornos e sombras
	Panel = Color3.fromRGB(34, 30, 54),
	PanelLight = Color3.fromRGB(52, 46, 80),
	Muted = Color3.fromRGB(200, 196, 220),
	Green = Color3.fromRGB(70, 220, 90),
	Blue = Color3.fromRGB(40, 190, 255),
	Purple = Color3.fromRGB(170, 80, 255),
	Pink = Color3.fromRGB(255, 70, 200),
	Orange = Color3.fromRGB(255, 150, 40),
	Red = Color3.fromRGB(240, 60, 70),
	Yellow = Color3.fromRGB(255, 215, 50),
	Gray = Color3.fromRGB(110, 110, 125),
	Success = Color3.fromRGB(120, 255, 140),
	Error = Color3.fromRGB(255, 110, 110),
})

local HOVER_SCALE = 1.06
local PRESS_SCALE = 0.94
local TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Style.darker(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v - amount, 0, 1))
end

function Style.corner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

-- Borda (em Frame/botão) ou contorno do texto (em TextLabel, com mode Contextual).
function Style.stroke(parent: Instance, color: Color3, thickness: number, mode: Enum.ApplyStrokeMode?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

-- Degradê vertical (cima → baixo).
function Style.gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = 90
	gradient.Parent = parent
	return gradient
end

function Style.padding(parent: Instance, pixels: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.Parent = parent
end

function Style.list(parent: Instance, spacing: number, horizontal: boolean?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, spacing)
	layout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layout.Parent = parent
	return layout
end

-- Texto de desenho animado: fonte grossa, contorno escuro grosso.
function Style.label(text: string, font: Enum.Font?, strokeThickness: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font or Style.TitleFont
	label.Text = text
	label.TextColor3 = Style.Colors.White
	label.TextScaled = true
	Style.stroke(label, Style.Colors.Ink, strokeThickness or 2, Enum.ApplyStrokeMode.Contextual)
	return label
end

-- Cresce ao passar o mouse e afunda ao clicar.
function Style.animate(button: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local function to(value: number)
		TweenService:Create(scale, TWEEN, { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		to(HOVER_SCALE)
	end)
	button.MouseLeave:Connect(function()
		to(1)
	end)
	button.MouseButton1Down:Connect(function()
		to(PRESS_SCALE)
	end)
	button.MouseButton1Up:Connect(function()
		to(HOVER_SCALE)
	end)
end

-- "Pulo" rápido, pra chamar atenção quando um número ou aviso muda.
function Style.pop(target: GuiObject)
	local scale = target:FindFirstChildOfClass("UIScale")
	if scale == nil then
		scale = Instance.new("UIScale")
		scale.Parent = target
	end
	local found = scale :: UIScale
	found.Scale = 1.15
	TweenService:Create(found, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

export type BigButton = {
	button: TextButton,
	icon: TextLabel,
	text: TextLabel,
	setColor: (Color3) -> (),
}

-- Botão grande do menu: bloco colorido com degradê, borda escura grossa, ícone à
-- esquerda e texto com contorno.
function Style.bigButton(icon: string, text: string, color: Color3, size: Vector2?): BigButton
	local dimensions = size or Vector2.new(190, 64)
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(dimensions.X, dimensions.Y)
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = color
	Style.corner(button, 12)
	local border = Style.stroke(button, Style.darker(color, 0.45), 3)
	Style.gradient(button, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 190))

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.BackgroundTransparency = 1
	iconLabel.Size = UDim2.new(0, dimensions.Y - 12, 1, -12)
	iconLabel.Position = UDim2.fromOffset(8, 6)
	iconLabel.Font = Style.BodyFont
	iconLabel.TextScaled = true
	iconLabel.Text = icon
	iconLabel.Parent = button

	local textLabel = Style.label(text, Style.TitleFont, 2.5)
	textLabel.Name = "Label"
	textLabel.Position = UDim2.new(0, dimensions.Y, 0, 10)
	textLabel.Size = UDim2.new(1, -dimensions.Y - 10, 1, -20)
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.Parent = button

	Style.animate(button)

	return {
		button = button,
		icon = iconLabel,
		text = textLabel,
		setColor = function(newColor: Color3)
			button.BackgroundColor3 = newColor
			border.Color = Style.darker(newColor, 0.45)
		end,
	}
end

-- Botão pequeno de ação (Comprar, X), colorido e com borda.
function Style.smallButton(text: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = color
	Style.corner(button, 10)
	Style.stroke(button, Style.darker(color, 0.45), 2.5)
	Style.gradient(button, Color3.fromRGB(255, 255, 255), Color3.fromRGB(195, 195, 195))

	local label = Style.label(text, Style.TitleFont, 2)
	label.Name = "Label"
	label.Size = UDim2.new(1, -12, 1, -10)
	label.Position = UDim2.fromOffset(6, 5)
	label.Parent = button

	Style.animate(button)
	return button
end

function Style.setButtonText(button: TextButton, text: string)
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

function Style.setButtonColor(button: TextButton, color: Color3)
	button.BackgroundColor3 = color
	local border = button:FindFirstChildOfClass("UIStroke")
	if border then
		border.Color = Style.darker(color, 0.45)
	end
end

export type Window = {
	frame: Frame,
	content: Frame,
	close: TextButton,
	message: TextLabel,
}

-- Janela no centro da tela: faixa de título colorida, botão X, área de conteúdo e
-- uma linha de mensagem embaixo.
function Style.window(title: string, icon: string, accent: Color3, size: Vector2): Window
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundColor3 = Style.Colors.Panel
	frame.Visible = false
	Style.corner(frame, 16)
	Style.stroke(frame, Style.Colors.Ink, 4)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 56)
	header.BackgroundColor3 = accent
	header.Parent = frame
	Style.corner(header, 16)
	Style.gradient(header, Color3.fromRGB(255, 255, 255), Color3.fromRGB(185, 185, 185))
	-- Tampa os cantos de baixo da faixa, pra ela encaixar reta no painel.
	local flat = Instance.new("Frame")
	flat.BorderSizePixel = 0
	flat.BackgroundColor3 = accent
	flat.Position = UDim2.new(0, 0, 1, -16)
	flat.Size = UDim2.new(1, 0, 0, 16)
	flat.Parent = header
	Style.gradient(flat, Color3.fromRGB(205, 205, 205), Color3.fromRGB(185, 185, 185))

	local titleLabel = Style.label(`{icon} {title}`, Style.TitleFont, 3)
	titleLabel.Position = UDim2.fromOffset(16, 8)
	titleLabel.Size = UDim2.new(1, -90, 0, 40)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 2
	titleLabel.Parent = header

	local close = Style.smallButton("X", Style.Colors.Red)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 8)
	close.Size = UDim2.fromOffset(44, 40)
	close.ZIndex = 3
	close.Parent = header

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(14, 66)
	content.Size = UDim2.new(1, -28, 1, -110)
	content.Parent = frame

	local message = Style.label("", Style.BodyFont, 1.5)
	message.Name = "Message"
	message.AnchorPoint = Vector2.new(0.5, 1)
	message.Position = UDim2.new(0.5, 0, 1, -10)
	message.Size = UDim2.new(1, -28, 0, 26)
	message.Parent = frame

	return { frame = frame, content = content, close = close, message = message }
end

-- Linha de item numa janela: nome, descrição e um botão à direita.
export type Row = {
	frame: Frame,
	name: TextLabel,
	detail: TextLabel,
	button: TextButton,
}

function Style.row(name: string, detail: string, buttonColor: Color3, height: number): Row
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundColor3 = Style.Colors.PanelLight
	Style.corner(frame, 12)
	Style.stroke(frame, Style.Colors.Ink, 2)

	local nameLabel = Style.label(name, Style.TitleFont, 2)
	nameLabel.Position = UDim2.fromOffset(12, 6)
	nameLabel.Size = UDim2.new(1, -170, 0.5, -4)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = frame

	local detailLabel = Style.label(detail, Style.BodyFont, 1.2)
	detailLabel.Position = UDim2.new(0, 12, 0.5, 2)
	detailLabel.Size = UDim2.new(1, -170, 0.5, -8)
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.TextColor3 = Style.Colors.Muted
	detailLabel.Parent = frame

	local button = Style.smallButton("", buttonColor)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.new(0, 140, 1, -18)
	button.Parent = frame

	return { frame = frame, name = nameLabel, detail = detailLabel, button = button }
end

return Style
