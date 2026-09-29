---Targets: the vehicle the player sits in or looks at, and the combination it belongs to.


---Returns the vehicles the set and remove keys act on: the combination the player sits in,
-- or on foot, the vehicle or tool the player is looking at
-- @return table vehicles
function HomeSpots.getTargetVehicles()
    local player = g_localPlayer
    if player == nil then
        return {}
    end

    local vehicles = {}
    local currentVehicle = player:getCurrentVehicle()

    if currentVehicle ~= nil then
        for _, childVehicle in ipairs(currentVehicle:getRootVehicle():getChildVehicles()) do
            if HomeSpots.canHaveHomeSpot(childVehicle) then
                table.insert(vehicles, childVehicle)
            end
        end
    else
        local vehicle = HomeSpots.getLookedAtVehicle(player)

        if vehicle ~= nil and HomeSpots.canHaveHomeSpot(vehicle) and vehicle:getOwnerFarmId() == g_currentMission:getFarmId() then
            table.insert(vehicles, vehicle)
        end
    end

    return vehicles
end


---Returns the vehicle a physics node belongs to, also when the node is a collision shape below a vehicle component
-- @param integer node node id
-- @return table vehicle vehicle or nil
function HomeSpots.getVehicleFromNode(node)
    local vehicleSystem = g_currentMission.vehicleSystem

    while node ~= nil and node ~= 0 and entityExists(node) do
        local vehicle = vehicleSystem:getVehicleByNodeId(node, node)
        if vehicle ~= nil then
            return vehicle
        end

        node = getParent(node)
    end

    return nil
end


---Returns the vehicle or tool the player on foot is looking at: first by a look ray against vehicle collisions,
-- then by the vehicles' outlines along the same ray, which also catches open frames like seed drills.
-- Both are worked out fresh every frame, so the result clears as soon as the player looks away.
-- @param table player player
-- @return table vehicle vehicle or nil
function HomeSpots.getLookedAtVehicle(player)
    if player.getLookRay == nil then
        return nil
    end

    local x, y, z, dirX, dirY, dirZ = player:getLookRay()
    if x == nil then
        return nil
    end

    HomeSpots.lookRayVehicle = nil
    raycastAll(x, y, z, dirX, dirY, dirZ, HomeSpots.LOOK_DISTANCE, "onLookRayHit", HomeSpots, CollisionFlag.VEHICLE)

    return HomeSpots.lookRayVehicle or HomeSpots.getVehicleAlongLookRay(x, y, z, dirX, dirY, dirZ)
end


---Returns the first vehicle of the player's farm whose outline (footprint and height) the look ray passes through.
-- Works from vehicle sizes alone, so it also finds tools whose collisions the look ray slips past.
-- A vehicle whose outline the player stands in is skipped: the ray starts inside it, so it would match wherever the player looks.
-- @param float x, y, z look ray start
-- @param float dirX, dirY, dirZ look ray direction (unit length)
-- @return table vehicle vehicle or nil
function HomeSpots.getVehicleAlongLookRay(x, y, z, dirX, dirY, dirZ)
    local farmId = g_currentMission:getFarmId()
    local nearby = {}

    for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.rootNode ~= nil and vehicle.size ~= nil and vehicle:getOwnerFarmId() == farmId and HomeSpots.canHaveHomeSpot(vehicle) then
            local area = HomeSpotArea.newFromNode(vehicle.size, vehicle.rootNode)
            local reach = HomeSpots.LOOK_DISTANCE + area.halfLength + area.halfWidth
            local dx, dz = area.x - x, area.z - z

            if dx * dx + dz * dz <= reach * reach then
                local _, rootY, _ = getWorldTranslation(vehicle.rootNode)
                local height = vehicle.size.height or HomeSpots.DEFAULT_VEHICLE_HEIGHT
                local candidate = {
                    vehicle = vehicle,
                    area = area,
                    minY = rootY - HomeSpots.LOOK_MARGIN - 1,
                    maxY = rootY + height + HomeSpots.LOOK_MARGIN
                }

                if not HomeSpots.getIsInOutline(candidate, x, y, z) then
                    table.insert(nearby, candidate)
                end
            end
        end
    end

    if #nearby == 0 then
        return nil
    end

    for distance = HomeSpots.LOOK_STEP, HomeSpots.LOOK_DISTANCE, HomeSpots.LOOK_STEP do
        local pointX, pointY, pointZ = x + dirX * distance, y + dirY * distance, z + dirZ * distance

        for _, candidate in ipairs(nearby) do
            if HomeSpots.getIsInOutline(candidate, pointX, pointY, pointZ) then
                return candidate.vehicle
            end
        end
    end

    return nil
end


---Returns true if a point lies inside a vehicle's outline: its footprint, widened by LOOK_MARGIN, between minY and maxY
-- @param table candidate outline (area, minY, maxY)
-- @param float x, y, z world position
-- @return boolean isInside
function HomeSpots.getIsInOutline(candidate, x, y, z)
    return y >= candidate.minY and y <= candidate.maxY and HomeSpotArea.getContainsPoint(candidate.area, x, z, HomeSpots.LOOK_MARGIN)
end


---Look ray callback: keep the first vehicle hit
-- @param integer hitObjectId hit physics object
-- @return boolean continue false once a vehicle is found
function HomeSpots:onLookRayHit(hitObjectId, x, y, z, distance, normalX, normalY, normalZ, subShapeIndex, shapeId)
    local vehicle = HomeSpots.getVehicleFromNode(hitObjectId) or HomeSpots.getVehicleFromNode(shapeId)
    if vehicle ~= nil then
        HomeSpots.lookRayVehicle = vehicle
        return false
    end

    return true
end
