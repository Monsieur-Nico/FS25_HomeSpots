---Adds "Send home" to the map menu of a selected vehicle or tool, next to Enter vehicle, Reset and Sell
HomeSpotMapMenu = {}


---Returns the combination of a map item if at least one part of it can be sent home
-- @param table hotspot selected map hotspot, or nil
-- @return table vehicles vehicles of the combination, or nil when there is nothing to send home
function HomeSpotMapMenu.getSendableVehicles(hotspot)
    if hotspot == nil or HomeSpots.pendingMoves ~= nil then
        return nil
    end

    local vehicle = InGameMenuMapUtil.getHotspotVehicle(hotspot)
    if vehicle == nil or vehicle.getRootVehicle == nil or vehicle:getOwnerFarmId() ~= g_currentMission:getFarmId() then
        return nil
    end

    local vehicles = vehicle:getRootVehicle():getChildVehicles()
    for _, childVehicle in ipairs(vehicles) do
        if HomeSpots.store:has(childVehicle) and not HomeSpots.getIsAtHome(childVehicle) then
            return vehicles
        end
    end

    return nil
end


---Add the action to the frame's context actions, again whenever the game rebuilds that list.
-- Like other mods' map actions it carries a ready translated title instead of a text name.
-- @param table frame in-game menu map frame
function HomeSpotMapMenu.addContextAction(frame)
    if frame.homeSpotsActionList == frame.contextActions then
        return
    end

    frame.homeSpotsAction = {
        title = g_i18n:getText("homeSpots_mapSendHome"),
        isActive = false,
        callback = function()
            HomeSpotMapMenu.onSendHome(frame)
        end
    }

    table.insert(frame.contextActions, frame.homeSpotsAction)
    frame.homeSpotsActionList = frame.contextActions
end


---Show the action only for a selection that has somewhere to go
-- @param table frame in-game menu map frame
-- @param table hotspot selected map hotspot, or nil
-- @return boolean isActive whether the action is shown
function HomeSpotMapMenu.updateContextAction(frame, hotspot)
    if type(frame.contextActions) ~= "table" then
        return false
    end

    HomeSpotMapMenu.addContextAction(frame)
    frame.homeSpotsAction.isActive = HomeSpotMapMenu.getSendableVehicles(hotspot) ~= nil

    return frame.homeSpotsAction.isActive
end


---Redraw the frame's list of map actions
-- @param table frame in-game menu map frame
function HomeSpotMapMenu.reloadContextButtons(frame)
    if frame.contextButtonList ~= nil then
        frame.contextButtonList:reloadData()
    end
end


---Before the game lists the actions of a new selection, so the action is part of that list
-- @param table frame in-game menu map frame
-- @param table hotspot selected map hotspot, or nil
function HomeSpotMapMenu.onBeforeSelection(frame, hotspot)
    HomeSpotMapMenu.updateContextAction(frame, hotspot)
end


---After the game listed the actions, in case it reset the action's state on the way
-- @param table frame in-game menu map frame
-- @param table hotspot selected map hotspot, or nil
function HomeSpotMapMenu.onAfterSelection(frame, hotspot)
    if HomeSpotMapMenu.updateContextAction(frame, hotspot) then
        HomeSpotMapMenu.reloadContextButtons(frame)
    end
end


---Send the selected combination home
-- @param table frame in-game menu map frame
function HomeSpotMapMenu.onSendHome(frame)
    local vehicles = HomeSpotMapMenu.getSendableVehicles(frame.currentHotspot)
    if vehicles == nil then
        return
    end

    HomeSpots.request(HomeSpots.ACTION_SEND, vehicles)
    HomeSpotMapMenu.updateContextAction(frame, frame.currentHotspot)
    HomeSpotMapMenu.reloadContextButtons(frame)
end


if InGameMenuMapFrame ~= nil and InGameMenuMapFrame.setMapSelectionItem ~= nil and InGameMenuMapUtil ~= nil and InGameMenuMapUtil.getHotspotVehicle ~= nil then
    InGameMenuMapFrame.setMapSelectionItem = Utils.prependedFunction(InGameMenuMapFrame.setMapSelectionItem, HomeSpotMapMenu.onBeforeSelection)
    InGameMenuMapFrame.setMapSelectionItem = Utils.appendedFunction(InGameMenuMapFrame.setMapSelectionItem, HomeSpotMapMenu.onAfterSelection)
else
    Logging.warning("Home Spots: map menu not found, the Send home map action is not added")
end
