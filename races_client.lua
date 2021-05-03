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

local STATE_IDLE = 0
local STATE_EDITING = 1
local STATE_REGISTERING = 2
local STATE_RACING = 3
local raceState = STATE_IDLE -- race state

local startFinishBlipColor = 5 -- yellow
local startBlipColor = 2 -- green
local finishBlipColor = 0 -- white
local midBlipColor = 38 -- dark blue
local registerBlipColor = 2 -- green
local selectedBlipColor = 1 -- red
local blipRouteColor = 18 -- light blue

local startFinishSprite = 38 -- checkered flag
local startSprite = 38 -- checkered flag
local finishSprite = 38 -- checkered flag
local midSprite = 1 -- numbered circle
local registerSprite = 58 -- circled star

local finishCheckpoint = 4 -- cylinder checkered
local midCheckpoint = 45 -- cylinder

local leftSide = 0.43 -- left position of HUD
local rightSide = 0.51 -- right position of HUD

local lastSelectedWaypoint = 0 -- index of last selected waypoint

local raceIndex = -1 -- index of race player has joined
local publicRace = false -- flag indicating if saved race is public or not
local savedRaceName = nil -- name of saved waypoints - nil if waypoints not saved

local waypointBlips = {} -- waypointBlips[] = blip - race waypoint blips
local startIsFinish = false -- flag indicating if start and finish are same waypoint

local numLaps = -1 -- number of laps in current race
local currentLap = -1 -- current lap

local numWaypointsPassed = -1 -- number of waypoints player has passed
local currentWaypoint = -1 -- current waypoint
local waypointCoord = nil -- coordinates of current waypoint

local raceStart = -1 -- start time of race before delay
local raceDelay = -1 -- delay before official start of race

local position = -1 -- position in race out of numRacers players
local numRacers = -1 -- number of players in race - no DNF players included

local lapTimeStart = -1 -- start time of current lap
local bestLapTime = -1 -- best lap time

local raceCheckpoint = nil -- race checkpoint in world

local DNFTimeout = -1 -- DNF timeout after first player finishes the race
local beginDNFTimeout = false -- flag indicating if DNF timeout should begin
local timeoutStart = -1 -- start time of DNF timeout

local vehicleName = "FEET" -- name of vehicle in which player started

local results = {} -- results[] = {playerName, finishTime, bestLapTime, vehicleName}

local frozen = false -- flag indicating if vehicle is frozen

local starts = {} -- starts[] = {owner, publicRace, savedRaceName, laps, blip, checkpoint} - registration points

local speedo = false -- flag indicating if speedometer is displayed

local function notifyPlayer(msg)
    TriggerEvent("chat:addMessage", {
        color = {255, 0, 0},
        multiline = true,
        args = {"[races:client]", msg}
    })
end

local function loadRace(public, raceName)
    if raceName ~= nil then
        if STATE_IDLE == raceState or STATE_EDITING == raceState then
            TriggerServerEvent("races:load", public, raceName)
        else
            notifyPlayer("Cannot load '" .. raceName .. "'.  Leave race first.\n")
        end
    else
        notifyPlayer("Cannot load.  Name required.\n")
    end
end

