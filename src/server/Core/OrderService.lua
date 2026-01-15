-- OrderService.lua FINAL
-- Управление заказами (владелец заказа и таймингов)

local HttpService = game:GetService("HttpService")

local EventBus = require(game.ServerScriptService.Core.EventBus)
local FoodConfig = require(game.ServerScriptService.Core.FoodConfig)

local OrderService = {}

---------------------------------------------------------------------
-- INTERNAL STATE
---------------------------------------------------------------------

local orders = {}

local OrderStatus = {
	CREATED = "CREATED",
	ACCEPTED = "ACCEPTED",
	COMPLETED = "COMPLETED",
	FAILED = "FAILED",
	CANCELLED = "CANCELLED",
}

---------------------------------------------------------------------
-- TIME BALANCE (позже можно вынести в Config)
---------------------------------------------------------------------

local TIME_CONFIG = {
	BaseBuffer = 8,      -- B
	ComplexityFactor = 1.3, -- α
	PerItemBuffer = 2,  -- K
	MinWait = 12,       -- Tmin
	MaxWait = 90,       -- Tmax
}

---------------------------------------------------------------------
-- INTERNAL HELPERS
---------------------------------------------------------------------

local function generateOrderId()
	return HttpService:GenerateGUID(false)
end

local function calculatePrice(items)
	local total = 0

	for foodId, data in pairs(items) do
		local food = FoodConfig.GetFoodById(foodId)
		if food then
			total += food.BasePrice * data.quantity
		end
	end

	return total
end

-- Tcook = сумма BaseCookTime * quantity
local function calculateCookTime(items)
	local total = 0

	for foodId, data in pairs(items) do
		local food = FoodConfig.GetFoodById(foodId)
		if food then
			total += (food.BaseCookTime or 0) * data.quantity
		end
	end

	return total
end

local function clamp(value, min, max)
	return math.max(min, math.min(max, value))
end

local function calculateWaitTime(cookTime, itemCount)
	local cfg = TIME_CONFIG

	local raw =
		cfg.BaseBuffer +
		cfg.ComplexityFactor * cookTime +
		cfg.PerItemBuffer * itemCount

	return clamp(raw, cfg.MinWait, cfg.MaxWait)
end

---------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------

-- items = { Burger = { quantity = 2 }, Coffee = { quantity = 1 } }
function OrderService.CreateOrder(player, items)
	assert(player, "[OrderService] player is required")
	assert(type(items) == "table", "[OrderService] items must be table")

	local orderId = generateOrderId()
	local price = calculatePrice(items)
	local cookTime = calculateCookTime(items)

	local itemCount = 0
	for _ in pairs(items) do
		itemCount += 1
	end

	local waitTime = calculateWaitTime(cookTime, itemCount)
	local now = os.clock()

	local order = {
		id = orderId,
		player = player,

		items = items,
		price = price,

		cookTime = cookTime,
		waitTime = waitTime,
		deadlineAt = now + waitTime,

		status = OrderStatus.CREATED,
		createdAt = now,
		updatedAt = now,
	}

	orders[orderId] = order

	EventBus.Fire("ORDER_CREATED", {
		orderId = orderId,
		player = player,
		items = items,
		price = price,
		waitTime = waitTime,
	})

	return orderId
end

function OrderService.AcceptOrder(orderId)
	local order = orders[orderId]
	if not order then
		return false, "ORDER_NOT_FOUND"
	end

	if order.status ~= OrderStatus.CREATED then
		return false, "INVALID_STATUS"
	end

	order.status = OrderStatus.ACCEPTED
	order.updatedAt = os.clock()

	EventBus.Fire("ORDER_ACCEPTED", {
		orderId = orderId,
		player = order.player,
		deadlineAt = order.deadlineAt,
	})

	return true
end

function OrderService.CompleteOrder(orderId)
	local order = orders[orderId]
	if not order then
		return false, "ORDER_NOT_FOUND"
	end

	if order.status ~= OrderStatus.ACCEPTED then
		return false, "INVALID_STATUS"
	end

	order.status = OrderStatus.COMPLETED
	order.updatedAt = os.clock()

	EventBus.Fire("ORDER_COMPLETED", {
		orderId = orderId,
		player = order.player,
		price = order.price,
	})

	return true
end

function OrderService.FailOrder(orderId, reason)
	local order = orders[orderId]
	if not order then
		return false, "ORDER_NOT_FOUND"
	end

	if order.status == OrderStatus.COMPLETED
		or order.status == OrderStatus.CANCELLED then
		return false, "ORDER_ALREADY_FINISHED"
	end

	order.status = OrderStatus.FAILED
	order.failReason = reason
	order.updatedAt = os.clock()

	EventBus.Fire("ORDER_FAILED", {
		orderId = orderId,
		player = order.player,
		reason = reason,
	})

	return true
end

function OrderService.CancelOrder(orderId, reason)
	local order = orders[orderId]
	if not order then
		return false, "ORDER_NOT_FOUND"
	end

	if order.status == OrderStatus.COMPLETED then
		return false, "ORDER_ALREADY_COMPLETED"
	end

	order.status = OrderStatus.CANCELLED
	order.cancelReason = reason
	order.updatedAt = os.clock()

	EventBus.Fire("ORDER_CANCELLED", {
		orderId = orderId,
		player = order.player,
		reason = reason,
	})

	return true
end

function OrderService.GetOrder(orderId)
	return orders[orderId]
end

function OrderService.GetOrderStatus(orderId)
	local order = orders[orderId]
	return order and order.status or nil
end

function OrderService.ClearPlayerOrders(player)
	for id, order in pairs(orders) do
		if order.player == player then
			orders[id] = nil
		end
	end
end

function OrderService.GetStatuses()
	return OrderStatus
end

---------------------------------------------------------------------

return OrderService
