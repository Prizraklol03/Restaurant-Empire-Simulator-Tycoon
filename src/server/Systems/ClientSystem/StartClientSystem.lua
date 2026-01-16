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

local function planarDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

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

local function logOccupancy(state)
	local parts = table.create(#state.spotOccupant)
	for index = 1, #state.spotOccupant do
		local clientId = state.spotOccupant[index]
		parts[index] = string.format("%d:%s", index, tostring(clientId or "nil"))
	end
	print(string.format("[Occupancy] player=%s spots=%s", state.player.UserId, table.concat(parts, " ")))
	print(string.format("[RegisterState] currentAtRegister=%s", tostring(state.currentAtRegister)))
end

local function countQueue(state)
	local count = 0
	for index = 1, #state.spotOccupant do
		if state.spotOccupant[index] then
			count += 1
		end
	end
	return count
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
		queueSize = countQueue(state),
		location = "Kiosk",
	})
end

local function sendCashRegister(state, payload)
	UpdateCashRegisterUI:FireClient(state.player, payload)
end

local function getClientRoot(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function moveToAndConfirm(model, targetPos, radius, timeout)
	if not model then
		return false
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = getClientRoot(model)
	if not humanoid or not root then
		return false
	end

	local safeTarget = Vector3.new(targetPos.X, root.Position.Y, targetPos.Z)
	humanoid:MoveTo(safeTarget)

	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if planarDistance(root.Position, safeTarget) <= radius then
			return true
		end
		task.wait(0.15)
	end

	return false
end

local function assignClientToSpot(state, clientId, spotIndex)
	if state.spotOccupant[spotIndex] then
		warn(string.format("[QueueAssign] spot %d already occupied", spotIndex))
		return false
	end

	local client = state.clients[clientId]
	if not client or not client.model then
		return false
	end

	state.spotOccupant[spotIndex] = clientId
	state.clientSpotIndex[clientId] = spotIndex
	client.state = "Queue"

	local pos = getSpotPosition(state.queueSpots[spotIndex])
	if not pos then
		return false
	end

	client.atSpot = false
	client.moveToken += 1
	local token = client.moveToken

	local reached = moveToAndConfirm(client.model, pos, 1.6, 6)
	if not reached then
		reached = moveToAndConfirm(client.model, pos, 1.6, 6)
	end

	if token ~= client.moveToken then
		return false
	end

	client.atSpot = reached
	print(string.format("[QueueAssign] clientId=%s spot=%d reached=%s", clientId, spotIndex, tostring(reached)))
	if not reached then
		state.spotOccupant[spotIndex] = nil
		state.clientSpotIndex[clientId] = nil
		return false
	end

	return true
end

local function shiftQueueForward(state)
	for index = 1, #state.queueSpots - 1 do
		if state.spotOccupant[index] == nil and state.spotOccupant[index + 1] ~= nil then
			local clientId = state.spotOccupant[index + 1]
			state.spotOccupant[index] = clientId
			state.spotOccupant[index + 1] = nil
			state.clientSpotIndex[clientId] = index

			local client = state.clients[clientId]
			local reached = false
			if client and client.model then
				client.state = "Queue"
				client.atSpot = false
				client.moveToken += 1
				local token = client.moveToken
				local pos = getSpotPosition(state.queueSpots[index])
				if pos then
					reached = moveToAndConfirm(client.model, pos, 1.6, 6)
					if not reached then
						reached = moveToAndConfirm(client.model, pos, 1.6, 6)
					end
				end
				if token == client.moveToken then
					client.atSpot = reached
				end
			end

			if not reached then
				warn("[QueueShift] failed move, reverting", clientId, index)
				state.spotOccupant[index + 1] = clientId
				state.spotOccupant[index] = nil
				state.clientSpotIndex[clientId] = index + 1
			end

			print(string.format("[QueueShift] clientId=%d %d->%d reached=%s", clientId, index + 1, index, tostring(reached)))
		end
	end

	logOccupancy(state)
end

local function spawnClient(state)
	local template = ServerStorage:FindFirstChild("ClientTemplate")
	if not template then
		warn("[ClientSystem] ClientTemplate missing")
		return
	end

	local freeSpot = nil
	for index = 1, #state.queueSpots do
		if state.spotOccupant[index] == nil then
			freeSpot = index
			break
		end
	end

	if not freeSpot then
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
		moveToken = 0,
	}

	print(string.format("[Spawn] player=%s clientId=%s queueSize=%d/%d", state.player.UserId, clientId, countQueue(state), #state.queueSpots))
	assignClientToSpot(state, clientId, freeSpot)
	logOccupancy(state)
	updateBusinessStats(state)
end

local function promoteToRegister(state)
	if state.currentAtRegister then
		return
	end

	local frontId = state.spotOccupant[1]
	if not frontId then
		return
	end

	local frontClient = state.clients[frontId]
	if not frontClient or not frontClient.model then
		return
	end

	local spotPos = getSpotPosition(state.queueSpots[1])
	local root = getClientRoot(frontClient.model)
	if not spotPos or not root then
		return
	end

	if planarDistance(root.Position, spotPos) > 1.8 then
		local now = os.clock()
		if now - (state._lastPromoteDebug or 0) > 1 then
			state._lastPromoteDebug = now
			print(string.format("[PromoteSkip] frontId=%s distToSpot1=%.2f", tostring(frontId), planarDistance(root.Position, spotPos)))
		end
		return
	end

	state.currentAtRegister = frontId
	frontClient.state = "Register"
	frontClient.atSpot = false

	local pos = getSpotPosition(state.orderPoint)
	if pos then
		print(string.format("[PromoteToRegister] clientId=%s", frontId))
		frontClient.moveToken += 1
		local token = frontClient.moveToken
		local reachedOrder = moveToAndConfirm(frontClient.model, pos, 3.0, 10)
		if token ~= frontClient.moveToken then
			return
		end

		if reachedOrder then
			state.spotOccupant[1] = nil
			state.clientSpotIndex[frontId] = nil
			print("[PromoteToRegister] reached orderPoint, freed Spot_1")
			print("[HOWTO] Клиент у кассы. Нажми TakeOrder на CashRegister.")
			shiftQueueForward(state)
		else
			print("[PromoteToRegister] failed reach orderPoint, will retry")
			state.currentAtRegister = nil
			frontClient.state = "Queue"
		end
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
	print(string.format("[HOWTO] Заказ создан: station=%s. Нажми %s.", order.stationType, order.stationType))

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
			client.moveToken += 1
			moveToAndConfirm(client.model, pos, 2.0, 8)
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
			client.moveToken += 1
			moveToAndConfirm(client.model, pos, 2.0, 8)
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
		print("[HOWTO] Блюдо готово. Нажми TakeOrder на CashRegister чтобы отдать/получить оплату.")

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
	if os.clock() >= state.nextSpawnAt and countQueue(state) < #state.queueSpots then
		spawnClient(state)
		state.nextSpawnAt = os.clock() + math.random(SPAWN_MIN, SPAWN_MAX)
	end

	promoteToRegister(state)

	local order = state.currentOrder
	if order and os.clock() > order.deadlineAt and not order.ready then
		failOrder(state, "timeout")
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
		spotOccupant = table.create(#sortedSpots, nil),
		clientSpotIndex = {},
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
