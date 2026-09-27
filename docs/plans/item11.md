# Item 11 — Rebirth

## Decisões

- `Config/Rebirth.luau`:
  - custo = `floor(BaseCost × CostGrowth^rebirths)` (1M, ×3 a cada rebirth);
  - multiplicador permanente de renda = `1 + rebirths × 0,5`.
- `PlayerData.Rebirths` (chave nova, sem migração).
- **Remote `Functions.Rebirth`** (sem argumentos). O servidor valida:
  - rate limit;
  - dados carregados;
  - Money ≥ custo.
- **O que o rebirth faz:** zera o Money (`RemoveMoney` do saldo inteiro), os guerreiros (`WarriorService:ResetSlots`, que também destrava slots) e os upgrades (`UpgradeService:ResetAll`), e soma 1 em `Rebirths`. O Speed não é zerado, porque o pedido lista só dinheiro, guerreiros e upgrades.
- **Roubo em andamento:** se alguém estava carregando um item do jogador, ao entregar recebe "Esse item não existe mais". O item foi embora com o rebirth, não duplica.
- **Limite do `IntValue`:** o `Money` do leaderstats vira `StringValue` com `Format.number` (1.5K, 2.3M, 4.1B). O `CurrencyService` também passa a marcar o atributo numérico `Money` no `Player`, só para o HUD.
  - É uma mudança só de exibição: o dado salvo (`Money`) continua o mesmo número.
- **HUD:** painel com Money, Speed e Rebirths, e botão "Rebirth" com o custo (confirmação em dois cliques).

## Minitarefas

- [x] 11.1 `Config/Rebirth.luau`
- [x] 11.2 Template: `Rebirths = 0`
- [x] 11.3 `CurrencyService`: leaderstats `Money` como `StringValue` formatado + atributo `Money`
- [x] 11.4 `WarriorService:ResetSlots(player)`
- [x] 11.5 `Remotes`: `Functions.Rebirth`
- [x] 11.6 `RebirthService`: validação, reset, multiplicador de renda registrado, atributo `Rebirths`
- [x] 11.7 `HudController`: Money / Speed / Rebirths e botão de rebirth
- [x] 11.8 `luau-lsp` strict sem erros; `CLAUDE.md`; commit
