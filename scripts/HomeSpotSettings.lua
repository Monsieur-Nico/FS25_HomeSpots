---Adds the "send vehicles home automatically" option to the in-game settings page
HomeSpotSettings = {}
HomeSpotSettings.optionElement = nil
HomeSpotSettings.injectedLayout = nil


---Returns the texts of the time option: "Off", then every hour of the day
-- @return table texts
function HomeSpotSettings.getOptionTexts()
    local texts = {g_i18n:getText("homeSpots_off")}

    for hour = 0, 23 do
        table.insert(texts, string.format("%02d:00", hour))
    end

    return texts
end


---Option state (1 = off, 2 = 00:00 ... 25 = 23:00) for an hour
-- @param integer hour hour or HomeSpotStore.AUTO_TIDY_OFF
-- @return integer state
function HomeSpotSettings.getStateFromHour(hour)
    if hour == nil or hour < 0 then
        return 1
    end

    return hour + 2
end


---Hour for an option state
-- @param integer state option state
-- @return integer hour hour or HomeSpotStore.AUTO_TIDY_OFF
function HomeSpotSettings.getHourFromState(state)
    if state <= 1 then
        return HomeSpotStore.AUTO_TIDY_OFF
    end

    return state - 2
end


---Returns true for a multi text option with free choice of texts (not an on/off toggle)
-- @param table element gui element
-- @return boolean isMultiTextOption
local function isMultiTextOption(element)
    return element:isa(MultiTextOptionElement) and not element:isa(BinaryOptionElement)
end


---Find a settings row holding a multi text option, to copy its look.
-- The time scale row is used when present, as it is known to be a multi text option.
-- @param table settingsFrame in-game menu settings frame
-- @param table layout settings layout
-- @return table row
local function findOptionRowTemplate(settingsFrame, layout)
    local timeScaleOption = settingsFrame.multiTimeScale
    if timeScaleOption ~= nil and timeScaleOption.parent ~= nil and isMultiTextOption(timeScaleOption) then
        return timeScaleOption.parent
    end

    for _, row in ipairs(layout.elements) do
        for _, child in ipairs(row.elements or {}) do
            if isMultiTextOption(child) then
                return row
            end
        end
    end

    return nil
end


---Find the first section header of the settings layout, to copy its look
-- @param table layout settings layout
-- @return table header
local function findSectionHeaderTemplate(layout)
    for _, element in ipairs(layout.elements) do
        if element.name == "sectionHeader" then
            return element
        end
    end

    return nil
end


---Add the option to the settings page (once per settings layout)
-- @param table settingsFrame in-game menu settings frame
function HomeSpotSettings.inject(settingsFrame)
    local layout = settingsFrame.generalSettingsLayout or settingsFrame.gameSettingsLayout
    if layout == nil then
        Logging.warning("Home Spots: settings layout not found, the automatic send-home option is not shown")
        return
    end

    if layout == HomeSpotSettings.injectedLayout then
        HomeSpotSettings.refresh()
        return
    end

    local rowTemplate = findOptionRowTemplate(settingsFrame, layout)
    if rowTemplate == nil then
        Logging.warning("Home Spots: no settings row to copy, the automatic send-home option is not shown")
        return
    end

    local headerTemplate = findSectionHeaderTemplate(layout)
    if headerTemplate ~= nil then
        local header = headerTemplate:clone(layout)
        header.id = nil
        header:setText(g_i18n:getText("homeSpots_settingsSection"))
    end

    local row = rowTemplate:clone(layout)
    row.id = nil

    local tooltip = g_i18n:getText("homeSpots_autoTidy_tooltip")
    for _, child in ipairs(row.elements) do
        child.id = nil

        if isMultiTextOption(child) then
            child.target = HomeSpotSettings
            child.onClickCallback = HomeSpotSettings.onAutoTidyChanged
            child:setTexts(HomeSpotSettings.getOptionTexts())
            child:setDisabled(false)

            local tooltipElement = child.elements[1]
            if tooltipElement ~= nil and tooltipElement:isa(TextElement) then
                tooltipElement:setText(tooltip)
            end

            HomeSpotSettings.optionElement = child
        elseif child:isa(TextElement) then
            child:setText(g_i18n:getText("homeSpots_autoTidy"))
        end
    end

    row:reloadFocusHandling(true)

    HomeSpotSettings.injectedLayout = layout
    layout:invalidateLayout()
    HomeSpotSettings.refresh()
end


---Called when the player picks another time
-- @param integer state option state
function HomeSpotSettings:onAutoTidyChanged(state)
    HomeSpots.store.autoTidyHour = HomeSpotSettings.getHourFromState(state)
end


---Show the current value of the setting
function HomeSpotSettings.refresh()
    if HomeSpotSettings.optionElement ~= nil then
        HomeSpotSettings.optionElement:setState(HomeSpotSettings.getStateFromHour(HomeSpots.store.autoTidyHour), false)
    end
end

