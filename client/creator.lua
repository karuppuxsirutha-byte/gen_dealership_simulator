-- In-game dealership creator (admin only; every action is re-validated server-side).
local T = Utils.T

local CONTROLS_TO_DISABLE = { 14, 15, 16, 17, 24, 25, 37, 44, 47, 140, 141, 142, 174, 175, 177, 200, 241, 242, 257, 263 }

local function openCreator(list)
    if State.shopOpen or State.testDrive then return end
    State.creatorOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openCreator',
        dealerships = list or State.dealerships,
        categories = Config.Categories,
        defaults = { blip = Config.DefaultBlip, previewModel = Config.Placement.previewModel },
        limits = { maxDisplays = Config.MaxDisplaySpots, maxVehicles = Config.MaxVehiclesPerDealership },
        currency = Config.Currency,
    })
end

RegisterNetEvent('gen_dealership:creator:open', openCreator)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/' .. Config.CreatorCommand, 'Open the vehicle dealership creator')
end)

-- ---------------------------------------------------------------------------
-- Placement tool
-- ---------------------------------------------------------------------------

local function rotationToDirection(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local n = math.abs(math.cos(x))
    return vector3(-math.sin(z) * n, math.cos(z) * n, math.sin(x))
end

local function raycast(distance, ignore)
    local from = GetGameplayCamCoord()
    local to = from + rotationToDirection(GetGameplayCamRot(2)) * distance
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 1 | 16, ignore, 4)
    local _, hit, coords = GetShapeTestResult(handle)
    return hit == true or hit == 1, coords
end

--- Lets the admin pick a position + heading in the world.
--- @param kind string 'shop' | 'spawn' | 'testdrive' | 'display'
--- @param model string|nil vehicle model for the ghost preview
--- @return table|nil { x, y, z, w }
local function runPlacement(kind, model)
    State.placing = true
    local ped = PlayerPedId()
    local useVehicle = kind ~= 'shop'
    local ghost, hash

    if useVehicle then
        hash = (model and LoadVehicleModel(model)) or LoadVehicleModel(Config.Placement.previewModel)
        if hash then
            local p = GetEntityCoords(ped)
            ghost = CreateVehicle(hash, p.x, p.y, p.z - 50.0, 0.0, false, false)
            SetEntityAlpha(ghost, 170, false)
            SetEntityCollision(ghost, false, false)
            FreezeEntityPosition(ghost, true)
            SetEntityInvincible(ghost, true)
            SetVehicleDoorsLocked(ghost, 2)
        end
    end

    local heading = GetEntityHeading(ped)
    local result

    while true do
        Wait(0)
        for _, c in ipairs(CONTROLS_TO_DISABLE) do DisableControlAction(0, c, true) end

        local fast = IsControlPressed(0, 21)
        if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 241) then
            heading = heading + (fast and 15.0 or 5.0)
        elseif IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 242) then
            heading = heading - (fast and 15.0 or 5.0)
        end
        if IsDisabledControlPressed(0, 174) then heading = heading + (fast and 3.0 or 1.0) end
        if IsDisabledControlPressed(0, 175) then heading = heading - (fast and 3.0 or 1.0) end
        heading = heading % 360.0

        local hit, coords = raycast(Config.Placement.distance, ped)

        if hit then
            if ghost then
                SetEntityCoordsNoOffset(ghost, coords.x, coords.y, coords.z + 0.5, false, false, false)
                SetEntityHeading(ghost, heading)
                SetVehicleOnGroundProperly(ghost)
            else
                DrawMarker(1, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    1.2, 1.2, 0.6, 30, 144, 255, 140, false, false, 2, false, nil, nil, false)
                local fwd = vector3(-math.sin(math.rad(heading)), math.cos(math.rad(heading)), 0.0)
                local tip = coords + fwd * 1.2
                DrawLine(coords.x, coords.y, coords.z + 0.1, tip.x, tip.y, tip.z + 0.1, 255, 255, 255, 220)
            end
        elseif ghost then
            SetEntityCoordsNoOffset(ghost, 0.0, 0.0, -100.0, false, false, false)
        end

        ShowHelp(T('placement_help'))

        if IsDisabledControlJustPressed(0, 38) and hit then
            if ghost then
                local c = GetEntityCoords(ghost)
                result = { x = c.x, y = c.y, z = c.z, w = heading }
            else
                result = { x = coords.x, y = coords.y, z = coords.z, w = heading }
            end
            break
        elseif IsDisabledControlJustPressed(0, 47) then
            local p = GetEntityCoords(ped)
            if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                p = GetEntityCoords(veh)
                result = { x = p.x, y = p.y, z = p.z, w = GetEntityHeading(veh) }
            else
                local found, groundZ = GetGroundZFor_3dCoord(p.x, p.y, p.z, false)
                result = { x = p.x, y = p.y, z = found and groundZ or (p.z - 1.0), w = GetEntityHeading(ped) }
            end
            break
        elseif IsDisabledControlJustPressed(0, 177) then
            break
        end
    end

    if ghost and DoesEntityExist(ghost) then DeleteEntity(ghost) end
    if hash then SetModelAsNoLongerNeeded(hash) end

    -- keep ESC / backspace from opening the pause menu on the frame we exit
    for _ = 1, 10 do
        DisableControlAction(0, 200, true)
        DisableControlAction(0, 177, true)
        Wait(0)
    end

    State.placing = false
    return result
