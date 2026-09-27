--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Template = require(script.Template)

local IS_STUDIO = RunService:IsStudio()

local DATASTORE_NAME = if IS_STUDIO then "PlayerData_Studio" else "PlayerData"
local KEY_PREFIX = "Player_"

-- Todas as sessões do Studio compartilham o dono do lock, para parar e dar Play de novo sem esperar o lock expirar.
local SESSION_ID = if IS_STUDIO then "Studio" else game.JobId

local AUTOSAVE_INTERVAL = 60
local LOCK_EXPIRE = 180
local LOAD_ATTEMPTS = 5
local LOAD_RETRY_DELAY = 5
local SAVE_ATTEMPTS = 3
local SAVE_RETRY_DELAY = 2

local STUDIO_HINT = "Studio: publique o place e ative Game Settings > Security > Enable Studio Access to API Services."

local KICK_MESSAGES: { [string]: string } = {
	error = "Não foi possível carregar seus dados. Tente entrar novamente em alguns instantes.",
	locked = "Seus dados ainda estão em uso em outro servidor. Tente novamente em alguns minutos.",
	newer = "Este servidor está desatualizado. Entre em outro servidor.",
	lost = "Sua sessão foi aberta em outro servidor.",
}

-- Migrations[n] converte os dados da versão n para a versão n + 1.
local Migrations: { [number]: (data: { [string]: any }) -> () } = {}

type Lock = { JobId: string, Time: number }
type Record = { Data: { [string]: any }, Lock: Lock? }
type Session = { data: { [string]: any }, saving: boolean, releasing: boolean }
type LoadResult = "ok" | "locked" | "newer" | "error"
type SaveResult = "ok" | "lost" | "error"

local dataStore: DataStore? = nil
local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local releasingUsers: { [number]: boolean } = {}
local loadedCallbacks: { (Player) -> () } = {}
local shuttingDown = false

local PlayerDataService = {}

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[deepCopy(key)] = deepCopy(child)
	end
	return copy
end

local function keyFor(player: Player): string
	return KEY_PREFIX .. player.UserId
end

local function isInGame(player: Player): boolean
	return player.Parent == Players
end

local function kick(player: Player, message: string)
	if isInGame(player) then
		player:Kick(message)
	end
end

local function trySave(store: DataStore, player: Player, session: Session, releaseLock: boolean): SaveResult
	local result: SaveResult = "error"

	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function(old: Record?): (Record?, { number }?)
			local lock = old and old.Lock
			if lock == nil or lock.JobId ~= SESSION_ID then
				result = "lost"
				return nil, nil
			end

			result = "ok"
			return {
				Data = session.data,
				Lock = if releaseLock then nil else { JobId = SESSION_ID, Time = os.time() },
			}, { player.UserId }
		end)
	end)

	if not ok then
		warn(`[PlayerDataService] Erro ao salvar {player.Name}: {err}`)
		return "error"
	end
	return result
end

local function save(player: Player, session: Session, releaseLock: boolean)
	local store = dataStore
	if store == nil then
		return
	end

	session.saving = true
	local result: SaveResult = "error"
	for attempt = 1, SAVE_ATTEMPTS do
		result = trySave(store, player, session, releaseLock)
		if result ~= "error" then
			break
		end
		if attempt < SAVE_ATTEMPTS then
			task.wait(SAVE_RETRY_DELAY)
		end
	end
	session.saving = false

	if result == "lost" then
		warn(`[PlayerDataService] {player.Name}: lock pertence a outro servidor; save cancelado`)
		session.releasing = true
		sessions[player] = nil
		kick(player, KICK_MESSAGES.lost)
	elseif result == "error" then
		warn(`[PlayerDataService] {player.Name}: save falhou após {SAVE_ATTEMPTS} tentativas`)
	end
end

local function release(player: Player)
	local session = sessions[player]
	if session == nil or session.releasing then
		return
	end
	session.releasing = true
	releasingUsers[player.UserId] = true

	-- Espera o autosave em andamento, senão ele poderia gravar o lock de novo depois da liberação.
	while session.saving do
		task.wait()
	end
	if sessions[player] == session then
		save(player, session, true)
	end

	sessions[player] = nil
	releasingUsers[player.UserId] = nil
end

local function tryLoad(store: DataStore, player: Player): (LoadResult, { [string]: any }?)
	local result: LoadResult = "error"
	local data: { [string]: any }? = nil

	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function(old: Record?): (Record?, { number }?)
			-- O UpdateAsync pode chamar esta função mais de uma vez; cada chamada define o resultado do zero.
			data = nil
			local record: Record = old or { Data = deepCopy(Template) }

			local lock = record.Lock
			if lock and lock.JobId ~= SESSION_ID and os.time() - lock.Time < LOCK_EXPIRE then
				result = "locked"
				return nil, nil
			end

			if record.Data.DataVersion > Template.DataVersion then
				result = "newer"
				return nil, nil
			end

			while record.Data.DataVersion < Template.DataVersion do
				Migrations[record.Data.DataVersion](record.Data)
				record.Data.DataVersion += 1
			end
			for key, value in Template do
				if record.Data[key] == nil then
					record.Data[key] = deepCopy(value)
				end
			end

			record.Data.JoinCount += 1
			record.Lock = { JobId = SESSION_ID, Time = os.time() }

			result = "ok"
			data = record.Data
			return record, { player.UserId }
		end)
	end)

	if not ok then
		warn(`[PlayerDataService] Erro ao carregar {player.Name}: {err}`)
		return "error", nil
	end
	return result, data
