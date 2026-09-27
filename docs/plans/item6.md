# Item 6 — Coleta de pergaminhos nas fases

Proposta aprovada. O mapa já tem `Phase1..Phase10`.

## Minitarefas

- [x] 6.1 `Config/Phases.luau`: pesos de raridade, `MaxScrolls` e `SpawnInterval` das 10 fases; `LegendaryEvent` (5 min, fases 8–10, Lendário 75 / Mítico 20 / Secreto 5)
- [x] 6.2 `BaseService`: `GetPhaseCount()` e `GetPhasePart(index)`
- [x] 6.3 `WarriorService`: `GetMaxSlots()` e `IsInPlacementArea(player, position?)`
- [x] 6.4 `Remotes`: `Functions.PlaceScroll` e `Events.Announcement`
- [x] 6.5 `ScrollService`: spawn por fase (começa cheia, repõe 1 por intervalo), ponto aleatório no volume + raio até o chão
- [x] 6.6 `ScrollService`: coleta encostando com distância real validada no servidor; carregar 1 por vez, visual acima da cabeça
- [x] 6.7 `ScrollService`: perda ao morrer / trocar de personagem / sair → volta para o chão da fase de origem
- [x] 6.8 `ScrollService`: remote `PlaceScroll` sem argumentos, rate limit, mensagens em português
- [x] 6.9 `ScrollService`: evento lendário com aviso no chat
- [x] 6.10 `ScrollController` (cliente): botão "Colocar pergaminho", mensagens, aviso no chat, giro local
- [x] 6.11 Remover o `TestService`
- [x] 6.12 `luau-lsp` strict sem erros; `CLAUDE.md` (checklist e Estado atual); commit
