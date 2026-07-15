--[=====[
[[SND Metadata]]
version: 1.4.3
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

import("System")
import("System.Numerics")

local tp_error = false
local interactioncount = 0
local targetName = nil
local debug = true
local FISHER_TARGET_LEVEL = 90
local no_of_retainers = 2

local hunt_log_queue_active = false --SET THIS MANUALLY

function HasFishAndLeves()
    return false --!will need to check inventory for black sole and the rest and leves
end

function DoOceanFishing() --get AH or vermaxion or FUTA fishing functionality
    yield("/e [QSTCC_Ret+FSH(IF)] ! Ocean fishing to come in a future update.")
    RelogNext()
end

function IsPluginEnabled(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name or plugin.Name == name then
            return plugin.IsLoaded
        end
    end
    return false
end

function PlayerIsAvailable()
    if Entity.Player and Player.Available and not Entity.Player.IsCasting and not Svc.Condition[45] and not Svc.Condition[51] and not Svc.Condition[58] and not Svc.Condition[78] and not Svc.Condition[50] then
        return true
    else
        return false
    end
end

function FisherLevelReached()
    return PlayerIsAvailable() and Player.GetJob(18).Level >= FISHER_TARGET_LEVEL
end

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
        sleep(0.1)
        yield("/click JournalDetail Initiate")
    end
    yield('/waitaddon "SelectYesno"')
    if Addons.GetAddon("SelectYesno").Ready then
        sleep(0.1)
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
    until PlayerIsAvailable() and not Svc.Condition[26]

    local character_open_attempts = 0
    repeat
        if PlayerIsAvailable() and not Svc.Condition[26] then
            yield("/character")
        end
        sleep(0.25)
        character_open_attempts = character_open_attempts + 1
    until Addons.GetAddon("Character").Ready or character_open_attempts >= 40

    if not Addons.GetAddon("Character").Ready then
        yield("/echo [QSTCC_Ret+FSH(I_F) EquipRecommendedGear: Character addon never opened after " .. character_open_attempts .. " attempts, aborting.")
        return
    end

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
    if not PlayerIsAvailable() then
        return false
    end
    
    local currentPos = Entity.Player.Position
    
    -- Handle nil position and combat/casting states
    if currentPos == nil or not PlayerIsAvailable() or Entity.Player.IsInCombat then --i really hope nothing will periodically trigger these while the toon is still stuck
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
    { addon = "JournalResult", command = function() sleep(0.1) yield("/click JournalResult Decline") end },
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

    if not PlayerIsAvailable() or Player.Job == nil then
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
            if PlayerIsAvailable() and Player.Job then
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
local quests_needed = {"311", "313", "314", "697", "1106", "921", "693", "696", "1134", "1107", "1108", "3843"} --no 1433 ill-venture(limsa) because henchman will do it
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

-- RelogNext's rotation-pass tracking has to survive across relogs, and this whole script
-- re-executes fresh (fresh Lua locals) on every "onlogin" trigger firing on the next character
-- -- so "have we already been all the way around" can't live in a local, it needs a file.
-- Svc.PluginInterface.ConfigDirectory resolves to THIS running instance's own SND config folder
-- (same mechanism SND itself uses internally), so this works correctly across separate
-- multi-boxed clients each with their own Dalamud data root, not just the default %appdata% one.
local rotation_state_file = Svc.PluginInterface.ConfigDirectory.FullName .. "\\qstcc_retfsh_if_rotation_state.txt"

local function ReadRotationStartCID()
    local file = io.open(rotation_state_file, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return tonumber(content)
end

local function WriteRotationStartCID(cid)
    local file = io.open(rotation_state_file, "w")
    if file then
        file:write(tostring(cid))
        file:close()
    end
end

local function ClearRotationState()
    os.remove(rotation_state_file)
end

-- Usage: RelogNext()
-- Finds the current character's CID in AutoRetainer's registered character list and relogs
-- into whichever character is next in that list. Stops (returns false, no relog issued) once
-- the next character in line would be the one this rotation pass started on, so a full roster
-- gets processed exactly once instead of cycling forever.
-- Uses /ays relog (-> MultiMode.Relog) directly rather than the PluginState.Relog IPC method:
-- that IPC call gates on CanAutoLogin(), which requires being logged OUT at the title screen,
-- so it always rejects when called while playing (confirmed against the installed AR build).
function RelogNext()
    if not Entity.Player then
        yield("/echo [QSTCC_Ret+FSH(I_F) RelogNext: no local player, aborting.")
        return false
    end

    local current_cid = Entity.Player.ContentId
    local registered_cids = IPC.AutoRetainer.GetRegisteredCharacters()

    local current_index = nil
    for i = 0, registered_cids.Count - 1 do
        if registered_cids[i] == current_cid then
            current_index = i
            break
        end
    end

    if current_index == nil then
        yield("/echo [QSTCC_Ret+FSH(I_F) RelogNext: current character (CID " .. tostring(current_cid) .. ") is not registered in AutoRetainer.")
        return false
    end

    local pass_start_cid = ReadRotationStartCID()
    if pass_start_cid == nil then
        pass_start_cid = current_cid
        WriteRotationStartCID(pass_start_cid)
        if debug then
            yield("/echo [QSTCC_Ret+FSH(I_F) RelogNext: starting new rotation pass at CID " .. tostring(pass_start_cid))
        end
    end

    local next_index = (current_index + 1) % registered_cids.Count
    local next_cid = registered_cids[next_index]

    if next_cid == pass_start_cid then
        yield("/echo [QSTCC_Ret+FSH(I_F) RelogNext: full rotation complete, every character has been processed. Stopping.")
        ClearRotationState()
        return false
    end

    local next_char = IPC.AutoRetainer.GetOfflineCharacterData(next_cid)
    local next_char_name = next_char.Name .. "@" .. next_char.World

    if debug then
        yield("/echo [QSTCC_Ret+FSH(I_F) RelogNext: currently index " .. current_index .. "/" .. (registered_cids.Count - 1) .. ", next is " .. next_char_name)
    end

    yield('/ays relog ' .. next_char_name)
    if debug then
        yield("/echo [QSTCC_Ret+FSH(I_F) RelogNext: relog issued for " .. next_char_name)
    end
    return true
end

function Henchman_IsBusy()
    if henchman_is_busy_subscriber == nil then
        local methods = Svc.PluginInterface:GetType():GetMethods()
        local boolType = luanet.make_array(Type, { Type.GetType("System.Boolean") })
        local method = nil
        for i = 0, methods.Length - 1 do
            local m = methods[i]
            if m.Name == "GetIpcSubscriber" and m.IsGenericMethodDefinition and m:GetGenericArguments().Length == 1 then
                method = m:MakeGenericMethod(boolType)
                break
            end
        end
        if method == nil then return false end

        local ok, subscriber = pcall(function()
            return method:Invoke(Svc.PluginInterface, luanet.make_array(Object, { "Henchman.IsBusy" }))
        end)
        if not ok or subscriber == nil then return false end
        henchman_is_busy_subscriber = subscriber
    end

    local ok, result = pcall(function() return henchman_is_busy_subscriber:InvokeFunc() end)
    if not ok then return false end
    return result
end

--[[###################################################################################################################################
###########           ####             ####           #####   ###            ####                   ###################################
###########   ############   ##############   ######   ####   ###   #######   ###########   ###########################################
###########   ############   ##############   #####    ####   ###   ######   ############   ###########################################
###########           ####   ##############         #######   ###           #############   ###########################################
###################   ####   ##############   ####   ######   ###   #####################   ###########################################
###################   ####   ##############   #####   #####   ###   #####################   ###########################################
###########           ####             ####   ######   ####   ###   #####################   ###########################################
#####################################################################################################################################]]




if not debug then
    yield("/dps wloadall") --this is for Dhog Potato System window placement
end

IPC.Questionable.ClearQuestPriority()
for _, questId in ipairs(quests_needed) do
    IPC.Questionable.AddQuestPriority(questId)
end

UpdateCompletedQuests()
local all_quests_complete = AllQuestsComplete()

repeat
    sleep(0.613)
until PlayerIsAvailable()

yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] Main loop entry: DTR exists=" .. tostring(Addons.GetAddon("_DTR").Exists) .. " hunt_log_queue_active=" .. tostring(hunt_log_queue_active) .. " all_quests_complete=" .. tostring(all_quests_complete))
if hunt_log_queue_active then
    yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] hunt_log_queue_active is TRUE -- main loop will NOT run at all. Set it to false to resume normal automation.")
end

while Addons.GetAddon("_DTR").Exists and not hunt_log_queue_active do
    sleep(0.615)
    local ok_retainer_count, retainer_count = pcall(function()
        return IPC.AutoRetainer.GetOfflineCharacterData(Entity.Player.ContentId).RetainerData.Count
    end)
    yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] tick: PlayerAvail=" .. tostring(PlayerIsAvailable())
        .. " all_quests_complete=" .. tostring(all_quests_complete)
        .. " QstRunning=" .. tostring(IPC.Questionable.IsRunning())
        .. " QuestId=" .. tostring(IPC.Questionable.GetCurrentQuestId())
        .. " RetainerCount=" .. tostring(ok_retainer_count and retainer_count or "ERR")
        .. " HenchmanBusy=" .. tostring(Henchman_IsBusy())
        .. " GCRank=" .. tostring(Player.GCRankImmortalFlames)
        .. " PosStuck=" .. tostring(CheckPosStuck()))
    if all_quests_complete and IPC.Questionable.IsRunning() and IPC.Questionable.GetCurrentQuestId() ~= "1433" then
        yield("/qst stop")
    end
    if not PlayerIsAvailable() then
        yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: player not available, skipping tick.")
        -- Player busy/transitioning (casting, cutscene, loading, etc.) -- skip this tick entirely
        -- rather than let a stale/transient read of retainer count or Henchman_IsBusy() fall
        -- through to an unrelated branch (e.g. relogging away from a character that still needs
        -- retainer/Henchman work done).
    elseif not all_quests_complete then
        yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: quest handling.")
        UpdateCompletedQuests()
        all_quests_complete = AllQuestsComplete()
        --local hunt_target = MatchHuntObjective(QuestText())
            -- Overworld mob hunting
        if Addons.GetAddon("PvpWelcome").Ready then
            yield('/callback PvpWelcome true -1')
        end
        if not IPC.Questionable.IsRunning() and not Svc.Condition[34] and not Svc.Condition[56] and not all_quests_complete then
            AddonHandler(addonConfigs)
            sleep(0.306)
            yield("/qst start")
        end
        local counter = 0
        repeat --cycle wait replacement with check for questId
            sleep(0.497)
            counter = counter + 1
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
        if CheckPosStuck() and PlayerIsAvailable() then
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
            elseif TerritoryType() == 128 and questId == "693" and not IPC.Questionable.IsQuestAccepted("693") then
                MoveAndInteract("Blanmhas")
                yield('/waitaddon "SelectString"')
                yield('/send NUMPAD0')
                yield('/send NUMPAD0')
                yield('/waitaddon "SelectYesno"')
                if Addons.GetAddon("SelectYesno").Ready then
                    sleep(0.1)
                    yield("/click SelectYesno Yes")
                end
                sleep(1.305)
                while not PlayerIsAvailable() do
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
                        sleep(0.1)
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
                        sleep(0.1)
                        yield("/click SelectYesno Yes")
                    end
                end
            end
            if PlayerIsAvailable() and not Svc.Condition[26] and not Svc.Condition[34] and not Svc.Condition[56] and not IPC.Lifestream.IsBusy() and not all_quests_complete then --pretty much hail merry attempt
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
    elseif (IPC.AutoRetainer.GetOfflineCharacterData(Entity.Player.ContentId).RetainerData.Count < no_of_retainers or Henchman_IsBusy()) then --need to make more retainers than currently have
        yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: retainer/henchman.")
        repeat
            sleep(0.859)
        until PlayerIsAvailable() 

        if IsPluginEnabled("Vermaxion") then
            yield('/xldisableplugin "Vermaxion"') --vermaxxion is useful for many things but can trigger on login and prevent henchman from working
        end
        IPC.Questionable.AddQuestPriority("1433") --ill-gained venture (limsa)
        if not Henchman_IsBusy() then
            yield("/henchman RetainerVocate "..tostring(no_of_retainers).." FSH MRD true") --can be changed to whatever you need
        end
        if IPC.Questionable.IsQuestAccepted("1433") and not IPC.Questionable.IsQuestComplete("1433") and not IPC.Questionable.IsRunning() then
            yield("/qst start")
        end
        if IPC.Questionable.IsQuestComplete("1433") and IPC.Questionable.IsRunning() and Henchman_IsBusy() then
            yield("/qst stop")
            yield("/ad stop")
        end
        if CheckPosStuck() then
            sleep(5.861)
            if CheckPosStuck() then --don't stop it at summoning bell
                yield("/henchman Stop")
            end
        end
    elseif not FisherLevelReached() and Player.GetJob(18).Level >= 30 and HasFishAndLeves() then --fisher leves in Costa via ChilledLeves
            yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: fisher leves.")
            repeat
                sleep(0.678)
            until PlayerIsAvailable()
            sleep(2.73)

            local job_swap_attempts = 0
            local job_swapped = SwapJobFromArmoury(18)
            while not job_swapped and job_swap_attempts < 3 do
                job_swap_attempts = job_swap_attempts + 1
                if debug then
                    yield("/echo [QSTCC_Ret+FSH(I_F) Fisher job swap failed, retrying (" .. job_swap_attempts .. "/3)...")
                end
                sleep(2)
                job_swapped = SwapJobFromArmoury(18)
            end

            if job_swapped then
                yield("/chilledleves start")

                -- ChilledLeves exposes no IPC and no "still running" flag we can read from SND, so
                -- progress is inferred from Fisher level: relies on ChilledLeves' own worklist
                -- (pre-populated by hand, shared across characters via its plugin config) for which
                -- leves to grab/turn in -- it does NOT catch fish, so the worklist only advances as
                -- far as already-stocked catch allows. ~15 min with no level gain is treated as
                -- "nothing left this character can turn in right now" and we move on.
                local last_level = Player.GetJob(18).Level
                local stagnant_checks = 0
                while Addons.GetAddon("_DTR").Exists and not FisherLevelReached() and stagnant_checks < 30 do
                    sleep(30)
                    AddonHandler(addonConfigs)
                    local current_level = Player.GetJob(18).Level
                    if current_level > last_level then
                        last_level = current_level
                        stagnant_checks = 0
                    else
                        stagnant_checks = stagnant_checks + 1
                    end
                end

                yield("/chilledleves stop")
                if debug then
                    yield("/echo [QSTCC_Ret+FSH(I_F) Fisher leveling paused at level " .. tostring(Player.GetJob(18).Level) .. " (target " .. FISHER_TARGET_LEVEL .. ").")
                end
                sleep(1.734)
                RelogNext()
            else
                yield("/echo [QSTCC_Ret+FSH(I_F) Fisher job swap failed after " .. job_swap_attempts .. " retries, skipping relog this pass.")
            end
    elseif os.date("!*t").hour % 2 == 1 and os.date("!*t").min < 12 then
        yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: ocean fishing window.")
        if os.date("!*t").min >= 6 then
            DoOceanFishing()
        end
    elseif Player.GCRankImmortalFlames < 9 then --for hunt log !add command/IPC as QST companion updates
        yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: GC rank hunt log, rank=" .. tostring(Player.GCRankImmortalFlames))
        repeat
            sleep(0.678)
        until PlayerIsAvailable()
        sleep(2.73)
        local job_swap_attempts = 0
        local job_swapped = SwapJobFromArmoury(3, 21)
        while not job_swapped and job_swap_attempts < 3 do
            job_swap_attempts = job_swap_attempts + 1
            if debug then
                yield("/echo [QSTCC_Ret+FSH(I_F) Job swap failed, retrying (" .. job_swap_attempts .. "/3)...")
            end
            sleep(2)
            job_swapped = SwapJobFromArmoury(3, 21)
        end

        if job_swapped then
            sleep(1.734)
            RelogNext()
            while Addons.GetAddon("_DTR").Exists and Player.GCRankImmortalFlames < 9 do
                sleep(10.679)
            end
        else
            yield("/echo [QSTCC_Ret+FSH(I_F) Job swap failed after " .. job_swap_attempts .. " retries, skipping relog this pass.")
        end
    else
        yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: else (no tasks) -- relogging.")
        sleep(3)
        RelogNext()
    end
end