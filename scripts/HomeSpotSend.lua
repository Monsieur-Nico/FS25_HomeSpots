---Sending home: where a vehicle's home spot is, how far off it stands, and moving vehicles and their tools there.


---Pose the helper node like the vehicle's root node would be at its home spot and return the footprint there
-- @param table vehicle vehicle
-- @param table components saved component positions
-- @return table area footprint
function HomeSpots.getHomeArea(vehicle, components)
    local position, rotation = components[1][1], components[1][2]

    setTranslation(HomeSpots.helperNode, position[1], position[2], position[3])
    setRotation(HomeSpots.helperNode, rotation[1], rotation[2], rotation[3])

    return HomeSpotArea.newFromNode(vehicle.size, HomeSpots.helperNode)
end


---Compare where a vehicle stands with its home spot
-- @param table vehicle vehicle
-- @param table components saved component positions
-- @return boolean isAtHome true within AT_HOME_DISTANCE and AT_HOME_ANGLE of the spot
-- @return table homeArea footprint at the home spot
-- @return table currentArea footprint where the vehicle stands now
function HomeSpots.getHomePose(vehicle, components)
    local homeArea = HomeSpots.getHomeArea(vehicle, components)
    local currentArea = HomeSpotArea.newFromNode(vehicle.size, vehicle.rootNode)
    local isAtHome = HomeSpotArea.getIsSamePose(homeArea, currentArea, HomeSpots.AT_HOME_DISTANCE, HomeSpots.AT_HOME_ANGLE)

    return isAtHome, homeArea, currentArea
end


---Returns the distance on the ground between a vehicle and its home spot
-- @param table vehicle vehicle
-- @param table components saved component positions
-- @return float distance in m
function HomeSpots.getDistanceToHome(vehicle, components)
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local home = components[1][1]

    return MathUtil.vector2Length(x - home[1], z - home[3])
end


---Returns true if the vehicle has a home spot and stands on it
-- @param table vehicle vehicle
-- @return boolean isAtHome
function HomeSpots.getIsAtHome(vehicle)
    local components = HomeSpots.store:get(vehicle)
    if components == nil or HomeSpots.helperNode == nil or #components ~= #vehicle.components then
        return false
    end

    return (HomeSpots.getHomePose(vehicle, components))
end


---Split the moves into those whose home spot is free and those whose spot is taken.
-- A blocked vehicle stays where it is, so it can in turn block another spot; repeat until nothing changes.
-- @param table moves candidate moves (vehicle, components, homeArea, currentArea)
-- @param table staticAreas footprints of vehicles that stay where they are
-- @return table accepted moves that can go ahead
-- @return table blocked moves left in place
function HomeSpots.resolveBlockedSpots(moves, staticAreas)
    local accepted = moves
    local blocked = {}
    local hasChanged = true

    while hasChanged do
        hasChanged = false

        local placedAreas = {}
        local stillAccepted = {}

        for _, move in ipairs(accepted) do
            if HomeSpotArea.getOverlapsAny(move.homeArea, staticAreas) or HomeSpotArea.getOverlapsAny(move.homeArea, placedAreas) then
                table.insert(blocked, move)
                table.insert(staticAreas, move.currentArea)
                hasChanged = true
            else
                table.insert(placedAreas, move.homeArea)
                table.insert(stillAccepted, move)
            end
        end

        accepted = stillAccepted
    end

    return accepted, blocked
end


---Server: send every farm's vehicles and tools home, at the daily send-home time
function HomeSpots.sendAllHome()
    HomeSpots.sendHome(g_currentMission.vehicleSystem.vehicles, {isAutomatic = true, isTargeted = false})
end


