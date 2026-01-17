-- Config.lua (адаптированный под один уровень)

local Config = {}

Config.Server = {
	MaxPlayers = 6,
	AutosaveInterval = 60,
	DebugMode = true,
	LogLevel = "INFO",
}

Config.Player = {
	StartMoney = 0,
	StartBusinessLevel = 1,
	StartLocation = "Kiosk",
	MaxBusinessLevel = 3,
	SaveVersion = "2.0",
}

-- Локации
Config.Locations = {
	Kiosk = {
		Level = 1,
		Template = "KioskTemplate",
		UnlockCost = 0,
		MaxQueueSize = 5,
		SpotsCount = 5,
		SpawnRate = 0.30,
	},
	Cafe = {
		Level = 2,
		Template = "CafeTemplate",
		UnlockCost = 2500,
		MaxQueueSize = 10,
		SpotsCount = 10,
		SpawnRate = 0.55,
	},
	Restaurant = {
		Level = 3,
		Template = "RestaurantTemplate",
		UnlockCost = 12000,
		MaxQueueSize = 20,
		SpotsCount = 20,
		SpawnRate = 0.85,
	},
}

Config.Customers = {
	MaxWaitTime = 20,
	MaxOrderProcessTime = 30,
	RegisterRadius = 4,
	TutorialPatienceMultiplier = 3,
	KioskSingleItem = true,

	Models = {
		"ClientTemplate",
	},
	
	Names = {
		"Ivan",
		"Kirill",
		"Nikita",
		"Alexey",
		"Mikhail",
		"Artem",
		"Dmitry",
		"Sergey",
	},

	Pathfinding = {
		AgentRadius = 1.5,
		AgentHeight = 5,
		AgentCanJump = true,
		WaypointSpacing = 2,
	},

	BaseTipChance = 0.3,
	MaxTipMultiplier = 0.5,
}

-- =========================================================
-- EMPLOYEES CONFIG
-- =========================================================
-- Конфиг описывает ПРАВИЛА генерации сотрудников.
-- Здесь НЕТ конкретных сотрудников.
--
-- Config отвечает за:
-- - возможные редкости
-- - диапазоны характеристик
-- - имена и модели
-- - зарплаты
--
-- Конкретные сотрудники создаются через EmployeeService
-- и сохраняются в SaveData игрока.
-- =========================================================

