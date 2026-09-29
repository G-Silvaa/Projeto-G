# Projeto G

Jogo multiplayer no Roblox (Luau) de coleção e roubo de guerreiros. Cada jogador tem uma base, coleta guerreiros que geram dinheiro, pode roubar guerreiros de outros jogadores, comprar upgrades e fazer rebirth.

## Ferramentas

- **Rojo 7.7.0** (via Rokit): sincroniza `src/` com o Roblox Studio. O `rojo serve` roda no Windows.
- **Roblox Studio**: execução, testes e edição visual do mapa.
- **Claude Code**: trabalha nos arquivos pelo WSL em `/mnt/c/Roblox/Projeto G`.
- **Git**: branch `main`.

Nunca edite scripts direto no Studio. A fonte da verdade é `src/`. O mapa (Workspace) é editado no Studio e **não** é sincronizado pelo Rojo.

## Conceito do jogo

Tema anime, com personagens 100% originais — nunca usar nomes, visuais ou elementos reconhecíveis de animes reais. Guerreiros são inspirados em arquétipos (ninja, samurai, monge, etc.), nunca cópias.

Loop principal:

1. O jogador treina velocidade numa esteira na própria base.
2. Corre pelo corredor compartilhado, dividido em 10 fases, e pega um pergaminho no chão. Só dá para carregar 1 pergaminho por vez. **Para o jogador, o pergaminho se chama "totem"** (todos os textos da tela dizem "totem"); no código e nos dados continua `Scroll`.
3. Cada fase tem um guardião que persegue quem está carregando pergaminho. Se alcançar, arremessa o jogador para longe, e o pergaminho volta para a fase.
4. Os guardiões ficam muito mais rápidos a cada fase: só com velocidade treinada dá para escapar nas fases finais.
5. Pergaminho entregue na base "choca" por um tempo que depende da raridade (Comum é curto, Secreto é muito longo). O tempo corre mesmo com o jogador offline, então o jogo guarda o horário de início, não um contador.
6. Quando termina de chocar, nasce um guerreiro que fica na base gerando dinheiro por segundo.

Outras regras:

- Há muitos guerreiros diferentes em cada raridade.
- Fases mais longe têm pergaminhos de raridade maior. Pergaminhos lendários (e acima) aparecem de vez em quando e geram disputa entre os jogadores.
- Jogadores podem roubar guerreiros e pergaminhos de outras bases.
- **Raridades** (do mais comum ao mais raro): Comum, Raro, Épico, Lendário, Mítico, Secreto.
- **Mutações**: multiplicador aplicado a um guerreiro (ex.: Despertado, Aura Dourada, Sombrio).
- **Fases (mundos)**: 10 no total. Nomes definidos até agora: 1) Vila Ninja, 2) Dojo da Montanha, 3) Cidade Neon, 10) Mundo Espiritual (a final). Fases 4 a 9 ainda sem nome.

## Mapeamento Rojo (`default.project.json`)

| Pasta local   | Destino no Studio                                |
|---------------|--------------------------------------------------|
| `src/server`  | `ServerScriptService.Server`                     |
| `src/shared`  | `ReplicatedStorage.Shared`                       |
| `src/client`  | `StarterPlayer.StarterPlayerScripts.Client`      |
| `src/gui`     | `StarterGui.Gui`                                 |

Se criar uma nova pasta raiz fora dessas, atualize o `default.project.json`.

Exceção: `tools/` fica fora do Rojo de propósito. São scripts para colar à mão na Barra de comandos do Studio (ex.: `tools/BuildMap.luau`), não rodam no jogo. Não adicione `tools/` ao `default.project.json`.

## Convenções de arquivos

- `Nome.server.luau` → Script (servidor)
- `Nome.client.luau` → LocalScript (cliente)
- `Nome.luau` → ModuleScript
- `init.luau` dentro de uma pasta transforma a pasta no próprio ModuleScript
- Serviços em PascalCase com sufixo `Service` (ex.: `CurrencyService`)
- Controladores do cliente com sufixo `Controller` (ex.: `UIController`)
- Configurações estáticas em `src/shared/Config/` (ex.: `Warriors.luau`, `Economy.luau`)

## Arquitetura

- **Um único Script de entrada por lado**: `src/server/Main.server.luau` e `src/client/Main.client.luau` carregam e inicializam os módulos. Os demais arquivos são ModuleScripts.
- Serviços do servidor ficam em `src/server/Services/`.
- Controladores do cliente ficam em `src/client/Controllers/`. Peças de interface compartilhadas ficam em `src/client/UI/` (ModuleScripts que o `Main.client` não carrega; os controllers dão `require`).
- RemoteEvents e RemoteFunctions são criados pelo servidor em `ReplicatedStorage.Remotes` na inicialização, com nomes centralizados em `src/shared/Remotes.luau`.
- Use `--!strict` no topo de todo arquivo novo e tipe as funções públicas.

## Regras de segurança (obrigatórias)

- **O servidor é a autoridade.** Dinheiro, inventário, guerreiros, roubos e compras são decididos só no servidor.
- **Nunca confie no cliente.** Todo remote valida tipo, faixa e permissão dos argumentos. O cliente pede ("quero comprar X"); o servidor decide.
- Aplique rate limit nos remotes que alteram estado.
- Checagens de distância e posição (ex.: roubo) são feitas no servidor.
- Nada de valores sensíveis em atributos ou Values editáveis pelo cliente.

## Dados (DataStore)

