-- ClientAI.lua
-- Simple movement helper for client NPCs

local ClientAI = {}

local function findHumanoid(model)
	return model and model:FindFirstChildOfClass("Humanoid")
end

function ClientAI.MoveTo(model, worldPosition, timeoutSeconds)
	if not model then
		warn("[ClientAI] MoveTo missing model")
		return false
	end

	local humanoid = findHumanoid(model)
	if not humanoid then
		warn("[ClientAI] MoveTo missing Humanoid")
		return false
	end

	local reached = false
	local finished = false
	local timeout = timeoutSeconds or 8

	local connection
	connection = humanoid.MoveToFinished:Connect(function(success)
		if finished then
			return
		end
		reached = success
		finished = true
		connection:Disconnect()
	end)

	humanoid:MoveTo(worldPosition)

	local startTime = os.clock()
	while not finished do
		if os.clock() - startTime >= timeout then
			finished = true
			reached = false
			if connection.Connected then
				connection:Disconnect()
			end
			break
		end
		task.wait(0.1)
	end

	return reached
end

return ClientAI
