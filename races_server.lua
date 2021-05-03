--[[

Copyright (c) 2021, Neil J. Tan
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

--]]

local STATE_REGISTERING = 0
local STATE_RACING = 1

local races = {} -- races[] = {state, laps, timeout, waypointCoords[] = {x, y, z}, publicRace, savedRaceName, numRacing, players[] = {numWaypointsPassed, data}, results[] = {playerName, finishTime, bestLapTime, vehicleName}}

local raceDataFile = "./resources/races/raceData.json"

local function notifyPlayer(source, msg)
    TriggerClientEvent("chat:addMessage", source, {
        color = {255, 0, 0},
        multiline = true,
        args = {"[races:server]", msg}
    })
end

local function convert()
    local raceData = nil

    local file = io.open(raceDataFile, "r")
    if file ~= nil then
        raceData = json.decode(file:read("*a"));
        io.close(file)
    end

    for license, playerRaces in pairs(raceData) do
        local newPlayerRaces = {}
        for name, waypointCoords in pairs(playerRaces) do
            newPlayerRaces[name] = {waypointCoords = waypointCoords, bestLaps = {}}
--[[
            print(("license: %s; name: %s"):format(license, name))
            for i, waypoint in ipairs(waypointCoords) do
                print(("%d: %f, %f, %f"):format(i, waypoint.x, waypoint.y, waypoint.z))
            end
--]]
        end
        raceData[license] = newPlayerRaces
    end

    file = io.open("./resources/races/raceData.new.json", "w+")
    if file ~= nil then
        file:write(json.encode(raceData))
        io.close(file)
    end

--[[
raceData[license] = playerRaces[name] = waypointCoords[i] = waypoint = {x, y, z}
raceData[license] = playerRaces[name] = {waypointCoords[] = {x, y, z}, bestLaps[] = {playerName, bestLapTime, vehicleName}}
--]]
end

local function loadPlayerData(public, source)
    local license = true == public and "PUBLIC" or GetPlayerIdentifier(source, 0)

    local playerRaces = nil

    if license ~= nil then
        if license ~= "PUBLIC" then
            license = string.sub(license, 9)
        end

        local raceData = nil

        local file = io.open(raceDataFile, "r")
        if file ~= nil then
            raceData = json.decode(file:read("*a"));
            io.close(file)
        else
            notifyPlayer(source, "loadPlayerData: Error opening file '" .. raceDataFile .. "' for read.\n")
            return nil
        end

        if nil == raceData then
            notifyPlayer(source, "loadPlayerData: No race data.\n")
            return nil
        end

        playerRaces = raceData[license]

        if nil == playerRaces then
            playerRaces = {}
        end
    else
        notifyPlayer(source, "loadPlayerData: Could not get license.\n")
        return nil
    end

    return playerRaces
end

local function savePlayerData(public, source, data)
    local license = true == public and "PUBLIC" or GetPlayerIdentifier(source, 0)

    if license ~= nil then
        if license ~= "PUBLIC" then
            license = string.sub(license, 9)
        end

        local raceData = nil

        local file = io.open(raceDataFile, "r")
        if file ~= nil then
            raceData = json.decode(file:read("*a"));
            io.close(file)
        else
            notifyPlayer(source, "savePlayerData: Error opening file '" .. raceDataFile .. "' for read.\n")
            return false
        end

        if nil == raceData then
            notifyPlayer(source, "savePlayerData: No race data.\n")
            return false
        end

        raceData[license] = data

        file = io.open(raceDataFile, "w+")
        if file ~= nil then
            file:write(json.encode(raceData))
            io.close(file)
        else
            notifyPlayer(source, "savePlayerData: Error opening file '" .. raceDataFile .. "' for write.\n")
            return false
        end
    else
        notifyPlayer(source, "savePlayerData: Could not get license.\n")
        return false
    end

    return true
end

