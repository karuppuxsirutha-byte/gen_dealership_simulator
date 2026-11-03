DB = {}

local schema = {
    [[CREATE TABLE IF NOT EXISTS `gen_dealerships` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `name` VARCHAR(64) NOT NULL,
        `label` VARCHAR(100) NOT NULL,
        `job` VARCHAR(64) NOT NULL DEFAULT '',
        `blip` LONGTEXT NULL,
        `shop` LONGTEXT NULL,
        `spawn` LONGTEXT NULL,
        `testdrive` LONGTEXT NULL,
        `displays` LONGTEXT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `name` (`name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `gen_dealership_vehicles` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `dealership_id` INT NOT NULL,
        `model` VARCHAR(32) NOT NULL,
        `label` VARCHAR(100) NOT NULL,
        `category` VARCHAR(64) NOT NULL DEFAULT 'other',
        `price` INT NOT NULL DEFAULT 0,
        `stock` INT NOT NULL DEFAULT -1,
        PRIMARY KEY (`id`),
        KEY `dealership_id` (`dealership_id`),
        CONSTRAINT `fk_gen_dealership_vehicles` FOREIGN KEY (`dealership_id`) REFERENCES `gen_dealerships` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `gen_dealership_sales` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `dealership` VARCHAR(64) NOT NULL,
        `identifier` VARCHAR(100) NOT NULL,
        `model` VARCHAR(32) NOT NULL,
        `plate` VARCHAR(8) NOT NULL,
        `price` INT NOT NULL,
        `payment` VARCHAR(16) NOT NULL,
        `sold_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- Only used in standalone mode
    [[CREATE TABLE IF NOT EXISTS `gen_dealership_owned` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(100) NOT NULL,
        `model` VARCHAR(32) NOT NULL,
        `plate` VARCHAR(8) NOT NULL,
        `dealership` VARCHAR(64) NOT NULL,
        `purchased_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `plate` (`plate`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

function DB.Init()
    for _, query in ipairs(schema) do
        MySQL.query.await(query)
    end
end

local function decode(str, fallback)
    if not str or str == '' then return fallback end
    local ok, result = pcall(json.decode, str)
    if ok and result ~= nil then return result end
    return fallback
end

-- oxmysql positional params must not contain nil holes, so encode "missing" as ''
local function encode(value)
    if value == nil then return '' end
    return json.encode(value)
end

function DB.LoadAll()
    local rows = MySQL.query.await('SELECT * FROM gen_dealerships ORDER BY label') or {}
    local vehicles = MySQL.query.await('SELECT * FROM gen_dealership_vehicles ORDER BY category, price, label') or {}

    local list, byId = {}, {}
    for _, r in ipairs(rows) do
        local d = {
            id = r.id,
            name = r.name,
            label = r.label,
            job = r.job ~= '' and r.job or nil,
            blip = decode(r.blip, nil) or {
                enabled = Config.DefaultBlip.enabled,
                sprite = Config.DefaultBlip.sprite,
                color = Config.DefaultBlip.color,
                scale = Config.DefaultBlip.scale,
            },
            shop = decode(r.shop, nil),
            spawn = decode(r.spawn, nil),
            testdrive = decode(r.testdrive, nil),
            displays = decode(r.displays, {}),
            vehicles = {},
        }
        list[#list + 1] = d
        byId[d.id] = d
    end

    for _, v in ipairs(vehicles) do
        local d = byId[v.dealership_id]
        if d then
            d.vehicles[#d.vehicles + 1] = {
                id = v.id,
                model = v.model,
                label = v.label,
                category = v.category,
                price = v.price,
                stock = v.stock,
            }
        end
    end

    return list, byId
end

--- Inserts or updates a (sanitized) dealership and replaces its vehicle list.
--- @return number id
function DB.Save(d)
    local params = {
        d.name, d.label, d.job or '', encode(d.blip),
        encode(d.shop), encode(d.spawn), encode(d.testdrive), encode(d.displays),
    }

    local id = d.id
    if id then
        params[#params + 1] = id
        MySQL.update.await(
            'UPDATE gen_dealerships SET name = ?, label = ?, job = ?, blip = ?, shop = ?, spawn = ?, testdrive = ?, displays = ? WHERE id = ?',
            params
        )
    else
        id = MySQL.insert.await(
            'INSERT INTO gen_dealerships (name, label, job, blip, shop, spawn, testdrive, displays) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            params
        )
    end

    local queries = {
        { query = 'DELETE FROM gen_dealership_vehicles WHERE dealership_id = ?', values = { id } },
    }
    for _, v in ipairs(d.vehicles) do
        queries[#queries + 1] = {
            query = 'INSERT INTO gen_dealership_vehicles (dealership_id, model, label, category, price, stock) VALUES (?, ?, ?, ?, ?, ?)',
            values = { id, v.model, v.label, v.category, v.price, v.stock },
        }
    end
    MySQL.transaction.await(queries)

    return id
end

function DB.Delete(id)
    MySQL.query.await('DELETE FROM gen_dealerships WHERE id = ?', { id })
end

function DB.SetStock(vehicleId, stock)
    MySQL.update('UPDATE gen_dealership_vehicles SET stock = ? WHERE id = ?', { stock, vehicleId })
end

function DB.LogSale(dealership, identifier, model, plate, price, payment)
    MySQL.insert(
        'INSERT INTO gen_dealership_sales (dealership, identifier, model, plate, price, payment) VALUES (?, ?, ?, ?, ?, ?)',
        { dealership, identifier or 'unknown', model, plate, price, payment }
    )
end
