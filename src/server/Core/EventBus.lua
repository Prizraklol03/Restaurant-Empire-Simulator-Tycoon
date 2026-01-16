-- EventBus.lua
-- Minimal in-memory event bus for server modules

local EventBus = {}

local listeners = {}

local function removeListener(list, callback)
	for index, stored in ipairs(list) do
		if stored == callback then
			table.remove(list, index)
			return
		end
	end
end

function EventBus.Connect(eventName, callback)
	assert(type(eventName) == "string", "[EventBus] eventName must be string")
	assert(type(callback) == "function", "[EventBus] callback must be function")

	listeners[eventName] = listeners[eventName] or {}
	table.insert(listeners[eventName], callback)

	return {
		Disconnect = function()
			local list = listeners[eventName]
			if list then
				removeListener(list, callback)
			end
		end,
	}
end

function EventBus.Fire(eventName, payload)
	local list = listeners[eventName]
	if not list then
		return
	end

	for _, callback in ipairs(list) do
		task.spawn(callback, payload)
	end
end

function EventBus.Clear()
	for key in pairs(listeners) do
		listeners[key] = nil
	end
end

return EventBus
