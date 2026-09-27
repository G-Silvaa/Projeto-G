# Relatório — itens 6 a 12

Tudo feito em sequência, sem push. Cada item tem o plano em `docs/plans/itemN.md`. As escolhas feitas sem confirmação estão em `docs/decisoes-pendentes.md`.

**Validação:** depois de cada item, `luau-compile` em todos os arquivos e `luau-lsp analyze` em modo strict, com as definições do Roblox e o sourcemap do Rojo, **sem erros nem avisos**.

**Nada foi testado no Studio.** O roteiro abaixo serve para isso.

## Commits

| Item | Commit | Resumo |
|---|---|---|
| 6 | `ed44813` | Coleta de pergaminhos nas fases |
| 7 | `8447849` + `acbb63c` | Guardiões das fases (+ força finita no arremesso) |
| 8 | `5d969ec` | Esteira de velocidade |
| 9 | `fc697df` | Roubo entre jogadores |
| 10 | `1a62230` | Upgrades |
| 11 | `045e834` | Rebirth e dinheiro formatado |
| 12 | `db0d115` | Monetização |

## O que foi feito

### Item 6 — Coleta de pergaminhos (`ScrollService`, `ScrollController`, `Config/Phases`)
- **Spawn:** pergaminhos aparecem no chão de `Phase1..10`. Cada fase tem pesos de raridade, um máximo e um intervalo de spawn; começa cheia e repõe 1 por intervalo.
- **Evento lendário:** a cada 5 min aparece um pergaminho lendário+ nas fases 8–10, com aviso no chat.
- **Coleta:** encostando. O servidor confere a distância real. Só dá para carregar 1 por vez, e ele aparece acima da cabeça.
- **Perda:** morrer, cair na KillZone ou sair faz o pergaminho voltar para a fase de origem.
- **Colocar:** o botão "Colocar pergaminho" aparece dentro do próprio ringue e chama o remote `PlaceScroll` (sem argumentos, com rate limit). As mensagens de erro vêm em português.

### Item 7 — Guardiões (`GuardianService`, `Config/Guardians`)
- **Quem são:** um NPC R15 por fase, parado no centro do chão dela.
- **Perseguição:** só vai atrás de quem carrega pergaminho dentro da fase dele, e volta ao posto quando o alvo some. A velocidade vai de 14 (fase 1) a 250 (fase 10). O movimento é em linha reta (`MoveTo`), atualizado a cada 0,15 s.
- **Captura (checada no servidor):** o pergaminho volta para a fase, o jogador é arremessado sem dano e recebe um aviso. Depois disso o guardião espera um tempo antes de perseguir de novo.
- **HUD de mensagens:** novo remote `Notify` e `HudController`.

### Item 8 — Esteira (`SpeedService`, `Config/Speed`)
- **A esteira:** uma por base. Usa o marcador `Treadmill` se ele existir no ringue; senão, o servidor cria uma na borda.
- **Como treina:** é uma esteira rolante que empurra na velocidade do dono. Só consegue ficar em cima quem corre contra ela, e estar em cima é o que conta como treino. O servidor não confia em nada do cliente.
- **Speed:** salvo no `PlayerData`. `WalkSpeed = 16 + 0,5 × Speed` (teto 350). Speed aparece no leaderstats e no HUD.
- **Modo de teste do Studio** (WalkSpeed 100): agora é aplicado pelo `SpeedService`, e o valor de teste nunca vira Speed salvo. O `StudioTestService` foi removido.

### Item 9 — Roubo (`StealService`, `Config/Steal`)
- **Roubar:** cada slot tem um prompt "Roubar" (segurar 1 s), escondido na tela do próprio dono. O servidor valida posse, distância, proteção de 30 s após colocar, cooldown de 20 s, rate limit e se o ladrão já carrega algo.
- **O item só sai dos dados do dono na entrega.** Até lá, o slot fica travado em memória: invisível e sem render.
  - Entregou no próprio ringue: o item passa para o ladrão.
  - O ladrão morreu, o dono ou um guardião o pegou, ou ele saiu: o item volta.
  - O dono saiu no meio: o roubo é cancelado.
- **Avisos:** o dono é avisado no início, na entrega e na devolução.
- **Carga genérica no `ScrollService`:** `CarryItem` com `onPlace`/`onLost`.

