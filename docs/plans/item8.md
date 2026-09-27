# Item 8 — Esteira de velocidade

## Decisões

- **Esteira = Part com `AssemblyLinearVelocity` (esteira rolante)**, ancorada, que empurra para o centro do ringue. A velocidade da esteira acompanha o `WalkSpeed` do dono. Assim, parado ele é levado para fora em menos de 1 s, e só fica em cima quem corre contra ela. O servidor não precisa confiar em nada do cliente: treina quem está em cima da esteira.
- Marcador `Treadmill` (Part) dentro do Model `BaseN`: se existir, é usado; a frente da Part (`LookVector`) é o sentido em que ela empurra. Se não existir, o servidor cria uma Part perto da borda +Z da área do ringue (`GetBaseArea`), empurrando para o centro.
- Só o dono da base treina na própria esteira.
- `Speed` (número, pode ser fracionário) no `PlayerData`. `WalkSpeed = min(MaxWalkSpeed, BaseWalkSpeed + Speed × WalkSpeedPerPoint)`, tudo em `Config/Speed.luau`. `Speed` inteiro no leaderstats.
- O modo de teste do Studio passa a ser aplicado pelo `SpeedService`: `WalkSpeed = max(treinado, StudioTest.WalkSpeed)`. O `Speed` salvo só cresce na esteira, nunca é derivado do `WalkSpeed`, então o 100 do teste nunca é salvo. O `StudioTestService` deixa de existir (a única coisa que ele fazia era isso); a config `StudioTest.luau` continua.
- Ponto de extensão `trainingMultiplier(player)` = 1 por enquanto (upgrades e Game Pass entram nos itens 10 e 12).

## Minitarefas

- [x] 8.1 `Config/Speed.luau`
- [x] 8.2 Template: `Speed = 0`
- [x] 8.3 `BaseService`: guardar o marcador de cada base + `GetBaseInstance(index)`
- [x] 8.4 `SpeedService`: achar/criar esteira por base, esteira rolante
- [x] 8.5 `SpeedService`: treino (dono em cima da esteira, a cada 0,5 s), salvar `Speed`
- [x] 8.6 `SpeedService`: aplicar `WalkSpeed` ao nascer e quando `Speed` muda; leaderstats `Speed`
- [x] 8.7 Mover o modo de teste do Studio para o `SpeedService`, remover `StudioTestService`
- [x] 8.8 `luau-lsp` strict sem erros; `CLAUDE.md`; commit
