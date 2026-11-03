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
end

local function broadcast(target)
    TriggerClientEvent('gen_dealership:sync', target or -1, Dealerships)
end

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

local function isNear(src, point, maxDist)
    if not point then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end -- OneSync off: cannot verify
    local c = GetEntityCoords(ped)
    return #(c - vector3(point.x, point.y, point.z)) <= maxDist
end

local function canUse(src, d)
    if not d.job then return true end
    return Bridge.GetJob(src) == d.job
end

local function findVehicle(d, vehicleId)
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
            vehicles[#vehicles + 1] = {
                model = model,
                label = cleanText(v.label, 100) ~= '' and cleanText(v.label, 100) or model,
                category = category,
                price = clampInt(v.price, 0, 1000000000, 0),
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

    return {
        id = id,
        name = name,
        label = label,
        job = job ~= '' and job or nil,
        blip = blip,
        shop = shop,
        spawn = spawn,
        testdrive = sanitizeVec4(data.testdrive),
        displays = displays,
        vehicles = vehicles,
    }
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

MySQL.ready(function()
    DB.Init()
    reload()
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

    local ok, idOrErr = pcall(DB.Save, d)
    if not ok then
        print(('^1[gen_dealership] save failed: %s^0'):format(idOrErr))
        return { ok = false, error = 'Database error while saving.' }
    end

    reload()
    broadcast()
    print(('[gen_dealership] %s saved dealership "%s" (#%s)'):format(GetPlayerName(src), d.name, idOrErr))
    return { ok = true, id = idOrErr, dealerships = Dealerships }
end)

RegisterCallback('creator:delete', function(src, id)
    if not Bridge.IsAdmin(src) then return { ok = false, error = T('no_permission') } end
    id = tonumber(id)
    if not id or not ById[id] then return { ok = false, error = 'Unknown dealership.' } end

    DB.Delete(id)
    reload()
    broadcast()
    print(('[gen_dealership] %s deleted dealership #%s'):format(GetPlayerName(src), id))
    return { ok = true, dealerships = Dealerships }
end)

-- ---------------------------------------------------------------------------
-- Shop
-- ---------------------------------------------------------------------------

RegisterCallback('shop:buy', function(src, dealershipId, vehicleId, method)
    local d = ById[tonumber(dealershipId)]
    if not d then return { ok = false, error = T('vehicle_not_found') } end
    if not canUse(src, d) then return { ok = false, error = T('no_access') } end
    if not isNear(src, d.shop, Config.PurchaseDistance) then return { ok = false, error = T('too_far') } end

    local v = findVehicle(d, vehicleId)
    if not v then return { ok = false, error = T('vehicle_not_found') } end
    if v.stock == 0 then return { ok = false, error = T('out_of_stock') } end

    local allowed = false
    for _, m in ipairs(Config.PaymentMethods) do
        if m == method then allowed = true break end
    end
    if not allowed then method = Config.PaymentMethods[1] end

    if purchaseLock[src] then return { ok = false, error = T('busy') } end
    purchaseLock[src] = true

    local plate = generatePlate()
    if not plate then
        purchaseLock[src] = nil
        return { ok = false, error = T('purchase_failed') }
    end

    if not Bridge.RemoveMoney(src, method, v.price, ('vehicle-purchase:%s'):format(v.model)) then
        purchaseLock[src] = nil
        return { ok = false, error = T('not_enough_money') }
    end

    local ok, given = pcall(Bridge.GiveVehicle, src, v.model, plate, d.name)
    if not ok or not given then
        if not ok then print(('^1[gen_dealership] GiveVehicle failed: %s^0'):format(given)) end
        Bridge.AddMoney(src, method, v.price, 'vehicle-purchase-refund')
        purchaseLock[src] = nil
        return { ok = false, error = T('purchase_failed') }
    end

    if v.stock > 0 then
        v.stock = v.stock - 1
        DB.SetStock(v.id, v.stock)
        broadcast()
    end

    DB.LogSale(d.name, Bridge.GetIdentifier(src), v.model, plate, v.price, method)
    issuedPlates[src] = plate
    purchaseLock[src] = nil

    return {
        ok = true,
        plate = plate,
        model = v.model,
        label = v.label,
        priceText = Utils.FormatMoney(v.price),
    }
end)

RegisterCallback('shop:testdrive', function(src, dealershipId, vehicleId)
    if not Config.TestDrive.enabled then return { ok = false, error = T('testdrive_disabled') } end

    local d = ById[tonumber(dealershipId)]
    if not d then return { ok = false, error = T('vehicle_not_found') } end
    if not canUse(src, d) then return { ok = false, error = T('no_access') } end
    if not isNear(src, d.shop, Config.PurchaseDistance) then return { ok = false, error = T('too_far') } end

    local v = findVehicle(d, vehicleId)
    if not v then return { ok = false, error = T('vehicle_not_found') } end

    local now = os.time()
    local active = testDrives[src]
    if active and active.expires > now then return { ok = false, error = T('testdrive_active') } end

    local last = testCooldown[src]
    if last and now - last < Config.TestDrive.cooldown then
        return { ok = false, error = T('testdrive_cooldown', Config.TestDrive.cooldown - (now - last)) }
    end

    local plate = (Config.TestDrive.platePrefix .. tostring(math.random(1000, 9999))):sub(1, 8)
    testDrives[src] = { expires = now + Config.TestDrive.duration + 30 }
    issuedPlates[src] = plate

    return { ok = true, plate = plate, model = v.model, duration = Config.TestDrive.duration }
end)

RegisterNetEvent('gen_dealership:testdriveEnd', function()
    local src = source
    if testDrives[src] then
        testDrives[src] = nil
        testCooldown[src] = os.time()
    end
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
    purchaseLock[src], testDrives[src], testCooldown[src], issuedPlates[src] = nil, nil, nil, nil
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
