---Shed finder: give every machine of a combination a place in the farm's sheds, self-driving machines in the front lines
-- and tools behind them, and turn a place into the component positions of a home spot.


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

                if HomeSpotShed.getIsDetailed() then
                    Logging.info("Home Spots: %s behind %s (line %d, %.1f m from the front): %s", place.vehicle:getFullName(), anchor.name or "a vehicle",
                        anchor.line or 0, HomeSpotShed.getFrontDepth(room, facing) - anchor.rear, isFree and "free" or reason)
                end

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
                if HomeSpotShed.getIsOverBudget(stats) then
                    return nil
                end

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
        local stats = {numTried = 0, numPhysics = 0, taken = 0, outside = 0, noFloor = 0, noRoof = 0, blocked = 0, trace = HomeSpotShed.getIsDetailed() and {} or nil}
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
