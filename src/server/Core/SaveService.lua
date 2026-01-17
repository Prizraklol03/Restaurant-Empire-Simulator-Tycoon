--====================================================
-- SaveService.lua
-- v2.0
-- DataStore-backed profile storage
--====================================================

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(game.ServerScriptService.Core.Config)
local FoodConfig = require(game.ServerScriptService.Core.FoodConfig)

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

local DEFAULT_START_FOODS = { "Burger", "Cola" }

local function ensureFoodTables(profile)
	profile.Business = profile.Business or {}
	profile.Business.UnlockedFoods = profile.Business.UnlockedFoods or {}
	profile.Business.EnabledFoods = profile.Business.EnabledFoods or {}

	if profile.Business.FoodsInitialized ~= true then
		local unlockedEmpty = next(profile.Business.UnlockedFoods) == nil
		local enabledEmpty = next(profile.Business.EnabledFoods) == nil
		if unlockedEmpty and enabledEmpty then
			for _, foodId in ipairs(DEFAULT_START_FOODS) do
				profile.Business.UnlockedFoods[foodId] = true
				profile.Business.EnabledFoods[foodId] = true
			end
		end
		profile.Business.FoodsInitialized = true
	end

	if profile.Business.EnabledInitialized ~= true then
		local enabledEmpty = next(profile.Business.EnabledFoods) == nil
		if enabledEmpty then
			for _, foodId in ipairs(DEFAULT_START_FOODS) do
				if profile.Business.UnlockedFoods[foodId] == true and FoodConfig.GetFoodById(foodId) then
					profile.Business.EnabledFoods[foodId] = true
				end
			end

			if next(profile.Business.EnabledFoods) == nil then
				for foodId, value in pairs(profile.Business.UnlockedFoods) do
					if value == true and FoodConfig.GetFoodById(foodId) then
						profile.Business.EnabledFoods[foodId] = true
						break
					end
				end
			end
		end

		if next(profile.Business.EnabledFoods) ~= nil then
			profile.Business.EnabledInitialized = true
		end
	end

	for foodId, value in pairs(profile.Business.EnabledFoods) do
		if value == true then
			local food = FoodConfig.GetFoodById(foodId)
			if not food then
				profile.Business.EnabledFoods[foodId] = nil
			elseif food.Unlock and profile.Business.UnlockedFoods[foodId] ~= true then
				profile.Business.EnabledFoods[foodId] = nil
			end
		else
			profile.Business.EnabledFoods[foodId] = nil
		end
	end
end

local function createDefaultProfile()
	local unlocked = { "Burger", "Cola" }
	local unlockedMap = {
		Burger = true,
		Cola = true,
	}
	local enabledMap = {
		Burger = true,
		Cola = true,
	}

	local profile = {
		schemaVersion = 2,
		money = 0,
		businessLevel = 1,
		stations = {
			GRILL = { level = 1 },
			DRINK = { level = 1 },
		},
		unlockedFoods = unlocked,
		enabledFoods = { "Burger", "Cola" },
		employees = nil,
		location = "Kiosk",
		ServedCount = 0,

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
			EnabledFoods = enabledMap,
			EnabledInitialized = true,
			FoodsInitialized = true,
			Employees = {},
		},
	}

	ensureFoodTables(profile)
	return profile
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
	profile.ServedCount = profile.ServedCount or 0

	profile.stations = profile.stations or defaults.stations
	profile.unlockedFoods = profile.unlockedFoods or defaults.unlockedFoods
	profile.enabledFoods = profile.enabledFoods or defaults.enabledFoods

	profile.Business = profile.Business or defaults.Business
	profile.Money = profile.Money or profile.money
	profile.BusinessLevel = profile.BusinessLevel or profile.businessLevel
	if type(profile.Business.UnlockedFoods) ~= "table" then
		profile.Business.UnlockedFoods = {}
	end
	if type(profile.Business.EnabledFoods) ~= "table" then
		profile.Business.EnabledFoods = {}
	end

	local canonicalMap = {}
	for foodId in pairs(FoodConfig.Foods) do
		canonicalMap[string.lower(foodId)] = foodId
	end
	for foodId in pairs(FoodConfig.FoodsPremium) do
		canonicalMap[string.lower(foodId)] = foodId
	end

	local function normalizeBusinessMap(map)
		if type(map) ~= "table" then
			return
		end

		for key, value in pairs(map) do
			if value == true then
				local canonical = canonicalMap[string.lower(key)]
				if canonical and canonical ~= key then
					map[canonical] = true
					map[key] = nil
				end
			else
				map[key] = nil
			end
		end
	end

	normalizeBusinessMap(profile.Business.UnlockedFoods)
	normalizeBusinessMap(profile.Business.EnabledFoods)

	for foodId in pairs(profile.Business.EnabledFoods) do
		if not profile.Business.UnlockedFoods[foodId] then
			profile.Business.EnabledFoods[foodId] = nil
		elseif not FoodConfig.GetFoodById(foodId) then
			profile.Business.EnabledFoods[foodId] = nil
		end
	end

	ensureFoodTables(profile)

	if type(profile.unlockedFoods) == "table" then
		local normalized = {}
		local seen = {}
		for _, key in ipairs(profile.unlockedFoods) do
			local canonical = canonicalMap[string.lower(key)]
			if canonical and not seen[canonical] then
				table.insert(normalized, canonical)
				seen[canonical] = true
			end
		end
		if #normalized > 0 then
			profile.unlockedFoods = normalized
		end
	end

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
	local profile = createDefaultProfile()
	Profiles[player] = profile

	task.spawn(function()
		local loaded = loadFromStore(player)
		if loaded then
			local migrated = migrateProfile(loaded)
			Profiles[player] = migrated

			for _, callback in ipairs(profileLoadedCallbacks) do
				callback(player, migrated)
			end
		else
			warn("[SaveService] Using default profile for", player.UserId)
		end
	end)

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
