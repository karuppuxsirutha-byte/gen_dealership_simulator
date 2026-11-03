-- Server-side framework bridge. Everything framework specific lives here.
Bridge = {}

local fw = Utils.DetectFramework()
Bridge.Framework = fw

local QBCore, ESX
if fw == 'qb' then
    QBCore = exports['qb-core']:GetCoreObject()
elseif fw == 'esx' then
    ESX = exports.es_extended:getSharedObject()
end

local isQB = fw == 'qb' or fw == 'qbx'
local esxAccounts = { cash = 'money', bank = 'bank' }

local function getPlayer(src)
    if fw == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    if fw == 'qb' then return QBCore.Functions.GetPlayer(src) end
    if fw == 'esx' then return ESX.GetPlayerFromId(src) end
    return nil
end

function Bridge.GetIdentifier(src)
    local p = getPlayer(src)
    if isQB then return p and p.PlayerData.citizenid end
    if fw == 'esx' then return p and p.identifier end
    return GetPlayerIdentifierByType(src, 'license') or ('player:' .. src)
end

function Bridge.GetName(src)
    local p = getPlayer(src)
    if isQB and p and p.PlayerData.charinfo then
        return ('%s %s'):format(p.PlayerData.charinfo.firstname or '', p.PlayerData.charinfo.lastname or '')
    end
    if fw == 'esx' and p and p.getName then return p.getName() end
    return GetPlayerName(src) or ('Player ' .. tostring(src))
end

function Bridge.GetJob(src)
    local p = getPlayer(src)
    if not p then return nil end
    if isQB then return p.PlayerData.job and p.PlayerData.job.name end
    if fw == 'esx' then return p.job and p.job.name end
    return nil
end

--- @return number|nil balance (nil when the framework has no economy)
function Bridge.GetMoney(src, account)
    if fw == 'standalone' then return nil end
    local p = getPlayer(src)
    if not p then return 0 end
    if isQB then return p.PlayerData.money[account] or 0 end
    local acc = p.getAccount(esxAccounts[account] or account)
    return acc and acc.money or 0
end

function Bridge.RemoveMoney(src, account, amount, reason)
    if amount <= 0 then return true end
    if fw == 'standalone' then return Config.Standalone.FreePurchases end
    local p = getPlayer(src)
    if not p then return false end
    if isQB then
        if (p.PlayerData.money[account] or 0) < amount then return false end
        return p.Functions.RemoveMoney(account, amount, reason) ~= false
    end
    local name = esxAccounts[account] or account
    local acc = p.getAccount(name)
    if not acc or acc.money < amount then return false end
    p.removeAccountMoney(name, amount, reason)
    return true
end

function Bridge.AddMoney(src, account, amount, reason)
    if amount <= 0 or fw == 'standalone' then return end
    local p = getPlayer(src)
    if not p then return end
    if isQB then
        p.Functions.AddMoney(account, amount, reason)
    else
        p.addAccountMoney(esxAccounts[account] or account, amount, reason)
    end
end

function Bridge.IsAdmin(src)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, Config.AdminAce) then return true end
    if fw == 'qb' then
        return QBCore.Functions.HasPermission(src, 'admin') or QBCore.Functions.HasPermission(src, 'god')
    elseif fw == 'qbx' then
        local ok, res = pcall(function() return exports.qbx_core:HasPermission(src, 'admin') end)
        return (ok and res) or IsPlayerAceAllowed(src, 'group.admin')
    elseif fw == 'esx' then
        local p = getPlayer(src)
        local group = p and p.getGroup and p.getGroup()
        return group == 'admin' or group == 'superadmin'
    end
    return false
end

local plateTable = isQB and 'player_vehicles' or (fw == 'esx' and 'owned_vehicles' or 'gen_dealership_owned')

function Bridge.PlateExists(plate)
    return MySQL.scalar.await(('SELECT 1 FROM `%s` WHERE plate = ? LIMIT 1'):format(plateTable), { plate }) ~= nil
end

--- Registers the vehicle as owned by the player. Must return true on success.
function Bridge.GiveVehicle(src, model, plate, dealership)
    local p = getPlayer(src)

    if fw == 'qbx' and Utils.IsRunning('qbx_vehicles') then
        local ok, id = pcall(function()
            return exports.qbx_vehicles:CreatePlayerVehicle({
                model = model,
                citizenid = p.PlayerData.citizenid,
                garage = Config.DefaultGarage,
                props = { plate = plate },
            })
        end)
        return ok and id ~= nil
    end

    if isQB then
        if not p then return false end
        local id = MySQL.insert.await(
            'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { p.PlayerData.license, p.PlayerData.citizenid, model, joaat(model), json.encode({ plate = plate }), plate, Config.DefaultGarage, 0 }
        )
        return id ~= nil
    end

    if fw == 'esx' then
        if not p then return false end
        local id = MySQL.insert.await(
            'INSERT INTO owned_vehicles (owner, plate, vehicle, type, stored) VALUES (?, ?, ?, ?, ?)',
            { p.identifier, plate, json.encode({ model = joaat(model), plate = plate }), 'car', 0 }
        )
        return id ~= nil
    end

    local id = MySQL.insert.await(
        'INSERT INTO gen_dealership_owned (identifier, model, plate, dealership) VALUES (?, ?, ?, ?)',
        { Bridge.GetIdentifier(src), model, plate, dealership }
    )
    return id ~= nil
end

--- Server-side key systems. Client-side ones are handled in bridge/client.lua.
function Bridge.GiveKeys(src, vehicle, plate)
    if Utils.IsRunning('qbx_vehiclekeys') then
        pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, vehicle, true) end)
    end
end

function Bridge.Notify(src, msg, kind)
    TriggerClientEvent('gen_dealership:notify', src, msg, kind)
end
