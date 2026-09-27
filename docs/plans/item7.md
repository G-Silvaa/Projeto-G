# Item 7 — Guardiões das fases

## Decisões

- NPC R15 gerado pelo servidor com `Players:CreateHumanoidModelFromDescription` (sem asset externo), um por `PhaseN` existente, parado no centro do chão da fase.
- Só persegue quem carrega pergaminho **e** está dentro da fase dele (`BaseService:GetPhaseAt`). Sem alvo, volta ao posto.
- Movimento com `Humanoid:MoveTo` em linha reta, atualizado a cada `UpdateInterval` (0,15 s); rede do guardião é do servidor (`SetNetworkOwner(nil)`).
- Alcance só no servidor. Como o guardião anda muito por atualização nas fases finais, o raio de captura é `max(CatchDistance, velocidade × intervalo × 0,5)`.
- Captura: o pergaminho volta para a fase de origem (`ScrollService:DropCarried`) e o jogador é arremessado por um `LinearVelocity` curto no `HumanoidRootPart` (o constraint replica e o cliente dono do personagem aplica), sem dano.
- Aviso para o jogador pego via novo remote `Events.Notify` (servidor → cliente), exibido por um `HudController` simples.

## Minitarefas

- [x] 7.1 `Config/Guardians.luau`: velocidades das 10 fases (14 → 250), intervalo, captura, arremesso, cooldown
- [x] 7.2 `ScrollService`: `IsCarrying`, `GetCarriers`, `DropCarried`
- [x] 7.3 `Remotes`: `Events.Notify`
- [x] 7.4 `GuardianService`: criar NPCs nos postos (chão achado por raio), cor por fase, vida infinita
- [x] 7.5 `GuardianService`: loop de perseguição (alvo mais próximo na fase, volta ao posto)
- [x] 7.6 `GuardianService`: captura (pergaminho volta + arremesso + aviso + cooldown)
- [x] 7.7 `HudController` (cliente): mensagens do `Notify`
- [x] 7.8 `luau-lsp` strict sem erros; `CLAUDE.md`; commit
