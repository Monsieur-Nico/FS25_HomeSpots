---Input: the keys and their prompts, in the vehicle and on foot.


---Action: save the current position of the targeted vehicles as their home spots,
-- after asking when it overlaps the home spot of another vehicle
function HomeSpots:onSetHomeInput()
    local vehicles = HomeSpots.getTargetVehicles()
    local overlapped = HomeSpots.getVehiclesWithOverlappingSpot(vehicles)

    if #overlapped == 0 then
        HomeSpots.request(HomeSpots.ACTION_SET, vehicles)
        return
    end

    YesNoDialog.show(HomeSpots.onSetOverlapAnswered, HomeSpots,
        HomeSpots.getText("homeSpots_overlapQuestion", HomeSpots.getVehicleNames(overlapped, HomeSpots.MAX_NAMES_LISTED)),
        nil, nil, nil, nil, nil, nil, vehicles)
end


---The player answered the question about a spot that overlaps another
-- @param boolean isYes true to save the spot anyway
-- @param table vehicles vehicles to save the spot of
function HomeSpots:onSetOverlapAnswered(isYes, vehicles)
    if isYes then
        HomeSpots.request(HomeSpots.ACTION_SET, vehicles)
    end
end


---Returns the vehicles, sorted by name, whose saved home spot the given vehicles stand on.
-- The given vehicles' own spots are left out: saving replaces them.
-- @param table vehicles vehicles about to get a home spot where they stand
-- @return table overlapped vehicles whose home spot would overlap
function HomeSpots.getVehiclesWithOverlappingSpot(vehicles)
    local isTarget = {}
    local areas = {}
    for _, vehicle in ipairs(vehicles) do
        isTarget[vehicle] = true
        table.insert(areas, HomeSpotArea.newFromNode(vehicle.size, vehicle.rootNode))
    end

    local overlapped = {}
    for vehicle, spotArea in pairs(HomeSpotNearby.getSpotAreas()) do
        if not isTarget[vehicle] and HomeSpotArea.getOverlapsAny(spotArea, areas) then
            table.insert(overlapped, vehicle)
        end
    end

    table.sort(overlapped, function(a, b) return a:getFullName() < b:getFullName() end)

    return overlapped
end


---Action: delete the home spots of the targeted vehicles
function HomeSpots:onClearHomeInput()
    HomeSpots.request(HomeSpots.ACTION_CLEAR, HomeSpots.getTargetVehicles())
end


---Action: send every vehicle and tool of the player's farm home
function HomeSpots:onSendAllHomeInput()
    HomeSpots.request(HomeSpots.ACTION_SEND_ALL, {})
end


---Action: send only what the player sits in or looks at home
function HomeSpots:onSendTargetHomeInput()
    HomeSpots.request(HomeSpots.ACTION_SEND, HomeSpots.getTargetVehicles())
end


---Action: give what the player sits in or looks at a home spot in a shed, and send it there
function HomeSpots:onFindShedInput()
    HomeSpots.request(HomeSpots.ACTION_FIND_SHED, HomeSpots.getTargetVehicles())
end