### Item 10 — Upgrades (`UpgradeService`, `ShopController`, `Config/Upgrades`)
- **Os upgrades:** Mais espaço (+1 slot por nível, até 6), Renda (+10% por nível) e Treino (+25% por nível). Preço exponencial.
- **Loja:** botão "Loja" que só aparece dentro do próprio ringue. O remote `BuyUpgrade` é validado no servidor: tipo, Id, rate limit, estar na base, nível máximo e dinheiro.
- **Efeitos:** registrados no `WarriorService` e no `SpeedService`, sem dependência circular.
- **`Format.number`:** 1.5K, 2.3M, 4.1B. Foi testado com o interpretador Luau.

### Item 11 — Rebirth (`RebirthService`, `Config/Rebirth`)
- **Custo:** 1M × 3^rebirths.
- **O que zera e o que dá:** zera Money, guerreiros e upgrades e dá renda multiplicada por `1 + 0,5 × rebirths`. O Speed não é zerado.
- **Remote `Rebirth`** validado no servidor. O botão no HUD pede confirmação em dois cliques.
- **Money no leaderstats:** virou `StringValue` formatado, que resolve o limite do `IntValue`. O HUD mostra Money, Velocidade e Rebirths.

### Item 12 — Monetização (`MonetizationService`, `StoreController`, `Config/Monetization`)
- **Os itens:** Game Passes Renda x2, Treino x2 e +2 espaços; Developer Products Pular chocagem e Pacote de dinheiro ($ 50K).
- **IDs = 0:** são placeholders. O item fica desligado e aparece como "Em breve", sem quebrar nada.
- **`ProcessReceipt` idempotente:** usa `ProcessedReceipts` no `PlayerData`. Jogador ausente ou dados não carregados respondem `NotProcessedYet`.
- **Abrir a compra:** o remote `PromptPurchase` é validado no servidor antes, inclusive "Pular chocagem" só com algum pergaminho chocando.

## Roteiro de teste no Studio

Pré-requisitos:
- Place publicado, com *Enable Studio Access to API Services* ligado.
- `Workspace.Map` com `Bases/Base1..5`, `Phases/Phase1..10`, `Lobby` e `KillZone`.
- *Max Players = 5*.

Para testar mais rápido, dá para baixar temporariamente os tempos nas configs (sem commitar), por exemplo `LegendaryEvent.IntervalSeconds = 20`.

### Item 6
1. Dê Play e ande pelas fases.
   **Esperado:** pergaminhos coloridos girando em todas as 10 fases, com o nome da raridade.
2. Encoste num pergaminho.
   **Esperado:** ele aparece acima da sua cabeça. Encostar em outro não faz nada.
3. Volte ao seu ringue.
   **Esperado:** aparece o botão "Colocar pergaminho". Ao apertar, sai "Colocado na sua base!" e surge uma placa chocando.
4. Carregando, tente colocar encostado num slot existente.
   **Esperado:** "Muito perto de outro guerreiro".
5. Pegue um pergaminho e pule na KillZone.
   **Esperado:** ele volta para o chão da fase de origem e você renasce no ringue.
6. Com `IntervalSeconds = 20`:
   **Esperado:** aviso no chat "Um pergaminho X apareceu na fase N!".

### Item 7
1. Dê Play.
   **Esperado:** um NPC vermelho-escuro parado no centro de cada fase.
2. Passe perto de um guardião **sem** pergaminho.
   **Esperado:** ele não se mexe.
3. Pegue um pergaminho na fase 1 e corra.
   **Esperado:** o guardião persegue. Se alcançar: você é arremessado, o pergaminho volta para a fase e aparece "O guardião te pegou!".
4. Saia da fase carregando.
   **Esperado:** o guardião volta ao posto.
5. Na fase 10, sem treino.
   **Esperado:** o guardião (250) alcança quase na hora.
   - O modo de teste do Studio deixa o WalkSpeed em pelo menos 100. Para testar de verdade, ponha `Enabled = false` em `Config/StudioTest`.
6. **Confira em especial o arremesso.** Se ele não acontecer, veja `docs/decisoes-pendentes.md`.

### Item 8
1. Com `StudioTest.Enabled = false`, dê Play.
   **Esperado:** Velocidade 0 no HUD e no leaderstats, e WalkSpeed 16.
2. Suba na esteira (a Part escura na borda do ringue) e fique parado.
   **Esperado:** ela te leva para fora.
3. Corra contra a esteira.
   **Esperado:** a Velocidade sobe cerca de 1 ponto por segundo e você fica mais rápido.
4. Saia e entre de novo.
   **Esperado:** a Velocidade continua salva.
5. Com `StudioTest.Enabled = true`:
   **Esperado:** WalkSpeed de pelo menos 100, e o Speed salvo não muda por causa disso.

