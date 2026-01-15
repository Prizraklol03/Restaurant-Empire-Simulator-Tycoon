-- OrderGenerator.lua
-- FINAL VERSION
-- Генерация заказа:
-- 1) обычное меню по категориям
-- 2) отдельный premium-pass (1 блюдо максимум)

local FoodConfig = require(game.ServerScriptService.Core.FoodConfig)

local OrderGenerator = {}

---------------------------------------------------------------------
-- INTERNAL HELPERS
---------------------------------------------------------------------

-- Взвешенный выбор по OrderChance
local function weightedPick(list)
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

	local r = math.random() * totalWeight
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

local function generateBaseOrder(menuLevel, stationLevels, unlockedFoods)
	local items = {}
	local usedCategories = {}

	local categories = FoodConfig.GetCategories()

	for categoryId, category in pairs(categories) do
		local categoryChance = category.OrderChance or 0
		local maxItems = category.MaxItems or 1

		-- ролл категории
		if math.random() <= categoryChance then
			local foods = FoodConfig.GetAvailableFoodsByCategory(
				categoryId,
				menuLevel,
				stationLevels,
				unlockedFoods
			)

			if #foods > 0 then
				usedCategories[categoryId] = true

				local distinctCount = math.random(1, math.min(maxItems, #foods))
				local picked = {}

				for _ = 1, distinctCount do
					local food = weightedPick(foods)
					if food and not picked[food.Id] then
						picked[food.Id] = true

						local maxPerOrder = food.MaxPerOrder or 1
						local quantity = math.random(1, maxPerOrder)

						items[food.Id] = {
							quantity = quantity,
						}
					end
				end
			end
		end
	end

	return items, usedCategories
end

---------------------------------------------------------------------
-- PREMIUM PASS
---------------------------------------------------------------------

local function applyPremiumPass(items, usedCategories, context)
	local premiumChance = context.premiumRollChance or 0
	if premiumChance <= 0 then
		return
	end

	-- ролл премиума
	if math.random() > premiumChance then
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

	local premiumFood = weightedPick(premiumCandidates)
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

	local menuLevel = context.menuLevel or 1
	local stationLevels = context.stationLevels or {}
	local unlockedFoods = context.unlockedFoods or {}

	-- 1️⃣ обычный заказ
	local items, usedCategories = generateBaseOrder(
		menuLevel,
		stationLevels,
		unlockedFoods
	)

	-- 2️⃣ premium-pass
	applyPremiumPass(items, usedCategories, context)

	return items
end

---------------------------------------------------------------------

return OrderGenerator
