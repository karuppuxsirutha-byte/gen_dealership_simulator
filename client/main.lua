local T = Utils.T

-- Shared client state (read by client/creator.lua)
State = {
    dealerships = {},
    shopOpen = false,
    shopId = nil,
    creatorOpen = false,
    placing = false,
    testDrive = nil,
    roles = {},          -- ["<dealershipId>"] = 'owner' | 'manager' | 'sales'
    manageOpen = false,
    manageId = nil,
    negotiating = false,
    offerOpen = false,
    logisticsOpen = false,
    financeOpen = false,
    adminOpen = false,
}

function UIBusy()
    return State.shopOpen or State.creatorOpen or State.placing or State.testDrive ~= nil
        or State.manageOpen or State.negotiating or State.offerOpen or State.logisticsOpen or State.financeOpen or State.adminOpen
end

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

function DrawText3D(coords, text)
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
    SetTimeout(500, function()
        refreshBlips()
        if RefreshRoles then RefreshRoles() end
    end)
end

-- ---------------------------------------------------------------------------
-- Showroom display vehicles
-- ---------------------------------------------------------------------------

local function deleteDisplays(id)
    local list = Displays[id]
    if not list then return end
    for _, e in pairs(list) do
        if DoesEntityExist(e) then
            if RemoveEntityTarget then RemoveEntityTarget(e) end
            DeleteEntity(e)
        end
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
            if AddDisplayTarget then
                local info = findVehicleByModel(d, spot.model)
                if info then AddDisplayTarget(veh, d, info.id, info.label) end
            end
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
    if RefreshTargets then RefreshTargets() end

    if State.shopOpen and State.shopId then
        local d = findDealership(State.shopId)
        if d then
            SendNUIMessage({ action = 'shopUpdate', vehicles = ShopVehicles(d), categories = shopCategories(d) })
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
    if StopPreview then StopPreview() end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    if State.negotiating then TriggerServerEvent('gen_dealership:customerRelease') end
    State.shopOpen = false
    State.shopId = nil
    State.creatorOpen = false
    State.manageOpen = false
    State.manageId = nil
    State.negotiating = false
    State.offerOpen = false
    State.logisticsOpen = false
    State.financeOpen = false
    State.adminOpen = false
end

--- Catalogue + pre-owned listings as one list for the shop UI
function ShopVehicles(d)
    local list = {}
    for _, v in ipairs(d.vehicles) do list[#list + 1] = v end
    for _, u in ipairs(d.used or {}) do
        list[#list + 1] = {
            id = Utils.USED_OFFSET + u.id, model = u.model, label = u.label, category = 'preowned',
            price = u.price, stock = -1, used = true, condition = u.condition, source = u.source,
        }
    end
    return list
end

local function shopCategories(d)
    local cats = {}
    for _, c in ipairs(Config.Categories) do cats[#cats + 1] = c end
    if d.used and #d.used > 0 then cats[#cats + 1] = { id = 'preowned', label = 'Pre-owned' } end
    return cats
end

local function shopFeatures()
    return {
        preview = Config.Preview.enabled,
        colors = Config.Colors,
        customPlate = Config.CustomPlate,
        finance = Config.Finance.enabled and {
            minPrice = Config.Finance.minPrice, minDeposit = Config.Finance.minDeposit,
            terms = Config.Finance.terms, interval = Config.Finance.interval, maxMissed = Config.Finance.maxMissed,
        } or false,
        tradeIn = Config.TradeIn.enabled,
    }
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
            business = d.business,
            selfService = Config.Simulation.selfService or not (d.business and d.business.owned),
            role = State.roles[tostring(d.id)],
        },
        vehicles = ShopVehicles(d),
        categories = shopCategories(d),
        features = shopFeatures(),
        balance = balance,
        payment = Config.PaymentMethods,
        currency = Config.Currency,
    })
end

RegisterNUICallback('nuiReady', function(_, cb)
    cb(Config.UI)
end)

-- Performance figures for the shop's stat bars (loaded on demand, cached)
local StatCache = {}
RegisterNUICallback('vehicleStats', function(data, cb)
    local model = type(data.model) == 'string' and data.model:lower() or ''
    if StatCache[model] then return cb(StatCache[model]) end
    if not Utils.ValidModelName(model) then return cb({ ok = false }) end

    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return cb({ ok = false }) end
    local loadedHere = false
    if not HasModelLoaded(hash) then
        RequestModel(hash)
        local timeout = GetGameTimer() + 3000
        while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
        loadedHere = true
    end

    local stats = {
        ok = true,
        speed = GetVehicleModelEstimatedMaxSpeed(hash),   -- m/s
        accel = GetVehicleModelAcceleration(hash),
        braking = GetVehicleModelMaxBraking(hash),
        traction = GetVehicleModelMaxTraction(hash),
        seats = GetVehicleModelNumberOfSeats(hash),
    }
    if loadedHere then SetModelAsNoLongerNeeded(hash) end
    StatCache[model] = stats
    cb(stats)
end)

