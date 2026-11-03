fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gen_dealership'
description 'In-game vehicle dealership creator & shop for FiveM (Qbox / QBCore / ESX / standalone)'
version '1.1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/business.js',
}

shared_scripts {
    'config.lua',
    'shared/utils.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/callback.lua',
    'client/main.lua',
    'client/creator.lua',
    'client/business.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/callback.lua',
    'server/database.lua',
    'server/business.lua',
    'server/simulation.lua',
    'server/main.lua',
}

dependency 'oxmysql'