Config.Employees = {

	-- =====================================================
	-- ИМЕНА СОТРУДНИКОВ
	-- =====================================================
	-- Используются ТОЛЬКО при генерации нового сотрудника.
	-- После найма имя сохраняется в данных сотрудника
	-- и больше НЕ меняется.
	--
	-- Не влияет на баланс, только визуал / атмосфера.
	-- =====================================================
	Names = {
		"Alexey",
		"Kirill",
		"Nikita",
		"Artem",
		"Dmitry",
		"Sergey",
		"Mikhail",
		"Ivan",
	},

	-- =====================================================
	-- МОДЕЛИ СОТРУДНИКОВ
	-- =====================================================
	-- Возможные визуальные модели сотрудников.
	-- Выбор происходит при найме и сохраняется навсегда.
	--
	-- Разделены по:
	-- 1) роли (WAITER / COOK)
	-- 2) редкости (Common → Mythical)
	--
	-- Модели лежат в ServerStorage.
	-- =====================================================
	Models = {

		-- ---------- ОФИЦИАНТ ----------
		WAITER = {
			Common     = { "Waiter_Common_1", "Waiter_Common_2" },
			Uncommon   = { "Waiter_Uncommon_1" },
			Rare       = { "Waiter_Rare_1" },
			Legendary  = { "Waiter_Legendary_1" },
			Mythical   = { "Waiter_Mythical_1" },
		},

		-- ---------- ПОВАР ----------
		COOK = {
			Common     = { "Cook_Common_1" },
			Uncommon   = { "Cook_Uncommon_1" },
			Rare       = { "Cook_Rare_1" },
			Legendary  = { "Cook_Legendary_1" },
			Mythical   = { "Cook_Mythical_1" },
		},
	},

	-- =====================================================
	-- ЗАРПЛАТЫ СОТРУДНИКОВ
	-- =====================================================
	-- Стоимость содержания сотрудника.
	-- Может списываться:
	-- - раз в день
	-- - раз в минуту
	-- - раз за игровой цикл
	--
	-- Зарплата зависит ТОЛЬКО от:
	-- - роли
	-- - редкости
	--
	-- НЕ зависит от конкретных статов.
	-- =====================================================
	Salaries = {

		WAITER = {
			Common     = 5,
			Uncommon   = 8,
			Rare       = 15,
			Legendary  = 30,
			Mythical   = 60,
		},

		COOK = {
			Common     = 8,
			Uncommon   = 12,
			Rare       = 20,
			Legendary  = 40,
			Mythical   = 80,
		},
	},

	-- =====================================================
	-- РЕДКОСТИ
	-- =====================================================
	-- Определяют:
	-- - шанс выпадения сотрудника
	-- - диапазоны характеристик
	-- - зарплату
	-- - визуал
	--
	-- Сумма всех Chance должна быть = 1.0
	-- =====================================================
	Rarities = {
		Common     = { Chance = 0.45 },
		Uncommon   = { Chance = 0.30 },
		Rare       = { Chance = 0.15 },
		Legendary  = { Chance = 0.08 },
		Mythical   = { Chance = 0.02 },
	},

	-- =====================================================
	-- РОЛИ СОТРУДНИКОВ И ИХ ХАРАКТЕРИСТИКИ
	-- =====================================================
	-- StatsByRarity определяет ДИАПАЗОН характеристик,
	-- внутри которого роллятся значения при найме.
	--
	-- После найма значения ФИКСИРУЮТСЯ
	-- и больше НЕ пересчитываются.
	-- =====================================================
	Roles = {

		-- =================================================
		-- ОФИЦИАНТ (ЛОГИСТИКА)
		-- =================================================
		WAITER = {
			StatsByRarity = {

				-- Скорость передвижения персонажа
				-- MaxActiveOrders — сколько заказов официант
				-- может одновременно обслуживать
				-- CarryCapacity — сколько заказов может нести за раз
				Common = {
					MoveSpeed = { min = 13, max = 14 },
					MaxActiveOrders = { min = 1, max = 1 },
					CarryCapacity = { min = 1, max = 1 },
				},

				Uncommon = {
					MoveSpeed = { min = 14, max = 15 },
					MaxActiveOrders = { min = 1, max = 2 },
					CarryCapacity = { min = 1, max = 2 },
				},

				Rare = {
					MoveSpeed = { min = 15, max = 16 },
					MaxActiveOrders = { min = 2, max = 3 },
					CarryCapacity = { min = 2, max = 2 },
				},

				Legendary = {
					MoveSpeed = { min = 16, max = 18 },
					MaxActiveOrders = { min = 3, max = 4 },
					CarryCapacity = { min = 2, max = 3 },
				},

				Mythical = {
					MoveSpeed = { min = 18, max = 20 },
					MaxActiveOrders = { min = 4, max = 5 },
					CarryCapacity = { min = 3, max = 4 },
				},
			},
		},

		-- =================================================
		-- ПОВАР (ПРОИЗВОДСТВО)
		-- =================================================
		COOK = {
			StatsByRarity = {

				-- CookTimeMultiplier — множитель времени готовки
				-- (меньше = быстрее)
				--
				-- PerfectDishChance — шанс приготовить
				-- идеальное блюдо
				--
				-- PerfectDishMultiplier — множитель цены
				-- идеального блюда
				Common = {
					CookTimeMultiplier = { min = 1.0, max = 0.95 },
					PerfectDishChance = { min = 0.03, max = 0.06 },
					PerfectDishMultiplier = 1.5,
				},

				Uncommon = {
					CookTimeMultiplier = { min = 0.95, max = 0.9 },
					PerfectDishChance = { min = 0.06, max = 0.1 },
					PerfectDishMultiplier = 1.5,
				},

				Rare = {
					CookTimeMultiplier = { min = 0.9, max = 0.8 },
					PerfectDishChance = { min = 0.1, max = 0.15 },
					PerfectDishMultiplier = 1.5,
				},

				Legendary = {
					CookTimeMultiplier = { min = 0.8, max = 0.7 },
					PerfectDishChance = { min = 0.15, max = 0.25 },
					PerfectDishMultiplier = 1.5,
				},

				Mythical = {
					CookTimeMultiplier = { min = 0.7, max = 0.6 },
					PerfectDishChance = { min = 0.25, max = 0.4 },
					PerfectDishMultiplier = 1.5,
				},
			},
		},
	},
}


-- =========================
-- COOKING CONFIG (FINAL)
-- =========================
-- Cooking отвечает ТОЛЬКО за:
-- 1) тип станции (еда / напитки)
-- 2) уровень станции
-- 3) скорость готовки (через уменьшение времени)
--
-- Cooking НЕ отвечает за:
-- - количество блюд
-- - доступность блюд
-- - качество
-- - клиентов
-- - экономику
--
-- Доступность блюд определяется ТОЛЬКО через FoodConfig
-- по уровню станции (RequiredStationLevel)
--
-- Cooking = ускоритель производства
-- =========================

