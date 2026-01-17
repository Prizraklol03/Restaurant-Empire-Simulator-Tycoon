-- StartClientSystem.lua
-- Orchestrates kiosk loop per player

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(game.ServerScriptService.Core.Config)
local FoodConfig = require(game.ServerScriptService.Core.FoodConfig)
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
local TAKE_ORDER_WINDOW = 10
local QUEUE_BUFFER = 15
local QUEUE_MIN = 20
local QUEUE_MAX = 120
local ORDER_BUFFER = 8
local ORDER_MIN = 12
local ORDER_MAX = 90

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
	local parts = table.create(state.numSpots)
	for index = 1, state.numSpots do
		local clientId = state.spotOccupant[index]
		parts[index] = string.format("%d:%s", index, tostring(clientId or "nil"))
	end
	print(string.format("[Occupancy] player=%s spots=%s", state.player.UserId, table.concat(parts, " ")))
	print(string.format("[RegisterState] currentAtRegister=%s", tostring(state.currentAtRegister)))
end

local function countQueue(state)
	local count = 0
	for index = 1, state.numSpots do
		if state.spotOccupant[index] ~= nil then
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

local orderHasRemainingForStation
local pickNextFoodForStation
local getUnitFinalCookTime

local function ensureBoolMap(t)
	if type(t) ~= "table" then
		return {}
	end
	if #t > 0 then
		local map = {}
		for _, id in ipairs(t) do
			if type(id) == "string" and id ~= "" then
				map[id] = true
			end
		end
		return map
	end
	return t
end

local function setCashPrompt(state, mode)
	local cashPrompt = state.cashPrompt
	if not cashPrompt then
		return
	end

	if mode == "TAKE" then
		cashPrompt.Enabled = true
		cashPrompt.ActionText = "Take Order"
	elseif mode == "GIVE" then
		cashPrompt.Enabled = true
		cashPrompt.ActionText = "Give Order"
	else
		cashPrompt.Enabled = false
	end
end

local function setStationPrompts(state)
	local order = state.currentOrder

	local function configurePrompts(prompts, stationType)
		for _, prompt in ipairs(prompts) do
			prompt.Enabled = false
			prompt.ActionText = "Cook"
			prompt.HoldDuration = 0
		end

		if not order then
			return
		end

		if not orderHasRemainingForStation(order, stationType) then
			return
		end

		local foodId = pickNextFoodForStation(order, stationType)
		if not foodId then
			return
		end

		local cookTime = getUnitFinalCookTime(state.player, foodId)
		local holdDuration = math.max(0.1, cookTime)

		for _, prompt in ipairs(prompts) do
			prompt.Enabled = true
			prompt.ActionText = "Cook"
			prompt.HoldDuration = holdDuration
		end
	end

	configurePrompts(state.grillPrompts, "GRILL")
	configurePrompts(state.drinkPrompts, "DRINK")
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

local function forEachPlannedItem(items, handler)
	if type(items) ~= "table" then
		return
	end

	if #items > 0 then
		for _, foodId in ipairs(items) do
			handler(foodId, 1)
		end
	else
		for foodId, entry in pairs(items) do
			local qty = 1
			if type(entry) == "table" then
				qty = entry.quantity or 1
			elseif type(entry) == "number" then
				qty = entry
			end
			handler(foodId, qty)
		end
	end
end

local function getStationMultiplier(stationLevels, stationType)
	local levels = stationLevels or {}
	local level = levels[stationType] or 1
	local stationMult = 1.0
	local stationCfg = Config.Cooking.Stations[stationType]
	if stationCfg and stationCfg.Levels and stationCfg.Levels[level] then
		stationMult = stationCfg.Levels[level].CookTimeMultiplier or 1.0
	end
	return stationMult
end

local function buildRemainingUnits(items)
	local remaining = {}
	forEachPlannedItem(items, function(foodId, qty)
		if qty > 0 then
			remaining[foodId] = (remaining[foodId] or 0) + qty
		end
	end)
	return remaining
