--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local Remotes = {}

-- Chave = valor, para usar como Remotes.Events.NomeDoRemote.
Remotes.Events = {} :: { [string]: string }

Remotes.Functions = {} :: { [string]: string }

local function createAll(folder: Folder, className: "RemoteEvent" | "RemoteFunction", names: { [string]: string })
	for key, name in names do
		assert(key == name, `Remotes: chave '{key}' diferente do nome '{name}'`)
		assert(folder:FindFirstChild(name) == nil, `Remotes: nome duplicado '{name}'`)

		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
	end
end

function Remotes.setup(): ()
	assert(RunService:IsServer(), "Remotes.setup só pode ser chamado no servidor")
	assert(ReplicatedStorage:FindFirstChild(FOLDER_NAME) == nil, "Remotes.setup já foi chamado")

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	createAll(folder, "RemoteEvent", Remotes.Events)
	createAll(folder, "RemoteFunction", Remotes.Functions)

	-- Só parenteia no fim, para o cliente nunca ver a pasta pela metade.
	folder.Parent = ReplicatedStorage
end

local function getRemote(name: string): Instance
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name)
end

function Remotes.getEvent(name: string): RemoteEvent
	local remote = getRemote(name)
	if not remote:IsA("RemoteEvent") then
		error(`Remotes: '{name}' não é um RemoteEvent`)
	end
	return remote
end

function Remotes.getFunction(name: string): RemoteFunction
	local remote = getRemote(name)
	if not remote:IsA("RemoteFunction") then
		error(`Remotes: '{name}' não é um RemoteFunction`)
	end
	return remote
end

return Remotes
