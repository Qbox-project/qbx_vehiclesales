local QBCore = exports['qb-core']:GetCoreObject()

-- Functions
local function generateOID()
    local num = math.random(1, 10) .. math.random(111, 999)

    return "OC" .. num
end

-- Callbacks
QBCore.Functions.CreateCallback('qb-occasions:server:getVehicles', function(_, cb)
    local result = MySQL.query.await('SELECT * FROM occasion_vehicles')

    if result[1] then
        cb(result)
    else
        cb(nil)
    end
end)

QBCore.Functions.CreateCallback("qb-occasions:server:getSellerInformation", function(_, cb, citizenid)
    MySQL.single('SELECT * FROM players WHERE citizenid = ?', {
        citizenid
    }, function(result)
        if result then
            cb(result)
        else
            cb(nil)
        end
    end)
end)

QBCore.Functions.CreateCallback("qb-vehiclesales:server:CheckModelName", function(_, cb, plate)
    if plate then
        local ReturnData = MySQL.scalar.await("SELECT vehicle FROM player_vehicles WHERE plate = ?", {
            plate
        })

        cb(ReturnData)
    end
end)

-- Events
RegisterNetEvent('qb-occasions:server:ReturnVehicle', function(vehicleData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local result = MySQL.single.await('SELECT * FROM occasion_vehicles WHERE plate = ? AND occasionid = ?', {
        vehicleData.plate,
        vehicleData.oid
    })

    if result then
        if result.seller == Player.PlayerData.citizenid then
            MySQL.insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
                Player.PlayerData.license,
                Player.PlayerData.citizenid,
                vehicleData.model,
                joaat(vehicleData.model),
                vehicleData.mods,
                vehicleData.plate,
                0
            })
            MySQL.query('DELETE FROM occasion_vehicles WHERE occasionid = ? AND plate = ?', {
                vehicleData.oid,
                vehicleData.plate
            })

            TriggerClientEvent("qb-occasions:client:ReturnOwnedVehicle", src, result)
            TriggerClientEvent('qb-occasion:client:refreshVehicles', -1)
        else
            TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_your_vehicle'), 'error', 3500)
        end
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.vehicle_does_not_exist'), 'error', 3500)
    end
end)

RegisterNetEvent('qb-occasions:server:sellVehicle', function(vehiclePrice, vehicleData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)

    MySQL.query('DELETE FROM player_vehicles WHERE plate = ? AND vehicle = ?', {
        vehicleData.plate,
        vehicleData.model
    })
    MySQL.insert('INSERT INTO occasion_vehicles (seller, price, description, plate, model, mods, occasionid) VALUES (?, ?, ?, ?, ?, ?, ?)',{Player.PlayerData.citizenid, vehiclePrice, vehicleData.desc, vehicleData.plate, vehicleData.model,json.encode(vehicleData.mods), generateOID()})

    TriggerEvent("qb-log:server:CreateLog", "vehicleshop", "Vehicle for Sale", "red", "**" .. GetPlayerName(src) .. "** has a " .. vehicleData.model .. " priced at " .. vehiclePrice)
    TriggerClientEvent('qb-occasion:client:refreshVehicles', -1)
end)

RegisterNetEvent('qb-occasions:server:sellVehicleBack', function(vehData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local price = 0
    local plate = vehData.plate

    for _, v in pairs(QBCore.Shared.Vehicles) do
        if v.hash == vehData.model then
            price = tonumber(v.price)
            break
        end
    end

    local payout = math.floor(tonumber(price * 0.5)) -- This will give you half of the cars value

    Player.Functions.AddMoney('bank', payout)

    TriggerClientEvent('QBCore:Notify', src, Lang:t('success.sold_car_for_price', { value = payout }), 'success', 5500)

    MySQL.query('DELETE FROM player_vehicles WHERE plate = ?', {
        plate
    })
end)

RegisterNetEvent('qb-occasions:server:buyVehicle', function(vehicleData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local result = MySQL.single.await('SELECT * FROM occasion_vehicles WHERE plate = ? AND occasionid = ?', {
        vehicleData.plate,
        vehicleData.oid
    })

    if result then
        if Player.PlayerData.money.bank >= result[1].price then
            local SellerCitizenId = result.seller
            local SellerData = QBCore.Functions.GetPlayerByCitizenId(SellerCitizenId)
            local NewPrice = math.ceil((result.price / 100) * 77)

            Player.Functions.RemoveMoney('bank', result.price)

            MySQL.insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
                Player.PlayerData.license,
                Player.PlayerData.citizenid, result.model,
                joaat(result.model),
                result.mods,
                result.plate,
                0
            })

            if SellerData then
                SellerData.Functions.AddMoney('bank', NewPrice)
            else
                local BuyerData = MySQL.single.await('SELECT * FROM players WHERE citizenid = ?',{SellerCitizenId})

                if BuyerData then
                    local BuyerMoney = json.decode(BuyerData.money)

                    BuyerMoney.bank = BuyerMoney.bank + NewPrice

                    MySQL.update('UPDATE players SET money = ? WHERE citizenid = ?', {
                        json.encode(BuyerMoney),
                        SellerCitizenId
                    })
                end
            end

            TriggerEvent("qb-log:server:CreateLog", "vehicleshop", "bought", "green", "**" .. GetPlayerName(src) .. "** has bought for " .. result.price .. " (" .. result.plate .. ") from **" .. SellerCitizenId .. "**")
            TriggerClientEvent("qb-occasions:client:BuyFinished", src, result)
            TriggerClientEvent('qb-occasion:client:refreshVehicles', -1)

            MySQL.query('DELETE FROM occasion_vehicles WHERE plate = ? AND occasionid = ?', {
                result.plate,
                result.occasionid
            })

            TriggerEvent('qb-phone:server:sendNewMailToOffline', SellerCitizenId, {
                sender = Lang:t('mail.sender'),
                subject = Lang:t('mail.subject'),
                message = Lang:t('mail.message', { value = NewPrice, value2 = QBCore.Shared.Vehicles[result.model].name})
            })
        else
            TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_enough_money'), 'error', 3500)
        end
    end
end)
