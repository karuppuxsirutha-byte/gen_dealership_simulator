-- Logistics job: ordered stock waits at a depot as shipments; players drive each
-- vehicle to the dealership's drop-off point and get paid by its condition.
Logistics = {}

local L = Config.Logistics
local T = Utils.T

local Shipments = {}   -- [id] = shipment
local Ready = false

local function now() return os.time() end
local function depotPoint() return L.depot.board end

function Logistics.Enabled() return L.enabled == true end

local function dropPoint(d)
    return d.delivery or d.spawn or d.shop
end

function Logistics.FeeFor(d)
    local from, to = depotPoint(), d.shop
    if not to then return L.baseFee end
    local dist = #(vector3(from.x, from.y, from.z) - vector3(to.x, to.y, to.z))
    return math.floor(L.baseFee + (dist / 1000.0) * L.perKm)
end

local function persist(sh)
    MySQL.update('UPDATE gen_dealership_shipments SET status = ?, driver = ?, payout = ? WHERE id = ?',
        { sh.status, sh.driverIdent or '', sh.payout or 0, sh.id })
end

-- ---------------------------------------------------------------------------
-- Loading & creation
-- ---------------------------------------------------------------------------

function Logistics.Load()
    Shipments = {}
    local rows = MySQL.query.await("SELECT * FROM gen_dealership_shipments WHERE status IN ('waiting', 'transit')") or {}
    local remaining = {}
    for _, r in ipairs(rows) do
        Shipments[r.id] = {
            id = r.id, orderId = r.order_id, dealershipId = r.dealership_id, vehicleId = r.vehicle_id,
            model = r.model, label = r.label, unitCost = r.unit_cost, fee = r.fee,
            status = 'waiting', autoAt = r.auto_at,
        }
        if r.status == 'transit' then -- a haul interrupted by a restart goes back on the board
            MySQL.update("UPDATE gen_dealership_shipments SET status = 'waiting', driver = '' WHERE id = ?", { r.id })
        end
        local key = r.dealership_id .. ':' .. r.order_id
        remaining[key] = { r.dealership_id, r.order_id, (remaining[key] and remaining[key][3] or 0) + 1 }
    end

    -- Keep business order bookkeeping in line with the shipments that are actually left
    for _, d in ipairs(GetAllDealerships()) do
        local s = Biz.Peek(d.id)
        if s then
            for _, o in ipairs(s.orders) do
                if o.arrives == 0 then
                    local left = remaining[d.id .. ':' .. o.id]
                    Biz.SetOrderRemaining(d.id, o.id, left and left[3] or 0)
                end
            end
        end
    end
    Ready = true
end

function Logistics.Forget(dealershipId)
    for id, sh in pairs(Shipments) do
        if sh.dealershipId == dealershipId then
            if sh.status == 'transit' then Logistics.Fail(sh, 'The dealership closed down.') end
            Shipments[id] = nil
        end
    end
end

local function canHaul(src, sh)
    if not L.job or L.job == '' then return true end
    if Bridge.GetJob(src) == L.job then return true end
    if L.staffCanDeliver and sh and Biz.RoleOf(sh.dealershipId, Bridge.GetIdentifier(src)) then return true end
    return false
end

local function isDriver(src)
    return (not L.job or L.job == '') or Bridge.GetJob(src) == L.job
end

local function notifyDrivers(msg)
    for _, p in ipairs(GetPlayers()) do
        local src = tonumber(p)
        if L.job and L.job ~= '' and Bridge.GetJob(src) == L.job then
            Bridge.Notify(src, msg, 'primary')
        end
    end
end

function Logistics.CreateShipments(d, v, orderId, qty, unitCost, fee)
    local autoAt = L.autoDeliverAfter > 0 and (now() + L.autoDeliverAfter) or 0
    for _ = 1, qty do
        local id = MySQL.insert.await(
            'INSERT INTO gen_dealership_shipments (order_id, dealership_id, vehicle_id, model, label, unit_cost, fee, auto_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { orderId, d.id, v.id, v.model, v.label, unitCost, fee, autoAt }
        )
        Shipments[id] = {
            id = id, orderId = orderId, dealershipId = d.id, vehicleId = v.id,
            model = v.model, label = v.label, unitCost = unitCost, fee = fee,
            status = 'waiting', autoAt = autoAt,
        }
    end
    notifyDrivers(('New freight: %dx %s to %s (%s each).'):format(qty, v.label, d.label, Utils.FormatMoney(fee)))
