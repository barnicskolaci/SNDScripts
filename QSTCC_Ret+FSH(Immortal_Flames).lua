--[=====[
[[SND Metadata]]
version: 1.3.1
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
    return ToDoListRowText(20101)
end

function LeveText()
    return ToDoListRowText(22001)
end

-- _ToDoList shows up to 5 tracked entries at once, each in its own row container.
-- Row containers are 20101 / 20201 / 20301 / 20401 / 20501, and clicking row N maps to callback index N-1.
local ToDoListRows = {20101, 20201, 20301, 20401, 20501}

function ToDoListRowText(rowId)
    if not Addons.GetAddon("_ToDoList").Exists then
        return ""
    end
    local todo = Addons.GetAddon("_ToDoList")
    if todo:GetNode(1, rowId, 6).IsVisible then
        return todo:GetNode(1, rowId, 6).Text
    elseif todo:GetNode(1, rowId, 7).IsVisible then
        return todo:GetNode(1, rowId, 7).Text
    else
        return ""
    end
end

-- Leve objective rows (e.g. "Bloodshore Snipper: 1/1") live under container IDs 22001-22005.
local LeveObjectiveRows = {22001, 22002, 22003, 22004, 22005}

-- Returns a plain array of mob names pulled from the leve objective rows, e.g.
-- {"Bloodshore Snipper", "Apkallu Caller", "Bloodshore Eyesore", "Unsightly Buffalo"}
function GetLeveObjectiveTargets()
    local targets = {}
    for _, rowId in ipairs(LeveObjectiveRows) do
        local text = ToDoListRowText(rowId)
        if text ~= "" then
            local name = text:match("^(.-)%s*:%s*%d+/%d+") or text
            table.insert(targets, name)
        end
    end
    return targets
end

-- Cycles /target through every mob name currently listed as a leve objective.
function TargetLeveObjectives()
    local targets = GetLeveObjectiveTargets()
    for _, name in ipairs(targets) do
        if debug then
            yield("/echo [QSTCC_Ret+FSH(I_F) Debug: Targeting leve objective \"" .. name .. "\"")
        end
        yield("/target " .. name)
        sleep(0.2)
        yield("/rsr manual")
        yield("/vbm ai on")
    end
    return targets
end

-- Usage: FindToDoListRow("trial guildleve") -- case-insensitive substring match
-- Returns the 0-based row index (for ClickToDoListRow) of the first matching entry, or nil.
function FindToDoListRow(matchText)
    matchText = matchText:lower()
    for i, rowId in ipairs(ToDoListRows) do
        local text = ToDoListRowText(rowId)
        if text ~= "" and text:lower():find(matchText, 1, true) then
            if debug then
                yield("/echo [QSTCC_Ret+FSH(I_F) Debug: Found ToDoList match \"" .. text .. "\" in row " .. tostring(i - 1))
            end
            return i - 1
        end
    end
    return nil
end

function ClickToDoListRow(rowIndex)
    if debug then
        yield("/echo [QSTCC_Ret+FSH(I_F) Debug: Clicking _ToDoList row " .. tostring(rowIndex))
    end
    yield('/callback _ToDoList true 7 ' .. rowIndex .. ' 0 74')
end

-- Usage: StartGuildLeveFromToDoList("trial guildleve")
-- Finds a matching entry in the _ToDoList tracker, clicks it to open the Journal to
-- that leve's page, then initiates it. Returns true if it got as far as clicking Initiate.
function StartGuildLeveFromToDoList(matchText)
    local rowIndex = FindToDoListRow(matchText)
    if rowIndex == nil then
        if debug then
            yield("/echo [QSTCC_Ret+FSH(I_F) Debug: No ToDoList entry matched \"" .. matchText .. "\".")
        end
        return false
    end

    ClickToDoListRow(rowIndex)
    sleep(0.095)
    if not Addons.GetAddon("Journal").Ready then
        yield("/send J")
    end
    yield('/waitaddon "JournalDetail"')
    if Addons.GetAddon("JournalDetail").Ready then
        yield("/click JournalDetail Initiate")
    end
    yield('/waitaddon "SelectYesno"')
    if Addons.GetAddon("SelectYesno").Ready then
        yield("/click SelectYesno Yes")
    end
    return true
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
            Engines.Native.Run("/echo [QSTCC_Ret+FSH(I_F) Debug: Teleport error detected.")
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
        yield("/echo [QSTCC_Ret+FSH(I_F) Debug: Checking if player is close to (" .. x .. ", " .. y .. ", " .. z .. ") with delta^2 " .. deltasquared .. " - Result: " .. tostring(result))
    end
    return result
end

function EquipRecommendedGear()
    if debug then
        yield("/echo [QSTCC_R+FSH(I_F)]: Equipping recommended gear.")
    end
    repeat
        sleep(0.1)
    until Entity.Player and Player.Available and not Entity.Player.IsCasting and not Svc.Condition[26]

    repeat
        yield("/character")
        sleep(0.1)
    until Addons.GetAddon("Character").Ready

    repeat
        if Addons.GetAddon("Character").Ready then
            yield("/callback Character true 12")
        end
        sleep(0.1)
    until Addons.GetAddon("RecommendEquip").Ready

    repeat
        yield("/character")
        sleep(0.1)
    until not Addons.GetAddon("Character").Ready

    repeat
        if Addons.GetAddon("RecommendEquip").Ready then
            yield("/callback RecommendEquip true 0")
        end
        sleep(0.1)
    until not Addons.GetAddon("RecommendEquip").Ready
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
    while not (Entity.Target and Entity.Target.Name == target) and TargetAttempts < 10 do
        sleep(0.207)
        yield('/target '.. target)
        TargetAttempts = TargetAttempts + 1
    end
    if Entity.Target and Entity.Target.Name == target then
        IPC.vnavmesh.PathfindAndMoveTo(Entity.Target.Position, false)
        local mvAttempts = 0
        while Entity.Target and Entity.Target.DistanceTo > 3 and mvAttempts < 100 do
            sleep(0.101)
            if not IPC.vnavmesh.IsRunning() then
                IPC.vnavmesh.PathfindAndMoveTo(Entity.Target.Position, false)
            end
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
    { addon = "PvpWelcome"},
    { addon = "GuildLeve", command = function() yield("/send NUMPAD0") yield("/send NUMPAD0") end }
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
            yield('/send DECIMAL')
            yield('/send DECIMAL')
            yield('/send DECIMAL')
        end
        ::skip_addon::
    end
end

function HardTarget()
    yield('/vbm cfg aiconfig forbidactions false')
    sleep(0.103)
    yield("/rsr manual")
    yield('/vbm ai on')
    if debug then
        yield("/echo [QST Comp Comp] Debug: HardTarget function called.")
    end
    if not Player.Entity.Target or not Svc.Targets.Target or Svc.Targets.Target:IsHostile() == false then
        if debug then
            yield("/echo [QST Comp Comp] Debug: Checking conditions for HardTarget.")
        end
      yield('/send TAB')
      if Addons.GetAddon("_EnemyList").Ready then
        yield("/callback _EnemyList true 12 0 0")
      end
      sleep(1.004)
    end
    sleep(1.005)

    if (Svc.Condition[56] or Svc.Condition[34]) and Player.Entity.Target then
        if (Svc.Targets.Target and Svc.Targets.Target:IsHostile() == true) or (tostring(Player.Entity.Target.Type):match("^EventObj")) then
            IPC.vnavmesh.PathfindAndMoveTo(Entity.Target.Position, false)
        end
    end
end

local hunt_objective_targets = {
}

function MatchHuntObjective(text)
    for prefix, creature in pairs(hunt_objective_targets) do
        if text:sub(1, #prefix) == prefix then
            return creature
        end
    end
    return nil
end

function SwapJobFromArmoury(...)
    local targetJobIds = {...}
    if #targetJobIds == 0 then
        yield("/echo [QSTCC_Ret+FSH(I_F) SwapJobFromArmoury: no job IDs given.")
        return false
    end

    if not Player.Available or Player.Job == nil then
        yield("/echo [QSTCC_Ret+FSH(I_F) SwapJobFromArmoury: Player.Job not available.")
        return false
    end

    for _, jobId in ipairs(targetJobIds) do
        if Player.Job.Id == jobId then
            EquipRecommendedGear()
            return true
        end
    end

    local InventoryType = luanet.import_type("FFXIVClientStructs.FFXIV.Client.Game.InventoryType")
    if InventoryType == nil then
        yield("/echo [QSTCC_Ret+FSH(I_F) SwapJobFromArmoury: failed to resolve InventoryType.")
        return false
    end

    local armoury = Inventory.ArmoryMainHand
    if armoury == nil then
        yield("/echo [QSTCC_Ret+FSH(I_F) SwapJobFromArmoury: armoury chest unavailable.")
        return false
    end

    for i = 0, armoury.Count - 1 do
        local item = armoury[i]
        if item and not item.IsEmpty then
            item:MoveItemSlotToSlot(InventoryType.EquippedItems, 0)
            sleep(0.5)
            if Player.Available and Player.Job then
                for _, jobId in ipairs(targetJobIds) do
                    if Player.Job.Id == jobId then
                        EquipRecommendedGear()
                        return true
                    end
                end
            end
        end
    end

    yield("/echo [QSTCC_Ret+FSH(I_F) SwapJobFromArmoury: no armoury item equipped the requested job.")
    return false
end

--MRD 1, 5, 10; Halatali, Pvp, Cutter's cry, Swiftperch and Costa Del Sol leves, FSH + Ocean Fishing quests
local quests_needed = {"311", "313", "314", "697", "1106", "921", "693", "696", "1134", "1107", "1108", "3843" }
local completed_quests = {}

-- Marks any not-yet-logged quest in quests_needed as complete if Questionable now reports it done.
function UpdateCompletedQuests()
    for _, questId in ipairs(quests_needed) do
        if not completed_quests[questId] and IPC.Questionable.IsQuestComplete(questId) then
            completed_quests[questId] = true
        end
    end
end

function AllQuestsComplete()
    for _, questId in ipairs(quests_needed) do
        if not completed_quests[questId] then
            return false
        end
    end
    return true
end

--[[#########################################
###########  SCRIPT START  ##################
###########################################]]

if not debug then
    yield("/dps wloadall") --this is for Dhog Potato System window placement
end

IPC.Questionable.ClearQuestPriority()
for _, questId in ipairs(quests_needed) do
    IPC.Questionable.AddQuestPriority(questId)
end

UpdateCompletedQuests()
local all_quests_complete = AllQuestsComplete()

while Addons.GetAddon("_DTR").Exists do
    if not all_quests_complete then
        UpdateCompletedQuests()
        all_quests_complete = AllQuestsComplete()
        --local hunt_target = MatchHuntObjective(QuestText())
            -- Overworld mob hunting
        if Addons.GetAddon("PvpWelcome").Ready then
            yield('/callback "PvpWelcome" true -1')
        end
        if not IPC.Questionable.IsRunning() and not Svc.Condition[34] and not Svc.Condition[56] then
            AddonHandler(addonConfigs)
            sleep(0.306)
            yield("/qst start")
        end
        local counter = 0
        repeat --cycle wait replacement with check for questId
            sleep(1.267)
            if (Svc.Condition[34] or Svc.Condition[56]) then
                if Svc.Condition[26] then
                    yield('/vbm cfg aiconfig ForbidMovement False')
                else
                    yield('/vbm cfg aiconfig ForbidMovement True')
                end
            end
        until counter >= 4
        --if hunt_target then
        if Entity.Player and not Entity.Player.IsInCombat and not Svc.Condition[26] and not Svc.Condition[34] and not Svc.Condition[56] then
            yield('/vbm ai off')
            yield('/vbm cfg aiconfig forbidactions true')
        end
        if TerritoryType() == 1042 then --some start stone vigil for some reason -- that reason was qstcc starting after being deleted. reload snd to fix
            yield("/xa leaveduty")
        end
        if CheckPosStuck() and Entity.Player and not Entity.Player.IsCasting then
            local counter = 0
            --quest-related stuck checks
            local questId = IPC.Questionable.GetCurrentQuestId()
            if questId == "311" and QuestText():find("Marauders' Guild.", 1, true) then
                yield("/li Marauders")
                while IPC.Lifestream.IsBusy() and counter < 20 do
                    sleep(1.417)
                    counter = counter + 1
                end
                counter = 0
            elseif TerritoryType() == 128 and IsPlayerCloseTo(-12.4980955, 91.49984, -12.168484) then
                MoveAndInteract("Blanmhas")
                yield('/waitaddon "SelectString"')
                yield('/send NUMPAD0')
                yield('/send NUMPAD0')
                yield('/waitaddon "SelectYesno"')
                if Addons.GetAddon("SelectYesno").Ready then
                    yield("/click SelectYesno Yes")
                end
                sleep(1.305)
                while not Player.Available do
                    sleep(0.307)
                end
                sleep(1.309)
                MoveAndInteract("T'mokkri")
            elseif IPC.Questionable.IsQuestAccepted("693") and not IPC.Questionable.IsQuestComplete("693") then --leve handler
                if debug then
                    yield("/echo [QST Comp Comp] Debug: Attempting Swiftperch leve.")
                end
                if Entity.Target and Entity.Target.Name  == "Swygskyf" then
                    yield('/waitaddon "JournalDetail"')
                    if Addons.GetAddon("JournalDetail").Ready then
                        yield("/callback JournalDetail true 3 556")
                    end
                    IPC.vnavmesh.PathfindAndMoveTo(Vector3(604.7, 6.5, 482), false)
                    while IPC.vnavmesh.IsRunning() and counter < 20 do
                        sleep(1.437)
                        counter = counter + 1
                    end
                    counter = 0
                end
                if FindToDoListRow("Report to") then
                    if debug then
                        yield("/e [QSTCC_Ret+FSH(Immortal_FLames)]: Swiftperch battle leve started.")
                    end
                    while IPC.vnavmesh.IsRunning() and counter < 20 do
                        sleep(1.445)
                        counter = counter + 1
                    end
                    counter = 0
                    StartGuildLeveFromToDoList("Report to")
                    while IPC.vnavmesh.IsRunning() and counter < 20 do
                        sleep(1.449)
                        counter = counter + 1
                    end
                    sleep(0.447)
                    counter = 0
                    while not (Entity.Player and Entity.Player.IsInCombat) and counter < 20 do
                        sleep(1.450)
                        yield("/target crab")
                        yield("/rsr manual")
                        yield("/vnav movetarget")
                        counter = counter + 1
                    end
                    sleep(1)
                    counter = 0
                    while Entity.Player and Entity.Player.IsInCombat and counter < 20 do
                        sleep(1.455)
                        counter = counter + 1
                    end
                    counter = 0
                    yield('/waitaddon "SelectYesno"')
                    if Addons.GetAddon("SelectYesno").Ready then
                        yield("/click SelectYesno Yes")
                    end
                    MoveAndInteract("Swygskyf")
                end
            elseif IPC.Questionable.IsQuestAccepted("696") and not IPC.Questionable.IsQuestComplete("696") then
                if Entity.Target and Entity.Target.Name  == "Nahctahr" then
                    yield('/waitaddon "JournalDetail"')
                    if Addons.GetAddon("JournalDetail").Ready then
                        yield("/callback JournalDetail true 3 629")
                    end
                    IPC.vnavmesh.PathfindAndMoveTo(Vector3(514.7, 9.7, 376.2), false)
                    while IPC.vnavmesh.IsRunning() and counter < 20 do
                        sleep(1.488)
                        counter = counter + 1
                    end
                    counter = 0
                elseif IsPlayerCloseTo(514.724, 9.702966, 376.21405) or Addons.GetAddon("_ToDoList"):GetNode(1,4).IsVisible then
                    if not Addons.GetAddon("_ToDoList"):GetNode(1,4).IsVisible then 
                        StartGuildLeveFromToDoList("Report to") --leve handler
                    end
                    sleep(1)
                    local locationCoords = {
                        [1] = Vector3(525.38184, 9.357127, 366.5743),
                        [2] = Vector3(509.2259, 8.977512, 296.1835),
                        [3] = Vector3(448.5125, 13.319736, 311.14517),
                        [4] = Vector3(449.51196, 14.8454895, 363.89316),
                        [5] = Vector3(341.6311, 33.9868, 358.9881)
                    }

                    function MoveToNextLocation(n)
                        if debug then
                            yield("/e Locations visited(n): "..n)
                        end
                        local coords = locationCoords[n + 1]  -- n already visited, so head to the (n+1)th spot
                        if coords then
                            IPC.vnavmesh.PathfindAndMoveTo(coords, false)
                            if debug then
                                yield("/e Moving to "..tostring(coords))
                            end
                            sleep(0.145)
                            while IPC.vnavmesh.IsRunning() do
                                MoveAndInteract("Destination")
                                sleep(1)
                            end
                        end
                    end
                    local n = 0
                    while Addons.GetAddon("_ToDoList"):GetNode(1,4).IsVisible do
                        yield("/qst stop")
                        sleep(0.5)
                        MoveToNextLocation(n)
                        sleep(2)
                        TargetLeveObjectives()
                        while Entity.Player and Entity.Player.IsInCombat do
                            HardTarget()
                            sleep(1)
                        end
                        n = n + 1
                        if n == 6 then
                            n = 0
                        end
                    end
                    yield('/waitaddon "SelectYesno"')
                    if Addons.GetAddon("SelectYesno").Ready then
                        yield("/click SelectYesno Yes")
                    end
                end
            end
            if Entity.Player and not Entity.Player.IsCasting and Player.Available and not Svc.Condition[26] and not Svc.Condition[34] and not Svc.Condition[56] and not IPC.Lifestream.IsBusy() then --pretty much hail merry attempt
                yield("/vbm ai off")
                yield("/vbm ar clear")
                yield('/vbm cfg aiconfig ForbidMovement True')
                yield("/qst stop")
                yield("/send NUMPAD0")
                yield("/send NUMPAD0")
                yield("/send NUMPAD0")
                sleep(2.573)
                yield("/qst start")
                sleep(9.575)
                if CheckPosStuck() then
                    yield("/echo [QST Comp Comp] Debug: Standing still out of combat, reloading quest.")
                    yield("/qst reload")
                end
            end
        AddonHandler(addonConfigs)
        positionHistory = {}
        end
        -- CheckPosStuck() end
    elseif Player.GCRankImmortalFlames < 9 then --this is for hunt log, but it should ideally do fisher leves first
        SwapJobFromArmoury(3, 21)
        while Player.GCRankImmortalFlames < 9 do
            sleep(10.679)
        end
    end
end