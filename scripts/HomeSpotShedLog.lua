---Shed log: what the finder found out about the rooms and the machines in them, for log.txt.
-- One line per machine is always written; the rest only when the "Detailed log" setting is on.


---Returns true when the detailed log is switched on in the settings
-- @return boolean isDetailed
function HomeSpotShed.getIsDetailed()
    return HomeSpots.store.detailLog == HomeSpotStore.LOG_ON
end


---Write what was found out about a room to the log, and a map of the squares under a roof when only some are
-- @param table room room with its grid and bounds
function HomeSpotShed.logRoom(room)
    if not HomeSpotShed.getIsDetailed() then
        return
    end

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


---Write down which machines and spots stand in a room, where the finder counts them, along its first facing
-- @param table room room with its facings
-- @param table taken footprints
function HomeSpotShed.logTaken(room, taken)
    local facing = room.facings[1]
    if facing == nil or not HomeSpotShed.getIsDetailed() then
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
    if trace == nil then
        return
    end

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
