--!strict

-- Atalhos de teste que só existem no Studio. Fora dele, não conecta nada.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StudioTest = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("StudioTest"))

local StudioTestService = {}

local function applyToCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.WalkSpeed = StudioTest.WalkSpeed
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(applyToCharacter)
	if player.Character then
		task.spawn(applyToCharacter, player.Character)
	end
end

function StudioTestService:Start()
	if not RunService:IsStudio() or not StudioTest.Enabled then
		return
	end

	-- warn de propósito: lembrete visível de que os números do teste não são os reais.
	warn(`[StudioTest] Modo de teste ativo (só no Studio): WalkSpeed = {StudioTest.WalkSpeed}`)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return StudioTestService
