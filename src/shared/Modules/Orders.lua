-- Orders.lua
-- Хранит активный заказ игрока

local Orders = {}

-- activeOrders[player] = {
--     client = NPC,
--     items = { "Burger", "Drink" },
--     status = "accepted" | "ready"
-- }

local activeOrders = {}

function Orders.HasOrder(player)
	return activeOrders[player] ~= nil
end

function Orders.CreateOrder(player, clientNpc)
	if activeOrders[player] then
		return false
	end

	activeOrders[player] = {
		client = clientNpc,
		items = { "Burger", "Drink" },
		status = "accepted"
	}

	return true
end

function Orders.GetOrder(player)
	return activeOrders[player]
end

function Orders.ClearOrder(player)
	activeOrders[player] = nil
end

return Orders
