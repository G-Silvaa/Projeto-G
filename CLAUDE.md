# Projeto G

Jogo multiplayer no Roblox (Luau) de coleção e roubo de criaturas. Cada jogador tem uma base, coleta criaturas que geram dinheiro, pode roubar criaturas de outros jogadores, comprar upgrades e fazer rebirth.

## Ferramentas

- **Rojo 7.7.0** (via Rokit): sincroniza `src/` com o Roblox Studio. O `rojo serve` roda no Windows.
- **Roblox Studio**: execução, testes e edição visual do mapa.
- **Claude Code**: trabalha nos arquivos pelo WSL em `/mnt/c/Roblox/Projeto G`.
- **Git**: branch `main`.

Nunca edite scripts direto no Studio. A fonte da verdade é `src/`. O mapa (Workspace) é editado no Studio e **não** é sincronizado pelo Rojo.

## Mapeamento Rojo (`default.project.json`)

| Pasta local   | Destino no Studio                                |
|---------------|--------------------------------------------------|
| `src/server`  | `ServerScriptService.Server`                     |
| `src/shared`  | `ReplicatedStorage.Shared`                       |
| `src/client`  | `StarterPlayer.StarterPlayerScripts.Client`      |
| `src/gui`     | `StarterGui.Gui`                                 |

Se criar uma nova pasta raiz fora dessas, atualize o `default.project.json`.

## Convenções de arquivos

- `Nome.server.luau` → Script (servidor)
- `Nome.client.luau` → LocalScript (cliente)
- `Nome.luau` → ModuleScript
- `init.luau` dentro de uma pasta transforma a pasta no próprio ModuleScript
- Serviços em PascalCase com sufixo `Service` (ex.: `CurrencyService`)
- Controladores do cliente com sufixo `Controller` (ex.: `UIController`)
- Configurações estáticas em `src/shared/Config/` (ex.: `Monsters.luau`, `Economy.luau`)

## Arquitetura

- **Um único Script de entrada por lado**: `src/server/Main.server.luau` e `src/client/Main.client.luau` carregam e inicializam os módulos. Os demais arquivos são ModuleScripts.
- Serviços do servidor ficam em `src/server/Services/`.
- Controladores do cliente ficam em `src/client/Controllers/`.
- RemoteEvents e RemoteFunctions são criados pelo servidor em `ReplicatedStorage.Remotes` na inicialização, com nomes centralizados em `src/shared/Remotes.luau`.
- Use `--!strict` no topo de todo arquivo novo e tipe as funções públicas.

## Regras de segurança (obrigatórias)

- **O servidor é a autoridade.** Dinheiro, inventário, criaturas, roubos e compras são decididos só no servidor.
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

## Sistemas planejados (em ordem)

1. [x] Estrutura base (Main server/client, Remotes, Config)
2. [x] PlayerData + DataStore
3. [ ] Currency (dinheiro)
4. [ ] Bases dos jogadores
5. [ ] Criaturas (definições + geração de renda)
6. [ ] Captura
7. [ ] Inventário
8. [ ] Roubo entre jogadores
9. [ ] Upgrades
10. [ ] Rebirth
11. [ ] Monetização (Game Passes / Developer Products)

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
  - `src/shared/Remotes.luau`: nomes em `Remotes.Events` / `Remotes.Functions` (chave = valor, vazios por enquanto); `getEvent(name)` / `getFunction(name)` nos dois lados.
  - `src/shared/Config/init.luau` contém só a versão (`0.0.1`).
- `PlayerDataService` (`src/server/Services/PlayerDataService/`) pronto:
  - Uma chave por jogador (`Player_<UserId>`) com `{ Data, Lock }`. Session lock via `UpdateAsync`: o lock expira em 180 s sem renovação; um servidor só grava se o lock for dele e, se não for, kicka o jogador.
  - Load com 5 tentativas (5 s entre elas); se falhar, kicka e não salva. Autosave a cada 60 s, save + liberação do lock ao sair e no `BindToClose`.
  - Template atual: `DataVersion = 1`, `JoinCount` (incrementado a cada load).
  - API (outros serviços usam `require(script.Parent.PlayerDataService)`): `IsLoaded(player)`, `Get(player, key)` (tabelas vêm como cópia), `Set(player, key, value)`, `Update(player, key, fn)` (o `fn` não pode yieldar), `OnPlayerLoaded(callback)`. `Set`/`Update` retornam `false` se o jogador não estiver carregado e dão erro se a chave não existir no template, se for `DataVersion` ou se o tipo for diferente.
- Nenhum sistema de gameplay implementado ainda.