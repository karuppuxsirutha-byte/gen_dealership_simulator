-- Logistics job (client): depot board, hauling shipment vehicles, drop-off.
local L = Config.Logistics
if not L.enabled then return end

local T = Utils.T
local depotBlip
local Haul = nil   -- { id, vehicle, plate, drop, blip, deadline, label, dealership }

local function mayUseDepot()
    if not L.job or L.job == '' then return true end
    if Bridge.GetJob() == L.job then return true end
    return L.staffCanDeliver and next(State.roles or {}) ~= nil
end

local function refreshDepotBlip()
    local want = mayUseDepot()
    if want and not depotBlip then
        local b = L.depot.board
        depotBlip = AddBlipForCoord(b.x, b.y, b.z)
        SetBlipSprite(depotBlip, L.depot.blip.sprite)
        SetBlipColour(depotBlip, L.depot.blip.color)
        SetBlipScale(depotBlip, L.depot.blip.scale + 0.0)
        SetBlipAsShortRange(depotBlip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(L.depot.label .. ' (Logistics)')
        EndTextCommandSetBlipName(depotBlip)
    elseif not want and depotBlip then
        RemoveBlip(depotBlip)
        depotBlip = nil
    end
end

CreateThread(function()
    while true do
        refreshDepotBlip()
        Wait(10000)
    end
end)

local function drawStatus(text)
    SetTextScale(0.42, 0.42)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.93)
end

local function fmtTime(sec)
    sec = math.max(0, math.floor(sec))
    return ('%d:%02d'):format(sec // 60, sec % 60)
end

-- ---------------------------------------------------------------------------
-- Haul lifecycle
-- ---------------------------------------------------------------------------

local function clearHaul()
    if not Haul then return end
    if Haul.blip and DoesBlipExist(Haul.blip) then
        SetBlipRoute(Haul.blip, false)
        RemoveBlip(Haul.blip)
    end
    Haul = nil
end

RegisterNetEvent('gen_dealership:logistics:ended', function()
    clearHaul()
end)

local function startHaul(res, spawn)
    DoScreenFadeOut(300)
    Wait(350)
    local veh = SpawnPlayerVehicle(res.model, spawn, res.plate)
    DoScreenFadeIn(400)
    if not veh then
        TriggerCallback('logistics:cancel')
        Bridge.Notify(T('haul_failed', 'could not load the vehicle model.'), 'error')
        return
    end
    TriggerServerEvent('gen_dealership:logistics:spawned', res.id, NetworkGetNetworkIdFromEntity(veh))

    local blip = AddBlipForCoord(res.drop.x + 0.0, res.drop.y + 0.0, res.drop.z + 0.0)
    SetBlipSprite(blip, 524)
    SetBlipColour(blip, 5)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Drop-off: ' .. res.dealership)
    EndTextCommandSetBlipName(blip)

    Haul = {
        id = res.id, vehicle = veh, plate = res.plate, label = res.label, dealership = res.dealership,
        drop = vector3(res.drop.x + 0.0, res.drop.y + 0.0, res.drop.z + 0.0),
        deadline = GetGameTimer() + res.timeLimit * 1000,
        blip = blip,
    }
    Bridge.Notify(('Deliver the %s to %s. Pay: %s (less any damage).'):format(res.label, res.dealership, Utils.FormatMoney(res.payout)), 'primary')
end

CreateThread(function()
    while true do
        local sleep = 500
        if Haul then
            sleep = 0
            local left = (Haul.deadline - GetGameTimer()) / 1000
            drawStatus(T('haul_status', Haul.label, Haul.dealership, fmtTime(left)))

            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local dist = #(pos - Haul.drop)
            if dist < 60.0 then
                DrawMarker(1, Haul.drop.x, Haul.drop.y, Haul.drop.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    L.dropRadius * 2.0, L.dropRadius * 2.0, 0.6, 245, 185, 66, 110, false, false, 2, false, nil, nil, false)
            end
            if dist < L.dropRadius and GetVehiclePedIsIn(ped, false) == Haul.vehicle and not UIBusy() then
                ShowHelp(T('deliver_vehicle'))
                if IsControlJustReleased(0, Config.InteractKey) then
                    local h = Haul
                    local res = TriggerCallback('logistics:deliver', h.id)
                    if res and res.ok then
                        clearHaul()
                        Bridge.Notify(T('haul_paid', res.label, res.condition, res.payoutText), 'success')
                    else
                        Bridge.Notify(res and res.error or 'No response from server.', 'error')
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ---------------------------------------------------------------------------
-- Depot board
-- ---------------------------------------------------------------------------

local function openBoard()
    local res = TriggerCallback('logistics:board')
    if not res or not res.ok then
        Bridge.Notify(res and res.error or 'No response from server.', 'error')
        return
    end
    State.logisticsOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openLogistics', data = res, currency = Config.Currency })
end

CreateThread(function()
    local b = L.depot.board
    local point = vector3(b.x, b.y, b.z)
    while true do
        local sleep = 750
        if not UIBusy() and depotBlip then
            local dist = #(GetEntityCoords(PlayerPedId()) - point)
            if dist < 20.0 then
                sleep = 0
                DrawMarker(39, b.x, b.y, b.z + 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.8, 0.8, 0.8,
                    245, 185, 66, 190, true, true, 2, false, nil, nil, false)
                if dist < Config.InteractDistance then
                    ShowHelp(T('open_logistics'))
                    if IsControlJustReleased(0, Config.InteractKey) then openBoard() end
                end
            end
        end
        Wait(sleep)
    end
end)

RegisterNUICallback('logiAccept', function(data, cb)
    local spawn
    for _, s in ipairs(L.depot.spawns) do
        if not SpotBlocked(s) then spawn = s break end
    end
    if not spawn then return cb({ ok = false, error = 'All loading bays are blocked. Clear one and try again.' }) end

    local res = TriggerCallback('logistics:accept', data.id)
    cb(res or { ok = false, error = 'No response from server.' })
    if res and res.ok then
        CloseUI()
        startHaul(res, spawn)
    end
end)

RegisterNUICallback('logiCancel', function(_, cb)
    local res = TriggerCallback('logistics:cancel')
    cb(res or { ok = false, error = 'No response from server.' })
    if res and res.ok then clearHaul() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearHaul()
    if depotBlip then RemoveBlip(depotBlip) end
end)
