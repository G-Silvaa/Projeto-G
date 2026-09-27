--!strict

-- Rebirth: zera Money, guerreiros e upgrades em troca de um multiplicador
-- permanente de renda (RebirthService).
local BaseCost = 1_000_000
local CostGrowth = 3
local MultiplierPerRebirth = 0.5

return table.freeze({
	BaseCost = BaseCost,
	CostGrowth = CostGrowth,
	MultiplierPerRebirth = MultiplierPerRebirth,

	-- Custo do próximo rebirth para quem já fez `rebirths`.
	CostFor = function(rebirths: number): number
		return math.floor(BaseCost * CostGrowth ^ rebirths)
	end,

	-- Multiplicador de renda com `rebirths` feitos (0 rebirths = x1).
	MultiplierFor = function(rebirths: number): number
		return 1 + rebirths * MultiplierPerRebirth
	end,
})
