# Item 9 — Roubo entre jogadores

## Decisões

- **O item roubado nunca sai dos dados do dono até a entrega.** Ao roubar, o slot do dono fica só *travado em memória*: some do ringue, não rende e não pode ser roubado de novo. O ladrão carrega um pergaminho da mesma raridade.
  - Entregou no próprio ringue: o slot é criado no ladrão (mesma raridade, guerreiro e horário de chocagem) e só então removido do dono (`TransferSlot`).
  - Ladrão morreu, foi pego pelo dono ou por um guardião, ou saiu: o slot é destravado e volta a aparecer para o dono.
  - Dono saiu no meio do roubo: o roubo é cancelado e o item continua salvo com o dono. É o caminho mais seguro, sem duplicar nem perder item, sem precisar escrever nos dados de quem está offline.
- **Roubar:** `ProximityPrompt` "Roubar" (segurar 1 s) em cada slot. O cliente esconde o prompt dos próprios slots. O servidor valida:
  - não é o dono;
  - não está carregando;
  - rate limit;
  - cooldown de roubo;
  - distância real até o slot;
  - proteção de alguns segundos após o slot ser colocado (`PlacedAt`).
- **Dono pega o ladrão:** se o dono encostar no ladrão (distância ≤ `CatchDistance`, checada no servidor a cada 0,25 s), o item volta.
- **Avisos pelo `Notify`:** o dono é avisado no início do roubo, na entrega e na devolução; o ladrão, nos casos dele.
- **`ScrollService` generalizado:** carregar qualquer item com dois callbacks, `onPlace` (o que acontece ao apertar "Colocar") e `onLost` (morreu / pego / saiu). Os pergaminhos de fase passam a usar o mesmo caminho.
- Números em `Config/Steal.luau`.

## Minitarefas

- [x] 9.1 `Config/Steal.luau`
- [x] 9.2 `ScrollService`: carregar genérico (`onPlace`/`onLost`), `CarryItem(player, rarity, onPlace, onLost)`, mensagens de roubo
- [x] 9.3 `WarriorService`: `PlacedAt` nos slots novos; `ProximityPrompt` "Roubar" nos slots; `OnStealAttempt`
- [x] 9.4 `WarriorService`: travar/destravar slot (sem renda, invisível), `GetSlotInfo`, `GetSlotWorldPosition`, `TransferSlot`
- [x] 9.5 `StealService`: validações, começo do roubo, entrega, devolução, dono pega o ladrão, dono sai
- [x] 9.6 Cliente: esconder o prompt dos próprios slots
- [x] 9.7 `luau-lsp` strict sem erros; `CLAUDE.md`; commit
