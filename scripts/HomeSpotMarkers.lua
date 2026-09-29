---Markers: the home spot markers on the map.


---Create, move or remove the map marker of a home spot to match the store
-- @param any key spot key
function HomeSpots.updateHotspot(key)
    local components = HomeSpots.store:getAll()[key]
    if components == nil or not g_currentMission:getIsClient() then
        HomeSpots.removeHotspot(key)
        return
    end

    local hotspot = HomeSpots.hotspots[key]
    if hotspot == nil then
        hotspot = HomeSpotHotspot.new(key)
        HomeSpots.hotspots[key] = hotspot
        g_currentMission:addMapHotspot(hotspot)
    end

    local position = components[1][1]
    hotspot:setWorldPosition(position[1], position[3])
end


---Remove the map marker of a home spot
-- @param any key spot key
function HomeSpots.removeHotspot(key)
    local hotspot = HomeSpots.hotspots[key]
    if hotspot ~= nil then
        g_currentMission:removeMapHotspot(hotspot)
        hotspot:delete()
        HomeSpots.hotspots[key] = nil
    end
end


---Remove every map marker
function HomeSpots.removeAllHotspots()
    for key in pairs(HomeSpots.hotspots) do
        HomeSpots.removeHotspot(key)
    end
end
