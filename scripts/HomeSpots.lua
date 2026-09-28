---Home Spots: give each vehicle and tool a home spot, then send everything home with one key.
HomeSpots = {}
HomeSpots.MOD_NAME = g_currentModName
HomeSpots.MAX_NAMES_LISTED = 3
HomeSpots.MAX_NAMES_IN_PROMPT = 2

-- A vehicle this close to its home spot (m, and heading in rad) counts as already home and is not moved
HomeSpots.AT_HOME_DISTANCE = 1.0
HomeSpots.AT_HOME_ANGLE = math.rad(10)

-- How far (m) the player on foot can be from a vehicle or tool to set its home spot
HomeSpots.LOOK_DISTANCE = 6
HomeSpots.LOOK_STEP = 0.25
HomeSpots.LOOK_MARGIN = 0.2
HomeSpots.DEFAULT_VEHICLE_HEIGHT = 4

HomeSpots.store = HomeSpotStore.new()
HomeSpots.hotspots = {}
HomeSpots.helperNode = nil
HomeSpots.pendingMoves = nil
HomeSpots.pendingReport = nil
HomeSpots.actionEventIds = {}
HomeSpots.shownActionState = nil
HomeSpots.loggedErrors = {}


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
    g_currentMission:addIngameNotification(notificationType or FSBaseMission.INGAME_NOTIFICATION_OK, text)
end


---Returns true if a home spot can be saved for this vehicle (trains and pallets are left out)
-- @param table vehicle vehicle
-- @return boolean canHaveSpot
function HomeSpots.canHaveHomeSpot(vehicle)
    return vehicle.components ~= nil
        and vehicle.size ~= nil
        and vehicle:getUniqueId() ~= nil
        and not vehicle.isPallet
        and vehicle.trainSystem == nil
        and vehicle.spec_locomotive == nil
end


---Returns true if the vehicle, or whatever it is attached to, is driven by a player or an AI worker
-- @param table vehicle vehicle
-- @return boolean isBusy
function HomeSpots.getIsBusy(vehicle)
    local rootVehicle = vehicle:getRootVehicle()

    if rootVehicle.getIsAIActive ~= nil and rootVehicle:getIsAIActive() then
        return true
    end

    return rootVehicle.getIsControlled ~= nil and rootVehicle:getIsControlled()
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

                table.insert(nearby, {
                    vehicle = vehicle,
                    area = area,
                    minY = rootY - HomeSpots.LOOK_MARGIN - 1,
                    maxY = rootY + height + HomeSpots.LOOK_MARGIN
                })
            end
        end
    end

    if #nearby == 0 then
        return nil
    end

    for distance = HomeSpots.LOOK_STEP, HomeSpots.LOOK_DISTANCE, HomeSpots.LOOK_STEP do
        local pointX, pointY, pointZ = x + dirX * distance, y + dirY * distance, z + dirZ * distance

        for _, candidate in ipairs(nearby) do
            if pointY >= candidate.minY and pointY <= candidate.maxY
                and HomeSpotArea.getContainsPoint(candidate.area, pointX, pointZ, HomeSpots.LOOK_MARGIN) then
                return candidate.vehicle
            end
        end
    end

    return nil
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
    local vehicles = HomeSpots.getTargetVehicles()

    for _, vehicle in ipairs(vehicles) do
        HomeSpots.store:set(vehicle)
        HomeSpots.updateHotspot(vehicle:getUniqueId())
    end

    if #vehicles > 0 then
        HomeSpots.notify(HomeSpots.getText("homeSpots_saved", HomeSpots.getVehicleNames(vehicles, HomeSpots.MAX_NAMES_LISTED)))
    end
end


---Action: delete the home spots of the targeted vehicles
function HomeSpots:onClearHomeInput()
    local removed = {}

    for _, vehicle in ipairs(HomeSpots.getTargetVehicles()) do
        if HomeSpots.store:remove(vehicle) then
            HomeSpots.removeHotspot(vehicle:getUniqueId())
            table.insert(removed, vehicle)
        end
    end

    if #removed > 0 then
        HomeSpots.notify(HomeSpots.getText("homeSpots_cleared", HomeSpots.getVehicleNames(removed, HomeSpots.MAX_NAMES_LISTED)))
    end