Config.Cooking = {

	Stations = {

		GRILL = {
			
			Name = "Grill",

			UnlockLevel = 1,

			MaxLevel = 5,

			Levels = {
				[1] = {
					CookTimeMultiplier = 1.0,
				},
				[2] = {
					CookTimeMultiplier = 0.9,
				},
				[3] = {
					CookTimeMultiplier = 0.8,
				},
				[4] = {
					CookTimeMultiplier = 0.7,
				},
				[5] = {
					CookTimeMultiplier = 0.6,
				},
			},

			-- FUTURE:
			-- Здесь позже можно добавить ModelsByLevel,
			-- чтобы визуал станции менялся при апгрейде
			-- ModelsByLevel = {
			--   [1] = "Grill_Level1",
			--   [2] = "Grill_Level2",
			-- }
		},

		-- =========================
		-- DRINK — НАПИТКИ
		-- =========================
		DRINK = {
			Name = "Drink Station",

			UnlockLevel = 1,
			MaxLevel = 5,

			Levels = {
				[1] = {
					CookTimeMultiplier = 0.8,
				},
				[2] = {
					CookTimeMultiplier = 0.7,
				},
				[3] = {
					CookTimeMultiplier = 0.6,
				},
				[4] = {
					CookTimeMultiplier = 0.5,
				},
				[5] = {
					CookTimeMultiplier = 0.4,
				},
			},

			-- FUTURE:
			-- ModelsByLevel = { ... }
		},
	},
}


-- =====================================================
-- UPGRADES CONFIG (FINAL)
-- =====================================================
-- Апгрейды усиливают БИЗНЕС В ЦЕЛОМ.
--
-- Они НЕ заменяют:
-- - прокачку станций (Config.Cooking)
-- - редкость и статы сотрудников
--
-- Апгрейды:
-- - ускоряют процессы
-- - увеличивают прибыль
-- - улучшают поток клиентов
-- - оптимизируют расходы
--
-- Игрок видит простые эффекты:
-- "Больше клиентов", "Готовка быстрее", "Больше денег"
-- =====================================================

Config.Upgrades = {

	-- =================================================
	-- ПОТОК КЛИЕНТОВ / СПРОС
	-- =================================================
	ClientFlow = {

		-- Увеличивает частоту прихода клиентов
		-- Реализуется через:
		-- - уменьшение SpawnInterval
		-- - или увеличение SpawnChance
		ClientAttraction = {
			BaseCost = 120,
			CostMultiplier = 1.6,
			Increment = 0.05, -- +5% к частоте прихода
			MaxLevel = 10,
		},

		-- Репутация бизнеса
		-- Клиенты реже уходят, меньше штрафов за ошибки
		-- НЕ тупо увеличивает таймер ожидания
		ReputationBoost = {
			BaseCost = 150,
			CostMultiplier = 1.7,
			Increment = 0.05, -- снижение шанса ухода
			MaxLevel = 5,
		},

		-- Увеличивает время ожидания клиентов
		-- Простая помощь для новичков
		CustomerPatience = {
			BaseCost = 80,
			CostMultiplier = 1.4,
			Increment = 5, -- секунд
			MaxLevel = 5,
		},
	},

	-- =================================================
	-- КУХНЯ / ГОТОВКА
	-- =================================================
	Kitchen = {

		-- Глобальный буст скорости готовки
		-- Итоговая формула:
		-- BaseFoodTime
		-- × EmployeeCookMultiplier
		-- × StationCookMultiplier
		-- × CookSpeedBoost
		CookSpeedBoost = {
			BaseCost = 150,
			CostMultiplier = 1.6,
			Multiplier = 0.95, -- -5% времени за уровень
			MaxLevel = 5,
		},

		-- Усиливает эффект прокачки станций
		-- Делает апгрейды GRILL / DRINK более ценными
		StationUpgradeBonus = {
			BaseCost = 200,
			CostMultiplier = 1.7,
			Multiplier = 0.95,
			MaxLevel = 5,
		},
	},

	-- =================================================
	-- СОТРУДНИКИ (ГЛОБАЛЬНЫЕ БОНУСЫ)
	-- =================================================
	Staff = {

		-- Сотрудники быстрее передвигаются
		-- Влияет на официантов
		StaffMoveBoost = {
			BaseCost = 120,
			CostMultiplier = 1.5,
			Multiplier = 1.05, -- +5% скорости
			MaxLevel = 5,
		},

		-- Повышает общую квалификацию сотрудников
		-- Усиливает:
		-- - шанс идеального блюда
		-- - скорость работы
		StaffSkillBoost = {
			BaseCost = 180,
			CostMultiplier = 1.6,
			Increment = 0.03, -- +3% к шансам / эффективности
			MaxLevel = 5,
		},

		-- Снижает зарплаты сотрудников
		-- Очень сильный экономический апгрейд
		StaffSalaryReduction = {
			BaseCost = 250,
			CostMultiplier = 1.7,
			Multiplier = 0.95, -- -5% к зарплате
			MaxLevel = 5,
		},

		-- Увеличивает эффективность официантов
		-- Например:
		-- - больше заказов за раз
		-- - быстрее обслуживание
		StaffCapacityBoost = {
			BaseCost = 160,
			CostMultiplier = 1.6,
			Increment = 1, -- логический бонус (не обязательно прямой стат)
			MaxLevel = 5,
		},

		-- Повышает шанс найти редких сотрудников при найме
		-- Очень сильный, азартный апгрейд
		HiringLuck = {
			BaseCost = 300,
			CostMultiplier = 1.8,
			Increment = 0.03, -- +3% к шансам редкости
			MaxLevel = 5,
		},
	},

	-- =================================================
	-- ЭКОНОМИКА / ДЕНЬГИ
	-- =================================================
	Economy = {

		-- Увеличивает базовую цену блюд
		MenuPriceBoost = {
			BaseCost = 200,
			CostMultiplier = 1.8,
			Multiplier = 1.10, -- +10% к цене
			MaxLevel = 5,
		},

		-- Чаевые выпадают чаще
		TipsChanceBoost = {
			BaseCost = 100,
			CostMultiplier = 1.4,
			Increment = 0.05,
			MaxLevel = 5,
		},

		-- Чаевые становятся больше
		TipsMultiplierBoost = {
			BaseCost = 150,
			CostMultiplier = 1.6,
			Multiplier = 1.10,
			MaxLevel = 5,
		},

		-- Бонус за идеальное обслуживание
		-- Заказы без ошибок, таймаутов и уходов
		ComboBonus = {
			BaseCost = 180,
			CostMultiplier = 1.6,
			Multiplier = 1.15,
			MaxLevel = 5,
		},
	},

	-- =================================================
	-- БУДУЩЕЕ / ЛЕЙТГЕЙМ
	-- =================================================
	Future = {

		-- Частичная автоматизация процессов
		-- (позже: автозаказ, автоприготовление)
		BusinessAutomation = {
			BaseCost = 500,
			CostMultiplier = 2.0,
			UnlockLevel = 3, -- ресторан
			MaxLevel = 3,
		},

		-- Престиж — глобальный бонус после ресета
		PrestigeBonus = {
			BaseCost = 0, -- не покупается напрямую
			Multiplier = 1.05,
			MaxLevel = 10,
		},
	},
}


