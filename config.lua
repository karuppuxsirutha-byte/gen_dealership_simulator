Config = {}

-- 'auto' | 'qbx' | 'qb' | 'esx' | 'standalone'
Config.Framework = 'auto'

-- Players with this ACE (or framework admin group) can use the creator.
-- server.cfg: add_ace group.admin dealership.admin allow
Config.AdminAce = 'dealership.admin'
Config.CreatorCommand = 'dealercreator'

-- Interaction
Config.InteractKey = 38            -- E
Config.InteractDistance = 2.0
Config.MarkerDrawDistance = 20.0
Config.Marker = { type = 36, scale = 0.8, color = { 30, 144, 255, 180 } }

-- Showroom display vehicles (client-side, non-networked)
Config.DisplayRenderDistance = 80.0
Config.DisplayLabelDistance = 6.0
Config.DisplayPlate = 'FORSALE'

-- Limits enforced by the server when saving
Config.MaxVehiclesPerDealership = 250
Config.MaxDisplaySpots = 30

-- Purchases
Config.PaymentMethods = { 'bank', 'cash' }   -- first entry is the default
Config.Currency = 'USD'
Config.PlateFormat = '11AAA111'              -- 1 = digit, A = letter, . = either, anything else literal
Config.DefaultGarage = 'pillboxgarage'       -- QB / Qbox garage purchased vehicles are registered to
Config.PurchaseDistance = 10.0               -- max distance (server-checked) from the catalogue point

-- Test drives
Config.TestDrive = {
    enabled = true,
    duration = 60,             -- seconds
    cooldown = 120,            -- seconds between test drives per player
    platePrefix = 'TEST',
    maxDistance = 1500.0,      -- metres from the test drive spawn before it ends (0 = unlimited)
    fromDisplays = true,       -- press E next to a showroom car to test drive it
    displayInteractDistance = 3.5,
    privateInstance = false,   -- drive in a private routing bucket (no other players / traffic collisions)
    bucketBase = 7000,         -- private bucket = bucketBase + player id
}

-- Standalone mode has no economy: should purchases be free?
Config.Standalone = { FreePurchases = true }

-- Placement tool
Config.Placement = {
    distance = 40.0,
    previewModel = 'adder',
}

-- ===========================================================================
-- Dealership simulator (player-owned businesses)
-- ===========================================================================
Config.Simulation = {
    enabled = true,
    selfService = true,          -- players can still buy from the catalogue of an owned dealership
    adminFullAccess = true,      -- admins can open any owned dealership's management panel
    maxOwnedPerPlayer = 1,
    sellBackRatio = 0.6,         -- owners can sell the business back for this share of its price
    startReputation = 50,        -- 0-100, drives AI customer frequency and budgets

    -- Pricing: wholesale cost defaults to price * ratio; owners price between cost*min and cost*max
    defaultCostRatio = 0.7,
    minMarkup = 0.9,
    maxMarkup = 2.0,

    -- Stock orders
    deliveryTime = 300,          -- seconds until ordered vehicles arrive
    maxOrderQty = 10,

    -- Staff
    maxEmployees = 12,
    commission = { manager = 5, sales = 10 },   -- default % of the sale price
    maxCommission = 50,
    dutyRadius = 60.0,           -- staff within this distance of the catalogue point are "on duty"
    offerTimeout = 60,           -- seconds a player has to answer a staff offer

    -- Shifts & wages
    requireClockIn = true,       -- staff must clock in (management panel) to count as on duty
    wages = { manager = 400, sales = 250 },  -- default hourly wage, paid from business funds
    maxWage = 2000,
    wagePayInterval = 600,       -- seconds between wage payouts (and on clock-out)
    autoClockOut = 900,          -- clock out staff who leave the dealership for this long

    -- Running costs (0 to disable), taken from the business account
    upkeep = 0,
    upkeepInterval = 3600,

    -- AI customers spawn while staff are on duty and haggle over in-stock vehicles
    customers = {
        enabled = true,
        interval = 45,           -- seconds between spawn rolls per dealership
        baseChance = 0.45,
        maxActive = 3,
        patience = 300,          -- seconds before an unattended customer leaves (-1 reputation)
        maxRounds = 3,           -- counter-offers before the customer walks
        peds = {
            'a_m_y_business_01', 'a_f_y_business_01', 'a_m_m_business_01', 'a_f_y_business_02',
            'a_m_y_hipster_01', 'a_f_y_hipster_02', 'a_m_m_bevhills_02', 'a_f_m_bevhills_01',
            'a_m_y_genstreet_01', 'a_f_y_tourist_01',
        },
    },
}

