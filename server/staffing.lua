-- Staff shifts (clock in/out), hourly wages, weekly sales targets & leaderboards.
Staffing = {}

local Sim = Config.Simulation
local T = Utils.T
local Shifts = {}   -- [src] = { id, dealershipId, ident, name, started, owed, earned, lastPay, lastAway }

local function now() return os.time() end

--- Monday 00:00 (UTC) of the current week
local function weekStart(t)
    t = t or now()
    return t - ((t - 345600) % 604800)
end
Staffing.WeekStart = weekStart

local function fmtDuration(sec)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    return h > 0 and ('%dh %02dm'):format(h, m) or ('%dm'):format(m)
end

function Staffing.ShiftOf(src) return Shifts[src] end

--- On duty = (clocked in to this dealership, if required) and within the duty radius
function IsStaffOnDuty(src, d)
    if not d.shop then return false end
    if Sim.requireClockIn then
        local sh = Shifts[src]
        if not sh or sh.dealershipId ~= d.id then return false end
    end
    return IsNear(src, d.shop, Sim.dutyRadius)
end

function Staffing.WageOf(dealershipId, ident)
    local s = Biz.Peek(dealershipId)
    if not s or s.owner == ident then return 0 end
    local e = s.employees[ident]
    return e and (e.wage or 0) or 0
end

local function payOwed(src, sh)
    local amount = math.floor(sh.owed)
    if amount <= 0 then return end
    local s = Biz.Peek(sh.dealershipId)
    if not s or not s.owner then sh.owed = 0 return end
    if s.balance < amount then
        Bridge.Notify(src, T('wage_unpaid'), 'error')
        return
    end
    Biz.AddBalance(sh.dealershipId, -amount, 'wage', ('Wages for %s'):format(sh.name), sh.name)
    Bridge.AddMoney(src, 'bank', amount, 'dealership-wage')
    sh.owed = sh.owed - amount
    sh.earned = sh.earned + amount
end

function Staffing.ClockIn(src, d)
    if Shifts[src] then return false, T('already_clocked_in') end
    local ident = Bridge.GetIdentifier(src)
    local sh = { dealershipId = d.id, ident = ident, name = Bridge.GetName(src), started = now(), owed = 0, earned = 0, lastPay = now() }
    Shifts[src] = sh
    sh.id = MySQL.insert.await('INSERT INTO gen_dealership_shifts (dealership_id, identifier, name, started) VALUES (?, ?, ?, ?)',
        { d.id, ident, sh.name, sh.started })
    Biz.Log(d.id, 'shift', 0, ('%s clocked in'):format(sh.name), sh.name)
    return true
end

function Staffing.ClockOut(src, notice)
    local sh = Shifts[src]
    if not sh then return false end
    Shifts[src] = nil
    if GetPlayerName(src) then payOwed(src, sh) end
    if sh.id then
        MySQL.update('UPDATE gen_dealership_shifts SET ended = ?, earned = ? WHERE id = ?', { now(), sh.earned, sh.id })
    end
    Biz.Log(sh.dealershipId, 'shift', 0, ('%s clocked out after %s (earned %s)'):format(sh.name, fmtDuration(now() - sh.started), Utils.FormatMoney(sh.earned)), sh.name)
    if notice and GetPlayerName(src) then Bridge.Notify(src, notice, 'primary') end
    return true
end

