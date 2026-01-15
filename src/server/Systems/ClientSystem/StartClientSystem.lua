--[[
	StartClientSystem.lua

	ЕДИНСТВЕННЫЙ ОРКЕСТРАТОР ЖИЗНИ NPC

	Источник истины:
	- Config.lua (ТОЛЬКО ТВОЙ, КОТОРЫЙ ТЫ СКИНУЛ)
	- Контракты 3.0.txt
	- Блок-схема Client Flow

	ЗАПРЕЩЕНО:
	- таймеры спавна
	- логика в ClientAI
	- логика в QueueService
	- доступ к OrderService минуя события
]]

---------------------------------------------------------------------
-- DEPENDENCIES
---------------------------------------------------------------------

local ServerStorage = game:GetService("ServerStorage")

local Config = require(game.ServerScriptService.Core.Config)
local PlayerService = require(game.ServerScriptService.Core.PlayerService)
local OrderService = require(game.ServerScriptService.Core.OrderService)
local OrderPointService = require(game.ServerScriptService.Core.OrderPointService)
local EventBus = require(game.ServerScriptService.Core.EventBus)

local ClientSystemFolder = script.Parent
local Modules = ClientSystemFolder:WaitForChild("Modules")

local ClientAI = require(Modules:WaitForChild("ClientAI"))
local QueueService = require(Modules:WaitForChild("QueueService"))
local ClientRegistry = require(ClientSystemFolder:WaitForChild("ClientRegistry"))

---------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------

local StartClientSystem = {}

---------------------------------------------------------------------
-- MANAGER
---------------------------------------------------------------------

local Manager = {}
Manager.__index = Manager

---------------------------------------------------------------------
-- CONSTRUCTOR
---------------------------------------------------------------------

function Manager.new(player, businessModel)
	local self = setmetatable({}, Manager)

	-----------------------------------------------------------------
	-- CORE REFERENCES
	-----------------------------------------------------------------

	self.player = player
	self.businessModel = businessModel
	self.alive = true

	-----------------------------------------------------------------
	-- SCENE CONTRACT (ЖЁСТКИЙ)
	-----------------------------------------------------------------

	local flow = businessModel:WaitForChild("ClientFlow")

	self.spawnPoint = flow:WaitForChild("ClientSpawn")
	self.orderPoint = flow:WaitForChild("OrderPoint")
	self.exitPoint = flow:WaitForChild("ClientEnd")

	self.cashRegister = businessModel:FindFirstChild("CashRegister", true)
	assert(self.cashRegister, "[ClientSystem] CashRegister not found")

	self.currentClientValue = self.cashRegister:FindFirstChild("CurrentClient")
	assert(
		self.currentClientValue and self.currentClientValue:IsA("ObjectValue"),
		"[ClientSystem] CashRegister.CurrentClient (ObjectValue) is missing"
	)

	-----------------------------------------------------------------
	-- CONFIG (ЕДИНСТВЕННЫЙ ИСТОЧНИК)
	-----------------------------------------------------------------

	local profile = PlayerService:GetProfile(player)
	local level = profile and profile.BusinessLevel or 1

	self.locationCfg = Config.GetLocationConfig(level)

	self.maxWaitTime = Config.Customers.MaxWaitTime
	self.maxOrderProcessTime = Config.Customers.MaxOrderProcessTime
	self.registerRadius = Config.Customers.RegisterRadius

	self.npcTemplateName = Config.Customers.Models[1]

	-----------------------------------------------------------------
	-- STATE
	-----------------------------------------------------------------

	self.queue = QueueService.new(businessModel)

	self.npcs = {} -- clientId -> npcData
	self.activeRegisterClientId = nil

	-----------------------------------------------------------------
	-- INIT FSM
	-----------------------------------------------------------------

	OrderPointService.InitPlayer(player)

	-----------------------------------------------------------------
	-- EVENTS & START
	-----------------------------------------------------------------

	self:_bindEvents()
	self:_trySpawnNpc() -- первая попытка

	return self
end

---------------------------------------------------------------------
-- SPAWN LOGIC (EVENT-DRIVEN)
---------------------------------------------------------------------

function Manager:_canSpawnNpc()
	if not self.alive then
		return false
	end

	return Config.CanSpawnClient(
		self.locationCfg.Level,
		self.queue:GetSize()
	)
end

