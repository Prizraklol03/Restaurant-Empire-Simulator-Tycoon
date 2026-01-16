# DEV_RULES

## Роли модулей
- `StartClientSystem`: оркестратор NPC (спавн, таймеры, решения).
- `QueueService`: очередь и Spot_N, без бизнес-логики.
- `ClientAI`: только движение и события достижения точек.
- `OrderService`: владелец заказов и таймингов.
- `EventBus`: серверные события (in-memory), не UI/remotes.

## Events / Remotes / DTO
- Все события и ремоты версионируются (см. `docs/contracts`).
- DTO без Instance, только примитивы/таблицы.
- Доступ к remotes только через `Shared/Net.lua`.

## Save schema + миграции
- Схема `v2` описана в `Contracts_SaveSchema_v2`.
- Любое изменение save требует миграции и bump версии.

## Server-authoritative
- Клиент никогда не является источником истины.
- RemoteFunctions — read-only.
- Любое действие клиента должно валидироваться сервером.
