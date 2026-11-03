local pending = {}
local nextId = 0

--- Yields until the server answers (or 15s timeout -> nil).
function TriggerCallback(name, ...)
    nextId = nextId + 1
    local id = nextId
    local p = promise.new()
    pending[id] = p
    TriggerServerEvent('gen_dealership:cb:req', name, id, ...)
    SetTimeout(15000, function()
        if pending[id] then
            pending[id] = nil
            p:resolve(nil)
        end
    end)
    return Citizen.Await(p)
end

RegisterNetEvent('gen_dealership:cb:res', function(id, result)
    local p = pending[id]
    if p then
        pending[id] = nil
        p:resolve(result)
    end
end)
