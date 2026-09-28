---Map marker for one saved home spot
HomeSpotHotspot = {}
local HomeSpotHotspot_mt = Class(HomeSpotHotspot, MapHotspot)

HomeSpotHotspot.ICON_FILENAME = Utils.getFilename("icon_homeSpotMarker.dds", g_currentModDirectory)
HomeSpotHotspot.ICON_SIZE = 32


---Create a new map marker
-- @param string uniqueId unique id of the vehicle the spot belongs to
-- @return table self
function HomeSpotHotspot.new(uniqueId)
    local self = MapHotspot.new(HomeSpotHotspot_mt)

    self.uniqueId = uniqueId
    self.width, self.height = getNormalizedScreenValues(HomeSpotHotspot.ICON_SIZE, HomeSpotHotspot.ICON_SIZE)
    self.icon = Overlay.new(HomeSpotHotspot.ICON_FILENAME, 0, 0, self.width, self.height)
    self.clickArea = MapHotspot.getClickCircle(0.667)

    return self
end


---Map filter category the marker is listed under
-- @return integer category
function HomeSpotHotspot:getCategory()
    return MapHotspot.CATEGORY_OTHER
end


---Returns the vehicle the spot belongs to
-- @return table vehicle vehicle, or nil once it has been sold
function HomeSpotHotspot:getVehicle()
    return g_currentMission.vehicleSystem:getVehicleByUniqueId(self.uniqueId)
end


---Hide markers of vehicles that no longer exist
-- @return boolean isVisible
function HomeSpotHotspot:getIsVisible()
    local superGetIsVisible = HomeSpotHotspot:superClass().getIsVisible
    local isVisible = superGetIsVisible == nil or superGetIsVisible(self)

    return isVisible and self:getVehicle() ~= nil
end


---Name shown when the marker is selected on the map
-- @return string name
function HomeSpotHotspot:getName()
    local vehicle = self:getVehicle()
    local vehicleName = vehicle ~= nil and vehicle:getFullName() or ""

    return string.format(g_i18n:getText("homeSpots_mapMarker"), vehicleName)
end
