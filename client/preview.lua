-- 3D vehicle preview (orbit camera + paint), trade-ins and /financing.
local T = Utils.T

local P = nil   -- active preview { veh, cam, model, center, angle, pitch, dist, minDist, maxDist, lastInput }

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local function placeCam()
    if not P then return end
    local yaw, pitch = math.rad(P.angle), math.rad(P.pitch)
    local x = P.center.x + math.cos(yaw) * math.cos(pitch) * P.dist
    local y = P.center.y + math.sin(yaw) * math.cos(pitch) * P.dist
    local z = P.center.z + math.sin(pitch) * P.dist
    SetCamCoord(P.cam, x, y, z)
    PointCamAtCoord(P.cam, P.center.x, P.center.y, P.center.z)
end

function StopPreview()
    if not P then return end
    local p = P
    P = nil
    RenderScriptCams(false, true, 400, true, true)
    DestroyCam(p.cam, false)
    if DoesEntityExist(p.veh) then DeleteEntity(p.veh) end
    ClearFocus()
    DisplayRadar(true)
end

local function applyColors(veh, c1, c2)
    c1, c2 = tonumber(c1), tonumber(c2)
    if not c1 then return end
    SetVehicleColours(veh, c1, c2 or c1)
end

RegisterNUICallback('previewStart', function(data, cb)
    if not Config.Preview.enabled then return cb({ ok = false, error = T('preview_disabled') }) end
    local d = State.shopId and FindDealership(State.shopId)
    local point = d and (d.preview or d.spawn)
    if not point then return cb({ ok = false, error = T('preview_disabled') }) end

    local model = type(data.model) == 'string' and data.model or ''
    if P and P.model == model then
        applyColors(P.veh, data.color1, data.color2)
        return cb({ ok = true })
    end

    local hash = LoadVehicleModel(model)
    if not hash then return cb({ ok = false, error = T('vehicle_not_found') }) end
    if P and DoesEntityExist(P.veh) then DeleteEntity(P.veh) end

    SetFocusPosAndVel(point.x + 0.0, point.y + 0.0, point.z + 0.0, 0.0, 0.0, 0.0)
    local veh = CreateVehicle(hash, point.x + 0.0, point.y + 0.0, point.z + 0.0, point.w + 0.0, false, false)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    FreezeEntityPosition(veh, true)
    SetEntityInvincible(veh, true)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleNumberPlateText(veh, 'PREVIEW')
    SetVehicleDoorsLocked(veh, 2)
    applyColors(veh, data.color1, data.color2)
    if data.condition and tonumber(data.condition) < 100 then
        SetVehicleDirtLevel(veh, (100 - tonumber(data.condition)) / 10.0)
    end
    SetModelAsNoLongerNeeded(hash)

    local min, max = GetModelDimensions(hash)
    local size = #(max - min)
    local pos = GetEntityCoords(veh)

    if not P then
        local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamFov(cam, 40.0)
        RenderScriptCams(true, true, 600, true, true)
        DisplayRadar(false)
        P = { cam = cam, angle = point.w + 140.0, pitch = 10.0 }
    end
    P.veh, P.model = veh, model
    P.center = vector3(pos.x, pos.y, pos.z + (max.z - min.z) * 0.1)
    P.minDist, P.maxDist = size * 0.55 + 1.0, size * 1.6 + 4.0
    P.dist = size * 0.95 + 1.5
    P.lastInput = 0
    placeCam()
    cb({ ok = true })
end)

RegisterNUICallback('previewCam', function(data, cb)
    if P then
        P.angle = P.angle - (tonumber(data.dx) or 0) * 0.35
        P.pitch = clamp(P.pitch + (tonumber(data.dy) or 0) * 0.2, -4.0, 60.0)
        P.dist = clamp(P.dist + (tonumber(data.zoom) or 0) * 0.004 * P.dist, P.minDist, P.maxDist)
        P.lastInput = GetGameTimer()
        placeCam()
    end
    cb('ok')
end)

RegisterNUICallback('previewColor', function(data, cb)
    if P then applyColors(P.veh, data.color1, data.color2) end
    cb('ok')
end)

RegisterNUICallback('previewStop', function(_, cb)
    StopPreview()
    cb('ok')
end)

-- Slow turntable spin while the viewer isn't dragging
CreateThread(function()
    while true do
        if P then
            HideHudAndRadarThisFrame()
            if GetGameTimer() - P.lastInput > 2500 then
                P.angle = P.angle + 0.12
                placeCam()
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Trade-ins
-- ---------------------------------------------------------------------------

RegisterNUICallback('tradeQuote', function(_, cb)
    if not State.shopId then return cb({ ok = false, error = T('vehicle_not_found') }) end
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then veh = GetVehiclePedIsIn(ped, true) end
    if veh == 0 or not DoesEntityExist(veh) or #(GetEntityCoords(veh) - GetEntityCoords(ped)) > Config.TradeIn.radius
        or not NetworkGetEntityIsNetworked(veh) then
        return cb({ ok = false, error = T('tradein_no_vehicle') })
    end
    cb(TriggerCallback('tradein:quote', State.shopId, NetworkGetNetworkIdFromEntity(veh)) or { ok = false, error = 'No response from server.' })
end)

RegisterNUICallback('tradeAccept', function(_, cb)
    local res = TriggerCallback('tradein:accept')
    cb(res or { ok = false, error = 'No response from server.' })
    if res and res.ok then Bridge.Notify(res.message, 'success') end
end)

-- ---------------------------------------------------------------------------
-- /financing
-- ---------------------------------------------------------------------------

if Config.Finance.enabled then
    RegisterCommand(Config.Finance.command, function()
        if UIBusy() then return end
        local res = TriggerCallback('finance:list')
        if not res or not res.ok then return end
        if #res.contracts == 0 then
            Bridge.Notify(T('finance_none'), 'primary')
            return
        end
        State.financeOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openFinance', data = res, currency = Config.Currency })
    end, false)

    CreateThread(function()
        TriggerEvent('chat:addSuggestion', '/' .. Config.Finance.command, 'View and pay your vehicle finance contracts')
    end)
end

RegisterNUICallback('financePay', function(data, cb)
    cb(TriggerCallback('finance:pay', data.id, data.full == true) or { ok = false, error = 'No response from server.' })
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then StopPreview() end
end)
