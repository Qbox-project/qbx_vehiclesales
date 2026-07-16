local config = require 'config.client'
local VEHICLES = exports.qbx_core:GetVehiclesByName()
local listingLocks = {}
local saleLocks = {}
local pendingSpawns = {}

local function generateOID()
    local oid
    repeat
        oid = 'OC' .. math.random(1, 10) .. math.random(111, 999)
    until not MySQL.scalar.await('SELECT 1 FROM occasion_vehicles WHERE occasionid = ?', {oid})
    return oid
end

local function getNearbyZone(source, maxDistance)
    local ped = GetPlayerPed(source)
    if ped == 0 then return end

    local coords = GetEntityCoords(ped)
    for name, zone in pairs(config.zones) do
        if #(coords - zone.sellVehicle.xyz) <= maxDistance then return name, zone end
    end
end

local function createOwnedVehicle(player, listing)
    return MySQL.insert.await('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        player.PlayerData.license,
        player.PlayerData.citizenid,
        listing.model,
        joaat(listing.model),
        listing.mods,
        listing.plate,
        0,
    })
end

local function authorizeSpawn(source, listing, coords)
    pendingSpawns[source] = {
        model = listing.model,
        mods = listing.mods,
        plate = listing.plate,
        coords = coords,
        expiresAt = os.time() + 30,
    }
end

lib.callback.register('qb-occasions:server:getVehicles', function()
    return MySQL.query.await('SELECT * FROM occasion_vehicles')
end)

lib.callback.register('qb-occasions:server:getSellerInformation', function(_, citizenId)
    if type(citizenId) ~= 'string' or #citizenId > 64 then return end
    local charinfo = MySQL.scalar.await('SELECT charinfo FROM players WHERE citizenid = ?', {citizenId})
    return charinfo and {charinfo = charinfo}
end)

lib.callback.register('qb-vehiclesales:server:CheckModelName', function(_, plate)
    if type(plate) ~= 'string' then return end
    return MySQL.scalar.await('SELECT vehicle FROM player_vehicles WHERE plate = ?', {qbx.string.trim(plate)})
end)

lib.callback.register('qbx_vehiclesales:server:spawnVehicle', function(source)
    local spawn = pendingSpawns[source]
    if not spawn or os.time() > spawn.expiresAt then
        pendingSpawns[source] = nil
        return
    end

    local _, zone = getNearbyZone(source, 150.0)
    if not zone or #(spawn.coords.xyz - zone.buyVehicle.xyz) > 1.0 then return end

    pendingSpawns[source] = nil
    local props = json.decode(spawn.mods) or {}
    local netId, vehicle = qbx.spawnVehicle({model = spawn.model, spawnSource = spawn.coords, props = props})
    if not vehicle or vehicle == 0 then return end

    SetVehicleNumberPlateText(vehicle, spawn.plate)
    TriggerClientEvent('vehiclekeys:client:SetOwner', source, spawn.plate)
    return netId
end)

lib.callback.register('qbx_vehiclesales:server:checkVehicleOwner', function(source, plate)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or type(plate) ~= 'string' then return false end

    local result = MySQL.single.await('SELECT id FROM player_vehicles WHERE plate = ? AND citizenid = ?', {qbx.string.trim(plate), player.PlayerData.citizenid})
    if not result then return false end

    local balance = MySQL.scalar.await('SELECT balance FROM vehicle_financing WHERE vehicleId = ?', {result.id})
    return true, balance or 0
end)

RegisterNetEvent('qb-occasions:server:ReturnVehicle', function(vehicleData)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    local _, zone = getNearbyZone(src, 150.0)
    if not player or not zone or type(vehicleData) ~= 'table' then return end

    local listing = MySQL.single.await('SELECT * FROM occasion_vehicles WHERE plate = ? AND occasionid = ?', {vehicleData.plate, vehicleData.oid})
    if not listing then
        exports.qbx_core:Notify(src, locale('error.vehicle_does_not_exist'), 'error', 3500)
        return
    end
    if listing.seller ~= player.PlayerData.citizenid then
        exports.qbx_core:Notify(src, locale('error.not_your_vehicle'), 'error', 3500)
        return
    end

    local deleted = MySQL.update.await('DELETE FROM occasion_vehicles WHERE id = ? AND seller = ?', {listing.id, player.PlayerData.citizenid})
    if deleted ~= 1 or not createOwnedVehicle(player, listing) then return end

    authorizeSpawn(src, listing, zone.buyVehicle)
    TriggerClientEvent('qb-occasions:client:ReturnOwnedVehicle', src, listing)
    TriggerClientEvent('qb-occasion:client:refreshVehicles', -1)
end)