- Um único `PlayerDataService` é dono dos dados do jogador. Outros serviços leem e escrevem por ele, nunca direto no DataStore.
- Salvar ao sair, em `BindToClose` e em autosave periódico.
- Tratar falhas com retry e não sobrescrever dados se o carregamento falhou.
- Versionar o formato dos dados (`DataVersion`) para migrações futuras.
- Template em `src/server/Services/PlayerDataService/Template.luau`. Chave nova no nível de cima é preenchida sozinha nos dados antigos (chaves aninhadas não). Renomear, remover ou mudar o tipo de uma chave exige subir `DataVersion` e adicionar `Migrations[n]` (n → n+1) no `init.luau`.
- No Studio o DataStore é `PlayerData_Studio`; no jogo publicado, `PlayerData`. Para funcionar no Studio, o place precisa estar publicado e com *Game Settings → Security → Enable Studio Access to API Services* ativado.

## Mapa (`Workspace.Map`)

O mapa é montado à mão no Studio (modelos da Loja) e fica salvo no place, não no git. O código não gera geometria: o `BaseService` só lê estes marcadores pelo nome quando o servidor inicia.

```
Workspace.Map
├── Bases/      Base1..Base5: o ringue inteiro (Model) ou uma Part no centro dele (colocados à mão)
├── Phases/     Phase1..PhaseN: Parts invisíveis cobrindo a área de cada fase
├── Guardians/  Guardian1..GuardianN: NPCs (R15 com Humanoid) montados à mão; N = fase
├── Lobby       Part (piso visível) onde nasce quem não tem base; precisa dar acesso ao corredor
├── KillZone    Part invisível abaixo de tudo; quem encosta volta pra própria base (ou pro lobby)
└── Corredor/   Chao_Fase1..N: chão de cada fase (vira o volume da fase quando não há Phases/)
```

- 5 bases no máximo (`BASE_COUNT` no topo do `BaseService`), então o servidor deve aceitar no máximo 5 jogadores. Isso se configura no Studio em *Game Settings → Places → Max Players = 5*; não dá para fazer pelo código.
- Marcador de base: `Model` ou `Part`, ancorado.
  - **Model** (o ringue inteiro): o personagem nasce no centro do ringue, em cima do piso. O piso é achado com um raio de cima pra baixo no centro da caixa do modelo, que só enxerga o próprio ringue. Não depende do pivot. Não coloque nada pendurado bem em cima do centro do ringue, senão o raio acerta isso primeiro.
  - **Part**: o personagem nasce em cima dela. A área da Part também é a área onde dá pra colocar pergaminhos, então ela precisa cobrir o piso inteiro do ringue (`Transparency = 1`, `CanCollide = false`).
  - Sem placa nem nome em cima das bases. A altura de nascimento é `SPAWN_HEIGHT` no topo do `BaseService`.
- Não precisa colocar `SpawnLocation` no mapa: o `BaseService` cria os pontos de nascimento sozinho. O do template pode ser apagado.
- **Volumes das fases:** se `Map.Phases` não existir (ou estiver vazia), o `BaseService` monta os volumes a partir de `Map.Corredor.Chao_FaseN`. Cada volume cobre o chão, de 5 studs abaixo até 40 acima (`DERIVED_PHASE_BELOW`/`ABOVE`), e onde dois chãos vizinhos se sobrepõem a divisa fica no meio. Essas Parts não vão para o Workspace e vêm com um `warn` informativo. `Map.Phases` feita à mão tem prioridade.
- **Guardiões:** `Model` com `Humanoid` dentro de `Map.Guardians`. **A fase dele é a do volume onde ele está**; o `N` do nome `GuardianN` só vale se ele estiver fora de todas as fases. Nome que não bate gera `warn`. Dois guardiões na mesma fase: vale o primeiro. O ideal é um rig de verdade (R15 ou R6, com `HumanoidRootPart` e `Motor6D`s). Uma **estátua R6** (Torso, Head, braços e pernas, soltos ou soldados, sem `HumanoidRootPart`) é montada pelo servidor: ele cria o `HumanoidRootPart` e os `Motor6D`s do R6 padrão na pose atual e prende chapéu, barba etc. na cabeça ou no tronco, sem colisão. Letreiros (`BillboardGui`) que vierem no NPC são removidos com `warn`; o nome vira "Guardião da fase N". A posição e a direção em que ele está no Studio viram o posto, e os totens da fase nascem em volta dele (até 25 studs). Coloque-o num lugar aberto do chão da fase. As peças podem ficar ancoradas no Studio; o servidor desancora ao iniciar. Fase sem guardião fica sem (com `warn`). Scripts dentro do NPC são removidos ao iniciar, com `warn` listando os nomes. Como scripts no Workspace rodam assim que o jogo abre, apague-os também no Studio. As animações vêm do servidor.
- **Totens** (fora do Workspace, em `ServerStorage`): `TotemTemplate` (Model) é o visual padrão; as peças com o atributo `RarityTint = true` ficam na cor da raridade (sem nenhuma marcada, pinta a peça principal). Em peça com `SpecialMesh` (acessório), a cor vai no `VertexColor`, porque a textura ignora a cor da peça. `Totem_<Rarity>` (ex.: `Totem_Legendary`) é opcional e é usado como está. No chão e na base o totem é escalado para `Config/Totems.GroundHeight` (6 studs; 0 = tamanho do template). Sem modelo, fica o visual antigo (cilindro neon) com `warn`. Scripts dos modelos são removidos dos clones.
- O número de fases é o maior `PhaseN` encontrado. `Phase1` é a mais perto das bases, e os volumes não devem se sobrepor.
- Marcador faltando ou do tipo errado gera um `warn` específico no Output quando o servidor inicia. O resto continua funcionando.
- Esqueleto inicial: `tools/BuildMap.luau`. Ele cria `Corridor` (4 biomas), `Phases/Phase1..4`, `Lobby`, `KillZone` e a pasta `Bases` vazia, e remove o `Baseplate` e o `SpawnLocation` do template.
  - Antes de rodar, ajuste as medidas no topo do script, principalmente `CORRIDOR_START` e `CORRIDOR_YAW`: a boca do corredor fica no meio entre os dois grupos de ringues.
  - Com o jogo parado, cole o script na Barra de comandos e salve o place.
  - Se `Corridor`, `Phases`, `Lobby` ou `KillZone` já existirem em `Workspace.Map`, o script avisa e não faz nada.

