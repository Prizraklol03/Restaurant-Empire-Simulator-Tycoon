# Contracts_Events_v1

## EventBus (server)
Единый in-memory bus для серверных модулей. Не заменяет RemoteEvent.

### Правила
- Имена событий: `SCREAMING_SNAKE_CASE`.
- Payload — plain table, без Instance-heavy ссылок, кроме допустимых `player`/`npc`.
- Публикации событий не должны блокировать (fire-and-forget).

### Базовые события
- `NPC_REACHED_SPOT`: `{ player, clientId, spotIndex }`
- `NPC_REACHED_REGISTER`: `{ player, clientId, npc }`
- `ORDER_CREATED`: `{ player, orderId, items, price, waitTime, clientId?, npcBrain? }`
- `ORDER_ACCEPTED`: `{ player, orderId, deadlineAt }`
- `ORDER_COMPLETED`: `{ player, orderId, price }`
- `ORDER_FAILED`: `{ player, orderId, reason }`
- `ORDER_CANCELLED`: `{ player, orderId, reason }`

## Remotes (client/server)
RemoteEvents/RemoteFunctions описаны в `Contracts_RemotesDTO_v1`.
