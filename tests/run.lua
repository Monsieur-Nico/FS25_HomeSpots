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

test("every script is loaded, in the order modDesc.xml lists them", function()
    local listed = {}
    for name in io.open("modDesc.xml"):read("*a"):gmatch('<sourceFile filename="scripts/(%w+)%.lua"') do
        table.insert(listed, name)
    end
    assertEquals(table.concat(machine.SCRIPTS, " "), table.concat(listed, " "), "the tests load the scripts the way modDesc.xml lists them")

    local numFiles = 0
    for _ in io.popen("ls scripts"):lines() do
        numFiles = numFiles + 1
    end
    assertEquals(numFiles, #listed, "no script in scripts/ is left out of modDesc.xml")
end)

local tractor = game.newVehicle("t1", "Fendt", 10, 0)
local plough = game.newVehicle("p1", "Plough", 10, -6)
local trailer = game.newVehicle("x1", "Trailer", 30, 0)
local car = game.newVehicle("c1", "Pickup", 100, 100)
plough.spec_motorized = nil
trailer.spec_motorized = nil
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

local function getZ(vehicle)
    return select(2, game.getPosition(vehicle))
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

test("a vehicle whose spot is taken parks in the nearest free space beside it", function()
    game.place(trailer, 520, 0)
    game.place(car, 31, 1)
    sendAllHome()
    assertEquals(getX(trailer), 27.5, "trailer beside the taken spot, clear of the car")
    assertEquals(select(2, game.getPosition(trailer)), 0, "and level with the spot")
    assertEquals(game.lastNotification(), "sent 1. home 2. beside: Trailer")
    assert(HomeSpots.store:has(trailer), "the home spot itself is kept")
    assertEquals(HomeSpots.store:get(trailer)[1][1][1], 30, "home spot unchanged")
end)

test("a vehicle parked beside its spot goes home once the spot is free", function()
    game.place(car, 200, 200)
    sendAllHome()
    assertEquals(getX(trailer), 30, "trailer")
end)

test("with no free space within reach a vehicle stays where it is", function()
    local maxDistance = HomeSpotNearby.MAX_DISTANCE
    HomeSpotNearby.MAX_DISTANCE, HomeSpotNearby.offsets = 1, nil

    game.place(trailer, 520, 0)
    game.place(car, 31, 1)
    sendAllHome()
    assertEquals(getX(trailer), 520, "trailer")
    assertEquals(game.lastNotification(), "home 2. blocked: Trailer")
    assertEquals(game.notifications[#game.notifications][1], FSBaseMission.INGAME_NOTIFICATION_INFO, "notification type")

    HomeSpotNearby.MAX_DISTANCE, HomeSpotNearby.offsets = maxDistance, nil
end)

test("a vehicle parked right beside a spot does not block it", function()
    game.place(car, 33.1, 0)
    sendAllHome()
    assertEquals(getX(trailer), 30, "trailer")
end)

test("a vehicle standing on another's spot moves aside and frees it", function()
    game.place(car, 30, 0)
    game.place(trailer, 10, 0)
    game.place(tractor, 700, 0)
    sendAllHome()
    assertEquals(getX(tractor), 10, "tractor gets its spot")
    assertEquals(getX(trailer), 26.5, "trailer beside the car, clear of it")
    game.place(car, 200, 200)
    sendAllHome()
    assertEquals(getX(trailer), 30, "trailer goes home next time")
end)

test("with no free space beside, a blocked vehicle can in turn block another spot", function()
    local maxDistance = HomeSpotNearby.MAX_DISTANCE
    HomeSpotNearby.MAX_DISTANCE, HomeSpotNearby.offsets = 1, nil

    game.place(car, 30, 0)
    game.place(trailer, 10, 0)
    game.place(tractor, 700, 0)
    sendAllHome()
    assertEquals(getX(tractor), 700, "tractor")
    assertEquals(getX(trailer), 10, "trailer")

    HomeSpotNearby.MAX_DISTANCE, HomeSpotNearby.offsets = maxDistance, nil
    game.place(car, 200, 200)
    game.place(trailer, 30, 0)
    sendAllHome()
    assertEquals(getX(tractor), 10, "tractor")
end)

test("rotated vehicles block by their real outline", function()
    game.place(car, 33, 0, math.pi / 2)
    game.place(trailer, 900, 0)
    game.place(tractor, 700, 0)
    sendAllHome()
    assertEquals(getX(trailer), 28.5, "trailer moves beside the turned car")

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

    test("settings section has the tidy-up hour, marker, fee and detailed log options, " .. caseName, function()
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
        assertEquals(#layout.elements, 8, "header and four rows added")

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

        local fee = HomeSpotSettings.OPTIONS[3].element
        assertEquals(layout.elements[7].elements[2].text, "homeSpots_fee")
        assertEquals(table.concat(fee.texts, ", "), "homeSpots_off, Low $25/km, Normal $50/km, High $100/km")
        assertEquals(fee.state, HomeSpotStore.FEE_OFF, "off by default")
        fee.onClickCallback(fee.target, HomeSpotStore.FEE_HIGH)
        assertEquals(HomeSpots.store.feeLevel, HomeSpotStore.FEE_HIGH, "high")
        assertEquals(HomeSpots.store.markerMode, HomeSpotStore.MARKERS_AWAY, "other settings kept")

        game.costMultiplier = 0.5
        HomeSpots.onSettingsFrameOpen(frame)
        assertEquals(fee.texts[3], "Normal $25/km", "prices follow the economic difficulty")
        game.costMultiplier = 1
        fee.onClickCallback(fee.target, HomeSpotStore.FEE_OFF)

        local detailLog = HomeSpotSettings.OPTIONS[4].element
        assertEquals(layout.elements[8].elements[2].text, "homeSpots_detailLog")
        assertEquals(table.concat(detailLog.texts, ", "), "homeSpots_off, homeSpots_on")
        assertEquals(detailLog.state, HomeSpotStore.LOG_OFF, "off by default")
        detailLog.onClickCallback(detailLog.target, HomeSpotStore.LOG_ON)
        assertEquals(HomeSpots.store.detailLog, HomeSpotStore.LOG_ON, "on")
        assertEquals(HomeSpots.store.markerMode, HomeSpotStore.MARKERS_AWAY, "other settings kept")
        detailLog.onClickCallback(detailLog.target, HomeSpotStore.LOG_OFF)

        HomeSpots.onSettingsFrameOpen(frame)
        assertEquals(#layout.elements, 8, "not added twice")
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
test("realism fee: off by default, nothing is charged", function()
    game.place(trailer, 30, 0)
    HomeSpots.store:set(trailer)
    game.place(tractor, 1010, 0)
    local balance = game.balances[1]
    sendAllHome()
    assertEquals(getX(tractor), 10, "moved home")
    assertEquals(game.balances[1], balance, "free")
    assert(not game.lastNotification():find("cost"), "no cost in the message")
end)

test("realism fee: each vehicle pays per km home, a tool hooked to it rides along free", function()
    HomeSpots.changeSettings({feeLevel = HomeSpotStore.FEE_NORMAL})
    game.place(tractor, 2010, 0)
    game.place(plough, 2010, -6)
    tractor.implements = {{object = plough}}
    plough.attacher = tractor
    game.place(trailer, 530, 0)
    local balance = game.balances[1]

    sendAllHome()
    assertEquals(getX(tractor), 10, "tractor home")
    assertEquals(getX(trailer), 30, "trailer home")
    assertEquals(balance - game.balances[1], 125, "2 km for the tractor and 0.5 km for the trailer at 50 per km, the plough free")
    assertEquals(game.lastNotification(), "sent 3. cost $125")
end)

test("realism fee: the price follows the economic difficulty and saves with the savegame", function()
    game.costMultiplier = 0.4
    game.place(trailer, 1030, 0)
    local balance = game.balances[1]
    sendAllHome()
    assertEquals(balance - game.balances[1], 20, "1 km at 50 x 0.4")
    game.costMultiplier = 1

    HomeSpots.onSaveCareer(g_currentMission.missionInfo)
    HomeSpots.store:reset()
    HomeSpots.store:loadFromDirectory("/savegame1")
    assertEquals(HomeSpots.store.feeLevel, HomeSpotStore.FEE_NORMAL, "fee level saved")
end)

test("the detailed log setting is saved with the savegame", function()
    HomeSpots.changeSettings({detailLog = HomeSpotStore.LOG_ON})
    HomeSpots.onSaveCareer(g_currentMission.missionInfo)
    HomeSpots.store:reset()
    assertEquals(HomeSpots.store.detailLog, HomeSpotStore.LOG_OFF, "off after a reset")
    HomeSpots.store:loadFromDirectory("/savegame1")
    assertEquals(HomeSpots.store.detailLog, HomeSpotStore.LOG_ON, "on again")
    HomeSpots.changeSettings({detailLog = HomeSpotStore.LOG_OFF})
    HomeSpots.onSaveCareer(g_currentMission.missionInfo)
end)

test("realism fee: without the money nothing moves and the player is told the price", function()
    game.place(trailer, 1030, 0)
    local balance = game.balances[1]
    game.balances[1] = 30
    sendAllHome()
    assertEquals(getX(trailer), 1030, "stays")
    assertEquals(game.balances[1], 30, "nothing charged")
    assertEquals(game.lastNotification(), "no money $50")

    game.balances[1] = balance
    sendAllHome()
    assertEquals(getX(trailer), 30, "goes once the farm can pay")
end)

test("realism fee: the daily send-home charges even when the farm is short", function()
    HomeSpots.store.autoTidyHour = 20
    game.place(trailer, 1030, 0)
    local balance = game.balances[1]
    game.balances[1] = 10
    game.fireHourChanged(20)
    HomeSpots:update(16)
    assertEquals(getX(trailer), 30, "sent home")
    assertEquals(game.balances[1], -40, "charged all the same, like other running costs")

    game.balances[1] = balance
    HomeSpots.store.autoTidyHour = HomeSpotStore.AUTO_TIDY_OFF
    HomeSpots.changeSettings({feeLevel = HomeSpotStore.FEE_OFF})
end)

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

-- Shed spots: a shed of the farm with its open side at z = 0, and a silo, which is no shed
local function parkInShed()
    HomeSpots:onFindShedInput()
    HomeSpots:update(16)
end

local function getSpot(vehicle)
    local position = HomeSpots.store:get(vehicle)[1][1]
    return string.format("%.1f %.1f %.1f", position[1], position[2], position[3])
end

local function setSpotAt(vehicle, x, z)
    HomeSpots.store:setByKey(HomeSpots.store:getKey(vehicle), {{{x, 0, z}, {0, 0, 0}}})
end

local spotsBeforeSheds = {}
for key, components in pairs(HomeSpots.store:getAll()) do
    spotsBeforeSheds[key] = components
end

local shed = game.newShed("Machine shed", 1, 200, 0, 220, 16, 5)
local silo = game.newShed("Silo", 1, 240, 0, 260, 10, 5, "SILOS")

test("park in a shed shows in the help panel for what the player looks at", function()
    registerKeys(nil)
    game.currentVehicle = nil
    game.collisionHitNode = trailer.rootNode
    HomeSpots:update(16)
    assertEquals(getShownEvent("HOMESPOTS_FIND_SHED").text, "shed: Trailer", "names the target")
    assertEquals(getShownEvent("HOMESPOTS_FIND_SHED").active, true, "shown")

    game.collisionHitNode = nil
    HomeSpots:update(16)
    assertEquals(getShownEvent("HOMESPOTS_FIND_SHED").active, false, "hidden without a target")
end)

test("park in a shed: the tractor stands in front and its tool behind it, under the roof, facing out of the open side", function()
    tractor.implements = {{object = plough}}
    plough.attacher = tractor
    tractor.isControlled = true
    game.currentVehicle = tractor
    game.place(tractor, 150, 0, 0)
    game.place(plough, 150, -6, 0)

    parkInShed()
    assertEquals(getSpot(tractor), "218.2 0.1 2.8", "tractor at the open front, at the left end of the line, just off the floor")
    assertEquals(getSpot(plough), "218.2 0.1 8.1", "plough right behind the tractor")
    assertEquals(string.format("%.1f %.2f", getX(tractor), math.abs(game.getYaw(tractor))), "218.2 3.14", "moved there, facing out")
    assertEquals(string.format("%.1f", getZ(plough)), "8.1", "plough moved")
    assertEquals(game.notifications[#game.notifications - 1][2], "in shed Fendt, Plough", "spots saved")
    assertEquals(game.lastNotification(), "sent: Fendt, Plough", "and sent there")
    assertEquals(HomeSpots.hotspots["t1"].x, HomeSpots.store:get(tractor)[1][1][1], "map marker follows")
    tractor.isControlled = false
end)

test("park in a shed: machines that drive themselves fill the front row, tools the row behind, as many side by side as fit", function()
    local spotsBefore = {}
    for key, components in pairs(HomeSpots.store:getAll()) do
        spotsBefore[key] = components
    end
    tractor.implements = {{object = plough}, {object = trailer}, {object = car}}
    plough.attacher, trailer.attacher, car.attacher = tractor, tractor, tractor
    tractor.isControlled = true
    game.currentVehicle = tractor
    game.place(tractor, 150, 0, 0)
    game.place(plough, 150, -6, 0)
    game.place(trailer, 150, -12, 0)
    game.place(car, 150, -18, 0)

    parkInShed()
    local front, back = {}, {}
    for _, vehicle in ipairs({tractor, car}) do
        assertEquals(string.format("%.1f", getZ(vehicle)), "2.8", vehicle.name .. " at the open front")
        table.insert(front, string.format("%.1f", getX(vehicle)))
    end
    for _, vehicle in ipairs({plough, trailer}) do
        assertEquals(string.format("%.1f", getZ(vehicle)), "8.1", vehicle.name .. " right behind the front row")
        table.insert(back, string.format("%.1f", getX(vehicle)))
    end
    table.sort(front)
    table.sort(back)
    assertEquals(table.concat(front, " "), "214.9 218.2", "two machines side by side in the front row")
    assertEquals(table.concat(back, " "), "214.9 218.2", "two tools, one behind each")
    assertEquals(string.format("%.2f", math.abs(game.getYaw(plough))), "3.14", "tools face out too")

    tractor.implements = {{object = plough}}
    trailer.attacher, car.attacher = nil, nil
    game.place(tractor, 150, 0, 0)
    game.place(plough, 150, -6, 0)
    game.place(trailer, 30, 0, 0)
    game.place(car, 100, 100, 0)
    HomeSpots.store:clearSpots()
    for key, components in pairs(spotsBefore) do
        HomeSpots.store:setByKey(key, components)
    end
    setSpotAt(plough, 201.8, 8.1)
    tractor.isControlled = false
end)

test("park in a shed: nothing is parked where the roof does not reach", function()
    local carport = game.newShed("Carport", 1, 400, 0, 420, 16, 5)
    game.removeSolid(carport.solids[4])
    local roof = game.addSolid("short roof", CollisionFlag.BUILDING, 399.7, 5, 0, 420.3, 5.3, 9)
    shed.farmId = 2
    game.currentVehicle = nil
    game.collisionHitNode = trailer.rootNode
    game.place(trailer, 150, 20, 0)

    parkInShed()
    local z = getZ(trailer)
    assert(z > 0 and z + 2.5 <= 9, "the whole trailer is under the roof, it stands at " .. z)

    shed.farmId = 1
    game.removeSolid(roof)
    game.removeShed(carport)
end)

test("park in a shed: a row of posts inside the edge of the floor keeps vehicles inside them, where the roof is", function()
    local carport = game.newShed("Posted carport", 1, 500, 0, 520, 16, 5)
    game.removeSolid(carport.solids[4])
    local posts = {}
    for _, x in ipairs({502, 508, 514, 519}) do
        table.insert(posts, game.addSolid("post", CollisionFlag.BUILDING, x - 0.2, 0, 1.3, x + 0.2, 5, 1.7))
    end
    shed.farmId = 2
    game.currentVehicle = nil
    game.collisionHitNode = car.rootNode
    game.place(car, 150, 20, 0)

    parkInShed()
    local z = getZ(car)
    assert(z >= 4.09, "the nose stays behind the posts at 1.3 m, the car stands at " .. z)
    assertEquals(string.format("%.2f", math.abs(game.getYaw(car))), "3.14", "facing out between the posts")

    shed.farmId = 1
    for _, post in ipairs(posts) do
        game.removeSolid(post)
    end
    game.removeShed(carport)
    HomeSpots.store:remove(car)
end)

test("park in a shed: in a shelter with only a back wall, a post in front does not turn vehicles sideways", function()
    local shelter = game.newShed("Shelter", 1, 300, 0, 320, 16, 5)
    game.removeSolid(shelter.solids[2])
    game.removeSolid(shelter.solids[3])
    local post = game.addSolid("post", CollisionFlag.BUILDING, 309.8, 0, -0.2, 310.2, 5, 0.2)
    shed.farmId = 2
    game.currentVehicle = nil
    game.collisionHitNode = car.rootNode
    local spot = HomeSpots.store:get(car)
    game.place(car, 290, 20, 0)

    parkInShed()
    assertEquals(getSpot(car), "318.2 0.1 2.8", "at the front, at the left end of the line")
    assertEquals(string.format("%.2f", math.abs(game.getYaw(car))), "3.14", "facing out of the front, not along the shelter")

    HomeSpots.store:setByKey("c1", spot)
    shed.farmId = 1
    game.removeSolid(post)
    game.removeShed(shelter)
end)

test("park in a shed: a pallet in the way is left room", function()
    HomeSpots.store:clearSpots()
    local pallet = game.addSolid("pallet", CollisionFlag.DYNAMIC_OBJECT, 217.7, 0, 9, 219.5, 1.5, 11)
    game.currentVehicle = nil
    game.collisionHitNode = trailer.rootNode
    game.place(trailer, 150, 20, 0)

    parkInShed()
    assertEquals(getSpot(trailer), "215.9 0.1 9.8", "next to the pallet, not on it, a tractor's length from the front")
    assertEquals(string.format("%.1f", getX(trailer)), "215.9", "moved")
    game.removeSolid(pallet)
end)

local function getShedLog()
    local lines, info = {}, Logging.info
    Logging.info = function(text, ...)
        table.insert(lines, string.format(text, ...))
    end
    parkInShed()
    Logging.info = info

    return lines
end

test("park in a shed: one log line per machine, and the details only with the detailed log on", function()
    HomeSpots.store:clearSpots()
    game.currentVehicle = nil
    game.collisionHitNode = trailer.rootNode
    game.place(trailer, 150, 20, 0)

    local lines = getShedLog()
    assertEquals(#lines, 1, "one line")
    assert(lines[1]:find("Trailer got a home spot in 'Machine shed'", 1, true), lines[1])

    HomeSpots.changeSettings({detailLog = HomeSpotStore.LOG_ON})
    game.place(trailer, 150, 20, 0)
    lines = getShedLog()
    HomeSpots.changeSettings({detailLog = HomeSpotStore.LOG_OFF})
    assert(#lines >= 3, "the room and which way the finder faces too")
    assert(table.concat(lines, "\n"):find("the finder faces", 1, true), "which way the finder faces")
end)

test("park in a shed: a machine gives up once it has tried the most places it may", function()
    HomeSpots.store:clearSpots()
    game.currentVehicle = nil
    game.collisionHitNode = trailer.rootNode
    game.place(trailer, 150, 20, 0)
    HomeSpotShed.MAX_PLACES_TRIED = 0

    parkInShed()
    HomeSpotShed.MAX_PLACES_TRIED = 30000
    assertEquals(game.lastNotification(), "no shed room", "no place found in time")
    assertEquals(getX(trailer), 150, "not moved")
end)

test("park in a shed: a tool parked alone goes behind a tractor that already has its spot in the shed", function()
    HomeSpots.store:clearSpots()
    setSpotAt(tractor, 210, 2.8)
    game.currentVehicle = nil
    game.collisionHitNode = trailer.rootNode
    game.place(trailer, 150, 20, 0)

    parkInShed()
    assertEquals(getSpot(trailer), "210.0 0.1 8.1", "right behind the tractor's spot")
end)

test("park in a shed: a tool goes behind the first machine in line with room behind it, then behind the next", function()
    HomeSpots.store:clearSpots()
    setSpotAt(tractor, 218.2, 2.8)
    setSpotAt(car, 214.9, 2.8)
    game.currentVehicle = nil
    game.collisionHitNode = trailer.rootNode
    game.place(trailer, 150, 20, 0)

    parkInShed()
    assertEquals(getSpot(trailer), "218.2 0.1 8.1", "behind the first one in line, from the left")

    local pallet = game.addSolid("pallet", CollisionFlag.DYNAMIC_OBJECT, 217.2, 0, 6, 219.7, 1.5, 10)
    game.place(trailer, 150, 20, 0)
    parkInShed()
    assertEquals(getSpot(trailer), "214.9 0.1 8.1", "the space behind the first one is taken, so behind the next one")

    game.removeSolid(pallet)
    HomeSpots.store:clearSpots()
    setSpotAt(plough, 210, 6)
    game.place(trailer, 150, 20, 0)
    parkInShed()
    assertEquals(getSpot(trailer), "210.0 0.1 11.3", "a tool parks behind another tool that has its spot there")
end)

test("park in a shed: a tractor takes the front line in front of a tool that stands snug behind where it would be", function()
    HomeSpots.store:clearSpots()
    setSpotAt(plough, 218.2, 8.06)
    tractor.implements = {}
    game.currentVehicle = nil
    game.collisionHitNode = tractor.rootNode
    game.place(tractor, 150, 0, 0)

    parkInShed()
    assertEquals(getSpot(tractor), "218.2 0.1 2.8", "in the front line, in front of the tool, not past it")

    tractor.implements = {{object = plough}}
    game.place(plough, 150, -6, 0)
    HomeSpots.store:clearSpots()
end)

test("park in a shed: a tool of the same kind as one in the shed goes behind it, before the machines that come first in line", function()
    HomeSpots.store:clearSpots()
    setSpotAt(tractor, 218.2, 2.8)
    setSpotAt(car, 213.5, 2.8)
    setSpotAt(plough, 213.5, 5)
    game.currentVehicle = nil
    game.collisionHitNode = trailer.rootNode
    game.place(trailer, 150, 20, 0)

    parkInShed()
    assertEquals(getSpot(trailer), "218.2 0.1 8.1", "another kind of tool goes behind the first one in line")

    plough.configFileName, trailer.configFileName = "tool.xml", "tool.xml"
    game.place(trailer, 150, 20, 0)
    parkInShed()
    assertEquals(getSpot(trailer), "213.5 0.1 10.3", "the same kind goes behind the one it is like")
    plough.configFileName, trailer.configFileName = nil, nil
    game.place(plough, 150, -6, 0)
end)

test("park in a shed: two machines fit side by side in a lane between a column and the wall when it is only just wide enough", function()
    local lane = game.newShed("Lane shed", 1, 600, 0, 620, 16, 5)
    local column = game.addSolid("column", CollisionFlag.BUILDING, 612.85, 0, 0, 613.05, 5, 16)
    shed.farmId = 2
    local spotsBefore = {}
    for key, components in pairs(HomeSpots.store:getAll()) do
        spotsBefore[key] = components
    end
    tractor.implements = {{object = car}}
    car.attacher = tractor
    tractor.isControlled = true
    game.currentVehicle = tractor
    game.place(tractor, 150, 0, 0)
    game.place(car, 150, -6, 0)

    parkInShed()
    local xs = {string.format("%.1f", getX(tractor)), string.format("%.1f", getX(car))}
    table.sort(xs)
    assertEquals(table.concat(xs, " "), "614.9 618.2", "both stand in the 6.95 m lane, snug against each other")
    assertEquals(string.format("%.1f %.1f", getZ(tractor), getZ(car)), "2.8 2.8", "both in the front line, free to drive out")

    tractor.implements = {{object = plough}}
    car.attacher = nil
    game.place(tractor, 150, 0, 0)
    game.place(car, 100, 100, 0)
    HomeSpots.store:clearSpots()
    for key, components in pairs(spotsBefore) do
        HomeSpots.store:setByKey(key, components)
    end
    tractor.isControlled = false
    game.currentVehicle = nil
    shed.farmId = 1
    game.removeSolid(column)
    game.removeShed(lane)
end)

test("park in a shed: a tractor and two tools fill a line of the shed front to back, one behind the other", function()
    local deep = game.newShed("Deep shed", 1, 400, 0, 420, 30, 5)
    shed.farmId = 2
    local spotsBefore = {}
    for key, components in pairs(HomeSpots.store:getAll()) do
        spotsBefore[key] = components
    end
    tractor.implements = {{object = plough}, {object = trailer}}
    plough.attacher, trailer.attacher = tractor, tractor
    tractor.isControlled = true
    game.currentVehicle = tractor
    game.place(tractor, 150, 0, 0)
    game.place(plough, 150, -6, 0)
    game.place(trailer, 150, -12, 0)

    parkInShed()
    assertEquals(getSpot(tractor), "418.2 0.1 2.8", "tractor at the front, at the left end")
    assertEquals(getSpot(plough), "418.2 0.1 8.1", "first tool behind the tractor")
    assertEquals(getSpot(trailer), "418.2 0.1 13.4", "second tool behind the first")

    tractor.implements = {{object = plough}}
    trailer.attacher = nil
    game.place(tractor, 150, 0, 0)
    game.place(plough, 150, -6, 0)
    game.place(trailer, 30, 0, 0)
    HomeSpots.store:clearSpots()
    for key, components in pairs(spotsBefore) do
        HomeSpots.store:setByKey(key, components)
    end
    setSpotAt(trailer, 201.8, 8.1)
    tractor.isControlled = false
    game.currentVehicle = nil
    shed.farmId = 1
    game.removeShed(deep)
end)

test("park in a shed: without a shed of the farm nothing changes and the player is told", function()
    shed.farmId = 2
    local spot = getSpot(trailer)
    game.place(trailer, 150, 20, 0)

    parkInShed()
    assertEquals(game.lastNotification(), "no shed room", "the silo does not count")
    assertEquals(getSpot(trailer), spot, "spot kept")
    assertEquals(getX(trailer), 150, "not moved")
    shed.farmId = 1
end)

test("a home spot that runs into a wall moves to the nearest free space beside it", function()
    HomeSpots.store:setByKey("x1", {{{210, 0, 16}, {0, 0, 0}}})
    game.collisionHitNode = trailer.rootNode

    sendTargetHome()
    local x, z = game.getPosition(trailer)
    assertEquals(x, 210, "in line with the spot")
    assertEquals(z, 13, "in front of the back wall, clear of it")
    assertEquals(game.lastNotification(), "sent: Trailer. beside: Trailer", "player is told")
end)

test("a home spot in a wall with no free space beside it stays where it is", function()
    local maxDistance = HomeSpotNearby.MAX_DISTANCE
    HomeSpotNearby.MAX_DISTANCE, HomeSpotNearby.offsets = 1, nil
    game.place(trailer, 150, 20, 0)

    sendTargetHome()
    assertEquals(getX(trailer), 150, "stays put")
    assertEquals(game.lastNotification(), "blocked: Trailer", "player is told")

    HomeSpotNearby.MAX_DISTANCE, HomeSpotNearby.offsets = maxDistance, nil
    game.collisionHitNode = nil
end)

-- Nearest free space beside a taken spot, and the question before a spot that overlaps another

local function sendTrailerHome()
    game.currentVehicle = nil
    game.collisionHitNode = trailer.rootNode
    sendTargetHome()
    game.collisionHitNode = nil
end

test("a space beside a taken spot keeps clear of another vehicle's home spot", function()
    HomeSpots.store:clearSpots()
    setSpotAt(trailer, 30, 0)
    setSpotAt(car, 27, 0)
    car.isControlled = true
    game.place(car, 31, 1)
    game.place(trailer, 520, 0)

    sendTrailerHome()
    local x, z = game.getPosition(trailer)
    assertEquals(x, 34.5, "on the other side, not on the car's own spot beside it")
    assertEquals(z, 0, "level with the spot")
    car.isControlled = false
end)

test("a space beside a taken spot keeps clear of a pallet", function()
    HomeSpots.store:clearSpots()
    setSpotAt(trailer, 30, 0)
    local pallet = game.addSolid("pallet", CollisionFlag.DYNAMIC_OBJECT, 24, 0, -1, 27, 1.5, 1)
    game.place(trailer, 520, 0)

    sendTrailerHome()
    assertEquals(getX(trailer), 34.5, "on the other side, not on the pallet")
    game.removeSolid(pallet)
end)

test("a vehicle sent beside its spot pays for the way to where it stands", function()
    HomeSpots.changeSettings({feeLevel = HomeSpotStore.FEE_NORMAL})
    local balance = game.balances[1]
    game.place(trailer, 2030, 0)

    sendTrailerHome()
    assertEquals(game.balances[1], balance - 100, "2,002.5 m at 50 per km")

    game.balances[1] = balance
    HomeSpots.changeSettings({feeLevel = HomeSpotStore.FEE_OFF})
end)

test("a spot that overlaps another vehicle's home spot asks first", function()
    HomeSpots.store:clearSpots()
    setSpotAt(trailer, 30, 0)
    game.place(trailer, 30, 0)
    game.place(car, 31, 1)
    game.currentVehicle = nil
    game.collisionHitNode = car.rootNode

    HomeSpots:onSetHomeInput()
    assertEquals(game.openDialog.text, "overlaps Trailer", "names the vehicle whose spot it is")
    game.openDialog.answer(false)
    assert(not HomeSpots.store:has(car), "nothing saved on No")

    HomeSpots:onSetHomeInput()
    game.openDialog.answer(true)
    assert(HomeSpots.store:has(car), "saved on Yes")
    assertEquals(game.lastNotification(), "saved Pickup")
    HomeSpots.store:remove(car)
    game.collisionHitNode = nil
end)

test("a spot that overlaps nothing, or only its own old spot, is saved without asking", function()
    game.place(car, 200, 200)
    game.currentVehicle = nil
    game.collisionHitNode = car.rootNode
    HomeSpots:onSetHomeInput()
    assertEquals(game.openDialog, nil, "clear ground")
    assert(HomeSpots.store:has(car), "saved")
    HomeSpots.store:remove(car)

    game.collisionHitNode = trailer.rootNode
    HomeSpots:onSetHomeInput()
    assertEquals(game.openDialog, nil, "updating a vehicle's own spot")

    game.place(car, 33.1, 0)
    game.collisionHitNode = car.rootNode
    HomeSpots:onSetHomeInput()
    assertEquals(game.openDialog, nil, "parked right beside another spot")
    HomeSpots.store:remove(car)
    game.collisionHitNode = nil
end)

test("a combination is saved together without asking about its own spots", function()
    HomeSpots.store:clearSpots()
    tractor.implements = {{object = plough}}
    plough.attacher = tractor
    game.place(tractor, 10, 0)
    game.place(plough, 10, -6)
    setSpotAt(tractor, 10, 0)
    setSpotAt(plough, 10, -6)
    game.currentVehicle = tractor

    HomeSpots:onSetHomeInput()
    assertEquals(game.openDialog, nil, "no question")
    assertEquals(game.lastNotification(), "saved Fendt, Plough")
    game.currentVehicle = nil
end)

game.removeShed(shed)
game.removeShed(silo)
HomeSpots.store:clearSpots()
for key, components in pairs(spotsBeforeSheds) do
    HomeSpots.store:setByKey(key, components)
end

require("multiplayer")(test, assertEquals, machine.newNetwork(luaGlobals))

print(string.format("\n%d passed, %d failed", numPassed, numFailed))
if numFailed > 0 then
    os.exit(1)
end