## Sistemas planejados (em ordem)

1. [x] Estrutura base (Main server/client, Remotes, Config)
2. [x] PlayerData + DataStore
3. [x] Currency (dinheiro)
4. [x] Bases dos jogadores
5. [x] Guerreiros e pergaminhos (definições, raridade, choca, renda)
6. [x] Coleta de pergaminhos nas fases
7. [x] Guardiões das fases
8. [x] Esteira de velocidade
9. [x] Roubo entre jogadores
10. [x] Upgrades
11. [x] Rebirth
12. [x] Monetização
13. [x] Rastro de velocidade
14. [ ] Esteira com níveis (compra com dinheiro; substitui o upgrade "Treino"; não zera no rebirth)

## Forma de trabalhar

- **Um sistema por vez.** Não implemente sistemas além do pedido na tarefa.
- Antes de codar algo grande, proponha a estrutura e espere aprovação.
- Ao terminar uma tarefa: diga como testar no Studio e sugira a mensagem de commit.
- Mantenha a checklist acima atualizada ao concluir um sistema.
- Prefira código simples e legível a abstrações genéricas.
- Não apague `.gitkeep` das pastas vazias.

## Estado atual

- Setup do Rojo funcionando e testado.
- Estrutura base pronta:
  - `Main.server.luau` chama `Remotes.setup()`, carrega os ModuleScripts de `Services/` (outros tipos de filho são ignorados), chama `Init()` em ordem alfabética e depois `Start()` em `task.spawn`. Os dois métodos são opcionais e chamados com `:`. Erro em um serviço gera `warn` e não derruba os outros; se o `Init` falhar, o `Start` daquele serviço não roda.
  - `Main.client.luau` faz o mesmo com `Controllers/`.
  - `src/shared/Remotes.luau`: nomes em `Remotes.Events` / `Remotes.Functions` (chave = valor); `getEvent(name)` / `getFunction(name)` nos dois lados. Hoje: `Functions.PlaceScroll(position)` (ver `ScrollService`), `Functions.PromptPurchase` (ver `MonetizationService`), `Functions.Rebirth` (ver `RebirthService`), `Functions.BuyUpgrade` (ver `UpgradeService`), `Events.Announcement` (ver `ScrollService`) e `Events.Notify` (mensagem curta do servidor para um jogador, mostrada pelo `HudController`).
  - `src/shared/Config/init.luau` contém só a versão (`0.0.1`).
  - `src/shared/Format.luau`: `Format.number(n)` → "950", "1.5K", "2.3M", "4.1B"... (servidor e cliente).
- `PlayerDataService` (`src/server/Services/PlayerDataService/`) pronto:
  - Uma chave por jogador (`Player_<UserId>`) com `{ Data, Lock }`. Session lock via `UpdateAsync`: o lock expira em 180 s sem renovação; um servidor só grava se o lock for dele e, se não for, kicka o jogador.
  - Load com 5 tentativas (5 s entre elas); se falhar, kicka e não salva. Autosave a cada 60 s, save + liberação do lock ao sair e no `BindToClose`.
  - Template atual: `DataVersion = 1`, `JoinCount` (incrementado a cada load), `Money`, `Slots` (ver `WarriorService`), `Speed` (ver `SpeedService`), `Upgrades` (ver `UpgradeService`), `Rebirths` (ver `RebirthService`), `ProcessedReceipts` (ver `MonetizationService`).
  - API (outros serviços usam `require(script.Parent.PlayerDataService)`): `IsLoaded(player)`, `Get(player, key)` (tabelas vêm como cópia), `Set(player, key, value)`, `Update(player, key, fn)` (o `fn` não pode yieldar), `OnPlayerLoaded(callback)`. `Set`/`Update` retornam `false` se o jogador não estiver carregado e dão erro se a chave não existir no template, se for `DataVersion` ou se o tipo for diferente.
- `CurrencyService` (`src/server/Services/CurrencyService.luau`) pronto:
  - `Money` (inteiro, `>= 0`) no template do `PlayerDataService`; chave nova de nível de cima, preenchida sozinha nos dados antigos, sem precisar de migração.
  - API: `GetMoney(player)` (`number?`), `AddMoney(player, amount)`, `RemoveMoney(player, amount)` (`boolean`, `false` se saldo insuficiente ou jogador não carregado). `amount` negativo, não-inteiro, NaN ou infinito faz `error()` — é bug de quem chamou, não estado de jogo.
  - Saldo mostrado no `leaderstats` como **`StringValue` formatado** (`Format.number`: 1.5K, 2.3M, 4.1B), porque um `IntValue` estoura em ~2,1 bilhões. O atributo numérico `Money` no `Player` alimenta o HUD. O dado salvo continua sendo o número.
  - Sem remotes: nada neste sistema é iniciado pelo cliente ainda.
