---Shed spots: find a free place under the roof of one of the farm's sheds for each vehicle and tool, clear of walls,
-- posts and whatever else stands there, self-driving machines in the front rows and tools behind them,
-- and tell when a saved home spot runs into a wall.
HomeSpotShed = {}

-- Shop categories (upper case) whose buildings are searched for room to park
HomeSpotShed.CATEGORY_PATTERNS = {"SHED", "SHELTER"}
-- Only the nearest sheds of the farm are searched
HomeSpotShed.MAX_SHEDS = 5

-- Room kept free around each vehicle (m)
HomeSpotShed.MARGIN = 0.3
-- How much closer than MARGIN a neighbour may stand and still count as clear, so a machine parked exactly a margin from another is never turned down by rounding
HomeSpotShed.CLEARANCE_SLACK = 0.05
-- Distance (m) between the places tried along a shed
HomeSpotShed.GRID_STEP = 0.5
-- Size (m) of the squares the floor and the roof of a room are looked up in, once per room
HomeSpotShed.CELL_SIZE = 1
-- The floor and the roof are checked over a vehicle's footprint at about this spacing (m)
HomeSpotShed.SAMPLE_SPACING = 1
-- A machine that has found a place slides towards where the line starts in steps this fine (m), up to GRID_STEP,
-- so it stands snug against a wall, a column or its neighbour and leaves the rest of the lane free for the next one
HomeSpotShed.SLIDE_STEP = 0.1
-- A place snug against another machine is this much further from it (m), so rounding never counts as an overlap
HomeSpotShed.SNUG_SLACK = 0.001
-- Most places tested against the physics per search, so a big shed never stalls the game
HomeSpotShed.MAX_PHYSICS_TESTS = 800
-- Slack (m) when telling whether a point lies inside a room
HomeSpotShed.ROOM_TOLERANCE = 0.05
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
-- Where a shed has posts or walls a little inside the edge of its clear area, that edge is not under its roof:
-- vehicles keep inside the posts. They are looked for by rays from each edge inwards, at most this far (m),
-- spaced this far apart (m); a line of posts is two or more hits within HIT_SPREAD (m) of the nearest, at least MIN_SPAN (m) apart
HomeSpotShed.BOUND_SEARCH = 4
HomeSpotShed.BOUND_RAY_SPACING = 0.4
HomeSpotShed.BOUND_HIT_SPREAD = 0.6
HomeSpotShed.BOUND_MIN_SPAN = 2
-- The rays keep this far (m) from the corners, so they never run along a side wall
HomeSpotShed.BOUND_CORNER = 0.25
-- Machines whose front edges lie within this distance (m) of each other stand in the same line
HomeSpotShed.LINE_TOLERANCE = 1.5
-- A tool with no tractor parked in the shed yet is put this far (m) from the open front, where a tractor's length will be
HomeSpotShed.FRONT_BAND = 7
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
function HomeSpotShed.getYaw(dirX, dirZ)
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
                depthIndex = axisIndex,
                sign = sign,
                -- Lines are filled from left to right as seen from outside the open front: along the row axis or against it
                rowDirection = rowAxis[1] * axis[2] * sign - rowAxis[2] * axis[1] * sign >= 0 and 1 or -1,
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


---Write what was found out about a room to the log, and a map of the squares under a roof when only some are
-- @param table room room with its grid and bounds
function HomeSpotShed.logRoom(room)
    local grid = room.grid
    local numCells = grid.numU * grid.numV

    Logging.info("Home Spots: shed '%s' room %.1f x %.1f m, roof over %d of %d squares, kept inside %.1f to %.1f and %.1f to %.1f m of its axes",
        room.name, room.axes[1][3] * 2, room.axes[2][3] * 2, room.numRoofed, numCells,
        room.bounds[1][1], room.bounds[1][2], room.bounds[2][1], room.bounds[2][2])

    if room.numRoofed > 0 and room.numRoofed < numCells then
        for iv = grid.numV, 1, -1 do
            local line = {}
            for iu = 1, grid.numU do
                table.insert(line, grid.cells[(iu - 1) * grid.numV + iv].hasRoof and "#" or ".")
            end
            Logging.info("Home Spots:   %s", table.concat(line))
        end
    end
end


---Returns the rooms of the farm's nearest sheds, nearest first
-- @param integer farmId farm
-- @param float x, z position the distance is measured from
-- @return table rooms rooms with their grids and facings
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
                room.name = sheds[index].placeable:getName()
                HomeSpotShed.setGrid(room)
                HomeSpotShed.setBounds(room)
                HomeSpotShed.setFacings(room)
                HomeSpotShed.logRoom(room)
                table.insert(rooms, room)
            end
        end
    end

    return rooms
end


