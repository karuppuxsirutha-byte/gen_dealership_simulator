-- Pre-owned lot (trade-ins & repossessions) and trade-in quotes.
UsedLot = {}

local T = Utils.T
local Lots = {}        -- [dealershipId] = { [id] = entry }
local Quotes = {}      -- [src] = pending trade-in quote

local function round100(n) return math.floor(n / 100 + 0.5) * 100 end

local function publicEntry(e)
    return { id = e.id, model = e.model, label = e.label, category = e.category, price = e.price, condition = e.condition, source = e.source }
end

function UsedLot.Load()
    Lots = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM gen_dealership_used ORDER BY id') or {}) do
        Lots[r.dealership_id] = Lots[r.dealership_id] or {}
        Lots[r.dealership_id][r.id] = {
            id = r.id, dealershipId = r.dealership_id, model = r.model, label = r.label, category = r.category,
            price = r.price, value = r.value, condition = r['condition'], source = r.source,
        }
    end
end

--- Attaches the public used list to a dealership object (called on every reload).
function UsedLot.Attach(d)
    local list = {}
    for _, e in pairs(Lots[d.id] or {}) do
        if not e.taken then list[#list + 1] = publicEntry(e) end
    end
    table.sort(list, function(a, b) return a.id > b.id end)
    d.used = list
end

local function refresh(dealershipId)
    local d = GetDealershipById(dealershipId)
    if d then UsedLot.Attach(d) end
    BroadcastDealerships()
end

--- Full entries (incl. trade-in value) for the management panel
function UsedLot.ListFull(dealershipId)
    local list = {}
    for _, e in pairs(Lots[dealershipId] or {}) do
        if not e.taken then
            list[#list + 1] = { id = e.id, model = e.model, label = e.label, price = e.price, value = e.value, condition = e.condition, source = e.source }
        end
    end
    table.sort(list, function(a, b) return a.id > b.id end)
    return list
end

function UsedLot.Find(dealershipId, id)
    local e = (Lots[dealershipId] or {})[tonumber(id)]
    if e and not e.taken then return e end
end

function UsedLot.Forget(dealershipId) Lots[dealershipId] = nil end

--- Adds a vehicle to a dealership's pre-owned lot.
function UsedLot.Add(dealershipId, model, label, category, value, condition, source)
    if not Config.UsedLot.enabled then return end
    local lot = Lots[dealershipId] or {}
    Lots[dealershipId] = lot

    -- make room: drop the oldest listing
    local count, oldest = 0, nil
    for id in pairs(lot) do
        count = count + 1
        if not oldest or id < oldest then oldest = id end
    end
    if count >= Config.UsedLot.maxPerDealership and oldest then
        lot[oldest] = nil
        MySQL.query('DELETE FROM gen_dealership_used WHERE id = ?', { oldest })
    end

    local price = math.max(100, round100(value * Config.UsedLot.markup))
    local id = MySQL.insert.await(
        'INSERT INTO gen_dealership_used (dealership_id, model, label, category, price, value, `condition`, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { dealershipId, model, label, category or 'other', price, value, condition, source }
    )
    if not id then return end
    lot[id] = { id = id, dealershipId = dealershipId, model = model, label = label, category = category or 'other', price = price, value = value, condition = condition, source = source }
    refresh(dealershipId)
end

--- Reserve a listing while a purchase is processed (no yield). Restore() undoes it.
function UsedLot.Take(e) e.taken = true end
function UsedLot.Restore(e) e.taken = nil end

function UsedLot.Finalize(e)
    local lot = Lots[e.dealershipId]
    if lot then lot[e.id] = nil end
    MySQL.query('DELETE FROM gen_dealership_used WHERE id = ?', { e.id })
    refresh(e.dealershipId)
end

function UsedLot.SetPrice(dealershipId, id, price)
    local e = UsedLot.Find(dealershipId, id)
    if not e then return false end
    e.price = price
    MySQL.update('UPDATE gen_dealership_used SET price = ? WHERE id = ?', { price, e.id })
    refresh(dealershipId)
    return true
end

--- Catalogue entry for a model hash: this dealership first, then any dealership.
function FindCatalogueByHash(hash, preferred)
    local function search(d)
        for _, v in ipairs(d.vehicles) do
            if joaat(v.model) == hash then return v end
        end
    end
    if preferred then
        local v = search(preferred)
        if v then return v end
    end
    for _, d in ipairs(GetAllDealerships()) do
        local v = search(d)
        if v then return v end
    end
end

-- ---------------------------------------------------------------------------
-- Trade-ins
-- ---------------------------------------------------------------------------

local function trimPlate(p) return ((p or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

local function evaluate(src, d, netId)
    if not Config.TradeIn.enabled then return nil, T('tradein_disabled') end
    if not CanUseDealership(src, d) then return nil, T('no_access') end
    if not IsNear(src, d.shop, Config.TradeIn.radius) then return nil, T('too_far') end

    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil, T('tradein_no_vehicle') end
    local shopVec = vector3(d.shop.x, d.shop.y, d.shop.z)
    if #(GetEntityCoords(veh) - shopVec) > Config.TradeIn.radius then return nil, T('tradein_no_vehicle') end
    local driver = GetPedInVehicleSeat(veh, -1)
    if driver and driver ~= 0 and driver ~= GetPlayerPed(src) then return nil, T('tradein_occupied') end

    local plate = trimPlate(GetVehicleNumberPlateText(veh))
    local owned = Bridge.GetOwnedVehicle(src, plate)
    if not owned then return nil, T('tradein_not_owner') end
    if Finance.HasActive(plate) then return nil, T('tradein_financed') end

    local cat = FindCatalogueByHash(owned.hash, d)
    if not cat then return nil, T('tradein_unknown_model') end

    local body = GetVehicleBodyHealth(veh) or 1000.0
    local engine = GetVehicleEngineHealth(veh) or 1000.0
    local condition = math.max(0.0, math.min(1.0, math.min(body, engine) / 1000.0))
    local value = round100(cat.price * Config.TradeIn.ratio * (0.4 + 0.6 * condition))

    if Biz.IsOwned(d.id) and Biz.Peek(d.id).balance < value then return nil, T('tradein_dealer_broke') end

    return { veh = veh, plate = plate, model = cat.model, label = cat.label, category = cat.category, value = value, condition = math.floor(condition * 100) }
end

RegisterCallback('tradein:quote', function(src, dealershipId, netId)
    local d = GetDealershipById(dealershipId)
    if not d then return { ok = false, error = T('vehicle_not_found') } end
    local q, err = evaluate(src, d, netId)
    if not q then return { ok = false, error = err } end
    Quotes[src] = { dealershipId = d.id, netId = netId, plate = q.plate, value = q.value, expires = os.time() + 60 }
    return { ok = true, label = q.label, model = q.model, plate = q.plate, value = q.value, condition = q.condition }
end)

RegisterCallback('tradein:accept', function(src)
    local quote = Quotes[src]
    Quotes[src] = nil
    if not quote or os.time() > quote.expires then return { ok = false, error = T('tradein_expired') } end
    local d = GetDealershipById(quote.dealershipId)
    if not d then return { ok = false, error = T('vehicle_not_found') } end

    -- Re-evaluate: the car could have been damaged or swapped since the quote
    local q, err = evaluate(src, d, quote.netId)
    if not q then return { ok = false, error = err } end
    if q.plate ~= quote.plate then return { ok = false, error = T('tradein_expired') } end
    local value = math.min(q.value, quote.value)

    if Biz.IsOwned(d.id) then
        if Biz.Peek(d.id).balance < value then return { ok = false, error = T('tradein_dealer_broke') } end
        Biz.AddBalance(d.id, -value, 'tradein', ('Trade-in: %s (%d%%) from %s'):format(q.label, q.condition, Bridge.GetName(src)), Bridge.GetName(src))
    end
    Bridge.RemoveVehicle(q.plate)
    Bridge.AddMoney(src, 'bank', value, 'vehicle-trade-in')
    UsedLot.Add(d.id, q.model, q.label, q.category, value, q.condition, 'tradein')

    Webhooks.Send('sales', ('Trade-in · %s'):format(d.label), nil, {
        Webhooks.Field('Vehicle', ('%s · %s'):format(q.label, q.plate)),
        Webhooks.Field('Paid', Utils.FormatMoney(value)),
        Webhooks.Field('Condition', ('%d%%'):format(q.condition)),
        Webhooks.Field('Seller', Webhooks.Who(src)),
    })

    return {
        ok = true,
        message = T('tradein_done', q.label, Utils.FormatMoney(value)),
        balance = { cash = Bridge.GetMoney(src, 'cash'), bank = Bridge.GetMoney(src, 'bank') },
    }
end)

AddEventHandler('playerDropped', function() Quotes[source] = nil end)
