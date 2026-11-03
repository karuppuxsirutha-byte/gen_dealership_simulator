-- Logistics job: ordered stock waits at a depot as shipments. Players haul one car
-- (single job) or several on a truck + trailer (carrier job) to the dealership's
-- drop-off point and are paid by condition. Cargo can be insured; hijackers may strike.
Logistics = {}

local L = Config.Logistics
local T = Utils.T

local Shipments = {}   -- [id] = shipment
local Hauls = {}       -- [id] = active haul
local nextHaulId = 0
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

local function isHighValue(sh) return L.highValue ~= nil and (sh.unitCost or 0) >= L.highValue.threshold end
local function shipmentPay(sh) return math.floor(sh.fee * (isHighValue(sh) and (1 + L.highValue.bonus) or 1)) end

local function persist(sh)
    MySQL.update('UPDATE gen_dealership_shipments SET status = ?, driver = ?, payout = ? WHERE id = ?',
        { sh.status, sh.driverIdent or '', sh.payout or 0, sh.id })
end

local function distanceTo(d)
    local drop, from = dropPoint(d), depotPoint()
    return drop and math.floor(#(vector3(from.x, from.y, from.z) - vector3(drop.x, drop.y, drop.z))) or 0
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
        remaining[key] = (remaining[key] or 0) + 1
    end

    -- Keep business order bookkeeping in line with the shipments that are actually left
    for _, d in ipairs(GetAllDealerships()) do
        local s = Biz.Peek(d.id)
        if s then
            for _, o in ipairs(s.orders) do
                if o.arrives == 0 then
                    Biz.SetOrderRemaining(d.id, o.id, remaining[d.id .. ':' .. o.id] or 0)
                end
            end
        end
    end
    Ready = true
end

local function memberOfCompany(src)
    return Company and Company.IsMember(Bridge.GetIdentifier(src))
end

local function isDriver(src)
    return (not L.job or L.job == '') or Bridge.GetJob(src) == L.job or memberOfCompany(src)
end

local function canHaul(src, sh)
    if isDriver(src) then return true end
    return L.staffCanDeliver and sh ~= nil and Biz.RoleOf(sh.dealershipId, Bridge.GetIdentifier(src)) ~= nil
end

local function notifyDrivers(msg)
    for _, p in ipairs(GetPlayers()) do
        local src = tonumber(p)
        if L.job and L.job ~= '' and (Bridge.GetJob(src) == L.job or memberOfCompany(src)) then
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
                local h = sh.haulId and Hauls[sh.haulId]
                if h then out.drivers[#out.drivers + 1] = h.driverName end
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

--- Admin dashboard figures
function Logistics.Totals()
    local waiting, transit = 0, 0
    for _, sh in pairs(Shipments) do
        if sh.status == 'transit' then transit = transit + 1 else waiting = waiting + 1 end
    end
    local hauls = 0
    for _ in pairs(Hauls) do hauls = hauls + 1 end
    return { waiting = waiting, transit = transit, hauls = hauls }
end

-- ---------------------------------------------------------------------------
-- Arrival & failure
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

local function entityOf(netId)
    if not netId then return nil end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
end

local function haulOf(src)
    for _, h in pairs(Hauls) do
        if h.driver == src then return h end
    end
end

--- Ends a haul without delivery. Shipments go back on the board.
--- @param lost boolean cargo destroyed (insurance pays out / penalty applies)
function Logistics.Fail(h, reason, lost)
    if not Hauls[h.id] then return end
    Hauls[h.id] = nil
    for _, net in ipairs({ h.vehicleNet, h.trailerNet }) do
        local ent = entityOf(net)
        if ent then DeleteEntity(ent) end
    end
    for _, sh in ipairs(h.shipments) do
        if Shipments[sh.id] then
            sh.status, sh.haulId, sh.driverIdent = 'waiting', nil, nil
            persist(sh)
        end
    end

    local driver = h.driver
    if driver and GetPlayerName(driver) then
        if lost then
            if h.insured then
                local comp = math.floor(h.payout * L.insurance.payout)
                Bridge.AddMoney(driver, 'bank', comp, 'logistics-insurance')
                Bridge.Notify(driver, T('haul_insured', Utils.FormatMoney(comp)), 'primary')
            else
                local penalty = math.floor(h.payout * L.insurance.uninsuredPenalty)
                if penalty > 0 then
                    Bridge.RemoveMoney(driver, 'bank', penalty, 'logistics-penalty')
                    Bridge.Notify(driver, T('haul_penalty', Utils.FormatMoney(penalty)), 'error')
                end
            end
        end
        TriggerClientEvent('gen_dealership:logistics:ended', driver, reason)
        Bridge.Notify(driver, T('haul_failed', reason), 'error')
    end
    if lost then
        Webhooks.Send('logistics', 'Freight lost', reason, {
            Webhooks.Field('Driver', h.driverName),
            Webhooks.Field('Cargo', ('%d vehicle(s)'):format(#h.shipments)),
            Webhooks.Field('Insured', h.insured and 'yes' or 'no'),
        }, 'bad')
    end
end

function Logistics.Forget(dealershipId)
    for _, h in pairs(Hauls) do
        if h.dealershipId == dealershipId then Logistics.Fail(h, 'The dealership closed down.', false) end
    end
    for id, sh in pairs(Shipments) do
        if sh.dealershipId == dealershipId then Shipments[id] = nil end
    end
end

-- ---------------------------------------------------------------------------
-- Board
-- ---------------------------------------------------------------------------

function Logistics.Board(src)
    if not Logistics.Enabled() then return { ok = false, error = 'Logistics are disabled.' } end
    if not IsNear(src, depotPoint(), 15.0) then return { ok = false, error = T('too_far') } end

    local driver = isDriver(src)
    local singles, groups = {}, {}
    for _, sh in pairs(Shipments) do
        if sh.status == 'waiting' and (driver or canHaul(src, sh)) then
            local d = GetDealershipById(sh.dealershipId)
            if d then
                singles[#singles + 1] = {
                    id = sh.id, label = sh.label, model = sh.model, dealership = d.label,
                    payout = shipmentPay(sh), distance = distanceTo(d), highValue = isHighValue(sh),
                }
                groups[d.id] = groups[d.id] or {}
                table.insert(groups[d.id], sh)
            end
        end
    end
    table.sort(singles, function(a, b) return a.payout > b.payout end)

    local carriers = {}
    if L.carrier.enabled then
        for dId, list in pairs(groups) do
            if #list >= L.carrier.minLoad then
                table.sort(list, function(a, b) return a.id < b.id end)
                local pay, labels, hv = 0, {}, false
                for i = 1, math.min(#list, L.carrier.capacity) do
                    pay = pay + shipmentPay(list[i])
                    labels[#labels + 1] = list[i].label
                    hv = hv or isHighValue(list[i])
                end
                local d = GetDealershipById(dId)
                carriers[#carriers + 1] = {
                    dealershipId = dId, dealership = d.label, count = #labels, waiting = #list,
                    labels = labels, payout = math.floor(pay * L.carrier.bonus), distance = distanceTo(d), highValue = hv,
                }
            end
        end
        table.sort(carriers, function(a, b) return a.payout > b.payout end)
    end

    local h = haulOf(src)
    local active
    if h then
        local d = GetDealershipById(h.dealershipId)
        active = {
            kind = h.kind, label = h.kind == 'carrier' and ('%d vehicles'):format(#h.shipments) or h.shipments[1].label,
            dealership = d and d.label or '?', timeLeft = math.max(0, h.deadline - now()), insured = h.insured, payout = h.payout,
        }
    end

    return {
        ok = true, depot = L.depot.label, canTake = driver or #singles > 0,
        job = L.job, shipments = singles, carriers = carriers, active = active,
        insurance = L.insurance, company = Company.Public(src),
    }
end

RegisterCallback('logistics:board', function(src) return Logistics.Board(src) end)

-- ---------------------------------------------------------------------------
-- Taking, delivering & cancelling hauls
-- ---------------------------------------------------------------------------

RegisterCallback('logistics:accept', function(src, req)
    req = type(req) == 'table' and req or {}
    if not Logistics.Enabled() then return { ok = false, error = 'Logistics are disabled.' } end
    if not IsNear(src, depotPoint(), 15.0) then return { ok = false, error = T('too_far') } end
    if haulOf(src) then return { ok = false, error = 'Finish your current delivery first.' } end

    local kind = req.kind == 'carrier' and 'carrier' or 'single'
    local cargo = {}
    if kind == 'carrier' then
        if not L.carrier.enabled then return { ok = false, error = 'Carrier jobs are disabled.' } end
        local dId = tonumber(req.dealershipId)
        for _, sh in pairs(Shipments) do
            if sh.status == 'waiting' and sh.dealershipId == dId and canHaul(src, sh) then cargo[#cargo + 1] = sh end
        end
        table.sort(cargo, function(a, b) return a.id < b.id end)
        while #cargo > L.carrier.capacity do table.remove(cargo) end
        if #cargo < L.carrier.minLoad then return { ok = false, error = 'Not enough cargo left for a carrier job.' } end
    else
        local sh = Shipments[tonumber(req.id)]
        if not sh or sh.status ~= 'waiting' then return { ok = false, error = 'That shipment was already taken.' } end
        if not canHaul(src, sh) then return { ok = false, error = T('no_permission') } end
        cargo = { sh }
    end

    local d = GetDealershipById(cargo[1].dealershipId)
    if not d then return { ok = false, error = T('vehicle_not_found') } end

    local payout, highValue = 0, false
    for _, sh in ipairs(cargo) do
        payout = payout + shipmentPay(sh)
        highValue = highValue or isHighValue(sh)
    end
    if kind == 'carrier' then payout = math.floor(payout * L.carrier.bonus) end

    local hz = L.hijack
    local chance = hz.chance
    if highValue then chance = math.max(chance, hz.highValueChance) end
    if kind == 'carrier' then chance = math.max(chance, hz.carrierChance) end

    nextHaulId = nextHaulId + 1
    local h = {
        id = nextHaulId, kind = kind, driver = src,
        driverIdent = Bridge.GetIdentifier(src) or '', driverName = Bridge.GetName(src),
        shipments = cargo, dealershipId = d.id,
        plate = (L.platePrefix .. tostring(math.random(100, 999))):sub(1, 8),
        deadline = now() + math.floor(L.timeLimit * (kind == 'carrier' and L.carrier.timeMultiplier or 1)),
        insured = req.insured == true, payout = payout,
        hijack = hz.enabled and math.random() < chance,
    }
    for _, sh in ipairs(cargo) do
        sh.status, sh.haulId, sh.driverIdent = 'transit', h.id, h.driverIdent
        persist(sh)
    end
    Hauls[h.id] = h
    IssuePlate(src, h.plate)

    return {
        ok = true, id = h.id, kind = kind,
        model = kind == 'carrier' and L.carrier.truck or cargo[1].model,
        trailer = kind == 'carrier' and L.carrier.trailer or nil,
        label = kind == 'carrier' and ('%d vehicles'):format(#cargo) or cargo[1].label,
        plate = h.plate, dealership = d.label, drop = dropPoint(d),
        timeLimit = h.deadline - now(), payout = payout, insured = h.insured,
        dropRadius = kind == 'carrier' and L.carrier.dropRadius or L.dropRadius,
        hijack = h.hijack and {
            delay = math.random(hz.delay[1], hz.delay[2]), vehicle = hz.vehicle, peds = hz.peds, weapon = hz.weapon,
        } or nil,
    }
end)

RegisterNetEvent('gen_dealership:logistics:spawned', function(haulId, vehicleNet, trailerNet)
    local h = Hauls[tonumber(haulId)]
    if h and h.driver == source and not h.vehicleNet then
        h.vehicleNet = tonumber(vehicleNet)
        h.trailerNet = tonumber(trailerNet)
    end
end)

local function conditionOf(veh)
    local body = GetVehicleBodyHealth(veh) or 1000.0
    local engine = GetVehicleEngineHealth(veh) or 1000.0
    return math.max(0.0, math.min(1.0, math.min(body, engine) / 1000.0))
end

RegisterCallback('logistics:deliver', function(src)
    local h = haulOf(src)
    if not h then return { ok = false, error = 'You have no active delivery.' } end
    local d = GetDealershipById(h.dealershipId)
    if not d then return { ok = false, error = T('vehicle_not_found') } end
    local drop = dropPoint(d)
    local radius = h.kind == 'carrier' and L.carrier.dropRadius or L.dropRadius

    local veh = entityOf(h.vehicleNet)
    if not veh then return { ok = false, error = 'The shipment vehicle is missing.' } end
    if #(GetEntityCoords(veh) - vector3(drop.x, drop.y, drop.z)) > radius + 2.0 then return { ok = false, error = 'Park on the drop-off marker.' } end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= veh then return { ok = false, error = 'You must be driving the shipment vehicle.' } end
    local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if plate ~= h.plate then return { ok = false, error = 'That is not the shipment vehicle.' } end

    local condition = conditionOf(veh)
    local trailer
    if h.kind == 'carrier' then
        trailer = entityOf(h.trailerNet)
        if not trailer or #(GetEntityCoords(trailer) - GetEntityCoords(veh)) > 25.0 then
            return { ok = false, error = 'Bring the trailer with you.' }
        end
        condition = math.min(condition, conditionOf(trailer))
    end

    local ratio = math.max(L.minPayoutRatio, condition)
    local gross = math.floor(h.payout * ratio)
    if h.hijack then gross = math.floor(gross * (1 + L.hijack.hazardBonus)) end
    local premium = h.insured and math.floor(gross * L.insurance.premium) or 0
    local driverPay, companyCut = Company.Split(gross - premium)

    Hauls[h.id] = nil
    DeleteEntity(veh)
    if trailer then DeleteEntity(trailer) end

    Bridge.AddMoney(src, 'bank', driverPay, 'logistics-delivery')
    Company.Credit(companyCut, ('%s → %s'):format(h.driverName, d.label))

    -- The dealership paid the freight fee up front: refund the damage deduction
    local refund = 0
    for _, sh in ipairs(h.shipments) do refund = refund + (sh.fee - math.floor(sh.fee * ratio)) end
    if refund > 0 then
        Biz.AddBalance(d.id, refund, 'refund', ('Freight damage refund (%d%% condition)'):format(math.floor(condition * 100)), 'System')
    end
    for _, sh in ipairs(h.shipments) do
        sh.payout = math.floor(driverPay / #h.shipments)
        arrive(sh, 'Driver', h.driverName)
    end

    Webhooks.Send('logistics', ('Freight delivered · %s'):format(d.label), nil, {
        Webhooks.Field('Cargo', h.kind == 'carrier' and ('%d vehicles (carrier)'):format(#h.shipments) or h.shipments[1].label),
        Webhooks.Field('Driver', Webhooks.Who(src)),
        Webhooks.Field('Condition', ('%d%%'):format(math.floor(condition * 100))),
        Webhooks.Field('Paid', Utils.FormatMoney(driverPay)),
        Webhooks.Field('Company cut', Utils.FormatMoney(companyCut)),
        Webhooks.Field('Ambushed', h.hijack and 'yes' or 'no'),
    })

    return {
        ok = true, payout = driverPay, payoutText = Utils.FormatMoney(driverPay), condition = math.floor(condition * 100),
        label = h.kind == 'carrier' and ('%d vehicles'):format(#h.shipments) or h.shipments[1].label,
        premium = premium, companyCut = companyCut, hazard = h.hijack,
    }
end)

RegisterCallback('logistics:cancel', function(src)
    local h = haulOf(src)
    if not h then return { ok = false, error = 'You have no active delivery.' } end
    Logistics.Fail(h, 'Delivery cancelled.', false)
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
            local list = {}
            for _, h in pairs(Hauls) do list[#list + 1] = h end
            for _, h in ipairs(list) do
                local ped = GetPlayerName(h.driver) and GetPlayerPed(h.driver)
                if not ped or ped == 0 then
                    Logistics.Fail(h, 'Driver disconnected.', false)
                elseif t > h.deadline then
                    Logistics.Fail(h, "Time's up.", false)
                elseif GetEntityHealth(ped) <= 0 then
                    Logistics.Fail(h, 'You were taken out and the cargo was lost.', true)
                elseif h.vehicleNet then
                    local veh = entityOf(h.vehicleNet)
                    local trailer = h.kind == 'carrier' and entityOf(h.trailerNet) or true
                    if not veh or GetVehicleEngineHealth(veh) <= -3900.0 or not trailer then
                        Logistics.Fail(h, 'The cargo was destroyed.', true)
                    end
                end
            end

            local ids = {}
            for id, sh in pairs(Shipments) do
                if sh.status == 'waiting' and (not Logistics.Enabled() or (sh.autoAt > 0 and t >= sh.autoAt)) then ids[#ids + 1] = id end
            end
            for _, id in ipairs(ids) do
                local sh = Shipments[id]
                if sh and sh.status == 'waiting' then arrive(sh, 'NPC freight', 'NPC freight') end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local h = haulOf(source)
    if h then Logistics.Fail(h, 'Driver disconnected.', false) end
end)
