# gen_dealership — FiveM Vehicle Dealership Creator

Build vehicle dealerships **in-game**, without editing config files or restarting the server. Admins open the creator, place points with a live ghost-vehicle preview, set up a catalogue with prices and stock, and arrange showroom display cars. Players walk up, browse, test drive and buy.

Works with **Qbox**, **QBCore**, **ESX** and **standalone** (detected automatically). The only hard dependency is **oxmysql**.

## Features

**Creator (`/dealercreator`)**
- Create, edit and delete any number of dealerships from an in-game UI
- Placement tool: aim at the ground with a translucent preview vehicle. `E` confirms, `G` uses your own position (or your vehicle's), scroll or arrow keys rotate (hold Shift to rotate faster), Backspace cancels
- Points: catalogue (interaction + blip), delivery spawn, optional test-drive spawn
- Vehicle catalogue: an in-game model check auto-fills the label (make + model) and suggests a category from the vehicle class. Price and stock are set per vehicle (`-1` = unlimited)
- Showroom: up to 30 frozen display vehicles per dealership, each showing its price when a player walks up
- Blip settings (sprite, colour, scale, on/off) and an optional job restriction
- Changes sync live to every player. No restart needed

**Player shop**
- Catalogue grid with category filter, search, stock badges and vehicle images
- Pay with bank or cash (configurable)
- Timed test drives with a countdown. They end automatically if the player leaves the vehicle, and the server enforces a cooldown
- Purchased vehicles are written to the framework's own table (`player_vehicles` / `owned_vehicles`), delivered at the spawn point, and come with keys and fuel

**Security**
- Every creator action is permission-checked on the server (ACE `dealership.admin` or the framework's admin group)
- All creator input is sanitized server-side (model names, lengths, coordinates, limits)
- Purchases check job access, distance to the dealership, stock and balance. Each player is locked to one purchase at a time, and money is refunded if registering the vehicle fails
- A key request is only honoured for the plate the server just issued to that player

## Installation

1. Drop the folder into your `resources` directory (for example as `[gen]/gen_dealership`).
2. Make sure `oxmysql` is installed. The tables are created automatically; `sql/install.sql` is provided if you prefer to run it yourself.
3. In `server.cfg`, start it **after** your framework:
   ```cfg
   ensure oxmysql
   ensure qb-core        # or qbx_core / es_extended
   ensure gen_dealership

   add_ace group.admin dealership.admin allow
   ```
4. In-game, run `/dealercreator`.

## Quick start

1. `/dealercreator` → **+ New dealership** → enter a display name. The identifier fills in automatically.
2. **Locations** → place the *Catalogue point* and the *Delivery spawn* (both required).
3. **Vehicles** → type a spawn name (e.g. `sultan`) → **Check** → set price and stock → **Add**.
4. **Showroom** → choose a vehicle → **Place display vehicle**.
5. **Save dealership**. It's live for everyone immediately.

## Integrations

| What | Supported out of the box | Where to change |
|---|---|---|
| Framework | qbx_core, qb-core, es_extended, standalone | `bridge/server.lua`, `bridge/client.lua` |
| Owned vehicles | qbx_vehicles export, `player_vehicles`, `owned_vehicles`, own table (standalone) | `Bridge.GiveVehicle` |
| Keys | qbx_vehiclekeys (server), qb-vehiclekeys, wasabi_carlock | `Bridge.GiveKeys` (both sides) |
| Fuel | LegacyFuel, ox_fuel, cdn-fuel, native | `Bridge.SetFuel` |
| Notifications | framework notify, or the native feed | `Bridge.Notify` |

## Configuration

Everything lives in `config.lua`: command name, ACE, interaction key and distances, plate format, payment methods, test drive duration and cooldown, limits, categories and all player-facing text.

## Exports (server)

```lua
exports.gen_dealership:GetDealerships()      -- array of every dealership
exports.gen_dealership:GetDealership('pdm')  -- one dealership by identifier
```

## Data

| Table | Purpose |
|---|---|
| `gen_dealerships` | dealership definitions (points, blip, showroom) |
| `gen_dealership_vehicles` | catalogue per dealership (price, stock) |
| `gen_dealership_sales` | sales log (who bought what, for how much, and how they paid) |
| `gen_dealership_owned` | owned vehicles, standalone mode only |
