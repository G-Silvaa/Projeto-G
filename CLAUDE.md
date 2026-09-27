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
2. Corre pelo corredor compartilhado, dividido em 10 fases, e pega um pergaminho no chão. Só dá para carregar 1 pergaminho por vez.
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
- Controladores do cliente ficam em `src/client/Controllers/`.
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
├── Lobby       Part (piso visível) onde nasce quem não tem base; precisa dar acesso ao corredor
├── KillZone    Part invisível abaixo de tudo; quem encosta volta pra própria base (ou pro lobby)
└── Corridor/   chão dos biomas e paredões (só visual, o código não lê)
```

- 5 bases no máximo (`BASE_COUNT` no topo do `BaseService`), então o servidor deve aceitar no máximo 5 jogadores. Isso se configura no Studio em *Game Settings → Places → Max Players = 5*; não dá para fazer pelo código.
- Marcador de base: `Model` ou `Part`, ancorado.
  - **Model** (o ringue inteiro): o personagem nasce no centro do ringue, em cima do piso. O piso é achado com um raio de cima pra baixo no centro da caixa do modelo, que só enxerga o próprio ringue. Não depende do pivot. Não coloque nada pendurado bem em cima do centro do ringue, senão o raio acerta isso primeiro.
  - **Part**: o personagem nasce em cima dela. A área da Part também é a área onde dá pra colocar pergaminhos, então ela precisa cobrir o piso inteiro do ringue (`Transparency = 1`, `CanCollide = false`).
  - Sem placa nem nome em cima das bases. A altura de nascimento é `SPAWN_HEIGHT` no topo do `BaseService`.
- Não precisa colocar `SpawnLocation` no mapa: o `BaseService` cria os pontos de nascimento sozinho. O do template pode ser apagado.
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
7. [ ] Guardiões das fases
8. [ ] Esteira de velocidade
9. [ ] Roubo entre jogadores
10. [ ] Upgrades
11. [ ] Rebirth
12. [ ] Monetização

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
  - `src/shared/Remotes.luau`: nomes em `Remotes.Events` / `Remotes.Functions` (chave = valor); `getEvent(name)` / `getFunction(name)` nos dois lados. Hoje: `Functions.PlaceScroll` e `Events.Announcement` (ver `ScrollService`).
  - `src/shared/Config/init.luau` contém só a versão (`0.0.1`).
- `PlayerDataService` (`src/server/Services/PlayerDataService/`) pronto:
  - Uma chave por jogador (`Player_<UserId>`) com `{ Data, Lock }`. Session lock via `UpdateAsync`: o lock expira em 180 s sem renovação; um servidor só grava se o lock for dele e, se não for, kicka o jogador.
  - Load com 5 tentativas (5 s entre elas); se falhar, kicka e não salva. Autosave a cada 60 s, save + liberação do lock ao sair e no `BindToClose`.
  - Template atual: `DataVersion = 1`, `JoinCount` (incrementado a cada load), `Money`, `Slots` (ver `WarriorService`).
  - API (outros serviços usam `require(script.Parent.PlayerDataService)`): `IsLoaded(player)`, `Get(player, key)` (tabelas vêm como cópia), `Set(player, key, value)`, `Update(player, key, fn)` (o `fn` não pode yieldar), `OnPlayerLoaded(callback)`. `Set`/`Update` retornam `false` se o jogador não estiver carregado e dão erro se a chave não existir no template, se for `DataVersion` ou se o tipo for diferente.
- `CurrencyService` (`src/server/Services/CurrencyService.luau`) pronto:
  - `Money` (inteiro, `>= 0`) no template do `PlayerDataService`; chave nova de nível de cima, preenchida sozinha nos dados antigos, sem precisar de migração.
  - API: `GetMoney(player)` (`number?`), `AddMoney(player, amount)`, `RemoveMoney(player, amount)` (`boolean`, `false` se saldo insuficiente ou jogador não carregado). `amount` negativo, não-inteiro, NaN ou infinito faz `error()` — é bug de quem chamou, não estado de jogo.
  - Saldo mostrado via `leaderstats` (`IntValue "Money"` em `player.leaderstats`), sincronizado pelo servidor a cada mudança; nenhum código de cliente.
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
  - API: `GetBase(player)` (índice `1..5` ou `nil`), `GetOwner(baseIndex)` (`Player?`), `GetPhaseAt(position)` (número da fase cujo volume `PhaseN` contém a posição, funcionando com a Part rotacionada, ou `nil`), `GetBaseArea(baseIndex)` (`CFrame?, Vector3?`: centro do piso da base, girado só no eixo vertical como o ringue, e o tamanho da área; Model usa a caixa do modelo, Part usa o tamanho da Part), `GetPhaseCount()` (maior `N` entre os `PhaseN`), `GetPhasePart(index)` (`BasePart?`).
- Modo de teste do Studio (`src/server/Services/StudioTestService.luau`, opções em `src/shared/Config/StudioTest.luau`):
  - Só roda se `RunService:IsStudio()` for verdadeiro e `Enabled = true`. Fora do Studio, o `Start` retorna sem conectar nada, então nunca afeta o jogo publicado.
  - Hoje só faz uma coisa: `WalkSpeed = 100` a cada personagem que nasce. Avisa no Output (`warn`) que está ativo.
  - Quando existir o sistema de treino de velocidade, ele também vai mexer em `WalkSpeed` e vai brigar com este modo. Nesse momento, decidir qual dos dois prevalece no Studio.
- `WarriorService` (`src/server/Services/WarriorService.luau`) pronto. Dados em `src/shared/Config/Rarities.luau` (cor, ordem, tempo de choca, faixa de renda) e `src/shared/Config/Warriors.luau` (36 guerreiros: 6 clãs × 6 raridades).
  - Os Ids de raridade (`Common`..`Secret`) e de guerreiro (ex.: `kaseri`) ficam salvos nos dados: não renomeie. `DisplayName` e `Name` podem mudar.
  - `Slots` no `PlayerData`: chave `"1".."6"` → `{ Rarity, StartedAt, OffsetX, OffsetZ, WarriorId? }`. `StartedAt` é `os.time()`, então a chocagem continua offline. `OffsetX/Z` é a posição relativa ao centro da base (`GetBaseArea`), então continua certa se o jogador pegar outra base; se a base nova for menor, o slot é trazido pra dentro dela.
  - A cada 1 s, para cada jogador carregado: termina as chocagens vencidas, sorteando um guerreiro da raridade (qualquer clã); soma a renda dos guerreiros e chama `CurrencyService:AddMoney`; atualiza o visual. A renda só corre com o dono no jogo.
  - Na inicialização, valida as configs: Ids únicos, raridade existente, renda inteira e dentro da faixa, pelo menos 1 guerreiro por raridade. Se algo falhar, dá erro e o `Start` não roda.
  - API:
    - `AddScroll(player, rarity, position?)`: retorna `(true)` ou `(false, motivo)`. Motivos: `NotLoaded`, `NoBase`, `NoPosition`, `OutsideBase`, `TooClose`, `NoFreeSlot`. Sem `position`, usa a posição atual do jogador. O servidor valida a posição: dentro da área do ringue do dono (`EDGE_MARGIN` da borda, altura perto do piso), a pelo menos `MIN_SLOT_DISTANCE` de outros slots, no máximo `SLOTS_PER_BASE` (6). Raridade inexistente dá `error()`.
    - `GetSlots(player)`: lista de `{ Index, Rarity, StartedAt, ReadyAt, WarriorId?, Offset }` em ordem de índice, ou `nil` se os dados não estiverem carregados.
    - `GetMaxSlots()` e `IsInPlacementArea(player, position?)` (mesma regra de área do `AddScroll`, sem olhar distância nem espaço livre).
  - Visual (só servidor, sem remotes): uma placa colorida pela raridade em cada slot, em `Workspace.WarriorSlots.<UserId>`, com um letreiro pequeno (visível até `LABEL_MAX_DISTANCE`). Chocando, mostra "Pergaminho", a raridade e o tempo restante; depois, o nome do guerreiro, a raridade e o `$/s`.
  - Ainda não existe: mutações, renda offline.
- `ScrollService` (`src/server/Services/ScrollService.luau`) pronto. Config em `src/shared/Config/Phases.luau`: `Phases[N]` com pesos de raridade, `MaxScrolls` e `SpawnInterval` de cada fase; `LegendaryEvent`.
  - **Spawn:** cada fase começa cheia e depois repõe 1 pergaminho por `SpawnInterval`, até `MaxScrolls`. O ponto é aleatório dentro do volume `PhaseN`, e um raio de cima pra baixo acha o chão.
  - **Evento lendário:** a cada `IntervalSeconds`, um pergaminho lendário+ aparece numa das fases de `LegendaryEvent.Phases`, e o chat de todo o servidor recebe um aviso (`Events.Announcement`). Ele não conta no `MaxScrolls`.
  - **Descompasso config × mapa:** fase da config sem `PhaseN` no mapa, ou `PhaseN` sem config, gera `warn` no início e fica sem pergaminhos.
  - **Contagem:** um pergaminho conta no `MaxScrolls` da fase de origem desde que aparece até ser colocado numa base, inclusive enquanto alguém carrega.
  - **Coleta:** pega encostando (`Touched`), mas o servidor confere a distância real até o personagem (`PICKUP_DISTANCE`), porque um exploit consegue disparar `Touched` de longe. Só dá pra carregar 1 por vez. Ele aparece acima da cabeça, preso ao personagem e sem colisão.
  - **Perda:** morrer (a KillZone mata), trocar de personagem ou sair do jogo faz o pergaminho voltar para o chão da mesma fase, com a mesma raridade.
  - **Colocar:** enquanto o jogador carrega, o servidor marca no `Player` os atributos `CarryingScroll` (raridade) e `InOwnBase` (a cada 0,25 s, via `IsInPlacementArea`). Eles só servem para o cliente mostrar o botão; o servidor não confia neles.
  - **Remote `Functions.PlaceScroll`:** não recebe argumento nenhum. O servidor usa o pergaminho carregado e a posição atual no `AddScroll`, com rate limit de 1 chamada a cada `PLACE_COOLDOWN` (0,5 s) por jogador. Devolve `(ok, mensagem)` já em português.
  - **Visual:** pergaminho `Neon` na cor da raridade, com letreiro pequeno, em `Workspace.PhaseScrolls`. O giro é feito só no cliente.
- `ScrollController` (`src/client/Controllers/ScrollController.luau`): botão "Colocar pergaminho", que só aparece com `CarryingScroll` e `InOwnBase`, mensagem de resultado por 3 s, aviso do evento no chat (`TextChatService`, canal `RBXGeneral`) e giro dos pergaminhos no chão.
- Nenhum outro sistema de gameplay implementado ainda.