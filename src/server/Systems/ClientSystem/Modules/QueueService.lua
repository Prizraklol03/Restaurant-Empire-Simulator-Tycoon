-- QueueService.lua
-- Queue manager for client models and spot assignment

local QueueService = {}
QueueService.__index = QueueService

local function spotIndexFromName(name)
	local match = string.match(name, "^Spot_(%d+)$")
	return match and tonumber(match) or nil
end

local function sortSpots(a, b)
	return a.index < b.index
end

function QueueService.new()
	local self = setmetatable({}, QueueService)
	self._spots = {}
	self._order = {}
	self._entries = {}
	self._onAssign = nil
	return self
end

function QueueService:SetSpots(spotsArray)
	self._spots = {}
	for _, spot in ipairs(spotsArray or {}) do
		if spot and spot:IsA("BasePart") then
			local index = spotIndexFromName(spot.Name) or (#self._spots + 1)
			table.insert(self._spots, { index = index, part = spot })
		end
	end

	table.sort(self._spots, sortSpots)
	self:_emitAssignments()
end

function QueueService:SetOnAssign(callback)
	self._onAssign = callback
end

function QueueService:GetCapacity()
	return #self._spots
end

function QueueService:GetSize()
	return #self._order
end

function QueueService:GetFront()
	return self._order[1]
end

function QueueService:Join(clientModel)
	if not clientModel or self._entries[clientModel] then
		return nil
	end

	if #self._order >= #self._spots then
		return nil
	end

	table.insert(self._order, clientModel)
	self._entries[clientModel] = true

	self:_emitAssignments()
	return #self._order
end

function QueueService:Leave(clientModel)
	if not clientModel or not self._entries[clientModel] then
		return false
	end

	for index, model in ipairs(self._order) do
		if model == clientModel then
			table.remove(self._order, index)
			break
		end
	end

	self._entries[clientModel] = nil
	self:_emitAssignments()
	return true
end

function QueueService:_emitAssignments()
	if not self._onAssign then
		return
	end

	local assignments = {}
	for index, model in ipairs(self._order) do
		local spot = self._spots[index]
		if spot then
			assignments[model] = spot.part
		end
	end

	self._onAssign(assignments)
end

return QueueService
