fx_version 'cerulean'
game 'gta5'

description 'qbx_vehiclesales'
repository 'https://github.com/Qbox-project/qbx_vehiclesales'
version '1.0.0'

shared_scripts {
	'@ox_lib/init.lua',
    '@qbx_core/modules/utils.lua',
    '@qbx_core/shared/locale.lua',
    'locales/en.lua',
    'locales/*.lua',
	'config.lua',
}

client_scripts {
	'@qbx_core/modules/playerdata.lua',
	'@PolyZone/client.lua',
	'@PolyZone/BoxZone.lua',
	'@PolyZone/EntityZone.lua',
	'@PolyZone/CircleZone.lua',
	'@PolyZone/ComboZone.lua',
	'client/main.lua'
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'server/main.lua'
}

ui_page 'html/ui.html'

files {
	'html/logo.svg',
	'html/ui.css',
	'html/ui.html',
	'html/vue.min.js',
	'html/ui.js'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'