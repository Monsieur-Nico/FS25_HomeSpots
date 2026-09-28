-- Stand-ins for the parts of the FS25 engine and game scripts the mod uses.
-- Only functions that exist in the real game belong here, so a passing test never relies on made-up API.
local game = {
    nodes = {},
    files = {},
    notifications = {},
    subscriptions = {},
    actionEvents = {},
    contextEvents = {},
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

-- Network: events, streams and object ids. A stream is a list of typed values, so reading a
-- different type or count than was written fails the test like a broken stream would in the game.
game.eventClasses = {}
game.objects = {}
game.nextObjectId = 1

Event = {}
function Event.new(mt) return setmetatable({}, mt) end
function InitEventClass(classTable, name) game.eventClasses[name] = classTable end

function game.newStream()
    return {values = {}, readPos = 0}
end

local function streamWrite(kind, check)
    return function(stream, value)
        assert(check(value), string.format("%s cannot hold %s", kind, tostring(value)))
        table.insert(stream.values, {kind, value})
    end
end

local function streamRead(kind)
    return function(stream)
        stream.readPos = stream.readPos + 1
        local entry = stream.values[stream.readPos]
        assert(entry ~= nil, "read past the end of the stream")
        assert(entry[1] == kind, string.format("read %s where %s was written", kind, entry[1]))
        return entry[2]
    end
end

local function isInteger(min, max)
    return function(value)
        return type(value) == "number" and value == math.floor(value) and value >= min and value <= max
    end
end

local function isNumber(value) return type(value) == "number" end
local function isBoolean(value) return type(value) == "boolean" end

streamWriteBool, streamReadBool = streamWrite("Bool", isBoolean), streamRead("Bool")
streamWriteInt8, streamReadInt8 = streamWrite("Int8", isInteger(-128, 127)), streamRead("Int8")
streamWriteUInt8, streamReadUInt8 = streamWrite("UInt8", isInteger(0, 255)), streamRead("UInt8")
streamWriteUInt16, streamReadUInt16 = streamWrite("UInt16", isInteger(0, 65535)), streamRead("UInt16")
streamWriteFloat32, streamReadFloat32 = streamWrite("Float32", isNumber), streamRead("Float32")

NetworkUtil = {
    getObjectId = function(object) return object.objectId end,
    getObject = function(objectId) return game.objects[objectId] end,
    writeNodeObjectId = streamWrite("ObjectId", isInteger(1, 65535)),
    readNodeObjectId = streamRead("ObjectId"),
}

function game.setObjectId(object, objectId)
    object.objectId = objectId
    game.objects[objectId] = object
end

-- Single player runs a server without remote players; the multiplayer tests connect some
g_server = {connections = {}}
function g_server:broadcastEvent(event)
    for _, connection in ipairs(self.connections) do
        connection:sendEvent(event)
    end
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
    homeSpots_mapSendHome = "Send home",
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

-- Map menu: selecting an item sets the frame's actions and lists the active ones,
-- by title when an action has one, else by text name (as the game does for other mods' actions)
InGameMenuMapFrame = {}
function InGameMenuMapFrame:setMapSelectionItem(hotspot)
    self.currentHotspot = hotspot
    self.contextButtonList:reloadData()
end
function InGameMenuMapFrame.newFrame(contextActions)
    local frame = setmetatable({contextActions = contextActions}, {__index = InGameMenuMapFrame})
    frame.contextButtonList = {reloadData = function()
        frame.shownActions = {}
        for _, action in ipairs(frame.contextActions) do
            if action.isActive then
                table.insert(frame.shownActions, action.title or action.text)
            end
        end
    end}
    return frame
end
InGameMenuMapUtil = {getHotspotVehicle = function(hotspot) return hotspot.vehicle end}
Utils = {
    appendedFunction = function(original, appended)
        return function(...)
            if original ~= nil then
                original(...)
            end
            appended(...)
        end
    end,
    prependedFunction = function(original, prepended)
        return function(...)
            prepended(...)
            return original(...)
        end
    end,
    getFilename = function(filename, directory) return directory .. filename end,
}
g_currentModDirectory = "/mods/FS25_HomeSpots/"
g_currentModName = "FS25_HomeSpots"
GS_PRIO_NORMAL = 2
InputAction = {
    HOMESPOTS_SEND_ALL = "A", HOMESPOTS_SET = "B", HOMESPOTS_CLEAR = "C", HOMESPOTS_SEND_ONE = "D",
    MENU_BACK = "MENU_BACK", MENU_ACCEPT = "MENU_ACCEPT", MENU_EXTRA_1 = "MENU_EXTRA_1",
}
MessageType = {HOUR_CHANGED = "hour"}

function addModEventListener() end
function getNormalizedScreenValues(x, y) return x / 1000, y / 1000 end

MapHotspot = {CATEGORY_OTHER = 9}
function MapHotspot.new(mt) return setmetatable({visible = true}, mt) end
function MapHotspot.getClickCircle(radius) return {radius = radius} end
function MapHotspot:getIsVisible() return self.visible end
function MapHotspot:setWorldPosition(x, z) self.x, self.z = x, z end
function MapHotspot:delete() self.deleted = true end
Overlay = {}
function Overlay.new(filename)
    local overlay = {filename = filename}
    function overlay:setImage(newFilename) self.filename = newFilename end
    return overlay
end

g_messageCenter = {
    subscribe = function(_, messageType, callback, target) game.subscriptions[messageType] = {callback, target} end,
    unsubscribeAll = function() game.subscriptions = {} end,
}

-- Like FS25, an event id is built from the action and the target object, so the same action and target
-- registered in two input contexts share one id: the id then only reaches the event registered last.
-- game.contextEvents keeps each context's own events, which is what the help panel of that context shows.
g_inputBinding = {
    registerActionEvent = function(_, action, target)
        local context = game.inputContext or "PLAYER"
        game.contextEvents[context] = game.contextEvents[context] or {}
        for _, event in ipairs(game.contextEvents[context]) do
            if event.action == action and event.target == target then
                return false, ""
            end
        end

        local id = action .. "|" .. tostring(target) .. "|1"
        local event = {action = action, target = target, context = context, active = true}
        table.insert(game.contextEvents[context], event)
        game.actionEvents[id] = event
        return true, id
    end,
    removeActionEvent = function(_, id)
        local event = game.actionEvents[id]
        if event == nil then
            return
        end
        for index, contextEvent in ipairs(game.contextEvents[event.context]) do
            if contextEvent == event then
                table.remove(game.contextEvents[event.context], index)
                break
            end
        end
        game.actionEvents[id] = nil
    end,
    setActionEventText = function(_, id, text) game.actionEvents[id].text = text end,
    setActionEventTextVisibility = function(_, id, visible) game.actionEvents[id].visible = visible end,
    setActionEventTextPriority = function(_, id, priority) game.actionEvents[id].priority = priority end,
    setActionEventActive = function(_, id, active) game.actionEvents[id].active = active end,
}

-- Menus: the in-game menu with its pages, and a GUI loader that builds a page from its real XML file,
-- so a page only finds the elements its XML actually defines
MathUtil = {vector2Length = function(x, z) return math.sqrt(x * x + z * z) end}
-- Same corner order as the game's GuiUtils.getUVs
GuiUtils = {}
function GuiUtils.getUVs(uvs, ref)
    local x, y, width, height = uvs[1] / ref[1], uvs[2] / ref[2], uvs[3] / ref[1], uvs[4] / ref[2]
    return {x, 1 - y - height, x, 1 - y, x + width, 1 - y - height, x + width, 1 - y}
end
FocusManager = {setFocus = function(_, element) game.focusedElement = element end}
g_i18n.formatDistance = function(_, distance) return string.format("%d m", math.floor(distance + 0.5)) end

TabbedMenuFrameElement = {}
function TabbedMenuFrameElement.new(_, mt) return setmetatable({menuButtonInfo = {}}, mt) end
function TabbedMenuFrameElement:onGuiSetupFinished() end
function TabbedMenuFrameElement:initialize() end
function TabbedMenuFrameElement:onFrameOpen() end
function TabbedMenuFrameElement:update() end
function TabbedMenuFrameElement:setMenuButtonInfo(info) self.menuButtonInfo = info end
function TabbedMenuFrameElement:setMenuButtonInfoDirty() self.menuButtonsDirty = true end
function TabbedMenuFrameElement:getMenuButtonInfo() return self.menuButtonInfo end

local function newGuiElement(kind)
    local element = {kind = kind, isVisible = true}
    function element:setText(text) self.text = text end
    function element:setTextColor(r, g, b, a) self.textColor = {r, g, b, a} end
    function element:setVisible(isVisible) self.isVisible = isVisible end
    function element:setImageFilename(filename) self.imageFilename = filename end
    function element:setImageUVs(_, ...) self.imageUVs = {...} end
    return element
end

-- A list asks its data source for the rows and fills one cell per row, like the game's SmoothList
local function newSmoothList(cellNames)
    local list = newGuiElement("SmoothList")
    list.selectedIndex = 1
    list.cells = {}

    function list:setDataSource(dataSource) self.dataSource = dataSource end
    function list:setDelegate(delegate) self.delegate = delegate end
    function list:getSelectedIndexInSection() return self.selectedIndex end

    function list:reloadData()
        self.cells = {}
        local numItems = self.dataSource:getNumberOfItemsInSection(self, 1)
        for index = 1, numItems do
            local attributes = {}
            for _, name in ipairs(cellNames) do
                attributes[name] = newGuiElement("Text")
            end
            local cell = {getAttribute = function(_, name) return assert(attributes[name], "no cell element " .. name) end}
            self.dataSource:populateCellForItemInSection(self, 1, index, cell)
            self.cells[index] = attributes
        end
        self.selectedIndex = math.max(1, math.min(self.selectedIndex, numItems))
    end

    function list:setSelectedIndex(index)
        self.selectedIndex = index
        self.delegate:onListSelectionChanged(self, 1, index)
    end

    return list
end

InGameMenu = {}
g_gui = {screenControllers = {}}
function g_gui:loadGui(filename, name, controller, isFrame)
    assert(isFrame, "a menu page is loaded as a frame")
    local file = assert(io.open(filename:gsub("^" .. g_currentModDirectory, ""), "r"), "missing " .. filename)
    local xml = file:read("*a")
    file:close()

    local cellNames = {}
    for tag, attributes in xml:gmatch("<(%a+)([^>]*)>") do
        local cellName = attributes:match('name="([^"]+)"')
        if tag == "Text" and cellName ~= nil then
            table.insert(cellNames, cellName)
        end
    end
    for tag, attributes in xml:gmatch("<(%a+)([^>]*)>") do
        local id = attributes:match('id="([^"]+)"')
        if id ~= nil then
            controller[id] = tag == "SmoothList" and newSmoothList(cellNames) or newGuiElement(tag)
        end
    end

    controller.name = name
    controller:onGuiSetupFinished()
end

-- The game's in-game menu with a few of its own pages
function game.newInGameMenu()
    local menu = {pageFrames = {}, tabs = {}, pagingElement = {elements = {}, pages = {}}}
    for _, pageName in ipairs({"pageMapOverview", "pageSettings", "pageHelpLine"}) do
        local page = {name = pageName}
        menu[pageName] = page
        table.insert(menu.pageFrames, page)
        table.insert(menu.pagingElement.elements, page)
        table.insert(menu.pagingElement.pages, {element = page})
    end

    function menu.pagingElement:addElement(element)
        table.insert(self.elements, element)
        table.insert(self.pages, {element = element})
    end
    function menu.pagingElement:updateAbsolutePosition() end
    function menu.pagingElement:updatePageMapping() end
    function menu:registerPage(page) table.insert(self.pageFrames, page) end
    function menu:addPageTab(page, iconFilename, uvs) self.tabs[page] = {iconFilename = iconFilename, uvs = uvs} end
    function menu:rebuildTabList() self.numTabRebuilds = (self.numTabRebuilds or 0) + 1 end

    return menu
end

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
    function vehicle:getImageFilename() return "store/" .. self.name .. ".dds" end
    function vehicle:getOwnerFarmId() return self.farmId end
    function vehicle:getRootVehicle() return self.attacher ~= nil and self.attacher:getRootVehicle() or self end
    function vehicle:getAttacherVehicle() return self.attacher end
    function vehicle:getAttachedImplements() return self.implements end
    function vehicle:getIsAIActive() return self.isAIActive == true end
    function vehicle:getIsControlled() return self.isControlled == true end
    function vehicle:getOwnerConnection() return self.ownerConnection end
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
    game.setObjectId(vehicle, game.nextObjectId)
    game.nextObjectId = game.nextObjectId + 1

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
    isServer = true,
    isClient = true,
    isMasterUser = false,
    farmId = 1,
    getIsServer = function(self) return self.isServer end,
    getIsClient = function(self) return self.isClient end,
    getFarmId = function(self) return self.farmId end,
    userManager = {
        getUserIdByConnection = function(_, connection) return connection.userId end,
        getIsConnectionMasterUser = function(_, connection) return connection.isMasterUser == true end,
    },
    addIngameNotification = function(_, notificationType, text) table.insert(game.notifications, {notificationType, text}) end,
    addMapHotspot = function(_, hotspot) game.hotspotsOnMap[hotspot] = true end,
    removeMapHotspot = function(_, hotspot) game.hotspotsOnMap[hotspot] = nil end,
}

-- Farms of the players, by user id
game.userFarms = {}
g_farmManager = {
    getFarmByUserId = function(_, userId)
        local farmId = game.userFarms[userId]
        return farmId ~= nil and {farmId = farmId} or nil
    end,
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