RegisterNetEvent('qb-occasions:server:sellVehicle', function(vehiclePrice, vehicleData)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    local _, zone = getNearbyZone(src, 12.0)
    if not player or not zone or type(vehicleData) ~= 'table' then return end

    local price = tonumber(vehiclePrice)
    if not price or math.type(price) ~= 'integer' or price < 1 or price > 100000000 then return end
    local description = type(vehicleData.desc) == 'string' and vehicleData.desc:sub(1, 500) or ''
    local plate = type(vehicleData.plate) == 'string' and qbx.string.trim(vehicleData.plate)
    if not plate then return end

    local ped = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped or qbx.getVehiclePlate(vehicle) ~= plate then return end

    local owned = MySQL.single.await('SELECT id, vehicle, mods, plate FROM player_vehicles WHERE plate = ? AND citizenid = ?', {plate, player.PlayerData.citizenid})
    if not owned or saleLocks[owned.id] then return end
    saleLocks[owned.id] = src
    if MySQL.scalar.await('SELECT 1 FROM vehicle_financing WHERE vehicleId = ? AND balance > 0', {owned.id}) then
        saleLocks[owned.id] = nil
        return
    end

    local success = MySQL.transaction.await({
        {
            query = 'DELETE FROM player_vehicles WHERE id = ? AND citizenid = ?',
            values = {owned.id, player.PlayerData.citizenid},
        },
        {
            query = 'INSERT INTO occasion_vehicles (seller, price, description, plate, model, mods, occasionid) VALUES (?, ?, ?, ?, ?, ?, ?)',
            values = {player.PlayerData.citizenid, price, description, owned.plate, owned.vehicle, owned.mods, generateOID()},
        },
    })
    saleLocks[owned.id] = nil
    if not success then return end

    TriggerEvent('qb-log:server:CreateLog', 'vehicleshop', 'Vehicle for Sale', 'red', ('**%s** listed %s for %s'):format(GetPlayerName(src), owned.vehicle, price))
    TriggerClientEvent('qb-occasion:client:refreshVehicles', -1)
end)

local function getVehPrice(model)
    return tonumber(VEHICLES[model]?.price) or 0
end

RegisterNetEvent('qb-occasions:server:sellVehicleBack', function(vehData)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    local _, zone = getNearbyZone(src, 12.0)
    if not player or not zone or type(vehData) ~= 'table' or type(vehData.plate) ~= 'string' then return end

    local plate = qbx.string.trim(vehData.plate)
    local owned = MySQL.single.await('SELECT id, vehicle FROM player_vehicles WHERE plate = ? AND citizenid = ?', {plate, player.PlayerData.citizenid})
    if not owned or MySQL.scalar.await('SELECT 1 FROM vehicle_financing WHERE vehicleId = ? AND balance > 0', {owned.id}) then return end

    local payout = math.floor(getVehPrice(owned.vehicle) * 0.5)
    if payout <= 0 then return end

    local deleted = MySQL.update.await('DELETE FROM player_vehicles WHERE id = ? AND citizenid = ?', {owned.id, player.PlayerData.citizenid})
    if deleted ~= 1 then return end

    player.Functions.AddMoney('bank', payout)
    exports.qbx_core:Notify(src, locale('success.sold_car_for_price'):format(payout), 'success', 5500)
end)

RegisterNetEvent('qb-occasions:server:buyVehicle', function(vehicleData)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    local _, zone = getNearbyZone(src, 150.0)
    if not player or not zone or type(vehicleData) ~= 'table' then return end

    local listing = MySQL.single.await('SELECT * FROM occasion_vehicles WHERE plate = ? AND occasionid = ?', {vehicleData.plate, vehicleData.oid})
    if not listing or listingLocks[listing.id] then return end
    listingLocks[listing.id] = src

    if player.PlayerData.money.bank < listing.price or not player.Functions.RemoveMoney('bank', listing.price) then
        listingLocks[listing.id] = nil
        exports.qbx_core:Notify(src, locale('error.not_enough_money'), 'error', 3500)
        return
    end

    local deleted = MySQL.update.await('DELETE FROM occasion_vehicles WHERE id = ?', {listing.id})
    if deleted ~= 1 or not createOwnedVehicle(player, listing) then
        player.Functions.AddMoney('bank', listing.price, 'occasion-purchase-refund')
        listingLocks[listing.id] = nil
        return
    end

    listingLocks[listing.id] = nil
    local sellerAmount = math.ceil(listing.price * 0.77)
    local seller = exports.qbx_core:GetPlayerByCitizenId(listing.seller)
    if seller then
        seller.Functions.AddMoney('bank', sellerAmount)
    else
        local sellerMoneyJson = MySQL.scalar.await('SELECT money FROM players WHERE citizenid = ?', {listing.seller})
        if sellerMoneyJson then
            local sellerMoney = json.decode(sellerMoneyJson)
            sellerMoney.bank += sellerAmount
            MySQL.update.await('UPDATE players SET money = ? WHERE citizenid = ?', {json.encode(sellerMoney), listing.seller})
        end
    end

    authorizeSpawn(src, listing, zone.buyVehicle)
    TriggerEvent('qb-log:server:CreateLog', 'vehicleshop', 'bought', 'green', ('**%s** bought %s for %s from **%s**'):format(GetPlayerName(src), listing.plate, listing.price, listing.seller))
    TriggerClientEvent('qb-occasions:client:BuyFinished', src, listing)
    TriggerClientEvent('qb-occasion:client:refreshVehicles', -1)
    TriggerEvent('qb-phone:server:sendNewMailToOffline', listing.seller, {
        sender = locale('mail.sender'),
        subject = locale('mail.subject'),
        message = locale('mail.message'):format(sellerAmount, VEHICLES[listing.model]?.name or listing.model),
    })
end)

AddEventHandler('playerDropped', function()
    pendingSpawns[source] = nil
end)