---Keep the help entries in line with what the player sits in or looks at:
-- "Set" and "Park in a shed" only show with a target, "Set" reads "Update" once it has a home spot,
-- "Send home" and "Remove" only show when the target has a home spot.
-- The game keeps separate keys on foot and in a vehicle, so every context is kept up to date.
function HomeSpots.updateActionEvents()
    if next(HomeSpots.actionEventIds) == nil then
        return
    end

    local vehicles = HomeSpots.getTargetVehicles()
    local vehiclesWithSpot = {}
    for _, vehicle in ipairs(vehicles) do
        if HomeSpots.store:has(vehicle) then
            table.insert(vehiclesWithSpot, vehicle)
        end
    end

    local hasTarget = #vehicles > 0
    local hasSpot = #vehiclesWithSpot > 0
    local setText = HomeSpots.getText(hasSpot and "homeSpots_updateFor" or "homeSpots_setFor", HomeSpots.getVehicleNames(vehicles, HomeSpots.MAX_NAMES_IN_PROMPT))
    local spotNames = HomeSpots.getVehicleNames(vehiclesWithSpot, HomeSpots.MAX_NAMES_IN_PROMPT)
    local clearText = HomeSpots.getText("homeSpots_clearFor", spotNames)
    local sendText = HomeSpots.getText("homeSpots_sendHomeFor", spotNames)
    local shedText = HomeSpots.getText("homeSpots_findShedFor", HomeSpots.getVehicleNames(vehicles, HomeSpots.MAX_NAMES_IN_PROMPT))

    local state = table.concat({tostring(hasTarget), setText, clearText, sendText, shedText}, "|")
    if state == HomeSpots.shownActionState then
        return
    end

    HomeSpots.shownActionState = state
    for _, eventIds in pairs(HomeSpots.actionEventIds) do
        HomeSpots.setActionEventState(eventIds.HOMESPOTS_SET, hasTarget, setText)
        HomeSpots.setActionEventState(eventIds.HOMESPOTS_CLEAR, hasSpot, clearText)
        HomeSpots.setActionEventState(eventIds.HOMESPOTS_SEND_ONE, hasSpot, sendText)
        HomeSpots.setActionEventState(eventIds.HOMESPOTS_FIND_SHED, hasTarget, shedText)
    end
end


---Show or hide one help entry and set its text
-- @param string eventId action event id, or nil when it was not registered
-- @param boolean isActive whether the entry is shown
-- @param string text help text
function HomeSpots.setActionEventState(eventId, isActive, text)
    if eventId ~= nil then
        g_inputBinding:setActionEventText(eventId, text)
        g_inputBinding:setActionEventActive(eventId, isActive)
    end
end


---Register an action event and show it in the help panel at the top left of the screen
-- @param table target object the key is registered for, one per input context
-- @param table eventIds event ids of the input context being registered, the new id is added to it
-- @param string actionName input action name
-- @param function callback callback
function HomeSpots.registerActionEvent(target, eventIds, actionName, callback)
    local _, eventId = g_inputBinding:registerActionEvent(InputAction[actionName], target, callback, false, true, false, true)
    if eventId == nil or eventId == "" then
        return
    end

    eventIds[actionName] = eventId
    g_inputBinding:setActionEventText(eventId, g_i18n:getText("input_" .. actionName))
    g_inputBinding:setActionEventTextVisibility(eventId, true)
    g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_NORMAL)
end


---Remove keys registered earlier in the same input context, so re-registering never leaves a second copy behind
-- @param table eventIds action name to event id, or nil
function HomeSpots.removeActionEvents(eventIds)
    for _, eventId in pairs(eventIds or {}) do
        g_inputBinding:removeActionEvent(eventId)
    end
end


---Register all of the mod's keys. Called by the game on foot and in a vehicle, in the middle of registering the player's own keys,
-- and again whenever those are refreshed (getting in or out, hitching or unhitching a tool).
-- @param table inputComponent player input component
-- @param string contextName input context name, nil on foot
function HomeSpots.registerGlobalActionEvents(inputComponent, contextName)
    local contextKey = contextName or HomeSpots.DEFAULT_INPUT_CONTEXT
    HomeSpots.removeActionEvents(HomeSpots.actionEventIds[contextKey])

    local target = HomeSpots.inputTargets[contextKey] or {}
    HomeSpots.inputTargets[contextKey] = target

    local eventIds = {}
    HomeSpots.actionEventIds[contextKey] = eventIds

    HomeSpots.registerActionEvent(target, eventIds, "HOMESPOTS_SEND_ALL", HomeSpots.onSendAllHomeInput)
    HomeSpots.registerActionEvent(target, eventIds, "HOMESPOTS_SEND_ONE", HomeSpots.onSendTargetHomeInput)
    HomeSpots.registerActionEvent(target, eventIds, "HOMESPOTS_SET", HomeSpots.onSetHomeInput)
    HomeSpots.registerActionEvent(target, eventIds, "HOMESPOTS_CLEAR", HomeSpots.onClearHomeInput)
    HomeSpots.registerActionEvent(target, eventIds, "HOMESPOTS_FIND_SHED", HomeSpots.onFindShedInput)

    HomeSpots.shownActionState = nil
end
