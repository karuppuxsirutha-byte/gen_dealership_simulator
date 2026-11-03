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
        `delivery` LONGTEXT NULL,
        `preview` LONGTEXT NULL,
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
        `cost` INT NOT NULL DEFAULT 0,
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
        `seller` VARCHAR(100) NOT NULL DEFAULT '',
        `kind` VARCHAR(16) NOT NULL DEFAULT 'shop',
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

    -- ---- Simulator ----
    [[CREATE TABLE IF NOT EXISTS `gen_dealership_business` (
        `dealership_id` INT NOT NULL,
        `price` INT NOT NULL DEFAULT 0,
        `owner` VARCHAR(100) NOT NULL DEFAULT '',
        `owner_name` VARCHAR(100) NOT NULL DEFAULT '',
        `owner_since` INT NOT NULL DEFAULT 0,
        `balance` BIGINT NOT NULL DEFAULT 0,
        `reputation` INT NOT NULL DEFAULT 50,
        PRIMARY KEY (`dealership_id`),
        CONSTRAINT `fk_gen_dealership_business` FOREIGN KEY (`dealership_id`) REFERENCES `gen_dealerships` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `gen_dealership_employees` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `dealership_id` INT NOT NULL,
        `identifier` VARCHAR(100) NOT NULL,
        `name` VARCHAR(100) NOT NULL,
        `role` VARCHAR(16) NOT NULL DEFAULT 'sales',
        `commission` INT NOT NULL DEFAULT 10,
        `hired_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `dealership_identifier` (`dealership_id`, `identifier`),
        CONSTRAINT `fk_gen_dealership_employees` FOREIGN KEY (`dealership_id`) REFERENCES `gen_dealerships` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `gen_dealership_orders` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `dealership_id` INT NOT NULL,
        `vehicle_id` INT NOT NULL,
        `model` VARCHAR(32) NOT NULL,
        `label` VARCHAR(100) NOT NULL,
        `quantity` INT NOT NULL,
        `cost` INT NOT NULL,
        `arrives_at` INT NOT NULL,
        `delivered` TINYINT NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`),
        KEY `pending` (`delivered`),
        CONSTRAINT `fk_gen_dealership_orders` FOREIGN KEY (`dealership_id`) REFERENCES `gen_dealerships` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `gen_dealership_shipments` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `order_id` INT NOT NULL,
        `dealership_id` INT NOT NULL,
        `vehicle_id` INT NOT NULL,
        `model` VARCHAR(32) NOT NULL,
        `label` VARCHAR(100) NOT NULL,
        `unit_cost` INT NOT NULL DEFAULT 0,
        `fee` INT NOT NULL DEFAULT 0,
        `status` VARCHAR(16) NOT NULL DEFAULT 'waiting',
        `driver` VARCHAR(100) NOT NULL DEFAULT '',
        `payout` INT NOT NULL DEFAULT 0,
        `auto_at` INT NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `status` (`status`),
        CONSTRAINT `fk_gen_dealership_shipments` FOREIGN KEY (`dealership_id`) REFERENCES `gen_dealerships` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `gen_dealership_used` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `dealership_id` INT NOT NULL,
        `model` VARCHAR(32) NOT NULL,
        `label` VARCHAR(100) NOT NULL,
        `category` VARCHAR(64) NOT NULL DEFAULT 'other',
        `price` INT NOT NULL,
        `value` INT NOT NULL DEFAULT 0,
        `condition` INT NOT NULL DEFAULT 100,
        `source` VARCHAR(16) NOT NULL DEFAULT 'tradein',
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `dealership_id` (`dealership_id`),
        CONSTRAINT `fk_gen_dealership_used` FOREIGN KEY (`dealership_id`) REFERENCES `gen_dealerships` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `gen_dealership_finance` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(100) NOT NULL,
        `owner_name` VARCHAR(100) NOT NULL DEFAULT '',
        `dealership_id` INT NULL,
        `dealership` VARCHAR(100) NOT NULL DEFAULT '',
        `plate` VARCHAR(8) NOT NULL,
        `model` VARCHAR(32) NOT NULL,
        `label` VARCHAR(100) NOT NULL,
        `total` INT NOT NULL,
        `remaining` INT NOT NULL,
        `payment` INT NOT NULL,
        `payments_left` INT NOT NULL,
        `next_due` INT NOT NULL,
        `missed` INT NOT NULL DEFAULT 0,
        `status` VARCHAR(16) NOT NULL DEFAULT 'active',
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `identifier` (`identifier`),
        KEY `status` (`status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `gen_dealership_transactions` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `dealership_id` INT NOT NULL,
        `type` VARCHAR(24) NOT NULL,
        `amount` BIGINT NOT NULL DEFAULT 0,
        `description` VARCHAR(255) NOT NULL DEFAULT '',
        `actor` VARCHAR(100) NOT NULL DEFAULT '',
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `dealership_time` (`dealership_id`, `created_at`),
        CONSTRAINT `fk_gen_dealership_tx` FOREIGN KEY (`dealership_id`) REFERENCES `gen_dealerships` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

-- Columns added after the first release (for databases created by older versions)
local migrations = {
    { 'gen_dealerships', 'delivery', 'LONGTEXT NULL AFTER `testdrive`' },
    { 'gen_dealerships', 'preview', 'LONGTEXT NULL AFTER `delivery`' },
    { 'gen_dealership_vehicles', 'cost', 'INT NOT NULL DEFAULT 0 AFTER `price`' },
    { 'gen_dealership_sales', 'seller', "VARCHAR(100) NOT NULL DEFAULT '' AFTER `payment`" },
    { 'gen_dealership_sales', 'kind', "VARCHAR(16) NOT NULL DEFAULT 'shop' AFTER `seller`" },
}

function DB.Init()
    for _, query in ipairs(schema) do
        MySQL.query.await(query)
    end
    for _, m in ipairs(migrations) do
        local exists = MySQL.scalar.await(
            'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            { m[1], m[2] }
        )
        if (tonumber(exists) or 0) == 0 then
            MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(m[1], m[2], m[3]))
            print(('[gen_dealership] migrated: added %s.%s'):format(m[1], m[2]))
        end
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
            delivery = decode(r.delivery, nil),
            preview = decode(r.preview, nil),
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
                cost = v.cost,
                stock = v.stock,
            }
        end
    end

    return list, byId
end

--- Inserts or updates a (sanitized) dealership and syncs its vehicle list.
--- Vehicles are upserted by model so their ids stay stable.
--- @param keepBusinessFields boolean when true (owned dealership) price & stock of existing vehicles are left alone
--- @return number id
function DB.Save(d, keepBusinessFields)
    local params = {
        d.name, d.label, d.job or '', encode(d.blip),
        encode(d.shop), encode(d.spawn), encode(d.testdrive), encode(d.delivery), encode(d.preview), encode(d.displays),
    }

    local id = d.id
    if id then
        params[#params + 1] = id
        MySQL.update.await(
            'UPDATE gen_dealerships SET name = ?, label = ?, job = ?, blip = ?, shop = ?, spawn = ?, testdrive = ?, delivery = ?, preview = ?, displays = ? WHERE id = ?',
            params
        )
    else
        id = MySQL.insert.await(
            'INSERT INTO gen_dealerships (name, label, job, blip, shop, spawn, testdrive, delivery, preview, displays) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            params
        )
    end

    local existing = MySQL.query.await('SELECT id, model FROM gen_dealership_vehicles WHERE dealership_id = ?', { id }) or {}
    local byModel = {}
    for _, r in ipairs(existing) do byModel[r.model] = r.id end

    local queries, keep = {}, {}
    for _, v in ipairs(d.vehicles) do
        local vid = byModel[v.model]
        if vid then
            keep[vid] = true
            if keepBusinessFields then
                queries[#queries + 1] = {
                    query = 'UPDATE gen_dealership_vehicles SET label = ?, category = ?, cost = ? WHERE id = ?',
                    values = { v.label, v.category, v.cost, vid },
                }
            else
                queries[#queries + 1] = {
                    query = 'UPDATE gen_dealership_vehicles SET label = ?, category = ?, price = ?, cost = ?, stock = ? WHERE id = ?',
                    values = { v.label, v.category, v.price, v.cost, v.stock, vid },
                }
            end
        else
            queries[#queries + 1] = {
                query = 'INSERT INTO gen_dealership_vehicles (dealership_id, model, label, category, price, cost, stock) VALUES (?, ?, ?, ?, ?, ?, ?)',
                values = { id, v.model, v.label, v.category, v.price, v.cost, (keepBusinessFields and v.stock < 0) and 0 or v.stock },
            }
        end
    end
    for _, r in ipairs(existing) do
        if not keep[r.id] then
            queries[#queries + 1] = { query = 'DELETE FROM gen_dealership_vehicles WHERE id = ?', values = { r.id } }
        end
    end
    if #queries > 0 then
        MySQL.transaction.await(queries)
    end

    return id
end

function DB.Delete(id)
    MySQL.query.await('DELETE FROM gen_dealerships WHERE id = ?', { id })
end

function DB.SetStock(vehicleId, stock)
    MySQL.update('UPDATE gen_dealership_vehicles SET stock = ? WHERE id = ?', { stock, vehicleId })
end

function DB.SetPrice(vehicleId, price)
    MySQL.update('UPDATE gen_dealership_vehicles SET price = ? WHERE id = ?', { price, vehicleId })
end

function DB.LogSale(dealership, identifier, model, plate, price, payment, seller, kind)
    MySQL.insert(
        'INSERT INTO gen_dealership_sales (dealership, identifier, model, plate, price, payment, seller, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { dealership, identifier or 'unknown', model, plate, price, payment, seller or '', kind or 'shop' }
    )
end
