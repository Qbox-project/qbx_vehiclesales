local config = require 'config.client'
local zone
local activeZone = {}
local currentVehicle = {}
local entityZones = {}
local occasionVehicles = {}

local function spawnOccasionsVehicles(vehicles)
    if zone then
        local oSlot = config.Zones[zone].spots
        if not occasionVehicles[zone] then occasionVehicles[zone] = {} end
        if vehicles then
            for i = 1, #vehicles, 1 do
                local model = joaat(vehicles[i].model)
                lib.requestModel(model)
                occasionVehicles[zone][i] = {
                    car = CreateVehicle(model, oSlot[i].x, oSlot[i].y, oSlot[i].z, false, false),
                    loc = vector3(oSlot[i].x, oSlot[i].y, oSlot[i].z),
                    price = vehicles[i].price,
                    owner = vehicles[i].seller,
                    model = vehicles[i].model,
                    plate = vehicles[i].plate,
                    oid = vehicles[i].occasionid,
                    desc = vehicles[i].description,
                    mods = vehicles[i].mods
                }

                lib.setVehicleProperties(occasionVehicles[zone][i].car, json.decode(vehicles[i].mods))

                SetModelAsNoLongerNeeded(model)
                SetVehicleOnGroundProperly(occasionVehicles[zone][i].car)
                SetEntityInvincible(occasionVehicles[zone][i].car,true)
                SetEntityHeading(occasionVehicles[zone][i].car, oSlot[i].w)
                SetVehicleDoorsLocked(occasionVehicles[zone][i].car, 3)
                SetVehicleNumberPlateText(occasionVehicles[zone][i].car, occasionVehicles[zone][i].oid)
                FreezeEntityPosition(occasionVehicles[zone][i].car,true)
                if config.UseTarget then
                    if not entityZones then entityZones = {} end
                    entityZones[i] = exports.ox_target:addLocalEntity(occasionVehicles[zone][i].car, {
                        {
                            icon = 'fas fa-car',
                            label = locale('menu.view_contract'),
                            onSelect = function()
                                TriggerEvent('qb-vehiclesales:client:OpenContract', i)
                            end,
                            distance = 2.0
                        }
                    })
                end
            end
        end
    end
end

local function despawnOccasionsVehicles()
    if not zone then return end
    local oSlot = config.Zones[zone].spots
    for i = 1, #oSlot, 1 do
        local loc = oSlot[i]
        local oldVehicle = GetClosestVehicle(loc.x, loc.y, loc.z, 1.3, 0, 70)
        if oldVehicle then
            DeleteVehicle(oldVehicle)
        end

        if entityZones[i] and config.UseTarget then
            exports.ox_target:removeLocalEntity(occasionVehicles[zone][i].car, locale('menu.view_contract'))
        end
    end
    table.wipe(entityZones)
end

local function openSellContract(bool)
    SetNuiFocus(bool, bool)
    SendNUIMessage({
        action = 'sellVehicle',
        showTakeBackOption = false,
        bizName = config.Zones[zone].businessName,
        sellerData = {
            firstname = QBX.PlayerData.charinfo.firstname,
            lastname = QBX.PlayerData.charinfo.lastname,
            account = QBX.PlayerData.charinfo.account,
            phone = QBX.PlayerData.charinfo.phone
        },
        plate = qbx.getVehiclePlate(cache.vehicle)
    })
end

local function openBuyContract(sellerData, vehicleData)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'buyVehicle',
        showTakeBackOption = sellerData.charinfo.firstname == QBX.PlayerData.charinfo.firstname and sellerData.charinfo.lastname == QBX.PlayerData.charinfo.lastname,
        bizName = config.Zones[zone].businessName,
        sellerData = {
            firstname = sellerData.charinfo.firstname,
            lastname = sellerData.charinfo.lastname,
            account = sellerData.charinfo.account,
            phone = sellerData.charinfo.phone
        },
        vehicleData = {
            desc = vehicleData.desc,
            price = vehicleData.price
        },
        plate = vehicleData.plate
    })
end