-- ===========================================================================
-- Logistics: ordered stock is hauled from a depot to the dealership by players
-- ===========================================================================
Config.Logistics = {
    enabled = true,              -- false = orders simply arrive after Config.Simulation.deliveryTime
    job = 'logistics',           -- framework job that may haul shipments ('' = anyone)
    staffCanDeliver = true,      -- dealership staff may haul their own dealership's orders
    baseFee = 500,               -- freight fee per vehicle = baseFee + perKm * distance (charged on order)
    perKm = 250,
    minPayoutRatio = 0.25,       -- driver pay scales with vehicle condition, never below this share
    timeLimit = 900,             -- seconds to complete a haul once the vehicle is taken
    autoDeliverAfter = 1800,     -- unclaimed shipments arrive by NPC freight after this many seconds (0 = never)
    dropRadius = 6.0,
    platePrefix = 'CARGO',
    depot = {
        label = 'Port of Los Santos',
        board = vector4(153.68, -3211.88, 5.91, 270.0),   -- where drivers open the logistics board
        spawns = {                                          -- where shipment vehicles are parked
            vector4(141.12, -3204.31, 5.85, 267.5),
            vector4(141.12, -3199.31, 5.85, 267.5),
            vector4(141.12, -3209.31, 5.85, 267.5),
        },
        blip = { sprite = 477, color = 21, scale = 0.8 },
    },

    -- Car carrier jobs: haul several vehicles for one dealership at once (truck + trailer)
    carrier = {
        enabled = true,
        minLoad = 2,             -- shipments for one dealership needed to offer a carrier job
        capacity = 4,
        bonus = 1.15,            -- pay multiplier vs. hauling the same cars one by one
        truck = 'packer',
        trailer = 'tr4',         -- car-carrier trailer
        spawn = nil,             -- vector4 for the truck (nil = first free loading bay); needs ~25 m of space behind
        dropRadius = 14.0,
        timeMultiplier = 1.5,    -- carriers get more time
    },

    -- High-value cargo pays extra (and attracts hijackers)
    highValue = { threshold = 250000, bonus = 0.5 },

    -- Drivers choose whether to insure their cargo when taking a job
    insurance = {
        premium = 0.10,          -- share of pay deducted on delivery when insured
        payout = 0.25,           -- share of pay received if insured cargo is lost
        uninsuredPenalty = 0.20, -- share of pay charged if uninsured cargo is lost
    },

    -- Hijack events: armed NPCs chase the driver
    hijack = {
        enabled = true,
        chance = 0.12,
        highValueChance = 0.35,
        carrierChance = 0.25,
        hazardBonus = 0.25,      -- extra pay when you deliver despite an ambush
        delay = { 45, 120 },     -- seconds after leaving the depot
        vehicle = 'cavalcade2',
        peds = { 'g_m_y_mexgoon_01', 'g_m_y_lost_01', 'g_m_m_chicold_01' },
        weapon = 'WEAPON_MICROSMG',
    },

    -- A player-owned logistics company takes a cut of every haul and can hire drivers
    company = {
        enabled = true,
        label = 'Port Logistics Co.',
        price = 500000,
        defaultCut = 15,         -- % of each haul's pay that goes to the company
        maxCut = 40,
        sellBackRatio = 0.6,
        maxDrivers = 20,
    },
}

-- ===========================================================================
-- Buying experience
-- ===========================================================================

-- 3D preview: the car is shown at the dealership's "preview" point (creator → Locations),
-- falling back to the delivery spawn. It is a local entity only the viewer sees.
Config.Preview = { enabled = true }

-- Paint colours offered in the preview (GTA colour index, label, swatch colour for the UI)
Config.Colors = {
    { id = 0,   label = 'Black',        hex = '#0d1116' },
    { id = 12,  label = 'Matte Black',  hex = '#13181f' },
    { id = 1,   label = 'Graphite',     hex = '#1c1d21' },
    { id = 4,   label = 'Silver',       hex = '#9ca1a3' },
    { id = 111, label = 'Frost White',  hex = '#f0f0f0' },
    { id = 27,  label = 'Red',          hex = '#c00e1a' },
    { id = 38,  label = 'Orange',       hex = '#f78616' },
    { id = 89,  label = 'Race Yellow',  hex = '#f5d20f' },
    { id = 92,  label = 'Lime',         hex = '#66b81f' },
    { id = 50,  label = 'Racing Green', hex = '#122e2b' },
    { id = 64,  label = 'Blue',         hex = '#2354a1' },
    { id = 70,  label = 'Ultra Blue',   hex = '#2446a8' },
    { id = 145, label = 'Purple',       hex = '#621276' },
    { id = 135, label = 'Hot Pink',     hex = '#f21f99' },
    { id = 90,  label = 'Bronze',       hex = '#9c6a3f' },
}

-- Custom plate text at purchase (2-8 characters, A-Z 0-9 and spaces)
Config.CustomPlate = { enabled = true, price = 5000 }

-- Financing: pay a deposit now, the rest in instalments taken from the bank
Config.Finance = {
    enabled = true,
    minPrice = 20000,          -- cheaper vehicles must be paid in full
    minDeposit = 0.2,          -- 20% minimum deposit
    terms = {
        { payments = 4,  interest = 0.08 },
        { payments = 8,  interest = 0.15 },
        { payments = 12, interest = 0.22 },
    },
    interval = 7200,           -- seconds between instalments (collected while the buyer is online)
    maxMissed = 3,             -- missed payments in a row before repossession
    command = 'financing',     -- players check / pay off their contracts with /financing
}

