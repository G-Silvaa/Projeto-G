# Item 10 — Upgrades

## Decisões

- 3 upgrades em `Config/Upgrades.luau`:
  - **Mais espaço** (+1 slot por nível, até +6);
  - **Renda** (+10% por nível, até +100%);
  - **Treino** (+25% de ganho na esteira por nível, até +250%).
- Preço: `floor(BaseCost × CostGrowth^nível)`. A função `CostFor` fica no próprio Config para servidor e cliente calcularem igual.
- Níveis salvos em `PlayerData.Upgrades` (`{ [Id]: nível }`), chave nova no template, sem migração.
- **Loja:** botão "Loja" no HUD que só aparece dentro do próprio ringue (atributo `InOwnBase`). Painel com os 3 upgrades, nível atual, efeito, preço e "Comprar".
- **Remote `Functions.BuyUpgrade(upgradeId)`:** o servidor valida:
  - `upgradeId` é string e existe na config;
  - rate limit;
  - o jogador está no próprio ringue;
  - não chegou ao nível máximo;
  - tem dinheiro (`CurrencyService:RemoveMoney`).
- **Efeitos** registrados sem dependência circular:
  - `WarriorService:AddSlotBonus` e `AddIncomeMultiplier`;
  - `SpeedService:AddTrainingMultiplier`.
- Níveis expostos ao cliente como atributos `Upgrade_<Id>`, só para exibir.
- `ResetAll(player)` para o rebirth (item 11).
- `src/shared/Format.luau`: formata números (1.5K, 2.3M, 4.1B), usado na loja e depois no HUD.

## Minitarefas

- [x] 10.1 `Config/Upgrades.luau` (+ `CostFor`, `Order`)
- [x] 10.2 `src/shared/Format.luau`
- [x] 10.3 Template: `Upgrades = {}`
- [x] 10.4 `Remotes`: `Functions.BuyUpgrade`
- [x] 10.5 `UpgradeService`: níveis, compra validada, atributos, efeitos registrados, `ResetAll`
- [x] 10.6 `ShopController` (cliente): botão "Loja" + painel de upgrades
- [x] 10.7 `luau-lsp` strict sem erros; `CLAUDE.md`; commit
