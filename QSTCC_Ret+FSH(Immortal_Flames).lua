--[=====[
[[SND Metadata]]
version: 1.0
triggers:
- onlogin
- onterritorychange
function_chat_filters:
  OnChatMessage:
    channels:
    - errormessage
    message_contains: Unable to teleport. Another teleport is already underway.
[[End Metadata]]
--]=====]

import("System.Numerics")

local tp_error = false
local interactioncount = 0
local targetName = nil
local debug = false

function TerritoryType()
    if Svc.ClientState.TerritoryType then
        return Svc.ClientState.TerritoryType
    end 
end

function QuestText()
    if not Addons.GetAddon("_ToDoList").Exists then
        return ""
    end
    if Addons.GetAddon("_ToDoList"):GetNode(1,20101,6).IsVisible then
        return Addons.GetAddon("_ToDoList"):GetNode(1,20101,6).Text
    elseif Addons.GetAddon("_ToDoList"):GetNode(1,20101,7).IsVisible then
        return Addons.GetAddon("_ToDoList"):GetNode(1,20101,7).Text
    else
        return ""
    end
end

function IsInSanctuary()
    if not Addons.GetAddon("_Exp").Exists then
        return false
    end
    return Addons.GetAddon("_Exp"):GetNode(1,3).IsVisible
end

function OnChatMessage()
    if tp_error == false then
        tp_error = true
        if debug then
            Engines.Native.Run("/echo [QST] Debug: Teleport error detected.")
        end
    end
end

function CloseCheck(a, b, tol) --tol is squared
    tol = tol or 4
    return ((a.X-b.X)^2 + (a.Y-b.Y)^2 + (a.Z-b.Z)^2) < tol
end

function IsPlayerCloseTo(x, y, z, deltasquared) --delta is squared
    if Entity.Player == nil or Entity.Player.Position == nil then
        return false
    end
    local p = Entity.Player.Position
    deltasquared = deltasquared or 4
    local result = CloseCheck(p, {X=x, Y=y, Z=z}, deltasquared)
    if debug then
        yield("/echo [QST] Debug: Checking if player is close to (" .. x .. ", " .. y .. ", " .. z .. ") with delta^2 " .. deltasquared .. " - Result: " .. tostring(result))
    end
    return result
end


-- Initialize position history

local positionHistory = {}