- `BaseService` (`src/server/Services/BaseService.luau`) pronto. Ele não gera geometria: só lê os marcadores de `Workspace.Map` (ver a seção "Mapa").
  - Cada marcador `Base1..Base5` (quantidade em `BASE_COUNT`, no topo do `BaseService`) pode ser `Model` (o ringue) ou `Part`.
    - Cada base (e o `Lobby`) ganha um ponto de nascimento no piso: um `SpawnLocation` invisível com `Neutral = true` e `CanTouch = false`. `Neutral = true` porque jogador sem time só usa `SpawnLocation` neutro; com `Neutral = false`, o Roblox ignorava o `RespawnLocation` e o jogador nascia fora do ringue. `CanTouch = false` para encostar nele não fazer nada.
  - **`Players.CharacterAutoLoads = false`** (no `Init`, cedo): o próprio `BaseService` cria o personagem (`spawnCharacter`) depois que os dados carregam. Ele define o `RespawnLocation`, chama `LoadCharacterAsync` e teleporta (`PivotTo`) para o ponto da base, ou do lobby se não sobrar base.
    - Com `CharacterAutoLoads = false` o Roblox **não** faz ninguém renascer sozinho. Então o `BaseService` escuta `Humanoid.Died` e chama `spawnCharacter` de novo depois de `Players.RespawnTime`.
    - Sistemas futuros que dependem do `Character` (movimento, combate, etc.) precisam contar com esse atraso e com o caso de o jogador nunca ter base própria.
  - Quem encosta na `KillZone` tem o `Humanoid` morto e renasce no próprio ringue (ou no lobby).
  - `Players.PlayerRemoving` libera a base (dono = `nil`).
  - Marcador faltando ou errado gera `warn` específico no `Init`. Sem `Workspace.Map`, ninguém recebe base, mas todos ainda recebem personagem.
  - API: `GetBase(player)` (índice `1..5` ou `nil`), `GetOwner(baseIndex)` (`Player?`), `GetPhaseAt(position)` (número da fase cujo volume `PhaseN` contém a posição, funcionando com a Part rotacionada, ou `nil`), `GetBaseArea(baseIndex)` (`CFrame?, Vector3?`: centro do piso da base, girado só no eixo vertical como o ringue, e o tamanho da área; Model usa a caixa do modelo, Part usa o tamanho da Part), `GetPhaseCount()` (maior `N` entre os `PhaseN`), `GetPhasePart(index)` (`BasePart?`), `GetBaseCount()`, `GetBaseInstance(index)` (o marcador `BaseN`), `GetGuardian(phase)` (o guardião que está no volume da fase) e `GetGuardianPost(phase)` (`CFrame` do `HumanoidRootPart`, ou do tronco numa estátua, lido no `Init`, antes de o NPC se mexer). Os avisos sobre `Map.Guardians` (nome que não bate, dois na mesma fase, fase sem guardião) saem do `BaseService`.
- `WarriorService` (`src/server/Services/WarriorService.luau`) pronto. Dados em `src/shared/Config/Rarities.luau` (cor, ordem, tempo de choca, faixa de renda) e `src/shared/Config/Warriors.luau` (36 guerreiros: 6 clãs × 6 raridades).
  - Os Ids de raridade (`Common`..`Secret`) e de guerreiro (ex.: `kaseri`) ficam salvos nos dados: não renomeie. `DisplayName` e `Name` podem mudar.
  - `Slots` no `PlayerData`: chave `"1".."N"` → `{ Rarity, StartedAt, OffsetX, OffsetZ, WarriorId?, PlacedAt? }` (`PlacedAt` = quando foi colocado nesta base; usado na proteção contra roubo). `StartedAt` é `os.time()`, então a chocagem continua offline. `OffsetX/Z` é a posição relativa ao centro da base (`GetBaseArea`), então continua certa se o jogador pegar outra base; se a base nova for menor, o slot é trazido pra dentro dela.
  - A cada 1 s, para cada jogador carregado: termina as chocagens vencidas, sorteando um guerreiro da raridade (qualquer clã); soma a renda dos guerreiros e chama `CurrencyService:AddMoney`; atualiza o visual. A renda por segundo fica no atributo `Income` do `Player`, usado só pelo placar. A renda só corre com o dono no jogo.
  - Na inicialização, valida as configs: Ids únicos, raridade existente, renda inteira e dentro da faixa, pelo menos 1 guerreiro por raridade. Se algo falhar, dá erro e o `Start` não roda.
  - API:
    - `AddScroll(player, rarity, position?)`: retorna `(true)` ou `(false, motivo)`. Motivos: `NotLoaded`, `NoBase`, `NoPosition`, `OutsideBase`, `TooClose`, `NoFreeSlot`. Sem `position`, usa a posição atual do jogador. O servidor valida a posição: dentro da área do ringue do dono (`EDGE_MARGIN` da borda, altura perto do piso), a pelo menos `MIN_SLOT_DISTANCE` de outros slots, no máximo `SLOTS_PER_BASE` (6). Raridade inexistente dá `error()`.
    - `GetSlots(player)`: lista de `{ Index, Rarity, StartedAt, ReadyAt, WarriorId?, Offset }` em ordem de índice, ou `nil` se os dados não estiverem carregados.
    - `GetMaxSlots(player)` (`SLOTS_PER_BASE` + bônus registrados por `AddSlotBonus`) e `IsInPlacementArea(player, position?)` (mesma regra de área do `AddScroll`, sem olhar distância nem espaço livre).
    - Extensões: `AddSlotBonus(fn)`, `AddIncomeMultiplier(fn)` (renda = soma × multiplicadores, arredondada pra baixo). Outros serviços registram aqui, para o `WarriorService` não depender deles.
    - Roubo: `OnStealAttempt(fn)` (prompt "Roubar" de cada slot), `GetSlotInfo(owner, key)`, `GetSlotWorldPosition(owner, key)`, `LockSlot`/`UnlockSlot` (travado = invisível, sem renda, só em memória), `TransferSlot(owner, key, thief, position?)` (cria no ladrão, no ponto dado ou na posição dele, e só então remove do dono; se o dono sumiu, desfaz).
  - Mantém o atributo `InOwnBase` de todos os jogadores (a cada 0,25 s, via `IsInPlacementArea`), só para a UI.
  - Visual (só servidor, sem remotes), em `Workspace.WarriorSlots.<UserId>`: cada slot tem uma placa (que segura o letreiro e o prompt "Roubar") e um letreiro pequeno (visível até `LABEL_MAX_DISTANCE`). Chocando, o totem da raridade (`TotemService`) fica em pé no ponto do slot, a placa fica invisível e o letreiro mostra "Totem", a raridade e o tempo restante. Guerreiro nascido: o totem some, a placa colorida volta e o letreiro mostra o nome, a raridade e o `$/s`. `AddScroll` e `TransferSlot` redesenham na hora.
  - Ainda não existe: mutações, renda offline.
