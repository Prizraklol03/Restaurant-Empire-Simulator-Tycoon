--====================================================
-- PlayerService.lua
-- v2.0
-- Единственный API доступа к данным игрока
--====================================================

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local SaveService = require(ServerScriptService.Core.SaveService)
local Config = require(ServerScriptService.Core.Config)
local FoodConfig = require(ServerScriptService.Core.FoodConfig)

local PlayerService = {}

----------------------------------------------------
-- INTERNAL HELPERS
----------------------------------------------------

local function getSave(player)
	local save = SaveService.GetSave(player)
	assert(save, "[PlayerService] SaveData not found for player")
	return save
end

local function getBusiness(save)
	assert(save.Business, "[PlayerService] Business data missing")
	return save.Business
end

local function ensureBoolMap(value)
	local map = {}
	if type(value) ~= "table" then
		return map
	end
	if #value > 0 then
		for _, entry in ipairs(value) do
			if type(entry) == "string" and entry ~= "" then
				map[entry] = true
			end
		end
		return map
	end
	for key, entry in pairs(value) do
		if entry == true then
			map[key] = true
		elseif type(entry) == "number" and entry ~= 0 then
			map[key] = true
		elseif type(entry) == "string" and entry == "true" then
			map[key] = true
		end
	end
	return map
end

local function resolveFoodsMap(profile, topKey, bizKey)
	local business = profile.Business or {}
	local topMap = ensureBoolMap(profile[topKey])
	local bizMap = ensureBoolMap(business[bizKey])

	for key in pairs(bizMap) do
		topMap[key] = true
	end
	for key in pairs(topMap) do
		bizMap[key] = true
	end

	profile[topKey] = topMap
	business[bizKey] = bizMap
	profile.Business = business

	return topMap
end

----------------------------------------------------
-- MONEY
----------------------------------------------------

function PlayerService.GetMoney(player)
	return getSave(player).Money
end

function PlayerService.AddMoney(player, amount)
	assert(type(amount) == "number", "Amount must be number")

	local save = getSave(player)
	save.Money += amount
end

function PlayerService.SpendMoney(player, amount)
	assert(type(amount) == "number", "Amount must be number")

	local save = getSave(player)
	if save.Money < amount then
		return false
	end

	save.Money -= amount
	return true
end

----------------------------------------------------
-- BUSINESS LEVEL
----------------------------------------------------

function PlayerService.GetBusinessLevel(player)
	return getSave(player).BusinessLevel
end

function PlayerService.SetBusinessLevel(player, level)
	assert(type(level) == "number", "Level must be number")

	local save = getSave(player)
	save.BusinessLevel = math.clamp(
		level,
		1,
		Config.Player.MaxBusinessLevel or level
	)
end

----------------------------------------------------
-- STATIONS
----------------------------------------------------

function PlayerService.GetStationLevel(player, stationType)
	local business = getBusiness(getSave(player))
	local station = business.Stations[stationType]
	return station and station.Level or 0
end

function PlayerService.UpgradeStation(player, stationType)
	local save = getSave(player)
	local business = getBusiness(save)

	local stationCfg = Config.Cooking.Stations[stationType]
	assert(stationCfg, "[PlayerService] Unknown station: " .. tostring(stationType))

	local station = business.Stations[stationType]
	if not station then
		return false
	end

	if station.Level >= stationCfg.MaxLevel then
		return false
	end

	station.Level += 1
	return true
end

function PlayerService.GetStationLevels(player)
	local save = getSave(player)
	local business = save.Business
	local result = {}

	local legacyStations = business and business.Stations or {}
	local newStations = save.stations or {}

	for stationType, data in pairs(legacyStations) do
		local level = tonumber(data.Level) or 0
		result[stationType] = math.max(0, level)
	end

	for stationType, data in pairs(newStations) do
		if result[stationType] == nil then
			local level = tonumber(data.level) or 0
			result[stationType] = math.max(0, level)
		end
	end

	if next(result) == nil then
		return {
			GRILL = 1,
			DRINK = 1,
		}
	end

	result.GRILL = result.GRILL or 0
	result.DRINK = result.DRINK or 0

	return result
end

----------------------------------------------------
-- UPGRADES
----------------------------------------------------

function PlayerService.GetUpgrades(player)
	return getBusiness(getSave(player)).Upgrades
end

function PlayerService.GetUpgradeLevel(player, category, upgradeId)
	local upgrades = PlayerService.GetUpgrades(player)
	return upgrades[category] and upgrades[category][upgradeId] or 0
end

