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
local PlotService = safeRequire(Core:WaitForChild("PlotService"))
local BusinessService = safeRequire(Core:WaitForChild("BusinessService"))
local RemoteSetup = safeRequire(Core:WaitForChild("RemoteSetup"))
local HealthCheck = safeRequire(Core:WaitForChild("HealthCheck"))
local RemoteHandlers = safeRequire(Core:WaitForChild("RemoteHandlers"))

local ClientSystemFolder = Systems:WaitForChild("ClientSystem")
local StartClientSystem = safeRequire(ClientSystemFolder:WaitForChild("StartClientSystem"))

RemoteSetup.EnsureRemotes()
HealthCheck.Run()
HealthCheck.RunStageAudit()
RemoteHandlers.Bind()

Players.PlayerAdded:Connect(function(player)
	SaveService.Load(player)
	local business = BusinessService.CreateBusinessForPlayer(player)
	if business then
		StartClientSystem.StartForPlayer(player, business)
	else
		warn("[SERVER] Business creation failed for", player.UserId)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	StartClientSystem.StopForPlayer(player)
	BusinessService.DestroyBusinessForPlayer(player)
	SaveService.Save(player)
	SaveService.Release(player)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		SaveService.Save(player)
	end
end)

print("[SERVER] Start OK")
