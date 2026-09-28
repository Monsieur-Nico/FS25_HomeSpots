---Multiplayer messages. The server owns the home spots and the settings and does every move;
-- players send it their key presses and get back the spots, the settings and a report of what happened.
HomeSpotNetwork = {}


---Write a list of vehicles as network object ids
-- @param integer streamId stream id
-- @param table vehicles vehicles
function HomeSpotNetwork.writeVehicles(streamId, vehicles)
    streamWriteUInt16(streamId, #vehicles)
    for _, vehicle in ipairs(vehicles) do
        NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(vehicle))
    end
end


---Read a list of vehicles written by writeVehicles. Vehicles this side does not know are left out.
-- @param integer streamId stream id
-- @return table vehicles vehicles
function HomeSpotNetwork.readVehicles(streamId)
    local vehicles = {}
    for _ = 1, streamReadUInt16(streamId) do
        local vehicle = NetworkUtil.getObject(NetworkUtil.readNodeObjectId(streamId))
        if vehicle ~= nil then
            table.insert(vehicles, vehicle)
        end
    end

    return vehicles
end


---Write realism fees per farm
-- @param integer streamId stream id
-- @param table fees farm id to amount
function HomeSpotNetwork.writeFees(streamId, fees)
    local farmIds = {}
    for farmId in pairs(fees) do
        table.insert(farmIds, farmId)
    end

    streamWriteUInt8(streamId, #farmIds)
    for _, farmId in ipairs(farmIds) do
        streamWriteUInt8(streamId, farmId)
        streamWriteFloat32(streamId, fees[farmId])
    end
end


---Read fees written by writeFees
-- @param integer streamId stream id
-- @return table fees farm id to amount
function HomeSpotNetwork.readFees(streamId)
    local fees = {}
    for _ = 1, streamReadUInt8(streamId) do
        local farmId = streamReadUInt8(streamId)
        fees[farmId] = streamReadFloat32(streamId)
    end

    return fees
end


---Write the component positions of a home spot, or none for a removed spot
-- @param integer streamId stream id
-- @param table components component positions, or nil
function HomeSpotNetwork.writeComponents(streamId, components)
    streamWriteUInt8(streamId, components ~= nil and #components or 0)
    for _, component in ipairs(components or {}) do
        for _, vector in ipairs(component) do
            for axis = 1, 3 do
                streamWriteFloat32(streamId, vector[axis])
            end
        end
    end
end


---Read component positions written by writeComponents
-- @param integer streamId stream id
-- @return table components component positions, or nil for a removed spot
function HomeSpotNetwork.readComponents(streamId)
    local numComponents = streamReadUInt8(streamId)
    if numComponents == 0 then
        return nil
    end

    local components = {}
    for i = 1, numComponents do
        local vectors = {}
        for j = 1, 2 do
            vectors[j] = {streamReadFloat32(streamId), streamReadFloat32(streamId), streamReadFloat32(streamId)}
        end
        components[i] = vectors
    end

    return components
end


---Returns the farm of the player behind a connection
-- @param table connection connection
-- @return integer farmId farm id, or nil when the player has no farm
function HomeSpotNetwork.getFarmId(connection)
    local userId = g_currentMission.userManager:getUserIdByConnection(connection)
    local farm = userId ~= nil and g_farmManager:getFarmByUserId(userId) or nil

    return farm ~= nil and farm.farmId or nil
end


---Returns true if the player behind a connection may change the Home Spots settings (host or server admin)
-- @param table connection connection
-- @return boolean isAdmin
function HomeSpotNetwork.getIsAdmin(connection)
    return connection:getIsLocal() or g_currentMission.userManager:getIsConnectionMasterUser(connection)
end


---Home spots from the server: every spot when a player joins, or the ones that were just set or removed
HomeSpotSpotsEvent = {}
local HomeSpotSpotsEvent_mt = Class(HomeSpotSpotsEvent, Event)
InitEventClass(HomeSpotSpotsEvent, "HomeSpotSpotsEvent")


---Create an empty event (used by the game when receiving)
-- @return table self
function HomeSpotSpotsEvent.emptyNew()
    return Event.new(HomeSpotSpotsEvent_mt)
end


---Create an event
-- @param table entries list of {vehicle, components}; components nil for a removed spot
-- @param boolean isFullSync true when the entries are all spots, replacing what the player had
-- @return table self
function HomeSpotSpotsEvent.new(entries, isFullSync)
    local self = HomeSpotSpotsEvent.emptyNew()
    self.entries = entries
    self.isFullSync = isFullSync

    return self
end


---Write the event
-- @param integer streamId stream id
-- @param table connection connection
function HomeSpotSpotsEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.isFullSync)
    streamWriteUInt16(streamId, #self.entries)
    for _, entry in ipairs(self.entries) do
        NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(entry.vehicle))
        HomeSpotNetwork.writeComponents(streamId, entry.components)
    end
end


---Read the event. Spots are kept by object id, so a spot also arrives for a vehicle that is still loading.
-- @param integer streamId stream id
-- @param table connection connection
function HomeSpotSpotsEvent:readStream(streamId, connection)
    self.isFullSync = streamReadBool(streamId)
    self.entries = {}
    for _ = 1, streamReadUInt16(streamId) do
        local objectId = NetworkUtil.readNodeObjectId(streamId)
        table.insert(self.entries, {objectId = objectId, components = HomeSpotNetwork.readComponents(streamId)})
    end

    self:run(connection)
end


---Apply the spots on the player's side
-- @param table connection connection
function HomeSpotSpotsEvent:run(connection)
    if connection:getIsServer() then
        HomeSpots.onSpotsReceived(self.entries, self.isFullSync)
    end
end


---Settings: from the server to every player, or from an admin to the server
HomeSpotSettingsEvent = {}
local HomeSpotSettingsEvent_mt = Class(HomeSpotSettingsEvent, Event)
InitEventClass(HomeSpotSettingsEvent, "HomeSpotSettingsEvent")


---Create an empty event (used by the game when receiving)
-- @return table self
function HomeSpotSettingsEvent.emptyNew()
    return Event.new(HomeSpotSettingsEvent_mt)
end


---Create an event
-- @param table settings all settings, see HomeSpotStore:getSettings
-- @return table self
function HomeSpotSettingsEvent.new(settings)
    local self = HomeSpotSettingsEvent.emptyNew()
    self.settings = settings

    return self
end


---Write the event
-- @param integer streamId stream id
-- @param table connection connection
function HomeSpotSettingsEvent:writeStream(streamId, connection)
    streamWriteInt8(streamId, self.settings.autoTidyHour)
    streamWriteUInt8(streamId, self.settings.markerMode)
    streamWriteUInt8(streamId, self.settings.feeLevel)
end


---Read the event
-- @param integer streamId stream id
-- @param table connection connection
function HomeSpotSettingsEvent:readStream(streamId, connection)
    local settings = {}
    settings.autoTidyHour = streamReadInt8(streamId)
    settings.markerMode = streamReadUInt8(streamId)
    settings.feeLevel = streamReadUInt8(streamId)
    self.settings = settings

    self:run(connection)
end


---On the server, apply an admin's change for everyone; on a player's side, show the server's settings
-- @param table connection connection
function HomeSpotSettingsEvent:run(connection)
    if connection:getIsServer() then
        HomeSpots.onSettingsReceived(self.settings)
    elseif HomeSpotNetwork.getIsAdmin(connection) then
        HomeSpots.applySettings(self.settings)
    else
        connection:sendEvent(HomeSpotSettingsEvent.new(HomeSpots.store:getSettings()))
    end
end


---A player's key press or map action, run on the server for that player's farm
HomeSpotRequestEvent = {}
local HomeSpotRequestEvent_mt = Class(HomeSpotRequestEvent, Event)
InitEventClass(HomeSpotRequestEvent, "HomeSpotRequestEvent")


---Create an empty event (used by the game when receiving)
-- @return table self
function HomeSpotRequestEvent.emptyNew()
    return Event.new(HomeSpotRequestEvent_mt)
end


---Create an event
-- @param integer action HomeSpots.ACTION_*
-- @param table vehicles vehicles the action is for (empty for send all)
-- @return table self
function HomeSpotRequestEvent.new(action, vehicles)
    local self = HomeSpotRequestEvent.emptyNew()
    self.action = action
    self.vehicles = vehicles

    return self
end


---Write the event
-- @param integer streamId stream id
-- @param table connection connection
function HomeSpotRequestEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.action)
    HomeSpotNetwork.writeVehicles(streamId, self.vehicles)
