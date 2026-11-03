local T = Utils.T

-- Shared client state (read by client/creator.lua)
State = {
    dealerships = {},
    shopOpen = false,
    shopId = nil,
    creatorOpen = false,
    placing = false,
    testDrive = nil,
}

local Blips = {}
local Displays = {}      -- [dealershipId] = { [spotIndex] = entity }
local SyncGeneration = 0

-- ---------------------------------------------------------------------------
-- Helpers (global ones are reused by creator.lua)
-- ---------------------------------------------------------------------------

function ToVec3(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end

function LoadVehicleModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then return nil end
        Wait(0)
    end
    return hash
end

function ShowHelp(msg)
    BeginTextCommandDisplayHelp('CELL_EMAIL_BCON')
    for i = 1, #msg, 99 do
        AddTextComponentSubstringPlayerName(msg:sub(i, i + 98))
    end
    EndTextCommandDisplayHelp(0, false, false, -1)
end

local function drawText3D(coords, text)
    local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function drawScreenText(text)
    SetTextScale(0.45, 0.45)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.90)
end

local function canAccess(d)
    if not d.job then return true end
    return Bridge.GetJob() == d.job
end

local function findDealership(id)
    for _, d in ipairs(State.dealerships) do
        if d.id == id then return d end
    end
end

local function findVehicleByModel(d, model)
    for _, v in ipairs(d.vehicles) do
        if v.model == model then return v end
    end
end

local function findVehicleById(d, id)
    for _, v in ipairs(d.vehicles) do
        if v.id == id then return v end
    end
end

-- ---------------------------------------------------------------------------
-- Blips
-- ---------------------------------------------------------------------------

local function refreshBlips()
    for _, b in ipairs(Blips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    Blips = {}

    for _, d in ipairs(State.dealerships) do
        if d.shop and d.blip and d.blip.enabled ~= false and canAccess(d) then
            local b = AddBlipForCoord(d.shop.x + 0.0, d.shop.y + 0.0, d.shop.z + 0.0)
            SetBlipSprite(b, d.blip.sprite or Config.DefaultBlip.sprite)
            SetBlipColour(b, d.blip.color or Config.DefaultBlip.color)
            SetBlipScale(b, (d.blip.scale or Config.DefaultBlip.scale) + 0.0)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(d.label)
            EndTextCommandSetBlipName(b)
            Blips[#Blips + 1] = b
        end
    end
end

function OnJobChanged()
    SetTimeout(500, refreshBlips)
end

-- ---------------------------------------------------------------------------
-- Showroom display vehicles
-- ---------------------------------------------------------------------------

local function deleteDisplays(id)
    local list = Displays[id]
    if not list then return end
    for _, e in pairs(list) do
        if DoesEntityExist(e) then DeleteEntity(e) end
    end
    Displays[id] = nil
end

local function deleteAllDisplays()
    for id in pairs(Displays) do deleteDisplays(id) end
end

local function spawnDisplays(d)
    local list = {}
    Displays[d.id] = list
    local generation = SyncGeneration

    for i, spot in ipairs(d.displays or {}) do
        local hash = LoadVehicleModel(spot.model)
        if generation ~= SyncGeneration or Displays[d.id] ~= list then
            -- data changed while we were loading: discard
            for _, e in pairs(list) do if DoesEntityExist(e) then DeleteEntity(e) end end
            return
        end
        if hash then
            local veh = CreateVehicle(hash, spot.x + 0.0, spot.y + 0.0, spot.z + 0.0, spot.w + 0.0, false, false)
            SetEntityAsMissionEntity(veh, true, true)
            SetVehicleOnGroundProperly(veh)
            FreezeEntityPosition(veh, true)
            SetEntityInvincible(veh, true)
            SetEntityCanBeDamaged(veh, false)
            SetVehicleDoorsLocked(veh, 2)
            SetVehicleDirtLevel(veh, 0.0)
            SetVehicleNumberPlateText(veh, Config.DisplayPlate)
            SetVehicleEngineOn(veh, false, true, true)
            SetModelAsNoLongerNeeded(hash)
            list[i] = veh
        end
    end
end

local function distanceToDealership(pos, d)
    local best = math.huge
    if d.shop then best = #(pos - ToVec3(d.shop)) end
    for _, s in ipairs(d.displays or {}) do
        local dist = #(pos - ToVec3(s))
        if dist < best then best = dist end
    end
    return best
end

CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for _, d in ipairs(State.dealerships) do
            local near = #(d.displays or {}) > 0 and distanceToDealership(pos, d) < Config.DisplayRenderDistance
            if near and not Displays[d.id] then
                spawnDisplays(d)
            elseif not near and Displays[d.id] then
                deleteDisplays(d.id)
            end
        end
        Wait(1000)
    end
end)

-- ---------------------------------------------------------------------------
-- Sync
-- ---------------------------------------------------------------------------

local function applySync(list)
    SyncGeneration = SyncGeneration + 1
    deleteAllDisplays()
    State.dealerships = list or {}
    refreshBlips()

    if State.shopOpen and State.shopId then
        local d = findDealership(State.shopId)
        if d then
            SendNUIMessage({ action = 'shopUpdate', vehicles = d.vehicles })
        else
            CloseUI()
        end
    end
end

RegisterNetEvent('gen_dealership:sync', applySync)

RegisterNetEvent('gen_dealership:notify', function(msg, kind)
    Bridge.Notify(msg, kind)
end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    applySync(TriggerCallback('getDealerships'))
end)

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------

function CloseUI()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    State.shopOpen = false
    State.shopId = nil
    State.creatorOpen = false
end

local function openShop(d)
    local balance = TriggerCallback('shop:balance') or {}
    State.shopOpen = true
    State.shopId = d.id
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openShop',
        dealership = {
            id = d.id,
            label = d.label,
            testDrive = Config.TestDrive.enabled,
            testDriveDuration = Config.TestDrive.duration,
        },
        vehicles = d.vehicles,
        categories = Config.Categories,
        balance = balance,
        payment = Config.PaymentMethods,
        currency = Config.Currency,
    })
