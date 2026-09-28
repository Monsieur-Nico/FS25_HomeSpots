---The Home Spots page of the in-game menu: every vehicle and tool of the player's farm that has a home spot,
-- whether it is home, away or in use and how far it is from its spot, with Send home for the selected one
-- and Send all home.
HomeSpotOverview = {}
HomeSpotOverview.PAGE_NAME = "pageHomeSpots"
HomeSpotOverview.GUI_NAME = "homeSpotsOverview"
HomeSpotOverview.XML_FILENAME = Utils.getFilename("gui/HomeSpotOverviewFrame.xml", g_currentModDirectory)
HomeSpotOverview.ICON_FILENAME = Utils.getFilename("icon_homeSpotsMenu.dds", g_currentModDirectory)
-- The page is listed right after this page of the game's menu, or last when the game has no such page
HomeSpotOverview.INSERT_AFTER_PAGE = "pageSettings"

-- In-game menus the page was added to (or tried), so each gets the page once
HomeSpotOverview.triedMenus = setmetatable({}, {__mode = "k"})

HomeSpotOverview.STATUS_AWAY = 1
HomeSpotOverview.STATUS_IN_USE = 2
HomeSpotOverview.STATUS_HOME = 3

HomeSpotOverview.STATUS_TEXTS = {
    [HomeSpotOverview.STATUS_AWAY] = "homeSpots_statusAway",
    [HomeSpotOverview.STATUS_IN_USE] = "homeSpots_statusInUse",
    [HomeSpotOverview.STATUS_HOME] = "homeSpots_statusHome",
}

-- Status colours, matching the map markers: orange away, green home
HomeSpotOverview.STATUS_COLORS = {
    [HomeSpotOverview.STATUS_AWAY] = {0.98, 0.45, 0.05, 1},
    [HomeSpotOverview.STATUS_IN_USE] = {0.25, 0.55, 0.95, 1},
    [HomeSpotOverview.STATUS_HOME] = {0.35, 0.75, 0.1, 1},
}


---Returns true if a worker or a player drives the vehicle's combination
-- @param table vehicle vehicle
-- @return boolean isInUse
function HomeSpotOverview.getIsInUse(vehicle)
    local rootVehicle = vehicle:getRootVehicle()

    return (rootVehicle.getIsAIActive ~= nil and rootVehicle:getIsAIActive())
        or (rootVehicle.getIsControlled ~= nil and rootVehicle:getIsControlled())
end


---Returns one row per vehicle of the player's farm with a home spot: away ones first, then in use, then home, each by name
-- @return table rows list of {vehicle, name, status, distance, tools}
function HomeSpotOverview.getRows()
    local farmId = g_currentMission:getFarmId()
    local rows = {}

    for key, components in pairs(HomeSpots.store:getAll()) do
        local vehicle = HomeSpots.store:getVehicle(key)

        if vehicle ~= nil and vehicle.rootNode ~= nil and vehicle:getOwnerFarmId() == farmId then
            local status = HomeSpotOverview.STATUS_AWAY
            if HomeSpotOverview.getIsInUse(vehicle) then
                status = HomeSpotOverview.STATUS_IN_USE
            elseif HomeSpots.getIsAtHome(vehicle) then
                status = HomeSpotOverview.STATUS_HOME
            end

            table.insert(rows, {
                vehicle = vehicle,
                name = vehicle:getFullName(),
                status = status,
                distance = HomeSpots.getDistanceToHome(vehicle, components),
                tools = HomeSpotOverview.getToolNames(vehicle)
            })
        end
    end

    table.sort(rows, function(a, b)
        if a.status ~= b.status then
            return a.status < b.status
        end
        return a.name < b.name
    end)

    return rows
end


