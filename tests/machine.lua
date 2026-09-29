-- Simulated multiplayer: every machine (host or player's PC) runs its own copy of the game stand-ins and of the mod,
-- and events travel between them only as written streams, the way the game sends them.
local machine = {}

-- Loaded in the order modDesc.xml lists them
machine.SCRIPTS = {
    "HomeSpotArea", "HomeSpotStore", "HomeSpotFee", "HomeSpotShed", "HomeSpotNearby", "HomeSpotHotspot", "HomeSpotSettings",
    "HomeSpots", "HomeSpotEvents", "HomeSpotMapMenu", "HomeSpotOverview",
}


---Run a Lua file with its own globals
-- @param table env globals
-- @param string path file
-- @return any result what the file returns
local function loadInto(env, path)
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)

    return chunk()
end


---Start a machine: fresh game stand-ins and a fresh copy of the mod
-- @param table luaGlobals plain Lua globals
-- @return table machine env (its globals) and game (its stand-ins)
function machine.new(luaGlobals)
    local env = setmetatable({}, {__index = luaGlobals})
    env._G = env

    local game = loadInto(env, "tests/game_mock.lua")
    for _, name in ipairs(machine.SCRIPTS) do
        loadInto(env, "scripts/" .. name .. ".lua")
    end

    return {env = env, game = game, HomeSpots = env.HomeSpots}
end


---Create a network that machines can join
-- @param table luaGlobals plain Lua globals
-- @return table network
function machine.newNetwork(luaGlobals)
    local network = {queue = {}}

    function network.newMachine()
        return machine.new(luaGlobals)
    end

    ---Write an event on one machine and queue it for another
    function network.send(event, sender, receiver, receiverConnection)
        local className
        for name, eventClass in pairs(sender.game.eventClasses) do
            if getmetatable(event).__index == eventClass then
                className = name
            end
        end
        assert(className ~= nil, "event class was not registered with InitEventClass")

        local stream = sender.game.newStream()
        event:writeStream(stream, nil)
        table.insert(network.queue, {className = className, stream = stream, receiver = receiver, connection = receiverConnection})
    end

    ---Read every queued event on its receiving machine, in the order they were sent
    function network.deliver()
        while #network.queue > 0 do
            local message = table.remove(network.queue, 1)
            local event = message.receiver.game.eventClasses[message.className].emptyNew()
            event:readStream(message.stream, message.connection)
            assert(message.stream.readPos == #message.stream.values, message.className .. " left unread values in the stream")
        end
    end

    ---Connect a player's machine to the host
    -- @param table host host machine
    -- @param table player player machine
    -- @param integer userId user id of the player
    -- @param integer farmId farm the player plays on
    -- @param boolean isMasterUser true for a server admin
    -- @return table connection the host's connection to the player
    function network.connect(host, player, userId, farmId, isMasterUser)
        local toPlayer = {userId = userId, isMasterUser = isMasterUser}
        local toHost = {}

        function toPlayer.getIsServer() return false end
        function toPlayer.getIsLocal() return false end
        function toPlayer.sendEvent(_, event) network.send(event, host, player, toHost) end
        function toHost.getIsServer() return true end
        function toHost.getIsLocal() return false end
        function toHost.sendEvent(_, event) network.send(event, player, host, toPlayer) end

        table.insert(host.env.g_server.connections, toPlayer)
        host.game.userFarms[userId] = farmId

        local mission = player.env.g_currentMission
        mission.isServer = false
        mission.isMasterUser = isMasterUser
        mission.farmId = farmId
        player.env.g_server = nil
        player.env.g_client = {getServerConnection = function() return toHost end}

        return toPlayer
    end

    ---The player's machine finished loading: the host's join hook runs for it
    -- @param table host host machine
    -- @param table connection the host's connection to the player
    function network.finishJoining(host, connection)
        host.env.FSBaseMission.onConnectionFinishedLoading(host.env.g_currentMission, connection)
    end

    ---Give a player's machine a copy of each of the host's vehicles, under the same network object id.
    -- Players never learn unique ids, so the copies have none.
    -- @param table host host machine
    -- @param table player player machine
    -- @return table copies player's vehicle by host vehicle
    function network.copyVehicles(host, player)
        local copies = {}
        for _, vehicle in ipairs(host.game.vehicles) do
            local x, z = host.game.getPosition(vehicle)
            local copy = player.game.newVehicle(nil, vehicle.name, x, z, host.game.getYaw(vehicle))
            player.game.objects[copy.objectId] = nil
            player.game.setObjectId(copy, vehicle.objectId)
            copy.farmId = vehicle.farmId
            copies[vehicle] = copy
        end

        return copies
    end

    ---The game's own vehicle sync: players see where the host's vehicles stand
    -- @param table host host machine
    -- @param table player player machine
    function network.syncPositions(host, player)
        for _, vehicle in ipairs(host.game.vehicles) do
            local copy = player.game.objects[vehicle.objectId]
            local x, z = host.game.getPosition(vehicle)
            player.game.place(copy, x, z, host.game.getYaw(vehicle))
        end
    end

    return network
end


return machine
