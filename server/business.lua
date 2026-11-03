-- Player-owned dealership businesses: ownership, funds, staff, stock orders.
-- In-memory state is authoritative; it is flushed to the database every few seconds
-- (one sequential writer, so writes can never land out of order).
Biz = {}

local Sim = Config.Simulation
local T = Utils.T

local State = {}   -- [dealershipId] = { price, owner, ownerName, ownerSince, balance, reputation, employees = { [identifier] = e }, orders = { o } }
local Dirty = {}
local Ready = false

local RANK = { sales = 1, manager = 2, owner = 3 }
local ROLE_LABEL = { owner = 'Owner', manager = 'Manager', sales = 'Salesperson' }
Biz.RANK = RANK

local function now() return os.time() end

local function clampInt(v, min, max)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    v = math.floor(v)
    if v < min or v > max then return nil end
    return v
end

-- ---------------------------------------------------------------------------
-- State & persistence
-- ---------------------------------------------------------------------------

local function blank()
    return {
        price = 0, owner = nil, ownerName = '', ownerSince = 0, balance = 0, reputation = Sim.startReputation,
        targetCount = 0, targetBonus = 0, adLabel = '', adBoost = 0, adUntil = 0,
        employees = {}, orders = {},
    }
end

function Biz.Load()
    State = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM gen_dealership_business') or {}) do
        State[r.dealership_id] = {
            price = r.price,
            owner = r.owner ~= '' and r.owner or nil,
            ownerName = r.owner_name or '',
            ownerSince = r.owner_since or 0,
            balance = tonumber(r.balance) or 0,
            reputation = r.reputation,
            targetCount = r.target_count or 0,
            targetBonus = r.target_bonus or 0,
            adLabel = r.ad_label or '',
            adBoost = r.ad_boost or 0,
            adUntil = r.ad_until or 0,
            employees = {},
            orders = {},
        }
    end
    for _, e in ipairs(MySQL.query.await('SELECT * FROM gen_dealership_employees') or {}) do
        local s = State[e.dealership_id]
        if s then
            local wage = (e.wage and e.wage >= 0) and e.wage or (Sim.wages[e.role] or 0)
            s.employees[e.identifier] = { identifier = e.identifier, name = e.name, role = e.role, commission = e.commission, wage = wage }
        end
    end
    for _, o in ipairs(MySQL.query.await('SELECT * FROM gen_dealership_orders WHERE delivered = 0 ORDER BY arrives_at') or {}) do
        local s = State[o.dealership_id]
        if s then
            s.orders[#s.orders + 1] = { id = o.id, vehicleId = o.vehicle_id, model = o.model, label = o.label, quantity = o.quantity, remaining = o.quantity, cost = o.cost, arrives = o.arrives_at }
        end
    end
    Ready = true
end

function Biz.Get(id)
    local s = State[id]
    if not s then
        s = blank()
        State[id] = s
        Dirty[id] = true
    end
    return s
end

function Biz.Peek(id) return State[id] end
function Biz.IsOwned(id) local s = State[id] return s ~= nil and s.owner ~= nil end
function Biz.Forget(id) State[id] = nil Dirty[id] = nil end
function Biz.MarkDirty(id) Dirty[id] = true end

local function flush()
    local ids = {}
    for id in pairs(Dirty) do ids[#ids + 1] = id end
    Dirty = {}
    for _, id in ipairs(ids) do
        local s = State[id]
        if s and GetDealershipById(id) then
            local ok, err = pcall(MySQL.update.await, [[
                INSERT INTO gen_dealership_business (dealership_id, price, owner, owner_name, owner_since, balance, reputation, target_count, target_bonus, ad_label, ad_boost, ad_until)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE price = VALUES(price), owner = VALUES(owner), owner_name = VALUES(owner_name),
                    owner_since = VALUES(owner_since), balance = VALUES(balance), reputation = VALUES(reputation),
                    target_count = VALUES(target_count), target_bonus = VALUES(target_bonus),
                    ad_label = VALUES(ad_label), ad_boost = VALUES(ad_boost), ad_until = VALUES(ad_until)
            ]], { id, s.price, s.owner or '', s.ownerName or '', s.ownerSince or 0, s.balance, s.reputation,
                s.targetCount or 0, s.targetBonus or 0, s.adLabel or '', s.adBoost or 0, s.adUntil or 0 })
            if not ok then print(('^1[gen_dealership] business flush failed for #%s: %s^0'):format(id, err)) end
        end
    end
end
Biz.Flush = flush

function Biz.Log(id, kind, amount, description, actor)
    MySQL.insert(
        'INSERT INTO gen_dealership_transactions (dealership_id, type, amount, description, actor) VALUES (?, ?, ?, ?, ?)',
        { id, kind, amount or 0, (description or ''):sub(1, 255), (actor or ''):sub(1, 100) }
    )
end

function Biz.AddBalance(id, amount, kind, description, actor)
    local s = Biz.Get(id)
    s.balance = s.balance + amount
    Dirty[id] = true
    Biz.Log(id, kind, amount, description, actor)
end

function Biz.AddReputation(id, delta)
    local s = State[id]
    if not s or not s.owner then return end
    s.reputation = math.max(0, math.min(100, s.reputation + delta))
    Dirty[id] = true
end

function Biz.SetPrice(id, price)
    local s = Biz.Get(id)
    if s.price ~= price then
        s.price = price
        Dirty[id] = true
    end
end

--- Public, non-sensitive business info attached to every dealership sent to clients.
function Biz.Decorate(d)
    local s = State[d.id]
    d.business = {
        owned = s ~= nil and s.owner ~= nil,
        ownerName = s and s.ownerName or '',
        price = s and s.price or 0,
        reputation = s and s.reputation or Sim.startReputation,
    }
end

function Biz.Refresh(id)
    local d = GetDealershipById(id)
    if d then Biz.Decorate(d) end
    BroadcastDealerships()
end

-- ---------------------------------------------------------------------------
-- Players, roles & permissions
-- ---------------------------------------------------------------------------

function Biz.OnlineMap()
    local map = {}
    for _, p in ipairs(GetPlayers()) do
        local src = tonumber(p)
        local ident = Bridge.GetIdentifier(src)
        if ident then map[ident] = src end
    end
    return map
end

function Biz.RoleOf(id, identifier)
    local s = State[id]
    if not s or not s.owner or not identifier then return nil end
    if s.owner == identifier then return 'owner' end
    local e = s.employees[identifier]
    return e and e.role or nil
end

function Biz.GetRole(src, id)
    if not Biz.IsOwned(id) then return nil end
    local role = Biz.RoleOf(id, Bridge.GetIdentifier(src))
    if not role and Sim.adminFullAccess and Bridge.IsAdmin(src) then role = 'owner' end
    return role
end

function Biz.Has(src, id, minRole)
    local role = Biz.GetRole(src, id)
    return role ~= nil and RANK[role] >= RANK[minRole], role
end

--- { ["<dealershipId>"] = role } (string keys so the map survives JSON/msgpack)
function Biz.RolesFor(src)
    local ident = Bridge.GetIdentifier(src)
    local admin = Sim.adminFullAccess and Bridge.IsAdmin(src)
    local out = {}
    for id, s in pairs(State) do
        if s.owner then
            local role = Biz.RoleOf(id, ident) or (admin and 'owner' or nil)
            if role then out[tostring(id)] = role end
        end
    end
    return out
end

function Biz.PushRoles(src)
    TriggerClientEvent('gen_dealership:roles', src, Biz.RolesFor(src))
end

function Biz.PushRolesTo(identifiers)
    local online = Biz.OnlineMap()
    for _, ident in ipairs(identifiers) do
        if online[ident] then Biz.PushRoles(online[ident]) end
    end
end

function Biz.NearbyPlayers(src, radius)
    local out = {}
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return out end
    local origin = GetEntityCoords(ped)
    for _, p in ipairs(GetPlayers()) do
        local other = tonumber(p)
        if other ~= src then
            local oped = GetPlayerPed(other)
            if oped and oped ~= 0 and #(GetEntityCoords(oped) - origin) <= radius then
                out[#out + 1] = { id = other, name = Bridge.GetName(other) }
            end
        end
    end
    return out
end

function Biz.PlayersNear(a, b, radius)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if not pa or pa == 0 or not pb or pb == 0 then return false end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb)) <= radius
end

-- ---------------------------------------------------------------------------
-- Economy helpers
-- ---------------------------------------------------------------------------

function Biz.MinPrice(v) return math.floor((v.cost or 0) * Sim.minMarkup) end
function Biz.MaxPrice(v) return math.max(math.ceil((v.cost or 0) * Sim.maxMarkup), Biz.MinPrice(v) + 1) end

function Biz.PayCommission(id, sellerSrc, price, label)
    local s = State[id]
    if not s or not sellerSrc then return 0 end
    local e = s.employees[Bridge.GetIdentifier(sellerSrc) or '']
    if not e or e.commission <= 0 then return 0 end
    local amount = math.floor(price * e.commission / 100)
    if amount <= 0 then return 0 end
    Biz.AddBalance(id, -amount, 'commission', ('%s%% commission on %s'):format(e.commission, label), e.name)
    Bridge.AddMoney(sellerSrc, 'bank', amount, 'dealership-commission')
    return amount
end

--- Adds units to a vehicle's stock. Returns false when the vehicle no longer exists.
function Biz.AddStock(id, vehicleId, qty)
    local d = GetDealershipById(id)
    local v = d and FindVehicle(d, vehicleId)
    if not v then return false end
    v.stock = math.max(v.stock, 0) + qty
    DB.SetStock(v.id, v.stock)
    return true, d, v
end

--- Called by logistics when one unit of an order has arrived (or been refunded).
function Biz.OrderUnitDone(id, orderId)
    local s = State[id]
    if not s then return end
    for i, o in ipairs(s.orders) do
        if o.id == orderId then
            o.remaining = (o.remaining or o.quantity) - 1
            if o.remaining <= 0 then
                table.remove(s.orders, i)
                MySQL.update('UPDATE gen_dealership_orders SET delivered = 1 WHERE id = ?', { orderId })
            end
            return
        end
    end
end

function Biz.SetOrderRemaining(id, orderId, remaining)
    local s = State[id]
    if not s then return end
    for i, o in ipairs(s.orders) do
        if o.id == orderId then
            if remaining <= 0 then
                table.remove(s.orders, i)
                MySQL.update('UPDATE gen_dealership_orders SET delivered = 1 WHERE id = ?', { orderId })
            else
                o.remaining = remaining
            end
            return
        end
    end
end

function Biz.NotifyManagers(id, msg, kind)
    for ident, src in pairs(Biz.OnlineMap()) do
        local role = Biz.RoleOf(id, ident)
        if role == 'owner' or role == 'manager' then Bridge.Notify(src, msg, kind) end
    end
end

function Biz.ResetOwnership(id, reason)
    local s = State[id]
    if not s or not s.owner then return end
    local affected = { s.owner }
    for ident in pairs(s.employees) do affected[#affected + 1] = ident end

    Staffing.ClockOutAt(id)
    s.owner, s.ownerName, s.ownerSince, s.balance = nil, '', 0, 0
    s.adUntil, s.targetCount, s.targetBonus = 0, 0, 0
    s.employees = {}
    Dirty[id] = true
    MySQL.query('DELETE FROM gen_dealership_employees WHERE dealership_id = ?', { id })
    Biz.Log(id, 'ownership', 0, reason or 'Ownership ended', 'System')

    if RemoveCustomersFor then RemoveCustomersFor(id) end
    Biz.Refresh(id)
    Biz.PushRolesTo(affected)
end

local function ownedCount(ident)
    local n = 0
    for _, s in pairs(State) do
        if s.owner == ident then n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- Snapshot sent to the management panel
-- ---------------------------------------------------------------------------

local function salesStats(id, since)
    local t = now()
    local rows = MySQL.query.await([[
        SELECT DATE_FORMAT(created_at, '%Y-%m-%d') AS day, COUNT(*) AS c, COALESCE(SUM(amount), 0) AS r
        FROM gen_dealership_transactions
        WHERE dealership_id = ? AND type IN ('sale', 'npc_sale')
          AND created_at >= FROM_UNIXTIME(?) AND created_at >= CURDATE() - INTERVAL 6 DAY
        GROUP BY day
    ]], { id, since }) or {}
    local byDay = {}
    for _, r in ipairs(rows) do byDay[r.day] = r end

    local daily, week = {}, { count = 0, revenue = 0 }
    for i = 6, 0, -1 do
        local ts = t - i * 86400
        local r = byDay[os.date('%Y-%m-%d', ts)]
        local entry = { label = i == 0 and 'Today' or os.date('%a', ts), count = r and r.c or 0, revenue = r and tonumber(r.r) or 0 }
        daily[#daily + 1] = entry
        week.count = week.count + entry.count
        week.revenue = week.revenue + entry.revenue
    end
    return { day = { count = daily[7].count, revenue = daily[7].revenue }, week = week, daily = daily }
end

function Biz.Snapshot(src, id)
    local d = GetDealershipById(id)
    local s = State[id]
    if not d or not s then return nil end
    local role = Biz.GetRole(src, id)
    local myIdent = Bridge.GetIdentifier(src)
    local online = Biz.OnlineMap()
    local t = now()

    local incoming = {}
    for _, o in ipairs(s.orders) do incoming[o.vehicleId] = (incoming[o.vehicleId] or 0) + (o.remaining or o.quantity) end

    local vehicles = {}
    for _, v in ipairs(d.vehicles) do
        vehicles[#vehicles + 1] = {
            id = v.id, model = v.model, label = v.label, category = v.category,
            price = v.price, cost = v.cost, stock = v.stock,
            incoming = incoming[v.id] or 0,
            minPrice = Biz.MinPrice(v), maxPrice = Biz.MaxPrice(v),
        }
    end

    local function staffEntry(ident, name, r, commission, wage)
        local esrc = online[ident]
        local shift = esrc and Staffing.ShiftOf(esrc)
        return {
            identifier = ident, name = name, role = r, roleLabel = ROLE_LABEL[r], commission = commission, wage = wage or 0,
            online = esrc ~= nil,
            clockedIn = shift ~= nil and shift.dealershipId == d.id,
            onDuty = esrc ~= nil and IsStaffOnDuty(esrc, d),
            me = ident == myIdent,
        }
    end
    local employees = { staffEntry(s.owner, s.ownerName, 'owner', 0, 0) }
    local onDuty = employees[1].onDuty and 1 or 0
    local list = {}
    for _, e in pairs(s.employees) do list[#list + 1] = staffEntry(e.identifier, e.name, e.role, e.commission, e.wage) end
    table.sort(list, function(a, b)
        if RANK[a.role] ~= RANK[b.role] then return RANK[a.role] > RANK[b.role] end
        return a.name < b.name
    end)
    for _, e in ipairs(list) do
        employees[#employees + 1] = e
        if e.onDuty then onDuty = onDuty + 1 end
    end

    local orders = {}
    for _, o in ipairs(s.orders) do
        local entry = { id = o.id, label = o.label, quantity = o.quantity, remaining = o.remaining or o.quantity, cost = o.cost }
        if o.arrives > 0 then
            entry.eta = math.max(0, o.arrives - t)
        else
            entry.freight = Logistics.OrderSummary(o.id)
        end
        orders[#orders + 1] = entry
    end

    local transactions = MySQL.query.await([[
        SELECT type, amount, description, actor, UNIX_TIMESTAMP(created_at) AS t
        FROM gen_dealership_transactions
        WHERE dealership_id = ? AND created_at >= FROM_UNIXTIME(?)
        ORDER BY id DESC LIMIT 60
    ]], { id, s.ownerSince or 0 }) or {}

    local me = s.employees[myIdent or '']
    local myShift = Staffing.ShiftOf(src)
    local campaigns = {}
    for _, c in ipairs(Config.Advertising.campaigns) do
        campaigns[#campaigns + 1] = { id = c.id, label = c.label, cost = c.cost, boost = c.boost, duration = c.duration, announce = c.announce }
    end

    return {
        id = d.id, name = d.name, label = d.label,
        role = role, roleLabel = ROLE_LABEL[role],
        ownerName = s.ownerName, balance = s.balance, reputation = s.reputation,
        myCommission = me and me.commission or 0,
        myWage = me and me.wage or 0,
        clockedIn = myShift ~= nil and myShift.dealershipId == d.id,
        clockedElsewhere = myShift ~= nil and myShift.dealershipId ~= d.id,
        shiftStarted = myShift and myShift.started or nil,
        shifts = Staffing.RecentShifts(id),
        leaderboard = Staffing.Leaderboard(d, myIdent),
        rank = Staffing.Rank(d),
        target = { count = s.targetCount or 0, bonus = s.targetBonus or 0, mine = myIdent and Staffing.WeeklyCount(d, myIdent) or 0 },
        market = Market.Public(),
        ad = Market.AdPublic(id),
        campaigns = campaigns,
        vehicles = vehicles, employees = employees, orders = orders,
        used = UsedLot.ListFull(id),
        transactions = transactions,
        stats = salesStats(id, s.ownerSince or 0),
        customers = CountCustomers and CountCustomers(id) or 0,
        onDuty = onDuty,
        now = t,
        settings = {
            minMarkup = Sim.minMarkup, maxMarkup = Sim.maxMarkup,
            deliveryTime = Sim.deliveryTime, maxOrderQty = Sim.maxOrderQty,
            maxEmployees = Sim.maxEmployees, maxCommission = Sim.maxCommission,
            sellBack = math.floor(s.price * Sim.sellBackRatio),
            upkeep = Sim.upkeep, upkeepInterval = Sim.upkeepInterval,
            customersEnabled = Sim.customers.enabled,
            dutyRadius = Sim.dutyRadius,
            logistics = Logistics.Enabled(),
            freightFee = Logistics.Enabled() and Logistics.FeeFor(d) or 0,
            depotLabel = Config.Logistics.depot.label,
            autoDeliverAfter = Config.Logistics.autoDeliverAfter,
            requireClockIn = Sim.requireClockIn,
            maxWage = Sim.maxWage,
        },
    }
end

-- ---------------------------------------------------------------------------
-- Management actions
-- ---------------------------------------------------------------------------

local Actions = {}

Actions.open = { min = 'sales', run = function() return { ok = true } end }

Actions.setPrice = { min = 'manager', run = function(src, d, s, p)
    local v = FindVehicle(d, p.vehicleId)
    if not v then return { ok = false, error = T('vehicle_not_found') } end
    local min, max = Biz.MinPrice(v), Biz.MaxPrice(v)
    local price = clampInt(p.price, min, max)
    if not price then
        return { ok = false, error = ('Price must be between %s and %s.'):format(Utils.FormatMoney(min), Utils.FormatMoney(max)) }
    end
    v.price = price
    DB.SetPrice(v.id, price)
    Biz.Log(d.id, 'price', 0, ('%s price set to %s'):format(v.label, Utils.FormatMoney(price)), Bridge.GetName(src))
    BroadcastDealerships()
    return { ok = true }
end }

Actions.clock = { min = 'sales', run = function(src, d)
    local shift = Staffing.ShiftOf(src)
    if shift then
        Staffing.ClockOut(src)
        return { ok = true, message = T('clocked_out') }
    end
    if not IsNear(src, d.shop, Sim.dutyRadius) then return { ok = false, error = T('clock_in_far') } end
    local ok, err = Staffing.ClockIn(src, d)
    if not ok then return { ok = false, error = err } end
    return { ok = true, message = T('clocked_in', d.label) }
end }

Actions.setTarget = { min = 'owner', run = function(src, d, s, p)
    local count = clampInt(p.count, 0, 500)
    local bonus = clampInt(p.bonus, 0, 10000000)
    if not count or not bonus then return { ok = false, error = 'Enter a valid target and bonus.' } end
    s.targetCount, s.targetBonus = count, bonus
    Biz.MarkDirty(d.id)
    Biz.Log(d.id, 'staff', 0, count > 0 and ('Weekly target set: %d sales → %s bonus'):format(count, Utils.FormatMoney(bonus)) or 'Weekly target removed', Bridge.GetName(src))
    return { ok = true, message = 'Weekly target saved.' }
end }

Actions.advertise = { min = 'manager', run = function(src, d, s, p)
    local c = Market.FindCampaign(p.id)
    if not c then return { ok = false, error = 'Unknown campaign.' } end
    if (s.adUntil or 0) > os.time() then return { ok = false, error = T('ad_running') } end
    if s.balance < c.cost then return { ok = false, error = ('Not enough business funds (%s needed).'):format(Utils.FormatMoney(c.cost)) } end

    local message = type(p.message) == 'string' and p.message:gsub('[<>]', ''):sub(1, 90) or ''
    s.adLabel, s.adBoost, s.adUntil = c.label, c.boost, os.time() + c.duration
    Biz.AddBalance(d.id, -c.cost, 'advert', ('%s campaign (%d min)'):format(c.label, math.floor(c.duration / 60)), Bridge.GetName(src))
    if c.announce then
        local text = message ~= '' and message or T('ad_default', d.label)
        TriggerClientEvent('gen_dealership:advert', -1, d.label, text)
    end
    Webhooks.Send('business', ('Advert · %s'):format(d.label), message ~= '' and message or nil, {
        Webhooks.Field('Campaign', c.label), Webhooks.Field('Cost', Utils.FormatMoney(c.cost)), Webhooks.Field('By', Webhooks.Who(src)),
    })
    return { ok = true, message = T('ad_started', c.label) }
end }

Actions.setUsedPrice = { min = 'manager', run = function(src, d, s, p)
    local entry = UsedLot.Find(d.id, p.id)
    if not entry then return { ok = false, error = T('vehicle_not_found') } end
    local max = math.max(1000, entry.value * 3)
    local price = clampInt(p.price, 100, max)
    if not price then return { ok = false, error = ('Price must be between %s and %s.'):format(Utils.FormatMoney(100), Utils.FormatMoney(max)) } end
    UsedLot.SetPrice(d.id, entry.id, price)
    Biz.Log(d.id, 'price', 0, ('Pre-owned %s price set to %s'):format(entry.label, Utils.FormatMoney(price)), Bridge.GetName(src))
    return { ok = true }
end }

Actions.order = { min = 'manager', run = function(src, d, s, p)
    local v = FindVehicle(d, p.vehicleId)
    if not v then return { ok = false, error = T('vehicle_not_found') } end
    local qty = clampInt(p.quantity, 1, Sim.maxOrderQty)
    if not qty then return { ok = false, error = ('Order between 1 and %d units.'):format(Sim.maxOrderQty) } end
    local useFreight = Logistics.Enabled()
    local fee = useFreight and Logistics.FeeFor(d) or 0
    local unitCost = math.floor((v.cost or 0) * Market.CostMultiplier(v.category))
    local total = unitCost * qty
    if s.balance < total + fee * qty then
        return { ok = false, error = ('Not enough business funds (%s needed).'):format(Utils.FormatMoney(total + fee * qty)) }
    end

    local actor = Bridge.GetName(src)
    Biz.AddBalance(d.id, -total, 'order', ('Ordered %dx %s'):format(qty, v.label), actor)
    if fee > 0 then
        Biz.AddBalance(d.id, -fee * qty, 'freight', ('Freight for %dx %s'):format(qty, v.label), actor)
    end

    local order = {
        vehicleId = v.id, model = v.model, label = v.label, quantity = qty, remaining = qty, cost = total,
        arrives = useFreight and 0 or (now() + Sim.deliveryTime),
    }
    s.orders[#s.orders + 1] = order
    order.id = MySQL.insert.await(
        'INSERT INTO gen_dealership_orders (dealership_id, vehicle_id, model, label, quantity, cost, arrives_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { d.id, v.id, v.model, v.label, qty, total, order.arrives }
    )

    if useFreight then
        Logistics.CreateShipments(d, v, order.id, qty, unitCost, fee)
        return { ok = true, message = ('Ordered %dx %s. Waiting for a driver at %s.'):format(qty, v.label, Config.Logistics.depot.label) }
    end
    return { ok = true, message = ('Ordered %dx %s. Arrives in %d min.'):format(qty, v.label, math.ceil(Sim.deliveryTime / 60)) }
end }

Actions.hire = { min = 'manager', run = function(src, d, s, p, myRole)
    local target = tonumber(p.target)
    local role = p.role == 'manager' and 'manager' or 'sales'
    if role == 'manager' and myRole ~= 'owner' then return { ok = false, error = 'Only the owner can hire managers.' } end
    if not target or not GetPlayerName(target) then return { ok = false, error = 'Player not found.' } end
    if not Biz.PlayersNear(src, target, 10.0) then return { ok = false, error = 'That player is too far away.' } end

    local ident = Bridge.GetIdentifier(target)
    if not ident then return { ok = false, error = 'That player has no character loaded.' } end
    if s.owner == ident or s.employees[ident] then return { ok = false, error = 'They already work here.' } end

    local count = 0
    for _ in pairs(s.employees) do count = count + 1 end
    if count >= Sim.maxEmployees then return { ok = false, error = ('Staff limit reached (%d).'):format(Sim.maxEmployees) } end

    local e = { identifier = ident, name = Bridge.GetName(target), role = role, commission = Sim.commission[role] or 0, wage = Sim.wages[role] or 0 }
    s.employees[ident] = e
    MySQL.insert.await(
        'INSERT INTO gen_dealership_employees (dealership_id, identifier, name, role, commission, wage) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), role = VALUES(role), commission = VALUES(commission), wage = VALUES(wage)',
        { d.id, ident, e.name, role, e.commission, e.wage }
    )
    Biz.Log(d.id, 'staff', 0, ('Hired %s as %s'):format(e.name, ROLE_LABEL[role]), Bridge.GetName(src))
    Webhooks.Send('business', ('Staff hired · %s'):format(d.label), ('%s hired **%s** as %s'):format(Bridge.GetName(src), e.name, ROLE_LABEL[role]))
    Biz.PushRoles(target)
    Bridge.Notify(target, ('You were hired at %s as %s.'):format(d.label, ROLE_LABEL[role]), 'success')
    return { ok = true, message = ('%s hired.'):format(e.name) }
end }

Actions.updateEmployee = { min = 'owner', run = function(src, d, s, p)
    local e = s.employees[p.identifier or '']
    if not e then return { ok = false, error = 'Employee not found.' } end
    local role = (p.role == 'manager' or p.role == 'sales') and p.role or e.role
    local commission = clampInt(p.commission, 0, Sim.maxCommission)
    if not commission then return { ok = false, error = ('Commission must be 0-%d%%.'):format(Sim.maxCommission) } end

    local wage = p.wage == nil and e.wage or clampInt(p.wage, 0, Sim.maxWage)
    if not wage then return { ok = false, error = ('Wage must be 0-%s per hour.'):format(Utils.FormatMoney(Sim.maxWage)) } end

    local roleChanged = role ~= e.role
    e.role, e.commission, e.wage = role, commission, wage
    MySQL.update('UPDATE gen_dealership_employees SET role = ?, commission = ?, wage = ? WHERE dealership_id = ? AND identifier = ?', { role, commission, wage, d.id, e.identifier })
    if roleChanged then
        Biz.Log(d.id, 'staff', 0, ('%s is now %s'):format(e.name, ROLE_LABEL[role]), Bridge.GetName(src))
        Biz.PushRolesTo({ e.identifier })
    end
    return { ok = true }
end }

Actions.fire = { min = 'manager', run = function(src, d, s, p, myRole)
    local e = s.employees[p.identifier or '']
    if not e then return { ok = false, error = 'Employee not found.' } end
    if e.role == 'manager' and myRole ~= 'owner' then return { ok = false, error = 'Only the owner can let managers go.' } end

    s.employees[e.identifier] = nil
    Staffing.ClockOutAt(d.id, { [e.identifier] = true })
    MySQL.query('DELETE FROM gen_dealership_employees WHERE dealership_id = ? AND identifier = ?', { d.id, e.identifier })
    Biz.Log(d.id, 'staff', 0, ('Let go of %s'):format(e.name), Bridge.GetName(src))
    Webhooks.Send('business', ('Staff let go · %s'):format(d.label), ('%s let go of **%s**'):format(Bridge.GetName(src), e.name), nil, 'warn')
    Biz.PushRolesTo({ e.identifier })
    local online = Biz.OnlineMap()
    if online[e.identifier] then Bridge.Notify(online[e.identifier], ('You no longer work at %s.'):format(d.label), 'error') end
    return { ok = true, message = ('%s was let go.'):format(e.name) }
end }

Actions.deposit = { min = 'manager', run = function(src, d, s, p)
    local amount = clampInt(p.amount, 1, 1000000000)
    if not amount then return { ok = false, error = 'Enter a valid amount.' } end
    if Bridge.Framework == 'standalone' then return { ok = false, error = 'No economy in standalone mode.' } end
    if not Bridge.RemoveMoney(src, 'bank', amount, 'dealership-deposit') then return { ok = false, error = T('not_enough_money') } end
    Biz.AddBalance(d.id, amount, 'deposit', 'Deposit', Bridge.GetName(src))
    return { ok = true, message = ('Deposited %s.'):format(Utils.FormatMoney(amount)) }
end }

Actions.withdraw = { min = 'owner', run = function(src, d, s, p)
    local amount = clampInt(p.amount, 1, 1000000000)
    if not amount then return { ok = false, error = 'Enter a valid amount.' } end
    if s.balance < amount then return { ok = false, error = 'Not enough business funds.' } end
    Biz.AddBalance(d.id, -amount, 'withdraw', 'Withdrawal', Bridge.GetName(src))
    Webhooks.Send('business', ('Withdrawal · %s'):format(d.label), nil, {
        Webhooks.Field('By', Webhooks.Who(src)),
        Webhooks.Field('Amount', Utils.FormatMoney(amount)),
        Webhooks.Field('Balance left', Utils.FormatMoney(s.balance)),
    }, amount >= 100000 and 'warn' or 'info')
    Bridge.AddMoney(src, 'bank', amount, 'dealership-withdraw')
    return { ok = true, message = ('Withdrew %s.'):format(Utils.FormatMoney(amount)) }
end }

Actions.nearby = { min = 'sales', snapshot = false, run = function(src)
    return { ok = true, players = Biz.NearbyPlayers(src, 10.0) }
end }

Actions.offer = { min = 'sales', snapshot = false, run = function(src, d, s, p)
    return CreateStaffOffer(src, d, p)
end }

Actions.sellBusiness = { min = 'owner', snapshot = false, run = function(src, d, s)
    if s.owner ~= Bridge.GetIdentifier(src) then return { ok = false, error = 'Only the real owner can sell the business.' } end
    local payout = math.floor(s.price * Sim.sellBackRatio) + math.max(s.balance, 0)
    Bridge.AddMoney(src, 'bank', payout, 'dealership-sold')
    Webhooks.Send('business', ('Business sold back · %s'):format(d.label), nil, {
        Webhooks.Field('Owner', Webhooks.Who(src)),
        Webhooks.Field('Payout', Utils.FormatMoney(payout)),
    }, 'warn')
    Biz.ResetOwnership(d.id, ('Business sold back by %s'):format(s.ownerName))
    return { ok = true, closed = true, message = ('You sold %s for %s (including remaining funds).'):format(d.label, Utils.FormatMoney(payout)) }
end }

RegisterCallback('biz:action', function(src, id, action, payload)
    id = tonumber(id)
    local d = id and GetDealershipById(id)
    if not d or not Biz.IsOwned(id) then return { ok = false, error = 'This dealership has no owner.' } end
    local def = Actions[action]
    if not def then return { ok = false, error = 'Unknown action.' } end

    local allowed, role = Biz.Has(src, id, def.min)
    if not allowed then return { ok = false, error = T('no_permission') } end

    local res = def.run(src, d, Biz.Get(id), type(payload) == 'table' and payload or {}, role) or { ok = false }
    if res.ok and def.snapshot ~= false then res.data = Biz.Snapshot(src, id) end
    return res
end)

RegisterCallback('biz:roles', function(src)
    return Biz.RolesFor(src)
end)

local buyLock = {}
RegisterCallback('biz:buyBusiness', function(src, id, method)
    id = tonumber(id)
    local d = id and GetDealershipById(id)
    if not d then return { ok = false, error = T('vehicle_not_found') } end
    local s = Biz.Get(id)
    if s.owner then return { ok = false, error = 'This dealership already has an owner.' } end
    if s.price <= 0 then return { ok = false, error = 'This dealership is not for sale.' } end
    if not IsNear(src, d.shop, Config.PurchaseDistance) then return { ok = false, error = T('too_far') } end

    local ident = Bridge.GetIdentifier(src)
    if not ident then return { ok = false, error = 'No character loaded.' } end
    if ownedCount(ident) >= Sim.maxOwnedPerPlayer then
        return { ok = false, error = ('You can own at most %d dealership(s).'):format(Sim.maxOwnedPerPlayer) }
    end
    if buyLock[id] then return { ok = false, error = T('busy') } end
    buyLock[id] = true

    local method_ = method == 'cash' and 'cash' or 'bank'
    if not Bridge.RemoveMoney(src, method_, s.price, 'dealership-business-purchase') then
        buyLock[id] = nil
        return { ok = false, error = T('not_enough_money') }
    end
    if s.owner then -- someone else won the race while money was being taken
        Bridge.AddMoney(src, method_, s.price, 'dealership-business-refund')
        buyLock[id] = nil
        return { ok = false, error = 'This dealership already has an owner.' }
    end

    s.owner, s.ownerName, s.ownerSince = ident, Bridge.GetName(src), now()
    s.balance = 0
    s.employees = {}
    Dirty[id] = true

    -- Owned dealerships run on real stock: unlimited stock becomes 0 and must be ordered
    for _, v in ipairs(d.vehicles) do
        if v.stock < 0 then
            v.stock = 0
            DB.SetStock(v.id, 0)
        end
    end

    Biz.Log(id, 'ownership', 0, ('Business bought by %s for %s'):format(s.ownerName, Utils.FormatMoney(s.price)), s.ownerName)
    buyLock[id] = nil
    Biz.Refresh(id)
    Biz.PushRoles(src)
    print(('[gen_dealership] %s bought dealership "%s"'):format(GetPlayerName(src), d.name))
    Webhooks.Send('business', ('Business bought · %s'):format(d.label), nil, {
        Webhooks.Field('Owner', Webhooks.Who(src)),
        Webhooks.Field('Price', Utils.FormatMoney(s.price)),
    }, 'good')
    return { ok = true, message = ('You now own %s! Press G at the catalogue point to manage it.'):format(d.label) }
end)

-- ---------------------------------------------------------------------------
-- Background: deliveries, upkeep, persistence
-- ---------------------------------------------------------------------------

local function deliver(id, s, o)
    MySQL.update('UPDATE gen_dealership_orders SET delivered = 1 WHERE id = ?', { o.id })
    local ok, d = Biz.AddStock(id, o.vehicleId, o.quantity)
    if not ok then
        -- vehicle was removed from the catalogue: refund the order
        Biz.AddBalance(id, o.cost, 'refund', ('Refund: %dx %s (no longer sold)'):format(o.quantity, o.label), 'System')
        return false
    end
    Biz.Log(id, 'delivery', 0, ('Delivered %dx %s'):format(o.quantity, o.label), 'System')
    Biz.NotifyManagers(id, ('%s: %dx %s delivered.'):format(d.label, o.quantity, o.label), 'success')
    return true
end

CreateThread(function()
    local lastUpkeep = now()
    while true do
        Wait(5000)
        if Ready then
            local t = now()
            local delivered = false
            for id, s in pairs(State) do
                if #s.orders > 0 then
                    local remaining = {}
                    for _, o in ipairs(s.orders) do
                        if o.arrives > 0 and o.arrives <= t then
                            if deliver(id, s, o) then delivered = true end
                        else
                            remaining[#remaining + 1] = o
                        end
                    end
                    s.orders = remaining
                end
            end
            if delivered then BroadcastDealerships() end

            if Sim.upkeep > 0 and t - lastUpkeep >= Sim.upkeepInterval then
                lastUpkeep = t
                for id, s in pairs(State) do
                    if s.owner then Biz.AddBalance(id, -Sim.upkeep, 'upkeep', 'Property upkeep', 'System') end
                end
            end

            flush()
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and Ready then flush() end
end)