function PlayerService.Upgrade(player, category, upgradeId)
	local upgrades = PlayerService.GetUpgrades(player)
	local categoryCfg = Config.Upgrades[category]
	assert(categoryCfg, "[PlayerService] Unknown upgrade category")

	local upgradeCfg = categoryCfg[upgradeId]
	assert(upgradeCfg, "[PlayerService] Unknown upgrade id")

	local current = upgrades[category][upgradeId] or 0
	if current >= upgradeCfg.MaxLevel then
		return false
	end

	upgrades[category][upgradeId] = current + 1
	return true
end

----------------------------------------------------
-- UNLOCKED FOODS
----------------------------------------------------

function PlayerService.IsFoodUnlocked(player, foodId)
	local business = getBusiness(getSave(player))
	return business.UnlockedFoods[foodId] == true
end

function PlayerService.UnlockFood(player, foodId)
	local business = getBusiness(getSave(player))
	business.UnlockedFoods[foodId] = true
end

function PlayerService.GetUnlockedFoods(player)
	local save = getSave(player)
	local result = resolveFoodsMap(save, "unlockedFoods", "UnlockedFoods")
	if Config.Server.DebugMode then
		print(string.format(
			"[PlayerFoods] unlocked sources: top=%s biz=%s",
			tostring(save.unlockedFoods ~= nil),
			tostring(save.Business and save.Business.UnlockedFoods ~= nil)
		))
		print(string.format(
			"[PlayerFoods] unlockedCola top=%s biz=%s",
			tostring(save.unlockedFoods and save.unlockedFoods["Cola"]),
			tostring(save.Business and save.Business.UnlockedFoods and save.Business.UnlockedFoods["Cola"])
		))
	end
	return result
end

function PlayerService.GetEnabledFoods(player)
	local save = getSave(player)
	local result = resolveFoodsMap(save, "enabledFoods", "EnabledFoods")
	if Config.Server.DebugMode then
		print(string.format(
			"[PlayerFoods] enabled sources: top=%s biz=%s",
			tostring(save.enabledFoods ~= nil),
			tostring(save.Business and save.Business.EnabledFoods ~= nil)
		))
		print(string.format(
			"[PlayerFoods] enabledCola top=%s biz=%s",
			tostring(save.enabledFoods and save.enabledFoods["Cola"]),
			tostring(save.Business and save.Business.EnabledFoods and save.Business.EnabledFoods["Cola"])
		))
	end
	return result
end

function PlayerService.SetFoodEnabled(player, foodId, enabled)
	local save = getSave(player)
	local business = getBusiness(save)
	local food = FoodConfig.GetFoodById(foodId)
	if not food then
		return false, "unknown_food"
	end

	if enabled then
		if not business.UnlockedFoods[foodId] then
			return false, "locked"
		end
		business.EnabledFoods[foodId] = true
		save.enabledFoods = save.enabledFoods or {}
		save.enabledFoods[foodId] = true
	else
		business.EnabledFoods[foodId] = nil
		if type(save.enabledFoods) == "table" then
			save.enabledFoods[foodId] = nil
		end
	end
	business.EnabledInitialized = true

	return true
end

function PlayerService.HasAnyEnabledFood(player, menuLevel, stationLevels)
	local business = getBusiness(getSave(player))
	local unlockedFoods = business.UnlockedFoods or {}
	local enabledFoods = business.EnabledFoods or {}
	local levels = stationLevels or PlayerService.GetStationLevels(player)
	local level = menuLevel or PlayerService.GetBusinessLevel(player)

	for foodId in pairs(enabledFoods) do
		local food = FoodConfig.GetFoodById(foodId)
		if food and FoodConfig.IsFoodAvailable(food, level, levels, unlockedFoods) then
			return true
		end
	end

	return false
end

----------------------------------------------------
-- RAW ACCESS (STRICT)
----------------------------------------------------

function PlayerService.GetSave(player)
	-- ТОЛЬКО ДЛЯ DEBUG / READ-ONLY
	return getSave(player)
end

function PlayerService.GetProfile(player)
	-- ТОЛЬКО ДЛЯ READ-ONLY
	return SaveService.GetProfile(player)
end

----------------------------------------------------
-- VALIDATION / DEBUG
----------------------------------------------------

function PlayerService.DebugDump(player)
	warn("[PlayerService] Save dump:", PlayerService.GetSave(player))
end

----------------------------------------------------
-- SERVED COUNT (TUTORIAL GATE)
----------------------------------------------------

function PlayerService.GetServedCount(player)
	local save = getSave(player)
	return save.ServedCount or 0
end

function PlayerService.IncrementServedCount(player)
	local save = getSave(player)
	save.ServedCount = (save.ServedCount or 0) + 1
	return save.ServedCount
end

----------------------------------------------------
-- SAFETY
----------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	-- Ничего не делаем.
	-- SaveService сам корректно освободит профиль.
end)

return PlayerService
