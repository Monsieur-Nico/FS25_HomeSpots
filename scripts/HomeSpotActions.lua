---Actions: the server side of what a player asks for: save a spot, clear it, send vehicles home, park in a shed.


---Carry out an action: right away on the server (and in single player), or by asking the server from a multiplayer client
-- @param integer action HomeSpots.ACTION_*
-- @param table vehicles vehicles the action is for (empty for send all)
function HomeSpots.request(action, vehicles)
    if action ~= HomeSpots.ACTION_SEND_ALL and #vehicles == 0 then
        return
    end

    if g_currentMission:getIsServer() then
        HomeSpots.runRequest(action, vehicles, g_currentMission:getFarmId(), nil)
    else
        g_client:getServerConnection():sendEvent(HomeSpotRequestEvent.new(action, vehicles))
    end
end


---Server: carry out an action for a player, only on vehicles of that player's farm
-- @param integer action HomeSpots.ACTION_*
-- @param table vehicles vehicles the action is for (empty for send all)
-- @param integer farmId farm of the player who asked
-- @param table connection connection of the player who asked, nil for the local player
function HomeSpots.runRequest(action, vehicles, farmId, connection)
    local options = {isAutomatic = false, isTargeted = action ~= HomeSpots.ACTION_SEND_ALL, farmId = farmId, connection = connection}

    if action == HomeSpots.ACTION_SEND_ALL then
        HomeSpots.sendHome(g_currentMission.vehicleSystem.vehicles, options)
        return
    end

    local farmVehicles = {}
    for _, vehicle in ipairs(vehicles) do
        if HomeSpots.canHaveHomeSpot(vehicle) and vehicle:getOwnerFarmId() == farmId then
            table.insert(farmVehicles, vehicle)
        end
    end

    if action == HomeSpots.ACTION_SEND then
        if #farmVehicles > 0 then
            HomeSpots.sendHome(farmVehicles, options)
        end
    elseif action == HomeSpots.ACTION_SET then
        HomeSpots.setSpots(farmVehicles, connection)
    elseif action == HomeSpots.ACTION_CLEAR then
        HomeSpots.clearSpots(farmVehicles, connection)
    elseif action == HomeSpots.ACTION_FIND_SHED then
        HomeSpots.parkInShed(farmVehicles, options)
    end
end


---Server: save the current position of vehicles as their home spots and tell every player
-- @param table vehicles vehicles
-- @param table connection connection of the player who asked, nil for the local player
function HomeSpots.setSpots(vehicles, connection)
    local changes = {}
    for _, vehicle in ipairs(vehicles) do
        table.insert(changes, {vehicle = vehicle, components = HomeSpots.store:set(vehicle)})
    end

    if #changes > 0 then
        HomeSpots.onSpotsChanged(changes)

        local report = HomeSpots.newReport(HomeSpots.REPORT_SAVED)
        report.vehicles = vehicles
        HomeSpots.deliverReport(report, connection)
    end
end


---Server: give vehicles a home spot in the nearest shed with room, tell every player, then send them there
-- @param table vehicles vehicles of the farm of the player who asked
-- @param table options send options, see HomeSpots.sendHome
function HomeSpots.parkInShed(vehicles, options)
    if #vehicles == 0 then
        return
    end

    local places = HomeSpotShed.findPlaces(vehicles, options.farmId)
    if #places == 0 then
        HomeSpots.deliverReport(HomeSpots.newReport(HomeSpots.REPORT_NO_SHED), options.connection)
        return
    end

    local isPlaced = {}
    for _, place in ipairs(places) do
        HomeSpots.store:setByKey(HomeSpots.store:getKey(place.vehicle), place.components)
        isPlaced[place.vehicle] = true
    end
    HomeSpots.onSpotsChanged(places)

    local report = HomeSpots.newReport(HomeSpots.REPORT_SHED_SAVED)
    for _, vehicle in ipairs(vehicles) do
        table.insert(isPlaced[vehicle] and report.vehicles or report.blocked, vehicle)
    end
    HomeSpots.deliverReport(report, options.connection)

    HomeSpots.sendHome(report.vehicles, options)
end


---Server: delete the home spots of vehicles and tell every player
-- @param table vehicles vehicles
-- @param table connection connection of the player who asked, nil for the local player
function HomeSpots.clearSpots(vehicles, connection)
    local changes = {}
    local removed = {}
    for _, vehicle in ipairs(vehicles) do
        if HomeSpots.store:remove(vehicle) then
            table.insert(changes, {vehicle = vehicle, components = nil})
            table.insert(removed, vehicle)
        end
    end

    if #removed > 0 then
        HomeSpots.onSpotsChanged(changes)

        local report = HomeSpots.newReport(HomeSpots.REPORT_CLEARED)
        report.vehicles = removed
        HomeSpots.deliverReport(report, connection)
    end
end