### Item 9 (use *Test → Clients and Servers* com 2 jogadores, A e B)
1. A coloca um pergaminho. Imediatamente, B chega perto dele.
   **Esperado:** o prompt "Roubar" aparece para B, mas não para A. Segurando antes de 30 s, B vê "Protegido por mais X s".
2. Depois de 30 s, B rouba.
   **Esperado:** o slot some do ringue de A. B carrega o item e A recebe "B está roubando seu ...!".
3. A encosta em B.
   **Esperado:** o item volta para o ringue de A e B recebe "O dono te pegou!".
4. Repita e deixe B chegar ao ringue dele e apertar "Colocar".
   **Esperado:** o item aparece no ringue de B (mesma raridade/guerreiro), some de A de vez, e A recebe "B roubou seu ...!".
5. B tenta roubar de novo logo em seguida.
   **Esperado:** "Espere X s para roubar de novo".

### Item 10
1. Dentro do seu ringue.
   **Esperado:** aparece o botão "Loja". Fora do ringue, ele some.
2. Abra a loja sem dinheiro e aperte "Comprar".
   **Esperado:** "Dinheiro insuficiente".
3. Com dinheiro (espere a renda subir), compre Mais espaço.
   **Esperado:** "Mais espaço nível 1!", o preço sobe e agora cabem 7 slots.
4. Compre Renda.
   **Esperado:** o dinheiro por segundo sobe cerca de 10%.
5. Compre Treino.
   **Esperado:** a esteira dá mais pontos por segundo.

### Item 11
1. HUD.
   **Esperado:** Money formatado ("1.5K"), Velocidade, Rebirths e o botão "Rebirth ($ 1M)".
2. Aperte com menos de 1M, clicando duas vezes.
   **Esperado:** "Precisa de $ 1M para o rebirth".
3. Com ≥ 1M (para testar, baixe `BaseCost` em `Config/Rebirth`), aperte duas vezes.
   **Esperado:** Money 0, guerreiros e upgrades zerados, Rebirths 1, "Renda x1.5", e o próximo custo fica 3×.
4. Leaderstats.
   **Esperado:** Money aparece como texto formatado.

### Item 12
1. Abra "Robux".
   **Esperado:** todos os itens mostram "Em breve" (IDs 0), e clicar mostra "Em breve".
2. Ponha um ID real de Game Pass em `Config/Monetization` e teste a compra no Studio (compra de teste).
   **Esperado:** "Renda x2 ativado!" e o botão vira "Comprado".
3. Ponha um ID real de Developer Product (Pacote de dinheiro) e compre.
   **Esperado:** "+$ 50K" uma única vez, mesmo se o Roblox repetir o recibo.
4. "Pular chocagem" sem nada chocando.
   **Esperado:** "Nenhum pergaminho chocando". Com algo chocando, a chocagem termina logo após a compra.

## Riscos

- **Nada rodou no Studio.** A análise estática não pega comportamento de física nem de rede. Os pontos mais sensíveis são:
  - o arremesso dos guardiões (`LinearVelocity` no personagem, que é simulado pelo cliente);
  - a esteira rolante (`AssemblyLinearVelocity` em Part ancorada);
  - o guardião R15 criado por `CreateHumanoidModelFromDescription`.
- **Compras de Developer Product:** podem se perder (nunca duplicar) se o servidor cair antes do autosave. A correção é um `SaveNow` no `PlayerDataService`.
- **Esteira criada automaticamente:** fica na borda do ringue e pode ficar mal posicionada em ringues com decoração. O ideal é um marcador `Treadmill`.
- **Guardiões muito rápidos:** nas fases finais, o raio de captura cresce com a velocidade. Pode parecer "de longe" demais ou de menos; ajuste em `Config/Guardians`.
- **Chat antigo (Legacy):** o aviso do evento lendário usa `TextChatService` e não aparece nesse modo.

## O que ficou de fora

- **Do conceito:** mutações (Despertado, Aura Dourada, Sombrio), renda offline e os nomes das fases 4 a 9.
- **Visual:** guerreiros e guardiões são simples (placa colorida e NPC de cor sólida). Não há animação especial, efeito, som nem modelo por guerreiro.
- **IDs de monetização:** são placeholders (0) e precisam dos IDs reais do Creator Dashboard.
- **`SaveNow` para compras:** não foi feito, por causa da regra de só acrescentar chaves ao `PlayerDataService`.
- **`MaxPlayers = 5`:** é configuração do place, não do código.
- **Speed no rebirth:** não é zerado, porque não estava no pedido.
- **Testes automatizados:** não há. A validação foi a análise estática em modo strict.
