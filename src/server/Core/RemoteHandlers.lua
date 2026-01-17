-- RemoteHandlers.lua
-- Binds RemoteFunction handlers with basic rate limiting

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local SaveService = require(game.ServerScriptService.Core.SaveService)

local RemoteHandlers = {}

local COOLDOWNS = {
	GetProfile = 0.5,
	GetBusinessStats = 0.5,
	GetGameState = 0.35,
}

local lastInvokeByPlayer = {}

local function checkRateLimit(player, name)
	local now = os.clock()
	local playerMap = lastInvokeByPlayer[player]
	if not playerMap then
		playerMap = {}
		lastInvokeByPlayer[player] = playerMap
	end

	local cooldown = COOLDOWNS[name] or 0
	local last = playerMap[name]
	if last and now - last < cooldown then
		return false
	end

	playerMap[name] = now
	return true
end

local function getSafeSave(player)
	return SaveService.GetSave(player)
end

function RemoteHandlers.Bind()
	local getProfile = Net.GetRemoteFunction("GetProfile")
	local getBusinessStats = Net.GetRemoteFunction("GetBusinessStats")
	local getGameState = Net.GetRemoteFunction("GetGameState")

	getProfile.OnServerInvoke = function(player)
		if not checkRateLimit(player, "GetProfile") then
			return nil
		end

		local profile = getSafeSave(player)
		if not profile then
			profile = SaveService.Load(player)
		end
		return profile
	end

	getBusinessStats.OnServerInvoke = function(player)
		if not checkRateLimit(player, "GetBusinessStats") then
			return nil
		end

		local save = getSafeSave(player)
		if not save then
			return nil
		end

		return {
			Money = save.Money or 0,
			BusinessLevel = save.BusinessLevel or 1,
		}
	end

	getGameState.OnServerInvoke = function(player)
		if not checkRateLimit(player, "GetGameState") then
			return nil
		end

		local save = getSafeSave(player)
		return {
			Money = save and save.Money or 0,
			QueueSize = 0,
			CurrentOrder = "—",
			HasWaiter = false,
		}
	end
end

Players.PlayerRemoving:Connect(function(player)
	lastInvokeByPlayer[player] = nil
end)

return RemoteHandlers
