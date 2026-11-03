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
    duration = 60,       -- seconds
    cooldown = 120,      -- seconds between test drives per player
    platePrefix = 'TEST',
}

-- Standalone mode has no economy: should purchases be free?
Config.Standalone = { FreePurchases = true }

-- Placement tool
Config.Placement = {
    distance = 40.0,
    previewModel = 'adder',
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
    testdrive_left     = 'Test drive: %ss left',
    testdrive_over     = 'Your test drive is over.',
    busy               = 'Please wait…',
    placement_help     = '~INPUT_CONTEXT~ Confirm~n~~INPUT_DETONATE~ Use my position~n~~INPUT_WEAPON_WHEEL_NEXT~ / ~INPUT_CELLPHONE_LEFT~ Rotate (~INPUT_SPRINT~ faster)~n~~INPUT_CELLPHONE_CANCEL~ Cancel',
    saved              = 'Dealership saved.',
    deleted            = 'Dealership deleted.',
}
