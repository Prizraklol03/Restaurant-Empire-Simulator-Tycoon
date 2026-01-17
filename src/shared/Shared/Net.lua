-- Net.lua
-- Shared remote accessor with caching and friendly errors

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local cachedEvents = {}
local cachedFunctions = {}

local function getRemotesRoot()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		error("[Net] ReplicatedStorage.Remotes not found. Did RemoteSetup run?", 3)
	end
	return remotes
end

local function getFolder(folderName)
	local remotes = getRemotesRoot()
	local folder = remotes:FindFirstChild(folderName)
	if not folder then
		error(string.format("[Net] ReplicatedStorage.Remotes.%s not found", folderName), 3)
	end
	return folder
end

function Net.GetRemoteEvent(name)
	assert(type(name) == "string", "[Net] name must be string")

	if cachedEvents[name] then
		return cachedEvents[name]
	end

	local eventsFolder = getFolder("Events")
	local remote = eventsFolder:FindFirstChild(name)
	if not remote or not remote:IsA("RemoteEvent") then
		error(string.format("[Net] RemoteEvent '%s' not found", name), 2)
	end

	cachedEvents[name] = remote
	return remote
end

function Net.GetRemoteFunction(name)
	assert(type(name) == "string", "[Net] name must be string")

	if cachedFunctions[name] then
		return cachedFunctions[name]
	end

	local functionsFolder = getFolder("Functions")
	local remote = functionsFolder:FindFirstChild(name)
	if not remote or not remote:IsA("RemoteFunction") then
		error(string.format("[Net] RemoteFunction '%s' not found", name), 2)
	end

	cachedFunctions[name] = remote
	return remote
end

return Net
