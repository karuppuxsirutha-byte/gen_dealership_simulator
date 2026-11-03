-- Optional: these tables are also created (and migrated) automatically on resource start.

CREATE TABLE IF NOT EXISTS `gen_dealerships` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_vehicles` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_sales` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_owned` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(100) NOT NULL,
  `model` VARCHAR(32) NOT NULL,
  `plate` VARCHAR(8) NOT NULL,
  `dealership` VARCHAR(64) NOT NULL,
  `purchased_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_business` (
  `dealership_id` INT NOT NULL,
  `price` INT NOT NULL DEFAULT 0,
  `owner` VARCHAR(100) NOT NULL DEFAULT '',
  `owner_name` VARCHAR(100) NOT NULL DEFAULT '',
  `owner_since` INT NOT NULL DEFAULT 0,
  `balance` BIGINT NOT NULL DEFAULT 0,
  `reputation` INT NOT NULL DEFAULT 50,
  `target_count` INT NOT NULL DEFAULT 0,
  `target_bonus` INT NOT NULL DEFAULT 0,
  `ad_label` VARCHAR(64) NOT NULL DEFAULT '',
  `ad_boost` INT NOT NULL DEFAULT 0,
  `ad_until` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`dealership_id`),
  CONSTRAINT `fk_gen_dealership_business` FOREIGN KEY (`dealership_id`) REFERENCES `gen_dealerships` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_employees` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `dealership_id` INT NOT NULL,
  `identifier` VARCHAR(100) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `role` VARCHAR(16) NOT NULL DEFAULT 'sales',
  `commission` INT NOT NULL DEFAULT 10,
  `wage` INT NOT NULL DEFAULT -1,
  `hired_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `dealership_identifier` (`dealership_id`, `identifier`),
  CONSTRAINT `fk_gen_dealership_employees` FOREIGN KEY (`dealership_id`) REFERENCES `gen_dealerships` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_orders` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_shipments` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_used` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_finance` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_shifts` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `dealership_id` INT NOT NULL,
  `identifier` VARCHAR(100) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `started` INT NOT NULL,
  `ended` INT NOT NULL DEFAULT 0,
  `earned` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `dealership_id` (`dealership_id`),
  CONSTRAINT `fk_gen_dealership_shifts` FOREIGN KEY (`dealership_id`) REFERENCES `gen_dealerships` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_bonuses` (
  `dealership_id` INT NOT NULL,
  `identifier` VARCHAR(100) NOT NULL,
  `week` INT NOT NULL,
  PRIMARY KEY (`dealership_id`, `identifier`, `week`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_logistics_company` (
  `id` INT NOT NULL,
  `owner` VARCHAR(100) NOT NULL DEFAULT '',
  `owner_name` VARCHAR(100) NOT NULL DEFAULT '',
  `balance` BIGINT NOT NULL DEFAULT 0,
  `cut` INT NOT NULL DEFAULT 15,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_logistics_drivers` (
  `identifier` VARCHAR(100) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `hired_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_transactions` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
