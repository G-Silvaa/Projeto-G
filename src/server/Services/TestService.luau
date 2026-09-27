--!strict

-- TEMPORÁRIO: dá pergaminhos pra testar o WarriorService. Só roda no Studio.
-- Apague este arquivo quando existir a coleta nas fases (item 6).

local RunService = game:GetService("RunService")

local BaseService = require(script.Parent.BaseService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local WarriorService = require(script.Parent.WarriorService)

-- true: esvazia os slots antes de dar os pergaminhos (pra repetir o teste do zero).
-- false: mantém o que já tinha (pra ver a chocagem que continuou com você offline).
local RESET_SLOTS = false

type TestScroll = {
	Rarity: string,
	X: number, -- fração do tamanho do ringue a partir do centro (0.3 = 30% pra um lado)
	Z: number,
	Expected: string,
}

local SCROLLS: { TestScroll } = {
	{ Rarity = "Common", X = -0.3, Z = -0.3, Expected = "true" },
	{ Rarity = "Common", X = 0.3, Z = -0.3, Expected = "true" },
	{ Rarity = "Rare", X = -0.3, Z = 0.3, Expected = "true" },
	{ Rarity = "Epic", X = 0.3, Z = 0.3, Expected = "true" },
	{ Rarity = "Common", X = 0.9, Z = 0, Expected = "false OutsideBase" },
	{ Rarity = "Common", X = -0.3, Z = -0.3, Expected = "false TooClose" },
}

local TestService = {}

local function waitForBase(player: Player): number?
	for _ = 1, 40 do
		local baseIndex = BaseService:GetBase(player)
		if baseIndex then
			return baseIndex
		end
		if player.Parent == nil then
			return nil
		end
		task.wait(0.25)
	end
	return nil
end

local function giveScrolls(player: Player)
	local baseIndex = waitForBase(player)
	if baseIndex == nil then
		warn(`[TestService] {player.Name} não recebeu base; nenhum pergaminho foi dado`)
		return
	end

	local areaCFrame, areaSize = BaseService:GetBaseArea(baseIndex)
	if not areaCFrame or not areaSize then
		return
	end

	if RESET_SLOTS then
		PlayerDataService:Set(player, "Slots", {})
	end

	for _, scroll in SCROLLS do
		local position = areaCFrame * Vector3.new(scroll.X * areaSize.X, 0, scroll.Z * areaSize.Z)
		local ok, reason = WarriorService:AddScroll(player, scroll.Rarity, position)
		print(`[TestService] {scroll.Rarity} em ({scroll.X}, {scroll.Z}) -> {ok} {reason or ""} (esperado: {scroll.Expected})`)
	end

	-- position = nil: usa a posição do jogador, que nasce no centro do ringue.
	if not player.Character then
		player.CharacterAdded:Wait()
	end
	task.wait(1)
	local ok, reason = WarriorService:AddScroll(player, "Common")
	print(`[TestService] Common na posição do jogador -> {ok} {reason or ""} (esperado: true)`)
end

function TestService:Start()
	if not RunService:IsStudio() then
		return
	end
	PlayerDataService:OnPlayerLoaded(giveScrolls)
end

return TestService
