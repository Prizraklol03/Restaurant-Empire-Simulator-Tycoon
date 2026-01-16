local SSS = game:GetService("ServerScriptService")
local Core = SSS:WaitForChild("Core")
local Systems = SSS:WaitForChild("Systems")

local Config = require(Core:WaitForChild("Config"))
local FoodConfig = require(Core:WaitForChild("FoodConfig"))
local SaveService = require(Core:WaitForChild("SaveService"))
local PlayerService = require(Core:WaitForChild("PlayerService"))
local OrderGenerator = require(Core:WaitForChild("OrderGenerator"))
local OrderService = require(Core:WaitForChild("OrderService"))
local RemoteSetup = require(Core:WaitForChild("RemoteSetup"))
local HealthCheck = require(Core:WaitForChild("HealthCheck"))
local RemoteHandlers = require(Core:WaitForChild("RemoteHandlers"))

local ClientSystemFolder = Systems:WaitForChild("ClientSystem")
local StartClientSystem = require(ClientSystemFolder:WaitForChild("StartClientSystem"))

RemoteSetup.EnsureRemotes()
HealthCheck.Run()
RemoteHandlers.Bind()

print("[SERVER] Start OK")
