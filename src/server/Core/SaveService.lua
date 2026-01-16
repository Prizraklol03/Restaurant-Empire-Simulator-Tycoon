--====================================================
-- SaveService.lua
-- v2.0
-- DataStore-backed profile storage
--====================================================

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(game.ServerScriptService.Core.Config)

local SaveService = {}

----------------------------------------------------
-- CONSTANTS
----------------------------------------------------

local PROFILE_STORE = DataStoreService:GetDataStore("Profiles_v2")
local AUTOSAVE_INTERVAL = 60

----------------------------------------------------
-- RUNTIME STATE
----------------------------------------------------

local Profiles = {} -- [player] = profile table
local profileLoadedCallbacks = {}

----------------------------------------------------
-- DEFAULT PROFILE
----------------------------------------------------

local function createDefaultProfile()
	local unlocked = { "burger", "tea" }
	local unlockedMap = {
		burger = true,
		tea = true,
	}

	return {
		schemaVersion = 2,
		money = 0,
		businessLevel = 1,
		stations = {
			GRILL = { level = 1 },
			DRINK = { level = 1 },
		},
		unlockedFoods = unlocked,
		enabledFoods = nil,
		employees = nil,
		location = "Kiosk",

		-- Legacy compatibility
		Version = "2.0",
		Money = 0,
		BusinessLevel = 1,
		Business = {
			Stations = {
				GRILL = { Level = 1 },
				DRINK = { Level = 1 },
			},
			Upgrades = {
				ClientFlow = {},
				Kitchen = {},
				Economy = {},
				Staff = {},
				Future = {},
			},
			UnlockedFoods = unlockedMap,
			Employees = {},
		},
	}
end

----------------------------------------------------
-- MIGRATION
----------------------------------------------------

local function applyDefaults(profile)
	local defaults = createDefaultProfile()

	for key, value in pairs(defaults) do
		if profile[key] == nil then
			profile[key] = value
		end
	end

	profile.schemaVersion = 2
	profile.Version = profile.Version or "2.0"
	profile.location = profile.location or Config.Player.StartLocation or "Kiosk"

	profile.money = profile.money or 0
	profile.businessLevel = profile.businessLevel or 1

	profile.stations = profile.stations or defaults.stations
	profile.unlockedFoods = profile.unlockedFoods or defaults.unlockedFoods

	profile.Business = profile.Business or defaults.Business
	profile.Money = profile.Money or profile.money
	profile.BusinessLevel = profile.BusinessLevel or profile.businessLevel

	return profile
end

local function migrateProfile(profile)
	if type(profile) ~= "table" then
		return createDefaultProfile()
	end

	local version = tonumber(profile.schemaVersion) or 0
	if version < 2 then
		profile.schemaVersion = 2
	end

	return applyDefaults(profile)
end

----------------------------------------------------
-- DATASTORE HELPERS
----------------------------------------------------

local function getKey(player)
	return tostring(player.UserId)
end

local function loadFromStore(player)
	local key = getKey(player)
	local ok, data = pcall(PROFILE_STORE.GetAsync, PROFILE_STORE, key)
	if not ok then
		warn("[SaveService] Load failed for", key, data)
		return nil
	end

	if data == nil then
		return createDefaultProfile()
	end

	return migrateProfile(data)
end

local function saveToStore(player, profile)
	local key = getKey(player)
	local ok, err = pcall(PROFILE_STORE.SetAsync, PROFILE_STORE, key, profile)
	if not ok then
		warn("[SaveService] Save failed for", key, err)
		return false
	end

	return true
end

----------------------------------------------------
-- PUBLIC API
----------------------------------------------------

function SaveService.Init()
	-- optional hook for future init
end

function SaveService.Load(player)
	local profile = loadFromStore(player) or createDefaultProfile()
	Profiles[player] = profile

	for _, callback in ipairs(profileLoadedCallbacks) do
		callback(player, profile)
	end

	return profile
end

function SaveService.Save(player)
	local profile = Profiles[player]
	if not profile then
		return false
	end

	return saveToStore(player, profile)
end

function SaveService.GetProfile(player)
	return Profiles[player]
end

function SaveService.GetSave(player)
	return Profiles[player]
end

function SaveService.Update(player, mutatorFn)
	local profile = Profiles[player]
	if not profile then
		profile = SaveService.Load(player)
	end

	if type(mutatorFn) == "function" then
		mutatorFn(profile)
	end

	return profile
end

function SaveService.OnProfileLoaded(player, callback)
	if type(player) == "function" and callback == nil then
		table.insert(profileLoadedCallbacks, player)
		return
	end

	if type(callback) == "function" then
		table.insert(profileLoadedCallbacks, function(loadedPlayer, profile)
			if loadedPlayer == player then
				callback(loadedPlayer, profile)
			end
		end)
	end
end

function SaveService.Release(player)
	Profiles[player] = nil
end

----------------------------------------------------
-- AUTOSAVE
----------------------------------------------------

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			SaveService.Save(player)
		end
	end
end)

return SaveService