- `ScrollService` (`src/server/Services/ScrollService.luau`) pronto. Config em `src/shared/Config/Phases.luau`: `Phases[N]` com pesos de raridade, `MaxScrolls` e `SpawnInterval` de cada fase; `LegendaryEvent`.
  - **Spawn:** cada fase começa cheia e depois repõe 1 pergaminho por `SpawnInterval`, até `MaxScrolls`. O ponto é sorteado **em volta do posto do guardião da fase**, entre `GuardianSpawn.MinDistance` e `GuardianSpawn.Radius` (6 e 25 studs, em `Config/Phases`). Se o guardião estiver perto da borda, o ponto é trazido para dentro do volume. Fase sem guardião: qualquer ponto do volume `PhaseN`. Um raio de cima pra baixo acha o chão: com guardião, ele começa `POST_RAY_ABOVE` (4) acima do posto e desce até `POST_RAY_BELOW` (25) abaixo, para não parar num telhado ou árvore em cima do guardião; sem guardião, começa no topo do volume. O raio atravessa peças sem colisão ou invisíveis. Fase que não consegue criar nenhum totem na largada gera `warn`.
  - **Evento lendário:** a cada `IntervalSeconds`, um pergaminho lendário+ aparece numa das fases de `LegendaryEvent.Phases`, e o chat de todo o servidor recebe um aviso (`Events.Announcement`). Ele não conta no `MaxScrolls`.
  - **Descompasso config × mapa:** fase da config sem `PhaseN` no mapa, ou `PhaseN` sem config, gera `warn` no início e fica sem pergaminhos.
  - **Contagem:** um pergaminho conta no `MaxScrolls` da fase de origem desde que aparece até ser colocado numa base, inclusive enquanto alguém carrega.
  - **Coleta:** pelo `ProximityPrompt` "Pegar" na `Hitbox` do totem (E no PC, X/quadrado no controle, botão na tela no celular; segurar por `PICKUP_HOLD_SECONDS` = 1 s). O servidor confere personagem vivo, mãos livres e distância real (`PICKUP_DISTANCE` + metade da largura do totem). Totem que acabou de cair só ganha o prompt depois de `DROP_PICKUP_DELAY`. Só dá pra carregar 1 por vez; enquanto carrega, o cliente esconde os prompts "Pegar".
  - **Perda:** morrer (a KillZone mata), trocar de personagem ou sair do jogo faz o pergaminho voltar para o chão da mesma fase, com a mesma raridade.
  - **Colocar:** clicando/tocando no chão da própria base. Enquanto o jogador carrega, o servidor marca no `Player` os atributos `CarryingScroll` (raridade) e `InOwnBase` (a cada 0,25 s, via `IsInPlacementArea`). Eles só servem para o cliente mostrar a dica; o servidor não confia neles.
  - **Remote `Functions.PlaceScroll(position: Vector3)`:** o ponto clicado. O servidor valida o tipo e se os números são finitos, aplica rate limit de 1 chamada a cada `PLACE_COOLDOWN` (0,5 s), exige que o **jogador** esteja no próprio ringue e passa o ponto ao `AddScroll`, que confere a área (inclusive a altura perto do piso), a distância de outros slots e o espaço livre. Só `OffsetX/Z` é salvo. Devolve `(ok, mensagem)` já em português. O `onPlace` do `CarryItem` recebe `(player, position)`.
  - **Visual:** totem (`TotemService`) em pé no chão, com giro aleatório e letreiro da raridade, em `Workspace.PhaseScrolls`. Uma `Hitbox` invisível do tamanho do totem segura o prompt "Pegar". O raio que acha o chão ignora `Map.Guardians`.
  - **Carregando:** um clone com `CarryHeight` de altura, nas costas ou acima da cabeça (`Config/Totems.CarryMount`), preso por `WeldConstraint`, sem massa e sem colisão.
  - **Totem caído:** quando o guardião pega quem carrega (`KnockDrop(player, position)`), o totem de fase cai no chão ali (`droppedAt`), ainda contando na fase. Nos primeiros `DROP_PICKUP_DELAY` (1,5 s) ele fica sem o prompt "Pegar". Depois, qualquer jogador pode pegar, ou o guardião busca (`GetDropped(phase)`, `TakeDropped(hitbox)` → `TakenTotem`, `PutBack(taken, position?)`). Caído há mais de `Config/Phases.DroppedTimeout` (30 s), volta sozinho para perto do guardião. Item roubado (sem `onDrop`) volta para o dono, como no `DropCarried`.
