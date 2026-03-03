# MSS

Roblox game project using a modular, server-authoritative architecture aligned to the Glowie service/data style.

## Architecture

### Runtime bootstrap
- `src/server/init.server.luau`: starts `ServiceRuntime`.
- `src/client/init.client.luau`: starts `ControllerRuntime`.

### Server modules
- `Modules/Data/Data_*`: server-owned gameplay data/config.
  - `Data_Combat.luau`
  - `Data_GameplayManager.luau`
  - `Data_Player.luau`
- `Modules/ServiceModules/GamePlaySystems/*`:
  - `GamePlayManagerService`: fixed-rate heartbeat manager + scheduler.
  - `NetworkService`: remote function contract setup.
  - `DataStoreService`: profile/data API.
  - `WeaponService`: player weapon lifecycle + inventory fetch API.
  - `MobService`: spawn/attack orchestration.
  - `CombatService`: packet intake, request validation, queueing, and tick-based processing.
  - `WeaponReplicationService`: weapon replication packet fan-out.

### Shared data + network
- `src/shared/Data/Data_*.luau`: shared data contracts.
- `src/shared/Network/GameplayPacket.luau`: gameplay packet namespace.
- `src/shared/Network/WeaponPacket.luau`: weapon replication packet namespace.
- `src/shared/Network/NetworkApi.luau`: shared API for packets + remote function lookup.

## Server-authoritative guarantees

- Combat input is received as packets, validated server-side, then queued.
- Damage application is processed on manager ticks, not directly on client event timing.
- Cooldowns/rate limiting are enforced on the server.
- Equipped weapon state is read from profile data on the server.
- Remotes/functions are created by server startup.

## Development notes

- `default.project.json` mappings:
  - `ServerStorage.Data -> Modules/Data`
  - `ServerStorage.ServiceModules -> Modules/ServiceModules`
- Regenerate sourcemap:
  - `rojo sourcemap default.project.json -o sourcemap.json`