RegisterNUICallback('close', function(_, cb)
    CloseUI()
    cb('ok')
end)

-- ---------------------------------------------------------------------------
-- Spawning purchased / test drive vehicles
-- ---------------------------------------------------------------------------

--- @param extra table|nil { props = { color1, color2 }, condition = 0-100 }
function SpawnPlayerVehicle(model, coords, plate, extra)
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
    if extra then
        local props = extra.props
        if props and props.color1 then SetVehicleColours(veh, props.color1, props.color2 or props.color1) end
        if extra.condition and extra.condition < 100 then
            local health = math.max(300.0, extra.condition * 10.0)
            SetVehicleBodyHealth(veh, health)
            SetVehicleEngineHealth(veh, health)
            SetVehicleDirtLevel(veh, (100 - extra.condition) / 10.0)
        end
    end

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

function SpotBlocked(coords)
    return IsAnyVehicleNearPoint(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, 3.0)
end

RegisterNUICallback('shopBuy', function(data, cb)
    local d = State.shopId and findDealership(State.shopId)
    if not d or not d.spawn then return cb({ ok = false, error = T('vehicle_not_found') }) end
    if SpotBlocked(d.spawn) then return cb({ ok = false, error = T('spawn_blocked') }) end

    local res = TriggerCallback('shop:buy', d.id, data.vehicleId, data.method, data.options or {})
    if not res then return cb({ ok = false, error = 'No response from server.' }) end
    cb(res)
    if not res.ok then return end

    CloseUI()
    DoScreenFadeOut(300)
    Wait(350)
    SpawnPlayerVehicle(res.model, d.spawn, res.plate, { props = res.props, condition = res.condition })
    DoScreenFadeIn(400)
    Bridge.Notify(T('purchased', res.label, res.priceText, res.plate), 'success')
    if res.financed then Bridge.Notify(T('finance_started', Config.Finance.command), 'primary') end
end)

RegisterNUICallback('shopBuyBusiness', function(data, cb)
    local res = TriggerCallback('biz:buyBusiness', State.shopId, data.method)
    cb(res or { ok = false, error = 'No response from server.' })
    if res and res.ok then
        CloseUI()
        Bridge.Notify(res.message, 'success')
    end
end)

-- ---------------------------------------------------------------------------
-- Test drives
-- ---------------------------------------------------------------------------

local TD = Config.TestDrive

local function endTestDrive(reason)
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
    TriggerServerEvent('gen_dealership:testdriveEnd')
    Wait(300) -- give the server a moment to move us back to the public instance
    DoScreenFadeIn(400)

    Bridge.Notify(reason or T('testdrive_over'), 'primary')
end