- `GuardianService` (`src/server/Services/GuardianService.luau`) pronto. Config em `src/shared/Config/Guardians.luau`.
  - Usa os NPCs de `Workspace.Map.Guardians.GuardianN` (ver a seção "Mapa"), pegos com `BaseService:GetGuardian`/`GetGuardianPost`; não cria NPC. O posto é o `CFrame` inicial do `HumanoidRootPart`, e os totens da fase nascem em volta dele. Vida infinita; física no servidor.
  - **Velocidade:** `Levels[N]` (900, 10K, 40K, 170K, 700K, 3M, 18M, 700M, 7B, 20B), o mesmo número de velocidade que o jogador treina. A velocidade real dele é `Config/Speed.RealSpeed(Levels[N])` (71 → 276 studs/s). O nome acima da cabeça mostra: "Guardião da fase N · ⚡ 10K". **Para levar um totem da fase N é preciso ter velocidade ≥ `Levels[N]`.**
  - A cada `UpdateInterval` (0,15 s):
    - **Perseguição:** o jogador mais próximo que carrega um totem **da fase dele** (`ScrollService:GetCarriedPhase`), em linha reta (`MoveTo`), por todo o corredor, até o jogador passar do começo da fase 1 (`BaseService:IsBeforeFirstPhase`): lá ele escapou. Jogador com velocidade menor que `Levels[N]` é perseguido a `ChaseAdvantage` (2) × a velocidade real dele, na hora (não escapa). Com igual ou maior, o guardião usa a própria velocidade real, começando em `ChaseStartFactor` (0,6) e chegando nela em `ChaseRampSeconds` (3 s). "!!" vermelho acima da cabeça. Persegue mesmo com um totem na mão. Os outros guardiões não se metem.
    - **Captura** (raio `max(CatchDistance, velocidade atual × intervalo × 0,5)`, medido no plano a partir da borda do tronco, e diferença de altura até a altura do guardião): o jogador é arremessado por um `LinearVelocity` curto (sem dano), o totem cai no chão ali (`ScrollService:KnockDrop`) e o jogador recebe `Notify`. Depois o guardião ignora alvos por `CatchCooldown`.
    - **Busca:** de mãos livres, vai (a `FetchSpeedFactor` × a máxima) até o totem caído mais perto na fase dele. Chegando (`bodyRadius + PickupReach`), para e toca a animação de pegar por `PickupSeconds`; se ninguém pegou antes, o totem (`HandTotemHeight`) vai para a mão (`RightHand`/`Right Arm`) com a animação de segurar.
    - **Sem alvo:** volta ao posto a `max(ReturnMinSpeed, ReturnSpeedFactor × máxima)`. Se estiver com totem, no posto toca a animação de pegar e o coloca no chão a `PlaceDistance` na frente dele (`ScrollService:PutBack`). Depois descansa.
    - **Descanso:** no posto, sem nada para fazer (e ao iniciar), senta no chão: animação `Sit`, root ancorado e o corpo baixado em `restDrop` (R6: comprimento da perna menos metade da espessura; R15: 80% da `HipHeight`; mais `RestExtraDrop`), com 💤 na cabeça. Jogador perto não o acorda. Quando alguém pega um totem da fase dele (ou há totem dela caído), o 💤 vira "!" e ele levanta `WakeDelay` (0,5 s) depois: volta à pose de pé, desancora e segue o comportamento normal.
    - **Segurança:** mais de `ResetDistance` (8000) do posto, ou `FallDistance` abaixo dele, é teleportado de volta.
  - **Animações** (`Config/Guardians.Animations`, por rig): R15 parado `507766666`, corrida `507767714`, pegar `522635514` (golpe de ferramenta), segurar `507768375`, sentar `2506281703`; R6 parado `180435571`, corrida `180426354`, pegar `129967390`, segurar `182393478`, sentar `178130996`. Parado/corrida trocam pela velocidade real no plano (> 0,5 studs/s = correndo), e a corrida acelera junto, até 3×. Pegar e segurar têm prioridade `Action`. Rig desconhecido fica sem animação, com `warn`.
  - `ScrollService` tem `IsCarrying`, `GetCarriers`, `GetCarriedPhase`, `DropCarried`, `KnockDrop`, `GetDropped`, `TakeDropped` e `PutBack`.
- `TotemService` (`src/server/Services/TotemService.luau`): só visual. Monta os totens a partir de `ServerStorage` (ver a seção "Mapa"), com pivot no centro da base do modelo. Config em `src/shared/Config/Totems.luau` (`CarryHeight`, `CarryMount`, `LightRange`). Não usa `Highlight` porque o Roblox só desenha ~31 ao mesmo tempo.
  - API: `Create(rarity, height?, withLabel)` (ancorado, sem colisão, sem toque e invisível para raios; `PointLight` na cor da raridade), `GetHeight(model)`, `HasTemplate(rarity)`, `AddHitbox(model)`, `MountOn(model, character)`, `AttachTo(model, anchor, offset)` (usado na mão do guardião).
