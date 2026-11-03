-- Dealership simulator (client): roles, management panel, AI customers, staff offers.
local T = Utils.T

local Customers = {}   -- [id] = { id, dealershipId, name, ped, coords, label }
local Peds = {}        -- [id] = ped handle
local SCENARIOS = { 'WORLD_HUMAN_STAND_IMPATIENT', 'WORLD_HUMAN_STAND_MOBILE', 'CODE_HUMAN_CROSS_ROAD_WAIT', 'WORLD_HUMAN_TOURIST_MOBILE' }

-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------

function RefreshRoles()
    State.roles = TriggerCallback('biz:roles') or {}
end

RegisterNetEvent('gen_dealership:roles', function(map)
    State.roles = map or {}
    if State.manageOpen and State.manageId and not State.roles[tostring(State.manageId)] then
        CloseUI()
    end
end)

-- ---------------------------------------------------------------------------
-- AI customers
-- ---------------------------------------------------------------------------

local function removePed(id, walkAway)
    local ped = Peds[id]
    Peds[id] = nil
    if not ped or not DoesEntityExist(ped) then return end
    if RemoveEntityTarget then RemoveEntityTarget(ped) end
    if walkAway then
        ClearPedTasks(ped)
        TaskWanderStandard(ped, 10.0, 10)
        SetTimeout(15000, function()
            if DoesEntityExist(ped) then DeleteEntity(ped) end
        end)
    else
        DeleteEntity(ped)
    end
end

local function setCustomers(list)
    local incoming = {}
    for _, c in ipairs(list or {}) do incoming[c.id] = c end
    for id in pairs(Customers) do
        if not incoming[id] then removePed(id, true) end
    end
    Customers = incoming
end

RegisterNetEvent('gen_dealership:customers', setCustomers)

local function spawnPed(c)
    local hash = joaat(c.ped)
    if not IsModelInCdimage(hash) then return end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(hash) or not Customers[c.id] or Peds[c.id] then return end

    local found, groundZ = GetGroundZFor_3dCoord(c.coords.x + 0.0, c.coords.y + 0.0, c.coords.z + 2.0, false)
    local ped = CreatePed(4, hash, c.coords.x + 0.0, c.coords.y + 0.0, (found and groundZ or c.coords.z) + 0.0, c.coords.w + 0.0, false, false)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdoll(ped, false)
    SetEntityInvincible(ped, true)
    SetPedDiesWhenInjured(ped, false)
    TaskStartScenarioInPlace(ped, SCENARIOS[(c.id % #SCENARIOS) + 1], 0, true)
    SetModelAsNoLongerNeeded(hash)
    Peds[c.id] = ped
    if AddCustomerTarget then AddCustomerTarget(ped, c.id, c.dealershipId) end
end

CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for id, c in pairs(Customers) do
            local dist = #(pos - ToVec3(c.coords))
            if dist < 80.0 and not Peds[id] then
                spawnPed(c)
            elseif dist > 100.0 and Peds[id] then
                removePed(id, false)
            end
        end
        Wait(1000)
    end
end)

function EngageCustomer(id)
    local res = TriggerCallback('customer:engage', id)
    if not res or not res.ok then
        Bridge.Notify(res and res.error or 'No response from server.', 'error')
        return
    end
    local ped = Peds[id]
    if ped and DoesEntityExist(ped) then
        ClearPedTasks(ped)
        TaskTurnPedToFaceEntity(ped, PlayerPedId(), -1)
    end
    State.negotiating = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openNegotiation', data = res, currency = Config.Currency })
end

CreateThread(function()
    while true do
        local sleep = 500
        if not UIBusy() then
            local pos = GetEntityCoords(PlayerPedId())
            for id, ped in pairs(Peds) do
                local c = Customers[id]
                if c and DoesEntityExist(ped) and State.roles[tostring(c.dealershipId)] then
                    local ppos = GetEntityCoords(ped)
                    local dist = #(pos - ppos)
                    if dist < 10.0 then
                        sleep = 0
                        DrawText3D(ppos + vector3(0.0, 0.0, 1.1), ('~b~%s~s~~n~Interested in %s'):format(c.name, c.label))
                        if dist < 2.0 and not UseTarget then
                            ShowHelp(T('talk_customer'))
                            if IsControlJustReleased(0, Config.InteractKey) then EngageCustomer(id) end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

RegisterNUICallback('negRespond', function(data, cb)
    local res = TriggerCallback('customer:respond', data.id, data.action, data.amount)
    cb(res or { ok = false, error = 'No response from server.' })
    if res and res.state == 'sold' then
        local ped = Peds[data.id]
        if ped and DoesEntityExist(ped) then
            TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CHEERING', 0, true)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Management panel
-- ---------------------------------------------------------------------------

function OpenManagement(id)
    local res = TriggerCallback('biz:action', id, 'open', {})
    if not res or not res.ok then
        Bridge.Notify(res and res.error or 'No response from server.', 'error')
        return
    end
    State.manageOpen = true
    State.manageId = id
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openManage', data = res.data, categories = Config.Categories, currency = Config.Currency })
end

RegisterNUICallback('bizAction', function(data, cb)
    if not State.manageId then return cb({ ok = false, error = 'Panel closed.' }) end
    local res = TriggerCallback('biz:action', State.manageId, data.action, data.payload or {})
    cb(res or { ok = false, error = 'No response from server.' })
    if res and res.ok and res.closed then
        CloseUI()
        if res.message then Bridge.Notify(res.message, 'success') end
    end
end)

-- ---------------------------------------------------------------------------
-- Incoming staff offers
-- ---------------------------------------------------------------------------

RegisterNetEvent('gen_dealership:offer', function(offer)
    State.offerOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openOffer', offer = offer, currency = Config.Currency })
end)

RegisterNUICallback('offerRespond', function(data, cb)
    local res = TriggerCallback('offer:respond', data.id, data.accept == true, data.method)
    cb(res or { ok = false, error = 'No response from server.' })
    State.offerOpen = false
    if not (State.shopOpen or State.creatorOpen or State.manageOpen or State.negotiating) then
        SetNuiFocus(false, false)
    end

    if res and res.ok and res.plate and res.spawn then
        if SpotBlocked(res.spawn) then
            Bridge.Notify(T('delivered_garage'), 'primary')
        else
            if State.shopOpen then CloseUI() end
            DoScreenFadeOut(300)
            Wait(350)
            SpawnPlayerVehicle(res.model, res.spawn, res.plate)
            DoScreenFadeIn(400)
        end
        Bridge.Notify(T('purchased', res.label, res.priceText, res.plate), 'success')
    end
end)

-- ---------------------------------------------------------------------------
-- Boot & cleanup
-- ---------------------------------------------------------------------------

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    Wait(1500)
    RefreshRoles()
    setCustomers(TriggerCallback('customers:get'))
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(Peds) do removePed(id, false) end
end)

-- Radio / billboard adverts bought by dealerships
RegisterNetEvent('gen_dealership:advert', function(dealership, text)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostMessagetext('CHAR_CARSITE', 'CHAR_CARSITE', false, 1, dealership, 'Advertisement')
    EndTextCommandThefeedPostTicker(false, true)
end)
