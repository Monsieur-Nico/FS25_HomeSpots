---Ground footprint of a vehicle as a rotated rectangle, used to tell whether a home spot is taken.
HomeSpotArea = {}

-- Rectangles may overlap by this much (in m) before they count as touching, so vehicles parked side by side still fit
HomeSpotArea.TOLERANCE = 0.25


---Create a footprint from a vehicle's size values and the pose of its root node
-- @param table size vehicle size (width, length, widthOffset, lengthOffset)
-- @param float x root node world x
-- @param float z root node world z
-- @param float dirX, dirZ world direction of the root node's z axis
-- @param float sideX, sideZ world direction of the root node's x axis
-- @return table area footprint
function HomeSpotArea.new(size, x, z, dirX, dirZ, sideX, sideZ)
    local widthOffset = size.widthOffset or 0
    local lengthOffset = size.lengthOffset or 0

    return {
        x = x + dirX * lengthOffset + sideX * widthOffset,
        z = z + dirZ * lengthOffset + sideZ * widthOffset,
        dirX = dirX,
        dirZ = dirZ,
        sideX = sideX,
        sideZ = sideZ,
        halfLength = size.length * 0.5,
        halfWidth = size.width * 0.5
    }
end


---Create a footprint from a node's current world position and rotation
-- @param table size vehicle size
-- @param integer node node (a vehicle's root node, or a helper node posed like it)
-- @return table area footprint
function HomeSpotArea.newFromNode(size, node)
    local x, _, z = getWorldTranslation(node)
    local dirX, _, dirZ = localDirectionToWorld(node, 0, 0, 1)
    local sideX, _, sideZ = localDirectionToWorld(node, 1, 0, 0)

    return HomeSpotArea.new(size, x, z, dirX, dirZ, sideX, sideZ)
end


---Returns true if two footprints stand in about the same place, facing about the same way
-- @param table a footprint
-- @param table b footprint
-- @param float maxDistance largest distance between the centres (m)
-- @param float maxAngle largest difference in heading (rad)
-- @return boolean isSamePose
function HomeSpotArea.getIsSamePose(a, b, maxDistance, maxAngle)
    local dx, dz = b.x - a.x, b.z - a.z
    if dx * dx + dz * dz > maxDistance * maxDistance then
        return false
    end

    return a.dirX * b.dirX + a.dirZ * b.dirZ >= math.cos(maxAngle)
end


---Half of the area's extent when projected onto an axis
-- @param table area footprint
-- @param float axisX, axisZ unit axis
-- @return float radius
local function getProjectedRadius(area, axisX, axisZ)
    return math.abs(area.dirX * axisX + area.dirZ * axisZ) * area.halfLength
        + math.abs(area.sideX * axisX + area.sideZ * axisZ) * area.halfWidth
end


---Returns true if two footprints overlap by more than the tolerance (separating axis test)
-- @param table a footprint
-- @param table b footprint
-- @return boolean overlaps
function HomeSpotArea.getOverlaps(a, b)
    local dx, dz = b.x - a.x, b.z - a.z
    local axes = {
        {a.dirX, a.dirZ}, {a.sideX, a.sideZ},
        {b.dirX, b.dirZ}, {b.sideX, b.sideZ}
    }

    for _, axis in ipairs(axes) do
        local distance = math.abs(dx * axis[1] + dz * axis[2])
        local reach = getProjectedRadius(a, axis[1], axis[2]) + getProjectedRadius(b, axis[1], axis[2])

        if distance >= reach - HomeSpotArea.TOLERANCE then
            return false
        end
    end

    return true
end


---Returns true if the footprint overlaps any footprint in the list
-- @param table area footprint
-- @param table others list of footprints
-- @return boolean overlaps
function HomeSpotArea.getOverlapsAny(area, others)
    for _, other in ipairs(others) do
        if HomeSpotArea.getOverlaps(area, other) then
            return true
        end
    end

    return false
end


---Returns true if a ground point lies inside the footprint, grown by a margin on every side
-- @param table area footprint
-- @param float x world x
-- @param float z world z
-- @param float margin extra room (m)
-- @return boolean containsPoint
function HomeSpotArea.getContainsPoint(area, x, z, margin)
    local dx, dz = x - area.x, z - area.z
    local along = dx * area.dirX + dz * area.dirZ
    local side = dx * area.sideX + dz * area.sideZ

    return math.abs(along) <= area.halfLength + margin and math.abs(side) <= area.halfWidth + margin
end
