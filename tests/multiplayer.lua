-- Multiplayer: a host playing on farm 1, a player on farm 2 and a server admin on farm 1, each on their own machine
return function(test, assertEquals, network)
    local host = network.newMachine()
    local hostGame, hostMod = host.game, host.HomeSpots
    local HomeSpotStore = host.env.HomeSpotStore

    local tractor = hostGame.newVehicle("t1", "Fendt", 10, 0)
    local trailer = hostGame.newVehicle("x1", "Trailer", 30, 0)
    local combine = hostGame.newVehicle("k1", "Claas", 60, 0)
    combine.farmId = 2

    host.env.g_currentMission.missionInfo = {savegameDirectory = "/mp"}
    hostMod.onMissionLoaded(host.env.g_currentMission)
    hostGame.currentVehicle = tractor
    hostMod:onSetHomeInput()
    hostGame.currentVehicle = nil
    hostMod.store:set(trailer)
    hostMod.changeSettings({autoTidyHour = 20, markerMode = HomeSpotStore.MARKERS_ALWAYS})

    local player = network.newMachine()
    local playerGame, playerMod = player.game, player.HomeSpots
    local playerCopies = network.copyVehicles(host, player)
    local toPlayer = network.connect(host, player, 2, 2, false)

    local admin = network.newMachine()
    local adminCopies = network.copyVehicles(host, admin)
    local toAdmin = network.connect(host, admin, 3, 1, true)

    -- Deliver what is on its way, let the host carry out queued moves, then deliver the reports
    local function step()
        network.deliver()
        hostMod:update(16)
        network.deliver()
    end

    local function getX(vehicle)
        return (hostGame.getPosition(vehicle))
    end

    test("multiplayer: a joining player gets the settings and every home spot", function()
        playerMod.onMissionLoaded(player.env.g_currentMission)
        network.finishJoining(host, toPlayer)
        network.deliver()

        assert(playerMod.store:has(playerCopies[tractor]), "tractor spot")
        assert(playerMod.store:has(playerCopies[trailer]), "trailer spot")
        assertEquals(playerMod.store.autoTidyHour, 20, "tidy-up hour")
        assertEquals(playerMod.store.markerMode, HomeSpotStore.MARKERS_ALWAYS, "marker setting")
        assertEquals(playerGame.countMapHotspots(), 2, "map markers")
        assertEquals(playerMod.hotspots[tractor.objectId]:getName(), "Home: Fendt", "marker name")
    end)

    test("multiplayer: spots sent before the player's game finished loading are kept", function()
        network.finishJoining(host, toAdmin)
        network.deliver()
        assert(admin.HomeSpots.store:has(adminCopies[tractor]), "tractor spot while still loading")
        admin.HomeSpots.onMissionLoaded(admin.env.g_currentMission)

        assert(admin.HomeSpots.store:has(adminCopies[tractor]), "tractor spot")
        assertEquals(admin.game.countMapHotspots(), 2, "map markers")
        assert(admin.HomeSpots.hotspots[tractor.objectId]:getIsVisible(), "marker shows")
    end)

    test("multiplayer: a player sets a spot from their seat and every player sees it", function()
        combine.isControlled, combine.ownerConnection = true, toPlayer
        playerGame.currentVehicle = playerCopies[combine]
        playerMod:onSetHomeInput()
        step()

        assert(hostMod.store:has(combine), "saved on the host")
        assert(playerMod.store:has(playerCopies[combine]), "player knows it")
        assert(admin.HomeSpots.store:has(adminCopies[combine]), "other players know it")
        assertEquals(playerGame.lastNotification(), "saved Claas", "player is told")
        assertEquals(hostGame.lastNotification(), "saved Fendt", "host is not told")
        assertEquals(playerGame.countMapHotspots(), 3, "player's map markers")
    end)

    test("multiplayer: a player cannot change another farm's spots", function()
        hostGame.place(tractor, 400, 0)
        playerMod.request(playerMod.ACTION_SET, {playerCopies[tractor]})
        playerMod.request(playerMod.ACTION_CLEAR, {playerCopies[trailer]})
        playerMod.request(playerMod.ACTION_SEND, {playerCopies[tractor]})
        step()

        assertEquals(hostMod.store:get(tractor)[1][1][1], 10, "tractor spot unchanged")
        assert(hostMod.store:has(trailer), "trailer spot kept")
        assertEquals(getX(tractor), 400, "tractor not moved")
        assertEquals(playerGame.lastNotification(), "saved Claas", "nothing to tell")
        hostGame.place(tractor, 10, 0)
    end)

    test("multiplayer: send all home from a player moves only their farm's vehicles", function()
        combine.isControlled = false
        playerGame.currentVehicle = nil
        hostGame.place(combine, 300, 0)
        hostGame.place(tractor, 400, 0)
        playerMod:onSendAllHomeInput()
        step()

        assertEquals(getX(combine), 60, "combine home")
        assertEquals(getX(tractor), 400, "host's tractor stays")
        assertEquals(playerGame.lastNotification(), "sent 1", "player is told")
        hostGame.place(tractor, 10, 0)
    end)

    test("multiplayer: send this one home works for the player sitting in it", function()
        combine.isControlled, combine.ownerConnection = true, toPlayer
        playerGame.currentVehicle = playerCopies[combine]
        hostGame.place(combine, 300, 0)
        playerMod:onSendTargetHomeInput()
        step()

        assertEquals(getX(combine), 60, "combine home")
        assertEquals(playerGame.lastNotification(), "sent: Claas")
        combine.isControlled = false
        playerGame.currentVehicle = nil
    end)

    test("multiplayer: a vehicle another player drives stays put", function()
        tractor.isControlled, tractor.ownerConnection = true, toAdmin
        hostGame.place(tractor, 400, 0)
        hostGame.collisionHitNode = tractor.rootNode
        hostMod:onSendTargetHomeInput()
        step()

        assertEquals(getX(tractor), 400, "tractor stays")
        assertEquals(hostGame.lastNotification(), "inuse 1", "host is told")

        tractor.isControlled, tractor.ownerConnection = false, nil
        hostGame.collisionHitNode = nil
        hostGame.place(tractor, 10, 0)
    end)

    test("multiplayer: Send home on a player's map asks the host", function()
        hostGame.place(combine, 300, 0)
        network.syncPositions(host, player)
        local frame = player.env.InGameMenuMapFrame.newFrame({})
        frame:setMapSelectionItem({vehicle = playerCopies[combine]})
        assertEquals(table.concat(frame.shownActions, ","), "Send home", "offered while away")

        frame.homeSpotsAction.callback()
        step()
        assertEquals(getX(combine), 60, "combine home")
        assertEquals(playerGame.lastNotification(), "sent: Claas")

        network.syncPositions(host, player)
        frame:setMapSelectionItem(frame.currentHotspot)
        assertEquals(#frame.shownActions, 0, "gone once home")
    end)

    test("multiplayer: only the host or an admin can change the settings", function()
        local function newOptionElement()
            return {setTexts = function() end, setState = function() end, setDisabled = function(self, isDisabled) self.isDisabled = isDisabled end}
        end

        player.env.HomeSpotSettings.OPTIONS[1].element = newOptionElement()
        player.env.HomeSpotSettings.refresh()
        assertEquals(player.env.HomeSpotSettings.OPTIONS[1].element.isDisabled, true, "locked for a player")

        admin.env.HomeSpotSettings.OPTIONS[1].element = newOptionElement()
        admin.env.HomeSpotSettings.refresh()
        assertEquals(admin.env.HomeSpotSettings.OPTIONS[1].element.isDisabled, false, "open for an admin")

        playerMod.changeSettings({autoTidyHour = 5, markerMode = HomeSpotStore.MARKERS_OFF})
        network.deliver()
        assertEquals(hostMod.store.autoTidyHour, 20, "host ignores a player")
        assertEquals(playerMod.store.autoTidyHour, 20, "player's page is put back")
        assertEquals(playerMod.store.markerMode, HomeSpotStore.MARKERS_ALWAYS, "player's marker setting is put back")

        admin.HomeSpots.changeSettings({autoTidyHour = 5, markerMode = HomeSpotStore.MARKERS_AWAY})
        network.deliver()
        assertEquals(hostMod.store.autoTidyHour, 5, "host takes an admin's change")
        assertEquals(playerMod.store.autoTidyHour, 5, "every player gets it")
        assertEquals(playerMod.store.markerMode, HomeSpotStore.MARKERS_AWAY, "marker setting too")

        hostMod.changeSettings({autoTidyHour = 20, markerMode = HomeSpotStore.MARKERS_ALWAYS})
        network.deliver()
        assertEquals(admin.HomeSpots.store.autoTidyHour, 20, "host's change reaches everyone")
    end)

    test("multiplayer: the realism fee is paid by the player's farm on the host, and the player sees the price", function()
        hostMod.changeSettings({feeLevel = HomeSpotStore.FEE_NORMAL})
        network.deliver()
        assertEquals(playerMod.store.feeLevel, HomeSpotStore.FEE_NORMAL, "player gets the fee setting")

        local hostBalance, playerBalance = hostGame.balances[1], hostGame.balances[2]
        hostGame.place(combine, 1060, 0)
        playerMod:onSendAllHomeInput()
        step()
        assertEquals(getX(combine), 60, "combine home")
        assertEquals(playerBalance - hostGame.balances[2], 50, "1 km at 50 from the player's farm")
        assertEquals(hostGame.balances[1], hostBalance, "host's farm pays nothing")
        assertEquals(playerGame.lastNotification(), "sent 1. cost $50", "player is told the price")

        hostGame.balances[2] = 10
        hostGame.place(combine, 1060, 0)
        playerMod:onSendAllHomeInput()
        step()
        assertEquals(getX(combine), 1060, "stays without the money")
        assertEquals(playerGame.lastNotification(), "no money $50", "player is told why")

        hostGame.balances[2] = playerBalance
        hostGame.place(combine, 60, 0)
        hostMod.changeSettings({feeLevel = HomeSpotStore.FEE_OFF})
        network.deliver()
    end)

    test("multiplayer: the daily send-home moves every farm's vehicles and tells everyone", function()
        playerGame.fireHourChanged(19)
        assertEquals(playerGame.lastNotification(), "soon 20:00", "heads-up for the player")

        hostGame.place(tractor, 400, 0)
        hostGame.place(combine, 300, 0)
        playerGame.fireHourChanged(20)
        step()
        assertEquals(getX(combine), 300, "a player's clock moves nothing")

        hostGame.fireHourChanged(20)
        step()
        assertEquals(getX(tractor), 10, "host's tractor")
        assertEquals(getX(combine), 60, "player's combine")
        assertEquals(playerGame.lastNotification():sub(1, 5), "Auto:", "player is told")
        assertEquals(admin.game.lastNotification():sub(1, 5), "Auto:", "admin is told")
        assertEquals(hostGame.lastNotification():sub(1, 5), "Auto:", "host is told")
    end)

    test("multiplayer: removing a spot reaches every player", function()
        playerGame.currentVehicle = playerCopies[combine]
        playerMod:onClearHomeInput()
        step()

        assert(not hostMod.store:has(combine), "gone on the host")
        assert(not playerMod.store:has(playerCopies[combine]), "gone for the player")
        assert(not admin.HomeSpots.store:has(adminCopies[combine]), "gone for other players")
        assertEquals(playerGame.countMapHotspots(), 2, "player's map markers")
        assertEquals(playerGame.lastNotification(), "cleared Claas")
        playerGame.currentVehicle = nil
    end)

    test("multiplayer: a player parks in their own farm's shed and every player sees the spot", function()
        local shed = hostGame.newShed("Shed", 2, 200, 0, 220, 10, 5)
        playerGame.currentVehicle = playerCopies[combine]
        playerMod:onFindShedInput()
        step()

        assertEquals(string.format("%.1f", getX(combine)), "218.2", "host moved the combine into the shed")
        assert(playerMod.store:has(playerCopies[combine]), "player sees the spot")
        assert(admin.HomeSpots.store:has(adminCopies[combine]), "other players see the spot")
        assertEquals(playerGame.lastNotification(), "sent: Claas", "player is told")

        playerMod:onClearHomeInput()
        step()
        playerGame.currentVehicle = nil
        hostGame.removeShed(shed)
        hostGame.place(combine, 60, 0)
    end)

    test("multiplayer: a player's vehicle whose spot is taken parks beside it and the player is told", function()
        hostMod.store:set(combine)
        hostGame.place(trailer, 60, 0)
        hostGame.place(combine, 300, 0)
        playerGame.place(playerCopies[combine], 300, 0)

        playerMod:onSendAllHomeInput()
        step()
        assertEquals(math.abs(getX(combine) - 60), 3.5, "beside the trailer that stands on the spot")
        assertEquals(playerGame.lastNotification(), "sent 1. beside: Claas", "player is told")

        hostMod.store:remove(combine)
        hostGame.place(trailer, 30, 0)
        hostGame.place(combine, 60, 0)
    end)

    test("multiplayer: a player is asked before saving a spot that overlaps another", function()
        playerGame.currentVehicle = playerCopies[combine]
        playerGame.place(playerCopies[combine], 31, 1)

        playerMod:onSetHomeInput()
        assertEquals(playerGame.openDialog.text, "overlaps Trailer", "question on the player's machine")
        playerGame.openDialog.answer(true)
        step()
        assert(hostMod.store:has(combine), "saved on the host once confirmed")

        playerMod:onClearHomeInput()
        step()
        playerGame.place(playerCopies[combine], 60, 0)
        playerGame.currentVehicle = nil
    end)

    test("multiplayer: only the host writes homeSpots.xml", function()
        playerMod.onSaveCareer({savegameDirectory = "/mp"})
        assertEquals(next(playerGame.files), nil, "nothing saved on the player's machine")

        hostMod.onSaveCareer({savegameDirectory = "/mp"})
        assertEquals(hostGame.files["/mp/homeSpots.xml"]["homeSpots.vehicle(0)#uniqueId"] ~= nil, true, "saved on the host")
    end)

    test("multiplayer: the Home Spots page on a player's machine lists their farm and asks the host", function()
        local menu = admin.game.newInGameMenu()
        admin.env.g_gui.screenControllers[admin.env.InGameMenu] = menu
        admin.env.HomeSpotOverview:update(16)
        local page = menu[admin.env.HomeSpotOverview.PAGE_NAME]

        hostGame.place(tractor, 400, 0, 0)
        network.syncPositions(host, admin)
        page:onFrameOpen()

        local cells = page.homeSpotsList.cells
        assertEquals(#cells, 2, "tractor and trailer, not the other farm's combine")
        assertEquals(cells[1].name.text .. " " .. cells[1].status.text .. " " .. cells[1].distance.text, "Fendt homeSpots_statusAway 390 m")

        page.sendButtonInfo.callback()
        step()
        assertEquals(getX(tractor), 10, "host moved the tractor")
        assertEquals(admin.game.lastNotification(), "sent: Fendt", "player is told")
    end)
end
