# Decisões pendentes e escolhas feitas sem confirmação

Pontos em que foi preciso escolher sem perguntar (itens 7 a 12). Sempre foi escolhida a opção mais segura e simples. Revise e mude se não concordar.

## Item 7 — Guardiões

- **Arremesso por `LinearVelocity` criado pelo servidor.** O personagem é simulado pelo cliente. O constraint replica e o cliente aplica o empurrão, que é a forma usual de knockback vindo do servidor. **Precisa ser conferido no Studio.** Se o arremesso não acontecer, a alternativa é tomar a posse de rede por um instante (`SetNetworkOwner(nil)`), aplicar a velocidade e devolver.
- **Aparência do guardião:** NPC gerado por `CreateHumanoidModelFromDescription` com cor sólida vermelho-escura. Não usa nenhum asset externo.
- **Posto:** fica no centro do chão de cada `PhaseN`. Se o chão da fase tiver um buraco bem no centro, a fase fica sem guardião (com `warn`).

## Item 8 — Esteira

- **"Correr" = estar em cima da esteira rolante.** A esteira empurra na velocidade do dono, então ninguém fica em cima dela parado. Assim o servidor não depende de nada vindo do cliente. Não ficou incluída uma checagem extra de `MoveDirection`.
- **Esteira criada quando falta marcador:** fica na borda +Z da área do ringue. Em ringues pequenos ou com decoração nessa borda, ela pode ficar em cima de alguma coisa. O ideal é colocar um marcador `Treadmill` à mão.
- **O Speed não é zerado no rebirth.** O pedido listava só dinheiro, guerreiros e upgrades.

## Item 9 — Roubo

- **"Se for pego" foi interpretado como:** o dono encostar no ladrão (a até `CatchDistance`) **ou** um guardião pegar o ladrão dentro de uma fase.
- **Dono sai no meio do roubo:** o roubo é cancelado e o item fica com o dono. Transferir o item para o ladrão exigiria escrever nos dados de um jogador offline.
- **Enquanto está sendo roubado,** o slot do dono não rende e fica invisível. A chocagem continua correndo.

## Item 10 — Upgrades

- **A loja só vende dentro do próprio ringue,** porque o pedido falava em "loja na base". O servidor confere isso de novo em cada compra.

## Item 11 — Rebirth

- **O rebirth tira o saldo inteiro,** não só o custo. É o comportamento mais comum desse tipo de jogo.
- **Exibição do dinheiro:** para o `Money` do leaderstats virar `StringValue`, foi preciso mudar a exibição no `CurrencyService`. A regra dizia "só adicione chaves ao template", mas essa mudança era pedida pelo próprio item 11 e não mexe no dado salvo.

## Item 12 — Monetização

- **Não existe "salvar agora" no `PlayerDataService`,** e a regra era só acrescentar chaves ao template dele. Por isso a compra de Developer Product é entregue e o `PurchaseId` é marcado na memória. Os dois são salvos no próximo autosave (60 s) ou na saída.
  - **Risco:** se o servidor cair nesse intervalo, o jogador perde a compra. Ela **nunca** é entregue duas vezes.
  - **Correção recomendada:** acrescentar um `SaveNow(player)` ao `PlayerDataService` e chamá-lo antes de responder `PurchaseGranted`.
- **"Pular chocagem"** termina **todas** as chocagens em andamento. O servidor só abre a compra se houver alguma chocando. Se a situação mudar entre abrir a compra e o recibo chegar, a compra é entregue mesmo assim (com `warn`), porque recibo pago não pode ser recusado.
- **Valores provisórios:** o Pacote de dinheiro dá $ 50K fixos. Os IDs dos 5 itens estão em 0 (placeholder) e precisam ser trocados pelos reais.

## Gerais

- Nada foi testado no Studio. A validação foi `luau-compile` + `luau-lsp analyze` em modo strict, com as definições do Roblox.
- **`MaxPlayers = 5`** precisa ser configurado à mão no Studio (*Game Settings → Places*).

## Totens e guardiões do mapa