end

-- ---------------------------------------------------------------------------
-- NUI callbacks
-- ---------------------------------------------------------------------------

RegisterNUICallback('creatorPlace', function(data, cb)
    cb({ ok = true })
    if State.placing then return end
    CreateThread(function()
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'hide' })
        local result = runPlacement(data.kind, data.model)
        SendNUIMessage({ action = 'placementResult', kind = data.kind, index = data.index, coords = result })
        if State.creatorOpen then SetNuiFocus(true, true) end
    end)
end)

RegisterNUICallback('creatorTeleport', function(data, cb)
    local c = data.coords
    if Utils.IsVec4(c) then
        local ped = PlayerPedId()
        SetEntityCoords(ped, c.x + 0.0, c.y + 0.0, c.z + 0.5, false, false, false, false)
        SetEntityHeading(ped, c.w + 0.0)
    end
    cb({ ok = true })
end)

RegisterNUICallback('creatorValidate', function(data, cb)
    local model = type(data.model) == 'string' and data.model:lower() or ''
    if not Utils.ValidModelName(model) then return cb({ valid = false }) end
    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return cb({ valid = false }) end

    local display = GetDisplayNameFromVehicleModel(hash)
    local label = GetLabelText(display)
    if not label or label == 'NULL' then label = display ~= 'CARNOTFOUND' and display or model end
    local make = GetLabelText(GetMakeNameFromVehicleModel(hash))
    if make and make ~= 'NULL' and make ~= '' then label = make .. ' ' .. label end

    cb({
        valid = true,
        model = model,
        label = label,
        category = Config.ClassCategories[GetVehicleClassFromName(hash)] or 'other',
    })
end)

RegisterNUICallback('creatorSave', function(data, cb)
    cb(TriggerCallback('creator:save', data) or { ok = false, error = 'No response from server.' })
end)

RegisterNUICallback('creatorDelete', function(data, cb)
    cb(TriggerCallback('creator:delete', data.id) or { ok = false, error = 'No response from server.' })
end)

-- ---------------------------------------------------------------------------
-- Admin dashboard (/dealeradmin)
-- ---------------------------------------------------------------------------

RegisterNetEvent('gen_dealership:admin:open', function(data)
    if UIBusy() then return end
    State.adminOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openAdmin', data = data, currency = Config.Currency })
end)

RegisterNUICallback('adminRefresh', function(_, cb)
    cb(TriggerCallback('admin:dashboard') or { ok = false, error = 'No response from server.' })
end)

RegisterNUICallback('adminMarket', function(data, cb)
    cb(TriggerCallback('admin:market', data.id) or { ok = false, error = 'No response from server.' })
end)

RegisterNUICallback('adminCreator', function(_, cb)
    cb('ok')
    CloseUI()
    ExecuteCommand(Config.CreatorCommand)
end)

RegisterNUICallback('creatorResetOwner', function(data, cb)
    cb(TriggerCallback('creator:resetOwner', data.id) or { ok = false, error = 'No response from server.' })
end)
