---Reports: tell the players what a request did.


---Create an empty report
-- @param integer kind HomeSpots.REPORT_*
-- @return table report kind, vehicles (saved, removed or moved), atHome, blocked, nearby (moved to a space beside their taken spot),
--   numBusy, isAutomatic, isTargeted, fees (farm id to the realism fee paid, or asked for when the farm could not pay)
function HomeSpots.newReport(kind)
    return {kind = kind, vehicles = {}, atHome = {}, blocked = {}, nearby = {}, numBusy = 0, isAutomatic = false, isTargeted = false, fees = {}}
end


---Server: tell the player who asked what happened. The daily send-home is told to every player.
-- @param table report report
-- @param table connection connection of the player who asked, nil for the local player
function HomeSpots.deliverReport(report, connection)
    if report.isAutomatic then
        HomeSpots.broadcast(HomeSpotReportEvent.new(report))
        HomeSpots.showReport(report)
    elseif connection ~= nil then
        connection:sendEvent(HomeSpotReportEvent.new(report))
    else
        HomeSpots.showReport(report)
    end
end


---Show a report as an in-game notification
-- @param table report report
function HomeSpots.showReport(report)
    local names = function(vehicles)
        return HomeSpots.getVehicleNames(vehicles, HomeSpots.MAX_NAMES_LISTED)
    end

    if report.kind == HomeSpots.REPORT_SAVED then
        HomeSpots.notify(HomeSpots.getText("homeSpots_saved", names(report.vehicles)))
        return
    elseif report.kind == HomeSpots.REPORT_CLEARED then
        HomeSpots.notify(HomeSpots.getText("homeSpots_cleared", names(report.vehicles)))
        return
    elseif report.kind == HomeSpots.REPORT_NOTHING then
        HomeSpots.notify(HomeSpots.getText("homeSpots_none"))
        return
    elseif report.kind == HomeSpots.REPORT_NO_SHED then
        HomeSpots.notify(HomeSpots.getText("homeSpots_noShedRoom"), FSBaseMission.INGAME_NOTIFICATION_INFO)
        return
    elseif report.kind == HomeSpots.REPORT_SHED_SAVED then
        local text = HomeSpots.getText("homeSpots_shedSaved", names(report.vehicles))
        if #report.blocked > 0 then
            text = text .. ". " .. HomeSpots.getText("homeSpots_noShedRoomFor", names(report.blocked))
        end
        HomeSpots.notify(text, #report.blocked > 0 and FSBaseMission.INGAME_NOTIFICATION_INFO or nil)
        return
    end

    local fee = report.fees[g_currentMission:getFarmId()]
    if report.kind == HomeSpots.REPORT_NO_MONEY then
        HomeSpots.notify(HomeSpots.getText("homeSpots_noMoney", g_i18n:formatMoney(fee, 0, true, true)), FSBaseMission.INGAME_NOTIFICATION_INFO)
        return
    end

    local moved = report.vehicles
    local parts = {}
    if report.isTargeted then
        if #moved > 0 then
            table.insert(parts, HomeSpots.getText("homeSpots_sentHomeFor", names(moved)))
        end
        if #report.atHome > 0 then
            table.insert(parts, HomeSpots.getText("homeSpots_alreadyHomeFor", names(report.atHome)))
        end
    else
        if #moved > 0 or #report.atHome == 0 then
            table.insert(parts, HomeSpots.getText("homeSpots_sentHome", #moved))
        end
        if #report.atHome > 0 then
            local isAllHome = #moved == 0 and report.numBusy == 0 and #report.blocked == 0
            table.insert(parts, isAllHome and HomeSpots.getText("homeSpots_allHome") or HomeSpots.getText("homeSpots_alreadyHome", #report.atHome))
        end
    end
    if report.numBusy > 0 then
        table.insert(parts, HomeSpots.getText("homeSpots_inUse", report.numBusy))
    end
    if #report.nearby > 0 then
        table.insert(parts, HomeSpots.getText("homeSpots_parkedBeside", names(report.nearby)))
    end
    if #report.blocked > 0 then
        table.insert(parts, HomeSpots.getText("homeSpots_blocked", names(report.blocked)))
    end
    if fee ~= nil then
        table.insert(parts, HomeSpots.getText("homeSpots_feePaid", g_i18n:formatMoney(fee, 0, true, true)))
    end

    local text = table.concat(parts, ". ")
    if report.isAutomatic then
        text = HomeSpots.getText("homeSpots_autoTidyPrefix") .. " " .. text
    end

    HomeSpots.notify(text, #report.blocked > 0 and FSBaseMission.INGAME_NOTIFICATION_INFO or nil)
end