local function updateBestLapTimes(index)
    local playerRaces = loadPlayerData(races[index].publicRace, index)
    if playerRaces ~= nil then
        local bestLaps = playerRaces[races[index].savedRaceName].bestLaps
        for _, result in pairs(races[index].results) do
            if result.bestLapTime ~= -1 then
                bestLaps[#bestLaps + 1] = {playerName = result.playerName, bestLapTime = result.bestLapTime, vehicleName = result.vehicleName}
            end
        end
        table.sort(bestLaps, function(p0, p1)
            return p0.bestLapTime < p1.bestLapTime
        end)
        if #bestLaps > 10 then
            for i = 11, #bestLaps do
                bestLaps[i] = nil
            end
        end
        playerRaces[races[index].savedRaceName].bestLaps = bestLaps
        if false == savePlayerData(races[index].publicRace, index, playerRaces) then
            notifyPlayer(index, "Save error updating best lap times.")
        end
    else
        notifyPlayer(index, "Load error updating best lap times.")
    end
end

RegisterNetEvent("races:load")
AddEventHandler("races:load", function(public, raceName)
    local source = source
    if public ~= nil and raceName ~= nil then
        local playerRaces = loadPlayerData(public, source)
        if playerRaces ~= nil then
            if playerRaces[raceName] ~= nil then
                TriggerClientEvent("races:load", source, public, raceName, playerRaces[raceName].waypointCoords)
            else
                notifyPlayer(source, "Cannot load.  '" .. raceName .. "' not found.\n")
            end
        else
            notifyPlayer(source, "Cannot load.  Error loading data.\n")
        end
    else
        notifyPlayer(source, "Ignoring load event.  Invalid paramaters.")
    end
end)

RegisterNetEvent("races:save")
AddEventHandler("races:save", function(public, raceName, waypointCoords)
    local source = source
    if public ~= nil and raceName ~= nil and waypointCoords ~= nil then
        local playerRaces = loadPlayerData(public, source)
        if playerRaces ~= nil then
            if nil == playerRaces[raceName] then
                playerRaces[raceName] = {waypointCoords = waypointCoords, bestLaps = {}}
                if true == savePlayerData(public, source, playerRaces) then
                    TriggerClientEvent("races:save", source, public, raceName)
                else
                    notifyPlayer(source, "Error saving '" .. raceName .. "'.\n")
                end
            else
                if true == public then
                    notifyPlayer(source, ("'%s' exists.  Type '/races overwritePublic %s'.\n"):format(raceName, raceName))
                else
                    notifyPlayer(source, ("'%s' exists.  Type '/races overwrite %s'.\n"):format(raceName, raceName))
                end
            end
        else
            notifyPlayer(source, "Cannot save.  Error loading data.\n")
        end
    else
        notifyPlayer(source, "Ignoring save event.  Invalid paramaters.")
    end
end)

RegisterNetEvent("races:overwrite")
AddEventHandler("races:overwrite", function(public, raceName, waypointCoords)
    local source = source
    if public ~= nil and raceName ~= nil and waypointCoords ~= nil then
        local playerRaces = loadPlayerData(public, source)
        if playerRaces ~= nil then
            if playerRaces[raceName] ~= nil then
                playerRaces[raceName] = {waypointCoords = waypointCoords, bestLaps = {}}
                if true == savePlayerData(public, source, playerRaces) then
                    TriggerClientEvent("races:overwrite", source, public, raceName)
                else
                    notifyPlayer(source, "Error overwriting '" .. raceName .. "'.\n")
                end
            else
                if true == public then
                    notifyPlayer(source, ("'%s' does not exist.  Type '/races savePublic %s'.\n"):format(raceName, raceName))
                else
                    notifyPlayer(source, ("'%s' does not exist.  Type '/races save %s'.\n"):format(raceName, raceName))
                end
            end
        else
            notifyPlayer(source, "Cannot overwrite.  Error loading data.\n")
        end
    else
        notifyPlayer(source, "Ignoring overwrite event.  Invalid paramaters.")
    end
end)

RegisterNetEvent("races:delete")
AddEventHandler("races:delete", function(public, raceName)
    local source = source
    if public ~= nil and raceName ~= nil then
        local playerRaces = loadPlayerData(public, source)
        if playerRaces ~= nil then
            if playerRaces[raceName] ~= nil then
                playerRaces[raceName] = nil
                if true == savePlayerData(public, source, playerRaces) then
                    local msg = "Deleted "
                    msg = msg .. (true == public and "public" or "private")
                    msg = msg .. " race '" .. raceName .. "'.\n"
                    notifyPlayer(source, msg)
                else
                    notifyPlayer(source, "Error deleting '" .. raceName .. "'.\n")
                end
            else
                notifyPlayer(source, "Cannot delete.  '" .. raceName .. "' not found.\n")
            end
        else
            notifyPlayer(source, "Cannot delete.  Error loading data.\n")
        end
    else
        notifyPlayer(source, "Ignoring delete event.  Invalid paramaters.")
    end
end)

RegisterNetEvent("races:list")
AddEventHandler("races:list", function(public)
    local source = source
    if public ~= nil then
        local playerRaces = loadPlayerData(public, source)
        if playerRaces ~= nil then
            local empty = true
            local msg = "Saved "
            msg = msg .. (true == public and "public" or "private")
            msg = msg .. " races:\n"
            for name, _ in pairs(playerRaces) do
                msg = msg .. name .. "\n"
                empty = false
            end
            if false == empty then
                notifyPlayer(source, msg)
            else
                notifyPlayer(source, "No saved races.\n")
            end
        else
            notifyPlayer(source, "Cannot list.  Error loading data.\n")
        end
    else
        notifyPlayer(source, "Ignoring list event.  Invalid paramaters.")
   end
end)

RegisterNetEvent("races:blt")
AddEventHandler("races:blt", function(public, raceName)
    local source = source
    if public ~= nil and raceName ~= nil then
        local playerRaces = loadPlayerData(public, source)
        if playerRaces ~= nil then
            if playerRaces[raceName] ~= nil then
                TriggerClientEvent("races:blt", source, public, raceName, playerRaces[raceName].bestLaps)
            else
                notifyPlayer(source, "Cannot list best lap times.  '" .. raceName .. "' not found.\n")
            end
        else
            notifyPlayer(source, "Cannot list best lap times.  Error loading data.\n")
        end
    else
        notifyPlayer(source, "Ignoring best lap times event.  Invalid paramaters.")
    end
end)

RegisterNetEvent("races:register")
AddEventHandler("races:register", function(laps, timeout, waypointCoords, publicRace, savedRaceName)
    local source = source
    if laps ~= nil and timeout ~= nil and waypointCoords ~= nil and publicRace ~= nil then
        if laps > 0 then
            if timeout >= 0 then
                if nil == races[source] then
                    local owner = GetPlayerName(source)
                    races[source] = {state = STATE_REGISTERING, laps = laps, timeout = timeout, waypointCoords = waypointCoords, publicRace = publicRace, savedRaceName = savedRaceName, numRacing = 0, players = {}, results = {}}
                    TriggerClientEvent("races:register", -1, source, owner, laps, waypointCoords[1], publicRace, savedRaceName)
                    local msg = "Registered "
                    if nil == savedRaceName then
                        msg = msg .. "private race "
                    else
                        msg = msg .. (true == publicRace and "public" or "private")
                        msg = msg .. " race '" .. savedRaceName .. "' "
                    end
                    msg = msg .. ("owned by %s : %d lap(s).\n"):format(owner, laps)
                    notifyPlayer(source, msg)
                else
                    if STATE_RACING == races[source].state then
                        notifyPlayer(source, "Previous race already started.\n")
                    else
                        notifyPlayer(source, "Previous race registered.  Unregister first.\n")
                    end
                end
            else
                notifyPlayer(source, "Invalid timeout.\n")
            end
        else
            notifyPlayer(source, "Invalid laps.\n")
        end
    else
        notifyPlayer(source, "Ignoring register event.  Invalid paramaters.")
    end
end)

RegisterNetEvent("races:unregister")
AddEventHandler("races:unregister", function()
    local source = source
    if races[source] ~= nil then
        races[source] = nil
        TriggerClientEvent("races:unregister", -1, source)
        notifyPlayer(source, "Race unregistered.\n")
    else
        notifyPlayer(source, "Cannot unregister.  No race registered.\n")
    end
end)

RegisterNetEvent("races:join")
AddEventHandler("races:join", function(index)
    local source = source
    if index ~= nil then
        if races[index] ~= nil then
            if STATE_REGISTERING == races[index].state then
                races[index].numRacing = races[index].numRacing + 1
                races[index].players[source] = {numWaypointsPassed = -1, data = -1}
                TriggerClientEvent("races:join", source, index, races[index].timeout, races[index].waypointCoords)
            else
                notifyPlayer(source, "Cannot join race in progress.\n")
            end
        else
            notifyPlayer(source, "Cannot join unkown race.\n")
        end
    else
        notifyPlayer(source, "Ignoring join event.  Invalid paramaters.")
    end
end)

RegisterNetEvent("races:leave")
AddEventHandler("races:leave", function(index)
    local source = source
    if index ~= nil then
        if races[index] ~= nil then
            if STATE_REGISTERING == races[index].state then
                if races[index].players[source] ~= nil then
                    races[index].players[source] = nil
                    races[index].numRacing = races[index].numRacing - 1
                else
                    notifyPlayer(source, "Cannot leave.  Not a member of this race.\n")
                end
            else
                notifyPlayer(source, "Cannot leave.  Race already started.\n")
            end
        else
            notifyPlayer(source, "Cannot leave.  Race does not exist.\n")
        end
    else
        notifyPlayer(source, "Ignoring leave event.  Invalid paramaters.")
    end
end)

RegisterNetEvent("races:rivals")
AddEventHandler("races:rivals", function(index)
    local source = source
    if index ~= nil then
        if races[index] ~= nil then
            if races[index].players[source] ~= nil then
                local empty = true
                local msg = "Competitors:\n"
                for i, _ in pairs(races[index].players) do
                    msg = msg .. GetPlayerName(i) .. "\n"
                    empty = false
                end
                if false == empty then
                    notifyPlayer(source, msg)
                else
                    notifyPlayer(source, "No competitors yet.\n")
                end
            else
                notifyPlayer(source, "Cannot list competitors.  Not a member of this race.\n")
            end
        else
            notifyPlayer(source, "Cannot list competitors.  Race does not exist.\n")
        end
    else
        notifyPlayer(source, "Ignoring rivals event.  Invalid paramaters.")
    end
end)

RegisterNetEvent("races:start")
AddEventHandler("races:start", function(delay)
    local source = source
    if delay ~= nil then
        if races[source] ~= nil then
            if STATE_REGISTERING == races[source].state then
                if delay >= 0 then
                    if next(races[source].players) ~= nil then
                        races[source].state = STATE_RACING
                        for i, _ in pairs(races[source].players) do
                            TriggerClientEvent("races:start", i, delay)
                        end
                        TriggerClientEvent("races:hide", -1, source) -- hide race so no one else can join
                    else
                        notifyPlayer(source, "Cannot start.  No players have joined race.\n")
                    end
                else
                    notifyPlayer(source, "Cannot start.  Invalid delay.\n")
                end
            else
                notifyPlayer(source, "Cannot start.  Race already started.\n")
            end
        else
            notifyPlayer(source, "Cannot start.  No race registered.\n")
        end
    else
        notifyPlayer(source, "Ignoring start event.  Invalid paramaters.")
    end
end)

RegisterNetEvent("races:finish")
AddEventHandler("races:finish", function(index, numWaypointsPassed, finishTime, bestLapTime, vehicleName)
    local source = source
    if index ~= nil and numWaypointsPassed ~= nil and finishTime ~= nil and bestLapTime ~= nil and vehicleName ~= nil then
        if races[index] ~= nil then
            if STATE_RACING == races[index].state then
                if races[index].players[source] ~= nil then
                    races[index].players[source].numWaypointsPassed = numWaypointsPassed
                    races[index].players[source].data = finishTime

                    local playerName = GetPlayerName(source)

                    for i, _ in pairs(races[index].players) do
                        TriggerClientEvent("races:finish", i, playerName, finishTime, bestLapTime, vehicleName)
                    end

                    races[index].results[#(races[index].results) + 1] = {playerName = playerName, finishTime = finishTime, bestLapTime = bestLapTime, vehicleName = vehicleName}

                    races[index].numRacing = races[index].numRacing - 1
                    if 0 == races[index].numRacing then
                        for i, _ in pairs(races[index].players) do
                            TriggerClientEvent("races:results", i, races[index].results)
                        end
                        if races[index].savedRaceName ~= nil then
                            updateBestLapTimes(index)
                        end
                        races[index] = nil -- delete race after all players finish
                    end
                else
                    notifyPlayer(source, "Cannot finish.  Not a member of this race.\n")
                end
            else
                notifyPlayer(source, "Cannot finish.  Race not in progress.\n")
            end
        else
            notifyPlayer(source, "Cannot finish.  Race does not exist.\n")
        end
    else
        notifyPlayer(source, "Ignoring finish event.  Invalid paramaters.")
    end
end)

RegisterNetEvent("races:report")
AddEventHandler("races:report", function(index, numWaypointsPassed, dist)
    local source = source
    if index ~= nil and numWaypointsPassed ~= nil and dist ~= nil then
        if races[index] ~= nil and races[index].players[source] ~= nil then
            races[index].players[source].numWaypointsPassed = numWaypointsPassed
            races[index].players[source].data = dist
        end
    else
        notifyPlayer(source, "Ignoring report event.  Invalid paramaters.")
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        for _, race in pairs(races) do
            if STATE_RACING == race.state then
                local sortedPlayers = {} -- will contain players still racing and players that finished without DNF
                local complete = true

                -- race.players[] = {numWaypointsPassed, data}
                for i, player in pairs(race.players) do
                    if -1 == player.numWaypointsPassed then -- player client hasn't updated numWaypointsPassed and data
                        complete = false
                        break
                    end

                    -- if player.data == -1 then player did not finish race - do not include in sortedPlayers
                    if player.data ~= -1 then
                        sortedPlayers[#sortedPlayers + 1] = {index = i, numWaypointsPassed = player.numWaypointsPassed, data = player.data}
                    end
                end

                if true == complete then -- all player clients have updated numWaypointsPassed and data
                    table.sort(sortedPlayers, function(p0, p1)
                        return (p0.numWaypointsPassed > p1.numWaypointsPassed) or (p0.numWaypointsPassed == p1.numWaypointsPassed and p0.data < p1.data)
                    end)
                    -- players sorted into sortedPlayers table
                    for position, sortedPlayer in pairs(sortedPlayers) do
                        TriggerClientEvent("races:position", sortedPlayer.index, position, #sortedPlayers)
                    end
                end
            end
        end
    end
end)
