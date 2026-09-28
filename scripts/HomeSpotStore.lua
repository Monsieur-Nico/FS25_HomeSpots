---Stores one home spot per vehicle.
-- A home spot is the world position and rotation of every component of the
-- vehicle, the same data the savegame uses to place vehicles on load.
-- The server (and single player) keys spots by the vehicle's unique id, which the savegame uses.
-- A multiplayer client never learns unique ids, so it keys the spots the server sends by network object id.
HomeSpotStore = {}
local HomeSpotStore_mt = Class(HomeSpotStore)

HomeSpotStore.FILENAME = "homeSpots.xml"
HomeSpotStore.XML_ROOT = "homeSpots"
HomeSpotStore.AUTO_TIDY_OFF = -1

-- How map markers show: only on spots whose vehicle is away, always (coloured home or away), or not at all
HomeSpotStore.MARKERS_AWAY = 1
HomeSpotStore.MARKERS_ALWAYS = 2
HomeSpotStore.MARKERS_OFF = 3


---Parse three space separated numbers, e.g. "12.5 80.1 -3.2"
-- @param string text text
-- @return table values {x, y, z}, or nil if the text is not three numbers
local function parseVector3(text)
    if text == nil then
        return nil
    end

    local values = {}
    for value in text:gmatch("%S+") do
        table.insert(values, tonumber(value))
    end

    if #values ~= 3 then
        return nil
    end

    return values
end


---Create a new, empty store
-- @return table self
function HomeSpotStore.new()
    local self = setmetatable({}, HomeSpotStore_mt)

    self.isServer = true
    self:reset()

    return self
end


---Remove every home spot and restore default settings
function HomeSpotStore:reset()
    self:clearSpots()
    self.autoTidyHour = HomeSpotStore.AUTO_TIDY_OFF
    self.markerMode = HomeSpotStore.MARKERS_AWAY
end


---Remove every home spot, keeping the settings
function HomeSpotStore:clearSpots()
    self.spots = {}
end


---Choose how spots are keyed: by unique id on the server, by network object id on a multiplayer client
-- @param boolean isServer true on the server and in single player
function HomeSpotStore:setIsServer(isServer)
    self.isServer = isServer
end


---Returns the key a vehicle's spot is stored under
-- @param table vehicle vehicle
-- @return any key unique id on the server, network object id on a client
function HomeSpotStore:getKey(vehicle)
    if self.isServer then
        return vehicle:getUniqueId()
    end

    return NetworkUtil.getObjectId(vehicle)
end


---Returns the vehicle a spot key belongs to
-- @param any key spot key
-- @return table vehicle vehicle, or nil once it is gone
function HomeSpotStore:getVehicle(key)
    if self.isServer then
        return g_currentMission.vehicleSystem:getVehicleByUniqueId(key)
    end

    return NetworkUtil.getObject(key)
end


---Returns all home spots
-- @return table spots components by spot key
function HomeSpotStore:getAll()
    return self.spots
end


---Returns the number of saved home spots
-- @return integer count
function HomeSpotStore:getCount()
    local count = 0
    for _ in pairs(self.spots) do
        count = count + 1
    end

    return count
end


---Save the vehicle's current position as its home spot (create or update)
-- @param table vehicle vehicle
-- @return table components the saved component positions
function HomeSpotStore:set(vehicle)
    local components = {}

    for i, component in ipairs(vehicle.components) do
        local x, y, z = getWorldTranslation(component.node)
        local rx, ry, rz = getWorldRotation(component.node)

        components[i] = {{x, y, z}, {rx, ry, rz}}
    end

    self:setByKey(self:getKey(vehicle), components)

    return components
end


---Store a spot under its key, or delete it
-- @param any key spot key
-- @param table components component positions, or nil to delete the spot
function HomeSpotStore:setByKey(key, components)
    if key ~= nil then
        self.spots[key] = components
    end
end


---Returns the home spot of a vehicle
-- @param table vehicle vehicle
-- @return table components component positions, or nil when the vehicle has no home spot
function HomeSpotStore:get(vehicle)
    local key = self:getKey(vehicle)
    if key == nil then
        return nil
    end

    return self.spots[key]