end


---Action: send every vehicle and tool home
function HomeSpots:onSendAllHomeInput()
    HomeSpots.runSafely(HomeSpots.sendAllHome, false)
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


---Send every vehicle and tool of the player's farm to its home spot.
-- Vehicles are unhooked this frame and moved on the next update, once the detach has settled.
-- Tools without a home spot are unhooked and left where they are.
-- @param boolean isAutomatic true when triggered by the daily send-home time
function HomeSpots.sendAllHome(isAutomatic)
    if not g_currentMission:getIsServer() then
        if not isAutomatic then
            HomeSpots.notify(HomeSpots.getText("homeSpots_singlePlayerOnly"))
        end
        return
    end

    if HomeSpots.pendingMoves ~= nil then
        return
    end

    local farmId = g_currentMission:getFarmId()
    local candidates = {}
    local isMoving = {}
    local numBusy = 0
    local numAtHome = 0

    for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
        local components = HomeSpots.store:get(vehicle)

        if components ~= nil and vehicle:getOwnerFarmId() == farmId and HomeSpots.canHaveHomeSpot(vehicle) then
            if HomeSpots.getIsBusy(vehicle) then
                numBusy = numBusy + 1
            elseif #components == #vehicle.components then
                local homeArea = HomeSpots.getHomeArea(vehicle, components)
                local currentArea = HomeSpotArea.newFromNode(vehicle.size, vehicle.rootNode)

                if HomeSpotArea.getIsSamePose(homeArea, currentArea, HomeSpots.AT_HOME_DISTANCE, HomeSpots.AT_HOME_ANGLE) then
                    numAtHome = numAtHome + 1
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

    if #candidates == 0 and numBusy == 0 and numAtHome == 0 then
        if not isAutomatic then
            HomeSpots.notify(HomeSpots.getText("homeSpots_none"))
        end
        return
    end

    local staticAreas = {}
    for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
        if not isMoving[vehicle] and vehicle.size ~= nil and vehicle.rootNode ~= nil then
            table.insert(staticAreas, HomeSpotArea.newFromNode(vehicle.size, vehicle.rootNode))
        end
    end

    local accepted, blocked = HomeSpots.resolveBlockedSpots(candidates, staticAreas)

    for _, move in ipairs(accepted) do
        HomeSpots.detachFromCombination(move.vehicle)
    end

    HomeSpots.pendingMoves = accepted
    HomeSpots.pendingReport = {isAutomatic = isAutomatic, numBusy = numBusy, numAtHome = numAtHome, blocked = blocked}
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

    local numMoved = 0
    for _, move in ipairs(moves) do
        if HomeSpots.moveToHomeSpot(move.vehicle, move.components) then
            numMoved = numMoved + 1
        end
    end

    local report = HomeSpots.pendingReport
    HomeSpots.pendingReport = nil

    local parts = {}
    if numMoved > 0 or report.numAtHome == 0 then
        table.insert(parts, HomeSpots.getText("homeSpots_sentHome", numMoved))
    end
    if report.numAtHome > 0 then
        local isAllHome = numMoved == 0 and report.numBusy == 0 and #report.blocked == 0
        table.insert(parts, isAllHome and HomeSpots.getText("homeSpots_allHome") or HomeSpots.getText("homeSpots_alreadyHome", report.numAtHome))
    end
    if report.numBusy > 0 then
        table.insert(parts, HomeSpots.getText("homeSpots_inUse", report.numBusy))
    end
    if #report.blocked > 0 then
        table.insert(parts, HomeSpots.getText("homeSpots_blocked", HomeSpots.getVehicleNames(HomeSpots.getMovedVehicles(report.blocked), HomeSpots.MAX_NAMES_LISTED)))
    end

    local text = table.concat(parts, ". ")
    if report.isAutomatic then
        text = HomeSpots.getText("homeSpots_autoTidyPrefix") .. " " .. text
    end

    HomeSpots.notify(text, #report.blocked > 0 and FSBaseMission.INGAME_NOTIFICATION_INFO or nil)
end


---Create or move the map marker of a home spot
-- @param string uniqueId vehicle unique id
function HomeSpots.updateHotspot(uniqueId)
    local components = HomeSpots.store:getAll()[uniqueId]
    if components == nil then
        return
    end

    local hotspot = HomeSpots.hotspots[uniqueId]
    if hotspot == nil then
        hotspot = HomeSpotHotspot.new(uniqueId)
        HomeSpots.hotspots[uniqueId] = hotspot
        g_currentMission:addMapHotspot(hotspot)
    end

    local position = components[1][1]
    hotspot:setWorldPosition(position[1], position[3])
end


---Remove the map marker of a home spot
-- @param string uniqueId vehicle unique id
function HomeSpots.removeHotspot(uniqueId)
    local hotspot = HomeSpots.hotspots[uniqueId]
    if hotspot ~= nil then
        g_currentMission:removeMapHotspot(hotspot)
        hotspot:delete()
        HomeSpots.hotspots[uniqueId] = nil
    end
end


---Remove every map marker
function HomeSpots.removeAllHotspots()
    for uniqueId in pairs(HomeSpots.hotspots) do
        HomeSpots.removeHotspot(uniqueId)
    end
end


---Keep the help entries in line with what the player sits in or looks at:
-- "Set" only shows with a target and reads "Update" once it has a home spot, "Remove" only shows when there is one to remove.
function HomeSpots.updateActionEvents()
    local setEventId = HomeSpots.actionEventIds.HOMESPOTS_SET
    local clearEventId = HomeSpots.actionEventIds.HOMESPOTS_CLEAR
    if setEventId == nil or clearEventId == nil then
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
    local clearText = HomeSpots.getText("homeSpots_clearFor", HomeSpots.getVehicleNames(vehiclesWithSpot, HomeSpots.MAX_NAMES_IN_PROMPT))

    local state = table.concat({tostring(setEventId), tostring(hasTarget), setText, clearText}, "|")
    if state == HomeSpots.shownActionState then
        return
    end

    HomeSpots.shownActionState = state
    g_inputBinding:setActionEventActive(setEventId, hasTarget)
    g_inputBinding:setActionEventText(setEventId, setText)
    g_inputBinding:setActionEventText(clearEventId, clearText)
    g_inputBinding:setActionEventActive(clearEventId, hasSpot)
end


---Run a function and log its error (once per distinct message) instead of letting it stop the game loop
-- @param function func function
-- @param any ... arguments
function HomeSpots.runSafely(func, ...)
    local success, errorMessage = pcall(func, ...)

    if not success then
        errorMessage = tostring(errorMessage)

        if not HomeSpots.loggedErrors[errorMessage] then
            HomeSpots.loggedErrors[errorMessage] = true
            Logging.error("Home Spots: %s", errorMessage)
        end
    end
end


---Mod event listener update
-- @param float dt time since last frame in ms
function HomeSpots:update(dt)
    HomeSpots.runSafely(HomeSpots.updateActionEvents)
    HomeSpots.runSafely(HomeSpots.processPendingMoves)
end


---Register an action event and show it in the help panel at the top left of the screen
-- @param string actionName input action name
-- @param function callback callback
function HomeSpots.registerActionEvent(actionName, callback)
    local _, eventId = g_inputBinding:registerActionEvent(InputAction[actionName], HomeSpots, callback, false, true, false, true)
    HomeSpots.actionEventIds[actionName] = eventId

    if eventId ~= nil then
        g_inputBinding:setActionEventText(eventId, g_i18n:getText("input_" .. actionName))
        g_inputBinding:setActionEventTextVisibility(eventId, true)
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_NORMAL)
    end