local function sellVehicleWait(price)
    DoScreenFadeOut(250)
    Wait(250)
    DeleteVehicle(cache.vehicle)
    Wait(1500)
    DoScreenFadeIn(250)
    exports.qbx_core:Notify((locale('success.car_up_for_sale'):format(price)), 'success')
    PlaySound(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', false, 0, true)
end

local function sellData(data, model)
    local dataReturning = lib.callback.await('qb-vehiclesales:server:CheckModelName', false, model)
    local vehicleData = {}
    vehicleData.ent = cache.vehicle
    vehicleData.model = dataReturning
    vehicleData.plate = model
    vehicleData.mods = lib.getVehicleProperties(vehicleData.ent)
    vehicleData.desc = data.desc
    TriggerServerEvent('qb-occasions:server:sellVehicle', data.price, vehicleData)
    sellVehicleWait(data.price)
end

local function createZones()
    for k, v in pairs(config.Zones) do

        local SellSpot = lib.zones.poly({
            name = k,
            points = v.points,
            thickness = 50,
            debug = false,
            onEnter = function(self)
                zone = self.name
                local vehicles = lib.callback.await('qb-occasions:server:getVehicles', false)
                despawnOccasionsVehicles()
                spawnOccasionsVehicles(vehicles)
            end,
            onExit = function()
                despawnOccasionsVehicles()
                zone = nil
            end,
        })
        
        activeZone[k] = SellSpot
    end
end

local function deleteZones()
    for k in pairs(activeZone) do
        activeZone[k]:remove()
    end
    table.wipe(activeZone)
end

local function isCarSpawned(Car)
    if occasionVehicles and next(occasionVehicles) then
        for k in pairs(occasionVehicles[zone]) do
            if k == Car then
                return true
            end
        end
    end
    return false
end

RegisterNUICallback('sellVehicle', function(data, cb)
    local plate = qbx.getVehiclePlate(cache.vehicle) --Getting the plate and sending to the function
    sellData(data,plate)
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('buyVehicle', function(_, cb)
    TriggerServerEvent('qb-occasions:server:buyVehicle', currentVehicle)
    cb('ok')
end)

RegisterNUICallback('takeVehicleBack', function(_, cb)
    TriggerServerEvent('qb-occasions:server:ReturnVehicle', currentVehicle)
    cb('ok')
end)

RegisterNetEvent('qb-occasions:client:BuyFinished', function(vehData)
    DoScreenFadeOut(250)
    Wait(500)
    local netId = lib.callback.await('qbx_vehiclesales:server:spawnVehicle', false, vehData, config.Zones[zone].buyVehicle, false)
    local timeout = 100
    while not NetworkDoesEntityExistWithNetworkId(netId) and timeout > 0 do
        Wait(10)
        timeout -= 1
    end
    local veh = NetToVeh(netId)
    SetEntityHeading(veh, config.Zones[zone].buyVehicle.w)
    SetVehicleFuelLevel(veh, 100)
    exports.qbx_core:Notify(locale('success.vehicle_bought'), 'success', 2500)
    Wait(500)
    DoScreenFadeIn(250)
    currentVehicle = {}
end)

AddEventHandler('qb-occasions:client:SellBackCar', function()
    if cache.vehicle then
        local vehicleData = {}
        vehicleData.model = GetEntityModel(cache.vehicle)
        vehicleData.plate = GetVehicleNumberPlateText(cache.vehicle)
        local owned, balance = lib.callback.await('qbx_vehiclesales:server:checkVehicleOwner', false, vehicleData.plate)
        if owned then
            if balance < 1 then
                TriggerServerEvent('qb-occasions:server:sellVehicleBack', vehicleData)
                DeleteVehicle(cache.vehicle)
            else
                exports.qbx_core:Notify(locale('error.finish_payments'), 'error', 3500)
            end
        else
            exports.qbx_core:Notify(locale('error.not_your_vehicle'), 'error', 3500)
        end
    else
        exports.qbx_core:Notify(locale('error.not_in_veh'), 'error', 4500)
    end
end)

RegisterNetEvent('qb-occasions:client:ReturnOwnedVehicle', function(vehData)
    DoScreenFadeOut(250)
    Wait(500)
    local netId = lib.callback.await('qbx_vehiclesales:server:spawnVehicle', false, vehData, config.Zones[zone].buyVehicle, false)
    local timeout = 100
    while not NetworkDoesEntityExistWithNetworkId(netId) and timeout > 0 do
        Wait(10)
        timeout -= 1
    end
    local veh = NetToVeh(netId)
    SetEntityHeading(veh, config.Zones[zone].buyVehicle.w)
    SetVehicleFuelLevel(veh, 100)
    exports.qbx_core:Notify(locale('success.vehicle_bought'), 'success', 2500)
    Wait(500)
    DoScreenFadeIn(250)
    currentVehicle = {}
end)

RegisterNetEvent('qb-occasion:client:refreshVehicles', function()
    if zone then
        local vehicles = lib.callback.await('qb-occasions:server:getVehicles')
        despawnOccasionsVehicles()
        spawnOccasionsVehicles(vehicles)
    end
end)

AddEventHandler('qb-vehiclesales:client:SellVehicle', function()
    local VehiclePlate = qbx.getVehiclePlate(cache.vehicle)
    local owned, balance = lib.callback.await('qbx_vehiclesales:server:checkVehicleOwner', false, VehiclePlate)

    if not owned then
        return exports.qbx_core:Notify(locale('error.not_your_vehicle'), 'error', 3500)
    end

    if balance and balance > 0 then
        return exports.qbx_core:Notify(locale('error.finish_payments'), 'error', 3500)
    end

    local vehicles = lib.callback.await('qb-occasions:server:getVehicles', false)
    if not vehicles or #vehicles < #config.Zones[zone].spots then
        openSellContract(true)
    else
        exports.qbx_core:Notify(locale('error.no_space_on_lot'), 'error', 3500)
    end
end)

AddEventHandler('qb-vehiclesales:client:OpenContract', function(contract)
    currentVehicle = occasionVehicles[zone][contract]
    if not currentVehicle then
        exports.qbx_core:Notify(locale('error.not_for_sale'), 'error', 7500)
        return
    end

    local info = lib.callback.await('qb-occasions:server:getSellerInformation', false, currentVehicle.owner)
    if info then
        info.charinfo = json.decode(info.charinfo)
    else
        info = {}
        info.charinfo = {
            firstname = locale('charinfo.firstname'),
            lastname = locale('charinfo.lastname'),
            account = locale('charinfo.account'),
            phone = locale('charinfo.phone')
        }
    end

    openBuyContract(info, currentVehicle)
end)

AddEventHandler('qb-occasions:client:MainMenu', function()
    lib.registerContext({
        id = 'qb_vehiclesales_menu',
        title = config.Zones[zone].businessName,
        options = {
            {
                title =  locale('menu.sell_vehicle'),
                description = locale('menu.sell_vehicle_help'),
                event = 'qb-vehiclesales:client:SellVehicle',
            },
            {
                title =  locale('menu.sell_back'),
                description = locale('menu.sell_back_help'),
                event = 'qb-occasions:client:SellBackCar',
            },
        },
    })
    lib.showContext('qb_vehiclesales_menu')
end)

CreateThread(function()
    for k, cars in pairs(config.Zones) do
        lib.zones.box({
            coords = vec3(cars.sellVehicle.x, cars.sellVehicle.y, cars.sellVehicle.z),
            size = vec3(3.0, 4.0, 3.0),
            rotation = 0,
            debug = false,
            onEnter = function()
                if cache.vehicle then
                    lib.showTextUI(locale('menu.interaction'), {position = 'left-center'})
                end
            end,
            onExit = function()
                lib.hideTextUI()
            end,
            inside = function()
                if IsControlJustReleased(0, 38) then
                    if cache.vehicle then
                        TriggerEvent('qb-occasions:client:MainMenu')
                    else
                        exports.qbx_core:Notify(locale('error.not_in_veh'), 'error', 4500)
                    end
                end
            end
        })

        if not config.UseTarget then
            for k2, v in pairs(config.Zones[k].spots) do
                lib.zones.box({
                    coords = vec3(v.x, v.y, v.z),
                    size = vec3(4.0, 5.0, 3.0),
                    rotation = 0,
                    debug = false,
                    onEnter = function()
                        if isCarSpawned(k2) then
                            lib.showTextUI(locale('menu.view_contract_int'), {position = 'left-center'})
                        end
                    end,
                    onExit = function()
                        lib.hideTextUI()
                    end,
                    inside = function()
                        if IsControlJustReleased(0, 38) then
                            TriggerEvent('qb-vehiclesales:client:OpenContract', k2)
                        end
                    end
                })
            end
        end

        local occasionBlip = AddBlipForCoord(cars.sellVehicle.x, cars.sellVehicle.y, cars.sellVehicle.z)
        SetBlipSprite(occasionBlip, 326)
        SetBlipDisplay(occasionBlip, 4)
        SetBlipScale(occasionBlip, 0.75)
        SetBlipAsShortRange(occasionBlip, true)
        SetBlipColour(occasionBlip, 3)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(locale('info.used_vehicle_lot'))
        EndTextCommandSetBlipName(occasionBlip)
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    createZones()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    deleteZones()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if cache.resource == resourceName then
        createZones()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if cache.resource == resourceName then
        deleteZones()
        despawnOccasionsVehicles()
    end
end)
