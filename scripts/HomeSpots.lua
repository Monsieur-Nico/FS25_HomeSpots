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


---Mod event listener update
-- @param float dt time since last frame in ms
function HomeSpots:update(dt)
    HomeSpots.updateActionEvents()
    HomeSpots.processPendingMoves()
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
