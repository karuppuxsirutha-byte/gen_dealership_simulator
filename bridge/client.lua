-- Client-side framework bridge.
Bridge = {}

local fw = Utils.DetectFramework()
Bridge.Framework = fw

local QBCore, ESX
if fw == 'qb' then
    QBCore = exports['qb-core']:GetCoreObject()
elseif fw == 'esx' then
    ESX = exports.es_extended:getSharedObject()
end

function Bridge.Notify(msg, kind)
    kind = kind or 'primary'
    if fw == 'qbx' then
        exports.qbx_core:Notify(msg, kind)
    elseif fw == 'qb' then
        QBCore.Functions.Notify(msg, kind)
    elseif fw == 'esx' then
        ESX.ShowNotification(msg)
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, true)
    end
end

function Bridge.GetJob()
    if fw == 'qbx' then
        local data = exports.qbx_core:GetPlayerData()
        return data and data.job and data.job.name
    elseif fw == 'qb' then
        local data = QBCore.Functions.GetPlayerData()
        return data and data.job and data.job.name
    elseif fw == 'esx' then
        local data = ESX.GetPlayerData()
        return data and data.job and data.job.name
    end
    return nil
end

function Bridge.GiveKeys(vehicle, plate)
    if Utils.IsRunning('qb-vehiclekeys') then
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
    elseif Utils.IsRunning('wasabi_carlock') then
        pcall(function() exports.wasabi_carlock:GiveKey(plate) end)
    end
    -- qbx_vehiclekeys is handled server-side (bridge/server.lua)
end

function Bridge.SetFuel(vehicle, level)
    if Utils.IsRunning('LegacyFuel') then
        exports.LegacyFuel:SetFuel(vehicle, level)
    elseif Utils.IsRunning('ox_fuel') then
        Entity(vehicle).state.fuel = level
    elseif Utils.IsRunning('cdn-fuel') then
        exports['cdn-fuel']:SetFuel(vehicle, level)
    else
        SetVehicleFuelLevel(vehicle, level + 0.0)
    end
end

-- Job changes refresh blips / access (OnJobChanged is defined in client/main.lua)
local function jobChanged() if OnJobChanged then OnJobChanged() end end
RegisterNetEvent('QBCore:Client:OnJobUpdate', jobChanged)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', jobChanged)
RegisterNetEvent('esx:setJob', jobChanged)
RegisterNetEvent('esx:playerLoaded', jobChanged)
