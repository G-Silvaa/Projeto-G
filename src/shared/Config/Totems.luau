--!strict

-- Visual dos totens (o "pergaminho" do jogo). Os modelos ficam no ServerStorage:
--   ServerStorage.Totem_<Rarity> (opcional, ex.: Totem_Legendary): usado como está.
--   ServerStorage.TotemTemplate: usado nas raridades sem modelo próprio. As peças com
--   o atributo RarityTint = true ficam na cor da raridade.
-- Sem nenhum dos dois, o jogo usa o visual antigo (cilindro neon) e dá warn.

export type CarryMount = "Back" | "Head"

return table.freeze({
	-- Altura (studs) do totem enquanto carregado; o clone é reduzido/aumentado pra isso.
	CarryHeight = 2.5,
	-- Onde o totem vai quando carregado: "Back" (costas) ou "Head" (acima da cabeça).
	CarryMount = "Back" :: CarryMount,
	-- Luz na cor da raridade (0 = sem luz).
	LightRange = 8,
})
