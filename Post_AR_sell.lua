local mode = 3
--Modes 1 sell only, 2 sell and reprice, 0 don't do either, 3 forced

local zoneID = Svc.ClientState.TerritoryType
yield("/dps wloadall")

function WaitForLifestream()
    sekonds = 0
    yield("/echo Waiting on lifestream")
    while IPC.Lifestream.IsBusy() do
        --DEBUG
        --yield("/echo Waiting on lifestream -> "..sekonds)
        sekonds = sekonds + 1
        yield("/wait 1")
        if IsAddonExists("SelectYesno") then yield("/callback SelectYesno true 0") end --finally no need for configuring chars to use aetheryte tickets 
    end
    yield("/echo Lifestream completed")
end

function IsPlayerOccupied()

    if not Player.Available then
        return true
    end

    local occupiedFlags = {
        25, -- Occupied
        30, -- Occupied30
        33, -- Occupied33
        38, -- Occupied38
        39, -- Occupied39
        35, -- OccupiedInCutSceneEvent
        31, -- OccupiedInEvent
        32, -- OccupiedInQuestEvent
        50, -- OccupiedSummoningBell
        52, -- WatchingCutscene
        78, -- WatchingCutscene78
        45, -- BetweenAreas
        51, -- BetweenAreas51
        11, -- InThatPosition
        5,  -- Crafting
        40, -- ExecutingCraftingAction
        41, -- PreparingToCraft
        2,  -- Dead (Unconscious)
        6,  -- MeldingMateria
        7,  -- Gathering
        65, -- CarryingItem
        70, -- BeingMoved
        10, -- RidingPillion
        66, -- Mounting
        71, -- Mounting71
        15, -- ParticipatingInCustomMatch
        14, -- PlayingLordOfVerminion
        12, -- ChocoboRacing
        13, -- PlayingMiniGame
        18, -- Performing
        43, -- Fishing
        68, -- Transformed
        67, -- UsingHousingFunctions
    }

    local c = Svc.Condition
    for i = 1, #occupiedFlags do
        if c[occupiedFlags[i]] then
            return true
        end
    end

    return false
end

function IsAddonExists(name)
    return Addons.GetAddon(name).Exists
end
function sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

if IsAddonExists("ReturnerDialog") then
    yield("/callback ReturnerDialog true 1")
end

if zoneID ~= 129 then
    if mode ~= 3 then 
        mode = 2
    end
    yield("/li lim")
    WaitForLifestream()
    sleep(0.5)
end

--if Inventory.GetFreeInventorySlots() < 100 then
--    mode = 1
--end
if mode == 3 then
    yield("/ays m disable")
end
while not Player.Available do
    sleep(1.01)
end
sleep(3)
yield("/target Summoning Bell")
if mode ~= 0 then
        local counter = 0
        while Entity.Player.Target == nil or Entity.Player.Target.Name ~= "Summoning Bell" do
            Dalamud.Log("[RR processing] Targeting summoning bell")
            yield("/target Summoning Bell")
            sleep(0.5)
        end
        while not IsAddonExists("RetainerList") do
            yield("/target Summoning Bell")
            sleep(0.505)
            yield("/interact")
            sleep(1.1)
        end
    sleep(1.2)
    Dalamud.Log("[RR processing] Retainer Repricer")
    if mode == 1 then
        yield("/rr start sell")
    else
        yield("/rr start")
    end
    while IsAddonExists("RetainerList") do
        if counter < 16 then
            sleep(0.52)
            if IsAddonExists("RetainerList") or not IsPlayerOccupied() then
                counter = counter+1
            else
                counter = 0
            end
        else
            yield("/rr stop")
            yield("/callback RetainerList true -1")
            sleep(1)
            if mode == 3 then
                IPC.AutoRetainer.EnableMultiMode()
            end
            yield("/snd stop all")
        end
        sleep(2.51)
    end
    counter = 0
    while counter < 6 do
        sleep(1.53)
        if IsAddonExists("RetainerList") or not IsPlayerOccupied() then
            counter = counter+1
        else
            counter = 0
        end
    end
    if IsAddonExists("RetainerList") then
        yield("/callback RetainerList true -1")
    end
end

while not Player.Available do
    sleep(1.3)
end
if mode == 3 then
    IPC.AutoRetainer.EnableMultiMode()
end