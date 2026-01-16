local SSS = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Core = SSS:WaitForChild("Core")
local Systems = SSS:WaitForChild("Systems")

local function safeRequire(moduleInstance)
	local ok, result = pcall(require, moduleInstance)
	if not ok then
		error(("Failed to require %s: %s"):format(moduleInstance:GetFullName(), tostring(result)))
	end
	return result
end

local Config = safeRequire(Core:WaitForChild("Config"))
local FoodConfig = safeRequire(Core:WaitForChild("FoodConfig"))
local SaveService = safeRequire(Core:WaitForChild("SaveService"))
local PlayerService = safeRequire(Core:WaitForChild("PlayerService"))
local OrderGenerator = safeRequire(Core:WaitForChild("OrderGenerator"))
local OrderService = safeRequire(Core:WaitForChild("OrderService"))
local BusinessService = safeRequire(Core:WaitForChild("BusinessService"))
local RemoteSetup = safeRequire(Core:WaitForChild("RemoteSetup"))
local HealthCheck = safeRequire(Core:WaitForChild("HealthCheck"))
local RemoteHandlers = safeRequire(Core:WaitForChild("RemoteHandlers"))

local ClientSystemFolder = Systems:WaitForChild("ClientSystem")
local StartClientSystem = safeRequire(ClientSystemFolder:WaitForChild("StartClientSystem"))

local activeSystems = {}

RemoteSetup.EnsureRemotes()
HealthCheck.Run()
RemoteHandlers.Bind()

Players.PlayerAdded:Connect(function(player)
	SaveService.Load(player)
	local business = BusinessService.CreateBusiness(player)
	if business then
		local system = StartClientSystem.Start(player, business)
		activeSystems[player] = system
	else
		warn("[SERVER] Business creation failed for", player.UserId)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local system = activeSystems[player]
	if system and system.Stop then
		system:Stop()
	end

	activeSystems[player] = nil
	BusinessService.RemoveBusiness(player)
	SaveService.Save(player)
	SaveService.Release(player)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		SaveService.Save(player)
	end
end)

print("[SERVER] Start OK")
