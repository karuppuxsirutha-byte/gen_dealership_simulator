-- Minimal client -> server request/response helper (no external dependency).
local handlers = {}

function RegisterCallback(name, fn)
    handlers[name] = fn
end

RegisterNetEvent('gen_dealership:cb:req', function(name, requestId, ...)
    local src = source
    local handler = handlers[name]
    if not handler then
        TriggerClientEvent('gen_dealership:cb:res', src, requestId, nil)
        return
    end
    local ok, result = pcall(handler, src, ...)
    if not ok then
        print(('^1[gen_dealership] callback "%s" errored: %s^0'):format(name, result))
        result = { ok = false, error = 'Server error' }
    end
    TriggerClientEvent('gen_dealership:cb:res', src, requestId, result)
end)
