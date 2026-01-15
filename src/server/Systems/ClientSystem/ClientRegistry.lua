--[[
	ClientRegistry.lua

	РОЛЬ:
	- Глобальный реестр ClientAI (brain)
	- Связка NPC Model ↔ ClientAI

	НЕ:
	- логика
	- события
	- таймеры
	- решения

	Используется:
	- StartClientSystem
	- EventBus handlers (через model)
]]

local ClientRegistry = {}

---------------------------------------------------------------------
-- INTERNAL STORAGE
---------------------------------------------------------------------

-- npcModel -> brain
local modelToBrain = {}

-- clientId -> brain (опционально, но удобно)
local idToBrain = {}

---------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------

-- Регистрирует brain
function ClientRegistry.Register(npcModel, brain)
	assert(npcModel, "[ClientRegistry] npcModel is required")
	assert(brain, "[ClientRegistry] brain is required")

	modelToBrain[npcModel] = brain

	if brain.GetClientId then
		local clientId = brain:GetClientId()
		if clientId then
			idToBrain[clientId] = brain
		end
	end
end

-- Получить brain по модели
function ClientRegistry.GetByModel(npcModel)
	return modelToBrain[npcModel]
end

-- Получить brain по clientId
function ClientRegistry.GetByClientId(clientId)
	return idToBrain[clientId]
end

-- Удаление (вызывать при уничтожении NPC)
function ClientRegistry.Unregister(brain)
	if not brain then
		return
	end

	-- чистим по clientId
	if brain.GetClientId then
		local clientId = brain:GetClientId()
		if clientId then
			idToBrain[clientId] = nil
		end
	end

	-- чистим по модели
	for model, storedBrain in pairs(modelToBrain) do
		if storedBrain == brain then
			modelToBrain[model] = nil
			break
		end
	end
end

-- Полная очистка (например, при Stop())
function ClientRegistry.Clear()
	table.clear(modelToBrain)
	table.clear(idToBrain)
end

---------------------------------------------------------------------

return ClientRegistry
