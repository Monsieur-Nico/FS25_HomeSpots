---Shed spots: find a free place under the roof of one of the farm's sheds for each vehicle, clear of walls, posts and
-- whatever else stands there, and tell when a saved home spot runs into a wall.
HomeSpotShed = {}

-- Shop categories (upper case) whose buildings are searched for room to park
HomeSpotShed.CATEGORY_PATTERNS = {"SHED", "SHELTER"}
-- Only the nearest sheds of the farm are searched
HomeSpotShed.MAX_SHEDS = 5

-- Room kept free around each vehicle (m)
HomeSpotShed.MARGIN = 0.3
-- Distance (m) between the places tried along a shed
HomeSpotShed.GRID_STEP = 0.5
-- Most places tested against the physics per vehicle, so a big shed never stalls the game
HomeSpotShed.MAX_PHYSICS_TESTS = 400
-- Height used for a vehicle whose size has none (m)
HomeSpotShed.DEFAULT_HEIGHT = 3.5
-- The free-space test starts this high above the floor (m), so the floor itself and small bumps never count
HomeSpotShed.FLOOR_CLEARANCE = 0.3
-- The floor is searched downwards from this high above the terrain (m), below any roof beam
HomeSpotShed.FLOOR_RAY_HEIGHT = 1.5
-- A floor higher than this above the terrain (m) is something standing in the shed, not the floor
HomeSpotShed.MAX_FLOOR_RISE = 1.2
-- How far up (m) a roof is looked for
HomeSpotShed.ROOF_RAY_LENGTH = 20
-- The walls of a shed are looked for at this height above the floor (m), with rays spread over the width of each side,
-- so a single post in front of an open side does not count as a wall
HomeSpotShed.WALL_RAY_HEIGHT = 1.5
HomeSpotShed.WALL_RAY_SPREAD = {-0.4, -0.2, 0, 0.2, 0.4}
-- A shed spot is saved this much above the floor (m), so the wheels never start inside it
HomeSpotShed.LIFT = 0.1

-- A home spot counts as in a wall when a box this far inside its outline (m), between these heights above it (m),
-- touches a building, a static object or a tree
HomeSpotShed.WALL_SHRINK = 0.5
HomeSpotShed.WALL_MIN_HEIGHT = 0.5
HomeSpotShed.WALL_MAX_HEIGHT = 2.0
HomeSpotShed.WALL_MIN_HALF_SIZE = 0.1

HomeSpotShed.GROUND_MASK = CollisionFlag.TERRAIN + CollisionFlag.BUILDING + CollisionFlag.STATIC_OBJECT
HomeSpotShed.WALL_MASK = CollisionFlag.BUILDING + CollisionFlag.STATIC_OBJECT
HomeSpotShed.SOLID_MASK = CollisionFlag.BUILDING + CollisionFlag.STATIC_OBJECT + CollisionFlag.TREE
HomeSpotShed.OBSTACLE_MASK = HomeSpotShed.SOLID_MASK + CollisionFlag.VEHICLE + CollisionFlag.DYNAMIC_OBJECT

-- Helper nodes to turn a vehicle with all its components as one piece: a pivot, and a child posed like each component
HomeSpotShed.pivotNode = nil
HomeSpotShed.componentNode = nil


---Create the helper nodes
function HomeSpotShed.createNodes()
    HomeSpotShed.deleteNodes()
    HomeSpotShed.pivotNode = createTransformGroup("homeSpotsShedPivot")
    HomeSpotShed.componentNode = createTransformGroup("homeSpotsShedComponent")
    link(HomeSpotShed.pivotNode, HomeSpotShed.componentNode)
end


---Delete the helper nodes
function HomeSpotShed.deleteNodes()
    if HomeSpotShed.pivotNode ~= nil then
        delete(HomeSpotShed.pivotNode)
        HomeSpotShed.pivotNode = nil
        HomeSpotShed.componentNode = nil
    end
end


---Returns the heading (y rotation) that faces a direction on the ground
-- @param float dirX, dirZ direction
-- @return float yaw
local function getYaw(dirX, dirZ)
    return math.atan2(dirX, dirZ)
