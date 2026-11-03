-- Admin dashboard (/dealeradmin) and vehicle registration papers.
local T = Utils.T

local function weekAgo() return os.time() - 7 * 86400 end

local function dashboard()
    local since = weekAgo()

    local totals = MySQL.single.await([[
        SELECT COUNT(*) AS c, COALESCE(SUM(price), 0) AS r FROM gen_dealership_sales WHERE sold_at >= FROM_UNIXTIME(?)
    ]], { since }) or { c = 0, r = 0 }

    local byKind = MySQL.query.await([[
        SELECT kind, COUNT(*) AS c, COALESCE(SUM(price), 0) AS r FROM gen_dealership_sales
        WHERE sold_at >= FROM_UNIXTIME(?) GROUP BY kind ORDER BY r DESC
    ]], { since }) or {}

    local topModels = MySQL.query.await([[
        SELECT model, COUNT(*) AS c, COALESCE(SUM(price), 0) AS r FROM gen_dealership_sales
        WHERE sold_at >= FROM_UNIXTIME(?) GROUP BY model ORDER BY c DESC LIMIT 8
    ]], { since }) or {}

    local perDealer = {}
    for _, r in ipairs(MySQL.query.await([[
        SELECT dealership, COUNT(*) AS c, COALESCE(SUM(price), 0) AS r FROM gen_dealership_sales
        WHERE sold_at >= FROM_UNIXTIME(?) GROUP BY dealership
    ]], { since }) or {}) do perDealer[r.dealership] = r end

    local bigMoves = MySQL.query.await([[
        SELECT t.type, t.amount, t.description, t.actor, UNIX_TIMESTAMP(t.created_at) AS t, d.label AS dealership
        FROM gen_dealership_transactions t JOIN gen_dealerships d ON d.id = t.dealership_id
        WHERE t.created_at >= NOW() - INTERVAL 1 DAY AND t.amount <> 0
        ORDER BY ABS(t.amount) DESC LIMIT 10
    ]]) or {}

    local labels = {}
    local dealers, balances = {}, 0
    for _, d in ipairs(GetAllDealerships()) do
        local s = Biz.Peek(d.id)
        local units = 0
        for _, v in ipairs(d.vehicles) do
            labels[v.model] = v.label
            if v.stock > 0 then units = units + v.stock end
        end
        local staff = 0
        if s then for _ in pairs(s.employees) do staff = staff + 1 end end
        local sales = perDealer[d.name] or { c = 0, r = 0 }
        if s and s.owner then balances = balances + s.balance end
        dealers[#dealers + 1] = {
            id = d.id, name = d.name, label = d.label,
            owned = s ~= nil and s.owner ~= nil, ownerName = s and s.ownerName or '',
            balance = s and s.owner and s.balance or nil, reputation = s and s.reputation or nil,
            staff = staff, stock = units, catalogue = #d.vehicles, used = #(d.used or {}),
            sales = sales.c, revenue = tonumber(sales.r) or 0,
        }
    end
    table.sort(dealers, function(a, b) return a.revenue > b.revenue end)
    for _, m in ipairs(topModels) do m.label = labels[m.model] or m.model; m.r = tonumber(m.r) or 0 end
    for _, k in ipairs(byKind) do k.r = tonumber(k.r) or 0 end

    local events = {}
    for _, ev in ipairs(Config.Market.events) do events[#events + 1] = { id = ev.id, label = ev.label } end

    return {
        ok = true,
        now = os.time(),
        totals = { count = totals.c, revenue = tonumber(totals.r) or 0 },
        byKind = byKind, topModels = topModels, dealers = dealers, bigMoves = bigMoves,
        economy = {
            businessBalances = balances,
            finance = Finance.Totals(),
            logistics = Logistics.Totals(),
            company = Company.Enabled() and Company.Totals() or nil,
        },
        market = Market.Public(), events = events,
    }
end

RegisterCommand('dealeradmin', function(src)
    if src == 0 then return print('[gen_dealership] /dealeradmin must be used in-game.') end
    if not Bridge.IsAdmin(src) then return Bridge.Notify(src, T('no_permission'), 'error') end
    TriggerClientEvent('gen_dealership:admin:open', src, dashboard())
end, false)

RegisterCallback('admin:dashboard', function(src)
    if not Bridge.IsAdmin(src) then return { ok = false, error = T('no_permission') } end
    return dashboard()
end)

RegisterCallback('admin:market', function(src, id)
    if not Bridge.IsAdmin(src) then return { ok = false, error = T('no_permission') } end
    if id == 'clear' then Market.Clear() else Market.Start(id ~= 'random' and id or nil) end
    Webhooks.Send('admin', 'Market changed by admin', ('%s → %s'):format(Webhooks.Who(src), tostring(id)))
    return dashboard()
end)

-- ---------------------------------------------------------------------------
-- Registration papers (ox_inventory / qb-inventory item with metadata)
-- ---------------------------------------------------------------------------

function GiveRegistrationPapers(src, d, v, plate, plan)
    local P = Config.Papers
    if not P or not P.enabled then return end
    local owner = Bridge.GetName(src)
    local metadata = {
        plate = plate, model = v.model, vehicle = v.label, owner = owner, dealership = d.label,
        date = os.date('%Y-%m-%d'), financed = plan ~= nil,
        description = ('%s · Plate %s\nOwner: %s\nSold by %s on %s%s'):format(
            v.label, plate, owner, d.label, os.date('%Y-%m-%d'), plan and '\nFinanced' or ''),
    }
    if not Bridge.GiveItem(src, P.item, metadata) and P.warnMissing then
        print(('[gen_dealership] could not give "%s" — add the item to your inventory resource or disable Config.Papers'):format(P.item))
    end
end
