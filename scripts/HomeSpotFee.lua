---Realism fee: an optional charge for each vehicle sent home, per km of the way back, as if a worker had driven it there
HomeSpotFee = {}

-- Price per km at each fee level, before the economy difficulty. A base-game worker on a drive-to job costs 0.0004 per ms,
-- 1,440 an hour; at about 40 km/h on roads a quarter longer than the straight line home, that is about 45 per km,
-- which Normal rounds up to 50.
HomeSpotFee.PRICE_PER_KM = {
    [HomeSpotStore.FEE_OFF] = 0,
    [HomeSpotStore.FEE_LOW] = 25,
    [HomeSpotStore.FEE_NORMAL] = 50,
    [HomeSpotStore.FEE_HIGH] = 100,
}


---Returns the price per km for a fee level, scaled by the economy difficulty like the game scales worker wages
-- @param integer feeLevel HomeSpotStore.FEE_*
-- @return float price per km
function HomeSpotFee.getPricePerKm(feeLevel)
    return (HomeSpotFee.PRICE_PER_KM[feeLevel] or 0) * EconomyManager.getCostMultiplier()
end


---Set the fee of each move: its distance home times the price per km.
-- A tool hooked to a vehicle that is sent home too rides along for free.
-- Call this before the vehicles are unhooked.
-- @param table moves moves (vehicle, components)
-- @param integer feeLevel HomeSpotStore.FEE_*
function HomeSpotFee.priceMoves(moves, feeLevel)
    local pricePerKm = HomeSpotFee.getPricePerKm(feeLevel)

    local isMoving = {}
    for _, move in ipairs(moves) do
        isMoving[move.vehicle] = true
    end

    for _, move in ipairs(moves) do
        local attacherVehicle = move.vehicle.getAttacherVehicle ~= nil and move.vehicle:getAttacherVehicle() or nil

        if attacherVehicle ~= nil and isMoving[attacherVehicle] then
            move.fee = 0
        else
            move.fee = HomeSpots.getDistanceToHome(move.vehicle, move.components) / 1000 * pricePerKm
        end
    end
end


---Returns what each farm pays for a list of priced moves, rounded to whole money; farms that pay nothing are left out
-- @param table moves priced moves
-- @return table fees farm id to amount
function HomeSpotFee.getFarmFees(moves)
    local fees = {}
    for _, move in ipairs(moves) do
        local farmId = move.vehicle:getOwnerFarmId()
        fees[farmId] = (fees[farmId] or 0) + (move.fee or 0)
    end

    for farmId, amount in pairs(fees) do
        fees[farmId] = math.floor(amount + 0.5)
        if fees[farmId] <= 0 then
            fees[farmId] = nil
        end
    end

    return fees
end


---Returns true if a farm has the money for a fee
-- @param integer farmId farm id
-- @param float amount fee
-- @return boolean canAfford
function HomeSpotFee.getCanAfford(farmId, amount)
    local farm = g_farmManager:getFarmById(farmId)

    return amount <= 0 or farm == nil or farm:getBalance() >= amount
end


---Server: take the fees from the farms' money, booked as wages
-- @param table fees farm id to amount
function HomeSpotFee.charge(fees)
    for farmId, amount in pairs(fees) do
        g_currentMission:addMoney(-amount, farmId, MoneyType.AI, true)
    end
end
