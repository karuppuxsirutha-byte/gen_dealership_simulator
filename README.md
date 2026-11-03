# gen_dealership — FiveM Vehicle Dealership Creator & Simulator

Build vehicle dealerships **in-game**, then let players **run them as businesses**.

- **Creator:** admins place dealerships, catalogues and showrooms without touching config files or restarting the server.
- **Shop:** players browse, test drive and buy.
- **Simulator:** players can buy a dealership, order stock wholesale, set prices, hire salespeople on commission, sell to other players and haggle with AI walk-in customers.

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
- Catalogue grid with category filter, search, sorting, stock badges, vehicle images and arrow-key browsing
- Details panel with real performance stats read from the game (top speed, acceleration, braking, handling, seats), your balance after purchase, and a purchase summary before you pay
- Pay with bank or cash (configurable)
- **Test drives:** start one from the catalogue, or walk up to any showroom car and press **E**.
  - The car spawns at the test-drive point with a countdown and a range readout, and turns red as you near the limit.
  - **X** ends the drive early. Driving too far, leaving the car, or running out of time sends you back automatically.
  - The server enforces a cooldown and cleans up abandoned test cars (crash or disconnect).
  - Optional private instance (routing bucket) so test drivers can't interfere with anyone.
- Purchased vehicles are written to the framework's own table (`player_vehicles` / `owned_vehicles`), delivered at the spawn point, and come with keys and fuel

**Security**
- Every creator action is permission-checked on the server (ACE `dealership.admin` or the framework's admin group)
- All creator input is sanitized server-side (model names, lengths, coordinates, limits)
- Purchases check job access, distance to the dealership, stock and balance. Each player is locked to one purchase at a time, and money is refunded if registering the vehicle fails
- A key request is only honoured for the plate the server just issued to that player

**Dealership simulator**
- **Business ownership:** admins give a dealership a business price, and a banner in the shop lets any player buy it. Owners can sell it back for 60% of the price (configurable) plus whatever is left in the account.
- **Business account:** all sales go into the dealership's own funds. Owners withdraw, and managers can deposit. Every movement is logged.
- **Inventory:** owned dealerships run on real stock. Managers order units at wholesale cost, and they arrive after a delivery timer. Retail prices are set within a markup range of cost.
- **Staff:** hire nearby players as *Salesperson* or *Manager*, each with their own commission %, which is paid from business funds on every deal they close.
  - Owner: everything.
  - Manager: stock, pricing, hiring salespeople, deposits.
  - Salesperson: selling.
- **Sales desk:** staff send a priced offer to a nearby player. The player gets an accept/decline popup, pays, and the car is delivered.
- **AI walk-in customers:** while staff are on duty (within 60 m), NPC customers turn up next to the display cars wanting a specific in-stock vehicle. Walk up, press **E** and haggle:
  - Accept their offer, counter, or decline.
  - Each customer has a hidden budget. Push too hard and they leave; insult them and reputation drops.
  - Reputation (0–100) controls how often customers come and how much they're willing to pay.
- **Logistics job:** ordered stock doesn't just appear. Each vehicle waits as a shipment at the depot (Port of Los Santos by default).
  - Players with the `logistics` job, or the dealership's own staff, open the depot board, take a job and drive the vehicle to the dealership's **Stock drop-off** point.
  - Pay is the freight fee the dealership paid (base fee plus a per-km rate), scaled by the vehicle's condition. The damage deduction is refunded to the dealership.
  - If the vehicle is wrecked, the driver runs out of time or disconnects, the shipment goes back on the board.
  - Shipments nobody claims arrive by NPC freight after 30 minutes (configurable), so dealerships never get stuck.
- **Management panel** (press **G** at the catalogue point): sales stats and a 7-day revenue chart, inventory and orders, the sales desk, staff, and finance with the transaction log.

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

## Running a dealership (simulator quick start)

1. In the creator's **General** tab, set a **Business price** (for example 750000) and save.
2. A player opens the catalogue and clicks **Buy business**. Unlimited stock becomes 0, so the dealership has to restock.
3. Press **G** at the catalogue point. Deposit money under **Finance**, then order vehicles under **Inventory** and set your prices.
4. Hire staff under **Staff** (stand next to them, then press **Refresh**).
5. Order arrivals: each car is a shipment at the depot. Haul it yourself, or wait for a logistics driver or NPC freight. Set a **Stock drop-off** point in the creator's Locations tab to say where drivers park.
6. Stay at the dealership. Walk-in customers appear by the display cars: press **E** to negotiate. Or use the **Sales desk** to sell to a player standing nearby.

Admins can revoke ownership from the creator. With `Config.Simulation.adminFullAccess`, admins can also open any owned dealership's panel.

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

`Config.UI` sets the accent colour used across every window (any `#rrggbb`) and the speed unit for vehicle stats (`kmh` / `mph`).

`Config.TestDrive` sets the duration, cooldown, max range, whether showroom cars can be test driven, and the private instance.

`Config.Simulation` holds the business settings:
- Markup range, delivery time and default commissions
- Duty radius, upkeep and sell-back ratio
- Whether owned dealerships still allow self-service purchases
- AI customers: spawn rate, patience, negotiation rounds and ped models

`Config.Logistics` covers the haulage job:
- The job name (`''` lets anyone haul), and whether dealership staff can haul their own orders
- The freight fee formula, minimum pay, time limit and NPC-freight fallback
- The depot's board location and loading-bay spawns. **Check these on your map.** The defaults are at the Elysian Island docks.

Set `Config.Logistics.enabled = false` to go back to timed deliveries.

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
| `gen_dealership_sales` | sales log (buyer, price, payment, seller, kind: shop / staff / npc) |
| `gen_dealership_business` | ownership, business funds, reputation, business price |
| `gen_dealership_employees` | staff per dealership (role, commission) |
| `gen_dealership_orders` | wholesale stock orders and delivery times |
| `gen_dealership_shipments` | freight units waiting at the depot or in transit |
| `gen_dealership_transactions` | business ledger (sales, orders, commissions, deposits…) |
| `gen_dealership_owned` | owned vehicles, standalone mode only |