end

function Logistics.OrderSummary(orderId)
    local out = { waiting = 0, transit = 0, drivers = {}, autoIn = nil }
    local t = now()
    for _, sh in pairs(Shipments) do
        if sh.orderId == orderId then
            if sh.status == 'transit' then
                out.transit = out.transit + 1
                out.drivers[#out.drivers + 1] = sh.driverName
            else
                out.waiting = out.waiting + 1
                if sh.autoAt > 0 then
                    local left = math.max(0, sh.autoAt - t)
                    if not out.autoIn or left < out.autoIn then out.autoIn = left end
                end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Arrival (driver or NPC freight)
-- ---------------------------------------------------------------------------

local function arrive(sh, how, actor)
    Shipments[sh.id] = nil
    sh.status = 'delivered'
    persist(sh)

    local ok, d = Biz.AddStock(sh.dealershipId, sh.vehicleId, 1)
    if not ok then
        Biz.AddBalance(sh.dealershipId, sh.unitCost, 'refund', ('Refund: %s (no longer sold)'):format(sh.label), 'System')
    else
        Biz.Log(sh.dealershipId, 'delivery', 0, ('%s delivered %s'):format(how, sh.label), actor or 'System')
        Biz.NotifyManagers(sh.dealershipId, ('%s: %s delivered by %s.'):format(d.label, sh.label, actor or how), 'success')
    end
    Biz.OrderUnitDone(sh.dealershipId, sh.orderId)
    BroadcastDealerships()
end

local function deleteHaulVehicle(sh)
    if not sh.netId then return end
    local ent = NetworkGetEntityFromNetworkId(sh.netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
end

--- Puts a hauled shipment back on the board.
function Logistics.Fail(sh, reason)
    deleteHaulVehicle(sh)
    local driver = sh.driver
    sh.status, sh.driver, sh.driverIdent, sh.driverName, sh.netId, sh.plate, sh.deadline = 'waiting', nil, nil, nil, nil, nil, nil
    persist(sh)
    if driver and GetPlayerName(driver) then
        TriggerClientEvent('gen_dealership:logistics:ended', driver, reason)
        Bridge.Notify(driver, T('haul_failed', reason), 'error')
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks
-- ---------------------------------------------------------------------------

local function activeFor(src)
    for _, sh in pairs(Shipments) do
        if sh.status == 'transit' and sh.driver == src then return sh end
    end
end

local function publicShipment(sh, d)
    local drop = dropPoint(d)
    local from = depotPoint()
    return {
        id = sh.id, label = sh.label, model = sh.model,
        dealership = d.label, payout = sh.fee,
        distance = drop and math.floor(#(vector3(from.x, from.y, from.z) - vector3(drop.x, drop.y, drop.z))) or 0,
    }
end

RegisterCallback('logistics:board', function(src)
    if not Logistics.Enabled() then return { ok = false, error = 'Logistics are disabled.' } end
    if not IsNear(src, depotPoint(), 15.0) then return { ok = false, error = T('too_far') } end

    local driver = isDriver(src)
    local list = {}
    for _, sh in pairs(Shipments) do
        if sh.status == 'waiting' and (driver or canHaul(src, sh)) then
            local d = GetDealershipById(sh.dealershipId)
            if d then list[#list + 1] = publicShipment(sh, d) end
        end
    end
    table.sort(list, function(a, b) return a.payout > b.payout end)

    if not driver and #list == 0 and not activeFor(src) then
        return { ok = false, error = ('Only %s workers can haul freight here.'):format(L.job) }
    end

    local active = activeFor(src)
    local activeView
    if active then
        local d = GetDealershipById(active.dealershipId)
        activeView = { id = active.id, label = active.label, dealership = d and d.label or '?', timeLeft = math.max(0, active.deadline - now()) }
    end
    return { ok = true, depot = L.depot.label, shipments = list, active = activeView }
end)

RegisterCallback('logistics:accept', function(src, id)
    local sh = Shipments[tonumber(id)]
    if not sh or sh.status ~= 'waiting' then return { ok = false, error = 'That shipment was already taken.' } end
    if not canHaul(src, sh) then return { ok = false, error = T('no_permission') } end
    if not IsNear(src, depotPoint(), 15.0) then return { ok = false, error = T('too_far') } end
    if activeFor(src) then return { ok = false, error = 'Finish your current delivery first.' } end

    local d = GetDealershipById(sh.dealershipId)
    if not d then return { ok = false, error = T('vehicle_not_found') } end

    sh.status = 'transit'
    sh.driver = src
    sh.driverIdent = Bridge.GetIdentifier(src) or ''
    sh.driverName = Bridge.GetName(src)
    sh.plate = (L.platePrefix .. tostring(math.random(100, 999))):sub(1, 8)
    sh.deadline = now() + L.timeLimit
    sh.netId = nil
    persist(sh)
    IssuePlate(src, sh.plate)

    return {
        ok = true, id = sh.id, model = sh.model, label = sh.label, plate = sh.plate,
        dealership = d.label, drop = dropPoint(d), timeLimit = L.timeLimit, payout = sh.fee,
    }
end)

RegisterNetEvent('gen_dealership:logistics:spawned', function(id, netId)
    local src = source
    local sh = Shipments[tonumber(id)]
    if sh and sh.status == 'transit' and sh.driver == src and not sh.netId then
        sh.netId = tonumber(netId)
    end
end)

RegisterCallback('logistics:deliver', function(src, id)
    local sh = Shipments[tonumber(id)]
    if not sh or sh.status ~= 'transit' or sh.driver ~= src then return { ok = false, error = 'You are not hauling that shipment.' } end
    local d = GetDealershipById(sh.dealershipId)
    if not d then return { ok = false, error = T('vehicle_not_found') } end
    local drop = dropPoint(d)

    local veh = sh.netId and NetworkGetEntityFromNetworkId(sh.netId) or 0
    if not veh or veh == 0 or not DoesEntityExist(veh) then return { ok = false, error = 'The shipment vehicle is missing.' } end

    local dropVec = vector3(drop.x, drop.y, drop.z)
    if #(GetEntityCoords(veh) - dropVec) > L.dropRadius + 2.0 then return { ok = false, error = 'Park the vehicle on the drop-off marker.' } end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= veh then return { ok = false, error = 'You must be driving the shipment vehicle.' } end
    local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if plate ~= sh.plate then return { ok = false, error = 'That is not the shipment vehicle.' } end

    -- Condition: worst of body / engine health (both 0-1000)
    local body = GetVehicleBodyHealth(veh) or 1000.0
    local engine = GetVehicleEngineHealth(veh) or 1000.0
    local condition = math.max(0.0, math.min(1.0, math.min(body, engine) / 1000.0))
    local ratio = math.max(L.minPayoutRatio, condition)
    local payout = math.floor(sh.fee * ratio)
    local refund = sh.fee - payout

    DeleteEntity(veh)
    sh.payout = payout
    Bridge.AddMoney(src, 'bank', payout, 'logistics-delivery')
    if refund > 0 then
        Biz.AddBalance(sh.dealershipId, refund, 'refund', ('Freight damage refund: %s (%d%% condition)'):format(sh.label, math.floor(condition * 100)), 'System')
    end
    arrive(sh, 'Driver', sh.driverName)

    return { ok = true, payout = payout, condition = math.floor(condition * 100), label = sh.label, payoutText = Utils.FormatMoney(payout) }
end)

RegisterCallback('logistics:cancel', function(src)
    local sh = activeFor(src)
    if not sh then return { ok = false, error = 'You have no active delivery.' } end
    Logistics.Fail(sh, 'Delivery cancelled.')
    return { ok = true }
end)

-- ---------------------------------------------------------------------------
-- Background: deadlines, wrecks, NPC freight
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(10000)
        if Ready then
            local t = now()
            for _, sh in pairs(Shipments) do
                if sh.status == 'transit' then
                    if not GetPlayerName(sh.driver) then
                        Logistics.Fail(sh, 'Driver disconnected.')
                    elseif t > sh.deadline then
                        Logistics.Fail(sh, "Time's up.")
                    elseif sh.netId then
                        local veh = NetworkGetEntityFromNetworkId(sh.netId)
                        if not veh or veh == 0 or not DoesEntityExist(veh) or GetVehicleEngineHealth(veh) <= -3900.0 then
                            Logistics.Fail(sh, 'The vehicle was destroyed.')
                        end
                    end
                elseif not Logistics.Enabled() or (sh.autoAt > 0 and t >= sh.autoAt) then
                    arrive(sh, 'NPC freight', 'NPC freight')
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local sh = activeFor(source)
    if sh then Logistics.Fail(sh, 'Driver disconnected.') end
end)
