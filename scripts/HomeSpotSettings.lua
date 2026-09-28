---Adds the Home Spots section to the in-game settings page: the daily send-home time and how map markers show
HomeSpotSettings = {}
HomeSpotSettings.injectedLayout = nil


---Returns an hour of the day as a clock time, e.g. "20:00"
-- @param integer hour hour
-- @return string text
function HomeSpotSettings.formatHour(hour)
    return string.format("%02d:00", hour)
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


-- The options, in the order they are listed. Each one knows its texts and how to read and write its value.
HomeSpotSettings.OPTIONS = {
    {
        textName = "homeSpots_autoTidy",
        tooltipName = "homeSpots_autoTidy_tooltip",
        getTexts = function()
            local texts = {g_i18n:getText("homeSpots_off")}
            for hour = 0, 23 do
                table.insert(texts, HomeSpotSettings.formatHour(hour))
            end
            return texts
        end,
        getState = function()
            return HomeSpotSettings.getStateFromHour(HomeSpots.store.autoTidyHour)
        end,
        setState = function(state)
            HomeSpots.store.autoTidyHour = HomeSpotSettings.getHourFromState(state)
        end
    },
    {
        textName = "homeSpots_markers",
        tooltipName = "homeSpots_markers_tooltip",
        getTexts = function()
            return {
                g_i18n:getText("homeSpots_markersAway"),
                g_i18n:getText("homeSpots_markersAlways"),
                g_i18n:getText("homeSpots_off")
            }
        end,
        getState = function()
            return HomeSpots.store.markerMode
        end,
        setState = function(state)
            HomeSpots.store.markerMode = state
        end
    }
}


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


---Add one option row, copied from the template row
-- @param table layout settings layout
-- @param table rowTemplate row to copy
-- @param table option option definition from HomeSpotSettings.OPTIONS
local function addOptionRow(layout, rowTemplate, option)
    local row = rowTemplate:clone(layout)
    row.id = nil

    for _, child in ipairs(row.elements) do
        child.id = nil

        if isMultiTextOption(child) then
            child.target = option
            child.onClickCallback = HomeSpotSettings.onOptionChanged
            child:setTexts(option.getTexts())
            child:setDisabled(false)

            local tooltipElement = child.elements[1]
            if tooltipElement ~= nil and tooltipElement:isa(TextElement) then
                tooltipElement:setText(g_i18n:getText(option.tooltipName))
            end

            option.element = child
        elseif child:isa(TextElement) then
            child:setText(g_i18n:getText(option.textName))
        end
    end

    row:reloadFocusHandling(true)
end


---Add the Home Spots section to the settings page (once per settings layout)
-- @param table settingsFrame in-game menu settings frame
function HomeSpotSettings.inject(settingsFrame)
    local layout = settingsFrame.generalSettingsLayout or settingsFrame.gameSettingsLayout
    if layout == nil then
        Logging.warning("Home Spots: settings layout not found, the Home Spots settings are not shown")
        return
    end

    if layout == HomeSpotSettings.injectedLayout then
        HomeSpotSettings.refresh()
        return
    end

    local rowTemplate = findOptionRowTemplate(settingsFrame, layout)
    if rowTemplate == nil then
        Logging.warning("Home Spots: no settings row to copy, the Home Spots settings are not shown")
        return
    end

    local headerTemplate = findSectionHeaderTemplate(layout)
    if headerTemplate ~= nil then
        local header = headerTemplate:clone(layout)
        header.id = nil
        header:setText(g_i18n:getText("homeSpots_settingsSection"))
    end

    for _, option in ipairs(HomeSpotSettings.OPTIONS) do
        addOptionRow(layout, rowTemplate, option)
    end

    HomeSpotSettings.injectedLayout = layout
    layout:invalidateLayout()
    HomeSpotSettings.refresh()
end


---Called when the player picks another value
-- @param table option option definition the changed element belongs to
-- @param integer state option state
function HomeSpotSettings.onOptionChanged(option, state)
    option.setState(state)
end


---Show the current value of every option
function HomeSpotSettings.refresh()
    for _, option in ipairs(HomeSpotSettings.OPTIONS) do
        if option.element ~= nil then
            option.element:setState(option.getState(), false)
        end
    end
end