-- Trade-ins: sell your owned car to a dealership (it becomes a pre-owned listing)
Config.TradeIn = {
    enabled = true,
    ratio = 0.5,               -- of the catalogue price, scaled by condition
    radius = 25.0,             -- the car must be this close to the catalogue point
}

-- Pre-owned lot: trade-ins and repossessions are resold
Config.UsedLot = {
    enabled = true,
    markup = 1.3,              -- listing price = trade-in value * markup
    maxPerDealership = 25,
}

-- ===========================================================================
-- Market events: random demand / cost swings (admins: /dealermarket <id|random|clear>)
-- ===========================================================================
Config.Market = {
    enabled = true,
    interval = 5400,       -- seconds between rolls for a new event
    chance = 0.7,          -- chance a roll starts an event
    duration = 3600,       -- default event length (seconds)
    events = {
        { id = 'suv_craze',       label = 'SUV craze',          description = 'Families are upgrading. Everyone wants an SUV.', category = 'suvs', demand = 1.8 },
        { id = 'track_day',       label = 'Track day hype',     description = 'A big race weekend has people buying sports cars.', category = 'sports', demand = 1.6, budget = 1.05 },
        { id = 'bike_season',     label = 'Bike season',        description = 'Sunny weather brings out the riders.', category = 'motorcycles', demand = 1.7, cost = 1.1 },
        { id = 'super_clearance', label = 'Supercar clearance', description = 'Importers are clearing old supercar stock.', category = 'super', cost = 0.85 },
        { id = 'fuel_spike',      label = 'Fuel price spike',   description = 'Gas is expensive. Nobody wants a muscle car.', category = 'muscle', demand = 0.6 },
        { id = 'shortage',        label = 'Supplier shortage',  description = 'A chip shortage pushes wholesale prices up.', cost = 1.25, demand = 0.9 },
        { id = 'boom',            label = 'Economic boom',      description = 'Wallets are full and spirits are high.', demand = 1.3, budget = 1.08 },
        { id = 'recession',       label = 'Recession',          description = 'Customers are cautious and bargain hard.', demand = 0.75, budget = 0.94 },
    },
}

-- Advertising campaigns owners/managers can buy (boost = extra AI customer traffic)
Config.Advertising = {
    campaigns = {
        { id = 'flyers',    label = 'Flyers',     cost = 2500,  boost = 25,  duration = 1800, announce = false },
        { id = 'radio',     label = 'Radio spot', cost = 10000, boost = 60,  duration = 3600, announce = true },
        { id = 'billboard', label = 'Billboard',  cost = 30000, boost = 120, duration = 7200, announce = true },
    },
}

-- Registration papers given on purchase (needs the item in ox_inventory / qb-inventory)
Config.Papers = { enabled = true, item = 'vehicle_registration', warnMissing = true }

-- ox_target third-eye options (used automatically when ox_target is running)
Config.Target = { enabled = true }

-- UI look & feel
Config.UI = {
    accent = '#3d8bff',   -- any #rrggbb colour
    speedUnit = 'kmh',    -- 'kmh' | 'mph'
}

Config.DefaultBlip = { enabled = true, sprite = 326, color = 3, scale = 0.8 }

Config.Categories = {
    { id = 'compacts',       label = 'Compacts' },
    { id = 'sedans',         label = 'Sedans' },
    { id = 'suvs',           label = 'SUVs' },
    { id = 'coupes',         label = 'Coupes' },
    { id = 'muscle',         label = 'Muscle' },
    { id = 'sportsclassics', label = 'Sports Classics' },
    { id = 'sports',         label = 'Sports' },
    { id = 'super',          label = 'Super' },
    { id = 'motorcycles',    label = 'Motorcycles' },
    { id = 'offroad',        label = 'Off-road' },
    { id = 'industrial',     label = 'Industrial' },
    { id = 'utility',        label = 'Utility' },
    { id = 'vans',           label = 'Vans' },
    { id = 'cycles',         label = 'Cycles' },
    { id = 'boats',          label = 'Boats' },
    { id = 'helicopters',    label = 'Helicopters' },
    { id = 'planes',         label = 'Planes' },
    { id = 'service',        label = 'Service' },
    { id = 'emergency',      label = 'Emergency' },
    { id = 'military',       label = 'Military' },
    { id = 'commercial',     label = 'Commercial' },
    { id = 'other',          label = 'Other' },
}

-- GTA vehicle class -> category suggestion used by the creator's model check
Config.ClassCategories = {
    [0] = 'compacts', [1] = 'sedans', [2] = 'suvs', [3] = 'coupes', [4] = 'muscle',
    [5] = 'sportsclassics', [6] = 'sports', [7] = 'super', [8] = 'motorcycles',
    [9] = 'offroad', [10] = 'industrial', [11] = 'utility', [12] = 'vans', [13] = 'cycles',
    [14] = 'boats', [15] = 'helicopters', [16] = 'planes', [17] = 'service',
    [18] = 'emergency', [19] = 'military', [20] = 'commercial',
}

-- Language: see locales/*.lua ('en', 'es')
Config.Locale = 'en'
