local RemoteSetup = require(game.ServerScriptService.Core.RemoteSetup)
local HealthCheck = require(game.ServerScriptService.Core.HealthCheck)
local RemoteHandlers = require(game.ServerScriptService.Core.RemoteHandlers)

RemoteSetup.EnsureRemotes()
HealthCheck.Run()
RemoteHandlers.Bind()

print("[SERVER] Startup complete")
