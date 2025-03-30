--[[######################################
##      Temporary GameObject Turnin     ##
##            by Friendly               ##
##      using dhogGPT's Futa_GC         ##
##########################################

####################################################
##                  Description                   ##
####################################################

-- This is a temporary solution with hard coded waits without relying on gameobjects
-- This script goes to GC and does turnin, nothing else
-- Starts and stops deliveroo until your ventures do not increase 3 times in a row for consistency
-- Enables CBT expert delivery, but it is not required
-- Made primarily to use with Char Cycler

-- ###########
-- # CONFIGS #
-- #########]]

local enable_chat_logging = false -- Options: true = see chat logs, false = don't

-- #####################################
-- #  DON'T TOUCH ANYTHING BELOW HERE  #
-- # UNLESS YOU KNOW WHAT YOU'RE DOING #
-- #####################################


-- Teleporter("gc", "li") --!!!!replacing with below repeat till gameobject fix
yield("/li gc")
for i=1, 15 do
    yield("/wait 3")
end
PauseYesAlready()
yield("/cbt enable MaxGCRank")
if enable_chat_logging then
    yield("/echo CBT Expert Delivery on!")
end
empty_delivery_counter = 0
benture = GetItemCount(21072)
while empty_delivery_counter < 3 do --!!go till 3 empty.max deliveroo loops, if you think you need more, get a gc promotion or set it higher idc
    maxcheck = 0
    seals = (GetItemCount(20) + GetItemCount(21) + GetItemCount(22)) --20 = storm, 21 = serpent, 22 = flame
    if enable_chat_logging then
        yield("/echo Deliveroo started")
    end
    yield("/deliveroo e")
    yield("/wait 3") --deliveroo needs a few sec to get going even without gear
    repeat
        yield("/wait 0.1")
        maxcheck = maxcheck + 1
    until IsAddonReady("GrandCompanySupplyList") or maxcheck > 70
    maxcheck = 0
    while maxcheck < 50 do -- !!max 125 seconds of turnin, this is enough for full natural turnin even w/ low gc rank.
        yield("/wait 3") -- each turnin can take up to 2.5 sec
        maxcheck = maxcheck + 1
        if seals == (GetItemCount(20) + GetItemCount(21) + GetItemCount(22)) then
            maxcheck = maxcheck + 50
            if enable_chat_logging then
                yield("/echo No more seals received, moving on")
            end
        end
        seals = (GetItemCount(20) + GetItemCount(21) + GetItemCount(22))
    end
    for i=1, 10 do
            yield("/send ESCAPE")
            yield("/deliveroo d")
            yield("/wait 0.2")
    end
    if enable_chat_logging then
        yield("/echo Delivero stopped")
        yield("/echo Empty delivery counter is -> "..empty_delivery_counter)
    end

    if benture == GetItemCount(21072) then --nothing changed since last time we did the round. maybe we ned to exit but increase the cardinality just in case
        empty_delivery_counter = empty_delivery_counter + 1 --stop turnin if seals don't increase
        if enable_chat_logging then
            yield("/echo No more ventures received, Empty delivery counter is -> "..empty_delivery_counter)
        end
    else 
        empty_delivery_counter = 0
    end
    benture = GetItemCount(21072)
end
yield("/cbt disable MaxGCRank")
if enable_chat_logging then
    yield("/echo CBT Expert Delivery off")
end
RestoreYesAlready()