function Manager:_trySpawnNpc()
	if not self:_canSpawnNpc() then
		return
	end

	local spawnRate = Config.GetClientSpawnRate(
		self.locationCfg.Level,
		PlayerService:GetUpgrades(self.player)
	)

	if math.random() > spawnRate then
		return
	end

	-- Создание NPC
	local template = ServerStorage:WaitForChild(self.npcTemplateName)
	local npcModel = template:Clone()
	npcModel.Parent = self.businessModel
	npcModel:PivotTo(self.spawnPoint.CFrame)

	-- Назначаем имя клиенту
	local names = Config.Customers.Names
	local clientName = names[math.random(1, #names)]
	npcModel:SetAttribute("ClientName", clientName)

	-- Создаём мозг
	local brain = ClientAI.new(npcModel, self.player)
	ClientRegistry.Register(npcModel, brain)

	local clientId = brain:GetClientId()

	-- Инициализация состояния NPC
	self.npcs[clientId] = {
		brain = brain,

		queueWaitStart = nil,      -- стартует при первом достижении Spot
		orderProcessStart = nil,   -- стартует при принятии заказа

		orderAccepted = false,
		exiting = false,
	}

	-- Вход в очередь
	self.queue:Join(brain)
end


---------------------------------------------------------------------
-- MAIN TICK (TIMEOUTS + FLOW)
---------------------------------------------------------------------

function Manager:_tick()
	local now = os.clock()

	for clientId, npc in pairs(self.npcs) do
		if npc.exiting then
			continue
		end

		-- ОЖИДАНИЕ В ОЧЕРЕДИ (до принятия заказа)
		if not npc.orderAccepted and npc.queueWaitStart then
			if now - npc.queueWaitStart >= Config.Customers.MaxWaitTime then
				self:_requestExit(clientId, "QUEUE_TIMEOUT")
			end
		end

		-- ОБРАБОТКА ЗАКАЗА
		if npc.orderProcessStart then
			if now - npc.orderProcessStart >= Config.Customers.MaxOrderProcessTime then
				self:_requestExit(clientId, "ORDER_PROCESS_TIMEOUT")
			end
		end
	end

	-- Проверяем, можно ли продвинуть очередь
	self:_tryMoveFrontToRegister()
end


---------------------------------------------------------------------
-- QUEUE → REGISTER
---------------------------------------------------------------------

function Manager:_tryMoveFrontToRegister()
	if self.activeRegisterClientId then
		return
	end

	if OrderPointService.GetState(self.player) ~= OrderPointService.States.EMPTY then
		return
	end

	local brain = self.queue:GetFront()
	if not brain then
		return
	end

	self.queue:Leave(brain)

	local clientId = brain:GetClientId()
	self.activeRegisterClientId = clientId

	brain:GoToRegister(self.orderPoint)
	OrderPointService.ClientArrived(self.player, brain)
end

---------------------------------------------------------------------
-- EXIT
---------------------------------------------------------------------

function Manager:_requestExit(clientId, reason)
	local npc = self.npcs[clientId]
	if not npc or npc.exiting then
		return
	end

	npc.exiting = true
	
	self.queue:LeaveByClientId(clientId)

	-- Если NPC был у кассы — освобождаем её
	if self.activeRegisterClientId == clientId then
		self.activeRegisterClientId = nil
		self.currentClientValue.Value = nil
		OrderPointService.ClientExit(self.player)
	end

	npc.brain:RequestExit(self.exitPoint, reason)
	
	self.npcs[clientId] = nil
	self:_trySpawnNpc()
end


---------------------------------------------------------------------
-- EVENT BUS
---------------------------------------------------------------------

function Manager:_bindEvents()

	EventBus.Connect("NPC_REACHED_REGISTER", function(data)
		if data.player ~= self.player then return end

		self.currentClientValue.Value = data.npc
	end)

	EventBus.Connect("ORDER_CREATED", function(data)
		if data.player ~= self.player then return end

		local npc = self.npcs[data.clientId]
		if not npc or npc.exiting then return end

		npc.orderAccepted = true
		npc.orderProcessStart = os.clock()

		-- Очередь закончилась
		npc.queueWaitStart = nil

		OrderPointService.OrderAccepted(
			self.player,
			data.npcBrain,
			data.orderId
		)
	end)


	EventBus.Connect("OrderServed", function(data)
		if data.player ~= self.player then return end
		self:_requestExit(data.clientId, "SERVED")
	end)

	EventBus.Connect("NPC_REACHED_SPOT", function(data)
		if data.player ~= self.player then return end

		local npc = self.npcs[data.clientId]
		if not npc or npc.exiting then return end

		-- Первый раз встал в очередь → запускаем таймер ожидания
		if npc.queueWaitStart == nil then
			npc.queueWaitStart = os.clock()
		end
	end)
end

---------------------------------------------------------------------
-- STOP
---------------------------------------------------------------------

function Manager:Stop()
	self.alive = false

	for clientId, npc in pairs(self.npcs) do
		npc.brain:RequestExit(self.exitPoint, "FORCE_BUSINESS_REMOVED")
		self.queue:LeaveByClientId(clientId)
	end

	self.npcs = {}
	self.activeRegisterClientId = nil
	self.currentClientValue.Value = nil

	OrderPointService.RemovePlayer(self.player)
end

---------------------------------------------------------------------
-- ENTRY POINT
---------------------------------------------------------------------

function StartClientSystem.Start(player, businessModel)
	local manager = Manager.new(player, businessModel)

	-- главный тик
	task.spawn(function()
		while manager.alive do
			manager:_tick()
			task.wait(0.2)
		end
	end)

	return {
		Stop = function()
			manager:Stop()
		end
	}
end

return StartClientSystem
