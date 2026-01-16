-- HealthCheck.lua
-- Minimal startup sanity checks

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(game.ServerScriptService.Core.Config)
local FoodConfig = require(game.ServerScriptService.Core.FoodConfig)

local HealthCheck = {}

local function addIssue(issues, message)
	table.insert(issues, message)
end

local function checkRemotes(issues)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		addIssue(issues, "ReplicatedStorage.Remotes missing")
		return
	end

	local events = remotes:FindFirstChild("Events")
	local functions = remotes:FindFirstChild("Functions")
	if not events then
		addIssue(issues, "ReplicatedStorage.Remotes.Events missing")
	end
	if not functions then
		addIssue(issues, "ReplicatedStorage.Remotes.Functions missing")
	end

	local requiredEvents = { "UpdateBusinessStats", "UpdateCashRegisterUI" }
	for _, name in ipairs(requiredEvents) do
		local remote = events and events:FindFirstChild(name)
		if not remote or not remote:IsA("RemoteEvent") then
			addIssue(issues, "RemoteEvent missing: " .. name)
		end
	end

	local requiredFunctions = { "GetBusinessStats", "GetGameState", "GetProfile" }
	for _, name in ipairs(requiredFunctions) do
		local remote = functions and functions:FindFirstChild(name)
		if not remote or not remote:IsA("RemoteFunction") then
			addIssue(issues, "RemoteFunction missing: " .. name)
		end
	end
end

local function checkConfig(issues)
	local customers = Config.Customers or {}
	if type(customers.MaxWaitTime) ~= "number" or customers.MaxWaitTime <= 0 then
		addIssue(issues, "Config.Customers.MaxWaitTime invalid")
	end
	if type(customers.MaxOrderProcessTime) ~= "number" or customers.MaxOrderProcessTime <= 0 then
		addIssue(issues, "Config.Customers.MaxOrderProcessTime invalid")
	end

	local multiplier = Config.GetFinalCookTimeMultiplier({
		employee = 1,
		station = 1,
		upgrade = 1,
	})
	if type(multiplier) ~= "number" then
		addIssue(issues, "Config.GetFinalCookTimeMultiplier returned non-number")
	end
end

local function checkFoodConfig(issues)
	if type(FoodConfig.Foods) ~= "table" or next(FoodConfig.Foods) == nil then
		addIssue(issues, "FoodConfig.Foods is empty")
	end
end

local function checkModules(issues)
	local core = game.ServerScriptService:FindFirstChild("Core")
	if not core then
		addIssue(issues, "ServerScriptService.Core missing")
		return
	end

	local requiredModules = {
		"Config",
		"FoodConfig",
		"OrderService",
		"PlayerService",
		"SaveService",
		"EventBus",
	}

	for _, name in ipairs(requiredModules) do
		if not core:FindFirstChild(name) then
			addIssue(issues, "Core module missing: " .. name)
		end
	end
end

function HealthCheck.Run()
	local issues = {}

	checkRemotes(issues)
	checkModules(issues)
	checkConfig(issues)
	checkFoodConfig(issues)

	if #issues == 0 then
		print("[HealthCheck][OK] All checks passed")
		return true
	end

	warn("[HealthCheck][FAIL] Issues detected:")
	for _, issue in ipairs(issues) do
		warn(" - " .. issue)
	end

	return false, issues
end

return HealthCheck
