# Item 12 — Monetização

## Decisões

- `Config/Monetization.luau`, todos os IDs = 0 (placeholders):
  - Game Passes: Renda x2, Treino x2, +2 espaços;
  - Developer Products: Pular chocagem, Pacote de dinheiro.
- **ID 0 = desligado:**
  - o servidor nunca consulta nem oferece;
  - `HasPass` retorna `false`;
  - a loja mostra "Em breve";
  - nada quebra.
- **Game Passes:** a posse é consultada ao entrar (`UserOwnsGamePassAsync` com `pcall`) e atualizada em `PromptGamePassPurchaseFinished`. Fica guardada em memória e em atributos `Pass_<Key>` (só para a UI). Os efeitos são registrados como os dos upgrades: `AddIncomeMultiplier`, `AddTrainingMultiplier` e `AddSlotBonus`.
- **Developer Products:**
  - `ProcessReceipt` é idempotente: `PurchaseId` já processado → `PurchaseGranted` sem entregar de novo.
  - Jogador fora do servidor ou dados não carregados → `NotProcessedYet`, e o Roblox tenta de novo depois.
  - Erro ao entregar → `NotProcessedYet`.
  - Os `PurchaseId` ficam em `PlayerData.ProcessedReceipts` (chave nova; mantém os 200 mais recentes).
- **Prompt de compra pelo servidor:** remote `Functions.PromptPurchase(kind, key)`. O servidor valida:
  - tipos e chave existente;
  - ID ≠ 0;
  - rate limit;
  - Game Pass ainda não comprado;
  - "Pular chocagem" só com algum pergaminho chocando.
  
  Só então chama `MarketplaceService:Prompt...`.
- **"Pular chocagem":** termina na hora todas as chocagens em andamento (`WarriorService:SkipHatching`).
- **"Pacote de dinheiro":** `CurrencyService:AddMoney` com um valor fixo da config.
- **Limitação (registrada em `docs/decisoes-pendentes.md`):** o `PlayerDataService` não tem "salvar agora", e a regra é só acrescentar chaves ao template dele. Então a compra é entregue e marcada na memória e salva no autosave/saída. Se o servidor cair nesse intervalo, o jogador perde a compra, mas ela nunca é duplicada.

## Minitarefas

- [x] 12.1 `Config/Monetization.luau`
- [x] 12.2 Template: `ProcessedReceipts = {}`
- [x] 12.3 `WarriorService`: `SkipHatching(player)` e `HasHatching(player)`
- [x] 12.4 `Remotes`: `Functions.PromptPurchase`
- [x] 12.5 `MonetizationService`: posse de Game Pass, efeitos, `ProcessReceipt` idempotente, prompt validado
- [x] 12.6 `StoreController` (cliente): botão "Robux" + painel (passes/produtos, "Em breve" para ID 0, "Comprado")
- [x] 12.7 `luau-lsp` strict sem erros; `CLAUDE.md`; commit
