# MSS

Roblox game project organized around a Knit-style service/controller architecture.

## Architecture

### Startup
- `src/server/init.server.luau`: boots Knit server services.
- `src/client/init.client.luau`: boots Knit client controllers.

### Server
- `src/server/Services/GameplayServices/*`
  - `GameplayManagerService`: fixed-rate heartbeat manager + scheduler.
  - `NetworkService`: remote function contract setup.
  - `DataStoreService`: profile/data API.
  - `WeaponService`: player weapon lifecycle + inventory fetch API.
  - `MobService`: mob spawning and combat routing.
  - `CombatService`: packet intake, validation, queueing, tick-based attack processing.
  - `WeaponReplicationService`: weapon replication packet fan-out.
- `src/server/Services/GameplayServices/Support/*`
  - combat gate/validation helpers.
- `src/server/Gameplay/Mob/*`
  - mob domain runtime (`MobManager`, `MobEntity`).
- `src/server/Config/Data_*.luau`
  - server-owned gameplay config definitions.

### Client
- `src/client/Controllers/GameplayControllers/*`
  - gameplay-facing Knit controllers (`Profile`, `UI`, `VFX`, `WeaponReplication`).
- `src/client/Gameplay/*`
  - client gameplay modules by domain (`Weapon`, `Combat`, `VFX`).

### Shared
- `src/shared/Data/Data_*.luau`: shared data contracts.
- `src/shared/Network/*`: ByteNet packet namespaces + shared network API.
- `src/shared/Utilities/*`: world access, packet subscriptions, weapon data/formation/payload helpers.
- `src/shared/ByteNet`, `src/shared/Zone`, `src/shared/Trove`, `src/shared/ReplicaController`, etc.

## Server-authoritative behavior

- Combat requests are sent as packets and validated on the server.
- Damage application runs on server ticks through `GameplayManagerService`.
- Cooldowns/rate limiting are enforced server-side.
- Equipped weapon state is sourced from server profile data.
