---Shed places: judge and search places for one machine in a room: clear of what is taken, inside the room, under the roof,
-- with nothing in the way, and snug against its neighbours.


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


---Returns true once a machine has used up its share of tries and physics tests, so the search stops
-- @param table stats counts of the places tried and why they were turned down
-- @return boolean isOverBudget
function HomeSpotShed.getIsOverBudget(stats)
    return stats.numTried > HomeSpotShed.MAX_PLACES_TRIED or stats.numPhysics >= HomeSpotShed.MAX_PHYSICS_TESTS
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

    stats.numTried = stats.numTried + 1
    if stats.numTried > HomeSpotShed.MAX_PLACES_TRIED then
        return false, "too many places tried"
    end

    local overlapped = HomeSpotArea.getFirstOverlap(HomeSpotShed.getPlaceArea(place, HomeSpotShed.MARGIN + HomeSpotArea.TOLERANCE - HomeSpotShed.CLEARANCE_SLACK), taken)
    if overlapped ~= nil then
        stats.taken = stats.taken + 1
        return false, string.format("taken by %s", overlapped.name or "a vehicle")
    end

    if HomeSpotShed.getIsOverBudget(stats) then
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
        if HomeSpotShed.getIsOverBudget(stats) then
            return false
        end

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
