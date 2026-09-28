-- Stand-ins for the parts of the FS25 engine and game scripts the mod uses.
-- Only functions that exist in the real game belong here, so a passing test never relies on made-up API.
local game = {
    nodes = {},
    files = {},
    notifications = {},
    subscriptions = {},
    actionEvents = {},
    hotspotsOnMap = {},
    nodeToVehicle = {},
    parentOf = {},
    rayHits = {},
    collisionHitNode = nil,
    currentVehicle = nil,
}

unpack = unpack or table.unpack

function Class(classTable, superClass)
    local mt = {__index = classTable}
    if superClass ~= nil then
        setmetatable(classTable, {__index = superClass})
        classTable.superClass = function()
            return superClass
        end
    end
    return mt
end

-- XML (legacy handle based API)
local xmlHandles, nextXmlHandle = {}, 1

local function openXml(path, data)
    local handle = nextXmlHandle
    nextXmlHandle = nextXmlHandle + 1
    xmlHandles[handle] = {path = path, data = data}
    return handle
end

function fileExists(path) return game.files[path] ~= nil end
function createXMLFile(_, path) return openXml(path, {}) end
function loadXMLFile(_, path) return openXml(path, game.files[path]) end
function setXMLString(handle, key, value) xmlHandles[handle].data[key] = value end
function getXMLString(handle, key) return xmlHandles[handle].data[key] end
function setXMLInt(handle, key, value) xmlHandles[handle].data[key] = value end
function getXMLInt(handle, key) return xmlHandles[handle].data[key] end
function saveXMLFile(handle) game.files[xmlHandles[handle].path] = xmlHandles[handle].data end

