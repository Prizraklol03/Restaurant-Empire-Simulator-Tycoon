-- StartClientSystem.lua
-- Orchestrates kiosk loop per player

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(game.ServerScriptService.Core.Config)
local PlayerService = require(game.ServerScriptService.Core.PlayerService)
local OrderGenerator = require(game.ServerScriptService.Core.OrderGenerator)
local OrderService = require(game.ServerScriptService.Core.OrderService)

local Net = require(ReplicatedStorage.Shared.Net)

local Modules = script.Parent:WaitForChild("Modules")
local ClientAI = require(Modules:WaitForChild("ClientAI"))
local QueueService = require(Modules:WaitForChild("QueueService"))

local UpdateBusinessStats = Net.GetRemoteEvent("UpdateBusinessStats")
local UpdateCashRegisterUI = Net.GetRemoteEvent("UpdateCashRegisterUI")

local StartClientSystem = {}

local ActiveBusinesses = {}

local function getClientTemplate()
	return ServerStorage:FindFirstChild("ClientTemplate")
end

local function setModelPosition(model, target)
	if not model then
		return
	end

	local primary = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if primary then
		model:PivotTo(target)
	end
end

local function getClientId(model)
	return model and model:GetAttribute("ClientId")
end

local function createClient(state)
	local template = getClientTemplate()
	if not template then
		warn("[ClientSystem] ClientTemplate missing")
		return nil
	end

	local clientModel = template:Clone()
	local clientId = tostring(game:GetService("HttpService"):GenerateGUID(false))
	clientModel:SetAttribute("ClientId", clientId)
	clientModel:SetAttribute("OwnerUserId", state.player.UserId)

	clientModel.Parent = state.clientsFolder
	setModelPosition(clientModel, state.spawnPoint.CFrame)

	state.clients[clientId] = {
		model = clientModel,
		spawnedAt = os.clock(),
	}

	return clientModel
end

local function updateQueueAssignments(state, assignments)
	for model, spot in pairs(assignments) do
		if model and model.Parent then
			ClientAI.MoveTo(model, spot.Position, 6)
		end
	end
end

local function enqueueClient(state, clientModel)
	local spotIndex = state.queue:Join(clientModel)
	if not spotIndex then
		clientModel:Destroy()
		return false
	end
	return true
end

local function sendBusinessStats(state)
	local now = os.clock()
	if now - state.lastStatsSent < 1 then
		return
	end

	state.lastStatsSent = now
	UpdateBusinessStats:FireClient(state.player, {
		v = 1,
		money = PlayerService.GetMoney(state.player),
		servedCount = state.servedCount,
		queueSize = state.queue:GetSize(),
		location = "Kiosk",
	})
end

local function sendCashRegister(state, payload)
	UpdateCashRegisterUI:FireClient(state.player, payload)
end

local function createOrderForClient(state, clientModel)
	local clientId = getClientId(clientModel)
	if not clientId then
		return nil
	end

	local items = OrderGenerator.Generate({
		menuLevel = 1,
		stationLevels = PlayerService.GetStationLevels(state.player),
		unlockedFoods = PlayerService.GetSave(state.player).Business.UnlockedFoods,
	})

	local order = OrderService.CreateOrder(state.player, clientId, {
		items = items,
		location = "Kiosk",
	})

	if not order then
		return nil
	end

	state.currentOrder = order
	state.currentAtRegister = clientModel

	sendCashRegister(state, {
		v = 1,
		state = "ORDER_CREATED",
		clientId = clientId,
		orderId = order.id,
		items = order.items,
		stationType = order.stationType,
		cookTime = order.cookTime,
		deadlineAt = order.deadlineAt,
	})

	return order
end

local function processFront(state)
	if state.currentAtRegister or state.currentOrder then
		return
	end

	local frontModel = state.queue:GetFront()
	if not frontModel then
		return
	end

	state.queue:Leave(frontModel)
	local reached = ClientAI.MoveTo(frontModel, state.orderPoint.Position, 8)
	if not reached then
		frontModel:Destroy()
		return
	end

	createOrderForClient(state, frontModel)
end