end

RegisterNUICallback('close', function(_, cb)
    CloseUI()
    cb('ok')
end)

-- ---------------------------------------------------------------------------
-- Spawning purchased / test drive vehicles
-- ---------------------------------------------------------------------------

local function spawnPlayerVehicle(model, coords, plate)
    local hash = LoadVehicleModel(model)
    if not hash then return nil end

    local veh = CreateVehicle(hash, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, coords.w + 0.0, true, false)
    local timeout = GetGameTimer() + 5000
    while not DoesEntityExist(veh) and GetGameTimer() < timeout do Wait(0) end
    if not DoesEntityExist(veh) then return nil end

    SetVehicleOnGroundProperly(veh)
    SetVehicleNumberPlateText(veh, plate)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    SetVehRadioStation(veh, 'OFF')
    SetVehicleDirtLevel(veh, 0.0)

    local netId = NetworkGetNetworkIdFromEntity(veh)
    SetNetworkIdCanMigrate(netId, true)

    TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    SetVehicleEngineOn(veh, true, true, false)
    Bridge.SetFuel(veh, 100.0)
    Bridge.GiveKeys(veh, plate)
    TriggerServerEvent('gen_dealership:vehicleSpawned', netId, plate)
    SetModelAsNoLongerNeeded(hash)
    return veh
end

local function spotBlocked(coords)
    return IsAnyVehicleNearPoint(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, 3.0)
end

RegisterNUICallback('shopBuy', function(data, cb)
    local d = State.shopId and findDealership(State.shopId)
    if not d or not d.spawn then return cb({ ok = false, error = T('vehicle_not_found') }) end
    if spotBlocked(d.spawn) then return cb({ ok = false, error = T('spawn_blocked') }) end

    local res = TriggerCallback('shop:buy', d.id, data.vehicleId, data.method)
    if not res then return cb({ ok = false, error = 'No response from server.' }) end
    cb(res)
    if not res.ok then return end

    CloseUI()
    DoScreenFadeOut(300)
    Wait(350)
    spawnPlayerVehicle(res.model, d.spawn, res.plate)
    DoScreenFadeIn(400)
    Bridge.Notify(T('purchased', res.label, res.priceText, res.plate), 'success')
end)

