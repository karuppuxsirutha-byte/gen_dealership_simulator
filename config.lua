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
}

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

Config.Text = {
    open_shop          = '~INPUT_CONTEXT~ Browse %s',
    open_shop_manage   = '~INPUT_CONTEXT~ Browse %s~n~~INPUT_DETONATE~ Manage business',
    talk_customer      = '~INPUT_CONTEXT~ Talk to customer',
    delivered_garage   = 'The delivery spot was blocked, so your vehicle was sent to your garage.',
    staff_only         = 'Purchases here go through a salesperson.',
    open_logistics     = '~INPUT_CONTEXT~ Open logistics board',
    deliver_vehicle    = '~INPUT_CONTEXT~ Deliver vehicle',
    haul_status        = 'Deliver %s to %s · %s left',
    haul_failed        = 'Delivery failed: %s',
    haul_paid          = 'Delivered %s (condition %d%%). You earned %s.',
    no_permission      = 'You do not have permission to do that.',
    not_enough_money   = 'You cannot afford this vehicle.',
    out_of_stock       = 'This vehicle is out of stock.',
    too_far            = 'You are too far from the dealership.',
    no_access          = 'You cannot use this dealership.',
    vehicle_not_found  = 'That vehicle is no longer available.',
    spawn_blocked      = 'The delivery spot is blocked. Clear it and try again.',
    purchase_failed    = 'Purchase failed. You have been refunded.',
    purchased          = 'You bought a %s for %s. Plate: %s',
    testdrive_disabled = 'Test drives are disabled here.',
    testdrive_active   = 'You are already on a test drive.',
    testdrive_cooldown = 'Wait %s seconds before another test drive.',
    testdrive_hud      = 'Test drive · %s left',
    testdrive_end_key  = '~INPUT_VEH_DUCK~ End test drive',
    testdrive_started  = 'Test driving the %s for %s seconds. Have fun!',
    testdrive_display  = '~INPUT_CONTEXT~ Test drive %s',
    testdrive_ended_early = 'Test drive ended. Come back any time!',
    testdrive_too_far  = 'You drove too far, so the test drive was ended.',
    testdrive_over     = 'Your test drive is over.',
    busy               = 'Please wait…',
    placement_help     = '~INPUT_CONTEXT~ Confirm~n~~INPUT_DETONATE~ Use my position~n~~INPUT_WEAPON_WHEEL_NEXT~ / ~INPUT_CELLPHONE_LEFT~ Rotate (~INPUT_SPRINT~ faster)~n~~INPUT_CELLPHONE_CANCEL~ Cancel',
    saved              = 'Dealership saved.',
    deleted            = 'Dealership deleted.',
}