- `SpeedService` (`src/server/Services/SpeedService.luau`) pronto. Config em `src/shared/Config/Speed.luau`.
  - `Speed` no `PlayerData` é o **nível de velocidade** (pode chegar a bilhões). A velocidade real é `WalkSpeed = Config/Speed.RealSpeed(nível) = min(MaxWalkSpeed, 16 + 28 × log10(1 + nível/10))`: nível 0 → 16, 900 → 71, 10K → 100, 20B → 276, teto 400. É a mesma função dos guardiões, então nível maior = mais rápido. No leaderstats e no HUD, o nível aparece formatado (`StringValue`, `Format.number`).
  - **Esteira:** uma por base. Usa o marcador `Treadmill` (Part) dentro do `BaseN` se existir; senão cria uma Part perto da borda +Z da área do ringue. É uma esteira rolante: `AssemblyLinearVelocity` no sentido do `LookVector` da Part, na mesma velocidade que o dono anda. Parado, o jogador sai dela; só fica em cima quem corre contra. Por isso "o dono está em cima" basta para treinar (a cada `TrainingTick`, `max(MinGainPerSecond, nível × GainPercentPerSecond)` por segundo × multiplicadores, ou seja, 1% do nível por segundo, no mínimo +1; teto `MaxLevel`), sem confiar no cliente. Treina só o dono da base.
  - **Modo de teste do Studio** (`src/shared/Config/StudioTest.luau`): agora aplicado aqui. Com `RunService:IsStudio()` e `Enabled = true`, `WalkSpeed = max(treinado, StudioTest.WalkSpeed)` (velocidade real, não nível: 100 ≈ nível 10K). O `Speed` salvo só cresce na esteira, então o valor de teste nunca é salvo. O antigo `StudioTestService` foi removido.
  - API: `GetSpeed(player)`, `AddTrainingMultiplier(fn)` (outros serviços registram multiplicadores do treino).
- `TrailService` (`src/server/Services/TrailService.luau`) pronto. Config em `src/shared/Config/Trails.luau`. Só visual, sem remotes.
  - O servidor cria um `Trail` no `HumanoidRootPart`, então todo mundo vê: uma faixa atrás das costas, dos pés até `Height`. Os instances se chamam `SpeedTrailTop`, `SpeedTrailBottom` e `SpeedTrail`.
  - São 10 rastros (Vento Branco → Arco-Íris Espiritual). `Tiers[N]` vale a partir de `Config/Guardians.Levels[N]` (o `MinSpeed` é preenchido de lá), então cada fase que o jogador consegue passar libera um rastro. Abaixo de `Levels[1]` (900), não tem rastro. Rastro com `Particles` solta faíscas (`ParticleEmitter`) nos pés, que só ligam acima de `ParticlesMinSpeed` no plano.
  - A cada `UpdateInterval` (0,2 s): recalcula o rastro pelo `SpeedService:GetSpeed` e, se mudou, recria. Ao subir de rastro, o jogador recebe `Notify` ("✨ Novo rastro: ..."), mas não ao entrar no jogo.
  - Na esteira quase não aparece, porque o corpo fica parado no mundo.
  - Studio: `Config/StudioTest.TrailTier` (1..10) força um rastro mínimo para teste; com 0, vale o `Speed` treinado.
- `StealService` (`src/server/Services/StealService.luau`) pronto. Config em `src/shared/Config/Steal.luau`.
  - Cada slot tem um `ProximityPrompt` "Roubar" (segurar 1 s). O cliente esconde o prompt nos próprios slots. O servidor valida: não é o dono; o dono está no jogo; o ladrão não carrega nada; rate limit (`AttemptRateLimit`); cooldown entre roubos (`CooldownSeconds`); distância real até o slot (`MaxStealDistance`); proteção após colocar (`ProtectionSeconds`, pelo `PlacedAt`).
  - **O item nunca sai dos dados do dono antes da entrega.** Ao roubar, o slot do dono é travado em memória e o ladrão carrega um pergaminho da mesma raridade (`ScrollService:CarryItem`).
    - Entregou no próprio ringue (clicando no chão): `TransferSlot`, no ponto clicado. O item é dele, com a mesma raridade, guerreiro e horário de chocagem.
    - Morreu, foi pego por um guardião, o dono encostou nele (`CatchDistance`, checado a cada 0,25 s) ou saiu: o slot destrava e volta pro dono.
    - O dono saiu no meio: o roubo é cancelado e o item fica salvo com o dono.
  - O dono é avisado (`Notify`) no início, na entrega e na devolução.
  - `ScrollService` passou a ter carga genérica: `CarryItem(player, rarity, onPlace, onLost)`. Os pergaminhos de fase usam o mesmo caminho.
- `UpgradeService` (`src/server/Services/UpgradeService.luau`) pronto. Config em `src/shared/Config/Upgrades.luau`: Mais espaço (+1 slot/nível, até 6), Renda (+10%/nível, até 10), Treino (+25%/nível, até 10). Preço `floor(BaseCost × CostGrowth^nível)`, calculado por `CostFor` (o mesmo no servidor e no cliente).
  - Níveis em `PlayerData.Upgrades` (`{ [Id]: nível }`), expostos ao cliente como atributos `Upgrade_<Id>` (só para exibir).
  - Remote `Functions.BuyUpgrade(upgradeId)`. O servidor valida: tipo, Id existente, rate limit (0,3 s), dados carregados, dentro do próprio ringue, nível máximo e dinheiro (`CurrencyService:RemoveMoney`).
  - Efeitos registrados nos serviços que os aplicam: `WarriorService:AddSlotBonus`, `WarriorService:AddIncomeMultiplier`, `SpeedService:AddTrainingMultiplier`.
  - API: `GetLevel(player, id)`, `ResetAll(player)` (usado pelo rebirth).
