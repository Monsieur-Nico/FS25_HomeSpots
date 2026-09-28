---Home Spots: give each vehicle and tool a home spot, then send everything home with one key.
HomeSpots = {}
HomeSpots.MOD_NAME = g_currentModName
HomeSpots.MAX_NAMES_LISTED = 3
HomeSpots.MAX_NAMES_IN_PROMPT = 2

-- What a player can ask for, carried out by the server
HomeSpots.ACTION_SET = 1
HomeSpots.ACTION_CLEAR = 2
HomeSpots.ACTION_SEND = 3
HomeSpots.ACTION_SEND_ALL = 4
HomeSpots.ACTION_FIND_SHED = 5

-- What the player is told afterwards
HomeSpots.REPORT_SAVED = 1
HomeSpots.REPORT_CLEARED = 2
HomeSpots.REPORT_SENT = 3
HomeSpots.REPORT_NOTHING = 4
HomeSpots.REPORT_NO_MONEY = 5
HomeSpots.REPORT_SHED_SAVED = 6
HomeSpots.REPORT_NO_SHED = 7

-- A vehicle this close to its home spot (m, and heading in rad) counts as already home and is not moved
HomeSpots.AT_HOME_DISTANCE = 1.0
HomeSpots.AT_HOME_ANGLE = math.rad(10)

-- How far (m) the player on foot can be from a vehicle or tool to set its home spot
HomeSpots.LOOK_DISTANCE = 6
HomeSpots.LOOK_STEP = 0.25
HomeSpots.LOOK_MARGIN = 0.2
HomeSpots.DEFAULT_VEHICLE_HEIGHT = 4
-- Key for help entries registered without an input context name
HomeSpots.DEFAULT_INPUT_CONTEXT = "default"

HomeSpots.store = HomeSpotStore.new()
HomeSpots.hotspots = {}
HomeSpots.helperNode = nil
HomeSpots.pendingMoves = nil
HomeSpots.pendingReport = nil
-- Action event ids per input context (on foot, in a vehicle), each a table of action name to event id
HomeSpots.actionEventIds = {}
-- The object the keys of each input context are registered for. The game builds an event id from the action and
-- this object, so one shared object would give both contexts the same ids and the on-foot entries could no longer be updated.
HomeSpots.inputTargets = {}
HomeSpots.shownActionState = nil


---Server: send an event to every connected player
-- @param table event event
function HomeSpots.broadcast(event)
    if g_server ~= nil then
        g_server:broadcastEvent(event)
    end
end


---Returns a translated text with its placeholders filled in
-- @param string textName l10n text name
-- @param any ... values for the text's placeholders
-- @return string text
function HomeSpots.getText(textName, ...)
    return string.format(g_i18n:getText(textName), ...)
end


---Show a short message in the top notification area
-- @param string text text
-- @param integer notificationType notification type, OK by default
function HomeSpots.notify(text, notificationType)
    if not g_currentMission:getIsClient() then
        return
    end

    g_currentMission:addIngameNotification(notificationType or FSBaseMission.INGAME_NOTIFICATION_OK, text)
end


---Returns true if a home spot can be saved for this vehicle (trains and pallets are left out)
-- @param table vehicle vehicle
-- @return boolean canHaveSpot
function HomeSpots.canHaveHomeSpot(vehicle)
    return vehicle.components ~= nil
        and vehicle.size ~= nil
        and (not HomeSpots.store.isServer or vehicle:getUniqueId() ~= nil)
        and not vehicle.isPallet
        and vehicle.trainSystem == nil
        and vehicle.spec_locomotive == nil
end


---Returns true if a worker drives the vehicle's combination, or a player other than the one who picked it
-- @param table vehicle vehicle
-- @param table options send options, see HomeSpots.sendHome
-- @return boolean isBusy
function HomeSpots.getIsBusy(vehicle, options)
    local rootVehicle = vehicle:getRootVehicle()

    if rootVehicle.getIsAIActive ~= nil and rootVehicle:getIsAIActive() then
        return true
    end

    if rootVehicle.getIsControlled == nil or not rootVehicle:getIsControlled() then
        return false
    end

    return not (options.isTargeted and HomeSpots.getIsControlledBy(rootVehicle, options.connection))