end


---Register all of the mod's keys
function HomeSpots.registerAllActionEvents()
    HomeSpots.registerActionEvent("HOMESPOTS_SEND_ALL", HomeSpots.onSendAllHomeInput)
    HomeSpots.registerActionEvent("HOMESPOTS_SET", HomeSpots.onSetHomeInput)
    HomeSpots.registerActionEvent("HOMESPOTS_CLEAR", HomeSpots.onClearHomeInput)

    HomeSpots.shownActionState = nil
end


---Called by the game on foot and in a vehicle, in the middle of registering the player's own keys.
-- Runs safely so a failure here can never leave the player without movement keys.
-- @param table inputComponent player input component
-- @param string contextName input context name
function HomeSpots.registerGlobalActionEvents(inputComponent, contextName)
    HomeSpots.runSafely(HomeSpots.registerAllActionEvents)
end


---Send everything home when the chosen hour starts
function HomeSpots:onHourChanged()
    local hour = HomeSpots.store.autoTidyHour

    if hour ~= HomeSpotStore.AUTO_TIDY_OFF and g_currentMission.environment.currentHour == hour then
        HomeSpots.runSafely(HomeSpots.sendAllHome, true)
    end
end


---Load home spots once the savegame folder is known
-- @param table mission mission
function HomeSpots.onMissionLoaded(mission)
    HomeSpots.runSafely(HomeSpots.loadMission, mission)