end


---Returns true if a physics hit is a real collision shape, not a trigger, and not one of the ignored vehicles
-- @param integer node hit node
-- @param table ignoredVehicles set of vehicles to look through, or nil
-- @return boolean isSolid
function HomeSpotShed.getIsSolidHit(node, ignoredVehicles)
    if node == nil or node == 0 or not getHasClassId(node, ClassIds.SHAPE) or getHasTrigger(node) then
        return false
    end

    if ignoredVehicles == nil then
        return true
    end

    local vehicle = HomeSpots.getVehicleFromNode(node)

    return vehicle == nil or not ignoredVehicles[vehicle]
end


---Returns the first solid thing inside a box standing upright on the ground
-- @param float x, y, z box centre
-- @param float yaw heading of the box's length
-- @param float halfWidth, halfHeight, halfLength half sizes
-- @param integer mask collision mask
-- @param table ignoredVehicles set of vehicles to look through, or nil
-- @return integer node the node hit, or nil when the box is free
function HomeSpotShed.getObstacle(x, y, z, yaw, halfWidth, halfHeight, halfLength, mask, ignoredVehicles)
    HomeSpotShed.overlapIgnored = ignoredVehicles
    HomeSpotShed.overlapHitNode = nil
    overlapBox(x, y, z, 0, yaw, 0, halfWidth, halfHeight, halfLength, "onOverlapHit", HomeSpotShed, mask, true, true, true, true)

    return HomeSpotShed.overlapHitNode
end


---Overlap callback: keep the first solid hit and stop there
-- @param integer node hit node
-- @return boolean continue
function HomeSpotShed:onOverlapHit(node)
    if HomeSpotShed.getIsSolidHit(node, HomeSpotShed.overlapIgnored) then
        HomeSpotShed.overlapHitNode = node
        return false
    end

    return true
end


---Returns how far a ray travels before it hits something
-- @param float x, y, z start
-- @param float dirX, dirY, dirZ direction (unit length)
-- @param float maxDistance longest distance
-- @param integer mask collision mask
-- @return float distance distance to the hit, or nil when nothing is hit
function HomeSpotShed.raycast(x, y, z, dirX, dirY, dirZ, maxDistance, mask)
    HomeSpotShed.rayHitDistance = nil
    raycastClosest(x, y, z, dirX, dirY, dirZ, maxDistance, "onRaycastHit", HomeSpotShed, mask)

    return HomeSpotShed.rayHitDistance
end


---Raycast callback: keep the distance of the closest hit
-- @param integer node hit node
-- @param float x, y, z hit position
-- @param float distance distance to the hit
-- @return boolean continue
function HomeSpotShed:onRaycastHit(node, x, y, z, distance)
    HomeSpotShed.rayHitDistance = distance

    return false
end