---Show a row's name, status and distance in three text elements
-- @param table row row
-- @param table name text element for the name
-- @param table status text element for the status
-- @param table distance text element for the distance
function HomeSpotOverview.showRowTexts(row, name, status, distance)
    name:setText(row.name)
    status:setText(g_i18n:getText(HomeSpotOverview.STATUS_TEXTS[row.status]))
    status:setTextColor(unpack(HomeSpotOverview.STATUS_COLORS[row.status]))
    distance:setText(row.status == HomeSpotOverview.STATUS_HOME and "-" or g_i18n:formatDistance(row.distance))
end


---Returns the names of the tools hooked to a vehicle that have a home spot, so Send home brings them along
-- @param table vehicle vehicle
-- @return table names
function HomeSpotOverview.getToolNames(vehicle)
    local names = {}
    for index, tool in ipairs(HomeSpotOverview.getVehicleWithTools(vehicle)) do
        if index > 1 and HomeSpots.store:has(tool) then
            table.insert(names, tool:getFullName())
        end
    end

    return names
end


---Returns the map marker the game shows for a vehicle, or for the vehicle it is hooked to
-- @param table vehicle vehicle
-- @return table hotspot, or nil when it has none
function HomeSpotOverview.getMapHotspot(vehicle)
    for _, candidate in ipairs({vehicle, vehicle:getRootVehicle()}) do
        local hotspot = candidate.getMapHotspot ~= nil and candidate:getMapHotspot() or nil
        if hotspot ~= nil then
            return hotspot
        end
    end

    return nil
end


---Returns the game's in-game menu once it exists
-- @return table inGameMenu, or nil
function HomeSpotOverview.getInGameMenu()
    return g_gui.screenControllers[InGameMenu]
end


---Returns a vehicle and every tool hooked to it, directly or through another tool
-- @param table vehicle vehicle
-- @param table vehicles list to add to, a new one when nil
-- @return table vehicles
function HomeSpotOverview.getVehicleWithTools(vehicle, vehicles)
    vehicles = vehicles or {}
    table.insert(vehicles, vehicle)

    if vehicle.getAttachedImplements ~= nil then
        for _, implement in ipairs(vehicle:getAttachedImplements()) do
            HomeSpotOverview.getVehicleWithTools(implement.object, vehicles)
        end
    end

    return vehicles
end


---Mod event listener update: add the page once the game's in-game menu exists, on every machine with a screen
-- @param float dt time since last frame in ms
function HomeSpotOverview:update(dt)
    if g_gui == nil or g_currentMission == nil or not g_currentMission:getIsClient() then
        return
    end

    local inGameMenu = HomeSpotOverview.getInGameMenu()
    if inGameMenu ~= nil and not HomeSpotOverview.triedMenus[inGameMenu] then
        -- Marked first, so a menu the page cannot be added to is only tried once
        HomeSpotOverview.triedMenus[inGameMenu] = true
        HomeSpotOverview.addToInGameMenu(inGameMenu)
    end
end


---Add the page to the game's in-game menu, next to its own pages
-- @param table inGameMenu in-game menu
function HomeSpotOverview.addToInGameMenu(inGameMenu)
    if inGameMenu.pagingElement == nil or inGameMenu.pageFrames == nil then
        Logging.warning("Home Spots: in-game menu not as expected, the Home Spots page is not added")
        return
    end

    local frame = HomeSpotOverviewFrame.new()
    g_gui:loadGui(HomeSpotOverview.XML_FILENAME, HomeSpotOverview.GUI_NAME, frame, true)

    local paging = inGameMenu.pagingElement
    paging:addElement(frame)

    local afterPage = inGameMenu[HomeSpotOverview.INSERT_AFTER_PAGE]
    local position = HomeSpotOverview.getIndexOf(paging.elements, afterPage)
    if position ~= nil then
        HomeSpotOverview.moveEntry(paging.elements, function(element) return element == frame end, position + 1)
        HomeSpotOverview.moveEntry(paging.pages, function(page) return page.element == frame end, position + 1)
    end

    paging:updateAbsolutePosition()
    paging:updatePageMapping()

    inGameMenu[HomeSpotOverview.PAGE_NAME] = frame
    inGameMenu:registerPage(frame, nil, function() return true end)
    inGameMenu:addPageTab(frame, HomeSpotOverview.ICON_FILENAME, HomeSpotOverview.getWholeImageUVs())

    local framePosition = HomeSpotOverview.getIndexOf(inGameMenu.pageFrames, afterPage)
    if framePosition ~= nil then
        HomeSpotOverview.moveEntry(inGameMenu.pageFrames, function(pageFrame) return pageFrame == frame end, framePosition + 1)
    end

    frame:initialize()
    inGameMenu:rebuildTabList()
    Logging.info("Home Spots: added the Home Spots page to the menu")
