---Nearby spots: when a vehicle's home spot is taken or runs into a wall, find the nearest free space beside it,
-- with the same heading, instead of leaving the vehicle where it is.
HomeSpotNearby = {}

-- The spot is searched on a grid this fine (m), out to this far from the home spot (m)
HomeSpotNearby.STEP = 0.5
HomeSpotNearby.MAX_DISTANCE = 20
-- A space whose floor is this much higher or lower than the home spot (m) is too steep or too far off level
HomeSpotNearby.MAX_HEIGHT_DIFFERENCE = 1.5
-- Most spaces tested against the physics per vehicle, so a crowded yard never stalls the game
HomeSpotNearby.MAX_PHYSICS_TESTS = 150

-- Grid offsets from the home spot, nearest first, built once: {along, side} in m in the vehicle's own directions
HomeSpotNearby.offsets = nil


---Returns the grid offsets around a spot, the spot itself first and then nearest first;
-- on a tie the one straight beside the spot comes first
-- @return table offsets list of {along, side, distance}
function HomeSpotNearby.getOffsets()
    if HomeSpotNearby.offsets ~= nil then
        return HomeSpotNearby.offsets
    end

    local offsets = {}
    local numSteps = math.floor(HomeSpotNearby.MAX_DISTANCE / HomeSpotNearby.STEP)

    for i = -numSteps, numSteps do
        for j = -numSteps, numSteps do
            local along, side = i * HomeSpotNearby.STEP, j * HomeSpotNearby.STEP
            local distance = MathUtil.vector2Length(along, side)

            if distance <= HomeSpotNearby.MAX_DISTANCE then
                table.insert(offsets, {along = along, side = side, distance = distance})
            end
        end
    end

    table.sort(offsets, function(a, b)
        if a.distance ~= b.distance then
            return a.distance < b.distance
        end
        if math.abs(a.along) ~= math.abs(b.along) then
            return math.abs(a.along) < math.abs(b.along)
        end
        if a.along ~= b.along then
            return a.along < b.along
        end
        return a.side < b.side
    end)

    HomeSpotNearby.offsets = offsets

    return offsets
end


---Returns the nearest free space beside a vehicle's home spot. The spot itself counts first: it may be free by now,
-- once a vehicle standing on it has been given a space of its own.
-- @param table move move (vehicle, homeArea, components)
-- @param table obstacles footprints the space must keep clear of
-- @param table ignoredVehicles set of vehicles that are about to move away, which the physics test looks through
-- @return table space movement of the spot (dx, dy, dz) and the footprint there (area), or nil when there is none;
--   dx, dy and dz are all 0 when the home spot itself is free
function HomeSpotNearby.findSpace(move, obstacles, ignoredVehicles)
    local area = move.homeArea
    local halfLength = area.halfLength + HomeSpotShed.MARGIN
    local halfWidth = area.halfWidth + HomeSpotShed.MARGIN
    local height = move.vehicle.size.height or HomeSpotShed.DEFAULT_HEIGHT
    local halfHeight = (height - HomeSpotShed.FLOOR_CLEARANCE) * 0.5
    local yaw = HomeSpotShed.getYaw(area.dirX, area.dirZ)
    local footprint = {length = halfLength * 2, width = halfWidth * 2}
    local homeFloorY = HomeSpotShed.getFloorHeight(area.x, area.z)
    local numTests = 0

    for _, offset in ipairs(HomeSpotNearby.getOffsets()) do
        local x = area.x + area.dirX * offset.along + area.sideX * offset.side
        local z = area.z + area.dirZ * offset.along + area.sideZ * offset.side
        local candidate = HomeSpotArea.new(footprint, x, z, area.dirX, area.dirZ, area.sideX, area.sideZ)

        if not HomeSpotArea.getOverlapsAny(candidate, obstacles) then
            numTests = numTests + 1
            if numTests > HomeSpotNearby.MAX_PHYSICS_TESTS then
                return nil
            end

            local floorY = HomeSpotShed.getFloorHeight(x, z)
            local rise = floorY - homeFloorY

            if math.abs(rise) <= HomeSpotNearby.MAX_HEIGHT_DIFFERENCE
                and HomeSpotShed.getObstacle(x, floorY + HomeSpotShed.FLOOR_CLEARANCE + halfHeight, z, yaw, halfWidth, halfHeight, halfLength,
                    HomeSpotShed.OBSTACLE_MASK, ignoredVehicles) == nil then
                local placed = {}
                for key, value in pairs(area) do
                    placed[key] = value
                end
                placed.x, placed.z = x, z

                local isMoved = offset.distance > 0

                return {dx = x - area.x, dy = isMoved and rise + HomeSpotShed.LIFT or 0, dz = z - area.z, area = placed}
            end
        end
    end

    return nil
