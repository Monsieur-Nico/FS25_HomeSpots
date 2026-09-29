---Shed rooms: find the farm's sheds, the room under each roof, which way vehicles face in it, and a grid of
-- floor height and roof over every square, so a place can be judged over its whole footprint without more rays.


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