---Returns what kind of machine a vehicle is, so that machines of one kind can be parked together
-- @param table vehicle vehicle
-- @return string kind
function HomeSpotShed.getKind(vehicle)
    return vehicle.configFileName or vehicle:getFullName()
end


---Returns the footprints no vehicle may be parked on: other vehicles, and other vehicles' home spots
-- @param table ignoredVehicles set of the vehicles being parked
-- @return table areas footprints
-- @return table selfDrivingAreas set of the footprints that belong to machines that drive themselves
function HomeSpotShed.getTakenAreas(ignoredVehicles)
    local areas, selfDrivingAreas = {}, {}

    local function add(vehicle, area, kind)
        area.name = string.format("%s (%s)", vehicle:getFullName(), kind)
        area.kind = HomeSpotShed.getKind(vehicle)
        table.insert(areas, area)
        selfDrivingAreas[area] = HomeSpotShed.getIsSelfDriving(vehicle)
    end

    for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
        if not ignoredVehicles[vehicle] and vehicle.size ~= nil and vehicle.rootNode ~= nil then
            add(vehicle, HomeSpotArea.newFromNode(vehicle.size, vehicle.rootNode), "standing")
        end
    end

    for key, components in pairs(HomeSpots.store:getAll()) do
        local vehicle = HomeSpots.store:getVehicle(key)
        if vehicle ~= nil and not ignoredVehicles[vehicle] and vehicle.size ~= nil and #components == #vehicle.components then
            add(vehicle, HomeSpots.getHomeArea(vehicle, components), "spot")
        end
    end

    return areas, selfDrivingAreas
end


---Look up the floor height and whether there is a roof over every square of a room, once,
-- so that any place in the room can be judged over its whole footprint without more rays
-- @param table room room, gets its grid and the number of roofed squares (numRoofed)
function HomeSpotShed.setGrid(room)
    local halfU, halfV = room.axes[1][3], room.axes[2][3]
    local numU = math.max(1, math.ceil(halfU * 2 / HomeSpotShed.CELL_SIZE - 0.001))
    local numV = math.max(1, math.ceil(halfV * 2 / HomeSpotShed.CELL_SIZE - 0.001))
    local cellU, cellV = halfU * 2 / numU, halfV * 2 / numV
    local cells = {}
    local numRoofed = 0

    for iu = 1, numU do
        for iv = 1, numV do
            local u, v = -halfU + (iu - 0.5) * cellU, -halfV + (iv - 0.5) * cellV
            local x = room.x + room.axes[1][1] * u + room.axes[2][1] * v
            local z = room.z + room.axes[1][2] * u + room.axes[2][2] * v
            local floorY, terrainY = HomeSpotShed.getFloorHeight(x, z)
            local hasRoof = HomeSpotShed.getHasRoof(x, floorY + 1, z)

            cells[(iu - 1) * numV + iv] = {floorY = floorY, rise = floorY - terrainY, hasRoof = hasRoof}
            if hasRoof then
                numRoofed = numRoofed + 1
            end
        end
    end

    room.grid = {numU = numU, numV = numV, cellU = cellU, cellV = cellV, cells = cells}
    room.numRoofed = numRoofed
end


---Returns how far in from one edge of a room the nearest line of posts or wall stands: everything between the edge and it
-- is outside the building's roof
-- @param table room room
-- @param float floorY floor height in the middle of the room
-- @param integer axisIndex 1 or 2, the axis of the edge
-- @param integer sign 1 for the edge at the end of the axis, -1 for the one at its start
-- @return float inset distance (m), 0 when there is no such line
function HomeSpotShed.getInset(room, floorY, axisIndex, sign)
    local axis, rowAxis = room.axes[axisIndex], room.axes[3 - axisIndex]
    local reach = math.max(0, rowAxis[3] - HomeSpotShed.BOUND_CORNER)
    local numRays = math.max(1, math.floor(reach * 2 / HomeSpotShed.BOUND_RAY_SPACING))
    local hits = {}
    local nearest = math.huge

    for i = 0, numRays do
        local offset = -reach + reach * 2 * i / numRays
        local x = room.x + axis[1] * axis[3] * sign + rowAxis[1] * offset
        local z = room.z + axis[2] * axis[3] * sign + rowAxis[2] * offset
        local distance = HomeSpotShed.raycast(x, floorY + HomeSpotShed.WALL_RAY_HEIGHT, z, -axis[1] * sign, 0, -axis[2] * sign,
            HomeSpotShed.BOUND_SEARCH, HomeSpotShed.WALL_MASK)

        if distance ~= nil then
            table.insert(hits, {distance = distance, offset = offset})
            nearest = math.min(nearest, distance)
        end
    end

    local minOffset, maxOffset = math.huge, -math.huge
    for _, hit in ipairs(hits) do
        if hit.distance <= nearest + HomeSpotShed.BOUND_HIT_SPREAD then
            minOffset, maxOffset = math.min(minOffset, hit.offset), math.max(maxOffset, hit.offset)
        end
    end

    if maxOffset - minOffset < HomeSpotShed.BOUND_MIN_SPAN then
        return 0
    end

    return nearest
