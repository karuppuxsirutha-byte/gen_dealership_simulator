-- Discord webhook logging.
Webhooks = {}

local COLORS = { info = 3901439, good = 3066993, warn = 16098851, bad = 15158332 }

--- @param channel string key in ServerConfig.Webhooks
--- @param fields table|nil array of { name, value, inline }
function Webhooks.Send(channel, title, description, fields, color)
    local cfg = ServerConfig.Webhooks or {}
    local url = cfg[channel]
    if not url or url == '' then url = cfg.default end
    if not url or url == '' then return end

    local embed = {
        title = title,
        description = description,
        color = COLORS[color] or color or COLORS.info,
        fields = fields,
        footer = { text = ('%s · %s'):format(GetCurrentResourceName(), GetConvar('sv_projectName', GetConvar('sv_hostname', 'FiveM'))) },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
    PerformHttpRequest(url, function(status)
        if status and status >= 400 then
            print(('[gen_dealership] webhook "%s" failed with HTTP %s'):format(channel, status))
        end
    end, 'POST', json.encode({ username = cfg.username or 'Dealership', embeds = { embed } }), { ['Content-Type'] = 'application/json' })
end

--- Shorthand for "Name (server id)" in log fields.
function Webhooks.Who(src)
    if not src or src == 0 then return 'Console' end
    return ('%s (#%s)'):format(Bridge.GetName(src), src)
end

function Webhooks.Field(name, value, inline)
    return { name = name, value = tostring(value), inline = inline ~= false }
end