end


---Returns true if the player who asked sits in the vehicle
-- @param table rootVehicle root vehicle of a combination
-- @param table connection connection of the player who asked, nil for the local player
-- @return boolean isControlledBy
function HomeSpots.getIsControlledBy(rootVehicle, connection)
    if connection ~= nil then
        return rootVehicle.getOwnerConnection ~= nil and rootVehicle:getOwnerConnection() == connection
    end

    local currentVehicle = g_localPlayer ~= nil and g_localPlayer:getCurrentVehicle() or nil

    return currentVehicle ~= nil and currentVehicle:getRootVehicle() == rootVehicle
end


---Returns the vehicles the set and remove keys act on: the combination the player sits in,
-- or on foot, the vehicle or tool the player is looking at
-- @return table vehicles
function HomeSpots.getTargetVehicles()
    local player = g_localPlayer
    if player == nil then
        return {}
    end

    local vehicles = {}
    local currentVehicle = player:getCurrentVehicle()

    if currentVehicle ~= nil then
        for _, childVehicle in ipairs(currentVehicle:getRootVehicle():getChildVehicles()) do
            if HomeSpots.canHaveHomeSpot(childVehicle) then
                table.insert(vehicles, childVehicle)
            end
        end
    else
        local vehicle = HomeSpots.getLookedAtVehicle(player)

        if vehicle ~= nil and HomeSpots.canHaveHomeSpot(vehicle) and vehicle:getOwnerFarmId() == g_currentMission:getFarmId() then
            table.insert(vehicles, vehicle)
        end
    end

    return vehicles
end


---Returns the vehicle a physics node belongs to, also when the node is a collision shape below a vehicle component
-- @param integer node node id
-- @return table vehicle vehicle or nil
function HomeSpots.getVehicleFromNode(node)
    local vehicleSystem = g_currentMission.vehicleSystem

    while node ~= nil and node ~= 0 and entityExists(node) do
        local vehicle = vehicleSystem:getVehicleByNodeId(node, node)
        if vehicle ~= nil then
            return vehicle
        end

        node = getParent(node)
    end

    return nil
end


---Returns the vehicle or tool the player on foot is looking at: first by a look ray against vehicle collisions,
-- then by the vehicles' outlines along the same ray, which also catches open frames like seed drills.
-- Both are worked out fresh every frame, so the result clears as soon as the player looks away.
-- @param table player player
-- @return table vehicle vehicle or nil
function HomeSpots.getLookedAtVehicle(player)
    if player.getLookRay == nil then
        return nil
    end

    local x, y, z, dirX, dirY, dirZ = player:getLookRay()
    if x == nil then
        return nil
    end

    HomeSpots.lookRayVehicle = nil
    raycastAll(x, y, z, dirX, dirY, dirZ, HomeSpots.LOOK_DISTANCE, "onLookRayHit", HomeSpots, CollisionFlag.VEHICLE)

    return HomeSpots.lookRayVehicle or HomeSpots.getVehicleAlongLookRay(x, y, z, dirX, dirY, dirZ)
end


---Returns the first vehicle of the player's farm whose outline (footprint and height) the look ray passes through.
-- Works from vehicle sizes alone, so it also finds tools whose collisions the look ray slips past.
-- A vehicle whose outline the player stands in is skipped: the ray starts inside it, so it would match wherever the player looks.
-- @param float x, y, z look ray start
-- @param float dirX, dirY, dirZ look ray direction (unit length)
-- @return table vehicle vehicle or nil
function HomeSpots.getVehicleAlongLookRay(x, y, z, dirX, dirY, dirZ)
    local farmId = g_currentMission:getFarmId()
    local nearby = {}

    for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.rootNode ~= nil and vehicle.size ~= nil and vehicle:getOwnerFarmId() == farmId and HomeSpots.canHaveHomeSpot(vehicle) then
            local area = HomeSpotArea.newFromNode(vehicle.size, vehicle.rootNode)
            local reach = HomeSpots.LOOK_DISTANCE + area.halfLength + area.halfWidth
            local dx, dz = area.x - x, area.z - z

            if dx * dx + dz * dz <= reach * reach then
                local _, rootY, _ = getWorldTranslation(vehicle.rootNode)
                local height = vehicle.size.height or HomeSpots.DEFAULT_VEHICLE_HEIGHT
                local candidate = {
                    vehicle = vehicle,
                    area = area,
                    minY = rootY - HomeSpots.LOOK_MARGIN - 1,
                    maxY = rootY + height + HomeSpots.LOOK_MARGIN
                }

                if not HomeSpots.getIsInOutline(candidate, x, y, z) then
                    table.insert(nearby, candidate)
                end
            end
        end
    end

    if #nearby == 0 then
        return nil
    end

    for distance = HomeSpots.LOOK_STEP, HomeSpots.LOOK_DISTANCE, HomeSpots.LOOK_STEP do
        local pointX, pointY, pointZ = x + dirX * distance, y + dirY * distance, z + dirZ * distance

        for _, candidate in ipairs(nearby) do
            if HomeSpots.getIsInOutline(candidate, pointX, pointY, pointZ) then
                return candidate.vehicle
            end
        end
    end

    return nil