end


---Set up the mod for a savegame: helper node, saved spots, map markers and the daily send-home time
-- @param table mission mission
function HomeSpots.loadMission(mission)
    HomeSpots.store:reset()
    HomeSpots.pendingMoves = nil
    HomeSpots.helperNode = createTransformGroup("homeSpotsHelper")
    g_messageCenter:subscribe(MessageType.HOUR_CHANGED, HomeSpots.onHourChanged, HomeSpots)

    local savegameDirectory = mission.missionInfo ~= nil and mission.missionInfo.savegameDirectory or nil
    if savegameDirectory ~= nil then
        HomeSpots.store:loadFromDirectory(savegameDirectory)
        Logging.info("Home Spots: loaded %d home spot(s)", HomeSpots.store:getCount())
    end

    for uniqueId in pairs(HomeSpots.store:getAll()) do
        HomeSpots.updateHotspot(uniqueId)
    end
end


---Save home spots next to the rest of the savegame
-- @param table missionInfo career mission info
function HomeSpots.onSaveCareer(missionInfo)
    HomeSpots.runSafely(HomeSpots.saveCareer, missionInfo)
end


---Write homeSpots.xml into the folder the game is saving to
-- @param table missionInfo career mission info
function HomeSpots.saveCareer(missionInfo)
    if g_currentMission == nil or not g_currentMission:getIsServer() or missionInfo.savegameDirectory == nil then
        return
    end

    local count = HomeSpots.store:saveToDirectory(missionInfo.savegameDirectory, g_currentMission.vehicleSystem)
    Logging.info("Home Spots: saved %d home spot(s)", count)
end


---Add the send-home time option whenever the settings page opens
-- @param table settingsFrame in-game menu settings frame
function HomeSpots.onSettingsFrameOpen(settingsFrame)
    local success, errorMessage = pcall(HomeSpotSettings.inject, settingsFrame)
    if not success then
        Logging.warning("Home Spots: could not add the settings option (%s)", tostring(errorMessage))
    end
end


---Forget everything when leaving the savegame
function HomeSpots.onMissionDeleted()
    g_messageCenter:unsubscribeAll(HomeSpots)
    HomeSpots.removeAllHotspots()
    HomeSpots.store:reset()
    HomeSpots.pendingMoves = nil
    HomeSpots.pendingReport = nil

    if HomeSpots.helperNode ~= nil then
        delete(HomeSpots.helperNode)
        HomeSpots.helperNode = nil
    end
end


PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, HomeSpots.registerGlobalActionEvents)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, HomeSpots.onMissionLoaded)
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, HomeSpots.onSaveCareer)
InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, HomeSpots.onSettingsFrameOpen)
FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, HomeSpots.onMissionDeleted)

addModEventListener(HomeSpots)
