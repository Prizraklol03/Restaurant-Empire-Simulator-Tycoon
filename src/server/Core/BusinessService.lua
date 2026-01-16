-- BusinessService.lua
-- Spawns and validates per-player business instances

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local PlotService = require(game.ServerScriptService.Core.PlotService)

local BusinessService = {}

local businessesFolder
local activeBusinesses = {}

local function getBusinessesFolder()
	if businessesFolder and businessesFolder.Parent then
		return businessesFolder
	end

	businessesFolder = Workspace:FindFirstChild("Businesses")
	if not businessesFolder then
		businessesFolder = Instance.new("Folder")
		businessesFolder.Name = "Businesses"
		businessesFolder.Parent = Workspace
	end

	return businessesFolder
end

local function gatherQueueSpots(queueFolder)
	local spots = {}
	for _, child in ipairs(queueFolder:GetChildren()) do
		local index = tonumber(string.match(child.Name, "^Spot_(%d+)$"))
		if index then
			table.insert(spots, { index = index, part = child })
		end
	end

	table.sort(spots, function(a, b)
		return a.index < b.index
	end)

	local result = {}
	for _, entry in ipairs(spots) do
		table.insert(result, entry.part)
	end

	return result
end

local function findPrompts(root)
	local prompts = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			table.insert(prompts, descendant)
		end
	end
	return prompts
end

local function pickPromptByName(prompts, name)
	for _, prompt in ipairs(prompts) do
		if prompt.Name == name then
			return prompt
		end
	end

	return prompts[1]
end

function BusinessService.CreateBusinessForPlayer(player)
	local plot = PlotService.AcquirePlot(player)
	if not plot then
		warn("[BusinessService] No available plot for player", player.UserId)
		return nil
	end

	local template = ServerStorage:FindFirstChild("KioskTemplate")
	if not template then
		warn("[BusinessService] KioskTemplate missing in ServerStorage")
		PlotService.ReleasePlot(player)
		return nil
	end

	local businessesRoot = getBusinessesFolder()

	local kiosk = template:Clone()
	kiosk.Name = "Kiosk_" .. tostring(player.UserId)
	kiosk:SetAttribute("OwnerUserId", player.UserId)
	kiosk.Parent = businessesRoot

	local plotCf, plotSize = plot:GetBoundingBox()
	local kioskCf, kioskSize = kiosk:GetBoundingBox()
	local plotTopY = plotCf.Position.Y + (plotSize.Y / 2)
	local kioskHalfY = kioskSize.Y / 2
	local targetY = plotTopY + kioskHalfY + 0.05

	local pivot = plot:GetPivot()
	local _, yaw, _ = pivot:ToOrientation()
	local targetPos = Vector3.new(plotCf.Position.X, targetY, plotCf.Position.Z)
	local targetCf = CFrame.new(targetPos) * CFrame.Angles(0, yaw, 0)

	for _, descendant in ipairs(kiosk:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	print(("[BusinessSpawn] plot=%s plotTopY=%.2f kioskSizeY=%.2f targetY=%.2f"):format(plot.Name, plotTopY, kioskSize.Y, targetY))
	kiosk:PivotTo(targetCf)

	local clientsFolder = Instance.new("Folder")
	clientsFolder.Name = "Clients"
	clientsFolder.Parent = kiosk

	local serviceFolder = kiosk:FindFirstChild("Service")
	local flowFolder = kiosk:FindFirstChild("ClientFlow")
	if not serviceFolder or not flowFolder then
		warn("[BusinessService] KioskTemplate missing Service or ClientFlow")
		kiosk:Destroy()
		PlotService.ReleasePlot(player)
		return nil
	end

	local cashRegister = serviceFolder:FindFirstChild("CashRegister")
	local drinkMachine = serviceFolder:FindFirstChild("DrinkMachine")
	local grill = serviceFolder:FindFirstChild("Grill")

	local queueFolder = flowFolder:FindFirstChild("Queue")
	local spawnPoint = flowFolder:FindFirstChild("ClientSpawn")
	local endPoint = flowFolder:FindFirstChild("ClientEnd")
	local orderPoint = flowFolder:FindFirstChild("OrderPoint")

	if not (cashRegister and drinkMachine and grill and queueFolder and spawnPoint and endPoint and orderPoint) then
		warn("[BusinessService] KioskTemplate missing required parts")
		kiosk:Destroy()
		PlotService.ReleasePlot(player)
		return nil
	end

	local cashPrompts = findPrompts(cashRegister)
	local grillPrompts = findPrompts(grill)
	local drinkPrompts = findPrompts(drinkMachine)

	if #cashPrompts == 0 or #grillPrompts == 0 or #drinkPrompts == 0 then
		warn("[BusinessService] Missing ProximityPrompt on service stations")
		kiosk:Destroy()
		PlotService.ReleasePlot(player)
		return nil
	end

	local queueSpots = gatherQueueSpots(queueFolder)
	if #queueSpots == 0 then
		warn("[BusinessService] Queue has no Spot_N parts")
		kiosk:Destroy()
		PlotService.ReleasePlot(player)
		return nil
	end

	local business = {
		player = player,
		kiosk = kiosk,
		plot = plot,
		clientsFolder = clientsFolder,
		spawnPoint = spawnPoint,
		endPoint = endPoint,
		orderPoint = orderPoint,
		queueSpots = queueSpots,
		cashRegisterPrompts = cashPrompts,
		grillPrompts = grillPrompts,
		drinkPrompts = drinkPrompts,
	}

	activeBusinesses[player] = business
	return business
end

function BusinessService.GetBusiness(player)
	return activeBusinesses[player]
end

function BusinessService.DestroyBusinessForPlayer(player)
	local business = activeBusinesses[player]
	if not business then
		PlotService.ReleasePlot(player)
		return
	end

	if business.kiosk and business.kiosk.Parent then
		business.kiosk:Destroy()
	end

	activeBusinesses[player] = nil
	PlotService.ReleasePlot(player)
end

return BusinessService
