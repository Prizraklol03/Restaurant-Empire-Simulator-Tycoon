-- RemoteSetup.server.lua
-- Ensures remotes exist in ReplicatedStorage

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = {}

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function ensureRemote(parent, name, className)
	local remote = parent:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = parent
	end
	return remote
end

function RemoteSetup.EnsureRemotes()
	local remotesRoot = ensureFolder(ReplicatedStorage, "Remotes")
	local eventsFolder = ensureFolder(remotesRoot, "Events")
	local functionsFolder = ensureFolder(remotesRoot, "Functions")

	ensureRemote(eventsFolder, "UpdateBusinessStats", "RemoteEvent")
	ensureRemote(eventsFolder, "UpdateCashRegisterUI", "RemoteEvent")

	ensureRemote(functionsFolder, "GetBusinessStats", "RemoteFunction")
	ensureRemote(functionsFolder, "GetGameState", "RemoteFunction")
	ensureRemote(functionsFolder, "GetProfile", "RemoteFunction")
end

return RemoteSetup
