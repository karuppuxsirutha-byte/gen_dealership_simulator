-- Logistics job (client): depot board, single & carrier hauls, hijack ambushes, drop-off.
local L = Config.Logistics
if not L.enabled then return end

local T = Utils.T
local depotBlip
local Haul = nil     -- { id, kind, vehicle, trailer, drop, dropRadius, blip, deadline, label, dealership, hijack }
local Ambush = nil   -- { vehicle, peds, blip, started }

local function mayUseDepot()
    if not L.job or L.job == '' then return true end
    if Bridge.GetJob() == L.job then return true end
    if L.company and L.company.enabled then return true end -- anyone may visit to buy / work for the company
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

local function loadModel(name)
    local hash = joaat(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

-- ---------------------------------------------------------------------------
-- Hijack ambush
-- ---------------------------------------------------------------------------

local function clearAmbush(hard)
    if not Ambush then return end
    local a = Ambush
    Ambush = nil
    if a.blip and DoesBlipExist(a.blip) then RemoveBlip(a.blip) end
    for _, ped in ipairs(a.peds) do
        if DoesEntityExist(ped) then
            if hard then DeleteEntity(ped) else SetPedAsNoLongerNeeded(ped) end
        end
    end
    if DoesEntityExist(a.vehicle) then
        if hard then DeleteEntity(a.vehicle) else SetVehicleAsNoLongerNeeded(a.vehicle) end
    end
end

local function spawnAmbush(cfg)
    if not Haul or not DoesEntityExist(Haul.vehicle) then return end
    local behind = GetOffsetFromEntityInWorldCoords(Haul.vehicle, 0.0, -90.0, 0.0)
    local found, node, heading = GetClosestVehicleNodeWithHeading(behind.x, behind.y, behind.z, 1, 3.0, 0)
    if not found then node, heading = behind, GetEntityHeading(Haul.vehicle) end

    local carHash = loadModel(cfg.vehicle)
    local pedHash = loadModel(cfg.peds[math.random(#cfg.peds)])
    if not carHash or not pedHash then return end

    local car = CreateVehicle(carHash, node.x, node.y, node.z, heading, true, false)
    local _, group = AddRelationshipGroup('GEN_HIJACKERS')
    SetRelationshipBetweenGroups(5, group, joaat("PLAYER"))
    SetRelationshipBetweenGroups(5, joaat("PLAYER"), group)

    local peds = {}
    for _, seat in ipairs({ -1, 0 }) do
        local ped = CreatePedInsideVehicle(car, 4, pedHash, seat, true, false)
        SetPedRelationshipGroupHash(ped, group)
        GiveWeaponToPed(ped, joaat(cfg.weapon), 250, false, true)
        SetPedCombatAttributes(ped, 2, true)    -- can do drive-bys
        SetPedCombatAttributes(ped, 46, true)   -- always fight
        SetPedAccuracy(ped, 22)
        SetPedKeepTask(ped, true)
        peds[#peds + 1] = ped
    end
    SetDriverAbility(peds[1], 1.0)
    SetDriverAggressiveness(peds[1], 1.0)
    TaskVehicleChase(peds[1], PlayerPedId())
    TaskCombatPed(peds[2], PlayerPedId(), 0, 16)
    SetModelAsNoLongerNeeded(carHash)
    SetModelAsNoLongerNeeded(pedHash)

    local blip = AddBlipForEntity(car)
    SetBlipColour(blip, 1)
    Ambush = { vehicle = car, peds = peds, blip = blip, started = GetGameTimer() }
    Bridge.Notify(T('hijack_warning'), 'error')
end

CreateThread(function()
    while true do
        if Ambush then
            local alive = 0
            for _, ped in ipairs(Ambush.peds) do
                if DoesEntityExist(ped) and not IsEntityDead(ped) then alive = alive + 1 end
            end
            local far = DoesEntityExist(Ambush.vehicle) and #(GetEntityCoords(Ambush.vehicle) - GetEntityCoords(PlayerPedId())) > 350.0
            if alive == 0 or far or GetGameTimer() - Ambush.started > 240000 then
                clearAmbush(false)
                if Haul then Bridge.Notify(T('hijack_lost'), 'success') end
            end
        end
        Wait(2000)
    end
end)

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
    clearAmbush(false)
end

RegisterNetEvent('gen_dealership:logistics:ended', function()
    clearHaul()
end)

local function startHaul(res, spawn)
    DoScreenFadeOut(300)
    Wait(350)
    local veh = SpawnPlayerVehicle(res.model, spawn, res.plate)
    local trailer
    if veh and res.trailer then
        local hash = loadModel(res.trailer)
        if hash then
            local pos = GetOffsetFromEntityInWorldCoords(veh, 0.0, -11.0, 0.0)
            trailer = CreateVehicle(hash, pos.x, pos.y, pos.z, GetEntityHeading(veh), true, false)
            SetEntityAsMissionEntity(trailer, true, true)
            SetVehicleOnGroundProperly(trailer)
            AttachVehicleToTrailer(veh, trailer, 1.1)
            SetModelAsNoLongerNeeded(hash)
        end
    end
    DoScreenFadeIn(400)
    if not veh or (res.trailer and not trailer) then
        if veh then DeleteEntity(veh) end
        TriggerCallback('logistics:cancel')
        Bridge.Notify(T('haul_failed', 'could not load the vehicle model.'), 'error')
        return
    end
    TriggerServerEvent('gen_dealership:logistics:spawned', res.id, NetworkGetNetworkIdFromEntity(veh),
        trailer and NetworkGetNetworkIdFromEntity(trailer) or nil)

    local blip = AddBlipForCoord(res.drop.x + 0.0, res.drop.y + 0.0, res.drop.z + 0.0)
    SetBlipSprite(blip, 524)
    SetBlipColour(blip, 5)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Drop-off: ' .. res.dealership)
    EndTextCommandSetBlipName(blip)

    Haul = {
        id = res.id, kind = res.kind, vehicle = veh, trailer = trailer, label = res.label, dealership = res.dealership,
        drop = vector3(res.drop.x + 0.0, res.drop.y + 0.0, res.drop.z + 0.0), dropRadius = res.dropRadius,
        deadline = GetGameTimer() + res.timeLimit * 1000, blip = blip,
    }
    Bridge.Notify(('Deliver %s to %s. Pay: %s (less any damage)%s.'):format(res.label, res.dealership,
        Utils.FormatMoney(res.payout), res.insured and ', insured' or ''), 'primary')

    if res.hijack then
        local haulId = res.id
        SetTimeout(res.hijack.delay * 1000, function()
            if Haul and Haul.id == haulId then spawnAmbush(res.hijack) end
        end)
    end
end

CreateThread(function()
    while true do
        local sleep = 500
        if Haul then
            sleep = 0
            local left = (Haul.deadline - GetGameTimer()) / 1000
            drawStatus(T('haul_status', Haul.label, Haul.dealership, fmtTime(left)))

            local ped = PlayerPedId()
            local dist = #(GetEntityCoords(ped) - Haul.drop)
            if dist < 80.0 then
                DrawMarker(1, Haul.drop.x, Haul.drop.y, Haul.drop.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    Haul.dropRadius * 2.0, Haul.dropRadius * 2.0, 0.6, 245, 185, 66, 110, false, false, 2, false, nil, nil, false)
            end
            if dist < Haul.dropRadius and GetVehiclePedIsIn(ped, false) == Haul.vehicle and not UIBusy() then
                ShowHelp(T(Haul.kind == 'carrier' and 'deliver_carrier' or 'deliver_vehicle'))
                if IsControlJustReleased(0, Config.InteractKey) then
                    local res = TriggerCallback('logistics:deliver')
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
OpenLogisticsBoard = openBoard

local function freeSpawn(kind)
    if kind == 'carrier' and L.carrier.spawn then
        return not SpotBlocked(L.carrier.spawn) and L.carrier.spawn or nil
    end
    for _, s in ipairs(L.depot.spawns) do
        if not SpotBlocked(s) then return s end
    end
end

RegisterNUICallback('logiAccept', function(data, cb)
    local spawn = freeSpawn(data.kind)
    if not spawn then return cb({ ok = false, error = 'All loading bays are blocked. Clear one and try again.' }) end

    local res = TriggerCallback('logistics:accept', {
        kind = data.kind, id = data.id, dealershipId = data.dealershipId, insured = data.insured == true,
    })
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

RegisterNUICallback('logiCompany', function(data, cb)
    cb(TriggerCallback('logistics:company', data.action, data.payload or {}) or { ok = false, error = 'No response from server.' })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearHaul()
    clearAmbush(true)
    if depotBlip then RemoveBlip(depotBlip) end
end)