--- Clock out staff of a dealership (all, or only the given identifiers set)
function Staffing.ClockOutAt(dealershipId, idents)
    local list = {}
    for src, sh in pairs(Shifts) do
        if sh.dealershipId == dealershipId and (not idents or idents[sh.ident]) then list[#list + 1] = src end
    end
    for _, src in ipairs(list) do Staffing.ClockOut(src, T('clocked_out_auto')) end
end

function Staffing.RecentShifts(dealershipId)
    local rows = MySQL.query.await('SELECT name, started, ended, earned FROM gen_dealership_shifts WHERE dealership_id = ? ORDER BY id DESC LIMIT 15',
        { dealershipId }) or {}
    for _, r in ipairs(rows) do
        r.duration = ((r.ended and r.ended > 0) and r.ended or now()) - r.started
        r.active = not r.ended or r.ended == 0
    end
    return rows
end

-- Wages accrue per minute while on duty; paid out every Sim.wagePayInterval and on clock-out
CreateThread(function()
    while true do
        Wait(60000)
        local list = {}
        for src in pairs(Shifts) do list[#list + 1] = src end
        for _, src in ipairs(list) do
            local sh = Shifts[src]
            local d = sh and GetDealershipById(sh.dealershipId)
            if sh then
                if not d or not Biz.IsOwned(sh.dealershipId) or not GetPlayerName(src) then
                    Staffing.ClockOut(src)
                elseif IsNear(src, d.shop, Sim.dutyRadius) then
                    sh.lastAway = nil
                    sh.owed = sh.owed + Staffing.WageOf(sh.dealershipId, sh.ident) / 60.0
                    if now() - sh.lastPay >= Sim.wagePayInterval then
                        sh.lastPay = now()
                        payOwed(src, sh)
                    end
                else
                    sh.lastAway = sh.lastAway or now()
                    if now() - sh.lastAway >= Sim.autoClockOut then
                        Staffing.ClockOut(src, T('clocked_out_away'))
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    if Shifts[source] then Staffing.ClockOut(source) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src, sh in pairs(Shifts) do
        if sh.id then MySQL.update('UPDATE gen_dealership_shifts SET ended = ?, earned = ? WHERE id = ?', { now(), sh.earned, sh.id }) end
    end
end)

-- ---------------------------------------------------------------------------
-- Weekly targets & leaderboards
-- ---------------------------------------------------------------------------

local function nameFor(s, ident)
    if s.owner == ident then return s.ownerName end
    local e = s.employees[ident]
    return e and e.name or 'Former staff'
end

function Staffing.Leaderboard(d, myIdent)
    local s = Biz.Peek(d.id)
    if not s then return {} end
    local rows = MySQL.query.await([[
        SELECT seller, COUNT(*) AS c, COALESCE(SUM(price), 0) AS r FROM gen_dealership_sales
        WHERE dealership = ? AND seller <> '' AND sold_at >= FROM_UNIXTIME(?)
        GROUP BY seller ORDER BY r DESC LIMIT 10
    ]], { d.name, weekStart() }) or {}
    local list = {}
    for _, r in ipairs(rows) do
        list[#list + 1] = { name = nameFor(s, r.seller), count = r.c, revenue = tonumber(r.r) or 0, me = r.seller == myIdent }
    end
    return list
end

function Staffing.Rank(d)
    local rows = MySQL.query.await([[
        SELECT dealership, COALESCE(SUM(price), 0) AS r FROM gen_dealership_sales
        WHERE sold_at >= FROM_UNIXTIME(?) GROUP BY dealership ORDER BY r DESC
    ]], { weekStart() }) or {}
    for i, r in ipairs(rows) do
        if r.dealership == d.name then return { rank = i, of = math.max(#rows, #GetAllDealerships()) } end
    end
    return { rank = nil, of = #GetAllDealerships() }
end

function Staffing.WeeklyCount(d, ident)
    return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM gen_dealership_sales WHERE dealership = ? AND seller = ? AND sold_at >= FROM_UNIXTIME(?)',
        { d.name, ident, weekStart() })) or 0
end

--- Called after every staff-closed sale (player offer or walk-in) to pay the weekly target bonus.
function OnStaffSale(d, sellerIdent)
    local s = Biz.Peek(d.id)
    if not s or not s.owner or s.owner == sellerIdent then return end
    if (s.targetCount or 0) <= 0 or (s.targetBonus or 0) <= 0 then return end
    if Staffing.WeeklyCount(d, sellerIdent) < s.targetCount then return end

    local inserted = MySQL.insert.await('INSERT IGNORE INTO gen_dealership_bonuses (dealership_id, identifier, week) VALUES (?, ?, ?)',
        { d.id, sellerIdent, weekStart() })
    if not inserted or inserted == 0 then return end -- already paid this week

    local name = nameFor(s, sellerIdent)
    if s.balance < s.targetBonus then
        Biz.NotifyManagers(d.id, T('bonus_unpaid', name), 'error')
        return
    end
    Biz.AddBalance(d.id, -s.targetBonus, 'bonus', ('Weekly target bonus: %s (%d sales)'):format(name, s.targetCount), name)
    local src = Biz.OnlineMap()[sellerIdent]
    if src then
        Bridge.AddMoney(src, 'bank', s.targetBonus, 'dealership-bonus')
        Bridge.Notify(src, T('bonus_paid', Utils.FormatMoney(s.targetBonus), s.targetCount), 'success')
    end
end
