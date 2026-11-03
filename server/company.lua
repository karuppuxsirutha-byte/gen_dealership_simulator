-- Player-owned logistics company: takes a cut of every haul, hires drivers
-- (who can then haul without the logistics job), owner withdraws profits.
Company = {}

local C = Config.Logistics.company
local T = Utils.T
local state = { owner = nil, ownerName = '', balance = 0, cut = C and C.defaultCut or 0 }
local Drivers = {}   -- [identifier] = name

function Company.Enabled() return C ~= nil and C.enabled == true end

local function save()
    MySQL.update('UPDATE gen_logistics_company SET owner = ?, owner_name = ?, balance = ?, cut = ? WHERE id = 1',
        { state.owner or '', state.ownerName or '', state.balance, state.cut })
end

function Company.Load()
    if not Company.Enabled() then return end
    MySQL.insert.await('INSERT IGNORE INTO gen_logistics_company (id, cut) VALUES (1, ?)', { C.defaultCut })
    local row = MySQL.single.await('SELECT * FROM gen_logistics_company WHERE id = 1')
    if row then
        state.owner = row.owner ~= '' and row.owner or nil
        state.ownerName = row.owner_name or ''
        state.balance = tonumber(row.balance) or 0
        state.cut = row.cut
    end
    Drivers = {}
    for _, r in ipairs(MySQL.query.await('SELECT identifier, name FROM gen_logistics_drivers') or {}) do
        Drivers[r.identifier] = r.name
    end
end

function Company.IsMember(ident)
    if not Company.Enabled() or not ident or not state.owner then return false end
    return state.owner == ident or Drivers[ident] ~= nil
end

--- Splits a haul payment: driver share, company cut
function Company.Split(amount)
    if not Company.Enabled() or not state.owner or amount <= 0 then return amount, 0 end
    local cut = math.floor(amount * state.cut / 100)
    return amount - cut, cut
end

function Company.Credit(amount)
    if amount <= 0 or not state.owner then return end
    state.balance = state.balance + amount
    save()
end

function Company.Public(src)
    if not Company.Enabled() then return nil end
    local ident = Bridge.GetIdentifier(src)
    local isOwner = state.owner ~= nil and state.owner == ident
    local out = {
        label = C.label, owned = state.owner ~= nil, ownerName = state.ownerName,
        price = C.price, cut = state.cut, isOwner = isOwner, isDriver = Drivers[ident or ''] ~= nil,
    }
    if isOwner then
        local online = Biz.OnlineMap()
        local drivers = {}
        for id, name in pairs(Drivers) do drivers[#drivers + 1] = { identifier = id, name = name, online = online[id] ~= nil } end
        table.sort(drivers, function(a, b) return a.name < b.name end)
        out.admin = {
            balance = state.balance, maxCut = C.maxCut, maxDrivers = C.maxDrivers,
            sellBack = math.floor(C.price * C.sellBackRatio), drivers = drivers,
        }
    end
    return out
end

local function clampInt(v, min, max)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    v = math.floor(v)
    if v < min or v > max then return nil end
    return v
end

RegisterCallback('logistics:company', function(src, action, p)
    p = type(p) == 'table' and p or {}
    if not Company.Enabled() then return { ok = false, error = 'The logistics company is disabled.' } end
    if not IsNear(src, Config.Logistics.depot.board, 15.0) then return { ok = false, error = T('too_far') } end
    local ident = Bridge.GetIdentifier(src)
    if not ident then return { ok = false, error = 'No character loaded.' } end

    local function done(message) return { ok = true, message = message, board = Logistics.Board(src) } end

    if action == 'buy' then
        if state.owner then return { ok = false, error = 'The company already has an owner.' } end
        if not Bridge.RemoveMoney(src, 'bank', C.price, 'logistics-company') then return { ok = false, error = T('not_enough_money') } end
        state.owner, state.ownerName, state.balance, state.cut = ident, Bridge.GetName(src), 0, C.defaultCut
        save()
        Webhooks.Send('logistics', ('%s bought'):format(C.label), nil, {
            Webhooks.Field('Owner', Webhooks.Who(src)), Webhooks.Field('Price', Utils.FormatMoney(C.price)),
        }, 'good')
        return done(('You now own %s!'):format(C.label))
    end

    if state.owner ~= ident then return { ok = false, error = T('no_permission') } end

    if action == 'withdraw' then
        local amount = clampInt(p.amount, 1, 1000000000)
        if not amount or amount > state.balance then return { ok = false, error = 'Enter an amount up to the company balance.' } end
        state.balance = state.balance - amount
        save()
        Bridge.AddMoney(src, 'bank', amount, 'logistics-company-withdraw')
        return done(('Withdrew %s.'):format(Utils.FormatMoney(amount)))
    elseif action == 'setCut' then
        local cut = clampInt(p.cut, 0, C.maxCut)
        if not cut then return { ok = false, error = ('Cut must be 0-%d%%.'):format(C.maxCut) } end
        state.cut = cut
        save()
        return done(('Company cut set to %d%%.'):format(cut))
    elseif action == 'nearby' then
        return { ok = true, players = Biz.NearbyPlayers(src, 10.0) }
    elseif action == 'hire' then
        local target = tonumber(p.target)
        if not target or not GetPlayerName(target) or not Biz.PlayersNear(src, target, 10.0) then return { ok = false, error = 'That player is too far away.' } end
        local tIdent = Bridge.GetIdentifier(target)
        if not tIdent or tIdent == ident or Drivers[tIdent] then return { ok = false, error = 'They already drive for you.' } end
        local count = 0
        for _ in pairs(Drivers) do count = count + 1 end
        if count >= C.maxDrivers then return { ok = false, error = ('Driver limit reached (%d).'):format(C.maxDrivers) } end
        local name = Bridge.GetName(target)
        Drivers[tIdent] = name
        MySQL.insert('INSERT IGNORE INTO gen_logistics_drivers (identifier, name) VALUES (?, ?)', { tIdent, name })
        Bridge.Notify(target, T('company_hired', C.label), 'success')
        return done(('%s hired.'):format(name))
    elseif action == 'fire' then
        local name = Drivers[p.identifier or '']
        if not name then return { ok = false, error = 'Driver not found.' } end
        Drivers[p.identifier] = nil
        MySQL.query('DELETE FROM gen_logistics_drivers WHERE identifier = ?', { p.identifier })
        local online = Biz.OnlineMap()[p.identifier]
        if online then Bridge.Notify(online, T('company_fired', C.label), 'error') end
        return done(('%s was let go.'):format(name))
    elseif action == 'sell' then
        local payout = math.floor(C.price * C.sellBackRatio) + state.balance
        Bridge.AddMoney(src, 'bank', payout, 'logistics-company-sold')
        Webhooks.Send('logistics', ('%s sold back'):format(C.label), nil, {
            Webhooks.Field('Owner', Webhooks.Who(src)), Webhooks.Field('Payout', Utils.FormatMoney(payout)),
        }, 'warn')
        state.owner, state.ownerName, state.balance, state.cut = nil, '', 0, C.defaultCut
        Drivers = {}
        MySQL.query('DELETE FROM gen_logistics_drivers')
        save()
        return done(('Sold for %s.'):format(Utils.FormatMoney(payout)))
    end
    return { ok = false, error = 'Unknown action.' }
end)

function Company.Totals()
    return { owned = state.owner ~= nil, ownerName = state.ownerName, balance = state.balance, cut = state.cut }
end