---Returns the height of the floor (a shed's floor, or the ground) at a position, and of the terrain
-- @param float x, z position
-- @return float floorY floor height
-- @return float terrainY terrain height
function HomeSpotShed.getFloorHeight(x, z)
    local terrainY = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    local startY = terrainY + HomeSpotShed.FLOOR_RAY_HEIGHT
    local distance = HomeSpotShed.raycast(x, startY, z, 0, -1, 0, HomeSpotShed.FLOOR_RAY_HEIGHT + 1, HomeSpotShed.GROUND_MASK)

    if distance == nil then
        return terrainY, terrainY
    end

    return startY - distance, terrainY
end


---Returns true if there is a roof above a point
-- @param float x, y, z point
-- @return boolean hasRoof
function HomeSpotShed.getHasRoof(x, y, z)
    return HomeSpotShed.raycast(x, y, z, 0, 1, 0, HomeSpotShed.ROOF_RAY_LENGTH, HomeSpotShed.WALL_MASK) ~= nil
end


---Returns true if a placeable is a shed or shelter by its shop category
-- @param table placeable placeable
-- @return boolean isShed
function HomeSpotShed.getIsShed(placeable)
    local categoryText = HomeSpotShed.getCategoryText(placeable)

    for _, pattern in ipairs(HomeSpotShed.CATEGORY_PATTERNS) do
        if categoryText:find(pattern, 1, true) ~= nil then
            return true
        end
    end

    return false
end


---Returns a placeable's shop categories as one text, e.g. "SHEDS"
-- @param table placeable placeable
-- @return string categories
function HomeSpotShed.getCategoryText(placeable)
    local storeItem = placeable.storeItem
    if storeItem == nil then
        return ""
    end

    return string.upper(table.concat(storeItem.categoryNames or {storeItem.categoryName}, " "))
end


---Returns the room inside a clear area of a shed: its centre and its two axes, each {dirX, dirZ, halfSize}
-- @param table clearArea clear area of a placeable (start, width and height nodes)
-- @return table room room, or nil when the area is too small
function HomeSpotShed.getRoom(clearArea)
    local x0, _, z0 = getWorldTranslation(clearArea.start)
    local x1, _, z1 = getWorldTranslation(clearArea.width)
    local x2, _, z2 = getWorldTranslation(clearArea.height)
    local widthX, widthZ = x1 - x0, z1 - z0
    local heightX, heightZ = x2 - x0, z2 - z0
    local width = MathUtil.vector2Length(widthX, widthZ)
    local height = MathUtil.vector2Length(heightX, heightZ)

    if width < 1 or height < 1 then
        return nil
    end

    return {
        x = x0 + (widthX + heightX) * 0.5,
        z = z0 + (widthZ + heightZ) * 0.5,
        axes = {
            {widthX / width, widthZ / width, width * 0.5},
            {heightX / height, heightZ / height, height * 0.5}
        }
    }
end


---Returns how many of the rays spread over a side of a room hit a wall on their way out of it
-- @param table room room
-- @param float floorY floor height in the middle of the room
-- @param table depthAxis axis the rays run along
-- @param table rowAxis axis the rays are spread along
-- @param integer sign 1 or -1, which way along the depth axis
-- @return integer numHits
function HomeSpotShed.getNumWallHits(room, floorY, depthAxis, rowAxis, sign)
    local numHits = 0

    for _, fraction in ipairs(HomeSpotShed.WALL_RAY_SPREAD) do
        local offset = fraction * rowAxis[3] * 2
        local x, z = room.x + rowAxis[1] * offset, room.z + rowAxis[2] * offset

        if HomeSpotShed.raycast(x, floorY + HomeSpotShed.WALL_RAY_HEIGHT, z, depthAxis[1] * sign, 0, depthAxis[2] * sign, depthAxis[3] + 1, HomeSpotShed.WALL_MASK) ~= nil then
            numHits = numHits + 1
        end
    end

    return numHits
end


---Work out which ways a vehicle can face in a room, best first: out of an open side, where most rays pass,
-- then with a wall behind it, then across the room, so vehicles stand side by side along its long side
-- @param table room room, gets its facings list
function HomeSpotShed.setFacings(room)
    local floorY = HomeSpotShed.getFloorHeight(room.x, room.z)
    local numRays = #HomeSpotShed.WALL_RAY_SPREAD
    local facings = {}

    for axisIndex, axis in ipairs(room.axes) do
        local rowAxis = room.axes[3 - axisIndex]

        for _, sign in ipairs({1, -1}) do
            local numHits = HomeSpotShed.getNumWallHits(room, floorY, axis, rowAxis, sign)
            local numHitsBehind = HomeSpotShed.getNumWallHits(room, floorY, axis, rowAxis, -sign)

            table.insert(facings, {
                dirX = axis[1] * sign,
                dirZ = axis[2] * sign,
                depthAxis = axis,
                rowAxis = rowAxis,
                isOpen = numHits * 2 < numRays,
                hasWallBehind = numHitsBehind * 2 > numRays,
                order = #facings
            })
        end
    end

    table.sort(facings, function(a, b)
        if a.isOpen ~= b.isOpen then
            return a.isOpen
        end
        if a.hasWallBehind ~= b.hasWallBehind then
            return a.hasWallBehind
        end
        if a.depthAxis[3] ~= b.depthAxis[3] then
            return a.depthAxis[3] < b.depthAxis[3]
        end
        return a.order < b.order
    end)

    room.facings = facings
end


---Returns the rooms of the farm's nearest sheds, nearest first
-- @param integer farmId farm
-- @param float x, z position the distance is measured from
-- @return table rooms rooms with their facings
function HomeSpotShed.getFarmRooms(farmId, x, z)
    local sheds = {}

    for _, placeable in ipairs(g_currentMission.placeableSystem.placeables) do
        if placeable:getOwnerFarmId() == farmId and placeable.rootNode ~= nil then
            local placeableX, _, placeableZ = getWorldTranslation(placeable.rootNode)
            local distance = MathUtil.vector2Length(placeableX - x, placeableZ - z)
            local clearAreas = placeable.spec_clearAreas ~= nil and placeable.spec_clearAreas.areas or {}

            if HomeSpotShed.getIsShed(placeable) and #clearAreas > 0 then
                table.insert(sheds, {placeable = placeable, distance = distance, clearAreas = clearAreas})
            end
        end
    end

    table.sort(sheds, function(a, b) return a.distance < b.distance end)

    local rooms = {}
    for index = 1, math.min(#sheds, HomeSpotShed.MAX_SHEDS) do
        for _, clearArea in ipairs(sheds[index].clearAreas) do
            local room = HomeSpotShed.getRoom(clearArea)
            if room ~= nil then
                HomeSpotShed.setFacings(room)
                room.name = sheds[index].placeable:getName()
                table.insert(rooms, room)
            end
        end
    end

    return rooms
end


---Returns the footprints no vehicle may be parked on: other vehicles, and other vehicles' home spots
-- @param table ignoredVehicles set of the vehicles being parked
-- @return table areas footprints
function HomeSpotShed.getTakenAreas(ignoredVehicles)
    local areas = {}

    for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
        if not ignoredVehicles[vehicle] and vehicle.size ~= nil and vehicle.rootNode ~= nil then
            table.insert(areas, HomeSpotArea.newFromNode(vehicle.size, vehicle.rootNode))
        end
    end

    for key, components in pairs(HomeSpots.store:getAll()) do
        local vehicle = HomeSpots.store:getVehicle(key)
        if vehicle ~= nil and not ignoredVehicles[vehicle] and vehicle.size ~= nil and #components == #vehicle.components then
            table.insert(areas, HomeSpots.getHomeArea(vehicle, components))
        end
    end

    return areas
end


---Returns the offsets tried across the depth of a room, the middle first
-- @param float depthRoom how far the vehicle can move from the middle each way
-- @return table offsets
local function getDepthOffsets(depthRoom)
    if depthRoom < HomeSpotShed.GRID_STEP then
        return {0}
    end

    return {0, -depthRoom, depthRoom}
end


---Test a place against the shed: a floor, a roof over the whole length, and nothing in the way up to the vehicle's height
-- @param table place centre (x, z), direction (dirX, dirZ) and half sizes with margin (halfWidth, halfLength)
-- @param float height vehicle height
-- @param table ignoredVehicles set of the vehicles being parked
-- @param table stats counts of why places were turned down
-- @return float floorY floor height when the place is free, else nil
function HomeSpotShed.testPlace(place, height, ignoredVehicles, stats)
    stats.numTested = stats.numTested + 1

    local floorY, terrainY = HomeSpotShed.getFloorHeight(place.x, place.z)
    if floorY - terrainY > HomeSpotShed.MAX_FLOOR_RISE then
        stats.noFloor = stats.noFloor + 1
        return nil
    end

    local endOffset = place.halfLength - HomeSpotShed.MARGIN
    for _, offset in ipairs({0, endOffset, -endOffset}) do
        if not HomeSpotShed.getHasRoof(place.x + place.dirX * offset, floorY + 1, place.z + place.dirZ * offset) then
            stats.noRoof = stats.noRoof + 1
            return nil
        end
    end

    local halfHeight = (height - HomeSpotShed.FLOOR_CLEARANCE) * 0.5
    local obstacle = HomeSpotShed.getObstacle(place.x, floorY + HomeSpotShed.FLOOR_CLEARANCE + halfHeight, place.z, getYaw(place.dirX, place.dirZ),
        place.halfWidth, halfHeight, place.halfLength, HomeSpotShed.OBSTACLE_MASK, ignoredVehicles)

    if obstacle ~= nil then
        stats.blocked = stats.blocked + 1
        return nil
    end

    return floorY
end


---Returns the first free place for a vehicle in the rooms: out of the open side first,
-- then along the room from one end, so vehicles line up side by side
-- @param table vehicle vehicle
-- @param table rooms rooms with their facings
-- @param table taken footprints no vehicle may be parked on
-- @param table ignoredVehicles set of the vehicles being parked
-- @param table stats counts of why places were turned down
-- @return table place place with its floor height (floorY) and footprint (area), or nil when none is free
function HomeSpotShed.findPlace(vehicle, rooms, taken, ignoredVehicles, stats)
    local halfLength = vehicle.size.length * 0.5 + HomeSpotShed.MARGIN
    local halfWidth = vehicle.size.width * 0.5 + HomeSpotShed.MARGIN
    local height = vehicle.size.height or HomeSpotShed.DEFAULT_HEIGHT
    local footprint = {length = halfLength * 2, width = halfWidth * 2}

    for _, room in ipairs(rooms) do
        for _, facing in ipairs(room.facings) do
            local depthRoom = facing.depthAxis[3] - halfLength
            local rowRoom = facing.rowAxis[3] - halfWidth

            if depthRoom >= 0 and rowRoom >= 0 then
                for row = -rowRoom, rowRoom, HomeSpotShed.GRID_STEP do
                    for _, depth in ipairs(getDepthOffsets(depthRoom)) do
                        local place = {
                            x = room.x + facing.rowAxis[1] * row + facing.depthAxis[1] * depth,
                            z = room.z + facing.rowAxis[2] * row + facing.depthAxis[2] * depth,
                            dirX = facing.dirX,
                            dirZ = facing.dirZ,
                            halfLength = halfLength,
                            halfWidth = halfWidth
                        }
                        place.area = HomeSpotArea.new(footprint, place.x, place.z, place.dirX, place.dirZ, place.dirZ, -place.dirX)

                        if HomeSpotArea.getOverlapsAny(place.area, taken) then
                            stats.taken = stats.taken + 1
                        else
                            if stats.numTested >= HomeSpotShed.MAX_PHYSICS_TESTS then
                                return nil
                            end

                            place.floorY = HomeSpotShed.testPlace(place, height, ignoredVehicles, stats)
                            if place.floorY ~= nil then
                                place.roomName = room.name
                                return place
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end


---Returns the component positions that put a vehicle on a place, turned as one piece around its root component
-- @param table vehicle vehicle
-- @param table place free place (x, z, dirX, dirZ, floorY)
-- @return table components component positions, like a saved home spot
function HomeSpotShed.getComponentsAt(vehicle, place)
    local size = vehicle.size
    local lengthOffset, widthOffset = size.lengthOffset or 0, size.widthOffset or 0
    local rootX = place.x - place.dirX * lengthOffset - place.dirZ * widthOffset
    local rootZ = place.z - place.dirZ * lengthOffset + place.dirX * widthOffset

    local currentX, currentY, currentZ = getWorldTranslation(vehicle.rootNode)
    local currentDirX, _, currentDirZ = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
    local heightAboveFloor = currentY - HomeSpotShed.getFloorHeight(currentX, currentZ)
    local rootY = place.floorY + heightAboveFloor + HomeSpotShed.LIFT

    local pivot, child = HomeSpotShed.pivotNode, HomeSpotShed.componentNode
    local components = {}

    for i, component in ipairs(vehicle.components) do
        setTranslation(pivot, currentX, currentY, currentZ)
        setRotation(pivot, 0, getYaw(currentDirX, currentDirZ), 0)
        setWorldTranslation(child, getWorldTranslation(component.node))
        setWorldRotation(child, getWorldRotation(component.node))

        setTranslation(pivot, rootX, rootY, rootZ)
        setRotation(pivot, 0, getYaw(place.dirX, place.dirZ), 0)

        local x, y, z = getWorldTranslation(child)
        local rx, ry, rz = getWorldRotation(child)
        components[i] = {{x, y, z}, {rx, ry, rz}}
    end

    return components
end


---Server: find a place in the farm's nearest sheds for each vehicle, one after the other so they never share one
-- @param table vehicles vehicles of one farm
-- @param integer farmId farm
-- @return table places list of {vehicle, components}; vehicles without room are left out
function HomeSpotShed.findPlaces(vehicles, farmId)
    if #vehicles == 0 or HomeSpotShed.pivotNode == nil then
        return {}
    end

    local x, _, z = getWorldTranslation(vehicles[1].rootNode)
    local rooms = HomeSpotShed.getFarmRooms(farmId, x, z)

    local ignoredVehicles = {}
    for _, vehicle in ipairs(vehicles) do
        ignoredVehicles[vehicle] = true
    end

    local taken = HomeSpotShed.getTakenAreas(ignoredVehicles)
    local places = {}

    for _, vehicle in ipairs(vehicles) do
        local stats = {numTested = 0, taken = 0, noFloor = 0, noRoof = 0, blocked = 0}
        local place = HomeSpotShed.findPlace(vehicle, rooms, taken, ignoredVehicles, stats)

        if place ~= nil then
            table.insert(taken, place.area)
            table.insert(places, {vehicle = vehicle, components = HomeSpotShed.getComponentsAt(vehicle, place)})
            Logging.info("Home Spots: '%s' got a home spot in '%s'", vehicle:getFullName(), place.roomName)
        else
            Logging.info("Home Spots: no room for '%s' in %d shed room(s): %d taken by other vehicles or spots, %d without floor, %d without roof, %d in the way",
                vehicle:getFullName(), #rooms, stats.taken, stats.noFloor, stats.noRoof, stats.blocked)
        end
    end

    return places
end


---Server: split moves into those whose home spot is clear, and those whose spot runs into a building, a wall or a tree
-- @param table moves moves (vehicle, components, homeArea)
-- @return table clear moves that can go ahead
-- @return table walled moves whose spot is in a wall
function HomeSpotShed.splitWalledSpots(moves)
    local clear, walled = {}, {}

    for _, move in ipairs(moves) do
        local obstacle = HomeSpotShed.getWallAt(move.homeArea, move.components[1][1][2])

        if obstacle ~= nil then
            table.insert(walled, move)
            Logging.info("Home Spots: the home spot of '%s' runs into '%s', left where it is", move.vehicle:getFullName(), getName(obstacle))
        else
            table.insert(clear, move)
        end
    end

    return clear, walled
end


---Returns the building, wall or tree a footprint runs into, well above the ground and a little inside its outline
-- @param table area footprint at the home spot
-- @param float y height of the spot's root component
-- @return integer node the node hit, or nil when the spot is clear
function HomeSpotShed.getWallAt(area, y)
    local halfWidth = math.max(area.halfWidth - HomeSpotShed.WALL_SHRINK, HomeSpotShed.WALL_MIN_HALF_SIZE)
    local halfLength = math.max(area.halfLength - HomeSpotShed.WALL_SHRINK, HomeSpotShed.WALL_MIN_HALF_SIZE)
    local halfHeight = (HomeSpotShed.WALL_MAX_HEIGHT - HomeSpotShed.WALL_MIN_HEIGHT) * 0.5

    return HomeSpotShed.getObstacle(area.x, y + HomeSpotShed.WALL_MIN_HEIGHT + halfHeight, area.z, getYaw(area.dirX, area.dirZ),
        halfWidth, halfHeight, halfLength, HomeSpotShed.SOLID_MASK, nil)
end
