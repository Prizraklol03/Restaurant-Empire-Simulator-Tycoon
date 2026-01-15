--[[
	QueueService.lua (v3.0)

	ТУПОЙ менеджер очереди.
	Источник истины: Контракты 3.0

	QueueService:
	- хранит порядок NPC
	- назначает Spot_N
	- двигает NPC по Spots при изменениях очереди (auto-advance)

	QueueService НЕ:
	- принимает решения (спавн/уход/таймеры)
	- знает про кассу, заказы, OrderPoint
	- знает бизнес-логику
]]

local QueueService = {}
QueueService.__index = QueueService

---------------------------------------------------------------------
-- INTERNAL HELPERS
---------------------------------------------------------------------

local function _isSpotName(name)
	-- Spot_1 .. Spot_N
	return typeof(name) == "string" and name:match("^Spot_%d+$") ~= nil
end

local function _spotIndexFromName(name)
	local n = name:match("^Spot_(%d+)$")
	return n and tonumber(n) or nil
end

local function _sortSpots(a, b)
	return a.index < b.index
end

---------------------------------------------------------------------
-- CONSTRUCTOR
---------------------------------------------------------------------

function QueueService.new(businessModel)
	assert(businessModel, "[QueueService] businessModel is required")

	local self = setmetatable({}, QueueService)

	-- Scene contract: businessModel.ClientFlow.Queue contains Spot_1..Spot_N
	local flow = businessModel:WaitForChild("ClientFlow")
	local queueFolder = flow:WaitForChild("Queue")

	self._businessModel = businessModel
	self._queueFolder = queueFolder

	-- Load spots dynamically (supports Kiosk/Cafe/Restaurant)
	self._spots = {}
	for _, child in ipairs(queueFolder:GetChildren()) do
		if child:IsA("BasePart") and _isSpotName(child.Name) then
			local idx = _spotIndexFromName(child.Name)
			if idx then
				table.insert(self._spots, { index = idx, part = child })
			end
		end
	end

	table.sort(self._spots, _sortSpots)

	assert(#self._spots > 0, "[QueueService] No Spot_N parts found in ClientFlow.Queue")

	-- Runtime state
	-- _order: array of clientIds in queue order (front = 1)
	-- _map: clientId -> { brain = ..., spotIndex = ... }
	self._order = {}
	self._map = {}

	return self
end

---------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------

function QueueService:GetSize()
	return #self._order
end

function QueueService:GetFront()
	local clientId = self._order[1]
	if not clientId then
		return nil
	end

	local entry = self._map[clientId]
	return entry and entry.brain or nil
end

-- Join queue (assign last spot)
function QueueService:Join(brain)
	assert(brain, "[QueueService] Join(brain) requires brain")

	local clientId = brain:GetClientId()
	assert(clientId ~= nil, "[QueueService] brain:GetClientId() returned nil")

	-- already in queue -> ignore (idempotent)
	if self._map[clientId] then
		return false
	end

	-- capacity = number of spots
	if #self._order >= #self._spots then
		return false
	end

	table.insert(self._order, clientId)

	local spotIndex = #self._order
	self._map[clientId] = {
		brain = brain,
		spotIndex = spotIndex,
	}

	self:_commandMoveToSpot(clientId, spotIndex)
	return true
end

-- Leave queue (remove anywhere), then auto-advance behind
function QueueService:Leave(brain)
	assert(brain, "[QueueService] Leave(brain) requires brain")

	local clientId = brain:GetClientId()
	if clientId == nil then
		return false
	end

	return self:LeaveByClientId(clientId)
end

-- Optional helper (useful for exits/timeouts while npc is still in queue)
function QueueService:LeaveByClientId(clientId)
	local entry = self._map[clientId]
	if not entry then
		return false
	end

	-- find position in order
	local removePos = nil
	for i = 1, #self._order do
		if self._order[i] == clientId then
			removePos = i
			break
		end
	end

	-- if map has it but order doesn't -> clean safely
	if not removePos then
		self._map[clientId] = nil
		return true
	end

	table.remove(self._order, removePos)
	self._map[clientId] = nil

	-- everyone behind shifts forward: i becomes Spot_i
	self:_reassignFrom(removePos)
	return true
end

-- Debug/utility
function QueueService:Contains(clientId)
	return self._map[clientId] ~= nil
end

function QueueService:GetSpotCount()
	return #self._spots
end

---------------------------------------------------------------------
-- INTERNAL: MOVE/ADVANCE
---------------------------------------------------------------------

function QueueService:_reassignFrom(fromPos)
	-- Reassign spot indexes for order[fromPos .. end]
	for pos = fromPos, #self._order do
		local cid = self._order[pos]
		local e = self._map[cid]
		if e then
			e.spotIndex = pos
			self:_commandMoveToSpot(cid, pos)
		end
	end
end

function QueueService:_commandMoveToSpot(clientId, spotIndex)
	local entry = self._map[clientId]
	if not entry then
		return
	end

	local spot = self._spots[spotIndex]
	if not spot then
		-- should never happen due to capacity checks
		return
	end

	local brain = entry.brain
	if not brain then
		return
	end

	-- Contract: QueueService "назначает Spot_N".
	-- Реальное движение исполняет ClientAI (brain).
	-- Мы НЕ ждём достижения спота и НЕ считаем таймеры.
	--
	-- Чтобы не сломаться от названий методов:
	-- поддерживаем несколько вариантов вызова.
	if brain.GoToSpot then
		brain:GoToSpot(spot.part, spotIndex)
	elseif brain.GoToQueueSpot then
		brain:GoToQueueSpot(spot.part, spotIndex)
	elseif brain.SetTargetSpot then
		brain:SetTargetSpot(spot.part, spotIndex)
	else
		error("[QueueService] Brain has no method to move to spot (expected GoToSpot/GoToQueueSpot/SetTargetSpot)")
	end
end

return QueueService
