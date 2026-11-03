# gen_dealership — FiveM Vehicle Dealership Creator & Simulator

Build vehicle dealerships **in-game**, let players **run them as businesses**, and have stock **hauled by a logistics job**.

Works with **Qbox**, **QBCore**, **ESX** and **standalone** (detected automatically). Requires **oxmysql**. **ox_target** and **ox_inventory** / **qb-inventory** are optional and detected automatically.

## Features

### Creator (`/dealercreator`)
- **Create dealerships in-game** with no config editing or restarts. Changes sync live to every player.
- **Placement tool:** a see-through ghost car shows where each point goes.
  - Required points: catalogue (the interaction point and blip) and delivery spawn.
  - Optional points: test-drive spawn, stock drop-off, and a 3D preview stage.
- **Catalogue:** add cars by spawn name. A model check fills in the label and category. Set retail price, wholesale cost and stock for each car.
- **Showroom:** up to 30 display cars. Players see each car's price as they walk up.
- **Other settings:** blip, job restriction, and a business price if you want players to be able to buy the dealership. Admins can also revoke a player's ownership here.

### Buying
- **Catalogue:**
  - Search, categories and sorting.
  - Stock labels and vehicle photos.
  - Arrow keys move between cars.
- **Real stats:** top speed, acceleration, braking, handling and seats, read from the game.
- **3D preview and paint:** the camera orbits the actual car. Drag to rotate, scroll to zoom, and pick primary and secondary paint. The chosen colours are saved to the owned vehicle.
- **Financing:**
  - Choose a deposit (20–90%) and a term (4, 8 or 12 instalments with interest).
  - Instalments are taken from the bank while the buyer is online.
  - Too many missed payments in a row means the car is repossessed.
  - Players check, pay early or pay off their contracts with `/financing`.
- **Custom plates** for a fee, checked for format and uniqueness.
- **Trade-ins:** drive your car to the dealership and click "Sell your car" to get a quote based on its condition. The money goes to your bank and the car goes to the dealership's pre-owned lot.
- **Pre-owned lot:** trade-ins and repossessions are resold in a "Pre-owned" category, showing their condition.
- **Test drives:**
  - Start one from the catalogue, or walk up to a showroom car and press E.
  - Timed, with a range limit; **X** ends it early.
  - Optional private instance (routing bucket) per test drive.
- **Registration papers:** an inventory item with plate, owner and vehicle details is given on purchase (ox_inventory / qb-inventory).

### Dealership simulator (player-owned businesses)
- **Ownership and funds:** buy the business, run its account, sell it back. Every money movement is logged.
- **Stock:** order wholesale. Market events can change wholesale cost. Retail prices are set within a markup range.
- **Staff:**
  - Owner, Manager and Salesperson roles.
  - Commission per employee.
  - Clock-in shifts with **hourly wages** paid from business funds, plus shift history.
- **Weekly sales target:** a bonus for each employee who hits it. There's also a top-seller **leaderboard** and a server-wide dealership **ranking**.
- **Sales desk:** send a priced offer to a nearby player. They accept, pay, and get the car.
- **AI walk-in customers:**
  - They show up while staff are on duty, and you haggle (accept, counter or decline).
  - Reputation (0–100) sets how often customers come and how much they'll pay.
- **Market events:** for example "SUV craze", "Supplier shortage" or "Recession". They swing demand, customer budgets and wholesale costs. They start randomly, or an admin starts one with `/dealermarket`.
- **Advertising:** flyers, radio or billboard campaigns raise customer traffic. Radio and billboard also broadcast your message to every player.
- **Management panel** (press **G** at the catalogue point): Overview, Inventory (including the pre-owned lot), Sales desk, Staff, Marketing and Finance.

### Logistics job
- **Freight shipments:** ordered stock waits at the depot (Port of LS by default) as shipments, each with a freight fee.
- **Who can haul:** players with the `logistics` job, logistics-company drivers, or the dealership's own staff.
- **Job types:**
  - Single deliveries.
  - **Car carrier** jobs: a truck and car-carrier trailer taking up to 4 vehicles at a pay bonus.
- **Pay:** based on the cargo's condition. **High-value cargo** pays extra.
- **Cargo insurance:** pay a premium on delivery, and get compensation if the cargo is lost. Uninsured losses cost a penalty instead.
- **Hijacks:** armed NPCs chase some hauls. Surviving an ambush earns hazard pay.
- **Logistics company:** a player can buy it to take a cut of every haul, hire drivers (who can then haul without the job), and withdraw the profits.
- **NPC freight:** shipments nobody takes arrive automatically after 30 minutes (configurable).

