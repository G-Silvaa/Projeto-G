--!strict

-- Roubo entre jogadores. O ladrão ativa o prompt "Roubar" de um slot alheio; o
-- servidor valida tudo, trava o slot do dono (some e para de render) e o ladrão
-- passa a carregar um pergaminho da mesma raridade.
--   - Entregou no próprio ringue: WarriorService:TransferSlot (o item é dele).
--   - Morreu, foi pego (pelo dono ou por um guardião) ou saiu: o slot destrava.
--   - O dono saiu no meio: o roubo é cancelado e o item fica salvo com o dono.
-- O item nunca sai dos dados do dono antes da entrega, então não há como duplicar
-- nem perder item.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StealConfig = require(Shared:WaitForChild("Config"):WaitForChild("Steal"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ScrollService = require(script.Parent.ScrollService)
local WarriorService = require(script.Parent.WarriorService)

local StealService = {}

local CATCH_CHECK_INTERVAL = 0.25

type Steal = {
	thief: Player,
	owner: Player,
	key: string,
	itemName: string,
}

local stealsByThief: { [Player]: Steal } = {}
local lastSteal: { [Player]: number } = {}
local lastAttempt: { [Player]: number } = {}

local function notify(player: Player, text: string)
	if player.Parent == Players then
		Remotes.getEvent(Remotes.Events.Notify):FireClient(player, text)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function onStealAttempt(thief: Player, owner: Player, key: string)
	local now = os.clock()
	local last = lastAttempt[thief]
	if last and now - last < StealConfig.AttemptRateLimit then
		return
	end
	lastAttempt[thief] = now

	if thief == owner or owner.Parent ~= Players then
		return
	end
	if ScrollService:IsCarrying(thief) then
		notify(thief, "Você já está carregando alguma coisa")
		return
	end
	local lastDone = lastSteal[thief]
	if lastDone and now - lastDone < StealConfig.CooldownSeconds then
		notify(thief, `Espere {math.ceil(StealConfig.CooldownSeconds - (now - lastDone))} s para roubar de novo`)
		return
	end

	local info = WarriorService:GetSlotInfo(owner, key)
	local slotPosition = WarriorService:GetSlotWorldPosition(owner, key)
	local thiefRoot = rootOf(thief)
	if info == nil or slotPosition == nil or thiefRoot == nil then
		return
	end
	-- O prompt tem alcance no cliente, mas vale a distância real no servidor.
	if (thiefRoot.Position - slotPosition).Magnitude > StealConfig.MaxStealDistance then
		return
	end
	local protectedFor = StealConfig.ProtectionSeconds - (os.time() - info.PlacedAt)
	if protectedFor > 0 then
		notify(thief, `Protegido por mais {math.ceil(protectedFor)} s`)
		return
	end

	if not WarriorService:LockSlot(owner, key) then
		return
	end

	local itemName = if info.WarriorId then "guerreiro" else "pergaminho"
	local steal: Steal = { thief = thief, owner = owner, key = key, itemName = itemName }

	local carrying = ScrollService:CarryItem(thief, info.Rarity, function(placer: Player): (boolean, string?)
		local ok, reason = WarriorService:TransferSlot(owner, key, placer)
		if ok then
			stealsByThief[thief] = nil
			notify(owner, `{thief.Name} roubou seu {itemName}!`)
		elseif reason == "Gone" then
			stealsByThief[thief] = nil
		end
		return ok, reason
	end, function()
		stealsByThief[thief] = nil
		WarriorService:UnlockSlot(owner, key)
		notify(owner, `Seu {itemName} voltou para a sua base.`)
	end)

	if not carrying then
		WarriorService:UnlockSlot(owner, key)
		return
	end

	stealsByThief[thief] = steal
	lastSteal[thief] = now
	notify(owner, `{thief.Name} está roubando seu {itemName}! Pegue ele antes que chegue na base.`)
	notify(thief, `Você pegou um {itemName}! Leve até o seu ringue.`)
end

-- Dono encostou no ladrão: o item volta.
local function checkCatches()
	for thief, steal in stealsByThief do
		local thiefRoot = rootOf(thief)
		local ownerRoot = rootOf(steal.owner)
		if thiefRoot and ownerRoot and (thiefRoot.Position - ownerRoot.Position).Magnitude <= StealConfig.CatchDistance then
			ScrollService:DropCarried(thief)
			notify(thief, "O dono te pegou! O item voltou para ele.")
		end
	end
end

function StealService:Start()
	WarriorService:OnStealAttempt(onStealAttempt)

	Players.PlayerRemoving:Connect(function(player: Player)
		-- Dono saiu: cancela os roubos dele (o item fica salvo com ele).
		for thief, steal in stealsByThief do
			if steal.owner == player then
				ScrollService:DropCarried(thief)
				notify(thief, "O dono saiu do jogo; o item voltou para ele.")
			end
		end
		lastSteal[player] = nil
		lastAttempt[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(CATCH_CHECK_INTERVAL)
			checkCatches()
		end
	end)
end

return StealService
