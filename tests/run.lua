-- Runs the Home Spots tests against stand-ins for the game.
-- Usage (from the repository root): lua5.1 tests/run.lua
package.path = "tests/?.lua;" .. package.path

local game = require("game_mock")

for _, name in ipairs({"HomeSpotArea", "HomeSpotStore", "HomeSpotHotspot", "HomeSpotSettings", "HomeSpots"}) do
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

HomeSpots.onMissionLoaded({missionInfo = {savegameDirectory = "/savegame1"}})

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
    assert(hotspot:getIsVisible())
    assertEquals(hotspot.x, 10, "x")
    assertEquals(hotspot.z, 0, "z")
    assert(hotspot.clickArea ~= nil, "marker can be clicked")
end)

test("spots and the tidy-up hour survive save and reload", function()
    HomeSpots.store.autoTidyHour = 20
    HomeSpots.onSaveCareer({savegameDirectory = "/savegame1"})
    HomeSpots.onMissionDeleted()
    assertEquals(game.countMapHotspots(), 0, "markers after leaving")

    HomeSpots.onMissionLoaded({missionInfo = {savegameDirectory = "/savegame1"}})
    assertEquals(HomeSpots.store.autoTidyHour, 20, "tidy-up hour")
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
    game.fireHourChanged(19)
    HomeSpots:update(16)
    assertEquals(getX(tractor), 800, "before the hour")

    game.fireHourChanged(20)
    HomeSpots:update(16)
    assertEquals(getX(tractor), 10, "at the hour")
    assertEquals(game.lastNotification():sub(1, 5), "Auto:", "message prefix")
end)

test("help panel names what set, update and remove will act on", function()
    HomeSpots.registerGlobalActionEvents(nil, nil)
    local events, ids = game.actionEvents, HomeSpots.actionEventIds

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

    test("tidy-up setting is an hour picker, " .. caseName, function()
        HomeSpotSettings.injectedLayout = nil
        HomeSpotSettings.optionElement = nil

        local layout = newElement("layout")
        local header = newElement("header")
        header.name = "sectionHeader"
        table.insert(layout.elements, header)
        table.insert(layout.elements, (newOptionRow(BinaryOptionElement)))
        local multiRow, multiOption = newOptionRow(MultiTextOptionElement)
        table.insert(layout.elements, multiRow)

        local frame = {generalSettingsLayout = layout, multiTimeScale = hasTimeScale and multiOption or nil}
        HomeSpots.onSettingsFrameOpen(frame)
        assertEquals(#layout.elements, 5, "header and row added")

        local option = HomeSpotSettings.optionElement
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

        HomeSpots.onSettingsFrameOpen(frame)
        assertEquals(#layout.elements, 5, "not added twice")
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

test("prompt clears as soon as the player looks away", function()
    HomeSpots.registerGlobalActionEvents(nil, nil)
    local events, ids = game.actionEvents, HomeSpots.actionEventIds

    lookRay = {300, 294, 0, 1}
    HomeSpots:update(16)
    assert(events[ids.HOMESPOTS_SET].active, "shown while facing it")

    lookRay = {300, 294, 0, -1}
    HomeSpots:update(16)
    assertEquals(events[ids.HOMESPOTS_SET].active, false, "hidden after looking away")
end)

print(string.format("\n%d passed, %d failed", numPassed, numFailed))
if numFailed > 0 then
    os.exit(1)
end