function hasXMLProperty(handle, key)
    for existingKey in pairs(xmlHandles[handle].data) do
        if existingKey:sub(1, #key) == key then
            return true
        end
    end
    return false
end

function delete(handle)
    xmlHandles[handle] = nil
end

-- Scene nodes: position and rotation only; directions use the y rotation
function game.newNode(x, z, yaw)
    table.insert(game.nodes, {t = {x, 0, z}, r = {0, yaw or 0, 0}})
    return #game.nodes
end

function createTransformGroup() return game.newNode(0, 0, 0) end
function setTranslation(node, x, y, z) game.nodes[node].t = {x, y, z} end
function setRotation(node, x, y, z) game.nodes[node].r = {x, y, z} end
function getWorldTranslation(node) return unpack(game.nodes[node].t) end
function getWorldRotation(node) return unpack(game.nodes[node].r) end
function entityExists(node) return node ~= nil and node ~= 0 end
function getParent(node) return game.parentOf[node] or 0 end

function localDirectionToWorld(node, localX, _, localZ)
    local yaw = game.nodes[node].r[2]
    local cos, sin = math.cos(yaw), math.sin(yaw)
    return localX * cos + localZ * sin, 0, -localX * sin + localZ * cos
end

-- Physics: the collision hit node (if any) is reported first, then any extra hits
CollisionFlag = {VEHICLE = 2}

function raycastAll(_, _, _, _, _, _, maxDistance, callbackName, target, collisionMask)
    assert(collisionMask == CollisionFlag.VEHICLE, "look ray only checks vehicles")
    assert(maxDistance == 6, "look ray reaches 6 m")

    local hits = {game.collisionHitNode}
    for _, hit in ipairs(game.rayHits) do
        table.insert(hits, hit)
    end

    for _, hit in ipairs(hits) do
        if not target[callbackName](target, hit, 0, 0, 0, 1, 0, 0, 0, 0, hit) then
            break
        end
    end
end

-- Game
local texts = {
    homeSpots_saved = "saved %s",
    homeSpots_cleared = "cleared %s",
    homeSpots_setFor = "set: %s",
    homeSpots_updateFor = "update: %s",
    homeSpots_clearFor = "clear: %s",
    homeSpots_sentHome = "sent %d",
    homeSpots_inUse = "inuse %d",
    homeSpots_blocked = "blocked: %s",
    homeSpots_mapMarker = "Home: %s",
    homeSpots_autoTidyPrefix = "Auto:",
    homeSpots_alreadyHome = "home %d",
    homeSpots_allHome = "all home",
    homeSpots_sendHomeFor = "send: %s",
    homeSpots_tidySoon = "soon %s",
    homeSpots_sentHomeFor = "sent: %s",
    homeSpots_alreadyHomeFor = "home: %s",
}

g_i18n = {getText = function(_, name) return texts[name] or name end}

Logging = {
    info = function(text, ...) print("INFO " .. string.format(text, ...)) end,
    warning = function(text, ...) print("WARN " .. string.format(text, ...)) end,
    error = function(text, ...) error("LOGGED " .. string.format(text, ...)) end,
}

FSBaseMission = {INGAME_NOTIFICATION_OK = 1, INGAME_NOTIFICATION_INFO = 2}
PlayerInputComponent, Mission00, FSCareerMissionInfo, InGameMenuSettingsFrame = {}, {}, {}, {}
Utils = {
    appendedFunction = function(_, appended) return appended end,
    getFilename = function(filename, directory) return directory .. filename end,
}
g_currentModDirectory = "/mods/FS25_HomeSpots/"
g_currentModName = "FS25_HomeSpots"
GS_PRIO_NORMAL = 2
InputAction = {HOMESPOTS_SEND_ALL = "A", HOMESPOTS_SET = "B", HOMESPOTS_CLEAR = "C", HOMESPOTS_SEND_ONE = "D"}
MessageType = {HOUR_CHANGED = "hour"}

function addModEventListener() end
function getNormalizedScreenValues(x, y) return x / 1000, y / 1000 end

MapHotspot = {CATEGORY_OTHER = 9}
function MapHotspot.new(mt) return setmetatable({visible = true}, mt) end
function MapHotspot.getClickCircle(radius) return {radius = radius} end
function MapHotspot:getIsVisible() return self.visible end
function MapHotspot:setWorldPosition(x, z) self.x, self.z = x, z end
function MapHotspot:delete() self.deleted = true end
Overlay = {new = function(filename) return {filename = filename} end}

g_messageCenter = {
    subscribe = function(_, messageType, callback, target) game.subscriptions[messageType] = {callback, target} end,
    unsubscribeAll = function() game.subscriptions = {} end,
}

-- FS25 action event ids are strings
local nextActionEventId = 1
g_inputBinding = {
    registerActionEvent = function(_, action)
        local id = "event" .. nextActionEventId
        nextActionEventId = nextActionEventId + 1
        game.actionEvents[id] = {action = action, active = true}
        return true, id
    end,
    setActionEventText = function(_, id, text) game.actionEvents[id].text = text end,
    setActionEventTextVisibility = function(_, id, visible) game.actionEvents[id].visible = visible end,
    setActionEventTextPriority = function(_, id, priority) game.actionEvents[id].priority = priority end,
    setActionEventActive = function(_, id, active) game.actionEvents[id].active = active end,
}

-- Vehicles
game.vehicles = {}

function game.newVehicle(uniqueId, name, x, z, yaw)
    local node = game.newNode(x, z, yaw)
    local vehicle = {
        uniqueId = uniqueId,
        name = name,
        components = {{node = node}},
        rootNode = node,
        farmId = 1,
        implements = {},
        size = {width = 3, length = 5, widthOffset = 0, lengthOffset = 0},
    }

    function vehicle:getUniqueId() return self.uniqueId end
    function vehicle:getFullName() return self.name end
    function vehicle:getOwnerFarmId() return self.farmId end
    function vehicle:getRootVehicle() return self.attacher ~= nil and self.attacher:getRootVehicle() or self end
    function vehicle:getAttacherVehicle() return self.attacher end
    function vehicle:getAttachedImplements() return self.implements end
    function vehicle:getIsAIActive() return self.isAIActive == true end
    function vehicle:getIsControlled() return self.isControlled == true end
    function vehicle:removeFromPhysics() end
    function vehicle:addToPhysics() end

    function vehicle:getChildVehicles()
        local children = {self}
        for _, implement in ipairs(self.implements) do
            table.insert(children, implement.object)
        end
        return children
    end

    function vehicle:detachImplementByObject(object)
        for i, implement in ipairs(self.implements) do
            if implement.object == object then
                table.remove(self.implements, i)
                object.attacher = nil
                break
            end
        end
    end

    function vehicle:setAbsolutePosition(_, _, _, _, _, _, components)
        for i, component in ipairs(self.components) do
            game.nodes[component.node].t = {unpack(components[i][1])}
            game.nodes[component.node].r = {unpack(components[i][2])}
        end
    end

    game.nodeToVehicle[node] = vehicle
    table.insert(game.vehicles, vehicle)

    return vehicle
end

function game.place(vehicle, x, z, yaw)
    game.nodes[vehicle.rootNode].t = {x, 0, z}
    if yaw ~= nil then
        game.nodes[vehicle.rootNode].r = {0, yaw, 0}
    end
end

function game.getPosition(vehicle)
    return game.nodes[vehicle.rootNode].t[1], game.nodes[vehicle.rootNode].t[3]
end

function game.getYaw(vehicle)
    return game.nodes[vehicle.rootNode].r[2]
end

-- Player: look ray is {x, z, dirX, dirZ, dirY}, eyes at 1.7 m, looking slightly down by default
lookRay = {0, 0, 1, 0}

g_localPlayer = {
    getCurrentVehicle = function() return game.currentVehicle end,
    getLookRay = function() return lookRay[1], 1.7, lookRay[2], lookRay[3], lookRay[5] or -0.3, lookRay[4] end,
}

g_currentMission = {
    vehicleSystem = {
        vehicles = game.vehicles,
        getVehicleByUniqueId = function(_, uniqueId)
            for _, vehicle in ipairs(game.vehicles) do
                if vehicle.uniqueId == uniqueId then
                    return vehicle
                end
            end
        end,
        getVehicleByNodeId = function(_, node) return game.nodeToVehicle[node] end,
    },
    environment = {currentHour = 0},
    getIsServer = function() return true end,
    getFarmId = function() return 1 end,
    addIngameNotification = function(_, notificationType, text) table.insert(game.notifications, {notificationType, text}) end,
    addMapHotspot = function(_, hotspot) game.hotspotsOnMap[hotspot] = true end,
    removeMapHotspot = function(_, hotspot) game.hotspotsOnMap[hotspot] = nil end,
}

function game.lastNotification()
    return game.notifications[#game.notifications][2]
end

function game.countMapHotspots()
    local count = 0
    for _ in pairs(game.hotspotsOnMap) do
        count = count + 1
    end
    return count
end

function game.fireHourChanged(hour)
    g_currentMission.environment.currentHour = hour
    local subscription = game.subscriptions[MessageType.HOUR_CHANGED]
    subscription[1](subscription[2])
end

return game