- `ShopController` (`src/client/Controllers/ShopController.luau`): botão "🛒 Loja" na coluna da esquerda, que só aparece com `InOwnBase`, e janela com os upgrades (nível, efeito, preço formatado e mensagem do servidor).
- `RebirthService` (`src/server/Services/RebirthService.luau`) pronto. Config em `src/shared/Config/Rebirth.luau`: custo `floor(1M × 3^rebirths)`, multiplicador de renda `1 + 0,5 × rebirths` (`CostFor`/`MultiplierFor`, os mesmos no servidor e no cliente).
  - Remote `Functions.Rebirth` (sem argumentos). O servidor valida rate limit (1 s), dados carregados e Money ≥ custo.
  - O rebirth zera o Money (o saldo inteiro), os guerreiros (`WarriorService:ResetSlots`) e os upgrades (`UpgradeService:ResetAll`) e soma 1 em `Rebirths`. O Speed não é zerado.
  - Multiplicador registrado em `WarriorService:AddIncomeMultiplier`. Atributo `Rebirths` no `Player`, para o HUD.
  - Se alguém estava carregando um item roubado deste jogador, ao entregar recebe "Esse item não existe mais". Não duplica.
- `MonetizationService` (`src/server/Services/MonetizationService.luau`) pronto. Config em `src/shared/Config/Monetization.luau`.
  - Itens: Game Passes Renda x2, Treino x2 e +2 espaços; Developer Products Pular chocagem e Pacote de dinheiro ($ 50K). **Todos os IDs estão em 0 (placeholder)**. Com ID 0 o item fica desligado: não é consultado, não é oferecido, a loja mostra "Em breve" e nada quebra.
  - Game Pass: a posse é consultada ao entrar (`UserOwnsGamePassAsync` com `pcall`) e em `PromptGamePassPurchaseFinished`. Fica em memória e em atributos `Pass_<Key>` (só UI). Efeitos registrados em `AddIncomeMultiplier`, `AddTrainingMultiplier` e `AddSlotBonus`.
  - Developer Product: `ProcessReceipt` idempotente. `PurchaseId` já entregue responde `PurchaseGranted` sem entregar de novo. Jogador ausente, dados não carregados ou erro na entrega respondem `NotProcessedYet`. Os `PurchaseId` ficam em `PlayerData.ProcessedReceipts` (os 200 mais recentes).
  - **Limitação:** a compra é salva no autosave ou na saída. Se o servidor cair antes, o jogador perde a compra (nunca duplica). Ver `docs/decisoes-pendentes.md`.
  - Remote `Functions.PromptPurchase(kind, key)`. O servidor valida tipos, chave, ID ≠ 0, rate limit, Game Pass ainda não comprado e, no "Pular chocagem", se há algo chocando. Só então abre a compra.
  - `WarriorService` ganhou `HasHatching(player)` e `SkipHatching(player)`.
- `StoreController` (`src/client/Controllers/StoreController.luau`): botão "💎 Robux" na coluna da esquerda e janela com passes e produtos ("Em breve" com ID 0, "Comprado" com `Pass_<Key>`).
- **HUD** (estilo "simulator": fonte `LuckiestGuy`/`FredokaOne`, contornos grossos, degradês, botões que crescem no hover). Ícones são emojis; para trocar por imagem, mude o `Icon` do `Style.bigButton`.
  - `src/client/UI/Style.luau`: cores, fontes e peças prontas: `bigButton`, `smallButton`, `window` (janela com faixa de título, X e linha de mensagem), `row`, `label`, `pop`, `animate`.
  - `src/client/UI/Hud.luau`: um `ScreenGui` "Hud" com as regiões `left` (coluna de botões; `LayoutOrder` 1 Loja, 2 Robux, 3 Rebirth), `bottomLeft`, `bottomCenter`, `topRight`, `bottomRight`, `notices` e `windows`. Um `UIScale` acompanha o tamanho da tela (0,55 a 1,25 de 1280×720). `Hud.notify(texto, cor?)` mostra um aviso no alto (até 3, somem em 3,5 s). `Hud.openWindow(frame)` abre uma janela e fecha as outras.
- `HudController` (`src/client/Controllers/HudController.luau`): no canto de baixo, a linha de rebirth e, em números grandes com degradê, a velocidade (⚡) e o dinheiro (💵). Lê os atributos `Money`, `Speed` e `Rebirths`. O botão "🔁 Rebirth" confirma em dois cliques (o primeiro avisa o custo). Os `Events.Notify` saem pelo `Hud.notify`.
- `LeaderboardController`: placar no canto de cima à direita (jogador, `$/s` do atributo `Income`, velocidade do atributo `Speed`), ordenado pela velocidade, com o jogador local destacado e botão para recolher. Desliga a lista de jogadores padrão do Roblox (`CoreGuiType.PlayerList`).
- `EventTimerController`: "🌟 Lendário em 4m 26s" no canto de baixo à direita, pelo atributo `NextLegendaryAt` do `ReplicatedStorage` (horário do servidor; marcado pelo `ScrollService` a cada ciclo do evento).
- `ScrollController` (`src/client/Controllers/ScrollController.luau`): com `CarryingScroll` e `InOwnBase`, mostra a faixa "👆 Clique (Toque) no chão da sua base para colocar o totem" e um disco translúcido sob o mouse. Clique (`MouseButton1`) ou toque rápido (`TouchTap`), fora de botões da tela, manda o ponto pelo `PlaceScroll`. O resultado sai pelo `Hud.notify`, e o aviso do evento vai para o chat (`TextChatService`, canal `RBXGeneral`). Os totens no chão não giram.
- Nenhum outro sistema de gameplay implementado ainda.