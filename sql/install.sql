-- Optional: these tables are also created automatically on resource start.

CREATE TABLE IF NOT EXISTS `gen_dealerships` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_vehicles` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gen_dealership_sales` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `dealership` VARCHAR(64) NOT NULL,
  `identifier` VARCHAR(100) NOT NULL,
  `model` VARCHAR(32) NOT NULL,
  `plate` VARCHAR(8) NOT NULL,
  `price` INT NOT NULL,
  `payment` VARCHAR(16) NOT NULL,
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
