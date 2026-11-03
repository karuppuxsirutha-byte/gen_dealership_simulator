local T = Utils.T

local Dealerships, ById = {}, {}
local Loaded = false

local purchaseLock = {}   -- [src] = true while a purchase is processing
local testDrives = {}     -- [src] = { expires = os.time() }
local testCooldown = {}   -- [src] = os.time() of last test drive end
local issuedPlates = {}   -- [src] = plate the client is allowed to request keys for

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function reload()
    Dealerships, ById = DB.LoadAll()
    for _, d in ipairs(Dealerships) do
        Biz.Decorate(d)
        UsedLot.Attach(d)
    end
end

local function broadcast(target)
    TriggerClientEvent('gen_dealership:sync', target or -1, Dealerships)
end

-- Shared with server/business.lua & server/simulation.lua
function GetDealershipById(id) return ById[tonumber(id)] end
function GetAllDealerships() return Dealerships end
function BroadcastDealerships(target) broadcast(target) end
function IssuePlate(src, plate) issuedPlates[src] = plate end

local function trim(s)
    if type(s) ~= 'string' then return nil end
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function cleanText(s, max)
    s = trim(s)
    if not s then return nil end
    s = s:gsub('[<>]', '')
    if #s > max then s = s:sub(1, max) end
    return s
end