end


---Returns true if the vehicle has a home spot
-- @param table vehicle vehicle
-- @return boolean hasSpot
function HomeSpotStore:has(vehicle)
    return self:get(vehicle) ~= nil
end


---Delete the home spot of a vehicle
-- @param table vehicle vehicle
-- @return boolean removed true if the vehicle had a home spot
function HomeSpotStore:remove(vehicle)
    local hadSpot = self:get(vehicle) ~= nil

    self:setByKey(self:getKey(vehicle), nil)

    return hadSpot
end


---Load all home spots from the savegame folder
-- @param string directory savegame directory
function HomeSpotStore:loadFromDirectory(directory)
    self:reset()

    local filename = directory .. "/" .. HomeSpotStore.FILENAME
    if not fileExists(filename) then
        return
    end

    local xmlFile = loadXMLFile("homeSpotsXML", filename)
    if xmlFile == nil or xmlFile == 0 then
        return
    end

    self.autoTidyHour = getXMLInt(xmlFile, HomeSpotStore.XML_ROOT .. "#autoTidyHour") or HomeSpotStore.AUTO_TIDY_OFF

    local markerMode = getXMLInt(xmlFile, HomeSpotStore.XML_ROOT .. "#markers")
    if markerMode == HomeSpotStore.MARKERS_ALWAYS or markerMode == HomeSpotStore.MARKERS_OFF then
        self.markerMode = markerMode
    end

    local i = 0
    while true do
        local key = string.format("%s.vehicle(%d)", HomeSpotStore.XML_ROOT, i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local uniqueId = getXMLString(xmlFile, key .. "#uniqueId")
        local components = {}

        local j = 0
        while true do
            local componentKey = string.format("%s.component(%d)", key, j)
            if not hasXMLProperty(xmlFile, componentKey) then
                break
            end

            local position = parseVector3(getXMLString(xmlFile, componentKey .. "#position"))
            local rotation = parseVector3(getXMLString(xmlFile, componentKey .. "#rotation"))
            if position ~= nil and rotation ~= nil then
                table.insert(components, {position, rotation})
            end

            j = j + 1
        end

        if uniqueId ~= nil and #components > 0 then
            self.spots[uniqueId] = components
        end

        i = i + 1
    end

    delete(xmlFile)
end


---Save all home spots to the savegame folder. Spots of vehicles that no longer exist are dropped.
-- @param string directory savegame directory
-- @param table vehicleSystem vehicle system used to check that a vehicle still exists
-- @return integer count number of home spots written
function HomeSpotStore:saveToDirectory(directory, vehicleSystem)
    local filename = directory .. "/" .. HomeSpotStore.FILENAME
    local xmlFile = createXMLFile("homeSpotsXML", filename, HomeSpotStore.XML_ROOT)
    if xmlFile == nil or xmlFile == 0 then
        return 0
    end

    setXMLInt(xmlFile, HomeSpotStore.XML_ROOT .. "#autoTidyHour", self.autoTidyHour)
    setXMLInt(xmlFile, HomeSpotStore.XML_ROOT .. "#markers", self.markerMode)

    local i = 0
    for uniqueId, components in pairs(self.spots) do
        if vehicleSystem:getVehicleByUniqueId(uniqueId) ~= nil then
            local key = string.format("%s.vehicle(%d)", HomeSpotStore.XML_ROOT, i)
            setXMLString(xmlFile, key .. "#uniqueId", uniqueId)

            for j, component in ipairs(components) do
                local componentKey = string.format("%s.component(%d)", key, j - 1)
                setXMLString(xmlFile, componentKey .. "#position", string.format("%.4f %.4f %.4f", unpack(component[1])))
                setXMLString(xmlFile, componentKey .. "#rotation", string.format("%.5f %.5f %.5f", unpack(component[2])))
            end

            i = i + 1
        end
    end

    saveXMLFile(xmlFile)
    delete(xmlFile)

    return i
end