local function endTestDrive()
    local td = State.testDrive
    if not td then return end
    State.testDrive = nil

    DoScreenFadeOut(400)
    Wait(450)
    local ped = PlayerPedId()
    SetEntityCoords(ped, td.returnPos.x, td.returnPos.y, td.returnPos.z, false, false, false, false)
    SetEntityHeading(ped, td.returnHeading)
    if DoesEntityExist(td.vehicle) then
        SetEntityAsMissionEntity(td.vehicle, true, true)
        DeleteVehicle(td.vehicle)
    end
    Wait(200)
    DoScreenFadeIn(400)

    TriggerServerEvent('gen_dealership:testdriveEnd')
    Bridge.Notify(T('testdrive_over'), 'primary')
end

RegisterNUICallback('shopTestDrive', function(data, cb)
    local d = State.shopId and findDealership(State.shopId)
    if not d then return cb({ ok = false, error = T('vehicle_not_found') }) end
    local point = d.testdrive or d.spawn
    if not point then return cb({ ok = false, error = T('testdrive_disabled') }) end
    if spotBlocked(point) then return cb({ ok = false, error = T('spawn_blocked') }) end

    local res = TriggerCallback('shop:testdrive', d.id, data.vehicleId)
    if not res then return cb({ ok = false, error = 'No response from server.' }) end
    cb(res)
    if not res.ok then return end

    CloseUI()
    local ped = PlayerPedId()
    local returnPos, returnHeading = GetEntityCoords(ped), GetEntityHeading(ped)

    DoScreenFadeOut(300)
    Wait(350)
    local veh = spawnPlayerVehicle(res.model, point, res.plate)
    DoScreenFadeIn(400)
    if not veh then
        TriggerServerEvent('gen_dealership:testdriveEnd')
        return
    end

    State.testDrive = {
        vehicle = veh,
        endsAt = GetGameTimer() + res.duration * 1000,
        returnPos = returnPos,
        returnHeading = returnHeading,
    }

    CreateThread(function()
        local outSince
        while State.testDrive and State.testDrive.vehicle == veh do
            local remaining = math.ceil((State.testDrive.endsAt - GetGameTimer()) / 1000)
            drawScreenText(T('testdrive_left', math.max(remaining, 0)))

            if GetVehiclePedIsIn(PlayerPedId(), false) ~= veh then
                outSince = outSince or GetGameTimer()
            else
                outSince = nil
            end

            if remaining <= 0
                or (outSince and GetGameTimer() - outSince > 5000)
                or not DoesEntityExist(veh)
                or IsEntityDead(PlayerPedId()) then
                endTestDrive()
                break
            end
            Wait(0)
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- World interaction loop
-- ---------------------------------------------------------------------------

CreateThread(function()
    local m = Config.Marker
    while true do
        local sleep = 750
        if not State.shopOpen and not State.creatorOpen and not State.placing and not State.testDrive then
            local pos = GetEntityCoords(PlayerPedId())

            for _, d in ipairs(State.dealerships) do
                if d.shop and canAccess(d) then
                    local point = ToVec3(d.shop)
                    local dist = #(pos - point)
                    if dist < Config.MarkerDrawDistance then
                        sleep = 0
                        DrawMarker(m.type, point.x, point.y, point.z + 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            m.scale, m.scale, m.scale, m.color[1], m.color[2], m.color[3], m.color[4],
                            true, true, 2, false, nil, nil, false)

                        if dist < Config.InteractDistance then
                            ShowHelp(T('open_shop', d.label))
                            if IsControlJustReleased(0, Config.InteractKey) then
                                openShop(d)
                            end
                        end
                    end
                end

                local list = Displays[d.id]
                if list then
                    for i, veh in pairs(list) do
                        if DoesEntityExist(veh) then
                            local vpos = GetEntityCoords(veh)
                            if #(pos - vpos) < Config.DisplayLabelDistance then
                                sleep = 0
                                local spot = d.displays[i]
                                local info = spot and findVehicleByModel(d, spot.model)
                                if info then
                                    drawText3D(vpos + vector3(0.0, 0.0, 1.3),
                                        ('%s~n~~g~%s'):format(info.label, Utils.FormatMoney(info.price)))
                                end
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ---------------------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    deleteAllDisplays()
    for _, b in ipairs(Blips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    if State.testDrive and DoesEntityExist(State.testDrive.vehicle) then
        DeleteEntity(State.testDrive.vehicle)
    end
    SetNuiFocus(false, false)
end)

-- Expose a few helpers for creator.lua
FindDealership = findDealership
FindVehicleById = findVehicleById