end


---Work out the part of a room that is inside its posts and walls, where a vehicle is under the roof
-- @param table room room, gets its bounds {{min, max}, {min, max}} along its two axes
function HomeSpotShed.setBounds(room)
    local floorY = HomeSpotShed.getFloorHeight(room.x, room.z)
    room.bounds = {}

    for axisIndex = 1, 2 do
        local half = room.axes[axisIndex][3]
        local atStart = HomeSpotShed.getInset(room, floorY, axisIndex, -1)
        local atEnd = HomeSpotShed.getInset(room, floorY, axisIndex, 1)

        room.bounds[axisIndex] = {-half + atStart, half - atEnd}
    end
end


---Returns the square of a room's grid a position lies in
-- @param table room room with its grid
-- @param float x, z world position
-- @return table cell floorY, rise (above the terrain) and hasRoof, or nil when the position is outside the room
function HomeSpotShed.getCell(room, x, z)
    local grid = room.grid
    local dx, dz = x - room.x, z - room.z
    local u = dx * room.axes[1][1] + dz * room.axes[1][2]
    local v = dx * room.axes[2][1] + dz * room.axes[2][2]
    local halfU, halfV = room.axes[1][3], room.axes[2][3]

    if math.abs(u) > halfU + HomeSpotShed.ROOM_TOLERANCE or math.abs(v) > halfV + HomeSpotShed.ROOM_TOLERANCE then
        return nil
    end

    local iu = math.min(grid.numU, math.max(1, math.floor((u + halfU) / grid.cellU) + 1))
    local iv = math.min(grid.numV, math.max(1, math.floor((v + halfV) / grid.cellV) + 1))

    return grid.cells[(iu - 1) * grid.numV + iv]
end


---Returns true for a machine that drives itself (tractors, trucks, harvesters), false for a tool or trailer that is pulled
-- @param table vehicle vehicle
-- @return boolean isSelfDriving
function HomeSpotShed.getIsSelfDriving(vehicle)
    return vehicle.spec_motorized ~= nil
end


---Returns a vehicle's place with its own size, for a spot to be found for
-- @param table vehicle vehicle
-- @return table place place (vehicle, halfLength, halfWidth) without a position yet
function HomeSpotShed.newPlace(vehicle)
    local area = HomeSpotArea.newFromNode(vehicle.size, vehicle.rootNode)

    return {vehicle = vehicle, halfLength = area.halfLength, halfWidth = area.halfWidth}
end


---Returns the footprint of a place, with the margin around it or without
-- @param table place place (x, z, dirX, dirZ, halfLength, halfWidth)
-- @param float margin extra room on every side (m)
-- @return table area footprint
function HomeSpotShed.getPlaceArea(place, margin)
    local size = {length = (place.halfLength + margin) * 2, width = (place.halfWidth + margin) * 2}

    return HomeSpotArea.new(size, place.x, place.z, place.dirX, place.dirZ, place.dirZ, -place.dirX)
end


---Test one vehicle's place in a room over its whole footprint: inside the room, on the floor, under the roof,
-- and nothing in the way up to the vehicle's height
-- @param table place place (x, z, dirX, dirZ, halfLength, halfWidth, vehicle), gets its floorY when it is free
-- @param table room room with its grid
-- @param table ignoredVehicles set of the vehicles being parked
-- @param table stats counts of why places were turned down
-- @return boolean isFree
-- @return string reason why not, when it is not free
function HomeSpotShed.testPlace(place, room, ignoredVehicles, stats)
    local numAlong = math.ceil(place.halfLength * 2 / HomeSpotShed.SAMPLE_SPACING) + 1
    local numSide = math.ceil(place.halfWidth * 2 / HomeSpotShed.SAMPLE_SPACING) + 1
    local sideX, sideZ = place.dirZ, -place.dirX

    for i = 0, numAlong - 1 do
        local along = -place.halfLength + place.halfLength * 2 * i / (numAlong - 1)

        for j = 0, numSide - 1 do
            local side = -place.halfWidth + place.halfWidth * 2 * j / (numSide - 1)
            local cell = HomeSpotShed.getCell(room, place.x + place.dirX * along + sideX * side, place.z + place.dirZ * along + sideZ * side)

            if cell == nil then
                stats.outside = stats.outside + 1
                return false, "partly outside the room"
            elseif cell.rise > HomeSpotShed.MAX_FLOOR_RISE then
                stats.noFloor = stats.noFloor + 1
                return false, "no floor"
            elseif room.numRoofed > 0 and not cell.hasRoof then
                stats.noRoof = stats.noRoof + 1
                return false, "not under the roof"
            end
        end
    end

    local floorY = HomeSpotShed.getCell(room, place.x, place.z).floorY
    local height = place.vehicle.size.height or HomeSpotShed.DEFAULT_HEIGHT
    local halfHeight = (height - HomeSpotShed.FLOOR_CLEARANCE) * 0.5

    stats.numPhysics = stats.numPhysics + 1
    local margin = HomeSpotShed.MARGIN - HomeSpotShed.CLEARANCE_SLACK
    local obstacle = HomeSpotShed.getObstacle(place.x, floorY + HomeSpotShed.FLOOR_CLEARANCE + halfHeight, place.z,
        HomeSpotShed.getYaw(place.dirX, place.dirZ), place.halfWidth + margin, halfHeight, place.halfLength + margin,
        HomeSpotShed.OBSTACLE_MASK, ignoredVehicles)

    if obstacle ~= nil then
        stats.blocked = stats.blocked + 1
        return false, string.format("'%s' in the way", getName(obstacle))
    end

    place.floorY = floorY

    return true
