# Contracts_NPCFlow_v3.2

## Цель
Единый контракт жизненного цикла NPC клиента (server-authoritative).

## Источник истины
- `StartClientSystem` — единственный оркестратор (спавн/таймеры/решения).
- `QueueService` — тупой менеджер очереди и назначение Spot_N.
- `ClientAI` — исполнитель движения и источник событий достижения точек.

## События (EventBus)
- `NPC_REACHED_SPOT`: `{ player, clientId, spotIndex }`
- `NPC_REACHED_REGISTER`: `{ player, clientId, npc }`
- `ORDER_CREATED`: `{ player, orderId, items, price, waitTime, clientId?, npcBrain? }`
- `ORDER_COMPLETED`: `{ player, orderId, price }`
- `ORDER_FAILED`: `{ player, orderId, reason }`
- `ORDER_CANCELLED`: `{ player, orderId, reason }`

> Важно: `StartClientSystem` не должен полагаться на поля, не указанные выше.

## Порядок флоу
1. `StartClientSystem` решает о спавне (Config + PlayerService).
2. `QueueService:Join` назначает Spot_N → `ClientAI:GoToSpot`.
3. `ClientAI` по достижении Spot_N → `NPC_REACHED_SPOT`.
4. `StartClientSystem` при свободном register вызывает `ClientAI:GoToRegister`.
5. `ClientAI` по достижении register → `NPC_REACHED_REGISTER`.
6. `OrderService.CreateOrder` → `ORDER_CREATED`.
7. `StartClientSystem` при завершении → `RequestExit`.

## Тайминги
- Очередь: `Config.Customers.MaxWaitTime`.
- Обработка заказа: `Config.Customers.MaxOrderProcessTime`.
- OrderService использует собственную модель wait/deadline; синхронизировать в следующем этапе.

## Запрещено
- Таймеры/решения в `ClientAI` и `QueueService`.
- Прямой доступ к `OrderService` минуя `EventBus`.