end


---Returns true if a point lies inside a vehicle's outline: its footprint, widened by LOOK_MARGIN, between minY and maxY
-- @param table candidate outline (area, minY, maxY)
-- @param float x, y, z world position
-- @return boolean isInside
function HomeSpots.getIsInOutline(candidate, x, y, z)
    return y >= candidate.minY and y <= candidate.maxY and HomeSpotArea.getContainsPoint(candidate.area, x, z, HomeSpots.LOOK_MARGIN)
end


---Look ray callback: keep the first vehicle hit
-- @param integer hitObjectId hit physics object
-- @return boolean continue false once a vehicle is found
function HomeSpots:onLookRayHit(hitObjectId, x, y, z, distance, normalX, normalY, normalZ, subShapeIndex, shapeId)
    local vehicle = HomeSpots.getVehicleFromNode(hitObjectId) or HomeSpots.getVehicleFromNode(shapeId)
    if vehicle ~= nil then
        HomeSpots.lookRayVehicle = vehicle
        return false
    end

    return true
end


---Action: save the current position of the targeted vehicles as their home spots
function HomeSpots:onSetHomeInput()
    HomeSpots.request(HomeSpots.ACTION_SET, HomeSpots.getTargetVehicles())
end


---Action: delete the home spots of the targeted vehicles
function HomeSpots:onClearHomeInput()
    HomeSpots.request(HomeSpots.ACTION_CLEAR, HomeSpots.getTargetVehicles())
end


---Action: send every vehicle and tool of the player's farm home
function HomeSpots:onSendAllHomeInput()
    HomeSpots.request(HomeSpots.ACTION_SEND_ALL, {})
end


---Action: send only what the player sits in or looks at home
function HomeSpots:onSendTargetHomeInput()
    HomeSpots.request(HomeSpots.ACTION_SEND, HomeSpots.getTargetVehicles())
end


---Action: give what the player sits in or looks at a home spot in a shed, and send it there
function HomeSpots:onFindShedInput()
    HomeSpots.request(HomeSpots.ACTION_FIND_SHED, HomeSpots.getTargetVehicles())
end


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


---Server: update the map markers of changed spots and send the changes to every player
-- @param table changes list of {vehicle, components}; components nil for a removed spot
function HomeSpots.onSpotsChanged(changes)
    for _, change in ipairs(changes) do
        HomeSpots.updateHotspot(HomeSpots.store:getKey(change.vehicle))
    end

    HomeSpots.broadcast(HomeSpotSpotsEvent.new(changes, false))
end


---Multiplayer client: take over spots sent by the server
-- @param table entries list of {objectId, components}; components nil for a removed spot
-- @param boolean isFullSync true when the entries are all spots, replacing the ones known so far
function HomeSpots.onSpotsReceived(entries, isFullSync)
    HomeSpots.store:setIsServer(false)

    if isFullSync then
        HomeSpots.removeAllHotspots()
        HomeSpots.store:clearSpots()
    end

    for _, entry in ipairs(entries) do
        HomeSpots.store:setByKey(entry.objectId, entry.components)
        HomeSpots.updateHotspot(entry.objectId)
    end

    HomeSpots.shownActionState = nil
end