local function failOrder(state, reason)
	local order = state.currentOrder
	if not order then
		return
	end

	OrderService.FailOrder(order.id, reason)
	sendCashRegister(state, {
		v = 1,
		state = "FAILED",
		reason = reason,
		orderId = order.id,
	})

	if state.currentAtRegister then
		ClientAI.MoveTo(state.currentAtRegister, state.endPoint.Position, 8)
		state.currentAtRegister:Destroy()
	end

	state.currentOrder = nil
	state.currentAtRegister = nil
	sendBusinessStats(state)
end

local function completeOrder(state)
	local order = state.currentOrder
	if not order then
		return
	end

	OrderService.CompleteOrder(order.id)
	PlayerService.AddMoney(state.player, order.price or 0)
	state.servedCount += 1

	sendBusinessStats(state)

	if state.currentAtRegister then
		ClientAI.MoveTo(state.currentAtRegister, state.endPoint.Position, 8)
		state.currentAtRegister:Destroy()
	end

	state.currentOrder = nil
	state.currentAtRegister = nil
end

local function startCooking(state, stationType)
	local order = state.currentOrder
	if not order or order.ready or order.cooking then
		return
	end

	if order.stationType ~= stationType then
		return
	end

	order.cooking = true
	sendCashRegister(state, {
		v = 1,
		state = "COOKING",
		orderId = order.id,
		stationType = stationType,
		cookTime = order.cookTime,
	})

	task.delay(order.cookTime, function()
		if state.currentOrder ~= order then
			return
		end

		order.ready = true
		order.cooking = false

		sendCashRegister(state, {
			v = 1,
			state = "READY",
			orderId = order.id,
		})
	end)
end

local function bindPrompts(state)
	state.cashRegisterPrompt.Triggered:Connect(function(player)
		if player ~= state.player then
			return
		end

		local order = state.currentOrder
		if not order or not order.ready then
			return
		end

		completeOrder(state)
		processFront(state)
	end)

	state.grillPrompt.Triggered:Connect(function(player)
		if player ~= state.player then
			return
		end
		startCooking(state, "GRILL")
	end)

	state.drinkPrompt.Triggered:Connect(function(player)
		if player ~= state.player then
			return
		end
		startCooking(state, "DRINK")
	end)
end

local function startSpawnLoop(state)
	state.spawnTask = task.spawn(function()
		while state.active do
			task.wait(math.random(6, 10))
			if state.queue:GetSize() >= state.queue:GetCapacity() then
				continue
			end

			local clientModel = createClient(state)
			if clientModel then
				enqueueClient(state, clientModel)
				processFront(state)
			end
		end
	end)
end

local function startTimeoutLoop(state)
	state.timeoutTask = task.spawn(function()
		while state.active do
			task.wait(1)
			local order = state.currentOrder
			if order and os.clock() > order.deadlineAt and not order.ready then
				failOrder(state, "timeout")
				processFront(state)
			end
		end
	end)
end

function StartClientSystem.Start(player, business)
	if not business then
		warn("[ClientSystem] Business missing for player", player.UserId)
		return nil
	end

	local state = {
		player = player,
		kiosk = business.kiosk,
		clientsFolder = business.clientsFolder,
		spawnPoint = business.spawnPoint,
		endPoint = business.endPoint,
		orderPoint = business.orderPoint,
		queueSpots = business.queueSpots,
		cashRegisterPrompt = business.cashRegisterPrompt,
		grillPrompt = business.grillPrompt,
		drinkPrompt = business.drinkPrompt,
		queue = QueueService.new(),
		clients = {},
		currentAtRegister = nil,
		currentOrder = nil,
		servedCount = 0,
		lastStatsSent = 0,
		active = true,
	}

	state.queue:SetSpots(state.queueSpots)
	state.queue:SetOnAssign(function(assignments)
		updateQueueAssignments(state, assignments)
	end)

	bindPrompts(state)
	startSpawnLoop(state)
	startTimeoutLoop(state)

	ActiveBusinesses[player] = state
	return {
		Stop = function()
			state.active = false
			ActiveBusinesses[player] = nil
			if state.currentAtRegister then
				state.currentAtRegister:Destroy()
			end
			for _, data in pairs(state.clients) do
				if data.model and data.model.Parent then
					data.model:Destroy()
				end
			end
		end,
	}
end

function StartClientSystem.Stop(player)
	local state = ActiveBusinesses[player]
	if not state then
		return
	end
	state.active = false
	ActiveBusinesses[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	StartClientSystem.Stop(player)
end)

return StartClientSystem
