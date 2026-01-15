--[[
	ClientAI.lua

	РОЛЬ:
	- Исполнитель команд движения NPC
	- Источник событий о достижении точек

	ЗАПРЕЩЕНО:
	- принимать решения
	- работать с таймерами
	- знать про очередь / кассу / заказы
	- уходить самостоятельно

	Источник истины:
	- StartClientSystem
	- Контракты 3.1
]]

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local EventBus = require(game.ServerScriptService.Core.EventBus)

local ClientAI = {}
ClientAI.__index = ClientAI

---------------------------------------------------------------------
-- CONSTRUCTOR
---------------------------------------------------------------------

function ClientAI.new(model, player)
	assert(model, "[ClientAI] model is required")
	assert(player, "[ClientAI] player is required")

	local self = setmetatable({}, ClientAI)

	self.model = model
	self.player = player

	self.humanoid = model:WaitForChild("Humanoid")
	self.root = model:WaitForChild("HumanoidRootPart")

	self.clientId = model:GetAttribute("ClientId")
	if not self.clientId then
		self.clientId = game:GetService("HttpService"):GenerateGUID(false)
		model:SetAttribute("ClientId", self.clientId)
	end

	-- runtime
	self._currentMoveToken = 0
	self._alive = true

	return self
end

---------------------------------------------------------------------
-- PUBLIC API (используется StartClientSystem / QueueService)
---------------------------------------------------------------------

function ClientAI:GetClientId()
	return self.clientId
end

-- Движение к Spot_N (очередь)
function ClientAI:GoToSpot(spotPart, spotIndex)
	self:_moveTo(
		spotPart.Position,
		function()
			EventBus.Fire("NPC_REACHED_SPOT", {
				player = self.player,
				clientId = self.clientId,
				spotIndex = spotIndex,
			})
		end
	)
end

-- Движение к кассе
function ClientAI:GoToRegister(orderPoint)
	self:_moveTo(
		orderPoint.Position,
		function()
			EventBus.Fire("NPC_REACHED_REGISTER", {
				player = self.player,
				clientId = self.clientId,
				npc = self.model,
			})
		end
	)
end

-- Уход из бизнеса
function ClientAI:RequestExit(exitPoint, reason)
	if not self._alive then
		return
	end

	self._alive = false

	self:_moveTo(exitPoint.Position, function()
		-- Здесь НЕ fire event — выход контролируется StartClientSystem
		self.model:Destroy()
	end)
end

---------------------------------------------------------------------
-- INTERNAL: MOVEMENT
---------------------------------------------------------------------

function ClientAI:_moveTo(targetPosition, onReached)
	self._currentMoveToken += 1
	local token = self._currentMoveToken

	local path = PathfindingService:CreatePath()
	path:ComputeAsync(self.root.Position, targetPosition)

	local waypoints = path:GetWaypoints()
	if #waypoints == 0 then
		return
	end

	task.spawn(function()
		for _, waypoint in ipairs(waypoints) do
			if token ~= self._currentMoveToken or not self._alive then
				return
			end

			self.humanoid:MoveTo(waypoint.Position)
			self.humanoid.MoveToFinished:Wait()
		end

		if token ~= self._currentMoveToken or not self._alive then
			return
		end

		if onReached then
			onReached()
		end
	end)
end

---------------------------------------------------------------------

return ClientAI