---Server: send vehicles to their home spots.
-- Vehicles are unhooked this frame and moved on the next update, once the detach has settled.
-- Tools without a home spot are unhooked and left where they are. A vehicle whose spot is taken, or runs into a wall,
-- goes to the nearest free space beside it, or stays put when there is none.
-- With the realism fee on, a player's own request goes ahead only if their farm can pay for it.
-- @param table vehicles vehicles to send home, those without a home spot are skipped
-- @param table options isAutomatic (daily send-home time), isTargeted (the player picked these vehicles, the report names them),
--   farmId (only this farm's vehicles, nil for every farm), connection (player who asked, nil for the local player)
function HomeSpots.sendHome(vehicles, options)
    if HomeSpots.pendingMoves ~= nil then
        return
    end

    local candidates = {}
    local isMoving = {}
    local numBusy = 0
    local atHome = {}

    for _, vehicle in ipairs(vehicles) do
        local components = HomeSpots.store:get(vehicle)

        if components ~= nil and (options.farmId == nil or vehicle:getOwnerFarmId() == options.farmId) and HomeSpots.canHaveHomeSpot(vehicle) then
            if HomeSpots.getIsBusy(vehicle, options) then
                numBusy = numBusy + 1
            elseif #components == #vehicle.components then
                local isAtHome, homeArea, currentArea = HomeSpots.getHomePose(vehicle, components)

                if isAtHome then
                    table.insert(atHome, vehicle)
                else
                    table.insert(candidates, {
                        vehicle = vehicle,
                        components = components,
                        homeArea = homeArea,
                        currentArea = currentArea
                    })
                    isMoving[vehicle] = true
                end
            end
        end
    end

    if #candidates == 0 and numBusy == 0 and #atHome == 0 then
        if not options.isAutomatic and not options.isTargeted then
            HomeSpots.deliverReport(HomeSpots.newReport(HomeSpots.REPORT_NOTHING), options.connection)
        end
        return
    end

    local staticAreas = {}
    for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
        if not isMoving[vehicle] and vehicle.size ~= nil and vehicle.rootNode ~= nil then
            table.insert(staticAreas, HomeSpotArea.newFromNode(vehicle.size, vehicle.rootNode))
        end
    end

    local walled
    candidates, walled = HomeSpotShed.splitWalledSpots(candidates)
    for _, move in ipairs(walled) do
        table.insert(staticAreas, move.currentArea)
    end

    local accepted, blocked = HomeSpots.resolveBlockedSpots(candidates, staticAreas)
    for _, move in ipairs(walled) do
        table.insert(blocked, move)
    end

    local placed
    placed, blocked = HomeSpotNearby.placeBlocked(blocked, accepted, staticAreas)

    local nearby = {}
    for _, move in ipairs(placed) do
        table.insert(accepted, move)
        if move.isNearby then
            table.insert(nearby, move)
        end
    end

    HomeSpotFee.priceMoves(accepted, HomeSpots.store.feeLevel)
    if not options.isAutomatic and options.farmId ~= nil then
        local fee = HomeSpotFee.getFarmFees(accepted)[options.farmId] or 0

        if not HomeSpotFee.getCanAfford(options.farmId, fee) then
            local report = HomeSpots.newReport(HomeSpots.REPORT_NO_MONEY)
            report.fees[options.farmId] = fee
            HomeSpots.deliverReport(report, options.connection)
            return
        end
    end

    for _, move in ipairs(accepted) do
        HomeSpots.detachFromCombination(move.vehicle)
    end

    HomeSpots.pendingMoves = accepted
    local report = HomeSpots.newReport(HomeSpots.REPORT_SENT)
    report.isAutomatic = options.isAutomatic
    report.isTargeted = options.isTargeted
    report.numBusy = numBusy
    report.atHome = atHome
    report.blocked = HomeSpots.getMovedVehicles(blocked)
    report.nearby = HomeSpots.getMovedVehicles(nearby)
    report.connection = options.connection
    HomeSpots.pendingReport = report
end


---Unhook a vehicle from whatever pulls it, and unhook every tool attached to it
-- @param table vehicle vehicle
function HomeSpots.detachFromCombination(vehicle)
    if vehicle.getAttacherVehicle ~= nil then
        local attacherVehicle = vehicle:getAttacherVehicle()
        if attacherVehicle ~= nil then
            attacherVehicle:detachImplementByObject(vehicle)
        end
    end

    if vehicle.getAttachedImplements ~= nil then
        local implements = {}
        for _, implement in ipairs(vehicle:getAttachedImplements()) do
            table.insert(implements, implement.object)
        end

        for _, object in ipairs(implements) do
            vehicle:detachImplementByObject(object)
        end
    end
end


---Move a vehicle to its home spot
-- @param table vehicle vehicle
-- @param table components saved component positions
-- @return boolean moved
function HomeSpots.moveToHomeSpot(vehicle, components)
    if vehicle.isDeleted or #components ~= #vehicle.components then
        return false
    end

    vehicle:removeFromPhysics()
    vehicle:setAbsolutePosition(0, 0, 0, 0, 0, 0, components)
    vehicle:addToPhysics()

    return true
end


---Returns a short list of vehicle names, e.g. "Fendt 942, Lemken Juwel +2"
-- @param table vehicles vehicles
-- @param integer maxListed most names to write out, the rest is counted
-- @return string names
function HomeSpots.getVehicleNames(vehicles, maxListed)
    local names = {}

    for i = 1, math.min(#vehicles, maxListed) do
        table.insert(names, vehicles[i]:getFullName())
    end

    local text = table.concat(names, ", ")
    if #vehicles > maxListed then
        text = string.format("%s +%d", text, #vehicles - maxListed)
    end

    return text
end


---Returns the vehicles of a list of moves
-- @param table moves moves
-- @return table vehicles
function HomeSpots.getMovedVehicles(moves)
    local vehicles = {}
    for _, move in ipairs(moves) do
        table.insert(vehicles, move.vehicle)
    end

    return vehicles
end


---Carry out moves queued by the send-home action and report what happened
function HomeSpots.processPendingMoves()
    local moves = HomeSpots.pendingMoves
    if moves == nil then
        return
    end

    HomeSpots.pendingMoves = nil

    local movedMoves = {}
    for _, move in ipairs(moves) do
        if HomeSpots.moveToHomeSpot(move.vehicle, move.components) then
            table.insert(movedMoves, move)
        end
    end

    local fees = HomeSpotFee.getFarmFees(movedMoves)
    HomeSpotFee.charge(fees)

    local report = HomeSpots.pendingReport
    HomeSpots.pendingReport = nil
    report.vehicles = HomeSpots.getMovedVehicles(movedMoves)
    report.fees = fees

    HomeSpots.deliverReport(report, report.connection)
end
