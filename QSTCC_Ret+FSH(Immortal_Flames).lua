--[=====[
[[SND Metadata]]
version: 1.5.8
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

--[[###########
### CONFIGS ###
##############]]


local tp_error = false
local debug = false
local FISHER_TARGET_LEVEL = 90
local no_of_retainers = 2

local skip_main_loop = false --SET THIS MANUALLY to true for hunt log
--for retainer making, use QST Companion and leave this on false

--[[###########
## FUNCTIONS ##
#############]]

function MoveTo(x,y,z)
    local movecounter = 0
    IPC.vnavmesh.PathfindAndMoveTo(Vector3(x, y, z), false)
    while IPC.vnavmesh.IsRunning() and movecounter < 20 do
        sleep(1.437)
        movecounter = movecounter + 1
    end
end

function HasFishAndLeves()
    return true --!will need to check inventory for black sole and the rest and leves
end

-- Fires VERMAXION's manual engine start and waits out a bounded ceiling before moving on. SND has no
-- IPC wrapper for VERMAXION (only plugins with a purpose-built IPC.cs inside SND itself are callable
-- from Lua -- confirmed against SND's own IPCModule.cs), so there's no clean "voyage complete" signal
-- to poll; a real voyage is a fixed 15min fishing window plus travel/registration/cleanup overhead,
-- so 25 minutes covers it with margin. Swaps to Fisher and saves gearset slot 2 first so VERMAXION's
-- Fisher-gearset check has something to find -- still needs the character/account enabled and an
-- XADB fisher level set in VERMAXION's own config, which this can't do for you.
function DoOceanFishing()
    if true then
        RelogNext()
        return --take out when ready
    end
    local job_swapped = SwapJobFromArmoury(18)
    yield("/e [QSTCC_Ret+FSH(IF)] ! Starting ocean fishing via VERMAXION.")
    yield("/vmx run")
    local counter = 0
    repeat
        sleep(30)
        counter = counter + 1
    until IsPlayerAvailable() and counter >= 70
end

function IsPluginEnabled(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name or plugin.Name == name then
            return plugin.IsLoaded
        end
    end
    return false
end

function IsPlayerAvailable()

    if not Player.Available then
        return false
    end

    if Entity.Player.IsCasting then
        return false
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
            return false
        end
    end

    return true
end

function FisherLevelReached()
    return IsPlayerAvailable() and Player.GetJob(18).Level >= FISHER_TARGET_LEVEL
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

function GetLeveAllowances()
    local was_open = Addons.GetAddon("Journal").Ready
    if not was_open then
        yield("/send J")
        yield('/waitaddon "Journal"')
        sleep(0.1)
    end

    local allowances = nil
    if Addons.GetAddon("Journal").Ready then
        local text = Addons.GetAddon("Journal"):GetNode(1, 33, 35, 2).Text
        allowances = tonumber(text:match("%d+"))
    end

    if not was_open then
        yield('/send ESCAPE')
    end

    return allowances
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
    until IsPlayerAvailable() and not Svc.Condition[26]

    local character_open_attempts = 0
    repeat
        if IsPlayerAvailable() and not Svc.Condition[26] then
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
    if not IsPlayerAvailable() then
        return false
    end
    
    local currentPos = Entity.Player.Position
    
    -- Handle nil position and combat/casting states
    if currentPos == nil or not IsPlayerAvailable() or Entity.Player.IsInCombat then --i really hope nothing will periodically trigger these while the toon is still stuck
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

    if not IsPlayerAvailable() or Player.Job == nil then
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
            if IsPlayerAvailable() and Player.Job then
                for _, jobId in ipairs(targetJobIds) do
                    if Player.Job.Id == jobId then
                        EquipRecommendedGear()
                        return true
                    end
                end
            end
        end
    end

    -- No owned armoury weapon covers any of the requested jobs -- buy one starter weapon for
    -- the first requested job (BuyAndEquipPlayerMainHand/BuyRetainerGear, defined further down
    -- this file) and retry the equip check once, rather than giving up outright.
    local job_details = GetJobDataForJobId(targetJobIds[1])
    if job_details then
        yield("/echo [QSTCC_Ret+FSH(I_F) SwapJobFromArmoury: no armoury item for job " .. targetJobIds[1] .. ", buying " .. job_details.jobName .. " starter weapon.")
        if BuyAndEquipPlayerMainHand(job_details) and IsPlayerAvailable() and Player.Job then
            for _, jobId in ipairs(targetJobIds) do
                if Player.Job.Id == jobId then
                    EquipRecommendedGear()
                    return true
                end
            end
        end
    end

    yield("/echo [QSTCC_Ret+FSH(I_F) SwapJobFromArmoury: no armoury item equipped the requested job.")
    return false
end

--MRD 1, 5, 10; Halatali, Pvp, Cutter's cry, Swiftperch and Costa Del Sol leves, FSH + Ocean Fishing quests
local quests_needed = {"311", "313", "314", "697", "1106", "921", "693", "696", "1134", "1107", "1108", "3843"} --no 1433 ill-venture(limsa), handled separately in the retainer-creation branch below
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

-- Usage: RelogNext() or RelogNext(true)
-- Finds the current character's CID in AutoRetainer's registered character list and relogs
-- into whichever character is next in that list. By default, stops (returns false, no relog
-- issued, logs out) once the next character in line would be the one this rotation pass
-- started on, so a full roster gets processed exactly once instead of cycling forever. Pass
-- loop=true to keep the toons looping instead: on wraparound it just relogs into the next
-- character (restarting the roster) rather than stopping, forever.
-- Uses /ays relog (-> MultiMode.Relog) directly rather than the PluginState.Relog IPC method:
-- that IPC call gates on CanAutoLogin(), which requires being logged OUT at the title screen,
-- so it always rejects when called while playing (confirmed against the installed AR build).
function RelogNext(loop)
    if not Entity.Player then
        yield("/echo [QSTCC_Ret+FSH(I_F) RelogNext: no local player, aborting.")
        return false
    end

    local current_cid = Entity.Player.ContentId
    local registered_cids = IPC.AutoRetainer.GetRegisteredCharacters()
    local loop = loop or false

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
        if not loop then
            yield("/echo [QSTCC_Ret+FSH(I_F) RelogNext: full rotation complete, every character has been processed. Stopping.")
            ClearRotationState()
            yield("/logout")
            sleep(3)
            if Addons.GetAddon("SelectYesno").Ready then
                sleep(0.1)
                yield("/click SelectYesno Yes")
            end
            return false
        end
        if debug then
            yield("/echo [QSTCC_Ret+FSH(I_F) RelogNext: full rotation complete, looping back to the start of the roster.")
        end
        -- Deliberately does NOT ClearRotationState() -- pass_start_cid stays pinned to the
        -- original roster-start CID across every future relog, so each subsequent lap keeps
        -- wrapping back through this same branch instead of drifting to a new "start".
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

--[[###################################################################################################################################
##  RetainerMaker: native SND reimplementation of Henchman's RetainerVocate feature (see SNDScripts/RetainerMaker.lua for the        ##
##  full design notes -- decompiled Henchman.dll v2.0.6.6 flow, known behavior gap around race/gender/clan/look selection, etc.)      ##
###################################################################################################################################]]

-- Per-job starter gear (unchanged ARR "Weathered" items) and the ClassJob sheet
-- name SelectString shows when assigning a retainer's job. Item IDs and vendor
-- categorization carried over as-is from the original Retainer Maker.lua.
local RETAINER_JOB_DATA = {
    GLA = { class = "DoW", itemID = 1601, jobName = "Gladiator" },    -- Weathered Shortsword
    PGL = { class = "DoW", itemID = 1680, jobName = "Pugilist" },     -- Weathered Hora
    MRD = { class = "DoW", itemID = 1749, jobName = "Marauder" },     -- Weathered War Axe
    LNC = { class = "DoW", itemID = 1819, jobName = "Lancer" },       -- Weathered Spear
    ROG = { class = "DoW", itemID = 7952, jobName = "Rogue" },        -- Weathered Daggers
    ARC = { class = "DoW", itemID = 1889, jobName = "Archer" },       -- Weathered Shortbow
    CNJ = { class = "DoM", itemID = 1995, jobName = "Conjurer" },     -- Weathered Cane
    THM = { class = "DoM", itemID = 2055, jobName = "Thaumaturge" },  -- Weathered Scepter
    ACN = { class = "DoM", itemID = 2142, jobName = "Arcanist" },     -- Weathered Grimoire
    MIN = { class = "DoL", itemID = 2519, jobName = "Miner" },        -- Weathered Pickaxe
    BTN = { class = "DoL", itemID = 2545, jobName = "Botanist" },     -- Weathered Hatchet
    FSH = { class = "DoL", itemID = 2571, jobName = "Fisher" },       -- Weathered Fishing Rod
}

function GetRetainerJobDetails(job)
    return RETAINER_JOB_DATA[job]
end

-- Reverse-maps a ClassJob RowId to its base class's RETAINER_JOB_DATA entry -- used by
-- SwapJobFromArmoury to buy a starter weapon when the player owns no armoury piece for the
-- requested job. Advanced jobs (e.g. WAR/21) map back to their base class (MRD) since that's
-- the weapon category the vendor actually sells; equipping it auto-resolves to the advanced
-- job once unlocked.
local JOB_ID_TO_BASE_ABBR = {
    [1] = "GLA", [19] = "GLA",
    [2] = "PGL", [20] = "PGL",
    [3] = "MRD", [21] = "MRD",
    [4] = "LNC", [22] = "LNC",
    [29] = "ROG", [30] = "ROG",
    [5] = "ARC", [23] = "ARC",
    [6] = "CNJ", [24] = "CNJ",
    [7] = "THM", [25] = "THM",
    [26] = "ACN", [27] = "ACN", [28] = "ACN",
    [16] = "MIN",
    [17] = "BTN",
    [18] = "FSH",
}

function GetJobDataForJobId(jobId)
    local abbr = JOB_ID_TO_BASE_ABBR[jobId]
    if not abbr then
        return nil
    end
    return GetRetainerJobDetails(abbr)
end

-- Generic SelectString entry finder, by exact visible text. Reuses the node-ID
-- chain QSTCC_RET's own henchman-stuck-check fallback already established as
-- correct for the CURRENT SelectString addon layout (root -> 1 -> list
-- component 3 -> row containers 51001-51008 -> text node 2), NOT the old
-- vac_functions-era GetNodeText("SelectString", 2, i, 3) addressing, which
-- targeted a different (older) helper's own component-index convention.
function FindSelectStringEntry(matchText)
    local selectStringAddon = Addons.GetAddon("SelectString")
    if not selectStringAddon.Ready then
        return nil
    end
    for containerId = 51001, 51008 do
        local text = selectStringAddon:GetNode(1, 3, containerId, 2).Text
        if text == "" then
            break
        end
        if text == matchText then
            return containerId - 51000
        end
    end
    return nil
end

-- Ported from Henchman.Helpers.NameGenerator (decompiled Henchman.dll v2.0.6.6,
-- internal static class NameGenerator) -- this is the ACTUAL algorithm Henchman
-- uses whenever no explicit retainer name is configured: GeneratePrefixMiddle(1,3)
-- (one random Prefix syllable + 1-2 random Middle syllables, straight
-- concatenation, no separators) followed by one random gendered Suffix. No length
-- cap, no forbidden-substring filtering, no capitalization step (Prefix entries
-- are already capitalized, Middle/Suffix entries lowercase) -- reproduced exactly
-- as decompiled, not the old script's own from-scratch generator.
--
-- Henchman picks masculine vs. feminine purely from Configuration.RetainerGender
-- (a setting IT controls, since it also fires the race/gender selection event).
-- This library doesn't select gender at all (see file header), so which suffix
-- list gets used is a random coin flip instead -- purely cosmetic. FFXIV's
-- retainer-naming step does not enforce name/gender concordance (confirmed:
-- Henchman submits config-derived names blind and never checks for a mismatch;
-- no validation of that kind exists anywhere in its retainer-creation flow).
math.randomseed(os.time())

local RETAINER_NAME_PREFIX = {
    "A", "Ad", "Al", "Am", "An", "Ar", "Be", "Bl", "Br", "Ch",
    "Cl", "De", "Ed", "El", "Em", "Fa", "Fl", "Fr", "Gr", "Jo",
    "Ki", "La", "Ma", "Na", "O", "Ol", "Or", "Pa", "Re", "Sh",
    "Si", "Ta", "Th", "Tr", "Va"
}
local RETAINER_NAME_MIDDLE = {
    "ad", "al", "am", "an", "ar", "as", "at", "el", "en", "er",
    "es", "et", "ei", "il", "in", "ir", "ol", "on", "or", "os",
    "ur"
}
local RETAINER_NAME_FEMININE_SUFFIX = {
    "a", "ina", "ie", "ara", "eera", "aea", "osa", "ya", "tha", "aya",
    "ana", "ielle", "ia", "ora", "iss", "ea", "ene", "ice", "ra", "ka",
    "nira", "wen", "elle", "lina", "wyn", "lora", "vina", "yn"
}
local RETAINER_NAME_MASCULINE_SUFFIX = {
    "an", "nik", "anar", "ton", "or", "ant", "er", "dir", "ius", "ric",
    "no", "ien", "ard", "len", "ian", "en", "o", "as", "on", "rus",
    "us"
}

-- Mirrors NameGenerator.GeneratePrefixMiddle(1, 3): C#'s Random.Next(1,3) is
-- exclusive of its upper bound (always 1 or 2) -- Lua's math.random(1,2) is the
-- direct equivalent (inclusive on both ends).
local function GeneratePrefixMiddle()
    local syllables = math.random(1, 2)
    local text = RETAINER_NAME_PREFIX[math.random(#RETAINER_NAME_PREFIX)]
    for _ = 1, syllables do
        text = text .. RETAINER_NAME_MIDDLE[math.random(#RETAINER_NAME_MIDDLE)]
    end
    return text
end

function GenerateRetainerName()
    if math.random(0, 1) == 0 then
        return GeneratePrefixMiddle() .. RETAINER_NAME_MASCULINE_SUFFIX[math.random(#RETAINER_NAME_MASCULINE_SUFFIX)]
    else
        return GeneratePrefixMiddle() .. RETAINER_NAME_FEMININE_SUFFIX[math.random(#RETAINER_NAME_FEMININE_SUFFIX)]
    end
end

-- Moves to and interacts with the Retainer Vocate ("Frydwyb", Limsa) and hires
-- one new retainer slot. Returns false once the game reports no slots are left
-- (SelectYesno never appears and the player becomes interactable again instead
-- of a chargen screen opening) -- the practical, Lua-reachable equivalent of
-- Henchman's CheckForRetainerEntitlement (MaxRetainerEntitlement == RetainerCount),
-- which reads RetainerManager natively and has no SND Lua equivalent.
function GoToRetainerVocateAndHire()
    MoveAndInteract("Frydwyb")
    yield('/waitaddon "SelectString"')
    sleep(0.1) -- settle delay before firing a callback into a just-opened addon
    if not Addons.GetAddon("SelectString").Ready then
        yield("/echo [RetainerMaker] SelectString never opened after interacting with the Retainer Vocate.")
        return false
    end

    local hireIdx = FindSelectStringEntry("Hire a retainer.")
    if hireIdx == nil then
        yield("/echo [RetainerMaker] Could not find \"Hire a retainer.\" in the Retainer Vocate's SelectString.")
        yield('/callback "SelectString" true -1')
        return false
    end
    yield('/callback "SelectString" true ' .. hireIdx)

    local wait_attempts = 0
    repeat
        sleep(0.2)
        wait_attempts = wait_attempts + 1
    until Addons.GetAddon("SelectYesno").Ready or IsPlayerAvailable() or wait_attempts >= 50

    if not Addons.GetAddon("SelectYesno").Ready then
        if debug then
            yield("/echo [RetainerMaker] No more retainer slots available on this character.")
        end
        return false
    end

    sleep(0.1)
    yield("/click SelectYesno Yes")
    yield('/waitaddon "_CharaMakeTitle"')
    return Addons.GetAddon("_CharaMakeTitle").Ready
end

-- Drives one retainer through character creation from _CharaMakeTitle to a
-- named, closed RetainerCharacter window. Deliberately skips race/gender/clan/
-- look (see file header) and accepts the panel's default -- goes straight from
-- _CharaMakeTitle to firing _CharaMakeFeature's confirmed-working Finish (100).
function CreateSingleRetainer()
    sleep(1) -- extra settle time, mirrors the original script's post-CharaMakeTitle safety wait

    yield('/waitaddon "_CharaMakeFeature"')
    sleep(0.1) -- settle delay before firing a callback into a just-opened addon
    if not Addons.GetAddon("_CharaMakeFeature").Ready then
        yield("/echo [RetainerMaker] _CharaMakeFeature never became ready, aborting this retainer.")
        return false
    end
    yield('/callback "_CharaMakeFeature" true 100')

    -- The game runs a short, currently-unverified confirmation/personality flow
    -- before naming. Drain any SelectYesno prompts generically (always Yes)
    -- rather than hardcoding an exact popup count/order that may not match the
    -- current character-creation UI (see file header -- this is the same UI
    -- overhaul that split race/gender/clan/look into separate addons).
    local drain_attempts = 0
    while not Addons.GetAddon("SelectString").Ready and not Addons.GetAddon("InputString").Ready and drain_attempts < 30 do
        if Addons.GetAddon("SelectYesno").Ready then
            sleep(0.1)
            yield("/click SelectYesno Yes")
        end
        sleep(0.3)
        drain_attempts = drain_attempts + 1
    end

    if Addons.GetAddon("SelectString").Ready then
        yield('/callback "SelectString" true 0') -- personality choice is cosmetic only, first option
        yield('/waitaddon "SelectYesno"')
        if Addons.GetAddon("SelectYesno").Ready then
            sleep(0.1)
            yield("/click SelectYesno Yes")
        end
    end

    yield('/waitaddon "InputString"')
    sleep(0.1) -- settle delay before firing a callback into a just-opened addon
    if not Addons.GetAddon("InputString").Ready then
        yield("/echo [RetainerMaker] InputString never appeared, aborting this retainer.")
        return false
    end

    local named = false
    local name_attempts = 0
    while not named and name_attempts < 10 do
        local retainer_name = GenerateRetainerName()
        if debug then
            yield("/echo [RetainerMaker] Attempting to name retainer " .. retainer_name)
        end
        yield('/callback "InputString" true 0 ' .. retainer_name)
        yield('/waitaddon "SelectYesno"')
        if Addons.GetAddon("SelectYesno").Ready then
            sleep(0.1)
            yield("/click SelectYesno Yes")
        end
        sleep(0.3)
        if not Addons.GetAddon("InputString").Ready then
            named = true
        else
            name_attempts = name_attempts + 1
        end
    end
    if not named then
        yield("/echo [RetainerMaker] Failed to name retainer after " .. name_attempts .. " attempts.")
        return false
    end

    yield('/waitaddon "RetainerCharacter"')
    if Addons.GetAddon("RetainerCharacter").Ready then
        sleep(0.3)
        yield('/callback "RetainerCharacter" true -1')
    end
    return true
end

-- Creates up to `amount` new retainers on the current character. Stops early
-- (returns the count actually created) once GoToRetainerVocateAndHire reports
-- no slots are left. Mirrors Henchman's CreateRetainers loop.
function CreateRetainers(amount)
    local created = 0
    for _ = 1, amount do
        if not GoToRetainerVocateAndHire() then
            break
        end
        if CreateSingleRetainer() then
            created = created + 1
        end
        sleep(0.5)
    end
    return created
end

-- Targets the correct Weathered-gear vendor for `job_details.class`, buys one
-- of `job_details.itemID`, and returns true on success. Finds the item by ID
-- inside the live Shop addon (AtkValues[2] = entry count, AtkValues[441 + i] =
-- item ID for entry i, per ECommons' AddonMaster.Shop) rather than trusting a
-- fixed shop-slot index -- more robust than the original script's hardcoded
-- store_location if the vendor's item ordering ever changes.
function BuyRetainerGear(job_details)
    if job_details.class == "DoW" or job_details.class == "DoM" then
        MoveAndInteract("Faezghim")
    else
        MoveAndInteract("Syneyhil")
    end

    yield('/waitaddon "SelectIconString"')
    sleep(0.1) -- settle delay before firing a callback into a just-opened addon
    if not Addons.GetAddon("SelectIconString").Ready then
        yield("/echo [RetainerMaker] SelectIconString never opened for the " .. job_details.jobName .. " vendor.")
        return false
    end
    -- Faezghim (DoW/DoM vendor) offers two categories; Syneyhil (DoL vendor)
    -- offers one. This index split is carried over from the original script --
    -- unverified for the single-category DoL case since SND has no Lua-exposed
    -- way to read SelectIconString's real entry count (unlike Shop's AtkValues).
    local icon = (job_details.class == "DoW") and 0 or 1
    yield('/callback "SelectIconString" true ' .. icon)

    yield('/waitaddon "SelectString"')
    sleep(0.1) -- settle delay before firing a callback into a just-opened addon
    if Addons.GetAddon("SelectString").Ready then
        yield('/callback "SelectString" true 0')
    end

    yield('/waitaddon "Shop"')
    sleep(0.1) -- settle delay before firing a callback into a just-opened addon
    if not Addons.GetAddon("Shop").Ready then
        yield("/echo [RetainerMaker] Shop never opened for " .. job_details.jobName .. ", aborting purchase.")
        return false
    end

    local shop = Addons.GetAddon("Shop")
    local numEntries = tonumber(shop:GetAtkValue(2).ValueString) or 0
    local slot = nil
    for i = 0, numEntries - 1 do
        local itemId = tonumber(shop:GetAtkValue(441 + i).ValueString)
        if itemId == job_details.itemID then
            slot = i
            break
        end
    end

    if slot == nil then
        yield("/echo [RetainerMaker] Could not find item " .. job_details.itemID .. " (" .. job_details.jobName .. ") in the shop list.")
        yield('/callback "Shop" true -1')
        return false
    end

    yield('/callback "Shop" true 0 ' .. slot .. ' 1')
    
    sleep(0.1)
    yield('/waitaddon "SelectYesno"') --there's a 2nd one here in case you need to confirm the purchase due to being unable to equip
    if Addons.GetAddon("SelectYesno").Ready then
        sleep(0.1)
        yield("/click SelectYesno Yes")
    end
    sleep(0.1)
    yield('/waitaddon "SelectYesno"')
    if Addons.GetAddon("SelectYesno").Ready then
        sleep(0.1)
        yield("/click SelectYesno Yes")
    end

    sleep(0.3)
    yield('/waitaddon "Shop"')
    if Addons.GetAddon("Shop").Ready then
        yield('/callback "Shop" true -1')
    end

    sleep(0.3) -- settle delay before firing a callback into a just-opened addon
    yield('/waitaddon "SelectString"')
    if Addons.GetAddon("SelectString").Ready then
        -- Farewell/close dialogue option -- index carried over from the
        -- original script, unverified against the current text. QSTCC_RET's
        -- own AddonHandler will mop up a stray SelectString here if this is wrong.
        yield('/callback "SelectString" true 5')
    end
    return true
end

-- Equips `itemID` into the currently-open RetainerCharacter's main-hand slot,
-- via a direct inventory-slot move -- same technique as QSTCC_RET's own
-- armoury job-swap and Questionable's own EquipItem.cs, no UI simulation.
function EquipRetainerWeapon(itemID)
    local InventoryType = luanet.import_type("FFXIVClientStructs.FFXIV.Client.Game.InventoryType")
    local item = Inventory.GetInventoryItem(itemID)
    if not item then
        yield("/echo [RetainerMaker] Item " .. itemID .. " not found in inventory, cannot equip.")
        return false
    end
    item:MoveItemSlotToSlot(InventoryType.RetainerEquippedItems, 0)
    sleep(0.3)
    return true
end

-- Buys one starter main-hand weapon for job_details and equips it onto the PLAYER character
-- (not a retainer) -- reuses BuyRetainerGear's vendor-shopping flow since the purchase lands
-- in the acting player's own inventory regardless of who it's ultimately equipped on, then
-- moves it into EquippedItems (mirrors EquipRetainerWeapon's RetainerEquippedItems move above).
function BuyAndEquipPlayerMainHand(job_details)
    yield("/li hawkers")
    repeat
        sleep(4)
    until not IPC.Lifestream.IsBusy() and IsPlayerAvailable()
    if not BuyRetainerGear(job_details) then
        return false
    end
    local InventoryType = luanet.import_type("FFXIVClientStructs.FFXIV.Client.Game.InventoryType")
    local item = Inventory.GetInventoryItem(job_details.itemID)
    if not item then
        yield("/echo [QSTCC_Ret+FSH(I_F) BuyAndEquipPlayerMainHand: purchased item " .. job_details.itemID .. " not found in inventory.")
        return false
    end
    item:MoveItemSlotToSlot(InventoryType.EquippedItems, 0)
    sleep(0.5)
    return true
end

-- Finds the RetainerList position of the first retainer AutoRetainer reports
-- with no class assigned yet (Job == 0). Reads AutoRetainer's own cached
-- retainer data rather than RetainerManager natively (not exposed to Lua) --
-- QSTCC_RET already relies on this same IPC call/field for its own retainer count checks.
function FindUnassignedRetainerIndex()
    local data = IPC.AutoRetainer.GetOfflineCharacterData(Entity.Player.ContentId).RetainerData
    for i = 0, data.Count - 1 do
        if data[i].Job == 0 then
            return i
        end
    end
    return nil
end

-- Assigns a class and equips the starter weapon for each entry in `jobs`
-- ({ {job = "FSH", amount = N}, ... }), against whichever unassigned retainers
-- are sitting in RetainerList (created by CreateRetainers beforehand). Mirrors
-- Henchman's AssignRetainerClassEquipMain step-for-step, including its
-- "Quit." exit back to RetainerList between retainers rather than a blind close.
--[[function AssignRetainerClassesAndEquip(jobs) -- "chunk"]:1035: <goto continue_retainer> at line 983 jumps into the scope of local 'jobIdx'
    MoveAndInteract("Summoning Bell")
    yield('/waitaddon "RetainerList"')
    sleep(0.1) -- settle delay before firing a callback into a just-opened addon
    if not Addons.GetAddon("RetainerList").Ready then
        yield("/echo [RetainerMaker] RetainerList never opened, aborting class assignment.")
        return
    end

    for _, retainer in ipairs(jobs) do
        local job_details = GetRetainerJobDetails(retainer.job)
        if not job_details then
            yield("/echo [RetainerMaker] Unknown job '" .. tostring(retainer.job) .. "', skipping.")
        else
            for _ = 1, retainer.amount do
                local pos = FindUnassignedRetainerIndex()
                if pos == nil then
                    yield("/echo [RetainerMaker] No unassigned retainer left for " .. job_details.jobName .. ".")
                    break
                end

                yield('/callback "RetainerList" true 2 ' .. pos .. ' 0 0')
                yield('/waitaddon "SelectString"')
                sleep(0.4) -- RetainerList -> SelectString is a fresh open, but pad it anyway for consistency

                local assignIdx = FindSelectStringEntry("Assign retainer class.")
                if assignIdx == nil then
                    yield("/echo [RetainerMaker] Could not find \"Assign retainer class.\" for retainer at position " .. pos .. ".")
                    goto continue_retainer
                end
                yield('/callback "SelectString" true ' .. assignIdx)
                -- SelectString stays open/visible across this transition (its content is refreshed
                -- in place to the job list), so /waitaddon can return instantly without the new
                -- content having actually populated yet -- pad with an explicit settle delay.
                yield('/waitaddon "SelectString"')
                sleep(0.4)

                local jobIdx = FindSelectStringEntry(job_details.jobName)
                if jobIdx == nil then
                    yield("/echo [RetainerMaker] Could not find job '" .. job_details.jobName .. "' in the class list.")
                    goto continue_retainer
                end
                yield('/callback "SelectString" true ' .. jobIdx)
                yield('/waitaddon "SelectYesno"')
                if Addons.GetAddon("SelectYesno").Ready then
                    sleep(0.1)
                    yield("/click SelectYesno Yes")
                end

                -- Same same-addon-refresh risk as above -- SelectString may stay visible under/behind
                -- SelectYesno rather than closing, so pad here too before reading its content.
                yield('/waitaddon "SelectString"')
                sleep(0.4)
                local gearIdx = FindSelectStringEntry("View retainer attributes and gear. (No main arm equipped)")
                if gearIdx == nil then
                    yield("/echo [RetainerMaker] Could not find the retainer gear entry after class assignment.")
                    goto continue_retainer
                end
                yield('/callback "SelectString" true ' .. gearIdx)
                yield('/waitaddon "RetainerCharacter"')
                if Addons.GetAddon("RetainerCharacter").Ready then
                    sleep(0.5)
                    EquipRetainerWeapon(job_details.itemID)
                    sleep(0.3)
                    yield('/callback "RetainerCharacter" true -1')
                end

                -- Highest-risk transition in this whole flow: fires right after closing
                -- RetainerCharacter (/callback "RetainerCharacter" true -1) with no intervening
                -- game-state change to guarantee /waitaddon actually blocked -- this is exactly
                -- the two-synthetic-events-with-no-frame-delay shape that causes a native UI
                -- reentrancy crash (see reference_ui_reentrancy_crashes). Pad generously.
                yield('/waitaddon "SelectString"')
                sleep(0.5)
                local quitIdx = FindSelectStringEntry("Quit.")
                if quitIdx then
                    yield('/callback "SelectString" true ' .. quitIdx)
                end

                ::continue_retainer::
                sleep(0.5)
            end
        end
    end

    yield('/waitaddon "RetainerList"')
    sleep(0.1) -- settle delay before firing a callback into a just-opened addon
    if Addons.GetAddon("RetainerList").Ready then
        yield('/callback "RetainerList" true -1')
    end
end]]

-- Entry point: creates retainers for the CURRENT character to cover `jobs`
-- ({ {job = "FSH", amount = 2}, ... }), buys and equips each job's starter
-- weapon, and assigns classes. Does NOT touch venture questing -- QSTCC_RET's
-- existing Questionable-driven branch already owns that (quest "1433").
-- Mirrors Henchman's RunFullCreation minus StartVentureQuest (out of scope --
-- see file header). Returns the number of retainers actually created.
function RunRetainerCreation(jobs)
    local total_amount = 0
    for _, retainer in ipairs(jobs) do
        total_amount = total_amount + retainer.amount
    end

    local created = CreateRetainers(total_amount)
    if created > 0 then
        for _, retainer in ipairs(jobs) do
            local job_details = GetRetainerJobDetails(retainer.job)
            if job_details then
                BuyRetainerGear(job_details)
            end
        end
        AssignRetainerClassesAndEquip(jobs)
    elseif debug then
        yield("/echo [RetainerMaker] No retainers were created (no free slots), skipping gear/class assignment.")
    end

    return created
end

function MakeGearsets()
    if Player.GetGearset(1).ClassJob ~= 18 then
        local job_swapped = SwapJobFromArmoury(18)
        if job_swapped then
            yield("/gs save 2")
        end
        yield('/waitaddon "SelectYesno"')
        if Addons.GetAddon("SelectYesno").Ready then
            sleep(0.1)
            yield("/click SelectYesno Yes")
        end
    sleep(1.626)
    end
    if Player.GetGearset(0).ClassJob ~= 3 and Player.GetGearset(1).ClassJob ~= 21 then
        local job_swapped = SwapJobFromArmoury(3, 21)
        if job_swapped then
            yield("/gs save 1")
        end
        yield('/waitaddon "SelectYesno"')
        if Addons.GetAddon("SelectYesno").Ready then
            sleep(0.1)
            yield("/click SelectYesno Yes")
        end
        sleep(1.200)
    end
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
until IsPlayerAvailable()

yield("/li")
repeat
    sleep(1.323)
until not IPC.Lifestream.IsBusy() and IsPlayerAvailable()

if skip_main_loop then
    if debug then
        yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] skip_main_loop is TRUE -- main loop will NOT run at all. Set it to false to resume normal automation.")
    end
else
    if debug then
        yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] Main loop entry: DTR exists=" .. tostring(Addons.GetAddon("_DTR").Exists) .. " skip_main_loop=" .. tostring(skip_main_loop) .. " all_quests_complete=" .. tostring(all_quests_complete))
    end
end

if all_quests_complete then --make gearsets for FSH and MRD cause some plugins NEED it
    MakeGearsets()
end

while (Addons.GetAddon("_DTR").Exists or Entity.Player) and not skip_main_loop do
    sleep(0.615)
    local ok_retainer_count, retainer_count = pcall(function()
        return IPC.AutoRetainer.GetOfflineCharacterData(Entity.Player.ContentId).RetainerData.Count
    end)
    if debug then
        yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] tick: PlayerAvail=" .. tostring(IsPlayerAvailable())
            .. " all_quests_complete=" .. tostring(all_quests_complete)
            .. " QstRunning=" .. tostring(IPC.Questionable.IsRunning())
            .. " QuestId=" .. tostring(IPC.Questionable.GetCurrentQuestId())
            .. " RetainerCount=" .. tostring(ok_retainer_count and retainer_count or "ERR")
            .. " GCRank=" .. tostring(Player.GCRankImmortalFlames)
            .. " PosStuck=" .. tostring(CheckPosStuck()))
    end
    if all_quests_complete and IPC.Questionable.IsRunning() and IPC.Questionable.GetCurrentQuestId() ~= "1433" then
        yield("/qst stop")
    end
    if not IsPlayerAvailable() then
        if debug then
            yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: player not available, skipping tick.")
        end
        -- Player busy/transitioning (casting, cutscene, loading, etc.) -- skip this tick entirely
        -- rather than let a stale/transient read of retainer count fall through to an unrelated
        -- branch (e.g. relogging away from a character that still needs retainer work done).
    elseif not all_quests_complete then
        if debug then
            yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: quest handling.")
        end
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
        if CheckPosStuck() and IsPlayerAvailable() then
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
                while not IsPlayerAvailable() do
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
                    MoveTo(604.7, 6.5, 482)
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
                    MoveTo(514.7, 9.7, 376.2)
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
                                sleep(1.273)
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
            if IsPlayerAvailable() and not Svc.Condition[26] and not Svc.Condition[34] and not Svc.Condition[56] and not IPC.Lifestream.IsBusy() and not all_quests_complete then --pretty much hail merry attempt
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
    elseif IPC.AutoRetainer.GetOfflineCharacterData(Entity.Player.ContentId).RetainerData.Count < no_of_retainers then --!needs fixing, including functions
        if debug then
            yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: retainer creation.")
        end
        repeat
            sleep(0.859)
        until IsPlayerAvailable()

        IPC.Questionable.AddQuestPriority("1433")
        if  Svc.ClientState.TerritoryType ~= 129 and Svc.ClientState.TerritoryType ~= 138 then
            yield("/li limsa")
        end
        while not IPC.Questionable.IsQuestComplete("1433") do
            if CheckPosStuck() and IsPlayerAvailable() and IsPlayerCloseTo(-145.8, 18.2, 19.3, 16) and not Entity.Target then
                yield("/qst start")
            end
            sleep(4)
            if IPC.Questionable.IsQuestComplete("1433") then
                yield("/qst stop")
            end
        end

        -- RunRetainerCreation (see the RetainerMaker block above) blocks synchronously until every
        -- requested retainer is created, geared and class-assigned -- unlike the old Henchman call,
        -- there's no "kick it off, then poll across ticks" background state to track here.
        local current_retainer_count = IPC.AutoRetainer.GetOfflineCharacterData(Entity.Player.ContentId).RetainerData.Count
        RunRetainerCreation({ { job = "FSH", amount = no_of_retainers - current_retainer_count } }) --can be changed to whatever job(s) you need
    elseif Player.GetJob(18).Level < 14 then --!OF timer and leves should also be a condition
        if debug then
            yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: normal fishing.")
        end
        repeat
            sleep(0.678)
        until IsPlayerAvailable()
        sleep(2.73)

        -- Used to decorrelate this character's random behavior below from every other
        -- character's -- computed once up front so both the post-gear stagger and the
        -- fishing-spot jitter reuse the same value.
        local fish_cid = Entity.Player and Entity.Player.ContentId or 0

        local job_swap_attempts = 0
        local job_swapped = SwapJobFromArmoury(18)
        while not job_swapped and job_swap_attempts < 4 do
            job_swap_attempts = job_swap_attempts + 1
            if debug then
                yield("/echo [QSTCC_Ret+FSH(I_F) Fisher job swap failed, retrying (" .. job_swap_attempts .. "/3)...")
            end
            sleep(1.358)
            job_swapped = SwapJobFromArmoury(18)
        end
        if job_swapped then
            -- Re-seed right here rather than trusting whatever seed the file-load-time
            -- math.randomseed(os.time()) landed on (that call may have run before Entity.Player
            -- existed, and os.time() alone would collide if multiple clients reach this branch
            -- within the same second) -- os.time() + fish_cid guarantees distinct characters get
            -- distinct draws even when launched simultaneously.
            math.randomseed(os.time() + fish_cid)
            local stagger_seconds = math.random(1, 60)
            if debug then
                yield("/echo [QSTCC_Ret+FSH(I_F) Staggering fishing start by " .. stagger_seconds .. "s after equipping gear.")
            end
            sleep(stagger_seconds)
        end
        if not IsPlayerCloseTo(-202.5, 8, 106.1) or TerritoryType()~=129 then
            yield("/li fisher")
        end
        local counter = 0
        repeat
            sleep(1.376)
            counter = counter+1
        until (not IPC.Lifestream.IsBusy() and IsPlayerAvailable()) or counter > 15
        sleep(3.381)
        -- Small per-character offset so multiple simultaneously-fishing characters don't stack on
        -- the exact same tile (very conspicuous with several game clients running at once).
        -- Derived deterministically from ContentId rather than math.random, so there's no risk of
        -- two clients launched within the same second landing on an identical "random" offset --
        -- every distinct character gets a different, always-the-same-for-that-character spot,
        -- comfortably inside the fishing hole (the three hardcoded waypoints already span ~2.7
        -- yalms, so a max ~0.8 yalm nudge stays well within casting range).
        local fish_jitter_x = ((fish_cid % 17) - 8) * 0.1
        local fish_jitter_z = ((math.floor(fish_cid / 17) % 17) - 8) * 0.1
        MoveTo(-200.2 + fish_jitter_x, 8, 107.5 + fish_jitter_z)
        sleep(0.138)
        MoveTo(-200.2 + fish_jitter_x, 8, 107.5 + fish_jitter_z)
        sleep(0.139)
        MoveTo(-202.5 + fish_jitter_x, 8, 106.1 + fish_jitter_z)
        yield("/ahbait Versatile Lure")
        sleep(1.386)
        yield("/vnav stop")
        yield("/ahstart")
        for cycle=1, 60 do --!add level requierement too
            sleep(13.82)
            if Player.GetJob(18).Level > 13 then
                break
            end
        end
        while Svc.Condition[6] or not IsPlayerAvailable() do
            yield("/hold S")
            sleep(1.453)
            yield("/release S")
            sleep(0.140)
        end
        RelogNext(true)
        sleep(13.92)--this is to avoid retriggeting via DTR loop
    elseif not FisherLevelReached() and Player.GetJob(18).Level >= 14 and HasFishAndLeves() then --fisher leves in Costa via ChilledLeves
            if debug then
                yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: fisher leves.")
            end
            repeat
                sleep(0.678)
            until IsPlayerAvailable()
            sleep(2.73)

            local job_swap_attempts = 0
            local job_swapped = SwapJobFromArmoury(18)
            while not job_swapped and job_swap_attempts < 4 do
                job_swap_attempts = job_swap_attempts + 1
                if debug then
                    yield("/echo [QSTCC_Ret+FSH(I_F) Fisher job swap failed, retrying (" .. job_swap_attempts .. "/3)...")
                end
                sleep(1.358)
                job_swapped = SwapJobFromArmoury(18)
            end

            if job_swapped then
                if Player.GetJob(18).Level < 30 then
                    yield("/chilledleves setup gather")
                else
                    yield("/chilledleves setup gather nahctahr")
                end
                sleep(0.150)
                yield("/chilledleves start gather")
                -- ChilledLeves exposes no IPC and no "still running" flag we can read from SND, so
                -- progress is inferred from Fisher level: relies on ChilledLeves' own worklist
                -- (pre-populated by hand, shared across characters via its plugin config) for which
                -- leves to grab/turn in -- it does NOT catch fish, so the worklist only advances as
                -- far as already-stocked catch allows. ~15 min with no level gain is treated as
                -- "nothing left this character can turn in right now" and we move on.
                local last_level = Player.GetJob(18).Level
                local stagnant_checks = 0
                while Addons.GetAddon("_DTR").Exists and not FisherLevelReached() and stagnant_checks < 4 do
                    yield("/gaction sprint")
                    sleep(10)
                    local current_level = Player.GetJob(18).Level
                    if current_level > last_level or not CheckPosStuck() then
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
                RelogNext(true)
            else
                yield("/echo [QSTCC_Ret+FSH(I_F) Fisher job swap failed after " .. job_swap_attempts .. " retries, skipping relog this pass.")
            end
    elseif os.date("!*t").hour % 2 == 0 and os.date("!*t").min < 12 then
        if debug then
            yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: ocean fishing window.")
        end
        DoOceanFishing()
    elseif Player.GCRankImmortalFlames < 9 then --for hunt log !add command/IPC as QST companion updates
        if debug then
            yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: GC rank hunt log, rank=" .. tostring(Player.GCRankImmortalFlames))
        end
        repeat
            sleep(0.678)
        until IsPlayerAvailable()
        sleep(2.73)
        local job_swap_attempts = 0
        local job_swapped = SwapJobFromArmoury(3, 21)
        while not job_swapped and job_swap_attempts < 4 do
            job_swap_attempts = job_swap_attempts + 1
            if debug then
                yield("/echo [QSTCC_Ret+FSH(I_F) Job swap failed, retrying (" .. job_swap_attempts .. "/3)...")
            end
            sleep(1.417)
            job_swapped = SwapJobFromArmoury(3, 21)
        end

        if job_swapped then
            sleep(1.734)
            RelogNext(true)
            while Addons.GetAddon("_DTR").Exists and Player.GCRankImmortalFlames < 9 do
                sleep(10.679)
            end
        else
            yield("/echo [QSTCC_Ret+FSH(I_F) Job swap failed after " .. job_swap_attempts .. " retries, skipping relog this pass.")
        end
    else
        if debug then
            yield("/echo [QSTCC_Ret+FSH(I_F) DEBUG] branch: else (no tasks) -- relogging.")
        end
        sleep(3)
        RelogNext()
    end
end