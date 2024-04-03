fx_version 'cerulean'
game 'gta5'

description 'qbx_vehiclesales'
repository 'https://github.com/Qbox-project/qbx_vehiclesales'
version '1.0.0'

ox_lib 'locale'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
}

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'html/ui.html'

files {
    'config/client.lua',
    'locales/*.json',
    'html/logo.svg',
    'html/ui.css',
    'html/ui.html',
    'html/vue.min.js',
    'html/ui.js'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'