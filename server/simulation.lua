-- AI customers & staff-to-player sale offers.
local Sim = Config.Simulation
local Cfg = Sim.customers
local T = Utils.T

local Customers = {}       -- [id] = customer
local nextCustomerId = 0
local Offers = {}          -- [id] = offer
local nextOfferId = 0

local FirstNames = { 'Alex', 'Jordan', 'Sam', 'Taylor', 'Morgan', 'Casey', 'Riley', 'Jamie', 'Avery', 'Quinn', 'Dakota', 'Reese', 'Skyler', 'Rowan', 'Elliot', 'Harper', 'Marco', 'Lena', 'Victor', 'Nina' }
local LastNames = { 'Reyes', 'Walker', 'Kim', 'Novak', 'Bennett', 'Okafor', 'Lindqvist', 'Moreau', 'Hayes', 'Castillo', 'Ito', 'Sullivan', 'Byrne', 'Varga', 'Mendes' }

local Lines = {
    greet = {
        "Hi! I've had my eye on the %s. What kind of deal can you do?",
        "That %s looks great. Let's talk numbers.",
        "I'm shopping for a %s today. Make me an offer I can't refuse.",
        "My old ride just died. Is this %s worth the money?",
    },
    counter = {
        "Hmm, that's steep. I could do %s.",
        "Meet me halfway: %s.",
        "I've seen better prices. %s, final-ish offer.",
        "Let's be reasonable. How about %s?",
    },
    accept = {
        "Deal! Where do I sign?",
        "You've got yourself a sale.",
        "Perfect, I'll take it!",
        "Alright, you drive a hard bargain. Deal.",
    },
    leave = {
        "That's way out of my budget. Have a nice day.",
        "I think I'll look elsewhere.",
        "Forget it, I'm out.",
    },
    insult = {
        "Are you serious? That's insulting. I'm leaving.",
        "You must think I'm an idiot. Bye.",
    },
    soldout = { "Oh, it's sold out? Never mind then." },
    declined = { "Your loss. Bye." },
}

