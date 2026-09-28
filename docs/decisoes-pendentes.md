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
- **Aceleração sem mudar o balanceamento:** `Speeds[N]` virou a velocidade máxima (a mesma de antes). A perseguição começa em 60% e chega nela em 3 s. Acelerar acima dos valores antigos deixaria a fase 10 mais rápida que o teto do jogador (350).
- **"Defender os totens"** foi interpretado como: ficar no posto (que você escolhe no Studio, perto dos totens), vigiar com alerta e perseguir só quem pegar um totem. Ninguém é atacado sem carregar totem.
- **Giro do guardião** (virar para quem se aproxima) é feito escrevendo o `CFrame` do `HumanoidRootPart` aos poucos. Pode ficar um pouco "travado"; se incomodar, dá para trocar por `AlignOrientation`.
