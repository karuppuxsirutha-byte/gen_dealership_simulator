-- Market events (demand / wholesale cost swings) and dealership advertising.
Market = {}

local M = Config.Market
local T = Utils.T
local current = nil        -- { event, endsAt }
local nextRoll = os.time() + (M.interval or 3600)

local function findEvent(id)
    for _, ev in ipairs(M.events) do
        if ev.id == id then return ev end
    end
end

function Market.Current()
    if current and os.time() < current.endsAt then return current end
    current = nil
    return nil
end

local function affects(ev, category) return not ev.category or ev.category == category end

local function multiplier(field, category)
    local c = Market.Current()
    if c and c.event[field] and affects(c.event, category) then return c.event[field] end
    return 1.0
end

function Market.CostMultiplier(category) return multiplier('cost', category) end
function Market.DemandMultiplier(category) return multiplier('demand', category) end
function Market.BudgetMultiplier(category) return multiplier('budget', category) end

--- Overall AI customer traffic factor
function Market.SpawnFactor()
    local c = Market.Current()
    if not c or not c.event.demand then return 1.0 end
    if c.event.category then return 1.0 + (c.event.demand - 1.0) * 0.3 end
    return c.event.demand
end

local function catLabel(id)
    for _, c in ipairs(Config.Categories) do
        if c.id == id then return c.label end
    end
    return id
end

local function pct(mult) return ('%+d%%'):format(math.floor((mult - 1) * 100 + 0.5)) end

function Market.Effects(ev)
    local scope = ev.category and catLabel(ev.category) or 'All vehicles'
    local out = {}
    if ev.demand then out[#out + 1] = ('%s demand %s'):format(scope, pct(ev.demand)) end
    if ev.budget then out[#out + 1] = ('%s customer budgets %s'):format(scope, pct(ev.budget)) end
    if ev.cost then out[#out + 1] = ('%s wholesale cost %s'):format(scope, pct(ev.cost)) end
    return out
end

function Market.Public()
    local c = Market.Current()
    if not c then return nil end
    return { id = c.event.id, label = c.event.label, description = c.event.description, effects = Market.Effects(c.event), endsIn = c.endsAt - os.time() }
end

local function announce(msg)
    for ident, src in pairs(Biz.OnlineMap()) do
        local roles = Biz.RolesFor(src)
        if next(roles) then Bridge.Notify(src, msg, 'primary') end
    end
end

function Market.Start(id, duration)
    local ev = id and findEvent(id) or M.events[math.random(#M.events)]
    if not ev then return nil end
    current = { event = ev, endsAt = os.time() + (duration or ev.duration or M.duration) }
    announce(T('market_started', ev.label, table.concat(Market.Effects(ev), ', ')))
    Webhooks.Send('admin', ('Market event: %s'):format(ev.label), ev.description, {
        Webhooks.Field('Effects', table.concat(Market.Effects(ev), '\n')),
        Webhooks.Field('Ends', ('<t:%d:R>'):format(current.endsAt)),
    })
    return ev
end

function Market.Clear()
    if current then announce(T('market_ended', current.event.label)) end
    current = nil
end

CreateThread(function()
    while true do
        Wait(60000)
        if M.enabled and not Market.Current() and os.time() >= nextRoll then
            nextRoll = os.time() + M.interval
            if math.random() < M.chance then Market.Start() end
        end
    end
end)

RegisterCommand('dealermarket', function(src, args)
    if src ~= 0 and not Bridge.IsAdmin(src) then return Bridge.Notify(src, T('no_permission'), 'error') end
    local arg = args[1]
    local function reply(msg) if src == 0 then print(msg) else Bridge.Notify(src, msg, 'primary') end end
    if arg == 'clear' then
        Market.Clear()
        reply('Market event cleared.')
    elseif arg == 'list' or not arg then
        local ids = {}
        for _, ev in ipairs(M.events) do ids[#ids + 1] = ev.id end
        local c = Market.Current()
        reply(('Current: %s · Events: %s · Usage: /dealermarket <id|random|clear>'):format(c and c.event.label or 'none', table.concat(ids, ', ')))
    else
        local ev = Market.Start(arg ~= 'random' and arg or nil)
        reply(ev and ('Started market event: %s'):format(ev.label) or 'Unknown event id.')
    end
end, false)

-- ---------------------------------------------------------------------------
-- Advertising
-- ---------------------------------------------------------------------------

function Market.AdBoost(dealershipId)
    local s = Biz.Peek(dealershipId)
    if s and s.adUntil and s.adUntil > os.time() then return (s.adBoost or 0) / 100.0 end
    return 0.0
end

function Market.AdPublic(dealershipId)
    local s = Biz.Peek(dealershipId)
    if s and s.adUntil and s.adUntil > os.time() then
        return { label = s.adLabel, boost = s.adBoost, endsIn = s.adUntil - os.time() }
    end
end

function Market.FindCampaign(id)
    for _, c in ipairs(Config.Advertising.campaigns) do
        if c.id == id then return c end
    end
end
