# Contracts_SaveSchema_v2

## Версия
`2.0`

## Структура
```lua
{
  Version = "2.0",
  Money = number,
  BusinessLevel = number,
  Business = {
    Stations = {
      GRILL = { Level = number },
      DRINK = { Level = number },
    },
    Upgrades = {
      ClientFlow = {},
      Kitchen = {},
      Economy = {},
      Staff = {},
      Future = {},
    },
    UnlockedFoods = { [foodId: string] = true },
    Employees = {},
  }
}
```

## Миграции
- `1.0` → `2.0`: перенос полей в `Business`, заполнение дефолтами.
- Любые будущие изменения должны поддерживать backward-compatible чтение.

## Правила
- Схема серверная, клиент получает read-only копии.
- Изменения схемы сопровождаются новой версией и миграцией.