Config.UI = {
	UpdateInterval = 0.3,
	AnimationSpeed = 0.2,

	Colors = {
		Primary = Color3.fromRGB(46, 204, 113),
		Secondary = Color3.fromRGB(52, 152, 219),
		Warning = Color3.fromRGB(230, 126, 34),
		Danger = Color3.fromRGB(231, 76, 60),
		Success = Color3.fromRGB(39, 174, 96),
	},
}


-- Вспомогательные функции
function Config.GetLocationConfig(level)
	if level <= 1 then
		return Config.Locations.Kiosk
	elseif level == 2 then
		return Config.Locations.Cafe
	else
		return Config.Locations.Restaurant
	end
end

function Config.GetMaxQueueSize(level)
	return Config.GetLocationConfig(level).MaxQueueSize
end

function Config.GetClientSpawnRate(level, upgrades)
	local location = Config.GetLocationConfig(level)

	local baseRate = location.SpawnRate or 1.0
	local lvl = upgrades and upgrades.ClientFlow and upgrades.ClientFlow.ClientAttraction or 0
	local inc = Config.Upgrades.ClientFlow.ClientAttraction.Increment
	return baseRate * (1 + lvl * inc)
end

function Config.CanSpawnClient(level, currentQueueSize)
	local maxQueue = Config.GetMaxQueueSize(level)
	return currentQueueSize < maxQueue
end

function Config.GetFinalCookTimeMultiplier(params)
	return (params.employee or 1.0)
		* (params.station or 1.0)
		* (params.upgrade or 1.0)
end

function Config.GetEmployeeSalary(role, rarity)
	return Config.Employees.Salaries[role][rarity]
end

function Config.GetHiringChance(rarity, upgrades)
	local base = Config.Employees.Rarities[rarity].Chance
	local lvl = upgrades and upgrades.Staff and upgrades.Staff.HiringLuck or 0
	local inc = Config.Upgrades.Staff.HiringLuck.Increment
	local bonus = lvl * inc
	return math.clamp(base + bonus, 0, 1)
end

function Config.GetFinalMenuPrice(basePrice, upgrades)
	local lvl = upgrades and upgrades.Economy and upgrades.Economy.MenuPriceBoost or 0
	local perLevel = Config.Upgrades.Economy.MenuPriceBoost.Multiplier
	return basePrice * (perLevel ^ lvl)
end


return Config