---Server: send a player who just joined the settings and every home spot
-- @param table mission mission
-- @param table connection connection of the player who joined
function HomeSpots.onClientJoined(mission, connection)
    if connection == nil or connection:getIsLocal() then
        return
    end

    local entries = {}
    for key, components in pairs(HomeSpots.store:getAll()) do
        local vehicle = HomeSpots.store:getVehicle(key)
        if vehicle ~= nil then
            table.insert(entries, {vehicle = vehicle, components = components})
        end
    end

    connection:sendEvent(HomeSpotSettingsEvent.new(HomeSpots.store:getSettings()))
    connection:sendEvent(HomeSpotSpotsEvent.new(entries, true))
end


---Returns true if this player may change the Home Spots settings: in single player, as host, or as server admin
-- @return boolean canChange
function HomeSpots.getCanChangeSettings()
    return g_currentMission:getIsServer() or g_currentMission.isMasterUser == true
end


---Change settings from the settings page: directly on the server, or by asking it
-- @param table changes the settings to change (see HomeSpotStore.SETTING_NAMES), the others keep their value
function HomeSpots.changeSettings(changes)
    local settings = HomeSpots.store:getSettings()
    for name, value in pairs(changes) do
        settings[name] = value
    end

    if g_currentMission:getIsServer() then
        HomeSpots.applySettings(settings)
    else
        HomeSpots.onSettingsReceived(settings)
        g_client:getServerConnection():sendEvent(HomeSpotSettingsEvent.new(settings))
    end
end


---Server: use new settings and send them to every player
-- @param table settings all settings
function HomeSpots.applySettings(settings)
    HomeSpots.onSettingsReceived(settings)
    HomeSpots.broadcast(HomeSpotSettingsEvent.new(settings))
end


---Use settings (the server's, or this player's own change) and show them on the settings page
-- @param table settings all settings
function HomeSpots.onSettingsReceived(settings)
    HomeSpots.store:setSettings(settings)
    HomeSpotSettings.refresh()
end


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
-- Tools without a home spot are unhooked and left where they are. A vehicle whose spot is taken, or runs into a wall, stays put.
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


---Create an empty report
-- @param integer kind HomeSpots.REPORT_*
-- @return table report kind, vehicles (saved, removed or moved), atHome, blocked, numBusy, isAutomatic, isTargeted,
--   fees (farm id to the realism fee paid, or asked for when the farm could not pay)
function HomeSpots.newReport(kind)
    return {kind = kind, vehicles = {}, atHome = {}, blocked = {}, numBusy = 0, isAutomatic = false, isTargeted = false, fees = {}}
end


---Server: tell the player who asked what happened. The daily send-home is told to every player.
-- @param table report report
-- @param table connection connection of the player who asked, nil for the local player
function HomeSpots.deliverReport(report, connection)
    if report.isAutomatic then
        HomeSpots.broadcast(HomeSpotReportEvent.new(report))
        HomeSpots.showReport(report)
    elseif connection ~= nil then
        connection:sendEvent(HomeSpotReportEvent.new(report))
    else
        HomeSpots.showReport(report)
    end
end