end


---Returns the saved positions of a spot moved by a distance, with the same headings
-- @param table components saved component positions
-- @param float dx, dy, dz how far to move
-- @return table components moved component positions
function HomeSpotNearby.getMovedComponents(components, dx, dy, dz)
    local moved = {}

    for i, component in ipairs(components) do
        local position, rotation = component[1], component[2]
        moved[i] = {{position[1] + dx, position[2] + dy, position[3] + dz}, {rotation[1], rotation[2], rotation[3]}}
    end

    return moved
end


---Returns the footprints of every saved home spot, by vehicle
-- @return table areas footprint by vehicle
function HomeSpotNearby.getSpotAreas()
    local areas = {}

    for key, components in pairs(HomeSpots.store:getAll()) do
        local vehicle = HomeSpots.store:getVehicle(key)

        if vehicle ~= nil and vehicle.size ~= nil and #components == #vehicle.components then
            areas[vehicle] = HomeSpots.getHomeArea(vehicle, components)
        end
    end

    return areas
end


---Server: move the blocked moves whose home spot is taken to the nearest free space beside it.
-- A vehicle that finds no space stays blocked. Spaces keep clear of every vehicle that stays where it is
-- (including the blocked ones still waiting), of every saved home spot, and of the spaces given out so far.
-- @param table blocked moves whose home spot is taken (vehicle, components, homeArea, currentArea)
-- @param table accepted moves that go ahead to their home spot
-- @param table staticAreas footprints of the vehicles that stay where they are, the blocked ones included
-- @return table placed the moves that got a space, with their components changed to it; isNearby is set on those
--   that could not go to their own spot after all
-- @return table stillBlocked the moves that found none
function HomeSpotNearby.placeBlocked(blocked, accepted, staticAreas)
    local placed, stillBlocked = {}, {}
    if #blocked == 0 then
        return placed, stillBlocked
    end

    local spotAreas = HomeSpotNearby.getSpotAreas()
    local ignoredVehicles = {}
    for _, move in ipairs(accepted) do
        ignoredVehicles[move.vehicle] = true
    end

    local leftAreas, givenAreas = {}, {}

    for _, move in ipairs(blocked) do
        local obstacles = {}
        for _, area in ipairs(staticAreas) do
            if area ~= move.currentArea and not leftAreas[area] then
                table.insert(obstacles, area)
            end
        end
        for vehicle, area in pairs(spotAreas) do
            if vehicle ~= move.vehicle then
                table.insert(obstacles, area)
            end
        end
        for _, area in ipairs(givenAreas) do
            table.insert(obstacles, area)
        end

        ignoredVehicles[move.vehicle] = true
        local space = HomeSpotNearby.findSpace(move, obstacles, ignoredVehicles)

        if space ~= nil then
            move.components = HomeSpotNearby.getMovedComponents(move.components, space.dx, space.dy, space.dz)
            move.homeArea = space.area
            move.isNearby = space.dx ~= 0 or space.dz ~= 0
            leftAreas[move.currentArea] = true
            table.insert(givenAreas, space.area)
            table.insert(placed, move)
        else
            ignoredVehicles[move.vehicle] = nil
            table.insert(stillBlocked, move)
        end
    end

    return placed, stillBlocked
end
