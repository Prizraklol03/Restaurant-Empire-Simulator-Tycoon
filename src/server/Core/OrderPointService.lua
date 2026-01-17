-- OrderPointService.lua
-- Minimal state tracker for order point occupancy

local Players = game:GetService("Players")

local OrderPointService = {}

OrderPointService.States = {
	EMPTY = "EMPTY",
	CLIENT_ARRIVED = "CLIENT_ARRIVED",
	ORDER_ACCEPTED = "ORDER_ACCEPTED",
}

local playerState = {}

local function setState(player, state)
	playerState[player] = state
end

function OrderPointService.InitPlayer(player)
	setState(player, OrderPointService.States.EMPTY)
end

function OrderPointService.GetState(player)
	return playerState[player] or OrderPointService.States.EMPTY
end

function OrderPointService.ClientArrived(player, _brain)
	setState(player, OrderPointService.States.CLIENT_ARRIVED)
end

function OrderPointService.OrderAccepted(player, _brain, _orderId)
	setState(player, OrderPointService.States.ORDER_ACCEPTED)
end

function OrderPointService.ClientExit(player)
	setState(player, OrderPointService.States.EMPTY)
end

function OrderPointService.RemovePlayer(player)
	playerState[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	playerState[player] = nil
end)

return OrderPointService
