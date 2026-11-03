-- Vehicle financing: deposit now, instalments taken from the bank while the buyer is online.
Finance = {}

local F = Config.Finance
local T = Utils.T
local Contracts = {}   -- [id] = active contract

local function now() return os.time() end

function Finance.Load()
    Contracts = {}
    for _, r in ipairs(MySQL.query.await("SELECT * FROM gen_dealership_finance WHERE status = 'active'") or {}) do
        Contracts[r.id] = {
            id = r.id, identifier = r.identifier, ownerName = r.owner_name, dealershipId = r.dealership_id,
            dealership = r.dealership, plate = r.plate, model = r.model, label = r.label,
            total = r.total, remaining = r.remaining, payment = r.payment, paymentsLeft = r.payments_left,
            nextDue = r.next_due, missed = r.missed,
        }
    end
end

local function persist(c, status)
    MySQL.update('UPDATE gen_dealership_finance SET remaining = ?, payments_left = ?, next_due = ?, missed = ?, status = ? WHERE id = ?',
        { c.remaining, c.paymentsLeft, c.nextDue, c.missed, status or 'active', c.id })
end

--- Validates a finance request and returns the plan, or nil + error.
--- @param opt table { term = index into Config.Finance.terms, deposit = 0..1 }
function Finance.Plan(price, opt)
    if not F.enabled then return nil, T('finance_disabled') end
    if price < F.minPrice then return nil, T('finance_min_price', Utils.FormatMoney(F.minPrice)) end
    local term = F.terms[tonumber(opt and opt.term) or 0]
    if not term then return nil, T('finance_bad_term') end
    local ratio = tonumber(opt.deposit) or F.minDeposit
    ratio = math.max(F.minDeposit, math.min(0.9, ratio))

    local deposit = math.ceil(price * ratio)
    local financed = price - deposit
    local total = math.floor(financed * (1 + term.interest))
    return {
        deposit = deposit,
        total = total,
        payments = term.payments,
        payment = math.ceil(total / term.payments),
        interest = term.interest,
    }
end

function Finance.HasActive(plate)
    for _, c in pairs(Contracts) do
        if c.plate == plate then return true end
    end
    return false
end

