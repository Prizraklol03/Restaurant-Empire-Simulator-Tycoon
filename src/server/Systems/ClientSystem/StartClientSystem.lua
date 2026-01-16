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

local UpdateBusinessStats = Net.GetRemoteEvent("UpdateBusinessStats")
local UpdateCashRegisterUI = Net.GetRemoteEvent("UpdateCashRegisterUI")

local StartClientSystem = {}

local Active = {}

local SPAWN_MIN = 3
local SPAWN_MAX = 6

local function getSpotPosition(spot)
	if not spot then
		return nil
	end
	if spot:IsA("Attachment") then
		return spot.WorldPosition
	end
	return spot.Position
end

local function logSpotNames(spots)
	local names = {}
	for _, spot in ipairs(spots) do
		local name = spot.Name
		table.insert(names, name)
	end
	return table.concat(names, ",")
end

local function updateBusinessStats(state)
	local now = os.clock()
	if now - (state.lastStatsSent or 0) < 1 then
		return
	end

	state.lastStatsSent = now
	UpdateBusinessStats:FireClient(state.player, {
		v = 1,
		money = PlayerService.GetMoney(state.player),
		servedCount = state.servedCount,
		queueSize = #state.queueOrder,
		location = "Kiosk",
	})
end

local function sendCashRegister(state, payload)
	UpdateCashRegisterUI:FireClient(state.player, payload)
end

local function assignQueueSpots(state)
	for index, clientId in ipairs(state.queueOrder) do
		local client = state.clients[clientId]
		local spot = state.queueSpots[index]
		if client and spot then
			if client.spotIndex ~= index then
				client.spotIndex = index
				client.atSpot = false
				local pos = getSpotPosition(spot)
				if pos and client.model then
					print(string.format("[Queue] player=%s clientId=%s spotIndex=%d", state.player.UserId, clientId, index))
					ClientAI.MoveTo(client.model, pos, 6)
					client.atSpot = true
				end
			end
		end
	end
end

