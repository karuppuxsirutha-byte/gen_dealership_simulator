Utils = {}

function Utils.T(key, ...)
    local str = Config.Text[key] or key
    if select('#', ...) > 0 then
        return str:format(...)
    end
    return str
end

local function running(name)
    local state = GetResourceState(name)
    return state == 'started' or state == 'starting'
end
Utils.IsRunning = running

function Utils.DetectFramework()
    if Config.Framework and Config.Framework ~= 'auto' then
        return Config.Framework
    end
    if running('qbx_core') then return 'qbx' end
    if running('qb-core') then return 'qb' end
    if running('es_extended') then return 'esx' end
    return 'standalone'
end

function Utils.IsVec4(t)
    return type(t) == 'table'
        and type(tonumber(t.x)) == 'number'
        and type(tonumber(t.y)) == 'number'
        and type(tonumber(t.z)) == 'number'
        and type(tonumber(t.w)) == 'number'
end

function Utils.Round(n, decimals)
    local m = 10 ^ (decimals or 2)
    return math.floor(n * m + 0.5) / m
end

function Utils.FormatMoney(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local formatted = (s:reverse():gsub('(%d%d%d)', '%1,')):reverse()
    formatted = (formatted:gsub('^,', ''))
    return '$' .. formatted
end

function Utils.ValidModelName(model)
    return type(model) == 'string' and #model > 0 and #model <= 32 and model:match('^[%w_%-]+$') ~= nil
end

function Utils.CategoryExists(id)
    for _, c in ipairs(Config.Categories) do
        if c.id == id then return true end
    end
    return false
end