end


---Returns the footprints that are close enough to a room to matter
-- @param table taken footprints
-- @param table room room
-- @return table areas footprints near the room
function HomeSpotShed.getTakenNear(taken, room)
    local near = {}
    local roomRadius = MathUtil.vector2Length(room.axes[1][3], room.axes[2][3])

    for _, area in ipairs(taken) do
        local reach = roomRadius + MathUtil.vector2Length(area.halfLength, area.halfWidth)

        if MathUtil.vector2Length(area.x - room.x, area.z - room.z) <= reach then
            table.insert(near, area)
        end
    end

    return near
end


---Returns the depths and rows (m along the facing and along the room's other axis) a machine's centre may stand at in a room,
-- keeping the whole machine inside the room's bounds and a margin from their edges
-- @param table place place (halfLength, halfWidth)
-- @param table room room with its bounds
-- @param table facing facing of the room
-- @return float nearest, furthest depth from the back of the room to the open side
-- @return float first, last row
function HomeSpotShed.getRanges(place, room, facing)
    local depthBounds, rowBounds = room.bounds[facing.depthIndex], room.bounds[3 - facing.depthIndex]
    local margin = HomeSpotShed.MARGIN
    local depthLow, depthHigh = depthBounds[1] + place.halfLength + margin, depthBounds[2] - place.halfLength - margin

    if facing.sign < 0 then
        depthLow, depthHigh = -depthHigh, -depthLow
    end

    return depthLow, depthHigh, rowBounds[1] + place.halfWidth + margin, rowBounds[2] - place.halfWidth - margin
end


---Try one place for a machine in a room: inside the room's bounds, clear of everything taken, under the roof, and nothing in the way
-- @param table place place (vehicle, halfLength, halfWidth), gets its position, depth, room and facing when it is free
-- @param table room room with its grid and bounds
-- @param table facing facing of the room (dirX, dirZ, rowAxis)
-- @param float depth, row where the machine's centre would stand (m along the facing and along the row axis)
-- @param table taken footprints no vehicle may be parked on
-- @param table ignoredVehicles set of the vehicles being parked
-- @param table stats counts of why spots were turned down
-- @return boolean isFree
-- @return string reason why not, when it is not free
function HomeSpotShed.tryPlace(place, room, facing, depth, row, taken, ignoredVehicles, stats)
    place.x = room.x + facing.dirX * depth + facing.rowAxis[1] * row
    place.z = room.z + facing.dirZ * depth + facing.rowAxis[2] * row
    place.dirX, place.dirZ = facing.dirX, facing.dirZ

    local overlapped = HomeSpotArea.getFirstOverlap(HomeSpotShed.getPlaceArea(place, HomeSpotShed.MARGIN + HomeSpotArea.TOLERANCE - HomeSpotShed.CLEARANCE_SLACK), taken)
    if overlapped ~= nil then
        stats.taken = stats.taken + 1
        return false, string.format("taken by %s", overlapped.name or "a vehicle")
    end

    if stats.numPhysics >= HomeSpotShed.MAX_PHYSICS_TESTS then
        return false, "too many places tried"
    end

    local isFree, reason = HomeSpotShed.testPlace(place, room, ignoredVehicles, stats)
    if not isFree then
        return false, reason
    end

    place.depth, place.row, place.room, place.facing = depth, row, room, facing

    return true
end


---Returns the rows (m along the room's other axis) worth trying for a machine at one depth, in the order of the line, from left
-- to right: every step across the room, and the places snug against the machines and spots in that line, where a machine
-- fits exactly between two others
-- @param table place place (halfLength, halfWidth)
-- @param table facing facing of the room (dirX, dirZ, rowAxis, rowDirection)
-- @param table room room
-- @param float depth depth of the line the machine's centre would stand at
-- @param float rowLow, rowHigh first and last row the centre may stand at
-- @param table taken footprints no vehicle may be parked on
-- @return table rows rows
function HomeSpotShed.getRowCandidates(place, room, facing, depth, rowLow, rowHigh, taken)
    local rows = {}
    local numRow = math.floor((rowHigh - rowLow) / HomeSpotShed.GRID_STEP + 0.001)

    for j = 0, numRow do
        table.insert(rows, rowLow + j * HomeSpotShed.GRID_STEP)
    end

    local rowAxis = facing.rowAxis
    local margin = HomeSpotShed.MARGIN

    for _, area in ipairs(taken) do
        local dx, dz = area.x - room.x, area.z - room.z
        local areaDepth = dx * facing.dirX + dz * facing.dirZ
        local areaRow = dx * rowAxis[1] + dz * rowAxis[2]
        local alongDepth, acrossDepth = area.dirX * facing.dirX + area.dirZ * facing.dirZ, area.sideX * facing.dirX + area.sideZ * facing.dirZ
        local alongRow, acrossRow = area.dirX * rowAxis[1] + area.dirZ * rowAxis[2], area.sideX * rowAxis[1] + area.sideZ * rowAxis[2]
        local reachDepth = math.abs(alongDepth) * area.halfLength + math.abs(acrossDepth) * area.halfWidth
        local reachRow = math.abs(alongRow) * area.halfLength + math.abs(acrossRow) * area.halfWidth

        if math.abs(areaDepth - depth) < reachDepth + place.halfLength + margin then
            for _, sign in ipairs({-1, 1}) do
                local row = areaRow + sign * (reachRow + place.halfWidth + margin + HomeSpotShed.SNUG_SLACK)

                if row >= rowLow and row <= rowHigh then
                    table.insert(rows, row)
                end
            end
        end
    end

    local sign = facing.rowDirection
    table.sort(rows, function(a, b) return a * sign < b * sign end)

    return rows
end


---Move a machine that has found its place towards where the line starts, as far as it stays free, so it stands snug
-- @param table place place that is free, with its position, depth, row, room and facing
-- @param table taken footprints no vehicle may be parked on
-- @param table ignoredVehicles set of the vehicles being parked
-- @param table stats counts of why spots were turned down
function HomeSpotShed.slideToStart(place, taken, ignoredVehicles, stats)
    local room, facing = place.room, place.facing
    local _, _, rowLow, rowHigh = HomeSpotShed.getRanges(place, room, facing)
    local best = {x = place.x, z = place.z, depth = place.depth, row = place.row, floorY = place.floorY}
    local numSlides = math.floor(HomeSpotShed.GRID_STEP / HomeSpotShed.SLIDE_STEP + 0.001)

    for i = 1, numSlides do
        local row = best.row - facing.rowDirection * HomeSpotShed.SLIDE_STEP
        if row < rowLow - 0.001 or row > rowHigh + 0.001
            or not HomeSpotShed.tryPlace(place, room, facing, best.depth, row, taken, ignoredVehicles, stats) then
            break
        end

        best = {x = place.x, z = place.z, depth = place.depth, row = place.row, floorY = place.floorY}
    end

    place.x, place.z, place.depth, place.row, place.floorY = best.x, best.z, best.depth, best.row, best.floorY
    place.room, place.facing = room, facing
end


---Write down which machines and spots stand in a room, where the finder counts them, along its first facing
-- @param table room room with its facings
-- @param table taken footprints
function HomeSpotShed.logTaken(room, taken)
    local facing = room.facings[1]
    if facing == nil then
        return
    end

    local front = HomeSpotShed.getFrontDepth(room, facing)
    Logging.info("Home Spots: in '%s' the finder faces (%.2f, %.2f) out of the front and fills each line %s along the row axis (%.2f, %.2f)",
        room.name, facing.dirX, facing.dirZ, facing.rowDirection > 0 and "up" or "down", facing.rowAxis[1], facing.rowAxis[2])

    for _, area in ipairs(HomeSpotShed.getTakenNear(taken, room)) do
        local dx, dz = area.x - room.x, area.z - room.z
        local depth = dx * facing.dirX + dz * facing.dirZ

        Logging.info("Home Spots:   %s: %.1f m from the front, %.1f m along the line, %.1f x %.1f m",
            area.name or "?", front - depth - area.halfLength, dx * facing.rowAxis[1] + dz * facing.rowAxis[2], area.halfLength * 2, area.halfWidth * 2)
    end
end


---Write down why the places along the first line of a room were turned down, as runs of the same reason
-- @param string name vehicle name
-- @param table trace turned-down places (facing, row, reason)
function HomeSpotShed.logTrace(name, trace)
    local runs = {}

    for _, entry in ipairs(trace) do
        local run = runs[#runs]
        local reason = entry.reason:gsub("^taken by (.-) %(.-%)$", "taken by %1")

        if run ~= nil and run.facing == entry.facing and run.reason == reason then
            run.last = entry.row
        else
            table.insert(runs, {facing = entry.facing, reason = reason, first = entry.row, last = entry.row})
        end
    end

    for i, run in ipairs(runs) do
        if i > 24 then
            Logging.info("Home Spots:   ... and %d more", #runs - 24)
            break
        end

        Logging.info("Home Spots:   %s: facing (%.2f, %.2f), line runs %s, along the line %.1f to %.1f m: %s",
            name, run.facing.dirX, run.facing.dirZ, run.facing.rowDirection > 0 and "up" or "down", run.first, run.last, run.reason)
    end
end


---Returns the first free spot for a machine in a room, facing one way. The room is filled in lines across it,
-- each from left to right as seen from outside the open front. The lines start at the open front, or at a depth given, and go back,
-- or start at the back wall and come forward. A machine that finds a place slides snug towards the start of its line.
-- @param table place place (vehicle, halfLength, halfWidth), gets its position when it is free
-- @param table room room with its grid and bounds
-- @param table facing facing of the room (dirX, dirZ, rowAxis, rowDirection)
-- @param table scan where to start: startDepth (m along the facing), or fromBack; the open front by default
-- @param table taken footprints no vehicle may be parked on
-- @param table ignoredVehicles set of the vehicles being parked
-- @param table stats counts of why spots were turned down
-- @return boolean isFound
function HomeSpotShed.findPlaceInRoom(place, room, facing, scan, taken, ignoredVehicles, stats)
    local depthLow, depthHigh, rowLow, rowHigh = HomeSpotShed.getRanges(place, room, facing)
    local step = HomeSpotShed.GRID_STEP
    local firstDepth, direction = math.min(scan.startDepth or depthHigh, depthHigh), -1

    if scan.fromBack then
        firstDepth, direction = depthLow, 1
    end

    local numDepth = math.floor(math.abs(firstDepth - (direction < 0 and depthLow or depthHigh)) / step + 0.001)
    if rowLow > rowHigh or firstDepth < depthLow - 0.001 then
        return false
    end

    for i = 0, numDepth do
        local depth = firstDepth + direction * i * step

        for _, row in ipairs(HomeSpotShed.getRowCandidates(place, room, facing, depth, rowLow, rowHigh, taken)) do
            local isFree, reason = HomeSpotShed.tryPlace(place, room, facing, depth, row, taken, ignoredVehicles, stats)

            if isFree then
                HomeSpotShed.slideToStart(place, taken, ignoredVehicles, stats)

                return true
            end

            if i == 0 and stats.trace ~= nil then
                table.insert(stats.trace, {facing = facing, row = row, reason = reason})
            end
        end
    end

    return false
end


---Returns a room's machines in the order of a walk: line by line from the front, each line from left to right
-- @param table facing facing of the room, with its anchors
-- @return table anchors machines (depth, row, rear, front)
function HomeSpotShed.getAnchorsInOrder(facing)
    local anchors = facing.anchors or {}

    table.sort(anchors, function(a, b) return a.front > b.front end)

    local line, lineFront = 0, nil
    for _, anchor in ipairs(anchors) do
        if lineFront == nil or lineFront - anchor.front > HomeSpotShed.LINE_TOLERANCE then
            line, lineFront = line + 1, anchor.front
        end
        anchor.line = line
    end

    table.sort(anchors, function(a, b)
        if a.line ~= b.line then
            return a.line < b.line
        end
        if a.row ~= b.row then
            return (a.row < b.row) == (facing.rowDirection > 0)
        end

        return false
    end)

    return anchors
end


---Returns the first free spot for a tool directly behind a machine that stands in the room: behind one of its own kind
-- if there is room, otherwise walking through the machines line by line from the front, each line from left to right,
-- and taking the first one with room behind it
-- @param table place place (vehicle, halfLength, halfWidth), gets its position when it is free
-- @param table room room with its grid and bounds
-- @param table facing facing of the room, with its anchors
-- @param table taken footprints no vehicle may be parked on
-- @param table ignoredVehicles set of the vehicles being parked
-- @param table stats counts of why spots were turned down
-- @return boolean isFound
function HomeSpotShed.findPlaceBehind(place, room, facing, taken, ignoredVehicles, stats)
    local depthLow, depthHigh, rowLow, rowHigh = HomeSpotShed.getRanges(place, room, facing)
    if rowLow > rowHigh then
        return false
    end

    local anchors = HomeSpotShed.getAnchorsInOrder(facing)
    local kind = HomeSpotShed.getKind(place.vehicle)

    -- Machines of the same kind first, so they stand in one column, then any machine, in order
    for pass = 1, 2 do
        for _, anchor in ipairs(anchors) do
            if pass == 2 or anchor.kind == kind then
                local depth = anchor.rear - HomeSpotShed.MARGIN - place.halfLength
                local row = math.min(rowHigh, math.max(rowLow, anchor.row))
                local isFree, reason = false, "no room behind it in the shed"

                if depth >= depthLow - 0.001 and depth <= depthHigh + 0.001 then
                    isFree, reason = HomeSpotShed.tryPlace(place, room, facing, depth, row, taken, ignoredVehicles, stats)
                end

                Logging.info("Home Spots: %s behind %s (line %d, %.1f m from the front): %s", place.vehicle:getFullName(), anchor.name or "a vehicle",
                    anchor.line or 0, HomeSpotShed.getFrontDepth(room, facing) - anchor.rear, isFree and "free" or reason)

                if isFree then
                    return true
                end
            end
        end
    end

    return false
end


---Take note of a machine standing, or with its home spot, in a room: what a tool can be parked behind, and for
-- machines that drive themselves how far back from the open front they reach
-- @param table room room with its facings and bounds
-- @param table area footprint of the machine
-- @param boolean isSelfDriving true for a machine that drives itself
function HomeSpotShed.addArea(room, area, isSelfDriving)
    for _, facing in ipairs(room.facings) do
        local depthBounds, rowBounds = room.bounds[facing.depthIndex], room.bounds[3 - facing.depthIndex]
        local dx, dz = area.x - room.x, area.z - room.z
        local depth = dx * facing.dirX + dz * facing.dirZ
        local row = dx * facing.rowAxis[1] + dz * facing.rowAxis[2]
        local along = area.dirX * facing.dirX + area.dirZ * facing.dirZ
        local across = area.dirX * facing.rowAxis[1] + area.dirZ * facing.rowAxis[2]
        local reach = math.abs(along) * area.halfLength + math.abs(across) * area.halfWidth

        if facing.sign * depth >= depthBounds[1] and facing.sign * depth <= depthBounds[2] and row >= rowBounds[1] and row <= rowBounds[2] then
            facing.anchors = facing.anchors or {}
            table.insert(facing.anchors, {name = area.name, kind = area.kind, depth = depth, row = row, rear = depth - reach, front = depth + reach})

            if isSelfDriving then
                facing.bandRear = math.min(facing.bandRear or math.huge, depth - reach)
            end
        end
    end
end


---Returns the depth of the open front of a room, facing one way (m along the facing, from the middle of the room)
-- @param table room room with its bounds
-- @param table facing facing of the room
-- @return float depth
function HomeSpotShed.getFrontDepth(room, facing)
    local depthBounds = room.bounds[facing.depthIndex]

    return facing.sign > 0 and depthBounds[2] or -depthBounds[1]
end


---Returns where to look for a machine's spot in one facing of a room, best first: machines that drive themselves start at the open
-- front. A tool goes directly behind a machine that stands in the room, the first one in line with room behind it,
-- or else starts right behind the machines at the front (where a tractor's length would end when there are none),
-- and then anywhere from the front.
-- @param table place place (vehicle, halfLength)
-- @param table room room with its bounds
-- @param table facing facing of the room, with bandRear once a machine that drives itself stands in it
-- @return table scans list of scans, see HomeSpotShed.findPlaceInRoom; behind means directly behind a machine
function HomeSpotShed.getScans(place, room, facing)
    if HomeSpotShed.getIsSelfDriving(place.vehicle) then
        return {{}}
    end

    local bandRear = facing.bandRear or HomeSpotShed.getFrontDepth(room, facing) - HomeSpotShed.FRONT_BAND

    return {{behind = true}, {startDepth = bandRear - HomeSpotShed.MARGIN - place.halfLength}, {}}
end


---Finds a spot for a machine in the rooms, the nearest shed first and in each room the best way to face first
-- @param table place place (vehicle, halfLength, halfWidth), gets its position when it is free
-- @param table rooms rooms with their grids and facings
-- @param table taken footprints no vehicle may be parked on
-- @param table ignoredVehicles set of the vehicles being parked
-- @param table stats counts of why spots were turned down
-- @return string roomName name of the shed, or nil when there is no room
function HomeSpotShed.findPlaceInRooms(place, rooms, taken, ignoredVehicles, stats)
    for _, room in ipairs(rooms) do
        local takenNear = HomeSpotShed.getTakenNear(taken, room)

        for _, facing in ipairs(room.facings) do
            for _, scan in ipairs(HomeSpotShed.getScans(place, room, facing)) do
                local isFound
                if scan.behind then
                    isFound = HomeSpotShed.findPlaceBehind(place, room, facing, takenNear, ignoredVehicles, stats)
                else
                    isFound = HomeSpotShed.findPlaceInRoom(place, room, facing, scan, takenNear, ignoredVehicles, stats)
                end

                if isFound then
                    return room.name
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
        setRotation(pivot, 0, HomeSpotShed.getYaw(currentDirX, currentDirZ), 0)
        setWorldTranslation(child, getWorldTranslation(component.node))
        setWorldRotation(child, getWorldRotation(component.node))

        setTranslation(pivot, rootX, rootY, rootZ)
        setRotation(pivot, 0, HomeSpotShed.getYaw(place.dirX, place.dirZ), 0)

        local x, y, z = getWorldTranslation(child)
        local rx, ry, rz = getWorldRotation(child)
        components[i] = {{x, y, z}, {rx, ry, rz}}
    end

    return components
end


---Server: find places in the farm's nearest sheds. Every machine gets a place of its own: the self-driving ones go first,
-- in the front rows, and the tools behind them, as many side by side in a row as the shed is wide.
-- @param table vehicles vehicles of one farm
-- @param integer farmId farm
-- @return table places list of {vehicle, components}; vehicles without room are left out
function HomeSpotShed.findPlaces(vehicles, farmId)
    if #vehicles == 0 or HomeSpotShed.pivotNode == nil then
        return {}
    end

    local x, _, z = getWorldTranslation(vehicles[1].rootNode)
    local rooms = HomeSpotShed.getFarmRooms(farmId, x, z)

    local ignoredVehicles, places = {}, {}
    for _, vehicle in ipairs(vehicles) do
        ignoredVehicles[vehicle] = true
        table.insert(places, HomeSpotShed.newPlace(vehicle))
    end

    -- Self-driving machines first, and the biggest first within each kind, which packs the rows best
    table.sort(places, function(a, b)
        local isSelfA, isSelfB = HomeSpotShed.getIsSelfDriving(a.vehicle), HomeSpotShed.getIsSelfDriving(b.vehicle)
        if isSelfA ~= isSelfB then
            return isSelfA
        end

        return a.halfLength * a.halfWidth > b.halfLength * b.halfWidth
    end)

    local taken, selfDrivingAreas = HomeSpotShed.getTakenAreas(ignoredVehicles)
    for _, room in ipairs(rooms) do
        for _, area in ipairs(taken) do
            HomeSpotShed.addArea(room, area, selfDrivingAreas[area] == true)
        end
    end
    for _, room in ipairs(rooms) do
        HomeSpotShed.logTaken(room, taken)
    end
    local result = {}

    for _, place in ipairs(places) do
        local stats = {numPhysics = 0, taken = 0, outside = 0, noFloor = 0, noRoof = 0, blocked = 0, trace = {}}
        local roomName = HomeSpotShed.findPlaceInRooms(place, rooms, taken, ignoredVehicles, stats)
        local name = place.vehicle:getFullName()

        HomeSpotShed.logTrace(name, stats.trace)

        if roomName ~= nil then
            local area = HomeSpotShed.getPlaceArea(place, 0)
            area.name = string.format("%s (spot)", place.vehicle:getFullName())
            area.kind = HomeSpotShed.getKind(place.vehicle)
            table.insert(taken, area)
            HomeSpotShed.addArea(place.room, area, HomeSpotShed.getIsSelfDriving(place.vehicle))
            table.insert(result, {vehicle = place.vehicle, components = HomeSpotShed.getComponentsAt(place.vehicle, place)})
            Logging.info("Home Spots: %s got a home spot in '%s', its front %.1f m from the open front, %.1f m along the line",
                name, roomName, HomeSpotShed.getFrontDepth(place.room, place.facing) - place.depth - place.halfLength, place.row or 0)
        else
            Logging.info("Home Spots: no room for %s in %d shed room(s): %d taken, %d partly outside, %d without floor, %d without roof, %d in the way",
                name, #rooms, stats.taken, stats.outside, stats.noFloor, stats.noRoof, stats.blocked)
        end
    end

    return result
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

    return HomeSpotShed.getObstacle(area.x, y + HomeSpotShed.WALL_MIN_HEIGHT + halfHeight, area.z, HomeSpotShed.getYaw(area.dirX, area.dirZ),
        halfWidth, halfHeight, halfLength, HomeSpotShed.SOLID_MASK, nil)
end
