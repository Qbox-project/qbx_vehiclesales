local VEHICLES = exports.qbx_core:GetVehiclesByName()

local function generateOID()
    local num = math.random(1, 10) .. math.random(111, 999)
    return 'OC' .. num
end

lib.callback.register('qb-occasions:server:getVehicles', function()
    local result = MySQL.query.await('SELECT * FROM occasion_vehicles')
    if result[1] then
        return result
    end
end)

lib.callback.register('qb-occasions:server:getSellerInformation', function(_, citizenId)
    local result = MySQL.query.await('SELECT * FROM players WHERE citizenid = ?', {citizenId})
    if result[1] then
        return result[1]
    end
end)

lib.callback.register('qb-vehiclesales:server:CheckModelName', function(_, plate)
    if plate then
        return MySQL.scalar.await('SELECT vehicle FROM player_vehicles WHERE plate = ?', {plate})
    end
end)

lib.callback.register('qbx_vehiclesales:server:spawnVehicle', function (source, vehicle, coords, warp)
    local vehmods = json.decode(vehicle.mods)
    local netId, veh = qbx.spawnVehicle({model = vehicle.model, spawnSource = coords, warp = warp, props = vehmods})
    if not veh or veh == 0 then return end
    
    SetVehicleNumberPlateText(veh, vehicle.plate)
    TriggerClientEvent('vehiclekeys:client:SetOwner', source, vehicle.plate)
    return netId
end)

lib.callback.register('qbx_vehiclesales:server:checkVehicleOwner', function(source, plate)
    local player = exports.qbx_core:GetPlayer(source)
    local result = MySQL.single.await('SELECT * FROM player_vehicles WHERE plate = ? AND citizenid = ?', {plate, player.PlayerData.citizenid})

    if result and result.id then
        local financeRow = MySQL.single.await('SELECT * FROM vehicle_financing WHERE vehicleId = ?', {result.id})
        return true, financeRow?.balance or 0
    end

    return false
end)

RegisterNetEvent('qb-occasions:server:ReturnVehicle', function(vehicleData)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    local result = MySQL.query.await('SELECT * FROM occasion_vehicles WHERE plate = ? AND occasionid = ?', {vehicleData.plate, vehicleData.oid})

    if not result[1] then
        exports.qbx_core:Notify(src, locale('error.vehicle_does_not_exist'), 'error', 3500)
        return
    end

    if result[1].seller ~= player.PlayerData.citizenid then
        exports.qbx_core:Notify(src, locale('error.not_your_vehicle'), 'error', 3500)
        return
    end

    MySQL.insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {player.PlayerData.license, player.PlayerData.citizenid, vehicleData.model, joaat(vehicleData.model), vehicleData.mods, vehicleData.plate, 0})
    MySQL.query('DELETE FROM occasion_vehicles WHERE occasionid = ? AND plate = ?', {vehicleData.oid, vehicleData.plate})
    TriggerClientEvent('qb-occasions:client:ReturnOwnedVehicle', src, result[1])
    TriggerClientEvent('qb-occasion:client:refreshVehicles', -1)
end)

RegisterNetEvent('qb-occasions:server:sellVehicle', function(vehiclePrice, vehicleData)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    MySQL.query('DELETE FROM player_vehicles WHERE plate = ? AND vehicle = ?',{vehicleData.plate, vehicleData.model})
    MySQL.insert('INSERT INTO occasion_vehicles (seller, price, description, plate, model, mods, occasionid) VALUES (?, ?, ?, ?, ?, ?, ?)',{player.PlayerData.citizenid, vehiclePrice, vehicleData.desc, vehicleData.plate, vehicleData.model,json.encode(vehicleData.mods), generateOID()})
    TriggerEvent('qb-log:server:CreateLog', 'vehicleshop', 'Vehicle for Sale', 'red','**' .. GetPlayerName(src) .. '** has a ' .. vehicleData.model .. ' priced at ' .. vehiclePrice)
    TriggerClientEvent('qb-occasion:client:refreshVehicles', -1)
end)

---@param model number
---@return number price defaults to 0
local function getVehPrice(model)
    for _, v in pairs(VEHICLES) do
        if v.hash == model then
            return tonumber(v.price)
        end
    end
    return 0
end

RegisterNetEvent('qb-occasions:server:sellVehicleBack', function(vehData)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    local plate = vehData.plate
    local price = getVehPrice(vehData.model)
    local payout = math.floor(price * 0.5) -- This will give you half of the cars value
    local success = MySQL.query.await('DELETE FROM player_vehicles WHERE plate = ? AND citizenid = ?', {plate, player.PlayerData.citizenid})
    if success and success.affectedRows > 0 then -- only pay out after we delete the vehicle
        player.Functions.AddMoney('bank', payout)
        exports.qbx_core:Notify(src, (locale('success.sold_car_for_price'):format(payout)), 'success', 5500)
    end
end)

RegisterNetEvent('qb-occasions:server:buyVehicle', function(vehicleData)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    local result = MySQL.query.await('SELECT * FROM occasion_vehicles WHERE plate = ? AND occasionid = ?',{vehicleData.plate, vehicleData.oid})
    if not result[1] or not next(result[1]) then return end
    if player.PlayerData.money.bank < result[1].price then
        exports.qbx_core:Notify(src, locale('error.not_enough_money'), 'error', 3500)
        return
    end

    local sellerCitizenId = result[1].seller
    local sellerData = exports.qbx_core:GetPlayerByCitizenId(sellerCitizenId)
    local newPrice = math.ceil((result[1].price / 100) * 77)
    player.Functions.RemoveMoney('bank', result[1].price)
    MySQL.insert(
        'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            player.PlayerData.license,
            player.PlayerData.citizenid, result[1].model,
            GetHashKey(result[1].model),
            result[1].mods,
            result[1].plate,
            0
        })
    if sellerData then
        sellerData.Functions.AddMoney('bank', newPrice)
    else
        local buyerData = MySQL.query.await('SELECT * FROM players WHERE citizenid = ?',{sellerCitizenId})
        if buyerData[1] then
            local buyerMoney = json.decode(buyerData[1].money)
            buyerMoney.bank = buyerMoney.bank + newPrice
            MySQL.update('UPDATE players SET money = ? WHERE citizenid = ?', {json.encode(buyerMoney), sellerCitizenId})
        end
    end
    TriggerEvent('qb-log:server:CreateLog', 'vehicleshop', 'bought', 'green', '**' .. GetPlayerName(src) .. '** has bought for ' .. result[1].price .. ' (' .. result[1].plate ..') from **' .. sellerCitizenId .. '**')
    TriggerClientEvent('qb-occasions:client:BuyFinished', src, result[1])
    TriggerClientEvent('qb-occasion:client:refreshVehicles', -1)
    MySQL.query('DELETE FROM occasion_vehicles WHERE plate = ? AND occasionid = ?',{result[1].plate, result[1].occasionid})
    TriggerEvent('qb-phone:server:sendNewMailToOffline', sellerCitizenId, {
        sender = locale('mail.sender'),
        subject = locale('mail.subject'),
        message = (locale('mail.message'):format(newPrice, VEHICLES[result[1].model].name))
    })
end)
