-- FoodConfig.lua
-- Подготовлен под:
--  - категории
--  - обычные и премиум блюда
--  - OrderGenerator v2
--  - CookingStationService

local FoodConfig = {}

---------------------------------------------------------------------
-- FOODS (ОБЫЧНЫЕ)
---------------------------------------------------------------------

FoodConfig.Foods = {

	-- ======================
	-- MENU LEVEL 1
	-- ======================

	Burger = {
		Id = "Burger",
		Name = "Burger",
		Category = "Main",

		MenuLevel = 1,
		Station = "GRILL",
		RequiredStationLevel = 1,

		BasePrice = 25,
		BaseCookTime = 8,

		OrderChance = 0.8,
		MaxPerOrder = 2,

		Unlock = {
			Type = "Cash",
			Price = 150,
		},

		Icon = "rbxassetid://1234567890",
		Description = "Classic beef burger",
	},

	Pizza = {
		Id = "Pizza",
		Name = "Pizza",
		Category = "Main",

		MenuLevel = 1,
		Station = "GRILL",
		RequiredStationLevel = 1,

		BasePrice = 40,
		BaseCookTime = 12,

		OrderChance = 0.6,
		MaxPerOrder = 1,

		Unlock = {
			Type = "Cash",
			Price = 200,
		},

		Icon = "rbxassetid://2345678901",
		Description = "Margherita pizza",
	},

	Sandwich = {
		Id = "Sandwich",
		Name = "Sandwich",
		Category = "Main",

		MenuLevel = 1,
		Station = "GRILL",
		RequiredStationLevel = 1,

		BasePrice = 20,
		BaseCookTime = 6,

		OrderChance = 0.5,
		MaxPerOrder = 2,

		Unlock = {
			Type = "Cash",
			Price = 120,
		},

		Icon = "rbxassetid://5678901234",
		Description = "Toasted sandwich",
	},

	Coffee = {
		Id = "Coffee",
		Name = "Coffee",
		Category = "Drink",

		MenuLevel = 1,
		Station = "DRINK",
		RequiredStationLevel = 1,

		BasePrice = 15,
		BaseCookTime = 4,

		OrderChance = 0.9,
		MaxPerOrder = 2,

		Unlock = {
			Type = "Cash",
			Price = 100,
		},

		Icon = "rbxassetid://3456789012",
		Description = "Fresh coffee",
	},

	Tea = {
		Id = "Tea",
		Name = "Tea",
		Category = "Drink",

		MenuLevel = 1,
		Station = "DRINK",
		RequiredStationLevel = 1,

		BasePrice = 12,
		BaseCookTime = 3,

		OrderChance = 0.7,
		MaxPerOrder = 2,

		Unlock = {
			Type = "Cash",
			Price = 80,
		},

		Icon = "rbxassetid://4567890123",
		Description = "Hot tea",
	},
}

---------------------------------------------------------------------
-- FOODS (PREMIUM / ROBUX)
---------------------------------------------------------------------

FoodConfig.FoodsPremium = {

	GoldenBurger = {
		Id = "GoldenBurger",
		Name = "Golden Burger",
		Category = "Main",

		MenuLevel = 1,
		Station = "GRILL",
		RequiredStationLevel = 1,

		BasePrice = 250,
		BaseCookTime = 10,

		OrderChance = 1.0,
		MaxPerOrder = 1,

		Unlock = {
			Type = "Robux",
			Price = 100,
		},

		Icon = "rbxassetid://999000111",
		Description = "Premium golden burger",
	},

	LuxuryCoffee = {
		Id = "LuxuryCoffee",
		Name = "Luxury Coffee",
		Category = "Drink",

		MenuLevel = 1,
		Station = "DRINK",
		RequiredStationLevel = 1,

		BasePrice = 120,
		BaseCookTime = 5,

		OrderChance = 1.0,
		MaxPerOrder = 1,

		Unlock = {
			Type = "Robux",
			Price = 60,
		},

		Icon = "rbxassetid://999000222",
		Description = "Exclusive premium coffee",
	},
}

---------------------------------------------------------------------
-- STATIONS
---------------------------------------------------------------------

FoodConfig.Stations = {
	GRILL = { Name = "Grill" },
	DRINK = { Name = "Drink Station" },
}

---------------------------------------------------------------------
-- CATEGORIES
---------------------------------------------------------------------

FoodConfig.Categories = {
	Main = {
		Name = "Main",
		Order = 1,
		Icon = "🍔",
		OrderChance = 0.95,
		MaxItems = 2,
	},

	Drink = {
		Name = "Drink",
		Order = 2,
		Icon = "🥤",
		OrderChance = 0.85,
		MaxItems = 2,
	},

	Dessert = {
		Name = "Dessert",
		Order = 3,
		Icon = "🍰",
		OrderChance = 0.20,
		MaxItems = 1,
	},
}

---------------------------------------------------------------------
-- INTERNAL HELPERS
---------------------------------------------------------------------

local function canCookFood(food, stationLevels)
	stationLevels = stationLevels or {}
	return (stationLevels[food.Station] or 0) >= (food.RequiredStationLevel or 1)
end

local function isUnlocked(food, unlockedFoods)
	return unlockedFoods and unlockedFoods[food.Id] == true
end

---------------------------------------------------------------------
-- PUBLIC API (ОБЩАЯ ЛОГИКА)
---------------------------------------------------------------------

function FoodConfig.GetCategories()
	return FoodConfig.Categories
end

function FoodConfig.GetFoodById(foodId)
	return FoodConfig.Foods[foodId] or FoodConfig.FoodsPremium[foodId]
end

function FoodConfig.IsFoodAvailable(food, menuLevel, stationLevels, unlockedFoods)
	if food.MenuLevel > menuLevel then
		return false
	end

	if not canCookFood(food, stationLevels) then
		return false
	end

	if food.Unlock then
		return isUnlocked(food, unlockedFoods)
	end

	return true
end

-- Универсальный фильтр (для обычных и премиум)
local function getAvailableFromSource(source, category, menuLevel, stationLevels, unlockedFoods)
	local foods = {}

	for _, food in pairs(source) do
		if food.Category == category
			and FoodConfig.IsFoodAvailable(food, menuLevel, stationLevels, unlockedFoods) then
			table.insert(foods, food)
		end
	end

	return foods
end

---------------------------------------------------------------------
-- PUBLIC API (РАЗДЕЛЕНИЕ ИСТОЧНИКОВ)
---------------------------------------------------------------------

function FoodConfig.GetAvailableFoodsByCategory(category, menuLevel, stationLevels, unlockedFoods)
	return getAvailableFromSource(
		FoodConfig.Foods,
		category,
		menuLevel,
		stationLevels,
		unlockedFoods
	)
end

function FoodConfig.GetAvailablePremiumFoodsByCategory(category, menuLevel, stationLevels, unlockedFoods)
	return getAvailableFromSource(
		FoodConfig.FoodsPremium,
		category,
		menuLevel,
		stationLevels,
		unlockedFoods
	)
end

---------------------------------------------------------------------

return FoodConfig