local function spawnClient(state)
	local template = ServerStorage:FindFirstChild("ClientTemplate")
	if not template then
		warn("[ClientSystem] ClientTemplate missing")
		return
	end

	state.clientCounter += 1
	local clientId = state.clientCounter
	local model = template:Clone()
	model:SetAttribute("ClientId", clientId)
	model:SetAttribute("OwnerUserId", state.player.UserId)
	model.Parent = state.clientsFolder

	if model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") then
		model:PivotTo(state.spawnPoint.CFrame)
	end

	state.clients[clientId] = {
		model = model,
		state = "Queue",
		spotIndex = nil,
		atSpot = false,
	}

	table.insert(state.queueOrder, clientId)
	print(string.format("[Spawn] player=%s clientId=%s queueSize=%d/%d", state.player.UserId, clientId, #state.queueOrder, #state.queueSpots))
	assignQueueSpots(state)
	updateBusinessStats(state)
end

local function moveToRegisterIfReady(state)
	if state.currentAtRegister then
		return
	end

	local frontId = state.queueOrder[1]
	if not frontId then
		return
	end

	local frontClient = state.clients[frontId]
	if not frontClient or not frontClient.atSpot then
		return
	end

	table.remove(state.queueOrder, 1)
	state.currentAtRegister = frontId
	frontClient.state = "Register"
	frontClient.atSpot = false

	assignQueueSpots(state)

	local pos = getSpotPosition(state.orderPoint)
	if pos and frontClient.model then
		print(string.format("[Register] player=%s clientId=%s moving to register", state.player.UserId, frontId))
		ClientAI.MoveTo(frontClient.model, pos, 8)
		frontClient.atSpot = true
		print(string.format("[Register] player=%s clientId=%s reached register", state.player.UserId, frontId))
	end
end

local function createOrder(state)
	local clientId = state.currentAtRegister
	if not clientId then
		warn("[TakeOrder] no client at register")
		return
	end

	if state.currentOrder then
		warn("[TakeOrder] order already exists")
		return
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
		warn("[Order] creation failed")
		return
	end

	state.currentOrder = {
		orderId = order.id,
		clientId = clientId,
		state = "CREATED",
		ready = false,
		stationType = order.stationType,
		cookTime = order.cookTime,
		deadlineAt = order.deadlineAt,
		price = order.price,
	}

	print(string.format("[Order] created player=%s clientId=%s orderId=%s", state.player.UserId, clientId, order.id))

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
end

local function completeOrder(state)
	local order = state.currentOrder
	if not order then
		return
	end

	OrderService.CompleteOrder(order.orderId)
	PlayerService.AddMoney(state.player, order.price or 0)
	state.servedCount += 1

	print(string.format("[Order] completed player=%s orderId=%s", state.player.UserId, order.orderId))

	updateBusinessStats(state)

	local clientId = state.currentAtRegister
	local client = clientId and state.clients[clientId]
	if client and client.model then
		local pos = getSpotPosition(state.endPoint)
		if pos then
			client.state = "Exit"
			ClientAI.MoveTo(client.model, pos, 8)
			client.model:Destroy()
			state.clients[clientId] = nil
		end
	end

	state.currentOrder = nil
	state.currentAtRegister = nil
end

local function failOrder(state, reason)
	local order = state.currentOrder
	if not order then
		return
	end

	OrderService.FailOrder(order.orderId, reason)
	print(string.format("[Order] failed player=%s orderId=%s reason=%s", state.player.UserId, order.orderId, reason))

	sendCashRegister(state, {
		v = 1,
		state = "FAILED",
		reason = reason,
		orderId = order.orderId,
	})

	local clientId = state.currentAtRegister
	local client = clientId and state.clients[clientId]
	if client and client.model then
		local pos = getSpotPosition(state.endPoint)
		if pos then
			client.state = "Exit"
			ClientAI.MoveTo(client.model, pos, 8)
			client.model:Destroy()
			state.clients[clientId] = nil
		end
	end

	state.currentOrder = nil
	state.currentAtRegister = nil
	updateBusinessStats(state)
end

local function startCooking(state, stationType)
	local order = state.currentOrder
	if not order then
		return
	end

	if order.ready or order.state == "COOKING" then
		return
	end

	if order.stationType ~= stationType then
		warn("[Cook] wrong station", stationType)
		return
	end

	order.state = "COOKING"
	print(string.format("[Cook] start player=%s orderId=%s station=%s", state.player.UserId, order.orderId, stationType))

	sendCashRegister(state, {
		v = 1,
		state = "COOKING",
		orderId = order.orderId,
		stationType = stationType,
		cookTime = order.cookTime,
	})

	task.delay(order.cookTime, function()
		if state.currentOrder ~= order then
			return
		end

		order.ready = true
		order.state = "READY"
		print(string.format("[Cook] ready player=%s orderId=%s", state.player.UserId, order.orderId))

		sendCashRegister(state, {
			v = 1,
			state = "READY",
			orderId = order.orderId,
		})
	end)
end

local function bindPrompts(state)
	local ownerId = state.player.UserId

	local takeOrderPrompt = state.takeOrderPrompt
	if takeOrderPrompt then
		takeOrderPrompt.Triggered:Connect(function(triggerPlayer)
			print("[TakeOrder] trigger", triggerPlayer.Name, "owner", ownerId, "currentAtRegister", state.currentAtRegister, "hasOrder", state.currentOrder ~= nil)
			if triggerPlayer.UserId ~= ownerId then
				warn("[TakeOrder] not owner")
				return
			end
			if not state.currentAtRegister then
				warn("[TakeOrder] no client at register")
				return
			end
			if state.currentOrder then
				if state.currentOrder.ready then
					completeOrder(state)
					moveToRegisterIfReady(state)
					return
				end
				warn("[TakeOrder] order already exists")
				return
			end
			createOrder(state)
		end)
	else
		warn("[ClientSystem] TakeOrder prompt missing")
	end

	local servePrompt = state.servePrompt
	if servePrompt then
		servePrompt.Triggered:Connect(function(triggerPlayer)
			if triggerPlayer.UserId ~= ownerId then
				warn("[ServeOrder] not owner")
				return
			end
			if not state.currentOrder then
				warn("[ServeOrder] no order")
				return
			end
			if not state.currentOrder.ready then
				warn("[ServeOrder] order not ready")
				return
			end
			completeOrder(state)
			moveToRegisterIfReady(state)
		end)
	end

	for _, prompt in ipairs(state.grillPrompts) do
		prompt.Triggered:Connect(function(triggerPlayer)
			if triggerPlayer.UserId ~= ownerId then
				warn("[Cook] not owner")
				return
			end
			startCooking(state, "GRILL")
		end)
	end

	for _, prompt in ipairs(state.drinkPrompts) do
		prompt.Triggered:Connect(function(triggerPlayer)
			if triggerPlayer.UserId ~= ownerId then
				warn("[Cook] not owner")
				return
			end
			startCooking(state, "DRINK")
		end)
	end
end

local function update(state)
	if os.clock() >= state.nextSpawnAt and #state.queueOrder < #state.queueSpots then
		spawnClient(state)
		state.nextSpawnAt = os.clock() + math.random(SPAWN_MIN, SPAWN_MAX)
	end

	moveToRegisterIfReady(state)

	local order = state.currentOrder
	if order and os.clock() > order.deadlineAt and not order.ready then
		failOrder(state, "timeout")
		moveToRegisterIfReady(state)
	end
end

function StartClientSystem.StartForPlayer(player, business)
	if not business or not business.kiosk then
		warn("[ClientSystem] Business missing for player", player.UserId)
		return nil
	end

	local flow = business.kiosk:WaitForChild("ClientFlow")
	local queueFolder = flow:WaitForChild("Queue")
	local spots = {}
	for _, child in ipairs(queueFolder:GetChildren()) do
		local index = tonumber(string.match(child.Name, "^Spot_(%d+)$"))
		if index then
			spots[index] = child
		end
	end

	local sortedSpots = {}
	for index = 1, #spots do
		if spots[index] then
			table.insert(sortedSpots, spots[index])
		end
	end

	print(string.format("[ClientSystem] player=%s spots=%d names=%s", player.UserId, #sortedSpots, logSpotNames(sortedSpots)))

	local cashPrompts = business.cashRegisterPrompts or {}
	local takeOrderPrompt = nil
	local servePrompt = nil
	for _, prompt in ipairs(cashPrompts) do
		if prompt.Name == "TakeOrder" then
			takeOrderPrompt = prompt
		elseif prompt.Name == "ServeOrder" or prompt.Name == "PayOrder" then
			servePrompt = prompt
		end
	end

	if not takeOrderPrompt then
		takeOrderPrompt = cashPrompts[1]
	end

	local state = {
		player = player,
		business = business,
		clientsFolder = business.clientsFolder,
		spawnPoint = business.spawnPoint,
		endPoint = business.endPoint,
		orderPoint = business.orderPoint,
		queueSpots = sortedSpots,
		queueOrder = {},
		clients = {},
		currentAtRegister = nil,
		currentOrder = nil,
		servedCount = 0,
		clientCounter = 0,
		lastStatsSent = 0,
		nextSpawnAt = os.clock() + math.random(SPAWN_MIN, SPAWN_MAX),
		grillPrompts = business.grillPrompts or {},
		drinkPrompts = business.drinkPrompts or {},
		takeOrderPrompt = takeOrderPrompt,
		servePrompt = servePrompt,
		active = true,
	}

	bindPrompts(state)

	Active[player] = state

	state.loop = task.spawn(function()
		while state.active do
			update(state)
			task.wait(0.3)
		end
	end)

	return state
end

function StartClientSystem.StopForPlayer(player)
	local state = Active[player]
	if not state then
		return
	end

	state.active = false
	Active[player] = nil

	if state.loop then
		-- loop exits on active=false
	end

	for _, client in pairs(state.clients) do
		if client.model and client.model.Parent then
			client.model:Destroy()
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	StartClientSystem.StopForPlayer(player)
end)

return StartClientSystem
