---Map marker for one saved home spot
HomeSpotHotspot = {}
local HomeSpotHotspot_mt = Class(HomeSpotHotspot, MapHotspot)

HomeSpotHotspot.ICON_HOME = Utils.getFilename("icon_homeSpotHome.dds", g_currentModDirectory)
HomeSpotHotspot.ICON_AWAY = Utils.getFilename("icon_homeSpotAway.dds", g_currentModDirectory)
HomeSpotHotspot.ICON_SIZE = 32


---Create a new map marker
-- @param any key spot key of the vehicle the spot belongs to, see HomeSpotStore:getKey
-- @return table self
function HomeSpotHotspot.new(key)
    local self = MapHotspot.new(HomeSpotHotspot_mt)

    self.key = key
    self.width, self.height = getNormalizedScreenValues(HomeSpotHotspot.ICON_SIZE, HomeSpotHotspot.ICON_SIZE)
    self.icon = Overlay.new(HomeSpotHotspot.ICON_AWAY, 0, 0, self.width, self.height)
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
    return HomeSpots.store:getVehicle(self.key)
end


---Show the marker as the marker setting says, green while its vehicle is home and orange while it is away.
-- By default only spots whose vehicle is away show, as the game's own vehicle icon already marks a parked one.
-- @return boolean isVisible
function HomeSpotHotspot:getIsVisible()
    local superGetIsVisible = HomeSpotHotspot:superClass().getIsVisible
    if superGetIsVisible ~= nil and not superGetIsVisible(self) then
        return false
    end

    local markerMode = HomeSpots.store.markerMode
    local vehicle = self:getVehicle()
    if vehicle == nil or markerMode == HomeSpotStore.MARKERS_OFF then
        return false
    end

    local isAtHome = HomeSpots.getIsAtHome(vehicle)
    self.icon:setImage(isAtHome and HomeSpotHotspot.ICON_HOME or HomeSpotHotspot.ICON_AWAY)

    return markerMode == HomeSpotStore.MARKERS_ALWAYS or not isAtHome
end


---Name shown when the marker is selected on the map
-- @return string name
function HomeSpotHotspot:getName()
    local vehicle = self:getVehicle()
    local vehicleName = vehicle ~= nil and vehicle:getFullName() or ""

    return string.format(g_i18n:getText("homeSpots_mapMarker"), vehicleName)
end