end

local function loadPlayer(player: Player)
	if loading[player] or sessions[player] then
		return
	end

	local store = dataStore
	if store == nil then
		kick(player, KICK_MESSAGES.error .. (if IS_STUDIO then `\n\n{STUDIO_HINT}` else ""))
		return
	end

	loading[player] = true

	-- Se o jogador acabou de sair deste servidor, espera o save de saída antes de ler.
	while releasingUsers[player.UserId] do
		task.wait()
	end

	local result: LoadResult = "error"
	local data: { [string]: any }? = nil
	for attempt = 1, LOAD_ATTEMPTS do
		if shuttingDown or not isInGame(player) then
			break
		end
		result, data = tryLoad(store, player)
		if result == "ok" or result == "newer" then
			break
		end
		if attempt < LOAD_ATTEMPTS then
			task.wait(LOAD_RETRY_DELAY)
		end
	end

	loading[player] = nil

	if result == "ok" and data then
		local session: Session = { data = data, saving = false, releasing = false }
		sessions[player] = session

		if shuttingDown or not isInGame(player) then
			release(player)
			return
		end

		print(`[PlayerDataService] {player.Name} carregado (JoinCount = {data.JoinCount})`)
		for _, callback in loadedCallbacks do
			task.spawn(callback, player)
		end
	elseif not shuttingDown and isInGame(player) then
		warn(`[PlayerDataService] {player.Name}: load falhou ({result}); jogador será kickado`)
		local message = KICK_MESSAGES[result]
		if result == "error" and IS_STUDIO then
			message ..= `\n\n{STUDIO_HINT}`
		end
		kick(player, message)
	end
end

local function autosaveLoop()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for player, session in sessions do
			if not session.saving and not session.releasing then
				task.spawn(save, player, session, false)
			end
		end
	end
end

local function onClose()
	shuttingDown = true
	for player in sessions do
		task.spawn(release, player)
	end
	while next(sessions) ~= nil or next(loading) ~= nil do
		task.wait()
	end
end

local function activeSession(player: Player): Session?
	local session = sessions[player]
	if session and not session.releasing then
		return session
	end
	return nil
end

local function validateKey(key: string, forWrite: boolean)
	if Template[key] == nil or (forWrite and key == "DataVersion") then
		error(`[PlayerDataService] Chave inválida: '{key}'`, 3)
	end
end

local function validateValue(key: string, value: any)
	local expected = typeof(Template[key])
	if typeof(value) ~= expected then
		error(`[PlayerDataService] '{key}' espera {expected}, recebeu {typeof(value)}`, 3)
	end
end

function PlayerDataService:Init()
	for version = 1, Template.DataVersion - 1 do
		assert(Migrations[version], `[PlayerDataService] Falta a migração da versão {version} para {version + 1}`)
	end

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		dataStore = result
	else
		warn(`[PlayerDataService] DataStore indisponível: {result}` .. (if IS_STUDIO then `\n{STUDIO_HINT}` else ""))
	end
end

function PlayerDataService:Start()
	game:BindToClose(onClose)
	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
	task.spawn(autosaveLoop)
end

function PlayerDataService:IsLoaded(player: Player): boolean
	return activeSession(player) ~= nil
end

function PlayerDataService:Get(player: Player, key: string): any
	validateKey(key, false)
	local session = activeSession(player)
	if session == nil then
		return nil
	end
	return deepCopy(session.data[key])
end

function PlayerDataService:Set(player: Player, key: string, value: any): boolean
	validateKey(key, true)
	validateValue(key, value)
	local session = activeSession(player)
	if session == nil then
		return false
	end
	session.data[key] = deepCopy(value)
	return true
end

-- `fn` recebe uma cópia do valor atual e devolve o novo valor. Não pode yieldar.
function PlayerDataService:Update(player: Player, key: string, fn: (any) -> any): boolean
	validateKey(key, true)
	local session = activeSession(player)
	if session == nil then
		return false
	end
	local value = fn(deepCopy(session.data[key]))
	validateValue(key, value)
	session.data[key] = value
	return true
end

function PlayerDataService:OnPlayerLoaded(callback: (Player) -> ())
	table.insert(loadedCallbacks, callback)
	for player, session in sessions do
		if not session.releasing then
			task.spawn(callback, player)
		end
	end
end

return PlayerDataService
