--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

type Loaded = { name: string, module: any }

local function loadModules(folder: Instance): { Loaded }
	local loaded: { Loaded } = {}

	for _, child in folder:GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		end

		local ok, result = xpcall(require, debug.traceback, child)
		if not ok then
			warn(`[Main] Falha ao carregar {child.Name}:\n{result}`)
		elseif typeof(result) ~= "table" then
			warn(`[Main] {child.Name} não retornou uma tabela; ignorado`)
		else
			table.insert(loaded, { name = child.Name, module = result })
		end
	end

	table.sort(loaded, function(a, b)
		return a.name < b.name
	end)

	return loaded
end

local function initAll(loaded: { Loaded }): { Loaded }
	local ready: { Loaded } = {}

	for _, entry in loaded do
		local init = entry.module.Init
		if typeof(init) == "function" then
			local ok, err = xpcall(init, debug.traceback, entry.module)
			if not ok then
				warn(`[Main] Erro no Init de {entry.name}; Start não será chamado:\n{err}`)
				continue
			end
		end
		table.insert(ready, entry)
	end

	return ready
end

local function startAll(ready: { Loaded })
	for _, entry in ready do
		local start = entry.module.Start
		if typeof(start) == "function" then
			task.spawn(function()
				local ok, err = xpcall(start, debug.traceback, entry.module)
				if not ok then
					warn(`[Main] Erro no Start de {entry.name}:\n{err}`)
				end
			end)
		end
	end
end

local controllers = initAll(loadModules(script.Parent:WaitForChild("Controllers")))
startAll(controllers)

print(`[Projeto G] Cliente v{Config.Versao} iniciado ({#controllers} controllers)`)