- **Raridade pela cor, não por `Highlight`.** As peças do `TotemTemplate` com o atributo `RarityTint = true` são pintadas, e todo totem ganha uma `PointLight` na cor da raridade. O Roblox só desenha ~31 `Highlight` ao mesmo tempo, e o jogo pode ter 60 totens nas fases e até 70 nas bases.
- **Carregado nas costas** por padrão (`Config/Totems.CarryMount = "Back"`; `"Head"` põe acima da cabeça), com `CarryHeight` de altura.
- **Totens no chão não giram mais.** Um totem em pé girando fica estranho.
- **Scripts dos modelos são removidos:** dos clones de totem e dos NPCs guardiões, com `warn` listando os nomes. Nos guardiões, a remoção acontece quando o servidor inicia, mas scripts no Workspace já rodaram ao abrir o jogo. Por isso o `warn` pede para apagá-los no Studio.
- **Animação dos guardiões:** só parado e corrida (as padrão do R15), tocadas pelo servidor. Não há animação de pulo, queda nem de "andar devagar". Na volta ao posto ele também usa a corrida, com a velocidade das pernas acompanhando a real.
- **Colocar clicando no chão:** o jogador precisa estar dentro do próprio ringue, e o ponto clicado também. Não há checagem extra de alcance: os dois estando na base já basta. A altura do clique só serve para validar; o slot salva só `OffsetX/Z`.
- **Aceleração:** a perseguição começa em 60% da velocidade máxima do guardião e chega nela em 3 s.
- **"Defender os totens"** foi interpretado como: ficar no posto (que você escolhe no Studio, perto dos totens), vigiar com alerta e perseguir só quem pegar um totem. Ninguém é atacado sem carregar totem.
- **Giro do guardião** (virar para quem se aproxima) é feito escrevendo o `CFrame` do `HumanoidRootPart` aos poucos. Pode ficar um pouco "travado"; se incomodar, dá para trocar por `AlignOrientation`.
- **Fases tiradas dos chãos:** sem `Map.Phases`, o `BaseService` usa os `Map.Corredor.Chao_FaseN` como fases. Cada volume vai de 5 studs abaixo até 40 acima do chão, e as sobreposições entre vizinhos são divididas no meio. Uma `Map.Phases` feita à mão continua tendo prioridade.
- **Fase do guardião pela posição:** vale a fase onde o NPC está, não o número do nome. No mapa atual, o `Guardian2` está na fase 1 e o `Guardian1` na fase 2; funciona, mas gera `warn` até serem renomeados.
- **Estátua vira rig:** os NPCs do mapa são estátuas R6 (sem `HumanoidRootPart`, peças soltas ou soldadas). O servidor monta o rig R6 padrão na pose atual. Um rig feito no *Rig Builder* continua sendo o ideal (proporções padrão, animações mais naturais).
- **Letreiros dos NPCs removidos** (ex.: "Krillin"); o nome exibido é "Guardião da fase N".
- **Totem no chão com 6 studs** (`Config/Totems.GroundHeight`): o `TotemTemplate` atual tem 28 studs de altura.

## Níveis de velocidade e totem caído

- **Nível × velocidade real:** os números pedidos (900 até 20B) são níveis. A velocidade real vem de uma escala logarítmica igual para jogador e guardião (`Config/Speed.RealSpeed`), entre 16 e ~276 studs/s. A física do Roblox não aguenta milhões de studs/s.
- **Treino em porcentagem:** 1% do nível por segundo, mínimo +1. Estimativa até 20B: ~40 min sem upgrades, ~12 min com Treino no máximo, ~6 min com o Game Pass. Os valores ficam em `Config/Speed`.
- **Dados antigos:** o `Speed` salvo continua o mesmo número, agora lido como nível. Quem tinha 100 pontos (andava a 66) passa a andar a ~45. Não precisa de migração (a chave e o tipo são os mesmos), mas quem já jogou fica um pouco mais lento até treinar de novo.
- **Totem caído:** qualquer jogador pode pegar (disputa), depois de 1,5 s. Sem busca em 30 s, volta sozinho.
- **Animações de pegar/segurar:** as padrão de ferramenta do Roblox (golpe e segurar). Não existe animação padrão de "pegar do chão"; dá para trocar os IDs em `Config/Guardians.Animations`.
- **Guardião descansando:** sentado no chão com a animação padrão de sentar e o corpo baixado até o chão (a altura é calculada pela perna; `RestExtraDrop` ajusta). Ele só acorda quando alguém pega um totem da fase dele. Jogador sem totem pode chegar perto à vontade.
- **Regra de velocidade:** com velocidade menor que a do guardião, ele corre 2× mais rápido que você (`ChaseAdvantage`) e persegue até o começo da fase 1. Com igual ou maior, você escapa. Se ainda der para escapar com velocidade menor (o tempo para acordar, `WakeDelay`, dá vantagem), é só subir o `ChaseAdvantage`.
- **Caminho do guardião:** ele corre em linha reta até o alvo. Pedras ou paredes no meio do corredor (ex.: fase 6) podem prendê-lo.