function Finance.Create(src, d, v, plate, plan)
    local c = {
        identifier = Bridge.GetIdentifier(src), ownerName = Bridge.GetName(src),
        dealershipId = d.id, dealership = d.label, plate = plate, model = v.model, label = v.label,
        total = plan.total, remaining = plan.total, payment = plan.payment, paymentsLeft = plan.payments,
        nextDue = now() + F.interval, missed = 0,
    }
    c.id = MySQL.insert.await([[
        INSERT INTO gen_dealership_finance (identifier, owner_name, dealership_id, dealership, plate, model, label, total, remaining, payment, payments_left, next_due)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { c.identifier, c.ownerName, c.dealershipId, c.dealership, plate, v.model, v.label, c.total, c.remaining, c.payment, c.paymentsLeft, c.nextDue })
    Contracts[c.id] = c
    Webhooks.Send('finance', 'Finance contract opened', nil, {
        Webhooks.Field('Buyer', Webhooks.Who(src)),
        Webhooks.Field('Vehicle', ('%s · %s'):format(v.label, plate)),
        Webhooks.Field('Deposit', Utils.FormatMoney(plan.deposit)),
        Webhooks.Field('Financed', ('%s in %d × %s'):format(Utils.FormatMoney(plan.total), plan.payments, Utils.FormatMoney(plan.payment))),
        Webhooks.Field('Dealership', d.label),
    })
end

--- Records a successful payment of `amount` on a contract.
local function applyPayment(c, amount, src, early)
    c.remaining = math.max(0, c.remaining - amount)
    c.paymentsLeft = math.max(0, c.paymentsLeft - 1)
    c.missed = 0
    if not early or c.nextDue < now() then c.nextDue = now() + F.interval end

    if c.dealershipId and Biz.IsOwned(c.dealershipId) then
        Biz.AddBalance(c.dealershipId, amount, 'finance', ('Instalment: %s (%s)'):format(c.label, c.ownerName), c.ownerName)
    end

    if c.remaining <= 0 then
        Contracts[c.id] = nil
        persist(c, 'paid')
        if src then Bridge.Notify(src, T('finance_paid_off', c.label), 'success') end
        Webhooks.Send('finance', 'Finance contract paid off', ('%s · %s · %s'):format(c.ownerName, c.label, c.plate), nil, 'good')
    else
        persist(c)
    end
end

local function repossess(c)
    Contracts[c.id] = nil
    persist(c, 'repossessed')
    Bridge.RemoveVehicle(c.plate)

    local d = c.dealershipId and GetDealershipById(c.dealershipId)
    if d then
        local cat = FindCatalogueByHash(joaat(c.model), d)
        local value = math.floor(((cat and cat.price) or c.total) * Config.TradeIn.ratio)
        UsedLot.Add(d.id, c.model, c.label, cat and cat.category or 'other', value, 85, 'repo')
    end
    Webhooks.Send('finance', 'Vehicle repossessed', nil, {
        Webhooks.Field('Owner', c.ownerName),
        Webhooks.Field('Vehicle', ('%s · %s'):format(c.label, c.plate)),
        Webhooks.Field('Unpaid', Utils.FormatMoney(c.remaining)),
    }, 'bad')
end

CreateThread(function()
    while true do
        Wait(60000)
        if F.enabled then
            local online = Biz.OnlineMap()
            local t = now()
            local ids = {}
            for id in pairs(Contracts) do ids[#ids + 1] = id end
            for _, id in ipairs(ids) do
                local c = Contracts[id]
                local src = c and online[c.identifier]
                if c and src and t >= c.nextDue then
                    local amount = math.min(c.payment, c.remaining)
                    if Bridge.RemoveMoney(src, 'bank', amount, 'vehicle-finance') then
                        Bridge.Notify(src, T('finance_instalment', Utils.FormatMoney(amount), c.label, math.max(0, c.paymentsLeft - 1)), 'primary')
                        applyPayment(c, amount, src, false)
                    else
                        c.missed = c.missed + 1
                        c.nextDue = t + F.interval
                        if c.missed >= F.maxMissed then
                            Bridge.Notify(src, T('finance_repossessed', c.label), 'error')
                            repossess(c)
                        else
                            Bridge.Notify(src, T('finance_missed', c.label, c.missed, F.maxMissed), 'error')
                            persist(c)
                        end
                    end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Player view (/financing)
-- ---------------------------------------------------------------------------

local function listFor(src)
    local ident = Bridge.GetIdentifier(src)
    local list = {}
    for _, c in pairs(Contracts) do
        if c.identifier == ident then
            list[#list + 1] = {
                id = c.id, label = c.label, model = c.model, plate = c.plate, dealership = c.dealership,
                total = c.total, remaining = c.remaining, payment = math.min(c.payment, c.remaining),
                paymentsLeft = c.paymentsLeft, dueIn = math.max(0, c.nextDue - now()), missed = c.missed,
            }
        end
    end
    table.sort(list, function(a, b) return a.dueIn < b.dueIn end)
    return list
end

RegisterCallback('finance:list', function(src)
    return { ok = true, contracts = listFor(src), maxMissed = F.maxMissed, balance = Bridge.GetMoney(src, 'bank') }
end)

RegisterCallback('finance:pay', function(src, id, full)
    local c = Contracts[tonumber(id)]
    if not c or c.identifier ~= Bridge.GetIdentifier(src) then return { ok = false, error = T('finance_not_found') } end
    local amount = full and c.remaining or math.min(c.payment, c.remaining)
    if not Bridge.RemoveMoney(src, 'bank', amount, 'vehicle-finance') then return { ok = false, error = T('not_enough_money') } end
    if full then c.paymentsLeft = 1 end
    applyPayment(c, amount, src, true)
    return { ok = true, contracts = listFor(src), balance = Bridge.GetMoney(src, 'bank'), message = T('finance_payment_ok', Utils.FormatMoney(amount)) }
end)

--- Admin dashboard figures
function Finance.Totals()
    local count, outstanding = 0, 0
    for _, c in pairs(Contracts) do
        count = count + 1
        outstanding = outstanding + c.remaining
    end
    return { count = count, outstanding = outstanding }
end
