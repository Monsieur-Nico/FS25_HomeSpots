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
-- Most places tried per machine, taken or not, so a huge shed with a crowd of machines never stalls the game
HomeSpotShed.MAX_PLACES_TRIED = 30000
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
