--====================================================
-- PlayerService.lua
-- v2.0
-- Единственный API доступа к данным игрока
--====================================================

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local SaveService = require(ServerScriptService.Core.SaveService)
local Config = require(ServerScriptService.Core.Config)

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
	local business = getBusiness(getSave(player))
	local result = {}

	for stationType, data in pairs(business.Stations) do
		result[stationType] = data.Level
	end

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

----------------------------------------------------
-- RAW ACCESS (STRICT)
----------------------------------------------------

function PlayerService.GetSave(player)
	-- ТОЛЬКО ДЛЯ DEBUG / READ-ONLY
	return getSave(player)
end

----------------------------------------------------
-- VALIDATION / DEBUG
----------------------------------------------------

function PlayerService.DebugDump(player)
	warn("[PlayerService] Save dump:", PlayerService.GetSave(player))
end

----------------------------------------------------
-- SAFETY
----------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	-- Ничего не делаем.
	-- SaveService сам корректно освободит профиль.
end)

return PlayerService
