-- Luacheck settings for the Home Spots mod (FS25 runs Lua 5.1)
std = "lua51"
max_line_length = 180
unused_args = false

-- Classes this mod defines
globals = {
    "HomeSpots",
    "HomeSpotArea",
    "HomeSpotHotspot",
    "HomeSpotMapMenu",
    "HomeSpotSettings",
    "HomeSpotStore",

    -- Base game classes the mod hooks into
    "FSBaseMission",
    "FSCareerMissionInfo",
    "InGameMenuMapFrame",
    "InGameMenuSettingsFrame",
    "Mission00",
    "PlayerInputComponent",
}

-- Base game and engine API used by the mod
read_globals = {
    "BinaryOptionElement",
    "Class",
    "CollisionFlag",
    "GS_PRIO_NORMAL",
    "InGameMenuMapUtil",
    "InputAction",
    "Logging",
    "MapHotspot",
    "MessageType",
    "MultiTextOptionElement",
    "Overlay",
    "TextElement",
    "Utils",
    "addModEventListener",
    "createTransformGroup",
    "createXMLFile",
    "delete",
    "entityExists",
    "fileExists",
    "g_currentMission",
    "g_currentModDirectory",
    "g_currentModName",
    "g_i18n",
    "g_inputBinding",
    "g_localPlayer",
    "g_messageCenter",
    "getNormalizedScreenValues",
    "getParent",
    "getWorldRotation",
    "getWorldTranslation",
    "getXMLInt",
    "getXMLString",
    "hasXMLProperty",
    "loadXMLFile",
    "localDirectionToWorld",
    "raycastAll",
    "saveXMLFile",
    "setRotation",
    "setTranslation",
    "setXMLInt",
    "setXMLString",
}

-- The tests replace the game with stand-ins, so they may define any global
files["tests/"] = {
    allow_defined_top = true,
    globals = {"lookRay"},
    read_globals = {},
    ignore = {"111", "112", "113", "121", "122", "131", "142", "143"},
}
