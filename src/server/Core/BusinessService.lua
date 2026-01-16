-- BusinessService.lua
-- Spawns and validates per-player business instances

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

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
		if child:IsA("BasePart") then
			local index = tonumber(string.match(child.Name, "^Spot_(%d+)$"))
			if index then
				table.insert(spots, { index = index, part = child })
			end
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

local function findPrompt(part)
	if not part then
		return nil
	end
	return part:FindFirstChildOfClass("ProximityPrompt")
end

function BusinessService.CreateBusiness(player)
	local template = ServerStorage:FindFirstChild("KioskTemplate")
	if not template then
		warn("[BusinessService] KioskTemplate missing in ServerStorage")
		return nil
	end

	local businessesRoot = getBusinessesFolder()
	local playerFolder = businessesRoot:FindFirstChild(tostring(player.UserId))
	if not playerFolder then
		playerFolder = Instance.new("Folder")
		playerFolder.Name = tostring(player.UserId)
		playerFolder.Parent = businessesRoot
	end

	for _, child in ipairs(playerFolder:GetChildren()) do
		child:Destroy()
	end

	local kiosk = template:Clone()
	kiosk.Name = "Kiosk"
	kiosk:SetAttribute("OwnerUserId", player.UserId)
	kiosk.Parent = playerFolder

	local clientsFolder = Instance.new("Folder")
	clientsFolder.Name = "Clients"
	clientsFolder.Parent = playerFolder

	local serviceFolder = kiosk:FindFirstChild("Service")
	local flowFolder = kiosk:FindFirstChild("ClientFlow")
	if not serviceFolder or not flowFolder then
		warn("[BusinessService] KioskTemplate missing Service or ClientFlow")
		kiosk:Destroy()
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
		return nil
	end

	local cashPrompt = findPrompt(cashRegister)
	local grillPrompt = findPrompt(grill)
	local drinkPrompt = findPrompt(drinkMachine)

	if not (cashPrompt and grillPrompt and drinkPrompt) then
		warn("[BusinessService] Missing ProximityPrompt on service stations")
		kiosk:Destroy()
		return nil
	end

	local queueSpots = gatherQueueSpots(queueFolder)
	if #queueSpots == 0 then
		warn("[BusinessService] Queue has no Spot_N parts")
		kiosk:Destroy()
		return nil
	end

	local business = {
		player = player,
		kiosk = kiosk,
		clientsFolder = clientsFolder,
		spawnPoint = spawnPoint,
		endPoint = endPoint,
		orderPoint = orderPoint,
		queueSpots = queueSpots,
		cashRegisterPrompt = cashPrompt,
		grillPrompt = grillPrompt,
		drinkPrompt = drinkPrompt,
	}

	activeBusinesses[player] = business
	return business
end

function BusinessService.GetBusiness(player)
	return activeBusinesses[player]
end

function BusinessService.RemoveBusiness(player)
	local business = activeBusinesses[player]
	if not business then
		return
	end

	if business.kiosk and business.kiosk.Parent then
		business.kiosk.Parent:Destroy()
	end

	activeBusinesses[player] = nil
end

return BusinessService