end


---Returns UVs covering a whole image, for the page icon and the shop pictures
-- @return table uvs
function HomeSpotOverview.getWholeImageUVs()
    return GuiUtils.getUVs({0, 0, 1, 1}, {1, 1})
end


---Returns the position of a value in a list
-- @param table list list
-- @param any value value, nil finds nothing
-- @return integer index, or nil when the value is not in the list
function HomeSpotOverview.getIndexOf(list, value)
    if value == nil then
        return nil
    end

    for i, entry in ipairs(list) do
        if entry == value then
            return i
        end
    end

    return nil
end


---Move the first list entry that matches to a new position
-- @param table list list
-- @param function matches returns true for the entry to move
-- @param integer position new position
function HomeSpotOverview.moveEntry(list, matches, position)
    for i, entry in ipairs(list) do
        if matches(entry) then
            table.remove(list, i)
            table.insert(list, math.min(position, #list + 1), entry)
            return
        end
    end
end


---The page itself
HomeSpotOverviewFrame = {}
local HomeSpotOverviewFrame_mt = Class(HomeSpotOverviewFrame, TabbedMenuFrameElement)

-- How often (ms) the open page checks for vehicles that moved, came home or were sent off
HomeSpotOverviewFrame.REFRESH_INTERVAL = 500


---Create the page
-- @return table self
function HomeSpotOverviewFrame.new()
    local self = TabbedMenuFrameElement.new(nil, HomeSpotOverviewFrame_mt)

    self.rows = {}
    self.shownState = nil
    self.refreshTimer = 0

    return self
end


---The page's elements are loaded: the list reads its rows from the page
function HomeSpotOverviewFrame:onGuiSetupFinished()
    HomeSpotOverviewFrame:superClass().onGuiSetupFinished(self)

    self.homeSpotsList:setDataSource(self)
    self.homeSpotsList:setDelegate(self)
end


---Set the texts and the buttons once the page is part of the menu
function HomeSpotOverviewFrame:initialize()
    HomeSpotOverviewFrame:superClass().initialize(self)

    self.homeSpotsHeaderText:setText(g_i18n:getText("homeSpots_settingsSection"))
    self.homeSpotsHeaderIcon:setImageFilename(HomeSpotOverview.ICON_FILENAME)
    self.homeSpotsHeaderIcon:setImageUVs(nil, unpack(HomeSpotOverview.getWholeImageUVs()))
    self.homeSpotsColumnVehicle:setText(g_i18n:getText("homeSpots_columnVehicle"))
    self.homeSpotsColumnStatus:setText(g_i18n:getText("homeSpots_columnStatus"))
    self.homeSpotsColumnDistance:setText(g_i18n:getText("homeSpots_columnDistance"))
    self.homeSpotsEmptyText:setText(g_i18n:getText("homeSpots_overviewEmpty"))

    self.backButtonInfo = {inputAction = InputAction.MENU_BACK}
    self.sendButtonInfo = {
        inputAction = InputAction.MENU_ACCEPT,
        text = g_i18n:getText("homeSpots_mapSendHome"),
        callback = function()
            self:onSendSelectedHome()
        end
    }
    self.sendAllButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_1,
        text = g_i18n:getText("input_HOMESPOTS_SEND_ALL"),
        callback = function()
            self:onSendAllHome()
        end
    }
    self.mapButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_2,
        text = g_i18n:getText("homeSpots_showOnMap"),
        callback = function()
            self:onShowOnMap()
        end
    }
    self.removeButtonInfo = {
        inputAction = InputAction.MENU_CANCEL,
        text = g_i18n:getText("homeSpots_removeSpot"),
        callback = function()
            self:onRemoveSpot()
        end
    }

    self:updateButtons()