local function pick(list) return list[math.random(#list)] end
local function round100(n) return math.floor(n / 100 + 0.5) * 100 end
local function rand(a, b) return a + math.random() * (b - a) end

local function clampInt(v, min, max)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    v = math.floor(v)
    if v < min or v > max then return nil end
    return v
end

-- ---------------------------------------------------------------------------
-- Customers
-- ---------------------------------------------------------------------------

local function publicList()
    local list = {}
    for _, c in pairs(Customers) do
        list[#list + 1] = { id = c.id, dealershipId = c.dealershipId, name = c.name, ped = c.ped, coords = c.coords, label = c.label }
    end
    return list
end

local function broadcastCustomers(target)
    TriggerClientEvent('gen_dealership:customers', target or -1, publicList())
end

function CountCustomers(id)
    local n = 0
    for _, c in pairs(Customers) do
        if c.dealershipId == id then n = n + 1 end
    end
    return n
end

function RemoveCustomersFor(id)
    local changed = false
    for cid, c in pairs(Customers) do
        if c.dealershipId == id then Customers[cid] = nil changed = true end
    end
    if changed then broadcastCustomers() end
end

local function pickSpot(d)
    local spots = d.displays or {}
    if #spots > 0 then
        local s = spots[math.random(#spots)]
        local h = math.rad(s.w)
        local side = math.random() < 0.5 and 1 or -1
        local rx, ry = math.cos(h) * side, math.sin(h) * side
        local dist = 2.3
        return {
            x = s.x + rx * dist, y = s.y + ry * dist, z = s.z,
            w = (s.w + 90.0 * side) % 360, -- facing the car
        }
    end
    local a = math.random() * math.pi * 2
    local r = rand(3.0, 5.0)
    return { x = d.shop.x + math.cos(a) * r, y = d.shop.y + math.sin(a) * r, z = d.shop.z, w = math.random(0, 359) + 0.0 }
end

local function spawnCustomer(d, s)
    local pool = {}
    for _, v in ipairs(d.vehicles) do
        if v.stock > 0 then pool[#pool + 1] = v end
    end
    if #pool == 0 then return false end
    local v = pick(pool)

    -- Reputation nudges budgets: 0 rep = 5% below list, 100 rep = 5% above
    local repFactor = 0.95 + s.reputation / 1000
    local budget = round100(v.price * rand(0.88, 1.12) * repFactor)
    local offer = round100(budget * rand(0.82, 0.94))

    nextCustomerId = nextCustomerId + 1
    Customers[nextCustomerId] = {
        id = nextCustomerId,
        dealershipId = d.id,
        name = ('%s %s'):format(pick(FirstNames), pick(LastNames)),
        ped = pick(Cfg.peds),
        coords = pickSpot(d),
        vehicleId = v.id,
        label = v.label,
        listPrice = v.price,
        budget = budget,
        offer = offer,
        round = 0,
        servedBy = nil,
        engaged = false,
        expires = os.time() + Cfg.patience,
    }
    return true
end

local function staffOnDuty(d, online)
    local n = 0
    for ident, src in pairs(online) do
        if Biz.RoleOf(d.id, ident) and IsNear(src, d.shop, Sim.dutyRadius) then n = n + 1 end
    end
    return n
end

local function tick()
    local t = os.time()
    local changed = false

    for id, c in pairs(Customers) do
        if c.servedBy and not GetPlayerName(c.servedBy) then c.servedBy = nil end
        if t > c.expires and not c.servedBy then
            if not c.engaged then Biz.AddReputation(c.dealershipId, -1) end
            Customers[id] = nil
            changed = true
        end
    end

    if Cfg.enabled then
        local online = Biz.OnlineMap()
        for _, d in ipairs(GetAllDealerships()) do
            local s = Biz.Peek(d.id)
            if s and s.owner and d.shop then
                if staffOnDuty(d, online) == 0 then
                    for id, c in pairs(Customers) do
                        if c.dealershipId == d.id and not c.servedBy then Customers[id] = nil changed = true end
                    end
                else
                    local max = math.min(Cfg.maxActive, 1 + math.floor(s.reputation / 35))
                    local chance = Cfg.baseChance * (0.5 + s.reputation / 100)
                    if CountCustomers(d.id) < max and math.random() < chance then
                        if spawnCustomer(d, s) then changed = true end
                    end
                end
            end
        end
    end

    if changed then broadcastCustomers() end
end

CreateThread(function()
    while true do
        Wait(Cfg.interval * 1000)
        local ok, err = pcall(tick)
        if not ok then print(('^1[gen_dealership] simulation tick failed: %s^0'):format(err)) end
    end
end)

RegisterCallback('customers:get', function()
    return publicList()
end)

local function negotiationView(c, d, v, src, extra)
    local s = Biz.Peek(c.dealershipId)
    local e = s and s.employees[Bridge.GetIdentifier(src) or '']
    local view = {
        ok = true,
        id = c.id,
        name = c.name,
        label = c.label,
        model = v and v.model,
        listPrice = c.listPrice,
        cost = v and v.cost or 0,
        offer = c.offer,
        round = c.round,
        maxRounds = Cfg.maxRounds,
        commission = e and e.commission or 0,
        state = 'open',
    }
    for k, val in pairs(extra or {}) do view[k] = val end
    return view
end

RegisterCallback('customer:engage', function(src, id)
    local c = Customers[tonumber(id)]
    if not c then return { ok = false, error = 'That customer has left.' } end
    if not Biz.Has(src, c.dealershipId, 'sales') then return { ok = false, error = T('no_permission') } end
    if not IsNear(src, c.coords, 6.0) then return { ok = false, error = T('too_far') } end
    if c.servedBy and c.servedBy ~= src then return { ok = false, error = 'A colleague is already helping this customer.' } end

    local d = GetDealershipById(c.dealershipId)
    local v = d and FindVehicle(d, c.vehicleId)
    if not v then
        Customers[c.id] = nil
        broadcastCustomers()
        return { ok = false, error = 'That customer has left.' }
    end

    c.servedBy = src
    c.expires = math.max(c.expires, os.time() + 120)
    local line = c.engaged and ('Still thinking about it. My offer stands at %s.'):format(Utils.FormatMoney(c.offer))
        or pick(Lines.greet):format(c.label)
    c.engaged = true
    return negotiationView(c, d, v, src, { line = line })
end)

RegisterNetEvent('gen_dealership:customerRelease', function()
    local src = source
    for _, c in pairs(Customers) do
        if c.servedBy == src then c.servedBy = nil end
    end
end)

local function finishCustomer(c, d)
    Customers[c.id] = nil
    broadcastCustomers()
end

local function closeDeal(src, c, d, v, price)
    v.stock = v.stock - 1
    DB.SetStock(v.id, v.stock)
    local sellerName = Bridge.GetName(src)
    Biz.AddBalance(d.id, price, 'npc_sale', ('%s sold to %s'):format(v.label, c.name), sellerName)
    local commission = Biz.PayCommission(d.id, src, price, v.label)
    Biz.AddReputation(d.id, price <= c.listPrice and 2 or 1)
    DB.LogSale(d.name, 'npc:' .. c.name, v.model, '-', price, 'bank', Bridge.GetIdentifier(src) or '', 'npc')
    Webhooks.Send('sales', ('Walk-in sale · %s'):format(d.label), nil, {
        Webhooks.Field('Vehicle', v.label),
        Webhooks.Field('Price', Utils.FormatMoney(price)),
        Webhooks.Field('Customer', c.name),
        Webhooks.Field('Salesperson', sellerName),
    }, 'good')
    finishCustomer(c, d)
    BroadcastDealerships()
    return negotiationView(c, d, v, src, {
        state = 'sold', price = price, commissionPaid = commission, line = pick(Lines.accept),
    })
end

RegisterCallback('customer:respond', function(src, id, action, amount)
    local c = Customers[tonumber(id)]
    if not c or c.servedBy ~= src then return { ok = false, error = 'That customer has left.' } end
    if not Biz.Has(src, c.dealershipId, 'sales') then return { ok = false, error = T('no_permission') } end

    local d = GetDealershipById(c.dealershipId)
    local v = d and FindVehicle(d, c.vehicleId)
    if not v or v.stock <= 0 then
        finishCustomer(c, d)
        return negotiationView(c, d, v, src, { state = 'left', line = pick(Lines.soldout) })
    end

    if action == 'accept' then
        return closeDeal(src, c, d, v, c.offer)
    elseif action == 'decline' then
        finishCustomer(c, d)
        return negotiationView(c, d, v, src, { state = 'left', line = pick(Lines.declined) })
    elseif action ~= 'counter' then
        return { ok = false, error = 'Unknown action.' }
    end

    local ask = clampInt(amount, 1, 1000000000)
    if not ask then return { ok = false, error = 'Enter a valid price.' } end

    if ask <= c.offer or ask <= c.budget then
        return closeDeal(src, c, d, v, ask)
    end
    if ask <= c.budget * 1.08 and math.random() < 0.4 then
        return closeDeal(src, c, d, v, ask)
    end
    if ask > c.listPrice * 1.25 then
        Biz.AddReputation(d.id, -2)
        finishCustomer(c, d)
        return negotiationView(c, d, v, src, { state = 'left', line = pick(Lines.insult) })
    end

    c.round = c.round + 1
    if c.round >= Cfg.maxRounds then
        Biz.AddReputation(d.id, -1)
        finishCustomer(c, d)
        return negotiationView(c, d, v, src, { state = 'left', line = pick(Lines.leave) })
    end

    c.offer = math.min(c.budget, round100(c.offer + (c.budget - c.offer) * rand(0.4, 0.7)))
    c.expires = math.max(c.expires, os.time() + 120)
    return negotiationView(c, d, v, src, { state = 'countered', line = pick(Lines.counter):format(Utils.FormatMoney(c.offer)) })
end)

-- ---------------------------------------------------------------------------
-- Staff -> player offers
-- ---------------------------------------------------------------------------

function CreateStaffOffer(src, d, p)
    local v = FindVehicle(d, p.vehicleId)
    if not v then return { ok = false, error = T('vehicle_not_found') } end
    if v.stock <= 0 then return { ok = false, error = T('out_of_stock') } end

    local target = tonumber(p.target)
    if not target or target == src or not GetPlayerName(target) then return { ok = false, error = 'Choose a customer.' } end
    if not IsNear(src, d.shop, Sim.dutyRadius) then return { ok = false, error = 'You must be at the dealership.' } end
    if not Biz.PlayersNear(src, target, 10.0) then return { ok = false, error = 'The customer is too far away.' } end

    local min, max = Biz.MinPrice(v), Biz.MaxPrice(v)
    local price = clampInt(p.price, min, max)
    if not price then
        return { ok = false, error = ('Price must be between %s and %s.'):format(Utils.FormatMoney(min), Utils.FormatMoney(max)) }
    end

    local t = os.time()
    for oid, o in pairs(Offers) do
        if o.expires < t then
            Offers[oid] = nil
        elseif o.target == target then
            return { ok = false, error = 'That customer already has a pending offer.' }
        end
    end

    nextOfferId = nextOfferId + 1
    local sellerName = Bridge.GetName(src)
    Offers[nextOfferId] = {
        id = nextOfferId, dealershipId = d.id, vehicleId = v.id,
        seller = src, sellerName = sellerName, sellerIdentifier = Bridge.GetIdentifier(src),
        target = target, price = price, expires = t + Sim.offerTimeout + 5,
    }
    TriggerClientEvent('gen_dealership:offer', target, {
        id = nextOfferId,
        dealership = d.label,
        label = v.label,
        model = v.model,
        price = price,
        sellerName = sellerName,
        payment = Config.PaymentMethods,
        timeout = Sim.offerTimeout,
    })
    return { ok = true, message = ('Offer sent to %s.'):format(Bridge.GetName(target)) }
end

RegisterCallback('offer:respond', function(src, id, accept, method)
    local o = Offers[tonumber(id)]
    if not o or o.target ~= src then return { ok = false, error = 'This offer is no longer valid.' } end
    Offers[o.id] = nil
    if os.time() > o.expires then return { ok = false, error = 'This offer has expired.' } end

    local sellerOnline = GetPlayerName(o.seller) ~= nil
    if not accept then
        if sellerOnline then Bridge.Notify(o.seller, ('%s declined your offer.'):format(Bridge.GetName(src)), 'error') end
        return { ok = true, declined = true }
    end

    local d = GetDealershipById(o.dealershipId)
    local v = d and FindVehicle(d, o.vehicleId)
    if not v or not Biz.IsOwned(d.id) then return { ok = false, error = T('vehicle_not_found') } end

    local res = ProcessSale(src, d, v, method, o.price, {
        seller = sellerOnline and o.seller or nil,
        sellerName = o.sellerName,
        sellerIdentifier = o.sellerIdentifier,
        kind = 'staff',
    })
    if sellerOnline then
        if res.ok then
            local extra = (res.commission or 0) > 0 and (' · commission %s'):format(Utils.FormatMoney(res.commission)) or ''
            Bridge.Notify(o.seller, ('Sold %s to %s for %s%s'):format(v.label, Bridge.GetName(src), Utils.FormatMoney(o.price), extra), 'success')
        else
            Bridge.Notify(o.seller, ('Sale failed: %s'):format(res.error or '?'), 'error')
        end
    end
    if res.ok then
        res.spawn = d.spawn
        Biz.AddReputation(d.id, 1)
    end
    return res
end)

AddEventHandler('playerDropped', function()
    local src = source
    for oid, o in pairs(Offers) do
        if o.target == src or o.seller == src then Offers[oid] = nil end
    end
    for _, c in pairs(Customers) do
        if c.servedBy == src then c.servedBy = nil end
    end
end)
