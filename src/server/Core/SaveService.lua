--====================================================
-- SaveService.lua
-- v2.0
-- Единственный владелец SaveData
--====================================================

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- ProfileService (обязательно положи ModuleScript)
local ProfileService = require(ServerScriptService.Core.ProfileService)

local Config = require(ServerScriptService.Core.Config)

local SaveService = {}

----------------------------------------------------
-- CONSTANTS
----------------------------------------------------

local PROFILE_STORE_NAME = "RestaurantEmpire_Save_v2"
local SAVE_VERSION = "2.0"

----------------------------------------------------
-- PROFILE STORE
----------------------------------------------------

local ProfileStore = ProfileService.GetProfileStore(
	PROFILE_STORE_NAME,
	{} -- шаблон не используем, создаём вручную
)

----------------------------------------------------
-- RUNTIME STATE
----------------------------------------------------

local Profiles = {} -- [player] = profile

----------------------------------------------------
-- DEFAULT SAVE DATA
----------------------------------------------------

local function createDefaultSave()
	return {
		Version = SAVE_VERSION,

		Money = Config.Player.StartMoney or 0,
		BusinessLevel = Config.Player.StartBusinessLevel or 1,

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

			UnlockedFoods = {},
			Employees = {}, -- на будущее
		},
	}
end

----------------------------------------------------
-- MIGRATIONS
----------------------------------------------------

local function migrateSave(save)
	-- если версии нет — считаем как 1.0
	if not save.Version then
		save.Version = "1.0"
	end

	-- пример будущей миграции
	if save.Version == "1.0" then
		-- здесь можно будет преобразовывать старую структуру
		save.Version = "2.0"
	end

	-- гарантируем наличие обязательных полей
	if not save.Business then
		save.Business = createDefaultSave().Business
	end

	return save
end

----------------------------------------------------
-- PROFILE LOAD
----------------------------------------------------

local function loadProfile(player)
	local profile = ProfileStore:LoadProfileAsync(
		"Player_" .. player.UserId,
		"ForceLoad"
	)

	if not profile then
		player:Kick("Save load failed. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile() -- на будущее

	profile.Data = migrateSave(profile.Data or createDefaultSave())

	Profiles[player] = profile

	profile:ListenToRelease(function()
		Profiles[player] = nil
		player:Kick("Save released.")
	end)

	return profile
end

----------------------------------------------------
-- PUBLIC API
----------------------------------------------------

function SaveService.GetProfile(player)
	return Profiles[player]
end

function SaveService.GetSave(player)
	local profile = Profiles[player]
	return profile and profile.Data
end

function SaveService.Release(player)
	local profile = Profiles[player]
	if profile then
		profile:Release()
	end
end

----------------------------------------------------
-- PLAYER LIFECYCLE
----------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	loadProfile(player)
end)

Players.PlayerRemoving:Connect(function(player)
	SaveService.Release(player)
end)

----------------------------------------------------
-- SHUTDOWN SAFETY
----------------------------------------------------

game:BindToClose(function()
	for player, profile in pairs(Profiles) do
		profile:Release()
	end
end)

----------------------------------------------------
-- DEBUG (OPTIONAL)
----------------------------------------------------

function SaveService._DebugDump(player)
	local save = SaveService.GetSave(player)
	if save then
		warn("[SaveService] Dump:", save)
	end
end

return SaveService