end


---Show the current rows when the page opens
function HomeSpotOverviewFrame:onFrameOpen()
    HomeSpotOverviewFrame:superClass().onFrameOpen(self)

    self.refreshTimer = 0
    self.shownState = nil
    self:refresh()
    FocusManager:setFocus(self.homeSpotsList)
end


---Keep the rows up to date while the page is open
-- @param float dt time since last frame in ms
function HomeSpotOverviewFrame:update(dt)
    HomeSpotOverviewFrame:superClass().update(self, dt)

    self.refreshTimer = self.refreshTimer + dt
    if self.refreshTimer >= HomeSpotOverviewFrame.REFRESH_INTERVAL then
        self.refreshTimer = 0
        self:refresh()
    end
end


---Read the rows again and redraw the list, only when something shown has changed
function HomeSpotOverviewFrame:refresh()
    local rows = HomeSpotOverview.getRows()

    local parts = {}
    for _, row in ipairs(rows) do
        table.insert(parts, string.format("%s|%s|%d|%d|%s", tostring(row.vehicle), row.name, row.status, math.floor(row.distance), table.concat(row.tools, ",")))
    end

    local state = table.concat(parts, ";")
    if state == self.shownState then
        return
    end

    local selectedRow = self:getSelectedRow()

    self.shownState = state
    self.rows = rows
    self.homeSpotsList:reloadData()
    self.homeSpotsEmptyText:setVisible(#rows == 0)
    self:updateSummary()

    -- A vehicle that came home moves down the list: keep it selected, so Send home never lands on another one
    for index, row in ipairs(rows) do
        if selectedRow ~= nil and row.vehicle == selectedRow.vehicle and index ~= self.homeSpotsList:getSelectedIndexInSection() then
            self.homeSpotsList:setSelectedIndex(index)
            break
        end
    end

    self:onSelectionChanged()
end


---Returns the row of the selected vehicle
-- @return table row, or nil without a selection
function HomeSpotOverviewFrame:getSelectedRow()
    return self.rows[self.homeSpotsList:getSelectedIndexInSection()]
end


---Show Send home only for a selected vehicle that is away, Send all home while there is any spot,
-- and Show on map and Remove spot for the selected vehicle
function HomeSpotOverviewFrame:updateButtons()
    local buttons = {self.backButtonInfo}

    local row = self:getSelectedRow()
    if row ~= nil and row.status == HomeSpotOverview.STATUS_AWAY then
        table.insert(buttons, self.sendButtonInfo)
    end

    if #self.rows > 0 then
        table.insert(buttons, self.sendAllButtonInfo)
    end

    if row ~= nil and HomeSpotOverview.getMapHotspot(row.vehicle) ~= nil then
        table.insert(buttons, self.mapButtonInfo)
    end

    if row ~= nil then
        table.insert(buttons, self.removeButtonInfo)
    end

    self:setMenuButtonInfo(buttons)
    self:setMenuButtonInfoDirty()
end


---Send the selected vehicle home, with any tools hooked to it
function HomeSpotOverviewFrame:onSendSelectedHome()
    local row = self:getSelectedRow()
    if row ~= nil and row.status == HomeSpotOverview.STATUS_AWAY then
        HomeSpots.request(HomeSpots.ACTION_SEND, HomeSpotOverview.getVehicleWithTools(row.vehicle))
    end
end


---Send every vehicle and tool of the farm home
function HomeSpotOverviewFrame:onSendAllHome()
    HomeSpots.request(HomeSpots.ACTION_SEND_ALL, {})
end


---Switch to the map page with the selected vehicle picked and in view
function HomeSpotOverviewFrame:onShowOnMap()
    local row = self:getSelectedRow()
    local inGameMenu = HomeSpotOverview.getInGameMenu()
    local hotspot = row ~= nil and HomeSpotOverview.getMapHotspot(row.vehicle) or nil
    if hotspot == nil or inGameMenu == nil or inGameMenu.pageMapOverview == nil then
        return
    end

    local mapFrame = inGameMenu.pageMapOverview
    inGameMenu:goToPage(mapFrame)
    mapFrame:setMapSelectionItem(hotspot)
    if mapFrame.ingameMap ~= nil then
        mapFrame.ingameMap:panToHotspot(hotspot)
    end
end


---Ask, then remove the selected vehicle's home spot
function HomeSpotOverviewFrame:onRemoveSpot()
    local row = self:getSelectedRow()
    if row == nil then
        return
    end

    YesNoDialog.show(HomeSpotOverviewFrame.onRemoveSpotAnswered, self,
        string.format(g_i18n:getText("homeSpots_removeSpotQuestion"), row.name),
        nil, nil, nil, nil, nil, nil, row.vehicle)
end


---The player answered the Remove spot question
-- @param boolean isYes true to remove the spot
-- @param table vehicle vehicle whose spot to remove
function HomeSpotOverviewFrame:onRemoveSpotAnswered(isYes, vehicle)
    if isYes then
        HomeSpots.request(HomeSpots.ACTION_CLEAR, {vehicle})
    end
end


---Count the rows by status in the line above the picture
function HomeSpotOverviewFrame:updateSummary()
    local counts = {0, 0, 0}
    for _, row in ipairs(self.rows) do
        counts[row.status] = counts[row.status] + 1
    end

    self.homeSpotsSummary:setVisible(#self.rows > 0)
    self.homeSpotsSummary:setText(string.format(g_i18n:getText("homeSpots_summary"),
        counts[HomeSpotOverview.STATUS_AWAY], counts[HomeSpotOverview.STATUS_IN_USE], counts[HomeSpotOverview.STATUS_HOME]))
end


---List data source: one section
-- @return integer numSections
function HomeSpotOverviewFrame:getNumberOfSections(list)
    return 1
end


---List data source: one row per vehicle
-- @return integer numItems
function HomeSpotOverviewFrame:getNumberOfItemsInSection(list, section)
    return #self.rows
end


---List data source: fill a row
-- @param table list list
-- @param integer section section
-- @param integer index row index
-- @param table cell list item
function HomeSpotOverviewFrame:populateCellForItemInSection(list, section, index, cell)
    local row = self.rows[index]
    if row == nil then
        return
    end

    HomeSpotOverview.showRowTexts(row, cell:getAttribute("name"), cell:getAttribute("status"), cell:getAttribute("distance"))
end


---List delegate: the selection changed
function HomeSpotOverviewFrame:onListSelectionChanged(list, section, index)
    self:onSelectionChanged()
end


---Show the selected vehicle in the preview and the buttons that fit it
function HomeSpotOverviewFrame:onSelectionChanged()
    self:updatePreview()
    self:updateButtons()
end


---Show the shop picture, name, status, distance and hooked tools of the selected vehicle, or nothing without a selection
function HomeSpotOverviewFrame:updatePreview()
    local row = self:getSelectedRow()

    self.homeSpotsPreview:setVisible(row ~= nil)
    if row == nil then
        return
    end

    if row.vehicle.getImageFilename ~= nil then
        self.homeSpotsPreviewImage:setImageFilename(row.vehicle:getImageFilename())
        self.homeSpotsPreviewImage:setImageUVs(nil, unpack(HomeSpotOverview.getWholeImageUVs()))
    end
    HomeSpotOverview.showRowTexts(row, self.homeSpotsPreviewName, self.homeSpotsPreviewStatus, self.homeSpotsPreviewDistance)

    self.homeSpotsPreviewTools:setVisible(#row.tools > 0)
    self.homeSpotsPreviewTools:setText(string.format(g_i18n:getText("homeSpots_previewTools"), table.concat(row.tools, ", ")))
end


addModEventListener(HomeSpotOverview)
