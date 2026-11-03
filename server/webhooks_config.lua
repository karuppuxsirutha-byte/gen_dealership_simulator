-- Server-only (never sent to clients). Paste Discord webhook URLs here.
-- Leave a channel empty to fall back to `default`; leave everything empty to disable logging.
ServerConfig = ServerConfig or {}

ServerConfig.Webhooks = {
    username = 'Dealership',
    default = '',
    sales = '',       -- vehicle purchases, staff & AI sales
    business = '',    -- business bought/sold, withdrawals, staff changes, ads
    finance = '',     -- financing contracts, repossessions
    logistics = '',   -- freight deliveries, company changes
    admin = '',       -- creator saves/deletes, ownership revokes, market events
}