local function waypointBlipsToCoords()
    local waypointCoords = {}
    for i = 1, #waypointBlips do
        waypointCoords[i] = GetBlipCoords(waypointBlips[i])
    end
    if true == startIsFinish then
        waypointCoords[#waypointCoords + 1] = waypointCoords[1]
    end
    return waypointCoords
end

local function saveRace(public, raceName)
    if raceName ~= nil then
        if #waypointBlips > 1 then
            TriggerServerEvent("races:save", public, raceName, waypointBlipsToCoords())
        else
            notifyPlayer("Cannot save.  Race needs to have at least 2 waypoints.\n")
        end
    else
        notifyPlayer("Cannot save.  Name required.\n")
    end
end

local function overwriteRace(public, raceName)
    if raceName ~= nil then
        if #waypointBlips > 1 then
            TriggerServerEvent("races:overwrite", public, raceName, waypointBlipsToCoords())
        else
            notifyPlayer("Cannot overwrite.  Race needs to have at least 2 waypoints.\n")
        end
    else
        notifyPlayer("Cannot overwrite.  Name required.\n")
    end
end

local function deleteRace(public, raceName)
    if raceName ~= nil then
        TriggerServerEvent("races:delete", public, raceName)
     else
         notifyPlayer("Cannot delete.  Name required.\n")
     end
end

local function bestLapTimes(public, raceName)
    if raceName ~= nil then
            TriggerServerEvent("races:blt", public, raceName)
    else
        notifyPlayer("Cannot list best lap times.  Name required.\n")
    end
end

local function deleteWaypointBlips()
    for i = 1, #waypointBlips do
        RemoveBlip(waypointBlips[i])
    end
    waypointBlips = {}
    startIsFinish = false
end

local function setStartToFinishBlips()
    if true == startIsFinish then
        SetBlipSprite(waypointBlips[1], startFinishSprite)
        SetBlipColour(waypointBlips[1], startFinishBlipColor)
        ShowNumberOnBlip(waypointBlips[1], -1)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Start/Finish")
        EndTextCommandSetBlipName(waypointBlips[1])

        if #waypointBlips > 1 then
            SetBlipSprite(waypointBlips[#waypointBlips], midSprite)
            SetBlipColour(waypointBlips[#waypointBlips], midBlipColor)
            ShowNumberOnBlip(waypointBlips[#waypointBlips], #waypointBlips - 1)
        end
    else -- #waypointBlips should be > 1
        SetBlipSprite(waypointBlips[1], startSprite)
        SetBlipColour(waypointBlips[1], startBlipColor)
        ShowNumberOnBlip(waypointBlips[1], -1)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Start")
        EndTextCommandSetBlipName(waypointBlips[1])

        SetBlipSprite(waypointBlips[#waypointBlips], finishSprite)
        SetBlipColour(waypointBlips[#waypointBlips], finishBlipColor)
        ShowNumberOnBlip(waypointBlips[#waypointBlips], -1)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Finish")
        EndTextCommandSetBlipName(waypointBlips[#waypointBlips])
    end

    for i = 2, #waypointBlips - 1 do
        SetBlipSprite(waypointBlips[i], midSprite)
        SetBlipColour(waypointBlips[i], midBlipColor)
        ShowNumberOnBlip(waypointBlips[i], i - 1)
    end
end

local function loadWaypointBlips(waypointCoords)
    deleteWaypointBlips()

    for i = 1, #waypointCoords - 1 do
        local blip = AddBlipForCoord(waypointCoords[i].x, waypointCoords[i].y, waypointCoords[i].z)
        SetBlipAsShortRange(blip, true)
        waypointBlips[i] = blip
    end

    startIsFinish =
        waypointCoords[1].x == waypointCoords[#waypointCoords].x and
        waypointCoords[1].y == waypointCoords[#waypointCoords].y and
        waypointCoords[1].z == waypointCoords[#waypointCoords].z

    if false == startIsFinish then
        local blip = AddBlipForCoord(waypointCoords[#waypointCoords].x, waypointCoords[#waypointCoords].y, waypointCoords[#waypointCoords].z)
        SetBlipAsShortRange(blip, true)
        waypointBlips[#waypointCoords] = blip
    end

    setStartToFinishBlips()

    SetBlipRoute(waypointBlips[1], true)
    SetBlipRouteColour(waypointBlips[1], blipRouteColor)
end

local function removeRegistrationPoint(index)
    RemoveBlip(starts[index].blip) -- delete registration blip
    DeleteCheckpoint(starts[index].checkpoint) -- delete registration checkpoint
    starts[index] = nil
end

local function minutesSeconds(milliseconds)
    local seconds = milliseconds / 1000.0
    local minutes = math.floor(seconds / 60.0)
    seconds = seconds - minutes * 60.0
    return minutes, seconds
end

local function printResults()
    if #results > 0 then
        local msg = "Race results:\n"
        for pos, result in ipairs(results) do
            if -1 == result.finishTime then
                msg = msg .. "DNF - " .. result.playerName
                if result.bestLapTime >= 0 then
                    local minutes, seconds = minutesSeconds(result.bestLapTime)
                    msg = msg .. (" - best lap %02d:%05.2f using %s"):format(minutes, seconds, result.vehicleName)
                end
                msg = msg .. "\n"
            else
                local fMinutes, fSeconds = minutesSeconds(result.finishTime)
                local lMinutes, lSeconds = minutesSeconds(result.bestLapTime)
                msg = msg .. ("%d - %02d:%05.2f - %s - best lap %02d:%05.2f using %s\n"):format(pos, fMinutes, fSeconds, result.playerName, lMinutes, lSeconds, result.vehicleName)
            end
        end
        notifyPlayer(msg)
    else
        notifyPlayer("No results.\n")
    end
end

local function createRaceCheckpoint(checkpointType, coord)
    raceCheckpoint = CreateCheckpoint(checkpointType, coord.x, coord.y, coord.z, 0, 0, 0, 10.0, 255, 255, 0, 127, 0)
    SetCheckpointCylinderHeight(raceCheckpoint, 10.0, 10.0, 10.0)
end

local function drawMsg(x, y, msg, scale)
    SetTextFont(4)
    SetTextScale(0, scale)
    SetTextColour(255, 255, 0, 255)
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(msg)
    DrawText(x, y)
end

RegisterCommand("races", function(_, args)
    if nil == args[1] then
        local msg = "Commands:\n"
        msg = msg .. "/races - display list of available races commands\n"
        msg = msg .. "/races edit - toggle editing race waypoints\n"
        msg = msg .. "/races clear - clear race waypoints\n"
        msg = msg .. "/races load [name] - load race waypoints saved as [name]\n"
        msg = msg .. "/races save [name] - save new race waypoints as [name]\n"
        msg = msg .. "/races overwrite [name] - overwrite existing race waypoints saved as [name]\n"
        msg = msg .. "/races delete [name] - delete race waypoints saved as [name]\n"
        msg = msg .. "/races blt [name] - list 10 best lap times of race saved as [name]\n"
        msg = msg .. "/races list - list saved races\n"
        msg = msg .. "/races loadPublic [name] - load public race waypoints saved as [name]\n"
        msg = msg .. "/races savePublic [name] - save new public race waypoints as [name]\n"
        msg = msg .. "/races overwritePublic [name] - overwrite existing public race waypoints saved as [name]\n"
        msg = msg .. "/races deletePublic [name] - delete public race waypoints saved as [name]\n"
        msg = msg .. "/races bltPublic [name] - list 10 best lap times of public race saved as [name]\n"
        msg = msg .. "/races listPublic - list public saved races\n"
        msg = msg .. "/races register (laps) (DNF timeout) - register your race; (laps) defaults to 1 lap; (DNF timeout) defaults to 120 seconds\n"
        msg = msg .. "/races unregister - unregister your race\n"
        msg = msg .. "/races leave - leave a race that you joined\n"
        msg = msg .. "/races rivals - list competitors in a race that you joined\n"
        msg = msg .. "/races start (delay) - start your registered race; (delay) defaults to 30 seconds\n"
        msg = msg .. "/races results - list latest race results\n"
        msg = msg .. "/races speedo - toggle display of speedometer\n"
        msg = msg .. "/races car (name) - spawn a car; (name) defaults to 'adder'\n"
        notifyPlayer(msg)
    elseif "edit" == args[1] then
        if STATE_IDLE == raceState then
            raceState = STATE_EDITING
            raceCheckpoint = nil
            lastSelectedWaypoint = 0
            SetWaypointOff()
            notifyPlayer("Editing started.\n")
        elseif STATE_EDITING == raceState then
            raceState = STATE_IDLE
            if raceCheckpoint ~= nil then
                DeleteCheckpoint(raceCheckpoint)
            end
            if lastSelectedWaypoint > 0 then
                setStartToFinishBlips()
            end
            notifyPlayer("Editing stopped.\n")
        else
            notifyPlayer("Cannot edit waypoints.  Leave race first.\n")
        end
    elseif "clear" == args[1] then
        if STATE_IDLE == raceState then
            savedRaceName = nil
            deleteWaypointBlips()
            notifyPlayer("Waypoints cleared.\n")
        elseif STATE_EDITING == raceState then
            if raceCheckpoint ~= nil then
                DeleteCheckpoint(raceCheckpoint)
                raceCheckpoint = nil
            end
            lastSelectedWaypoint = 0
            savedRaceName = nil
            deleteWaypointBlips()
            notifyPlayer("Waypoints cleared.\n")
        else
            notifyPlayer("Cannot clear waypoints.  Leave race first.\n")
        end
    elseif "load" == args[1] then
        loadRace(false, args[2])
    elseif "loadPublic" == args[1] then
        loadRace(true, args[2])
    elseif "save" == args[1] then
        saveRace(false, args[2])
    elseif "savePublic" == args[1] then
        saveRace(true, args[2])
    elseif "overwrite" == args[1] then
        overwriteRace(false, args[2])
    elseif "overwritePublic" == args[1] then
        overwriteRace(true, args[2])
    elseif "delete" == args[1] then
        deleteRace(false, args[2])
    elseif "deletePublic" == args[1] then
        deleteRace(true, args[2])
    elseif "blt" == args[1] then
        bestLapTimes(false, args[2])
    elseif "bltPublic" == args[1] then
        bestLapTimes(true, args[2])
    elseif "list" == args[1] then
        TriggerServerEvent("races:list", false)
    elseif "listPublic" == args[1] then
        TriggerServerEvent("races:list", true)
    elseif "register" == args[1] then
        local laps = tonumber(args[2]) or 1
        if laps > 0 then
            local timeout = tonumber(args[3]) or (2 * 60)
            if timeout >= 0 then
                if STATE_IDLE == raceState then
                    if #waypointBlips > 1 then
                        if laps < 2 then
                            TriggerServerEvent("races:register", laps, timeout, waypointBlipsToCoords(), publicRace, savedRaceName)
                        elseif true == startIsFinish then
                            TriggerServerEvent("races:register", laps, timeout, waypointBlipsToCoords(), publicRace, savedRaceName)
                        else
                            notifyPlayer("For multi-lap races, start and finish waypoints need to be the same: While editing waypoints, select finish waypoint first, then select start waypoint.  To separate start/finish waypoint, add a new waypoint or select start/finish waypoint first, then select highest numbered waypoint.\n")
                        end
                    else
                        notifyPlayer("Cannot register.  Race needs to have at least 2 waypoints.\n")
                    end
                elseif STATE_EDITING == raceState then
                    notifyPlayer("Cannot register.  Stop editing first.\n")
                else
                    notifyPlayer("Cannot register.  Leave race first.\n")
                end
            else
                notifyPlayer("Invalid DNF timeout.\n")
            end
        else
            notifyPlayer("Invalid laps number.\n")
        end
    elseif "unregister" == args[1] then
        TriggerServerEvent("races:unregister")
    elseif "leave" == args[1] then
        if STATE_REGISTERING == raceState then
            raceState = STATE_IDLE
            TriggerServerEvent("races:leave", raceIndex)
            notifyPlayer("Left race.\n")
        elseif STATE_RACING == raceState then
            raceState = STATE_IDLE
            TriggerServerEvent("races:finish", raceIndex, numWaypointsPassed, -1, bestLapTime, vehicleName)
            DeleteCheckpoint(raceCheckpoint)
            SetBlipRoute(waypointBlips[1], true)
            SetBlipRouteColour(waypointBlips[1], blipRouteColor)
            speedo = false
            notifyPlayer("Left race.\n")
        else
            notifyPlayer("Cannot leave.  Not joined to any race.\n")
        end
    elseif "rivals" == args[1] then
        if STATE_REGISTERING == raceState or STATE_RACING == raceState then
            TriggerServerEvent("races:rivals", raceIndex)
        else
            notifyPlayer("Cannot list competitors.  Not joined to any race.\n")
        end
    elseif "start" == args[1] then
        local delay = tonumber(args[2]) or 30
        if delay >= 0 then
            TriggerServerEvent("races:start", delay)
        else
            notifyPlayer("Cannot start.  Invalid delay.\n")
        end
    elseif "results" == args[1] then
        printResults()
    elseif "speedo" == args[1] then
        speedo = not speedo
        if true == speedo then
            notifyPlayer("Speedometer enabled.\n")
        else
            notifyPlayer("Speedometer disabled.\n")
        end
    elseif "car" == args[1] then
        local vehicleHash = args[2] or "adder"
        if 1 == IsModelInCdimage(vehicleHash) and 1 == IsModelAVehicle(vehicleHash) then
            RequestModel(vehicleHash)
            while false == HasModelLoaded(vehicleHash) do
                Citizen.Wait(500)
            end

            local player = PlayerPedId()
            local pedCoord = GetEntityCoords(player)
            local vehicle = CreateVehicle(vehicleHash, pedCoord.x, pedCoord.y, pedCoord.z, GetEntityHeading(player), true, false)
            SetPedIntoVehicle(player, vehicle, -1)
            SetEntityAsNoLongerNeeded(vehicle)
            SetModelAsNoLongerNeeded(vehicleHash)
            notifyPlayer("'" .. GetLabelText(GetDisplayNameFromVehicleModel(vehicleHash)) .. "' spawned.\n")
        else
            notifyPlayer("Invalid vehicle '" .. vehicleHash .. "'.\n")
        end
--[[
    elseif "test" == args[1] then
        TriggerEvent("races:finish", "John Doe", (5 * 60 + 24) * 1000, (1 * 60 + 32) * 1000, "Duck")
--]]
    else
        notifyPlayer("Unknown command.\n")
    end
end)

RegisterNetEvent("races:load")
AddEventHandler("races:load", function(public, raceName, waypointCoords)
    if public ~= nil and raceName ~= nil and waypointCoords ~= nil then
        if STATE_IDLE == raceState then
            publicRace = public
            savedRaceName = raceName
            loadWaypointBlips(waypointCoords)
            notifyPlayer("Loaded '" .. raceName .. "'.\n")
        elseif STATE_EDITING == raceState then
            if raceCheckpoint ~= nil then
                DeleteCheckpoint(raceCheckpoint)
                raceCheckpoint = nil
            end
            lastSelectedWaypoint = 0
            publicRace = public
            savedRaceName = raceName
            loadWaypointBlips(waypointCoords)
            notifyPlayer("Loaded '" .. raceName .. "'.\n")
        else
            notifyPlayer("Ignoring load event.  Currently joined to race.\n")
        end
    else
        notifyPlayer("Ignoring load event.  Invalid paramaters.\n")
    end
end)

RegisterNetEvent("races:save")
AddEventHandler("races:save", function(public, raceName)
    if public ~= nil and raceName ~= nil then
        publicRace = public
        savedRaceName = raceName
        notifyPlayer("Saved '" .. raceName .. "'.\n")
    else
        notifyPlayer("Ignoring save event.  Invalid paramaters.\n")
    end
end)

RegisterNetEvent("races:overwrite")
AddEventHandler("races:overwrite", function(public, raceName)
    if public ~= nil and raceName ~= nil then
        publicRace = public
        savedRaceName = raceName
        notifyPlayer("Overwrote '" .. raceName .. "'.\n")
    else
        notifyPlayer("Ignoring overwrite event.  Invalid paramaters.\n")
    end
end)

RegisterNetEvent("races:blt")
AddEventHandler("races:blt", function(public, raceName, bestLaps)
    if public ~= nil and raceName ~=nil and bestLaps ~= nil then
        local msg = true == public and "public" or "private"
        msg = msg .. " race '" .. raceName .. "'"
        if #bestLaps > 0 then
            msg = "Best lap times for " .. msg .. ":\n"
            for pos, bestLap in ipairs(bestLaps) do
                local minutes, seconds = minutesSeconds(bestLap.bestLapTime)
                msg = msg .. ("%d - %s - %02d:%05.2f using %s\n"):format(pos, bestLap.playerName, minutes, seconds, bestLap.vehicleName)
            end
        else
            msg = "No best lap times for " .. msg .. ".\n"
        end
        notifyPlayer(msg)
    else
        notifyPlayer("Ignoring best lap times event.  Invalid paramaters.\n")
    end
end)

RegisterNetEvent("races:register")
AddEventHandler("races:register", function(index, owner, laps, coord, public, raceName)
    if index ~= nil and owner ~= nil and laps ~=nil and coord ~= nil and public ~= nil then
        local blip = AddBlipForCoord(coord.x, coord.y, coord.z) -- registration blip
        SetBlipAsShortRange(blip, true)
        SetBlipSprite(blip, registerSprite)
        SetBlipColour(blip, registerBlipColor)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Registration point")
        EndTextCommandSetBlipName(blip)

        local checkpoint = CreateCheckpoint(midCheckpoint, coord.x, coord.y, coord.z, 0, 0, 0, 10.0, 0, 255, 0, 127, 0) -- registration checkpoint
        SetCheckpointCylinderHeight(checkpoint, 10.0, 10.0, 10.0)

        starts[index] = {owner = owner, laps = laps, publicRace = public, savedRaceName = raceName, blip = blip, checkpoint = checkpoint}
    else
        notifyPlayer("Ignoring register event.  Invalid paramaters.\n")
    end
end)

RegisterNetEvent("races:unregister")
AddEventHandler("races:unregister", function(index)
    if index ~= nil then
        if starts[index] ~= nil then
            removeRegistrationPoint(index)
            if raceIndex == index then
                if STATE_REGISTERING == raceState then
                    raceState = STATE_IDLE
                    notifyPlayer("Race canceled.\n")
                elseif STATE_RACING == raceState then
                    raceState = STATE_IDLE
                    SetBlipRoute(waypointBlips[1], true)
                    SetBlipRouteColour(waypointBlips[1], blipRouteColor)
                    DeleteCheckpoint(raceCheckpoint)
                    speedo = false
                    notifyPlayer("Race canceled.\n")
                end
            end
        else
            notifyPlayer("Ignoring unregister event.  Unknown race.\n")
        end
    else
        notifyPlayer("Ignoring unregister event.  Invalid paramaters.\n")
    end
end)

RegisterNetEvent("races:join")
AddEventHandler("races:join", function(index, timeout, waypointCoords)
    if index ~= nil and timeout ~= nil and waypointCoords ~= nil then
        if starts[index] ~= nil then
            if STATE_IDLE == raceState then
                raceState = STATE_REGISTERING
                raceIndex = index
                numLaps = starts[index].laps
                DNFTimeout = timeout * 1000
                loadWaypointBlips(waypointCoords)
                local msg = "Joined "
                if nil == starts[index].savedRaceName then
                    msg = msg .. "private race "
                else
                    msg = msg .. (true == starts[index].publicRace and "public" or "private")
                    msg = msg .. " race '" .. starts[index].savedRaceName .. "' "
                end
                msg = msg .. ("owned by %s : %d lap(s).\n"):format(starts[index].owner, numLaps)
                notifyPlayer(msg)
            elseif STATE_EDITING == raceState then
                notifyPlayer("Ignoring join event.  Currently editing.\n")
            else
                notifyPlayer("Ignoring join event.  Already joined to a race.\n")
            end
        else
            notifyPlayer("Ignoring join event.  Unknown race.\n")
        end
    else
        notifyPlayer("Ignoring join event.  Invalid paramaters.\n")
    end
end)

RegisterNetEvent("races:start")
AddEventHandler("races:start", function(delay)
    if delay ~= nil then
        if delay >= 0 then
            if STATE_REGISTERING == raceState then
                raceState = STATE_RACING
                raceStart = GetGameTimer()
                raceDelay = delay
                lapTimeStart = raceStart + delay * 1000
                bestLapTime = -1
                currentLap = 1
                numWaypointsPassed = 0
                position = -1
                numRacers = -1
                beginDNFTimeout = false
                timeoutStart = -1
                vehicleName = "FEET"
                results = {}
                frozen = false
                speedo = true

                local checkpointType
                if true == startIsFinish then
                    currentWaypoint = 1
                    checkpointType =  midCheckpoint
                else
                    currentWaypoint = 2
                    checkpointType = (#waypointBlips == currentWaypoint and numLaps == currentLap) and finishCheckpoint or midCheckpoint
                end
                waypointCoord = GetBlipCoords(waypointBlips[2])
                createRaceCheckpoint(checkpointType, waypointCoord)

                SetBlipRoute(waypointBlips[2], true)
                SetBlipRouteColour(waypointBlips[2], blipRouteColor)

                notifyPlayer("Race started.\n")
            elseif STATE_RACING == raceState then
                notifyPlayer("Ignoring start event.  Already in a race.\n")
            elseif STATE_EDITING == raceState then
                notifyPlayer("Ignoring start event.  Currently editing.\n")
            else
                notifyPlayer("Ignoring start event.  Currently idle.\n")
            end
        else
            notifyPlayer("Ignoring start event.  Invalid delay.\n")
        end
    else
        notifyPlayer("Ignoring start event.  Invalid paramaters.\n")
    end
end)

RegisterNetEvent("races:results")
AddEventHandler("races:results", function(raceResults)
    if raceResults ~= nil then
        results = raceResults -- results[] = {playerName, finishTime, bestLapTime, vehicleName}

        table.sort(results, function(p0, p1)
            return
                (p0.finishTime >= 0 and (-1 == p1.finishTime or p0.finishTime < p1.finishTime)) or
                (-1 == p0.finishTime and -1 == p1.finishTime and (p0.bestLapTime >= 0 and (-1 == p1.bestLapTime or p0.bestLapTime < p1.bestLapTime)))
        end)

        printResults()
    else
        notifyPlayer("Ignoring results event.  Invalid paramaters.\n")
    end
end)

RegisterNetEvent("races:hide")
AddEventHandler("races:hide", function(index)
    if index ~= nil then
        if starts[index] ~= nil then
            removeRegistrationPoint(index)
        else
            notifyPlayer("Ignoring hide event.  Unknown race.\n")
        end
    else
        notifyPlayer("Ignoring hide event.  Invalid paramaters.\n")
    end
end)

RegisterNetEvent("races:finish")
AddEventHandler("races:finish", function(playerName, raceFinishTime, raceBestLapTime, raceVehicleName)
    if playerName ~= nil and raceFinishTime ~= nil and raceBestLapTime ~= nil and raceVehicleName ~= nil then
        if -1 == raceFinishTime then
            if -1 == raceBestLapTime then
                notifyPlayer(playerName .. " did not finish.\n")
            else
                local minutes, seconds = minutesSeconds(raceBestLapTime)
                notifyPlayer(("%s did not finish and had a best lap time of %02d:%05.2f using %s\n"):format(playerName, minutes, seconds, raceVehicleName))
            end
        else
            if false == beginDNFTimeout then
                beginDNFTimeout = true
                timeoutStart = GetGameTimer()
            end

            local fMinutes, fSeconds = minutesSeconds(raceFinishTime)
            local lMinutes, lSeconds = minutesSeconds(raceBestLapTime)
            notifyPlayer(("%s finished in %02d:%05.2f and had a best lap time of %02d:%05.2f using %s\n"):format(playerName, fMinutes, fSeconds, lMinutes, lSeconds, raceVehicleName))
        end
    else
        notifyPlayer("Ignoring finish event.  Invalid paramaters.\n")
    end
end)

RegisterNetEvent("races:position")
AddEventHandler("races:position", function(pos, numR)
    if pos ~= nil and numR ~= nil then
        if STATE_RACING == raceState then
            position = pos
            numRacers = numR
        else
            notifyPlayer("Ignoring position event.  Race not in progress.\n")
        end
    else
        notifyPlayer("Ignoring position event.  Invalid paramaters.\n")
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        if STATE_RACING == raceState then
            local blipCoord = GetBlipCoords(waypointBlips[currentWaypoint])
            local pedCoord = GetEntityCoords(PlayerPedId())
            local dist = CalculateTravelDistanceBetweenPoints(pedCoord.x, pedCoord.y, pedCoord.z, blipCoord.x, blipCoord.y, blipCoord.z)
            TriggerServerEvent("races:report", raceIndex, numWaypointsPassed, dist)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(10)
        if STATE_EDITING == raceState then
            if IsWaypointActive() then
                local waypoint = GetBlipCoords(GetFirstBlipInfoId(8))
                local _, coord = GetClosestVehicleNode(waypoint.x, waypoint.y, waypoint.z, 1)
                SetWaypointOff()

                local selectedWaypoint = 0
                for index, blip in pairs(waypointBlips) do
                    if coord == GetBlipCoords(blip) then
                        selectedWaypoint = index
                        break
                    end
                end

                if 0 == selectedWaypoint then -- no existing waypoint selected
                    if 0 == lastSelectedWaypoint then -- no previous selected waypoint exists, add new waypoint
                        local blip = AddBlipForCoord(coord.x, coord.y, coord.z)
                        SetBlipAsShortRange(blip, true)

                        waypointBlips[#waypointBlips + 1] = blip
                        startIsFinish = 1 == #waypointBlips and true or false

                        setStartToFinishBlips()

                        if raceCheckpoint ~= nil then -- new waypoint was added previously
                            DeleteCheckpoint(raceCheckpoint)
                        end
                    else -- previous selected waypoint exists, move previous selected waypoint to new location
                        SetBlipCoords(waypointBlips[lastSelectedWaypoint], coord.x, coord.y, coord.z)
                        DeleteCheckpoint(raceCheckpoint)
                    end

                    savedRaceName = nil

                    SetBlipRoute(waypointBlips[1], true)
                    SetBlipRouteColour(waypointBlips[1], blipRouteColor)

                    createRaceCheckpoint(midCheckpoint, coord)
                else -- existing waypoint selected
                    if 0 == lastSelectedWaypoint then -- no previous selected waypoint exists
                        SetBlipColour(waypointBlips[selectedWaypoint], selectedBlipColor)

                        lastSelectedWaypoint = selectedWaypoint

                        if raceCheckpoint ~= nil then -- new waypoint was added previously
                            DeleteCheckpoint(raceCheckpoint)
                        end

                        createRaceCheckpoint(midCheckpoint, coord)
                    else -- previous selected waypoint exists
                        DeleteCheckpoint(raceCheckpoint)
                        if selectedWaypoint ~= lastSelectedWaypoint then -- selected waypoint and previous selected waypoint are different
                            if true == startIsFinish then
                                if #waypointBlips == selectedWaypoint and 1 == lastSelectedWaypoint then -- split start/finish waypoint
                                    startIsFinish = false
                                    setStartToFinishBlips()
                                    lastSelectedWaypoint = 0
                                    raceCheckpoint = nil
                                    savedRaceName = nil
                                else
                                    setStartToFinishBlips()
                                    SetBlipColour(waypointBlips[selectedWaypoint], selectedBlipColor)
                                    lastSelectedWaypoint = selectedWaypoint
                                    createRaceCheckpoint(midCheckpoint, coord)
                                end
                            else
                                if 1 == selectedWaypoint and #waypointBlips == lastSelectedWaypoint then -- combine start and finish waypoints
                                    startIsFinish = true
                                    setStartToFinishBlips()
                                    lastSelectedWaypoint = 0
                                    raceCheckpoint = nil
                                    savedRaceName = nil
                                else
                                    setStartToFinishBlips()
                                    SetBlipColour(waypointBlips[selectedWaypoint], selectedBlipColor)
                                    lastSelectedWaypoint = selectedWaypoint
                                    createRaceCheckpoint(midCheckpoint, coord)
                                end
                            end
                        else -- selected waypoint and previous selected waypoint are the same
                            setStartToFinishBlips()
                            lastSelectedWaypoint = 0
                            raceCheckpoint = nil
                        end
                    end
                end
            else
                if lastSelectedWaypoint > 0 and IsControlJustReleased(2, 193) then -- space or X button or square button
                    RemoveBlip(waypointBlips[lastSelectedWaypoint])
                    table.remove(waypointBlips, lastSelectedWaypoint)

                    lastSelectedWaypoint = 0

                    DeleteCheckpoint(raceCheckpoint)
                    raceCheckpoint = nil

                    savedRaceName = nil

                    if #waypointBlips > 0 then
                        setStartToFinishBlips()
                        SetBlipRoute(waypointBlips[1], true)
                        SetBlipRouteColour(waypointBlips[1], blipRouteColor)
                    end
                end
            end
        elseif STATE_RACING == raceState then
            local player = PlayerPedId()
            local currentTime = GetGameTimer()
            local elapsedTime = currentTime - raceStart - raceDelay * 1000
            if elapsedTime < 0 then
                drawMsg(0.41, 0.50, ("Race starting in %05.2f seconds"):format(-elapsedTime / 1000.0), 0.7)

                if IsPedInAnyVehicle(player, false) then
                    FreezeEntityPosition(GetVehiclePedIsIn(player, false), true)
                    frozen = true
                end
            else
                if true == frozen then
                    if IsPedInAnyVehicle(player, false) then
                        local vehicle = GetVehiclePedIsIn(player, false)
                        FreezeEntityPosition(vehicle, false)
                        vehicleName = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
                    end
                    frozen = false
                end

                drawMsg(leftSide, 0.03, "Position", 0.5)
                if -1 == position then
                    drawMsg(rightSide, 0.03, "-- of --", 0.5)
                else
                    drawMsg(rightSide, 0.03, ("%d of %d"):format(position, numRacers), 0.5)
                end

                drawMsg(leftSide, 0.06, "Lap", 0.5)
                drawMsg(rightSide, 0.06, ("%d of %d"):format(currentLap, numLaps), 0.5)

                drawMsg(leftSide, 0.09, "Waypoint", 0.5)
                if true == startIsFinish then
                    drawMsg(rightSide, 0.09, ("%d of %d"):format(currentWaypoint, #waypointBlips), 0.5)
                else
                    drawMsg(rightSide, 0.09, ("%d of %d"):format(currentWaypoint - 1, #waypointBlips - 1), 0.5)
                end

                local minutes, seconds = minutesSeconds(elapsedTime)
                drawMsg(leftSide, 0.12, "Total time", 0.5)
                drawMsg(rightSide, 0.12, ("%02d:%05.2f"):format(minutes, seconds), 0.5)

                local lapTime = currentTime - lapTimeStart
                minutes, seconds = minutesSeconds(lapTime)
                drawMsg(leftSide, 0.20, "Lap time", 0.7)
                drawMsg(rightSide, 0.20, ("%02d:%05.2f"):format(minutes, seconds), 0.7)

                drawMsg(leftSide, 0.24, "Best lap", 0.7)
                if -1 == bestLapTime then
                    drawMsg(rightSide, 0.24, "- - : - -", 0.7)
                else
                    minutes, seconds = minutesSeconds(bestLapTime)
                    drawMsg(rightSide, 0.24, ("%02d:%05.2f"):format(minutes, seconds), 0.7)
                end

                if true == beginDNFTimeout then
                    local milliseconds = timeoutStart + DNFTimeout - currentTime
                    if milliseconds > 0 then
                        minutes, seconds = minutesSeconds(milliseconds)
                        drawMsg(leftSide, 0.28, "DNF time", 0.7)
                        drawMsg(rightSide, 0.28, ("%02d:%05.2f"):format(minutes, seconds), 0.7)
                    else -- DNF
                        raceState = STATE_IDLE
                        TriggerServerEvent("races:finish", raceIndex, numWaypointsPassed, -1, bestLapTime, vehicleName)
                        DeleteCheckpoint(raceCheckpoint)

                        SetBlipRoute(waypointBlips[1], true)
                        SetBlipRouteColour(waypointBlips[1], blipRouteColor)
                        speedo = false
                    end
                end

                if STATE_RACING == raceState then
                    if #(GetEntityCoords(player) - waypointCoord) < 10.0 then
                        DeleteCheckpoint(raceCheckpoint)

                        numWaypointsPassed = numWaypointsPassed + 1

                        if currentWaypoint < #waypointBlips then
                            currentWaypoint = currentWaypoint + 1
                        else
                            currentWaypoint = 1
                            lapTimeStart = currentTime
                            if -1 == bestLapTime or lapTime < bestLapTime then
                                bestLapTime = lapTime
                            end
                            if currentLap < numLaps then
                                currentLap = currentLap + 1
                            else
                                raceState = STATE_IDLE
                                TriggerServerEvent("races:finish", raceIndex, numWaypointsPassed, elapsedTime, bestLapTime, vehicleName)
                                SetBlipRoute(waypointBlips[1], true)
                                SetBlipRouteColour(waypointBlips[1], blipRouteColor)
                                speedo = false
                            end
                        end

                        if STATE_RACING == raceState then
                            local checkpointType
                            if true == startIsFinish then
                                local realWaypoint = currentWaypoint % #waypointBlips + 1
                                waypointCoord = GetBlipCoords(waypointBlips[realWaypoint])
                                checkpointType = (1 == realWaypoint and currentLap == numLaps) and finishCheckpoint or midCheckpoint
                                SetBlipRoute(waypointBlips[realWaypoint], true)
                                SetBlipRouteColour(waypointBlips[realWaypoint], blipRouteColor)
                            else
                                waypointCoord = GetBlipCoords(waypointBlips[currentWaypoint])
                                checkpointType = (#waypointBlips == currentWaypoint and currentLap == numLaps) and finishCheckpoint or midCheckpoint
                                SetBlipRoute(waypointBlips[currentWaypoint], true)
                                SetBlipRouteColour(waypointBlips[currentWaypoint], blipRouteColor)
                            end
                            createRaceCheckpoint(checkpointType, waypointCoord)
                        end
                    end
                end
            end
        elseif STATE_IDLE == raceState then
            local pedCoord = GetEntityCoords(PlayerPedId())
            for index, start in pairs(starts) do
                if #(pedCoord - GetBlipCoords(start.blip)) < 10.0 then
                    local msg = "Press [E] or right DPAD to join "
                    if nil == start.savedRaceName then
                        msg = msg .. "private race "
                    else
                        msg = msg .. (true == start.publicRace and "public" or "private")
                        msg = msg .. " race '" .. start.savedRaceName .. "' "
                    end
                    msg = msg .. ("owned by %s : %d lap(s).\n"):format(start.owner, start.laps)
                    drawMsg(0.34, 0.50, msg, 0.7)
                    if IsControlJustReleased(0, 51) then -- E or DPAD RIGHT
                        TriggerServerEvent('races:join', index)
                    end
                    break
                end
            end
        end

        if true == speedo then
            local speed = GetEntitySpeed(PlayerPedId())
            drawMsg(0.37, 0.91, ("%05.2f"):format(speed * 3.6), 0.7)
            drawMsg(0.41, 0.91, "kph", 0.7)
            drawMsg(0.57, 0.91, ("%05.2f"):format(speed * 2.2369363), 0.7)
            drawMsg(0.61, 0.91, "mph", 0.7)
        end
    end
end)
