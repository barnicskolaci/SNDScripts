--[=====[
[[SND Metadata]]
author: barni
version: 1.0.0
description: >
  Fisher levequests as an AutoRetainer CharacterPostProcess. AR logs a toon in, finishes its
  retainers, then fires this once. It swaps to Fisher, runs ChilledLeves priority-leve gather
  (turns stocked fish in for leve rewards, spending allowances), stops once nothing is being
  turned in for 40s or the fish/allowances run out, parks at the inn, and ENDS. SND then calls
  AR's FinishCharacterPostProcess automatically -> AR relogs to the next toon.
  This macro must NEVER relog or toggle MultiMode (AR owns that during the lease), and must
  ALWAYS reach the end (all loops are iteration-capped) or AR wedges forever.
triggers:
- onautoretainercharacterpostprocess
[[End Metadata]]
--]=====]

-- ============================================================================================
-- Extracted from SNDScripts/FSH_Leves_isolated.lua (2026-08-06). This is the AR-postprocess
-- variant: NO roster loop, NO RelogNext, NO MultiMode writes -- AR drives the rotation and this
-- runs exactly once per character. Progress is tracked by fish consumed (a pure inventory read),
-- not the FSH position/level stall (which false-triggers during the near-stationary rapid
-- turn-ins ChilledLeves does at Nahctahr) and not a Journal scrape (which would fight
-- ChilledLeves' own addon automation mid-gather).
-- ============================================================================================

-- Nahctahr Fisher priority-leve delivery items (leve 780 Black Sole=4892, 778 Ash Tuna=4896,
-- 779 Indigo Herring=4895, 781 Sea Pickle=4894). ChilledLeves consumes these on every turn-in,
-- so their total only ever drops while it's working and goes flat when it's out of fish/leves.
local FISH_ITEMS = { 4892, 4896, 4895, 4894 }

--[[###########
## FUNCTIONS ##
#############]]

function sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

-- Verbatim from FSH_Leves_isolated.lua:80 -- true only when the character is loaded and not busy
-- (casting / cutscene / between-areas / crafting / mounting / fishing / etc).
function IsPlayerAvailable()
    if not Player.Available then
        return false
    end
    if Entity.Player.IsCasting then
        return false
    end
    local occupiedFlags = {
        25, 30, 33, 38, 39, 35, 31, 32, 50, 52, 78, 45, 51, 11, 5, 40, 41, 2, 6, 7,
        65, 70, 10, 66, 71, 15, 14, 12, 13, 18, 43, 68, 67,
    }
    local c = Svc.Condition
    for i = 1, #occupiedFlags do
        if c[occupiedFlags[i]] then
            return false
        end
    end
    return true
end

-- Verbatim from FSH_Leves_isolated.lua:257 -- reads the current leve-allowance count off the
-- Journal addon. Only called ONCE, before gather starts (opening the Journal mid-gather would
-- interfere with ChilledLeves' UI automation), purely to skip toons that have 0 allowances fast.
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

-- Sum of the four priority-leve delivery fish. Pure memory read -- safe to poll at framerate,
-- never touches the UI, so it can run alongside ChilledLeves without any addon contention.
function FishSum()
    local s = 0
    for _, id in ipairs(FISH_ITEMS) do
        s = s + (Inventory.GetItemCount(id) or 0)
    end
    return s
end

-- Ensure the toon is on Fisher (job 18) with its FULL gear, exactly the way Questionable's
-- ClassJobUtils.SwitchClassJob does it: if already on the job, done; otherwise scan gearsets
-- 0..99 for the one whose ClassJob is Fisher and equip it natively via the game's gearset module
-- (RaptureGearsetModule.EquipGearset). SND exposes this as GearsetWrapper.Equip() -- no /gs chat
-- command, and it equips the WHOLE saved set (weapon + armour) so the toon is never left in a bare
-- rod (which looks bot-suspicious). If there is NO Fisher gearset, return false and skip this toon
-- this pass -- we never leave a toon naked. Bounded scan, single native call, no UI, no hang risk.
function EnsureFisher()
    if not IsPlayerAvailable() or Player.Job == nil then
        return false
    end
    if Player.Job.Id == 18 then
        return true
    end

    for i = 0, 99 do
        local gs = Player.GetGearset(i)
        if gs ~= nil and gs.IsValid and gs.ClassJob == 18 then
            gs:Equip()
            -- poll for the job change instead of a single fixed wait (more first-pass reliable)
            local w = 0
            repeat
                sleep(0.5)
                w = w + 1
            until (Player.Job and Player.Job.Id == 18) or w > 12
            if Player.Job and Player.Job.Id == 18 then
                return true
            end
        end
    end
    return false
end

--[[###########
### POSTPROCESS BODY (runs once per character) ###
##############]]

-- AR has just logged us in and finished retainers -- wait until the character is actually
-- controllable before doing anything. Bounded (~40s) so we never hang here.
local ready = 0
repeat
    sleep(0.678)
    ready = ready + 1
until IsPlayerAvailable() or ready > 60
sleep(2.0)

-- Swap to Fisher (bounded, no UI). If we can't get onto Fisher, there's nothing to do -- fall
-- straight through to the inn-park + end so AR is released promptly.
local is_fisher = EnsureFisher()

-- Only run leves if we're Fisher AND actually have allowances. This is exactly the gate that was
-- missing from the original fleet run (HasFishAndLeves() was a stub returning true), which is why
-- toons got "parked" with their leves never done. GetLeveAllowances reads the real count.
local allowances = GetLeveAllowances() or 0
local name = tostring(Entity.Player and Entity.Player.Name or "?")

if is_fisher and allowances > 0 then
    yield("/echo [FSH_PostAR] " .. name .. ": " .. allowances .. " leve allowances, starting gather.")

    -- Costa/tmokkri set below Fisher 30, Nahctahr set at 30+.
    if Player.GetJob(18).Level < 30 then
        yield("/chilledleves setup gather")
    else
        yield("/chilledleves setup gather nahctahr")
    end
    sleep(0.150)
    yield("/chilledleves start gather")

    -- Drain detector on fish-consumed. `began` flips on the first turn-in (tolerates the teleport
    -- + walk to Nahctahr with a ~120s startup grace); after that, 40s (4x10s) with no turn-in means
    -- ChilledLeves is out of fish or allowances -- the user's "hasn't changed for 40s or reached 0".
    -- Hard 30-min ceiling so the macro can NEVER hang in Running (which would wedge AR forever).
    local last = FishSum()
    local stall = 0
    local began = false
    local cap = 0
    while cap < 180 do
        sleep(10)
        cap = cap + 1
        local now = FishSum()
        if now < last then
            began = true
            last = now
            stall = 0
        else
            stall = stall + 1
        end
        if now <= 0 then break end                              -- delivery fish exhausted
        if began and stall >= 4 then break end                  -- drained: 40s with no turn-in
        if not began and stall >= 12 then break end             -- never started (~120s): stuck / no-op
        if not Addons.GetAddon("_DTR").Exists then break end    -- logged out / aborted
    end

    yield("/chilledleves stop")
    sleep(1.0)
else
    yield("/echo [FSH_PostAR] " .. name .. ": skipping leves (fisher=" .. tostring(is_fisher)
        .. ", allowances=" .. allowances .. ").")
end

-- Park at the inn (has a summoning bell, so AR can process this toon in place next rotation), then
-- END. Do NOT relog and do NOT touch MultiMode -- AR relogs to the next toon by itself once this
-- macro reaches Completed/Error and SND calls FinishCharacterPostProcess. Bounded (~120s).
yield("/li inn")
local innwait = 0
repeat
    sleep(1.0)
    innwait = innwait + 1
until (not IPC.Lifestream.IsBusy()) or innwait > 120

yield("/echo [FSH_PostAR] " .. name .. ": done, releasing to AutoRetainer.")
-- macro ends -> SND -> AR.FinishCharacterPostProcess() -> AR relogs to the next toon