local function clampInt(v, min, max, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    v = math.floor(v)
    if v < min then return min end
    if v > max then return max end
    return v
end

local function clampNum(v, min, max, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    return math.min(max, math.max(min, v))
end

local function sanitizeVec4(t)
    if not Utils.IsVec4(t) then return nil end
    return {
        x = Utils.Round(tonumber(t.x), 3),
        y = Utils.Round(tonumber(t.y), 3),
        z = Utils.Round(tonumber(t.z), 3),
        w = Utils.Round(tonumber(t.w) % 360, 2),
    }
end

function IsNear(src, point, maxDist)
    if not point then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end -- OneSync off: cannot verify
    local c = GetEntityCoords(ped)
    return #(c - vector3(point.x, point.y, point.z)) <= maxDist
end

function CanUseDealership(src, d)
    if not d.job then return true end
    return Bridge.GetJob(src) == d.job
end

function FindVehicle(d, vehicleId)
    vehicleId = tonumber(vehicleId)
    for _, v in ipairs(d.vehicles) do
        if v.id == vehicleId then return v end
    end
end

local charset = { letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ', digits = '0123456789' }
local function randomPlate()
    local out = {}
    for i = 1, #Config.PlateFormat do
        local c = Config.PlateFormat:sub(i, i)
        local pool
        if c == '1' then pool = charset.digits
        elseif c == 'A' then pool = charset.letters
        elseif c == '.' then pool = charset.letters .. charset.digits end
        if pool then
            local n = math.random(1, #pool)
            out[#out + 1] = pool:sub(n, n)
        else
            out[#out + 1] = c
        end
    end
    return table.concat(out):sub(1, 8)
end

local function generatePlate()
    for _ = 1, 50 do
        local plate = randomPlate()
        if not Bridge.PlateExists(plate) then return plate end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Sanitizing creator input (never trust the client)
-- ---------------------------------------------------------------------------

local function sanitizeDealership(data)
    if type(data) ~= 'table' then return nil, 'Invalid data.' end

    local name = trim(data.name)
    if not name or #name < 2 or #name > 64 or not name:match('^[%w_%-]+$') then
        return nil, 'Identifier must be 2-64 characters: letters, numbers, - or _.'
    end
    name = name:lower()

    local label = cleanText(data.label, 100)
    if not label or label == '' then return nil, 'A display name is required.' end

    local job = trim(data.job or '') or ''
    if job ~= '' and (#job > 64 or not job:match('^[%w_%-]+$')) then
        return nil, 'Invalid job name.'
    end

    local id = tonumber(data.id)
    if id and not ById[id] then return nil, 'This dealership no longer exists.' end

    for _, other in ipairs(Dealerships) do
        if other.name == name and other.id ~= id then
            return nil, ('Identifier "%s" is already used.'):format(name)
        end
    end

    local b = type(data.blip) == 'table' and data.blip or {}
    local blip = {
        enabled = b.enabled ~= false,
        sprite = clampInt(b.sprite, 1, 900, Config.DefaultBlip.sprite),
        color = clampInt(b.color, 0, 85, Config.DefaultBlip.color),
        scale = Utils.Round(clampNum(b.scale, 0.2, 3.0, Config.DefaultBlip.scale), 2),
    }

    local shop = sanitizeVec4(data.shop)
    local spawn = sanitizeVec4(data.spawn)
    if not shop then return nil, 'The catalogue point must be placed.' end
    if not spawn then return nil, 'The delivery spawn must be placed.' end

    local vehicles, seen = {}, {}
    for _, v in ipairs(type(data.vehicles) == 'table' and data.vehicles or {}) do
        if #vehicles >= Config.MaxVehiclesPerDealership then break end
        local model = type(v) == 'table' and trim(v.model)
        model = model and model:lower()
        if Utils.ValidModelName(model) and not seen[model] then
            seen[model] = true
            local category = type(v.category) == 'string' and v.category or 'other'
            if not Utils.CategoryExists(category) then category = 'other' end
            local price = clampInt(v.price, 0, 1000000000, 0)
            local cost = clampInt(v.cost, 0, 1000000000, nil)
            vehicles[#vehicles + 1] = {
                model = model,
                label = cleanText(v.label, 100) ~= '' and cleanText(v.label, 100) or model,
                category = category,
                price = price,
                cost = cost or math.floor(price * Config.Simulation.defaultCostRatio),
                stock = clampInt(v.stock, -1, 1000000, -1),
            }
        end
    end

    local displays = {}
    for _, s in ipairs(type(data.displays) == 'table' and data.displays or {}) do
        if #displays >= Config.MaxDisplaySpots then break end
        local pos = sanitizeVec4(s)
        local model = type(s) == 'table' and trim(s.model)
        model = model and model:lower()
        if pos and Utils.ValidModelName(model) then
            pos.model = model
            displays[#displays + 1] = pos
        end
    end

    local business = type(data.business) == 'table' and data.business or {}

    return {
        id = id,
        name = name,
        businessPrice = clampInt(business.price, 0, 2000000000, 0),
        label = label,
        job = job ~= '' and job or nil,
        blip = blip,
        shop = shop,
        spawn = spawn,
        testdrive = sanitizeVec4(data.testdrive),
        delivery = sanitizeVec4(data.delivery),
        preview = sanitizeVec4(data.preview),
        displays = displays,
        vehicles = vehicles,
    }
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

MySQL.ready(function()
    DB.Init()
    Biz.Load()
    UsedLot.Load()
    Finance.Load()
    reload()
    Logistics.Load()
    Loaded = true
    broadcast()
    print(('^2[gen_dealership]^0 Loaded %d dealership(s) | framework: %s'):format(#Dealerships, Bridge.Framework))
end)

-- ---------------------------------------------------------------------------
-- Public data
-- ---------------------------------------------------------------------------

RegisterCallback('getDealerships', function()
    return Dealerships
end)

RegisterCallback('shop:balance', function(src)
    return { cash = Bridge.GetMoney(src, 'cash'), bank = Bridge.GetMoney(src, 'bank') }
end)

-- ---------------------------------------------------------------------------
-- Creator
-- ---------------------------------------------------------------------------

RegisterCommand(Config.CreatorCommand, function(src)
    if src == 0 then
        print('[gen_dealership] The creator must be opened in-game.')
        return
    end
    if not Bridge.IsAdmin(src) then
        Bridge.Notify(src, T('no_permission'), 'error')
        return
    end
    TriggerClientEvent('gen_dealership:creator:open', src, Dealerships)
end, false)

RegisterCallback('creator:save', function(src, data)
    if not Bridge.IsAdmin(src) then return { ok = false, error = T('no_permission') } end
    if not Loaded then return { ok = false, error = 'Database not ready yet.' } end

    local d, err = sanitizeDealership(data)
    if not d then return { ok = false, error = err } end

    local owned = d.id ~= nil and Biz.IsOwned(d.id)
    local ok, idOrErr = pcall(DB.Save, d, owned)
    if not ok then
        print(('^1[gen_dealership] save failed: %s^0'):format(idOrErr))
        return { ok = false, error = 'Database error while saving.' }
    end

    Biz.SetPrice(idOrErr, d.businessPrice)
    reload()
    broadcast()
    print(('[gen_dealership] %s saved dealership "%s" (#%s)'):format(GetPlayerName(src), d.name, idOrErr))
    Webhooks.Send('admin', 'Dealership saved', ('**%s** (`%s`, #%s)'):format(d.label, d.name, idOrErr), {
        Webhooks.Field('Admin', Webhooks.Who(src)),
        Webhooks.Field('Vehicles', #d.vehicles),
        Webhooks.Field('Display spots', #d.displays),
    })
    return { ok = true, id = idOrErr, dealerships = Dealerships }
end)

RegisterCallback('creator:delete', function(src, id)
    if not Bridge.IsAdmin(src) then return { ok = false, error = T('no_permission') } end
    id = tonumber(id)
    if not id or not ById[id] then return { ok = false, error = 'Unknown dealership.' } end

    DB.Delete(id)
    UsedLot.Forget(id)
    Logistics.Forget(id)
    Biz.Forget(id)
    RemoveCustomersFor(id)
    reload()
    broadcast()
    print(('[gen_dealership] %s deleted dealership #%s'):format(GetPlayerName(src), id))
    Webhooks.Send('admin', 'Dealership deleted', ('#%s'):format(id), { Webhooks.Field('Admin', Webhooks.Who(src)) }, 'bad')
    return { ok = true, dealerships = Dealerships }
end)

RegisterCallback('creator:resetOwner', function(src, id)
    if not Bridge.IsAdmin(src) then return { ok = false, error = T('no_permission') } end
    id = tonumber(id)
    if not id or not Biz.IsOwned(id) then return { ok = false, error = 'This dealership has no owner.' } end
    Biz.ResetOwnership(id, ('Ownership revoked by admin %s'):format(GetPlayerName(src)))
    print(('[gen_dealership] %s revoked ownership of dealership #%s'):format(GetPlayerName(src), id))
    Webhooks.Send('admin', 'Ownership revoked', ('Dealership #%s'):format(id), { Webhooks.Field('Admin', Webhooks.Who(src)) }, 'warn')
    return { ok = true, dealerships = Dealerships }
end)

-- ---------------------------------------------------------------------------
-- Sales
-- ---------------------------------------------------------------------------

local function validMethod(method)
    for _, m in ipairs(Config.PaymentMethods) do
        if m == method then return m end
    end
    return Config.PaymentMethods[1]
end

--- Normalises custom plate text; nil when invalid.
function NormalizePlate(text)
    if type(text) ~= 'string' then return nil end
    local plate = text:upper():gsub('^%s+', ''):gsub('%s+$', '')
    if #plate < 2 or #plate > 8 or not plate:match('^[A-Z0-9 ]+$') then return nil end
    return plate
end

local validColors = {}
for _, c in ipairs(Config.Colors or {}) do validColors[c.id] = true end

--- Purchase options from the UI → safe vehicle props
local function sanitizeProps(options)
    local props = {}
    local c1, c2 = tonumber(options.color1), tonumber(options.color2)
    if c1 and validColors[c1] then props.color1 = c1 end
    if c2 and validColors[c2] then props.color2 = c2 end
    if props.color1 and not props.color2 then props.color2 = props.color1 end
    return next(props) and props or nil
end

--- Charges the buyer, registers the vehicle, updates stock and routes revenue.
--- Used by the self-service shop and by staff offers.
--- @param opts table|nil { seller, sellerName, sellerIdentifier, kind, props, plate, finance, used }
function ProcessSale(buyer, d, v, method, price, opts)
    opts = opts or {}
    method = validMethod(method)
    local used = opts.used
    if not used and v.stock == 0 then return { ok = false, error = T('out_of_stock') } end
    if purchaseLock[buyer] then return { ok = false, error = T('busy') } end
    purchaseLock[buyer] = true
    local function fail(err)
        purchaseLock[buyer] = nil
        return { ok = false, error = err }
    end

    -- Plate: custom (paid extra) or generated
    local plate, plateFee = nil, 0
    if opts.plate and opts.plate ~= '' then
        if not Config.CustomPlate.enabled then return fail(T('plate_disabled')) end
        plate = NormalizePlate(opts.plate)
        if not plate then return fail(T('plate_invalid')) end
        if Bridge.PlateExists(plate) then return fail(T('plate_taken')) end
        plateFee = Config.CustomPlate.price
    else
        plate = generatePlate()
        if not plate then return fail(T('purchase_failed')) end
    end

    -- re-check availability after the yields above
    if not used and v.stock == 0 then return fail(T('out_of_stock')) end
    if used and used.taken then return fail(T('vehicle_not_found')) end

    -- Financing: deposit now (bank only), instalments later
    local plan
    if opts.finance then
        local err
        plan, err = Finance.Plan(price, opts.finance)
        if not plan then return fail(err) end
        method = 'bank'
    end
    local upfront = (plan and plan.deposit or price) + plateFee

    if not Bridge.RemoveMoney(buyer, method, upfront, ('vehicle-purchase:%s'):format(v.model)) then
        return fail(T('not_enough_money'))
    end

    -- reserve the unit before any further yield
    local reserved = not used and v.stock > 0
    if reserved then v.stock = v.stock - 1 end
    if used then UsedLot.Take(used) end

    local ok, given = pcall(Bridge.GiveVehicle, buyer, v.model, plate, d.name, opts.props)
    if not ok or not given then
        if not ok then print(('^1[gen_dealership] GiveVehicle failed: %s^0'):format(given)) end
        Bridge.AddMoney(buyer, method, upfront, 'vehicle-purchase-refund')
        if reserved then v.stock = v.stock + 1 end
        if used then UsedLot.Restore(used) end
        return fail(T('purchase_failed'))
    end
    if reserved then DB.SetStock(v.id, v.stock) end
    if used then UsedLot.Finalize(used) end

    local commission = 0
    if Biz.IsOwned(d.id) then
        local received = plan and plan.deposit or price
        Biz.AddBalance(d.id, received, 'sale',
            ('%s%s sold to %s%s'):format(used and 'Pre-owned ' or '', v.label, Bridge.GetName(buyer), plan and ' (financed)' or ''),
            opts.sellerName or 'Self-service')
        if opts.seller then commission = Biz.PayCommission(d.id, opts.seller, price, v.label) end
    end
    if plan then Finance.Create(buyer, d, v, plate, plan) end

    DB.LogSale(d.name, Bridge.GetIdentifier(buyer), v.model, plate, price, plan and 'finance' or method, opts.sellerIdentifier, opts.kind or 'shop')
    if opts.sellerIdentifier and opts.sellerIdentifier ~= '' then OnStaffSale(d, opts.sellerIdentifier) end
    Webhooks.Send('sales', ('Vehicle sold · %s'):format(d.label), nil, {
        Webhooks.Field('Vehicle', ('%s%s (`%s`)'):format(used and 'Pre-owned ' or '', v.label, v.model)),
        Webhooks.Field('Price', Utils.FormatMoney(price)),
        Webhooks.Field('Plate', plate .. (plateFee > 0 and ' (custom)' or '')),
        Webhooks.Field('Buyer', Webhooks.Who(buyer)),
        Webhooks.Field('Payment', plan and ('Financed · deposit %s'):format(Utils.FormatMoney(plan.deposit)) or method),
        Webhooks.Field('Sold by', opts.sellerName or 'Self-service'),
    }, 'good')
    if GiveRegistrationPapers then GiveRegistrationPapers(buyer, d, v, plate, plan) end

    issuedPlates[buyer] = plate
    purchaseLock[buyer] = nil
    if reserved then broadcast() end

    return {
        ok = true,
        plate = plate,
        model = v.model,
        label = v.label,
        price = price,
        priceText = plan and ('%s deposit'):format(Utils.FormatMoney(plan.deposit)) or Utils.FormatMoney(price),
        commission = commission,
        props = opts.props,
        condition = used and used.condition or nil,
        financed = plan ~= nil,
    }
end

--- Resolves a shop vehicle id (catalogue or pre-owned) → vehicle table, price, used entry
local function resolveShopVehicle(d, vehicleId)
    local id = tonumber(vehicleId) or 0
    if id >= Utils.USED_OFFSET then
        local used = UsedLot.Find(d.id, id - Utils.USED_OFFSET)
        if not used then return nil end
        return { id = id, model = used.model, label = used.label, stock = 1 }, used.price, used
    end
    local v = FindVehicle(d, id)
    if not v then return nil end
    return v, v.price, nil
end
ResolveShopVehicle = resolveShopVehicle

-- ---------------------------------------------------------------------------
-- Shop
-- ---------------------------------------------------------------------------

RegisterCallback('shop:buy', function(src, dealershipId, vehicleId, method, options)
    options = type(options) == 'table' and options or {}
    local d = ById[tonumber(dealershipId)]
    if not d then return { ok = false, error = T('vehicle_not_found') } end
    if not CanUseDealership(src, d) then return { ok = false, error = T('no_access') } end
    if not IsNear(src, d.shop, Config.PurchaseDistance) then return { ok = false, error = T('too_far') } end
    if Biz.IsOwned(d.id) and not Config.Simulation.selfService then return { ok = false, error = T('staff_only') } end

    local v, price, used = resolveShopVehicle(d, vehicleId)
    if not v then return { ok = false, error = T('vehicle_not_found') } end

    return ProcessSale(src, d, v, method, price, {
        kind = used and 'used' or 'shop',
        props = sanitizeProps(options),
        plate = type(options.plate) == 'string' and options.plate or nil,
        finance = type(options.finance) == 'table' and options.finance or nil,
        used = used,
    })
end)

-- ---------------------------------------------------------------------------
-- Test drives
-- ---------------------------------------------------------------------------

local TD = Config.TestDrive

--- Near the catalogue point or any showroom car of this dealership
local function nearDealership(src, d)
    if IsNear(src, d.shop, Config.PurchaseDistance) then return true end
    for _, spot in ipairs(d.displays or {}) do
        if IsNear(src, spot, (TD.displayInteractDistance or 3.5) + 4.0) then return true end
    end
    return false
end

local function finishTestDrive(src, forced)
    local td = testDrives[src]
    if not td then return end
    testDrives[src] = nil
    testCooldown[src] = os.time()

    if td.netId then
        local veh = NetworkGetEntityFromNetworkId(td.netId)
        if veh and veh ~= 0 and DoesEntityExist(veh) then DeleteEntity(veh) end
    end
    if td.bucket ~= nil and GetPlayerName(src) then
        SetPlayerRoutingBucket(src, td.bucket)
    end
    if forced and GetPlayerName(src) then
        TriggerClientEvent('gen_dealership:testdriveForceEnd', src, T('testdrive_over'))
    end
end

RegisterCallback('shop:testdrive', function(src, dealershipId, vehicleId)
    if not TD.enabled then return { ok = false, error = T('testdrive_disabled') } end

    local d = ById[tonumber(dealershipId)]
    if not d then return { ok = false, error = T('vehicle_not_found') } end
    if not CanUseDealership(src, d) then return { ok = false, error = T('no_access') } end
    if not nearDealership(src, d) then return { ok = false, error = T('too_far') } end

    local v = resolveShopVehicle(d, vehicleId)
    if not v then return { ok = false, error = T('vehicle_not_found') } end

    local now = os.time()
    if testDrives[src] then return { ok = false, error = T('testdrive_active') } end

    local last = testCooldown[src]
    if last and now - last < TD.cooldown then
        return { ok = false, error = T('testdrive_cooldown', TD.cooldown - (now - last)) }
    end

    local plate = (TD.platePrefix .. tostring(math.random(1000, 9999))):sub(1, 8)
    local td = { expires = now + TD.duration + 30 }
    if TD.privateInstance then
        td.bucket = GetPlayerRoutingBucket(src)
        SetPlayerRoutingBucket(src, TD.bucketBase + src)
    end
    testDrives[src] = td
    issuedPlates[src] = plate

    return {
        ok = true, plate = plate, model = v.model, label = v.label,
        duration = TD.duration, instanced = TD.privateInstance == true,
    }
end)

RegisterNetEvent('gen_dealership:testdriveSpawned', function(netId)
    local td = testDrives[source]
    if td and not td.netId then td.netId = tonumber(netId) end
end)

RegisterNetEvent('gen_dealership:testdriveEnd', function()
    finishTestDrive(source, false)
end)

-- Safety net: end test drives the client never closed (crash, script error, …)
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for src, td in pairs(testDrives) do
            if now > td.expires then finishTestDrive(src, true) end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(testDrives) do finishTestDrive(src, false) end
end)

RegisterNetEvent('gen_dealership:vehicleSpawned', function(netId, plate)
    local src = source
    if type(plate) ~= 'string' or issuedPlates[src] ~= plate then return end
    issuedPlates[src] = nil

    local vehicle, timeout = 0, GetGameTimer() + 3000
    while vehicle == 0 and GetGameTimer() < timeout do
        vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
        if vehicle == 0 then Wait(100) end
    end
    if vehicle ~= 0 then
        Bridge.GiveKeys(src, vehicle, plate)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    finishTestDrive(src, false)
    purchaseLock[src], testCooldown[src], issuedPlates[src] = nil, nil, nil
end)

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

exports('GetDealerships', function() return Dealerships end)
exports('GetDealership', function(name)
    for _, d in ipairs(Dealerships) do
        if d.name == name then return d end
    end
end)
