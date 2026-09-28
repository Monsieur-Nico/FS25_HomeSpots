-- Runs the Home Spots tests against stand-ins for the game.
-- Usage (from the repository root): lua5.1 tests/run.lua
package.path = "tests/?.lua;" .. package.path

-- The plain Lua globals, before the game stand-ins are added, for the separate machines of the multiplayer tests
local luaGlobals = {}
for name, value in pairs(_G) do
    luaGlobals[name] = value
end

local game = require("game_mock")
local machine = require("machine")

for _, name in ipairs(machine.SCRIPTS) do
    dofile("scripts/" .. name .. ".lua")
end

local numFailed, numPassed = 0, 0

-- Tests run in order and share one savegame, like a play session
local function test(name, func)
    local success, errorMessage = pcall(func)
    if success then
        numPassed = numPassed + 1
        print("ok      " .. name)
    else
        numFailed = numFailed + 1
        print("FAILED  " .. name .. "\n        " .. tostring(errorMessage))
    end
end

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %q, got %q", message or "value", tostring(expected), tostring(actual)), 2)
    end
end

local tractor = game.newVehicle("t1", "Fendt", 10, 0)
local plough = game.newVehicle("p1", "Plough", 10, -6)
local trailer = game.newVehicle("x1", "Trailer", 30, 0)
local car = game.newVehicle("c1", "Pickup", 100, 100)
tractor.implements = {{object = plough}}
plough.attacher = tractor
game.currentVehicle = tractor

local function sendAllHome()
    HomeSpots:onSendAllHomeInput()
    HomeSpots:update(16)
end

local function getX(vehicle)
    return (game.getPosition(vehicle))
end

g_currentMission.missionInfo = {savegameDirectory = "/savegame1"}
HomeSpots.onMissionLoaded(g_currentMission)

test("set spot in a vehicle saves the whole combination", function()
    HomeSpots:onSetHomeInput()
    assert(HomeSpots.store:has(tractor) and HomeSpots.store:has(plough))
    assertEquals(game.lastNotification(), "saved Fendt, Plough")
    assertEquals(game.countMapHotspots(), 2, "map markers")
end)

test("set spot on foot saves only the looked at vehicle", function()
    game.currentVehicle = nil
    game.collisionHitNode = trailer.rootNode
    HomeSpots:onSetHomeInput()
    assert(HomeSpots.store:has(trailer))
    assertEquals(game.lastNotification(), "saved Trailer")
    assertEquals(game.countMapHotspots(), 3, "map markers")
end)