local function testDriveHud(remaining, km, maxKm, warn)
    local text = T('testdrive_hud', ('%d:%02d'):format(remaining // 60, remaining % 60))
    if maxKm then
        text = text .. ('  ·  %s%.1f / %.1f km~s~'):format(warn and '~r~' or '', km, maxKm)
    end
    SetTextScale(0.42, 0.42)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text .. '~n~' .. T('testdrive_end_key'))
    EndTextCommandDisplayText(0.5, 0.885)
end

--- Starts a test drive of one catalogue vehicle. Returns ok, error.
local function startTestDrive(d, vehicleId)
    if not TD.enabled then return false, T('testdrive_disabled') end
    if State.testDrive then return false, T('testdrive_active') end
    local point = d.testdrive or d.spawn
    if not point then return false, T('testdrive_disabled') end
    if SpotBlocked(point) then return false, T('spawn_blocked') end

    local res = TriggerCallback('shop:testdrive', d.id, vehicleId)
    if not res then return false, 'No response from server.' end
    if not res.ok then return false, res.error end

    if State.shopOpen then CloseUI() end
    local ped = PlayerPedId()
    local returnPos, returnHeading = GetEntityCoords(ped), GetEntityHeading(ped)

    DoScreenFadeOut(300)
    Wait(350)
    if res.instanced then Wait(250) end -- routing bucket switch
    local veh = SpawnPlayerVehicle(res.model, point, res.plate)
    DoScreenFadeIn(400)
    if not veh then
        TriggerServerEvent('gen_dealership:testdriveEnd')
        return false, T('vehicle_not_found')
    end
    TriggerServerEvent('gen_dealership:testdriveSpawned', NetworkGetNetworkIdFromEntity(veh))

    local origin = vector3(point.x + 0.0, point.y + 0.0, point.z + 0.0)
    State.testDrive = {
        vehicle = veh,
        endsAt = GetGameTimer() + res.duration * 1000,
        returnPos = returnPos,
        returnHeading = returnHeading,
    }
    Bridge.Notify(T('testdrive_started', res.label, res.duration), 'primary')

    CreateThread(function()
        local outSince
        local maxDist = (TD.maxDistance or 0) > 0 and TD.maxDistance or nil
        while State.testDrive and State.testDrive.vehicle == veh do
            local myPed = PlayerPedId()
            local remaining = math.max(0, math.ceil((State.testDrive.endsAt - GetGameTimer()) / 1000))
            local dist = #(GetEntityCoords(myPed) - origin)
            local warn = maxDist and dist > maxDist * 0.8
            testDriveHud(remaining, dist / 1000.0, maxDist and maxDist / 1000.0, warn)

            if GetVehiclePedIsIn(myPed, false) ~= veh then
                outSince = outSince or GetGameTimer()
            else
                outSince = nil
            end

            DisableControlAction(0, 73, true)
            if IsDisabledControlJustReleased(0, 73) then
                endTestDrive(T('testdrive_ended_early'))
                break
            elseif maxDist and dist > maxDist then
                endTestDrive(T('testdrive_too_far'))
                break
            elseif remaining <= 0
                or (outSince and GetGameTimer() - outSince > 5000)
                or not DoesEntityExist(veh)
                or IsEntityDead(myPed) then
                endTestDrive()
                break
            end
            Wait(0)
        end
    end)
    return true
end

RegisterNUICallback('shopTestDrive', function(data, cb)
    local d = State.shopId and findDealership(State.shopId)
    if not d then return cb({ ok = false, error = T('vehicle_not_found') }) end
    -- answer the UI first: startTestDrive closes it and yields for the fade
    local point = d.testdrive or d.spawn
    if not point then return cb({ ok = false, error = T('testdrive_disabled') }) end
    if SpotBlocked(point) then return cb({ ok = false, error = T('spawn_blocked') }) end
    local ok, err = startTestDrive(d, data.vehicleId)
    cb({ ok = ok, error = err })
end)

-- Server ended the test drive (timeout / cleanup)
RegisterNetEvent('gen_dealership:testdriveForceEnd', function(reason)
    if State.testDrive then endTestDrive(reason) end
end)

-- ---------------------------------------------------------------------------
-- World interaction loop
-- ---------------------------------------------------------------------------

CreateThread(function()
    local m = Config.Marker
    while true do
        local sleep = 750
        if not UIBusy() then
            local pos = GetEntityCoords(PlayerPedId())
            local prompted = false

            for _, d in ipairs(State.dealerships) do
                local access = canAccess(d)
                if d.shop and access then
                    local point = ToVec3(d.shop)
                    local dist = #(pos - point)
                    if dist < Config.MarkerDrawDistance then
                        sleep = 0
                        DrawMarker(m.type, point.x, point.y, point.z + 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            m.scale, m.scale, m.scale, m.color[1], m.color[2], m.color[3], m.color[4],
                            true, true, 2, false, nil, nil, false)

                        if dist < Config.InteractDistance and not UseTarget then
                            prompted = true
                            local role = State.roles[tostring(d.id)]
                            ShowHelp(role and T('open_shop_manage', d.label) or T('open_shop', d.label))
                            if IsControlJustReleased(0, Config.InteractKey) then
                                openShop(d)
                            elseif role and IsControlJustReleased(0, 47) then
                                OpenManagement(d.id)
                            end
                        end
                    end
                end

                local list = Displays[d.id]
                if list then
                    local closest, closestDist, closestInfo
                    for i, veh in pairs(list) do
                        if DoesEntityExist(veh) then
                            local vpos = GetEntityCoords(veh)
                            local vdist = #(pos - vpos)
                            if vdist < Config.DisplayLabelDistance then
                                sleep = 0
                                local spot = d.displays[i]
                                local info = spot and findVehicleByModel(d, spot.model)
                                if info then
                                    DrawText3D(vpos + vector3(0.0, 0.0, 1.3),
                                        ('%s~n~~g~%s'):format(info.label, Utils.FormatMoney(info.price)))
                                    if not closestDist or vdist < closestDist then
                                        closest, closestDist, closestInfo = veh, vdist, info
                                    end
                                end
                            end
                        end
                    end

                    -- Test drive straight from a showroom car
                    if TD.enabled and TD.fromDisplays and access and closest and not prompted
                        and closestDist < (TD.displayInteractDistance or 3.5) and not UseTarget then
                        prompted = true
                        ShowHelp(T('testdrive_display', closestInfo.label))
                        if IsControlJustReleased(0, Config.InteractKey) then
                            local ok, err = startTestDrive(d, closestInfo.id)
                            if not ok and err then Bridge.Notify(err, 'error') end
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
CanAccessDealership = canAccess
OpenShopFor = openShop
StartTestDriveFor = startTestDrive
FindVehicleById = findVehicleById