### Admin and integrations
- **`/dealeradmin` dashboard:**
  - Sales, revenue, top models and sales channels.
  - Every dealership's owner, funds, reputation, stock and staff.
  - Finance outstanding, freight and the logistics company.
  - The biggest money movements, plus starting or ending market events.
- **Discord webhooks:** sales, business, finance, logistics and admin events. Webhook URLs live in `server/webhooks_config.lua`, which is server-only.
- **ox_target:** third-eye options for the catalogue, management, showroom cars (test drive or view), AI customers and the logistics board. They're used automatically when ox_target is running.
- **Translations:** `locales/en.lua` and `locales/es.lua`, selected with `Config.Locale`. The in-game messages are translated; the NUI windows are English.
- **Security:** everything is checked on the server, including permissions, input cleaning, distance, stock and money checks, purchase locks, refunds, and plate checks for keys and deliveries.

## Installation

1. Drop the folder into `resources` (for example `[gen]/gen_dealership`).
2. Make sure `oxmysql` is running. All tables are created and migrated automatically; `sql/install.sql` is included for reference.
3. In `server.cfg`, start it **after** your framework (and after ox_target / ox_inventory if you use them):
   ```cfg
   ensure oxmysql
   ensure qb-core        # or qbx_core / es_extended
   ensure gen_dealership

   add_ace group.admin dealership.admin allow
   ```
4. Optional:
   - Create a `logistics` job in your framework, or set `Config.Logistics.job = ''`.
   - Add a `vehicle_registration` item to your inventory, or set `Config.Papers.enabled = false`.
   - Paste Discord webhook URLs into `server/webhooks_config.lua`.
5. **Check `Config.Logistics.depot` in-game.** The default board and loading-bay coordinates are at the Elysian Island docks; adjust them to your map. Carrier trucks need about 25 m of clear space behind the bay.

## Quick start

1. `/dealercreator` → **+ New dealership**: place the points, add vehicles, place showroom cars, and save. Optionally set a business price.
2. Players open the catalogue with **E** to buy, finance, customise, test drive or trade in.
3. A player buys the business from the shop banner, then presses **G** to manage it: order stock, set prices, hire staff, clock in.
4. Logistics drivers open the depot board, take single or carrier jobs, and deliver the stock.
5. Staff on duty haggle with AI customers (**E** on them) or send offers from the sales desk.

## Commands

| Command | Who | What |
|---|---|---|
| `/dealercreator` | admin | Create and edit dealerships |
| `/dealeradmin` | admin | Server-wide dashboard |
| `/dealermarket <id\|random\|clear\|list>` | admin / console | Control market events |
| `/financing` | players | View and pay finance contracts |

## Configuration

Everything is in `config.lua`, with a comment on each option:

| Section | Covers |
|---|---|
| General | Framework, permissions, keys, distances |
| `Config.TestDrive` | Duration, range, private instance |
| `Config.Simulation` | Markup, staff, wages, AI customers |
| `Config.Logistics` | Fees, depot, carrier jobs, insurance, hijacks, company |
| Buying | `Config.Preview`, `Config.Colors`, `Config.CustomPlate`, `Config.Finance`, `Config.TradeIn`, `Config.UsedLot` |
| `Config.Market` | Market events |
| `Config.Advertising` | Ad campaigns |
| `Config.Papers` | Registration papers |
| `Config.Target` | ox_target |
| `Config.UI` | Accent colour, speed unit |
| `Config.Locale` | Language |

## Integrations

| What | Supported | Where to change |
|---|---|---|
| Framework | qbx_core, qb-core, es_extended, standalone | `bridge/server.lua`, `bridge/client.lua` |
| Owned vehicles | qbx_vehicles, `player_vehicles`, `owned_vehicles`, own table | `Bridge.GiveVehicle` / `GetOwnedVehicle` / `RemoveVehicle` |
| Keys | qbx_vehiclekeys, qb-vehiclekeys, wasabi_carlock | `Bridge.GiveKeys` |
| Fuel | LegacyFuel, ox_fuel, cdn-fuel, native | `Bridge.SetFuel` |
| Items | ox_inventory, qb-inventory | `Bridge.GiveItem` |
| Interaction | E prompts, ox_target | `client/target.lua` |

## Exports (server)

```lua
exports.gen_dealership:GetDealerships()
exports.gen_dealership:GetDealership('pdm')
```
