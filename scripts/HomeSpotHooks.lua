---Hooks: connect Home Spots to the game's loading, saving and menus, once every part of it is loaded.

PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, HomeSpots.registerGlobalActionEvents)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, HomeSpots.onMissionLoaded)
FSBaseMission.onConnectionFinishedLoading = Utils.appendedFunction(FSBaseMission.onConnectionFinishedLoading, HomeSpots.onClientJoined)
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, HomeSpots.onSaveCareer)
InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, HomeSpots.onSettingsFrameOpen)
FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, HomeSpots.onMissionDeleted)

addModEventListener(HomeSpots)
