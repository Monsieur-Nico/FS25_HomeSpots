---Stores one home spot per vehicle, keyed by the vehicle's unique id.
-- A home spot is the world position and rotation of every component of the
-- vehicle, the same data the savegame uses to place vehicles on load.
HomeSpotStore = {}
local HomeSpotStore_mt = Class(HomeSpotStore)

HomeSpotStore.FILENAME = "homeSpots.xml"
HomeSpotStore.XML_ROOT = "homeSpots"
HomeSpotStore.AUTO_TIDY_OFF = -1


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

    self.spots = {}
    self.autoTidyHour = HomeSpotStore.AUTO_TIDY_OFF

    return self
end


---Remove every home spot and restore default settings
function HomeSpotStore:reset()
    self.spots = {}
    self.autoTidyHour = HomeSpotStore.AUTO_TIDY_OFF
end


---Returns all home spots
-- @return table spots components by vehicle unique id
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
function HomeSpotStore:set(vehicle)
    local components = {}

    for i, component in ipairs(vehicle.components) do
        local x, y, z = getWorldTranslation(component.node)
        local rx, ry, rz = getWorldRotation(component.node)

        components[i] = {{x, y, z}, {rx, ry, rz}}
    end

    self.spots[vehicle:getUniqueId()] = components
end


---Returns the home spot of a vehicle
-- @param table vehicle vehicle
-- @return table components component positions, or nil when the vehicle has no home spot
function HomeSpotStore:get(vehicle)
    return self.spots[vehicle:getUniqueId()]
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
    local uniqueId = vehicle:getUniqueId()
    local hadSpot = self.spots[uniqueId] ~= nil

    self.spots[uniqueId] = nil

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
