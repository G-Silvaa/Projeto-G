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