---Show a report as an in-game notification
-- @param table report report
function HomeSpots.showReport(report)
    local names = function(vehicles)
        return HomeSpots.getVehicleNames(vehicles, HomeSpots.MAX_NAMES_LISTED)
    end

    if report.kind == HomeSpots.REPORT_SAVED then
        HomeSpots.notify(HomeSpots.getText("homeSpots_saved", names(report.vehicles)))
        return
    elseif report.kind == HomeSpots.REPORT_CLEARED then
        HomeSpots.notify(HomeSpots.getText("homeSpots_cleared", names(report.vehicles)))
        return
    elseif report.kind == HomeSpots.REPORT_NOTHING then
        HomeSpots.notify(HomeSpots.getText("homeSpots_none"))
        return
    elseif report.kind == HomeSpots.REPORT_NO_SHED then
        HomeSpots.notify(HomeSpots.getText("homeSpots_noShedRoom"), FSBaseMission.INGAME_NOTIFICATION_INFO)
        return
    elseif report.kind == HomeSpots.REPORT_SHED_SAVED then
        local text = HomeSpots.getText("homeSpots_shedSaved", names(report.vehicles))
        if #report.blocked > 0 then
            text = text .. ". " .. HomeSpots.getText("homeSpots_noShedRoomFor", names(report.blocked))
        end
        HomeSpots.notify(text, #report.blocked > 0 and FSBaseMission.INGAME_NOTIFICATION_INFO or nil)
        return
    end

    local fee = report.fees[g_currentMission:getFarmId()]
    if report.kind == HomeSpots.REPORT_NO_MONEY then
        HomeSpots.notify(HomeSpots.getText("homeSpots_noMoney", g_i18n:formatMoney(fee, 0, true, true)), FSBaseMission.INGAME_NOTIFICATION_INFO)
        return
    end

    local moved = report.vehicles
    local parts = {}
    if report.isTargeted then
        if #moved > 0 then
            table.insert(parts, HomeSpots.getText("homeSpots_sentHomeFor", names(moved)))
        end
        if #report.atHome > 0 then
            table.insert(parts, HomeSpots.getText("homeSpots_alreadyHomeFor", names(report.atHome)))
        end
    else
        if #moved > 0 or #report.atHome == 0 then
            table.insert(parts, HomeSpots.getText("homeSpots_sentHome", #moved))
        end
        if #report.atHome > 0 then
            local isAllHome = #moved == 0 and report.numBusy == 0 and #report.blocked == 0
            table.insert(parts, isAllHome and HomeSpots.getText("homeSpots_allHome") or HomeSpots.getText("homeSpots_alreadyHome", #report.atHome))
        end
    end
    if report.numBusy > 0 then
        table.insert(parts, HomeSpots.getText("homeSpots_inUse", report.numBusy))
    end
    if #report.blocked > 0 then
        table.insert(parts, HomeSpots.getText("homeSpots_blocked", names(report.blocked)))
    end
    if fee ~= nil then
        table.insert(parts, HomeSpots.getText("homeSpots_feePaid", g_i18n:formatMoney(fee, 0, true, true)))
    end

    local text = table.concat(parts, ". ")
    if report.isAutomatic then
        text = HomeSpots.getText("homeSpots_autoTidyPrefix") .. " " .. text
    end

    HomeSpots.notify(text, #report.blocked > 0 and FSBaseMission.INGAME_NOTIFICATION_INFO or nil)
end


---Create, move or remove the map marker of a home spot to match the store
-- @param any key spot key
function HomeSpots.updateHotspot(key)
    local components = HomeSpots.store:getAll()[key]
    if components == nil or not g_currentMission:getIsClient() then
        HomeSpots.removeHotspot(key)
        return
    end

    local hotspot = HomeSpots.hotspots[key]
    if hotspot == nil then
        hotspot = HomeSpotHotspot.new(key)
        HomeSpots.hotspots[key] = hotspot
        g_currentMission:addMapHotspot(hotspot)
    end

    local position = components[1][1]
    hotspot:setWorldPosition(position[1], position[3])
end


---Remove the map marker of a home spot
-- @param any key spot key
function HomeSpots.removeHotspot(key)
    local hotspot = HomeSpots.hotspots[key]
    if hotspot ~= nil then
        g_currentMission:removeMapHotspot(hotspot)
        hotspot:delete()
        HomeSpots.hotspots[key] = nil
    end
end


---Remove every map marker
function HomeSpots.removeAllHotspots()
    for key in pairs(HomeSpots.hotspots) do
        HomeSpots.removeHotspot(key)
    end
end


---Keep the help entries in line with what the player sits in or looks at:
-- "Set" and "Park in a shed" only show with a target, "Set" reads "Update" once it has a home spot,
-- "Send home" and "Remove" only show when the target has a home spot.
-- The game keeps separate keys on foot and in a vehicle, so every context is kept up to date.
function HomeSpots.updateActionEvents()
    if next(HomeSpots.actionEventIds) == nil then
        return
    end

    local vehicles = HomeSpots.getTargetVehicles()
    local vehiclesWithSpot = {}
    for _, vehicle in ipairs(vehicles) do
        if HomeSpots.store:has(vehicle) then
            table.insert(vehiclesWithSpot, vehicle)
        end
    end

    local hasTarget = #vehicles > 0
    local hasSpot = #vehiclesWithSpot > 0
    local setText = HomeSpots.getText(hasSpot and "homeSpots_updateFor" or "homeSpots_setFor", HomeSpots.getVehicleNames(vehicles, HomeSpots.MAX_NAMES_IN_PROMPT))
    local spotNames = HomeSpots.getVehicleNames(vehiclesWithSpot, HomeSpots.MAX_NAMES_IN_PROMPT)
    local clearText = HomeSpots.getText("homeSpots_clearFor", spotNames)
    local sendText = HomeSpots.getText("homeSpots_sendHomeFor", spotNames)
    local shedText = HomeSpots.getText("homeSpots_findShedFor", HomeSpots.getVehicleNames(vehicles, HomeSpots.MAX_NAMES_IN_PROMPT))

    local state = table.concat({tostring(hasTarget), setText, clearText, sendText, shedText}, "|")
    if state == HomeSpots.shownActionState then
        return
    end

    HomeSpots.shownActionState = state
    for _, eventIds in pairs(HomeSpots.actionEventIds) do
        HomeSpots.setActionEventState(eventIds.HOMESPOTS_SET, hasTarget, setText)
        HomeSpots.setActionEventState(eventIds.HOMESPOTS_CLEAR, hasSpot, clearText)
        HomeSpots.setActionEventState(eventIds.HOMESPOTS_SEND_ONE, hasSpot, sendText)
        HomeSpots.setActionEventState(eventIds.HOMESPOTS_FIND_SHED, hasTarget, shedText)
    end
end


---Show or hide one help entry and set its text
-- @param string eventId action event id, or nil when it was not registered
-- @param boolean isActive whether the entry is shown
-- @param string text help text
function HomeSpots.setActionEventState(eventId, isActive, text)
    if eventId ~= nil then
        g_inputBinding:setActionEventText(eventId, text)
        g_inputBinding:setActionEventActive(eventId, isActive)
    end
end


---Mod event listener update
-- @param float dt time since last frame in ms
function HomeSpots:update(dt)
    HomeSpots.updateActionEvents()
    HomeSpots.processPendingMoves()
end


---Register an action event and show it in the help panel at the top left of the screen
-- @param table target object the key is registered for, one per input context
-- @param table eventIds event ids of the input context being registered, the new id is added to it
-- @param string actionName input action name
-- @param function callback callback
function HomeSpots.registerActionEvent(target, eventIds, actionName, callback)
    local _, eventId = g_inputBinding:registerActionEvent(InputAction[actionName], target, callback, false, true, false, true)
    if eventId == nil or eventId == "" then
        return
    end

    eventIds[actionName] = eventId
    g_inputBinding:setActionEventText(eventId, g_i18n:getText("input_" .. actionName))
    g_inputBinding:setActionEventTextVisibility(eventId, true)
    g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_NORMAL)
end


---Remove keys registered earlier in the same input context, so re-registering never leaves a second copy behind
-- @param table eventIds action name to event id, or nil
function HomeSpots.removeActionEvents(eventIds)
    for _, eventId in pairs(eventIds or {}) do
        g_inputBinding:removeActionEvent(eventId)
    end
end


---Register all of the mod's keys. Called by the game on foot and in a vehicle, in the middle of registering the player's own keys,
-- and again whenever those are refreshed (getting in or out, hitching or unhitching a tool).
-- @param table inputComponent player input component
-- @param string contextName input context name, nil on foot
function HomeSpots.registerGlobalActionEvents(inputComponent, contextName)
    local contextKey = contextName or HomeSpots.DEFAULT_INPUT_CONTEXT
    HomeSpots.removeActionEvents(HomeSpots.actionEventIds[contextKey])

    local target = HomeSpots.inputTargets[contextKey] or {}
    HomeSpots.inputTargets[contextKey] = target

    local eventIds = {}
    HomeSpots.actionEventIds[contextKey] = eventIds

    HomeSpots.registerActionEvent(target, eventIds, "HOMESPOTS_SEND_ALL", HomeSpots.onSendAllHomeInput)
    HomeSpots.registerActionEvent(target, eventIds, "HOMESPOTS_SEND_ONE", HomeSpots.onSendTargetHomeInput)
    HomeSpots.registerActionEvent(target, eventIds, "HOMESPOTS_SET", HomeSpots.onSetHomeInput)
    HomeSpots.registerActionEvent(target, eventIds, "HOMESPOTS_CLEAR", HomeSpots.onClearHomeInput)
    HomeSpots.registerActionEvent(target, eventIds, "HOMESPOTS_FIND_SHED", HomeSpots.onFindShedInput)

    HomeSpots.shownActionState = nil
end


---Send everything home when the chosen hour starts (on the server), with a heads-up one hour before (for every player)
function HomeSpots:onHourChanged()
    local hour = HomeSpots.store.autoTidyHour
    if hour == HomeSpotStore.AUTO_TIDY_OFF then
        return
    end

    local currentHour = g_currentMission.environment.currentHour

    if currentHour == hour then
        if g_currentMission:getIsServer() then
            HomeSpots.sendAllHome()
        end
    elseif currentHour == (hour - 1) % 24 and HomeSpots.store:getCount() > 0 then
        HomeSpots.notify(HomeSpots.getText("homeSpots_tidySoon", HomeSpotSettings.formatHour(hour)), FSBaseMission.INGAME_NOTIFICATION_INFO)
    end
end


---Set up the mod for a savegame once its folder is known: helper node, saved spots, map markers and the daily send-home time.
-- A multiplayer client keeps what it holds: the server may have sent the spots before this ran.
-- @param table mission mission
function HomeSpots.onMissionLoaded(mission)
    HomeSpots.store:setIsServer(mission:getIsServer())
    HomeSpots.pendingMoves = nil
    HomeSpots.helperNode = createTransformGroup("homeSpotsHelper")
    HomeSpotShed.createNodes()
    g_messageCenter:subscribe(MessageType.HOUR_CHANGED, HomeSpots.onHourChanged, HomeSpots)

    if mission:getIsServer() then
        HomeSpots.store:reset()

        local savegameDirectory = mission.missionInfo ~= nil and mission.missionInfo.savegameDirectory or nil
        if savegameDirectory ~= nil then
            HomeSpots.store:loadFromDirectory(savegameDirectory)
            Logging.info("Home Spots: loaded %d home spot(s)", HomeSpots.store:getCount())
        end
    end

    for key in pairs(HomeSpots.store:getAll()) do
        HomeSpots.updateHotspot(key)
    end
end


---Write homeSpots.xml into the folder the game is saving to, next to the rest of the savegame
-- @param table missionInfo career mission info
function HomeSpots.onSaveCareer(missionInfo)
    if g_currentMission == nil or not g_currentMission:getIsServer() or missionInfo.savegameDirectory == nil then
        return
    end

    local count = HomeSpots.store:saveToDirectory(missionInfo.savegameDirectory, g_currentMission.vehicleSystem)
    Logging.info("Home Spots: saved %d home spot(s)", count)
end


---Add the send-home time option whenever the settings page opens
-- @param table settingsFrame in-game menu settings frame
function HomeSpots.onSettingsFrameOpen(settingsFrame)
    HomeSpotSettings.inject(settingsFrame)
end


---Forget everything when leaving the savegame
function HomeSpots.onMissionDeleted()
    g_messageCenter:unsubscribeAll(HomeSpots)
    HomeSpots.removeAllHotspots()
    HomeSpots.store:reset()
    HomeSpots.pendingMoves = nil
    HomeSpots.pendingReport = nil
    HomeSpots.actionEventIds = {}
    HomeSpots.inputTargets = {}
    HomeSpots.shownActionState = nil

    if HomeSpots.helperNode ~= nil then
        delete(HomeSpots.helperNode)
        HomeSpots.helperNode = nil
    end
    HomeSpotShed.deleteNodes()
end


PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, HomeSpots.registerGlobalActionEvents)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, HomeSpots.onMissionLoaded)
FSBaseMission.onConnectionFinishedLoading = Utils.appendedFunction(FSBaseMission.onConnectionFinishedLoading, HomeSpots.onClientJoined)
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, HomeSpots.onSaveCareer)
InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, HomeSpots.onSettingsFrameOpen)
FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, HomeSpots.onMissionDeleted)

addModEventListener(HomeSpots)