end

orderHasRemainingForStation = function(order, stationType)
	if not order or not order.remainingUnits then
		return false
	end

	for foodId, qty in pairs(order.remainingUnits) do
		if qty > 0 then
			local food = FoodConfig.GetFoodById(foodId)
			if food and food.Station == stationType then
				return true
			end
		end
	end

	return false
end

pickNextFoodForStation = function(order, stationType)
	if not order or not order.remainingUnits then
		return nil
	end

	local candidates = {}
	for foodId, qty in pairs(order.remainingUnits) do
		if qty > 0 then
			local food = FoodConfig.GetFoodById(foodId)
			if food and food.Station == stationType then
				table.insert(candidates, foodId)
			end
		end
	end

	table.sort(candidates)
	return candidates[1]
end

getUnitFinalCookTime = function(player, foodId)
	local food = FoodConfig.GetFoodById(foodId)
	if not food then
		return 0
	end

	local stationLevels = PlayerService.GetStationLevels(player)
	local mult = getStationMultiplier(stationLevels, food.Station)
	return (food.BaseCookTime or 0) * mult
end

local function debugMenuSnapshotOnce(state)
	if not Config.Server.DebugMode then
		return
	end
	if state._menuSnapshotLogged then
		return
	end
	state._menuSnapshotLogged = true

	local stationLevels = PlayerService.GetStationLevels(state.player) or {}
	local unlocked = ensureBoolMap(PlayerService.GetUnlockedFoods(state.player))
	local enabled = ensureBoolMap(PlayerService.GetEnabledFoods(state.player))

	local function keys(t)
		local out = {}
		for k, v in pairs(t) do
			if v == true or type(v) == "number" then
				table.insert(out, tostring(k) .. "=" .. tostring(v))
			end
		end
		table.sort(out)
		return table.concat(out, ",")
	end

	print("[MenuSnapshot] stationLevels=" .. keys(stationLevels))
	print("[MenuSnapshot] unlocked=" .. keys(unlocked))
	print("[MenuSnapshot] enabled=" .. keys(enabled))

	local categories = FoodConfig.GetCategories()
	local menuLevel = 1
	for categoryId in pairs(categories) do
		local foods = FoodConfig.GetAvailableFoodsByCategory(categoryId, menuLevel, stationLevels, unlocked)
		local candidates = {}
		for _, food in ipairs(foods) do
			if enabled[food.Id] == true then
				table.insert(candidates, food.Id .. "(" .. tostring(food.Station) .. ")")
			end
		end
		table.sort(candidates)
		print(string.format("[MenuSnapshot] category=%s candidates=%d [%s]", categoryId, #candidates, table.concat(candidates, ",")))
	end

	local cola = FoodConfig.GetFoodById("Cola")
	print("[MenuSnapshot] colaExists=" .. tostring(cola ~= nil) .. " colaStation=" .. tostring(cola and cola.Station))
end

local function computePlannedOrder(state)
	local stationLevels = PlayerService.GetStationLevels(state.player)
	local unlockedFoods = ensureBoolMap(PlayerService.GetUnlockedFoods(state.player))
	local enabledFoods = ensureBoolMap(PlayerService.GetEnabledFoods(state.player))
	if next(enabledFoods) == nil then
		enabledFoods = unlockedFoods
	end
	local menuLevel = 1

	if Config.Server.DebugMode then
		print(string.format(
			"[OrderGenContext] enabledType=%s unlockedType=%s enabledCola=%s unlockedCola=%s",
			typeof(enabledFoods),
			typeof(unlockedFoods),
			tostring(enabledFoods and enabledFoods["Cola"]),
			tostring(unlockedFoods and unlockedFoods["Cola"])
		))

		local function logKeys(label, data)
			local keys = {}
			for key, value in pairs(data or {}) do
				if value == true or value == 1 then
					table.insert(keys, tostring(key))
				end
			end
			table.sort(keys)
			local shown = {}
			for index = 1, math.min(10, #keys) do
				shown[index] = keys[index]
			end
			print(string.format("[OrderGenContext] %sKeys=%s", label, table.concat(shown, ",")))
		end

		logKeys("enabled", enabledFoods)
		logKeys("unlocked", unlockedFoods)
	end

	local items = OrderGenerator.Generate({
		menuLevel = menuLevel,
		stationLevels = stationLevels,
		unlockedFoods = unlockedFoods,
		enabledFoods = enabledFoods,
	})

	local baseCookSum = 0
	local finalCookSum = 0
	local stations = {}
	local warnedMissingFood = false

	forEachPlannedItem(items, function(foodId, qty)
		local food = FoodConfig.GetFoodById(foodId)
		if food and food.BaseCookTime then
			local finalQty = qty or 1
			local baseCook = food.BaseCookTime * finalQty
			baseCookSum += baseCook
			local stationMult = getStationMultiplier(stationLevels, food.Station)
			finalCookSum += baseCook * stationMult
			stations[food.Station] = true
		else
			if not warnedMissingFood then
				warn("[PlannedOrder] missing FoodConfig for", foodId)
				warnedMissingFood = true
			end
		end
	end)

	return items, baseCookSum, finalCookSum, stations
end

local function recomputeQueueDeadlines(state)
	local now = os.clock()
	local cumulative = 0
	local patienceMultiplier = 1
	if PlayerService.GetServedCount(state.player) < 1 then
		patienceMultiplier = Config.Customers.TutorialPatienceMultiplier or 1
	end

	if state.currentAtRegister and not state.currentOrder then
		local c = state.clients[state.currentAtRegister]
		local base = (c and c.plannedBaseCook) or 0
		cumulative += TAKE_ORDER_WINDOW + base
	elseif state.currentOrder and not state.currentOrder.ready then
		cumulative += (state.currentOrder.baseCookTime or 0)
	end

	for index = 1, state.numSpots do
		local clientId = state.spotOccupant[index]
		local client = clientId and state.clients[clientId]
		if client then
			local eta = cumulative + QUEUE_BUFFER
			local patience = math.clamp(eta * patienceMultiplier, QUEUE_MIN, QUEUE_MAX)
			client.queueDeadlineAt = now + patience

			local base = client.plannedBaseCook or 0
			cumulative += TAKE_ORDER_WINDOW + base
			print(string.format("[QueueETA] clientId=%s spot=%d patience=%.2f", tostring(clientId), index, patience))
		end
	end
end

local function logMenuClosed(state)
	if not Config.Server.DebugMode then
		return
	end
	if state._menuClosedLogged then
		return
	end

	state._menuClosedLogged = true

	local unlocked = PlayerService.GetUnlockedFoods(state.player) or {}
	local enabled = PlayerService.GetEnabledFoods(state.player) or {}
	local unlockedCount = 0
	local enabledCount = 0
	local enabledKeys = {}

	for foodId in pairs(unlocked) do
		unlockedCount += 1
	end

	for foodId in pairs(enabled) do
		enabledCount += 1
		table.insert(enabledKeys, foodId)
	end

	table.sort(enabledKeys)
	local shown = {}
	for index = 1, math.min(10, #enabledKeys) do
		shown[index] = enabledKeys[index]
	end

	warn(string.format(
		"[MenuClosedDebug] unlocked=%d enabled=%d enabledKeys=%s",
		unlockedCount,
		enabledCount,
		table.concat(shown, ",")
	))
end

local function moveClientToEndAndDestroyAsync(state, clientModel)
	if not clientModel then
		return
	end
	local pos = getSpotPosition(state.endPoint)
	if not pos then
		clientModel:Destroy()
		return
	end
	print(string.format("[ExitAsync] moving client model=%s", clientModel.Name))
	task.spawn(function()
		moveToAndConfirm(clientModel, pos, 2.0, 8)
		if clientModel and clientModel.Parent then
			clientModel:Destroy()
			print(string.format("[ExitAsync] destroyed model=%s", clientModel.Name))
		end
	end)
end

local function resetInteraction(state)
	state.currentOrder = nil
	state.currentAtRegister = nil
	state.registerWaitStartAt = nil
	setCashPrompt(state, "DISABLED")
	setStationPrompts(state)
end

local function isOrderPointClear(state, radius)
	local pos = getSpotPosition(state.orderPoint)
	if not pos then
		return true
	end
	radius = radius or 4.0
	for _, model in ipairs(state.clientsFolder:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("OwnerUserId") == state.player.UserId then
			local root = getClientRoot(model)
			if root and planarDistance(root.Position, pos) <= radius then
				return false
			end
		end
	end
	return true
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

	recomputeQueueDeadlines(state)
	return true
end

local function shiftQueueForward(state)
	for index = 1, state.numSpots - 1 do
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
	recomputeQueueDeadlines(state)
end

local function spawnClient(state)
	local template = ServerStorage:FindFirstChild("ClientTemplate")
	if not template then
		warn("[ClientSystem] ClientTemplate missing")
		return
	end

	local freeSpot = nil
	for index = 1, state.numSpots do
		if state.spotOccupant[index] == nil then
			freeSpot = index
			break
		end
	end

	if not freeSpot then
		return
	end

	local items, baseCookSum, finalCookSum, stations = computePlannedOrder(state)
	if not items or next(items) == nil then
		if Config.Server.DebugMode then
			warn("[MenuClosed] no enabled foods available; skipping spawn")
			logMenuClosed(state)
		end
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

	local client = state.clients[clientId]
	client.plannedItems = items
	client.plannedBaseCook = baseCookSum
	client.plannedFinalCook = finalCookSum
	client.plannedStations = stations
	client.queueDeadlineAt = nil
	client.takeDeadlineAt = nil

	if Config.Server.DebugMode then
		local stationList = {}
		for station in pairs(stations) do
			table.insert(stationList, station)
		end
		table.sort(stationList)
		print(string.format(
			"[PlannedOrder] clientId=%s base=%.2f final=%.2f stations=%s",
			tostring(clientId),
			baseCookSum,
			finalCookSum,
			table.concat(stationList, ",")
		))
	end

	print(string.format("[Spawn] player=%s clientId=%s queueSize=%d/%d", state.player.UserId, clientId, countQueue(state), state.numSpots))
	assignClientToSpot(state, clientId, freeSpot)
	logOccupancy(state)
	updateBusinessStats(state)
end

local function removeClientFromQueue(state, clientId, reason)
	local client = state.clients[clientId]
	if not client then
		return
	end

	local spotIndex = state.clientSpotIndex[clientId]
	if spotIndex then
		state.spotOccupant[spotIndex] = nil
		state.clientSpotIndex[clientId] = nil
	end

	print(string.format("[QueueExit] clientId=%s reason=%s", clientId, reason))
	local model = client.model
	state.clients[clientId] = nil
	shiftQueueForward(state)
	if model then
		moveClientToEndAndDestroyAsync(state, model)
	end
end

local function removeClientAtRegister(state, reason)
	local clientId = state.currentAtRegister
	if not clientId then
		return
	end

	local client = state.clients[clientId]
	local model = client and client.model
	if client then
		print(string.format("[RegisterExit] clientId=%s reason=%s", clientId, reason))
		state.clients[clientId] = nil
	end

	resetInteraction(state)
	updateBusinessStats(state)
	recomputeQueueDeadlines(state)
	if model then
		moveClientToEndAndDestroyAsync(state, model)
	end
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

	if not isOrderPointClear(state, 4.0) then
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
			if frontClient then
				frontClient.takeDeadlineAt = os.clock() + TAKE_ORDER_WINDOW
			end
			print("[PromoteToRegister] reached orderPoint, freed Spot_1")
			print("[HOWTO] Клиент у кассы. Нажми Take Order на CashRegister.")
			setCashPrompt(state, "TAKE")
			setStationPrompts(state)
			shiftQueueForward(state)
		else
			print("[PromoteToRegister] failed reach orderPoint, will retry")
			state.currentAtRegister = nil
			frontClient.state = "Queue"
			setCashPrompt(state, "DISABLED")
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

	local client = state.clients[clientId]
	local items = client and client.plannedItems
	local baseCookSum = client and client.plannedBaseCook
	local finalCookSum = client and client.plannedFinalCook
	local stations = client and client.plannedStations

	if not items then
		items, baseCookSum, finalCookSum, stations = computePlannedOrder(state)
	end

	if not items or next(items) == nil then
		if Config.Server.DebugMode then
			warn("[MenuClosed] no enabled foods available; cannot create order")
			logMenuClosed(state)
		end
		return
	end

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
		items = items,
		remainingUnits = buildRemainingUnits(items),
		stations = stations or {},
		baseCookTime = baseCookSum or order.cookTime or 0,
		cookTime = finalCookSum or order.cookTime,
		deadlineAt = os.clock() + math.clamp((baseCookSum or 0) + ORDER_BUFFER, ORDER_MIN, ORDER_MAX),
		price = order.price,
	}

	local stationType = nil
	if stations then
		local stationList = {}
		for station in pairs(stations) do
			table.insert(stationList, station)
		end
		table.sort(stationList)
		if #stationList == 1 then
			stationType = stationList[1]
		elseif #stationList > 1 then
			stationType = "MIXED"
		end
	end

	print(string.format("[Order] created player=%s clientId=%s orderId=%s", state.player.UserId, clientId, order.id))
	if stationType then
		print(string.format("[HOWTO] Заказ создан: station=%s. Нажми %s.", stationType, stationType))
	else
		print("[HOWTO] Заказ создан.")
	end
	setCashPrompt(state, "COOKING")
	setStationPrompts(state)
	if client then
		client.takeDeadlineAt = nil
	end

	print(string.format(
		"[OrderTiming] clientId=%s base=%.2f final=%.2f deadlineIn=%.2f",
		tostring(clientId),
		(state.currentOrder.baseCookTime or 0),
		(state.currentOrder.cookTime or 0),
		(state.currentOrder.deadlineAt - os.clock())
	))

	recomputeQueueDeadlines(state)

	sendCashRegister(state, {
		v = 1,
		state = "ORDER_CREATED",
		clientId = clientId,
		orderId = order.id,
		items = order.items,
		stationType = stationType,
		baseCookTime = state.currentOrder.baseCookTime,
		cookTime = state.currentOrder.cookTime,
		deadlineAt = state.currentOrder.deadlineAt,
	})
end

local function completeOrder(state)
	local order = state.currentOrder
	if not order then
		return
	end

	local clientId = state.currentAtRegister
	local client = clientId and state.clients[clientId]
	local model = client and client.model

	OrderService.CompleteOrder(order.orderId)
	PlayerService.AddMoney(state.player, order.price or 0)
	state.servedCount += 1
	PlayerService.IncrementServedCount(state.player)

	print(string.format("[Order] completed player=%s orderId=%s", state.player.UserId, order.orderId))

	resetInteraction(state)
	updateBusinessStats(state)
	recomputeQueueDeadlines(state)

	if clientId then
		state.clients[clientId] = nil
	end
	if model then
		moveClientToEndAndDestroyAsync(state, model)
	end
end

local function failOrder(state, reason)
	local order = state.currentOrder
	if not order then
		return
	end

	local clientId = state.currentAtRegister
	local client = clientId and state.clients[clientId]
	local model = client and client.model

	OrderService.FailOrder(order.orderId, reason)
	print(string.format("[Order] failed player=%s orderId=%s reason=%s", state.player.UserId, order.orderId, reason))

	sendCashRegister(state, {
		v = 1,
		state = "FAILED",
		reason = reason,
		orderId = order.orderId,
	})

	resetInteraction(state)
	updateBusinessStats(state)
	recomputeQueueDeadlines(state)
	if clientId then
		state.clients[clientId] = nil
	end
	if model then
		moveClientToEndAndDestroyAsync(state, model)
	end
end

local function startCooking(state, stationType)
	local order = state.currentOrder
	if not order then
		return
	end

	if order.ready then
		return
	end

	local foodId = pickNextFoodForStation(order, stationType)
	if not foodId then
		return
	end

	order.remainingUnits[foodId] = (order.remainingUnits[foodId] or 1) - 1
	if order.remainingUnits[foodId] <= 0 then
		order.remainingUnits[foodId] = nil
	end

	local remainingTotal = 0
	for _, qty in pairs(order.remainingUnits) do
		remainingTotal += qty
	end

	if Config.Server.DebugMode then
		print(string.format(
			"[CookUnit] station=%s foodId=%s remainingTotal=%d",
			tostring(stationType),
			tostring(foodId),
			remainingTotal
		))
	end

	if remainingTotal <= 0 then
		order.ready = true
		order.state = "READY"
		print(string.format("[Cook] ready player=%s orderId=%s", state.player.UserId, order.orderId))
		print("[HOWTO] Блюдо готово. Нажми Give Order на CashRegister.")
		setStationPrompts(state)
		setCashPrompt(state, "GIVE")

		sendCashRegister(state, {
			v = 1,
			state = "READY",
			orderId = order.orderId,
		})
	else
		setStationPrompts(state)
	end
end

local function bindPrompts(state)
	local ownerId = state.player.UserId

	local cashPrompt = state.cashPrompt
	if cashPrompt then
		cashPrompt.Triggered:Connect(function(triggerPlayer)
			if triggerPlayer.UserId ~= ownerId then
				warn("[CashRegister] not owner")
				return
			end
			if not state.currentAtRegister then
				return
			end
			if not state.currentOrder then
				createOrder(state)
				return
			end
			if state.currentOrder.ready then
				completeOrder(state)
			end
		end)
	else
		warn("[ClientSystem] CashRegister prompt missing")
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
	if os.clock() >= state.nextSpawnAt and countQueue(state) < state.numSpots then
		spawnClient(state)
		state.nextSpawnAt = os.clock() + math.random(SPAWN_MIN, SPAWN_MAX)
	end

	promoteToRegister(state)

	if state.currentAtRegister ~= nil and state.currentOrder == nil then
		local currentClient = state.clients[state.currentAtRegister]
		local deadline = currentClient and currentClient.takeDeadlineAt
		if deadline and os.clock() > deadline then
			print("[RegisterTimeout] client waited too long for Take Order")
			removeClientAtRegister(state, "take_timeout")
		end
	end

	for index = 1, state.numSpots do
		local clientId = state.spotOccupant[index]
		local client = clientId and state.clients[clientId]
		if client and client.state == "Queue" and client.queueDeadlineAt then
			if os.clock() > client.queueDeadlineAt then
				removeClientFromQueue(state, clientId, "queue_timeout")
			end
		end
	end

	local order = state.currentOrder
	if order and os.clock() > order.deadlineAt and not order.ready then
		failOrder(state, "order_timeout")
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
	local cashPrompt = cashPrompts[1]

	local state = {
		player = player,
		business = business,
		clientsFolder = business.clientsFolder,
		spawnPoint = business.spawnPoint,
		endPoint = business.endPoint,
		orderPoint = business.orderPoint,
		queueSpots = sortedSpots,
		numSpots = #sortedSpots,
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
		cashPrompt = cashPrompt,
		registerWaitStartAt = nil,
		active = true,
	}

	bindPrompts(state)
	setCashPrompt(state, "DISABLED")
	setStationPrompts(state)
	Active[player] = state
	debugMenuSnapshotOnce(state)

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