test("set spot on foot while looking at nothing does nothing", function()
    game.collisionHitNode = nil
    local numNotifications = #game.notifications
    HomeSpots:onSetHomeInput()
    assertEquals(#game.notifications, numNotifications, "notifications")
end)

test("map marker is named after its vehicle and placed on the spot", function()
    local hotspot = HomeSpots.hotspots["t1"]
    assertEquals(hotspot:getName(), "Home: Fendt")
    assertEquals(hotspot.x, 10, "x")
    assertEquals(hotspot.z, 0, "z")
    assert(hotspot.clickArea ~= nil, "marker can be clicked")
end)

test("map marker shows only while its vehicle is away, in orange", function()
    local hotspot = HomeSpots.hotspots["t1"]
    assertEquals(HomeSpots.store.markerMode, HomeSpotStore.MARKERS_AWAY, "default setting")
    assertEquals(hotspot:getIsVisible(), false, "hidden while parked at home")

    game.place(tractor, 400, 0)
    assert(hotspot:getIsVisible(), "shown while away")
    assertEquals(hotspot.icon.filename, HomeSpotHotspot.ICON_AWAY, "orange")

    game.place(tractor, 10.5, 0)
    assertEquals(hotspot:getIsVisible(), false, "hidden when nudged but home")
end)

test("marker setting: always shows green at home and orange away, off hides all", function()
    local hotspot = HomeSpots.hotspots["t1"]
    HomeSpots.store.markerMode = HomeSpotStore.MARKERS_ALWAYS
    assert(hotspot:getIsVisible(), "shown at home")
    assertEquals(hotspot.icon.filename, HomeSpotHotspot.ICON_HOME, "green")

    game.place(tractor, 400, 0)
    assert(hotspot:getIsVisible(), "shown away")
    assertEquals(hotspot.icon.filename, HomeSpotHotspot.ICON_AWAY, "orange")

    HomeSpots.store.markerMode = HomeSpotStore.MARKERS_OFF
    assertEquals(hotspot:getIsVisible(), false, "off")

    HomeSpots.store.markerMode = HomeSpotStore.MARKERS_ALWAYS
    game.place(tractor, 10, 0)
end)

test("spots and the tidy-up hour survive save and reload", function()
    HomeSpots.store.autoTidyHour = 20
    HomeSpots.onSaveCareer({savegameDirectory = "/savegame1"})
    HomeSpots.onMissionDeleted()
    assertEquals(game.countMapHotspots(), 0, "markers after leaving")
    assertEquals(HomeSpots.store.markerMode, HomeSpotStore.MARKERS_AWAY, "marker setting back to default")

    HomeSpots.onMissionLoaded(g_currentMission)
    assertEquals(HomeSpots.store.autoTidyHour, 20, "tidy-up hour")
    assertEquals(HomeSpots.store.markerMode, HomeSpotStore.MARKERS_ALWAYS, "marker setting")
    assert(HomeSpots.store:has(plough))
    assertEquals(game.countMapHotspots(), 3, "markers after reload")
end)

test("send all home moves everything back", function()
    game.place(tractor, 500, 0)
    game.place(plough, 500, -6)
    game.place(trailer, 520, 0)
    sendAllHome()
    assertEquals(getX(tractor), 10, "tractor")
    assertEquals(getX(plough), 10, "plough")
    assertEquals(getX(trailer), 30, "trailer")
    assertEquals(game.lastNotification(), "sent 3")
end)

test("a vehicle whose spot is taken stays where it is", function()
    game.place(trailer, 520, 0)
    game.place(car, 31, 1)
    sendAllHome()
    assertEquals(getX(trailer), 520, "trailer")
    assertEquals(game.lastNotification(), "home 2. blocked: Trailer")
    assertEquals(game.notifications[#game.notifications][1], FSBaseMission.INGAME_NOTIFICATION_INFO, "notification type")
end)

test("a vehicle parked right beside a spot does not block it", function()
    game.place(car, 33.1, 0)
    sendAllHome()
    assertEquals(getX(trailer), 30, "trailer")
end)

test("a blocked vehicle can in turn block another spot", function()
    game.place(car, 30, 0)
    game.place(trailer, 10, 0)
    game.place(tractor, 700, 0)
    sendAllHome()
    assertEquals(getX(tractor), 700, "tractor")
    assertEquals(getX(trailer), 10, "trailer")
end)

test("rotated vehicles block by their real outline", function()
    game.place(car, 33, 0, math.pi / 2)
    game.place(trailer, 900, 0)
    game.place(tractor, 700, 0)
    sendAllHome()
    assertEquals(getX(trailer), 900, "trailer blocked by turned car")

    game.place(car, 33.1, 0, 0)
    game.place(trailer, 900, 0)
    sendAllHome()
    assertEquals(getX(trailer), 30, "trailer fits beside straight car")
end)

test("vehicles in use are left alone", function()
    game.place(car, 200, 200)
    tractor.isControlled = true
    game.place(tractor, 700, 0)
    sendAllHome()
    assertEquals(getX(tractor), 700, "tractor")
    tractor.isControlled = false
end)

test("daily tidy-up runs at the chosen hour only", function()
    game.place(tractor, 800, 0)
    game.fireHourChanged(18)
    HomeSpots:update(16)
    assert(game.lastNotification() ~= "soon 20:00", "no heads-up two hours before")

    game.fireHourChanged(19)
    HomeSpots:update(16)
    assertEquals(getX(tractor), 800, "before the hour")
    assertEquals(game.lastNotification(), "soon 20:00", "heads-up one hour before")
    assertEquals(game.notifications[#game.notifications][1], FSBaseMission.INGAME_NOTIFICATION_INFO, "heads-up type")

    game.fireHourChanged(20)
    HomeSpots:update(16)
    assertEquals(getX(tractor), 10, "at the hour")
    assertEquals(game.lastNotification():sub(1, 5), "Auto:", "message prefix")
end)

test("help panel names what set, update and remove will act on", function()
    HomeSpots.registerGlobalActionEvents(nil, nil)
    local events, ids = game.actionEvents, HomeSpots.actionEventIds[HomeSpots.DEFAULT_INPUT_CONTEXT]

    game.collisionHitNode = nil
    HomeSpots:update(16)
    assertEquals(events[ids.HOMESPOTS_SET].active, false, "set hidden")
    assertEquals(events[ids.HOMESPOTS_CLEAR].active, false, "remove hidden")
    assert(events[ids.HOMESPOTS_SEND_ALL].visible, "send all shown")

    game.collisionHitNode = car.rootNode
    HomeSpots:update(16)
    assertEquals(events[ids.HOMESPOTS_SET].text, "set: Pickup")
    assertEquals(events[ids.HOMESPOTS_CLEAR].active, false, "remove hidden without spot")

    game.collisionHitNode = trailer.rootNode
    HomeSpots:update(16)
    assertEquals(events[ids.HOMESPOTS_SET].text, "update: Trailer")
    assertEquals(events[ids.HOMESPOTS_CLEAR].text, "clear: Trailer")
    assert(events[ids.HOMESPOTS_CLEAR].active, "remove shown")
end)

test("remove spot on foot", function()
    HomeSpots:onClearHomeInput()
    assert(not HomeSpots.store:has(trailer))
    assertEquals(game.countMapHotspots(), 2, "map markers")
    assertEquals(game.lastNotification(), "cleared Trailer")
    game.collisionHitNode = nil
end)

-- Settings page stand-ins: a layout with a header, an on/off toggle row and a multi choice row
MultiTextOptionElement, TextElement, BinaryOptionElement = {}, {}, {}
local superClassOf = {[BinaryOptionElement] = MultiTextOptionElement}

local function newElement(kind)
    local element = {kind = kind, elements = {}}

    function element:isa(class)
        local current = self.kind
        while current ~= nil do
            if current == class then
                return true
            end
            current = superClassOf[current]
        end
        return false
    end

    function element:clone(parent)
        local copy = newElement(self.kind)
        copy.name = self.name
        for _, child in ipairs(self.elements) do
            child:clone(copy).parent = copy
        end
        if parent ~= nil then
            table.insert(parent.elements, copy)
            copy.parent = parent
        end
        return copy
    end

    function element:setTexts(texts)
        assert(self.kind ~= BinaryOptionElement, "an on/off toggle takes exactly 2 texts")
        self.texts = texts
    end

    function element:setState(state) self.state = state end
    function element:setText(text) self.text = text end
    function element:setDisabled(isDisabled) self.isDisabled = isDisabled end
    function element:reloadFocusHandling() end
    function element:invalidateLayout() self.isInvalidated = true end

    return element
end

local function newOptionRow(kind)
    local row, option = newElement("row"), newElement(kind)
    option.parent = row
    table.insert(option.elements, newElement(TextElement))
    table.insert(row.elements, option)
    table.insert(row.elements, newElement(TextElement))
    return row, option
end

for _, hasTimeScale in ipairs({false, true}) do
    local caseName = hasTimeScale and "copying the time scale row" or "searching the layout"

    test("settings section has the tidy-up hour and marker options, " .. caseName, function()
        HomeSpotSettings.injectedLayout = nil

        local layout = newElement("layout")
        local header = newElement("header")
        header.name = "sectionHeader"
        table.insert(layout.elements, header)
        table.insert(layout.elements, (newOptionRow(BinaryOptionElement)))
        local multiRow, multiOption = newOptionRow(MultiTextOptionElement)
        table.insert(layout.elements, multiRow)

        local frame = {generalSettingsLayout = layout, multiTimeScale = hasTimeScale and multiOption or nil}
        HomeSpots.onSettingsFrameOpen(frame)
        assertEquals(#layout.elements, 6, "header and two rows added")

        local option = HomeSpotSettings.OPTIONS[1].element
        assert(option ~= nil and option.kind == MultiTextOptionElement, "copied a multi choice row, not a toggle")
        assertEquals(#option.texts, 25, "Off plus 24 hours")
        assertEquals(option.texts[22], "20:00")
        assertEquals(option.state, 22, "shows the saved hour")
        assertEquals(option.elements[1].text, "homeSpots_autoTidy_tooltip")
        assertEquals(layout.elements[5].elements[2].text, "homeSpots_autoTidy")

        option.onClickCallback(option.target, 1)
        assertEquals(HomeSpots.store.autoTidyHour, HomeSpotStore.AUTO_TIDY_OFF, "off")
        option.onClickCallback(option.target, 19)
        assertEquals(HomeSpots.store.autoTidyHour, 17, "17:00")
        option.onClickCallback(option.target, 22)

        local markers = HomeSpotSettings.OPTIONS[2].element
        assertEquals(layout.elements[6].elements[2].text, "homeSpots_markers")
        assertEquals(#markers.texts, 3, "away only, always, off")
        assertEquals(markers.state, HomeSpots.store.markerMode, "shows the saved setting")
        markers.onClickCallback(markers.target, HomeSpotStore.MARKERS_OFF)
        assertEquals(HomeSpots.store.markerMode, HomeSpotStore.MARKERS_OFF, "off")
        markers.onClickCallback(markers.target, HomeSpotStore.MARKERS_AWAY)

        HomeSpots.onSettingsFrameOpen(frame)
        assertEquals(#layout.elements, 6, "not added twice")
    end)
end

test("everything already home: nothing moves, one message", function()
    game.place(car, 200, 200)
    game.place(trailer, 300, 300)
    game.place(tractor, 10, 0, 0)
    game.place(plough, 10, -6)
    sendAllHome()
    assertEquals(game.lastNotification(), "all home")
end)

test("a small nudge still counts as home", function()
    game.place(tractor, 10.5, 0, math.rad(5))
    sendAllHome()
    assertEquals(getX(tractor), 10.5, "left in place")
    assertEquals(game.getYaw(tractor), math.rad(5), "not turned")
    assertEquals(game.lastNotification(), "all home")
end)

test("2 m off or turned 20 degrees gets moved back", function()
    game.place(tractor, 12, 0, 0)
    sendAllHome()
    assertEquals(getX(tractor), 10, "moved back")
    assertEquals(game.lastNotification(), "sent 1. home 1")

    game.place(tractor, 10, 0, math.rad(20))
    sendAllHome()
    assertEquals(game.getYaw(tractor), 0, "turned back")
end)

test("look ray finds a tool through a collision shape below its component", function()
    game.currentVehicle = nil
    local shape, ground = createTransformGroup(), createTransformGroup()
    game.parentOf[shape] = trailer.rootNode

    game.rayHits = {ground, shape}
    assertEquals(HomeSpots.getTargetVehicles()[1], trailer, "via parent node")

    game.rayHits = {ground}
    assertEquals(#HomeSpots.getTargetVehicles(), 0, "ground only")
    game.rayHits = {}
end)

test("tool without a hittable collision is found by its outline", function()
    game.place(car, 200, 200)
    game.place(trailer, 300, 300)
    game.place(plough, 305, 300, 0)

    lookRay = {300, 294, 0, 1}
    assertEquals(HomeSpots.getTargetVehicles()[1], trailer, "facing the trailer")

    lookRay = {300, 294, 0, -1}
    assertEquals(#HomeSpots.getTargetVehicles(), 0, "facing away")

    lookRay = {305, 290, 0, 1}
    assertEquals(#HomeSpots.getTargetVehicles(), 0, "10 m away")

    lookRay = {300, 294, 0, 1, 0.9}
    assertEquals(#HomeSpots.getTargetVehicles(), 0, "looking up over it")

    trailer.farmId = 2
    lookRay = {300, 294, 0, 1}
    assertEquals(#HomeSpots.getTargetVehicles(), 0, "another farm's tool")
    trailer.farmId = 1
end)

test("standing inside a vehicle's outline does not lock the prompt onto it", function()
    game.currentVehicle = nil
    game.place(trailer, 300, 300)
    game.place(plough, 305, 300, 0)

    lookRay = {300, 300, 0, -1}
    assertEquals(#HomeSpots.getTargetVehicles(), 0, "looking away from inside the trailer")

    lookRay = {300, 300, 1, 0}
    assertEquals(HomeSpots.getTargetVehicles()[1], plough, "looking at the tool next to it")
end)

test("prompt clears as soon as the player looks away", function()
    HomeSpots.registerGlobalActionEvents(nil, nil)
    local events, ids = game.actionEvents, HomeSpots.actionEventIds[HomeSpots.DEFAULT_INPUT_CONTEXT]

    lookRay = {300, 294, 0, 1}
    HomeSpots:update(16)
    assert(events[ids.HOMESPOTS_SET].active, "shown while facing it")

    lookRay = {300, 294, 0, -1}
    HomeSpots:update(16)
    assertEquals(events[ids.HOMESPOTS_SET].active, false, "hidden after looking away")
end)

test("heads-up for a midnight tidy-up comes at 23:00", function()
    HomeSpots.store.autoTidyHour = 0
    game.fireHourChanged(23)
    assertEquals(game.lastNotification(), "soon 00:00")
    HomeSpots.store.autoTidyHour = 20
end)

local function sendTargetHome()
    HomeSpots:onSendTargetHomeInput()
    HomeSpots:update(16)
end

test("send this one home from the seat moves only that combination, with the player", function()
    lookRay = {300, 294, 0, -1}
    tractor.implements = {{object = plough}}
    plough.attacher = tractor
    tractor.isControlled = true
    game.currentVehicle = tractor
    game.place(tractor, 600, 0)
    game.place(plough, 600, -6)
    game.place(trailer, 620, 0)
    game.place(car, 200, 200)

    sendTargetHome()
    assertEquals(getX(tractor), 10, "tractor")
    assertEquals(getX(plough), 10, "plough")
    assertEquals(getX(trailer), 620, "trailer stays")
    assertEquals(game.lastNotification(), "sent: Fendt, Plough")
    tractor.isControlled = false
end)

test("send this one home on foot unhooks and moves only the looked at tool", function()
    HomeSpots.store:set(trailer)
    game.place(trailer, 30, 0)
    tractor.implements = {{object = plough}}
    plough.attacher = tractor
    game.place(tractor, 650, 0)
    game.place(plough, 650, -6)
    game.currentVehicle = nil
    game.collisionHitNode = plough.rootNode

    sendTargetHome()
    assertEquals(getX(plough), 10, "plough")
    assertEquals(getX(tractor), 650, "tractor stays")
    assertEquals(plough.attacher, nil, "plough unhooked")
    assertEquals(game.lastNotification(), "sent: Plough")
end)

test("send this one home says when it is already home", function()
    sendTargetHome()
    assertEquals(getX(plough), 10, "plough")
    assertEquals(game.lastNotification(), "home: Plough")
end)

test("send this one home leaves a worker's vehicle alone", function()
    game.place(tractor, 650, 0)
    tractor.isAIActive = true
    game.currentVehicle = tractor
    game.collisionHitNode = nil

    sendTargetHome()
    assertEquals(getX(tractor), 650, "tractor")
    assertEquals(game.lastNotification(), "inuse 1")
    tractor.isAIActive = false
end)

test("send this one home only shows for something with a home spot", function()
    HomeSpots.registerGlobalActionEvents(nil, nil)
    local events, ids = game.actionEvents, HomeSpots.actionEventIds[HomeSpots.DEFAULT_INPUT_CONTEXT]
    game.currentVehicle = nil

    game.collisionHitNode = car.rootNode
    HomeSpots:update(16)
    assertEquals(events[ids.HOMESPOTS_SEND_ONE].active, false, "hidden without spot")

    game.collisionHitNode = trailer.rootNode
    HomeSpots:update(16)
    assert(events[ids.HOMESPOTS_SEND_ONE].active, "shown with spot")
    assertEquals(events[ids.HOMESPOTS_SEND_ONE].text, "send: Trailer")
    game.collisionHitNode = nil
end)

test("map menu offers Send home only for a vehicle away from its spot", function()
    game.currentVehicle = nil
    tractor.implements, plough.attacher = {}, nil
    game.place(tractor, 10, 0)
    game.place(car, 200, 200)
    local frame = InGameMenuMapFrame.newFrame({{text = "Enter", isActive = true}, {text = "Sell", isActive = true}})

    frame:setMapSelectionItem({vehicle = tractor})
    assertEquals(table.concat(frame.shownActions, ","), "Enter,Sell", "hidden while home")

    game.place(tractor, 650, 0)
    frame:setMapSelectionItem({vehicle = tractor})
    assertEquals(table.concat(frame.shownActions, ","), "Enter,Sell,Send home", "listed last while away")

    frame:setMapSelectionItem({vehicle = car})
    assertEquals(#frame.shownActions, 2, "hidden for a vehicle without a spot")

    frame:setMapSelectionItem(nil)
    assertEquals(#frame.shownActions, 2, "hidden without a selection")

    frame.contextActions = {{text = "Enter", isActive = true}}
    frame:setMapSelectionItem({vehicle = tractor})
    assertEquals(table.concat(frame.shownActions, ","), "Enter,Send home", "added again to a rebuilt list")
end)

test("Send home from the map moves the vehicle and hides the action", function()
    local frame = InGameMenuMapFrame.newFrame({})
    frame:setMapSelectionItem({vehicle = tractor})
    frame.homeSpotsAction.callback()
    assertEquals(#frame.shownActions, 0, "hidden once sent")

    HomeSpots:update(16)
    assertEquals(getX(tractor), 10, "tractor home")
    assertEquals(game.lastNotification(), "sent: Fendt")

    frame:setMapSelectionItem(frame.currentHotspot)
    assertEquals(#frame.shownActions, 0, "nothing left to send")
end)

-- The game registers the on-foot keys without a context name, and the vehicle keys again whenever
-- the vehicle refreshes its own (getting in, hitching or unhitching, being sent home)
local function registerKeys(contextName)
    game.inputContext = contextName or "PLAYER"
    HomeSpots.registerGlobalActionEvents(nil, contextName)
    game.inputContext = nil
end

local function getShownEvent(actionName)
    local shown
    for _, event in ipairs(game.contextEvents.PLAYER) do
        if event.action == InputAction[actionName] then
            assertEquals(shown, nil, "one entry per key on foot")
            shown = event
        end
    end
    return shown
end

test("help panel follows the target on foot after leaving a vehicle", function()
    registerKeys(nil)
    game.currentVehicle = nil
    game.collisionHitNode = tractor.rootNode
    HomeSpots:update(16)
    assertEquals(getShownEvent("HOMESPOTS_SET").text, "update: Fendt", "looking at the tractor")

    game.currentVehicle = tractor
    registerKeys("VEHICLE")
    HomeSpots:update(16)
    registerKeys("VEHICLE")
    HomeSpots:update(16)

    game.currentVehicle = nil
    registerKeys(nil)
    game.collisionHitNode = car.rootNode
    HomeSpots:update(16)
    assertEquals(getShownEvent("HOMESPOTS_SET").text, "set: Pickup", "on foot entry names what is looked at")
    assertEquals(getShownEvent("HOMESPOTS_SEND_ONE").active, false, "on foot send hidden")
    game.collisionHitNode = nil
end)

-- Home Spots page of the in-game menu
local menu = game.newInGameMenu()
local page

local function getShownRows()
    local rows = {}
    for _, cell in ipairs(page.homeSpotsList.cells) do
        table.insert(rows, string.format("%s|%s|%s", cell.name.text, cell.status.text, cell.distance.text))
    end
    return table.concat(rows, ", ")
end

local function getButtonTexts()
    local texts = {}
    for _, button in ipairs(page:getMenuButtonInfo()) do
        table.insert(texts, button.text or button.inputAction)
    end
    return table.concat(texts, ",")
end

local function getPreview()
    if not page.homeSpotsPreview.isVisible then
        return "hidden"
    end
    return table.concat({page.homeSpotsPreviewImage.imageFilename, page.homeSpotsPreviewName.text,
        page.homeSpotsPreviewStatus.text, page.homeSpotsPreviewDistance.text}, "|")
end

test("Home Spots page is added to the menu once, right after the settings", function()
    g_gui.screenControllers[InGameMenu] = menu
    HomeSpotOverview:update(16)
    HomeSpotOverview:update(16)

    page = menu[HomeSpotOverview.PAGE_NAME]
    assert(page ~= nil, "page added")
    assertEquals(menu.pagingElement.elements[3], page, "listed after the settings")
    assertEquals(menu.pagingElement.pages[3].element, page, "paged after the settings")
    assertEquals(menu.pageFrames[3], page, "tab after the settings")
    assertEquals(#menu.pageFrames, 4, "added once")
    assertEquals(menu.tabs[page].iconFilename, g_currentModDirectory .. "icon_homeSpotsMenu.dds", "tab icon")
    assertEquals(page.homeSpotsHeaderText.text, "homeSpots_settingsSection", "title")
    assertEquals(page.homeSpotsColumnDistance.text, "homeSpots_columnDistance", "column title")
end)

test("page lists the farm's vehicles with a spot, away ones first", function()
    game.currentVehicle = nil
    tractor.implements, plough.attacher = {}, nil
    tractor.isControlled, tractor.isAIActive = false, false
    game.place(tractor, 510, 0, 0)
    game.place(plough, 10, -6, 0)
    game.place(trailer, 30, 0, 0)
    HomeSpots.store:set(trailer)
    game.place(trailer, 30, 40, 0)
    car.farmId = 2
    HomeSpots.store:set(car)
    game.place(car, 300, 300)
    tractor.mapHotspot = {name = "Fendt marker"}

    page:onFrameOpen()
    assertEquals(getShownRows(), "Fendt|homeSpots_statusAway|500 m, Trailer|homeSpots_statusAway|40 m, Plough|homeSpots_statusHome|-")
    assertEquals(page:getSelectedRow().vehicle, tractor, "first row selected")
    assertEquals(page.homeSpotsList.cells[1].status.textColor[1], 0.98, "away in orange")
    assertEquals(page.homeSpotsEmptyText.isVisible, false, "no empty text")
    assertEquals(game.focusedElement, page.homeSpotsList, "list has the focus")
    assertEquals(getButtonTexts(), "MENU_BACK,Send home,input_HOMESPOTS_SEND_ALL,homeSpots_showOnMap,homeSpots_removeSpot")
    assertEquals(page.homeSpotsSummary.text, "2 away, 0 in use, 1 home", "summary")
    assertEquals(page.homeSpotsPreviewTools.isVisible, false, "no tools hooked")
    assertEquals(getPreview(), "store/Fendt.dds|Fendt|homeSpots_statusAway|500 m", "preview of the selected vehicle")
    assertEquals(table.concat(page.homeSpotsPreviewImage.imageUVs, " "), "0 0 0 1 1 0 1 1", "whole picture")
    assertEquals(page.homeSpotsPreviewStatus.textColor[1], 0.98, "preview status in orange")
end)

test("Send home on the page moves the selected vehicle with its tools", function()
    tractor.implements = {{object = plough}}
    plough.attacher = tractor
    game.place(plough, 510, -6, 0)
    page:update(HomeSpotOverviewFrame.REFRESH_INTERVAL)
    assert(page.homeSpotsPreviewTools.isVisible, "hooked tools shown")
    assertEquals(page.homeSpotsPreviewTools.text, "With: Plough", "tool that comes along")

    page.sendButtonInfo.callback()
    HomeSpots:update(16)
    assertEquals(getX(tractor), 10, "tractor home")
    assertEquals(getX(plough), 10, "its tool home")
    assertEquals(getX(trailer), 30, "trailer stays away")

    page:update(HomeSpotOverviewFrame.REFRESH_INTERVAL)
    assertEquals(getShownRows(), "Trailer|homeSpots_statusAway|40 m, Fendt|homeSpots_statusHome|-, Plough|homeSpots_statusHome|-")
    assertEquals(page:getSelectedRow().vehicle, tractor, "selection follows the tractor down the list")
    assertEquals(getPreview(), "store/Fendt.dds|Fendt|homeSpots_statusHome|-", "preview follows it too")
    assertEquals(getButtonTexts(), "MENU_BACK,input_HOMESPOTS_SEND_ALL,homeSpots_showOnMap,homeSpots_removeSpot", "nothing to send for it")
end)

test("page hides Send home for a vehicle that is home or in use", function()
    page.homeSpotsList:setSelectedIndex(3)
    assertEquals(getPreview(), "store/Plough.dds|Plough|homeSpots_statusHome|-", "preview of the tool picked")
    page.homeSpotsList:setSelectedIndex(2)
    assertEquals(getButtonTexts(), "MENU_BACK,input_HOMESPOTS_SEND_ALL,homeSpots_showOnMap,homeSpots_removeSpot", "home")

    game.place(tractor, 200, 0)
    tractor.isControlled = true
    page:update(HomeSpotOverviewFrame.REFRESH_INTERVAL)
    assertEquals(page.homeSpotsList.cells[2].status.text, "homeSpots_statusInUse", "driven")
    page.homeSpotsList:setSelectedIndex(2)
    assertEquals(getButtonTexts(), "MENU_BACK,input_HOMESPOTS_SEND_ALL,homeSpots_showOnMap,homeSpots_removeSpot", "in use")
    assertEquals(page.homeSpotsSummary.text, "1 away, 1 in use, 1 home", "summary counts the driven one")

    tractor.isControlled = false
    game.place(tractor, 10, 0)
end)

test("Send all home on the page moves everything home", function()
    page.sendAllButtonInfo.callback()
    HomeSpots:update(16)
    assertEquals(getX(trailer), 30, "trailer home")

    page:update(HomeSpotOverviewFrame.REFRESH_INTERVAL)
    assertEquals(getShownRows(), "Fendt|homeSpots_statusHome|-, Plough|homeSpots_statusHome|-, Trailer|homeSpots_statusHome|-")
end)

test("Show on map opens the map page with the vehicle, or the one its tool hangs on", function()
    page.homeSpotsList:setSelectedIndex(1)
    assertEquals(page:getSelectedRow().vehicle, tractor)
    page.mapButtonInfo.callback()
    assertEquals(menu.currentPage, menu.pageMapOverview, "map page opened")
    assertEquals(menu.pageMapOverview.selectedHotspot, tractor.mapHotspot, "tractor picked")
    assertEquals(menu.pageMapOverview.pannedTo, tractor.mapHotspot, "tractor in view")

    page.homeSpotsList:setSelectedIndex(2)
    assertEquals(page:getSelectedRow().vehicle, plough)
    tractor.implements, plough.attacher = {{object = plough}}, tractor
    menu.pageMapOverview.selectedHotspot = nil
    page.mapButtonInfo.callback()
    assertEquals(menu.pageMapOverview.selectedHotspot, tractor.mapHotspot, "hooked tool shows its tractor")

    page.homeSpotsList:setSelectedIndex(3)
    assertEquals(page:getSelectedRow().vehicle, trailer)
    assertEquals(getButtonTexts(), "MENU_BACK,input_HOMESPOTS_SEND_ALL,homeSpots_removeSpot", "no marker, no map button")
end)

test("Remove spot asks first, then removes only the selected spot", function()
    page.removeButtonInfo.callback()
    assertEquals(game.openDialog.text, "Remove Trailer?", "question names it")
    game.openDialog.answer(false)
    assert(HomeSpots.store:has(trailer), "kept on No")

    page.removeButtonInfo.callback()
    game.openDialog.answer(true)
    assert(not HomeSpots.store:has(trailer), "removed on Yes")
    assert(HomeSpots.store:has(tractor) and HomeSpots.store:has(plough), "others kept")

    page:update(HomeSpotOverviewFrame.REFRESH_INTERVAL)
    assertEquals(getShownRows(), "Fendt|homeSpots_statusHome|-, Plough|homeSpots_statusHome|-")
    assertEquals(page.homeSpotsSummary.text, "0 away, 0 in use, 2 home", "summary follows")
    HomeSpots.store:set(trailer)
end)

test("page without any spot says how to set one", function()
    local spots = HomeSpots.store.spots
    HomeSpots.store.spots = {}
    page:update(HomeSpotOverviewFrame.REFRESH_INTERVAL)

    assertEquals(#page.homeSpotsList.cells, 0, "no rows")
    assert(page.homeSpotsEmptyText.isVisible, "empty text shown")
    assertEquals(page.homeSpotsEmptyText.text, "homeSpots_overviewEmpty")
    assertEquals(getButtonTexts(), "MENU_BACK", "only back")
    assertEquals(getPreview(), "hidden", "no preview")
    assertEquals(page.homeSpotsSummary.isVisible, false, "no summary")

    HomeSpots.store.spots = spots
    car.farmId = 1
end)

require("multiplayer")(test, assertEquals, machine.newNetwork(luaGlobals))

print(string.format("\n%d passed, %d failed", numPassed, numFailed))
if numFailed > 0 then
    os.exit(1)
end
