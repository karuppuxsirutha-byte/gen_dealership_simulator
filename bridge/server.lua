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
--- @param props table|nil extra vehicle properties (color1, color2, ...) merged with { plate }
function Bridge.GiveVehicle(src, model, plate, dealership, props)
    local p = getPlayer(src)
    local mods = { plate = plate }
    for k, v in pairs(props or {}) do mods[k] = v end

    if fw == 'qbx' and Utils.IsRunning('qbx_vehicles') then
        local ok, id = pcall(function()
            return exports.qbx_vehicles:CreatePlayerVehicle({
                model = model,
                citizenid = p.PlayerData.citizenid,
                garage = Config.DefaultGarage,
                props = mods,
            })
        end)
        return ok and id ~= nil
    end

    if isQB then
        if not p then return false end
        local id = MySQL.insert.await(
            'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { p.PlayerData.license, p.PlayerData.citizenid, model, joaat(model), json.encode(mods), plate, Config.DefaultGarage, 0 }
        )
        return id ~= nil
    end

    if fw == 'esx' then
        if not p then return false end
        mods.model = joaat(model)
        local id = MySQL.insert.await(
            'INSERT INTO owned_vehicles (owner, plate, vehicle, type, stored) VALUES (?, ?, ?, ?, ?)',
            { p.identifier, plate, json.encode(mods), 'car', 0 }
        )
        return id ~= nil
    end

    local id = MySQL.insert.await(
        'INSERT INTO gen_dealership_owned (identifier, model, plate, dealership) VALUES (?, ?, ?, ?)',
        { Bridge.GetIdentifier(src), model, plate, dealership }
    )
    return id ~= nil
end

--- Returns { hash = number, model = string|nil } when `plate` is owned by the player, else nil.
function Bridge.GetOwnedVehicle(src, plate)
    local ident = Bridge.GetIdentifier(src)
    if not ident then return nil end
    if isQB then
        local row = MySQL.single.await('SELECT vehicle, hash FROM player_vehicles WHERE plate = ? AND citizenid = ? LIMIT 1', { plate, ident })
        if not row then return nil end
        return { hash = tonumber(row.hash) or joaat(row.vehicle), model = row.vehicle }
    elseif fw == 'esx' then
        local row = MySQL.single.await('SELECT vehicle FROM owned_vehicles WHERE plate = ? AND owner = ? LIMIT 1', { plate, ident })
        if not row then return nil end
        local ok, data = pcall(json.decode, row.vehicle or '')
        return ok and data and data.model and { hash = tonumber(data.model) } or nil
    end
    local row = MySQL.single.await('SELECT model FROM gen_dealership_owned WHERE plate = ? AND identifier = ? LIMIT 1', { plate, ident })
    return row and { hash = joaat(row.model), model = row.model } or nil
end

--- Identifier of whoever owns `plate`, or nil.
function Bridge.GetPlateOwner(plate)
    if isQB then return MySQL.scalar.await('SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1', { plate }) end
    if fw == 'esx' then return MySQL.scalar.await('SELECT owner FROM owned_vehicles WHERE plate = ? LIMIT 1', { plate }) end
    return MySQL.scalar.await('SELECT identifier FROM gen_dealership_owned WHERE plate = ? LIMIT 1', { plate })
end

--- Removes an owned vehicle record (trade-in, repossession) and deletes it from the world if spawned.
function Bridge.RemoveVehicle(plate)
    MySQL.query.await(('DELETE FROM `%s` WHERE plate = ?'):format(plateTable), { plate })
    for _, veh in ipairs(GetAllVehicles()) do
        local p = (GetVehicleNumberPlateText(veh) or ''):gsub('^%s+', ''):gsub('%s+$', '')
        if p == plate then DeleteEntity(veh) end
    end
end

--- Gives an inventory item with metadata (ox_inventory / qb-inventory). Returns true if given.
function Bridge.GiveItem(src, item, metadata)
    if Utils.IsRunning('ox_inventory') then
        local ok, res = pcall(function() return exports.ox_inventory:AddItem(src, item, 1, metadata) end)
        return ok and res ~= false
    end
    if isQB then
        local p = getPlayer(src)
        if p and p.Functions.AddItem then return p.Functions.AddItem(item, 1, false, metadata) ~= false end
    end
    return false
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
