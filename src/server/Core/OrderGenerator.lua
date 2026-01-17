-- OrderGenerator.lua
-- FINAL VERSION
-- Генерация заказа:
-- 1) обычное меню по категориям
-- 2) отдельный premium-pass (1 блюдо максимум)

local FoodConfig = require(game.ServerScriptService.Core.FoodConfig)
local Config = require(game.ServerScriptService.Core.Config)

local OrderGenerator = {}

---------------------------------------------------------------------
-- INTERNAL HELPERS
---------------------------------------------------------------------

local function normalizeBoolMap(value)
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
		end
	end
	return map
end

-- Взвешенный выбор по OrderChance
local function weightedPick(list, roll01)
	if #list == 0 then
		return nil
	end

	local totalWeight = 0
	local pool = {}

	for _, item in ipairs(list) do
		local weight = item.OrderChance or 1
		if weight > 0 then
			totalWeight += weight
			table.insert(pool, {
				item = item,
				acc = totalWeight,
			})
		end
	end

	if totalWeight <= 0 then
		return nil
	end

	local r = roll01() * totalWeight
	for _, entry in ipairs(pool) do
		if r <= entry.acc then
			return entry.item
		end
	end

	return pool[#pool].item
end

---------------------------------------------------------------------
-- BASE ORDER (обычное меню)
---------------------------------------------------------------------

local function generateBaseOrder(candidatesByCategory, categories, roll01, rollChance, randInt)
	local items = {}
	local usedCategories = {}
	local picked = {}

	local function addFood(food)
		if picked[food.Id] then
			return false
		end
		picked[food.Id] = true
		local maxPerOrder = food.MaxPerOrder or 1
		local quantity = randInt(1, maxPerOrder)
		items[food.Id] = {
			quantity = quantity,
		}
		return true
	end

	local mainCandidates = candidatesByCategory.Main or {}
	if #mainCandidates > 0 then
		local mainFood = weightedPick(mainCandidates, roll01)
		if mainFood then
			addFood(mainFood)
			usedCategories.Main = true
		end
	end

	local drinkCandidates = candidatesByCategory.Drink or {}
	if #drinkCandidates > 0 then
		local drinkChance = 0.6
		local drinkRoll = roll01()
		if Config.Server.DebugMode then
			print(string.format(
				"[OrderGenRoll] Drink roll=%.3f chance=%.2f candidates=%d",
				drinkRoll,
				drinkChance,
				#drinkCandidates
			))
		end
		if drinkRoll <= drinkChance then
			local drinkFood = weightedPick(drinkCandidates, roll01)
			if drinkFood then
				addFood(drinkFood)
				usedCategories.Drink = true
			end
		end
	end

	for categoryId, category in pairs(categories) do
		if categoryId == "Main" or categoryId == "Drink" then
			continue
		end
		local foods = candidatesByCategory[categoryId] or {}
		if #foods == 0 then
			continue
		end

		local categoryChance = category.OrderChance or 0
		local maxItems = category.MaxItems or 1

		-- ролл категории
		if rollChance(categoryChance) then
			usedCategories[categoryId] = true

			local distinctCount = randInt(1, math.min(maxItems, #foods))

			for _ = 1, distinctCount do
				local food = weightedPick(foods, roll01)
				if food then
					addFood(food)
				end
			end
		end
	end

	return items, usedCategories
end

---------------------------------------------------------------------
-- PREMIUM PASS
---------------------------------------------------------------------

local function applyPremiumPass(items, usedCategories, context, roll01, rollChance)
	local premiumChance = context.premiumRollChance or 0
	if premiumChance <= 0 then
		return
	end

	-- ролл премиума
	if not rollChance(premiumChance) then
		return
	end

	local menuLevel = context.menuLevel or 1
	local stationLevels = context.stationLevels or {}
	local unlockedFoods = context.unlockedFoods or {}

	local premiumCandidates = {}

	-- если есть категории в базовом заказе → используем их
	for categoryId in pairs(usedCategories) do
		local foods = FoodConfig.GetAvailablePremiumFoodsByCategory(
			categoryId,
			menuLevel,
			stationLevels,
			unlockedFoods
		)

		for _, food in ipairs(foods) do
			table.insert(premiumCandidates, food)
		end
	end

	-- если базовый заказ пуст или нет релевантных категорий
	if #premiumCandidates == 0 then
		for _, category in pairs(FoodConfig.GetCategories()) do
			local foods = FoodConfig.GetAvailablePremiumFoodsByCategory(
				category.Name,
				menuLevel,
				stationLevels,
				unlockedFoods
			)

			for _, food in ipairs(foods) do
				table.insert(premiumCandidates, food)
			end
		end
	end

	if #premiumCandidates == 0 then
		return
	end

	local premiumFood = weightedPick(premiumCandidates, roll01)
	if not premiumFood then
		return
	end

	-- добавляем ровно 1 премиум-блюдо
	items[premiumFood.Id] = {
		quantity = 1,
	}
end

---------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------

function OrderGenerator.Generate(context)
	assert(type(context) == "table", "[OrderGenerator] context is required")

	local rng = context.rng or Random.new()
	local function roll01()
		return rng:NextNumber()
	end
	local function rollChance(p)
		return roll01() <= p
	end
	local function randInt(min, max)
		return rng:NextInteger(min, max)
	end

	local menuLevel = context.menuLevel or 1
	local stationLevels = context.stationLevels or {}
	local unlockedFoods = normalizeBoolMap(context.unlockedFoods)
	local enabledFoods = context.enabledFoods == nil and nil or normalizeBoolMap(context.enabledFoods)

	local categories = FoodConfig.GetCategories()
	local candidatesByCategory = {}
	local allCandidates = {}

	for categoryId in pairs(categories) do
		local foods = FoodConfig.GetAvailableFoodsByCategory(
			categoryId,
			menuLevel,
			stationLevels,
			unlockedFoods
		)
		local filtered = {}
		for _, food in ipairs(foods) do
			local isEnabled = enabledFoods == nil or enabledFoods[food.Id] == true
			local isUnlocked = unlockedFoods[food.Id] == true or not food.Unlock
			if isEnabled and isUnlocked and FoodConfig.GetFoodById(food.Id) then
				table.insert(filtered, food)
				table.insert(allCandidates, food)
			end
		end
		candidatesByCategory[categoryId] = filtered
	end

	-- 1️⃣ обычный заказ
	local items, usedCategories = generateBaseOrder(candidatesByCategory, categories, roll01, rollChance, randInt)

	-- 2️⃣ premium-pass
	applyPremiumPass(items, usedCategories, context, roll01, rollChance)

	if next(items) == nil and #allCandidates > 0 then
		local fallback = candidatesByCategory.Main or {}
		local fallbackDrink = candidatesByCategory.Drink or {}
		local fallbackDessert = candidatesByCategory.Dessert or {}
		local chosen = fallback[1] or fallbackDrink[1] or fallbackDessert[1] or allCandidates[1]
		if chosen then
			items[chosen.Id] = {
				quantity = 1,
			}
			if Config and Config.Server and Config.Server.DebugMode then
				print(string.format(
					"[OrderGenFallback] empty result -> forced=%s candidates=%d",
					tostring(chosen.Id),
					#allCandidates
				))
			end
		end
	end

	if Config.Server.DebugMode then
		local parts = {}
		local stations = {}
		for foodId, entry in pairs(items) do
			local qty = entry.quantity or entry or 1
			table.insert(parts, string.format("%s=%s", foodId, tostring(qty)))
			local food = FoodConfig.GetFoodById(foodId)
			if food and food.Station then
				stations[food.Station] = true
			end
		end
		table.sort(parts)
		local stationList = {}
		for station in pairs(stations) do
			table.insert(stationList, station)
		end
		table.sort(stationList)
		print(string.format(
			"[OrderGenResult] items=%s stations=%s",
			table.concat(parts, ","),
			table.concat(stationList, ",")
		))
	end

	return items
end

---------------------------------------------------------------------

return OrderGenerator