end


---Read the event
-- @param integer streamId stream id
-- @param table connection connection
function HomeSpotRequestEvent:readStream(streamId, connection)
    self.action = streamReadUInt8(streamId)
    self.vehicles = HomeSpotNetwork.readVehicles(streamId)

    self:run(connection)
end


---Run the action on the server
-- @param table connection connection
function HomeSpotRequestEvent:run(connection)
    if connection:getIsServer() then
        return
    end

    local farmId = HomeSpotNetwork.getFarmId(connection)
    if farmId ~= nil then
        HomeSpots.runRequest(self.action, self.vehicles, farmId, connection)
    end
end


---What an action did, from the server to the player it is for (or to everyone for the daily send-home)
HomeSpotReportEvent = {}
local HomeSpotReportEvent_mt = Class(HomeSpotReportEvent, Event)
InitEventClass(HomeSpotReportEvent, "HomeSpotReportEvent")


---Create an empty event (used by the game when receiving)
-- @return table self
function HomeSpotReportEvent.emptyNew()
    return Event.new(HomeSpotReportEvent_mt)
end


---Create an event
-- @param table report report, see HomeSpots.newReport
-- @return table self
function HomeSpotReportEvent.new(report)
    local self = HomeSpotReportEvent.emptyNew()
    self.report = report

    return self
end


---Write the event
-- @param integer streamId stream id
-- @param table connection connection
function HomeSpotReportEvent:writeStream(streamId, connection)
    local report = self.report
    streamWriteUInt8(streamId, report.kind)
    streamWriteBool(streamId, report.isAutomatic)
    streamWriteBool(streamId, report.isTargeted)
    streamWriteUInt16(streamId, report.numBusy)
    HomeSpotNetwork.writeVehicles(streamId, report.vehicles)
    HomeSpotNetwork.writeVehicles(streamId, report.atHome)
    HomeSpotNetwork.writeVehicles(streamId, report.blocked)
    HomeSpotNetwork.writeFees(streamId, report.fees)
end


---Read the event
-- @param integer streamId stream id
-- @param table connection connection
function HomeSpotReportEvent:readStream(streamId, connection)
    local report = HomeSpots.newReport(streamReadUInt8(streamId))
    report.isAutomatic = streamReadBool(streamId)
    report.isTargeted = streamReadBool(streamId)
    report.numBusy = streamReadUInt16(streamId)
    report.vehicles = HomeSpotNetwork.readVehicles(streamId)
    report.atHome = HomeSpotNetwork.readVehicles(streamId)
    report.blocked = HomeSpotNetwork.readVehicles(streamId)
    report.fees = HomeSpotNetwork.readFees(streamId)
    self.report = report

    self:run(connection)
end


---Show the report to the player
-- @param table connection connection
function HomeSpotReportEvent:run(connection)
    if connection:getIsServer() then
        HomeSpots.showReport(self.report)
    end
end
