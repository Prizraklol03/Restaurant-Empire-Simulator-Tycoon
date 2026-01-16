# Contracts_RemotesDTO_v1

## Обязательные RemoteFunctions
- `GetProfile()` → `SaveSchema_v2` (read-only).
- `GetBusinessStats()` → `{ Money: number, BusinessLevel: number }`.
- `GetGameState()` → `{ Money: number, QueueSize: number, CurrentOrder: string, HasWaiter: boolean }`.

## Обязательные RemoteEvents
- `UpdateBusinessStats`: payload `{ Money, BusinessLevel, ... }`.
- `UpdateCashRegisterUI`: payload `{ QueueSize, CurrentOrder, ... }`.

## Правила DTO
- DTO всегда versioned, backward-compatible.
- Никаких Instance в DTO (только примитивы/таблицы).
- Server-authoritative: клиент не может менять состояние через функции.

## Транспорт
Использовать `Shared/Net.lua` для доступа к remotes.
