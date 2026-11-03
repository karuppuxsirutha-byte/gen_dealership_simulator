fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gen_dealership'
description 'In-game vehicle dealership creator & shop for FiveM (Qbox / QBCore / ESX / standalone)'
version '1.7.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/business.js',
    'html/logistics.js',
    'html/buying.js',
}

shared_scripts {
    'config.lua',
    'locales/*.lua',
    'shared/utils.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/callback.lua',
    'client/main.lua',
    'client/creator.lua',
    'client/business.lua',
    'client/logistics.lua',
    'client/preview.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/webhooks_config.lua',
    'server/webhooks.lua',
    'server/callback.lua',
    'server/database.lua',
    'server/business.lua',
    'server/simulation.lua',
    'server/logistics.lua',
    'server/company.lua',
    'server/usedlot.lua',
    'server/finance.lua',
    'server/staffing.lua',
    'server/market.lua',
    'server/main.lua',
}

dependency 'oxmysql'