function CheckPosStuck()
    if not Entity.Player or not Player.Available then
        return false
    end
    
    local currentPos = Entity.Player.Position
    
    -- Handle nil position and combat/casting states
    if currentPos == nil or not Player.Available or Entity.Player.IsInCombat or Entity.Player.IsCasting then --i really hope nothing will periodically trigger these while the toon is still stuck
        positionHistory = {}
        return false
    end
    
    -- Add current position to history
    table.insert(positionHistory, currentPos)
    
    -- Keep only last 3 positions
    if #positionHistory > 3 then
        table.remove(positionHistory, 1)
    end
    
    -- Debug: yield position history
    if debug then
        yield("/echo Position History: " .. tostring(#positionHistory) .. " entries")
        for i, pos in ipairs(positionHistory) do
            yield("/echo [" .. i .. "] " .. tostring(pos))
        end
    end
    
    -- Check if we have 3 positions and they're all the same
    if #positionHistory == 3 then
        local pos1 = positionHistory[1]
        local pos2 = positionHistory[2]
        local pos3 = positionHistory[3]
        
        -- Compare Vector3 objects directly
        if CloseCheck(pos1, pos2, 2) and CloseCheck(pos2, pos3, 2) then
            yield("/echo Player is not moving anywhere.")
            return true
        end
    end
    
    return false
end        

function sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

function MoveAndInteract(target)
    if debug then
        yield("/echo [QST Comp Comp] Debug: Moving to and interacting with target: " .. target)
    end
    yield('/rsr off') -- this is needed cause qst companion turns it on and it prevents targetting
    yield('/vbm ar disable') --same
    yield('/target '.. target)
    local TargetAttempts = 0
    while not (Entity.Target and Entity.Target.Name == target) and TargetAttempts < 20 do
        sleep(0.100)
        TargetAttempts = TargetAttempts + 1
    end
    if Entity.Target and Entity.Target.Name == target then
        yield('/vnav movetarget')
        local mvAttempts = 0
        while Entity.Target and Entity.Target.DistanceTo > 3 and mvAttempts < 60 do
            sleep(0.101)
            mvAttempts = mvAttempts + 1
        end
        yield("/vnav stop")
        yield('/interact')
    end
end

local addonConfigs = {
    { addon = "TelepotTown", command = function() yield("/send ESCAPE") end }, --this might be fine, but needs testing; needs attention
    { addon = "Shop" }, --Dressed to Call: stuck on Buyback tab of shop
    { addon = "SelectYesno", condition = tp_error == false and function() return not IPC.Lifestream.IsBusy() end },
    { addon = "SelectString" },
    { addon = "JournalAccept" }, --qst stuck on war quest waiting to equip soul crystal
    { addon = "JournalResult", command = function() yield("/click JournalResult Decline") end },
    { addon = "JournalRewardItem" },
    { addon = "GrandCompanySupplyList" },
    { addon = "Description" }, --stuck on frontline info
    { addon = "Repair" },
    { addon = "GrandCompanyExchange" }, --stuck on GC exchange
    { addon = "PvpWelcome"}
}

function AddonHandler(addonConfigs)
    for _, config in ipairs(addonConfigs) do
        local Addon = config.addon
        local condition = config.condition

        -- Check custom condition if provided
        if condition and not condition() then
            goto skip_addon
        end

        if Entity.Player and Entity.Player.IsCasting then
            goto skip_addon
        end

        local attempts = 0
        local maxAttempts = config.maxAttempts or 3
        local waitBetween = config.waitBetween or 1.198

        while Addons.GetAddon(Addon).Ready and attempts < maxAttempts do
            if config.command then
                config.command()
                if debug then
                    yield("/echo [QST Comp Comp] Debug: Handling addon (custom): " .. Addon)
                end
            else
                if Addons.GetAddon(Addon).Ready then
                    -- Prefer callback when addon GUI is ready
                    yield('/callback "'.. Addon ..'" true -1')
                end
                if debug then
                    yield("/echo [QST Comp Comp] Debug: Handling addon: " .. Addon .. " (attempt " .. tostring(attempts+1) .. ")")
                end
            end

            attempts = attempts + 1
            sleep(waitBetween)
        end

        if Addons.GetAddon(Addon).Ready then -- Fallback: try to close with keys
            if debug then
                yield("/echo [QST Comp Comp] Warning: addon '" .. Addon .. "' still exists after " .. tostring(attempts) .. " attempts")
            end
            yield('/send ESCAPE')
            yield('/send DECIMAL')
        end
        ::skip_addon::
    end
end

function HardTarget()
    yield('/vbm cfg aiconfig forbidactions false')
    sleep(0.103)
    yield('/vbm ai on')
    if debug then
        yield("/echo [QST Comp Comp] Debug: HardTarget function called.")
    end
    if not Player.Entity.Target or not Svc.Targets.Target or Svc.Targets.Target:IsHostile() == false then
        if debug then
            yield("/echo [QST Comp Comp] Debug: Checking conditions for HardTarget.")
        end
      yield('/send TAB')
      sleep(1.004)
    end
    sleep(1.005)

    if (Svc.Condition[56] or Svc.Condition[34]) and Player.Entity.Target then
        if (Svc.Targets.Target and Svc.Targets.Target:IsHostile() == true) or (tostring(Player.Entity.Target.Type):match("^EventObj")) then
            yield('/vnav movetarget')
        end
    end
end

hunt_objective_targets = {
    ["Slay coeurl pups and collect coeurl pup whiskers."] = "Coeurl Pup",
    ["Slay antelope stags for their horns."] = "Antelope Stag",
    ["Slay ziz."] = "Ziz",
    ["Slay ice sprites and obtain their cores."] = "Ice Sprite",
}

function MatchHuntObjective(text)
    for prefix, creature in pairs(hunt_objective_targets) do
        if text:sub(1, #prefix) == prefix then
            return creature
        end
    end
    return nil
end

local quests_needed = {"1433", "693", "696", "1134", "1107", "1108" }

--[[#########################################
###########  SCRIPT START  ##################
###########################################]]

yield("/dps wloadall") --this is for Dhog Potato System window placement

while Addons.GetAddon("_DTR").Exists do
    --local hunt_target = MatchHuntObjective(QuestText())
        -- Overworld mob hunting
    if not IPC.Questionable.IsRunning() and not Svc.Condition[34] and not Svc.Condition[56] then
        AddonHandler(addonConfigs)
        sleep(0.306)
        yield("/qst start")
    end
    local counter_questId_343 = 0
    repeat --cycle wait replacement with check for questId 343
        sleep(1.267)
        counter_questId_343 = counter_questId_343 + 1
        if QuestText() == "Speak with the flame sergeant." and Entity.Player and Player.IsCasting then --lord of the inferno avoid tp=ing away
            MoveAndInteract("Flame Sergeant")
        end
        if (Svc.Condition[34] or Svc.Condition[56]) then
            if Svc.Condition[26] then
                yield('/vbm cfg aiconfig ForbidMovement False')
            else
                yield('/vbm cfg aiconfig ForbidMovement True')
            end
        end
    until counter_questId_343 >= 4
    if hunt_target then
    elseif Entity.Player and not Entity.Player.IsInCombat and not Svc.Condition[26] and not Svc.Condition[34] and not Svc.Condition[56] then
        yield('/vbm ai off')
        yield('/vbm cfg aiconfig forbidactions true')
    end
    if CheckPosStuck() and Entity.Player and not Entity.Player.IsCasting then

        --quest-related stuck checks
        local questId = IPC.Questionable.GetCurrentquestId()
        if TerritoryType() == 128 and IsPlayerCloseTo(-12.4980955 91.49984 -12.168484) then
            MoveAndInteract("Blanmhas")
            yield('/waitaddon "SelectString"')
            yield('/send NUMPAD0')
            yield('/send NUMPAD0')
            yield('/waitaddon "SelectYesno"')
            if Addons.GetAddon("SelectYesno").Ready then
                yield("/click SelectYesno Yes")
            end
        end

        AddonHandler(addonConfigs)
        positionHistory = {}
    end
    -- CheckPosStuck() end
end