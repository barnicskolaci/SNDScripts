--[[#######################################
##            Character Cycler           ##
##              by Friendly              ##
##                                       ##
##        SND gameobject fail edition    ##
##                                       ##
##   made with WigglyMuffin functions    ##
###########################################

####################################################
##                  Description                   ##
####################################################

-- This is a temporary solution with hard coded waits without relying on gameobjects
-- This script cycles through characters and runs scripts per char and/or a full cycle
-- Run retainers "without" AR, do quests or turnin on alts, etc. The sky is the limit.
-- Can operate continuously if you put this script's name as cycle_script_name
-- Get vac_char_list.lua and vac_functions.lua from https://github.com/WigglyMuffin/SNDScripts
-- put them in your SND config folder: %appdata%\XIVLauncher\pluginConfigs\SomethingNeedDoing (can copy and paste this in Windows)

-- ###########
-- # CONFIGS #
-- #########]]

local use_external_character_list = true -- Options: true = uses the external character list in the same folder, default name being char_list.lua, false uses the list you put in this file
char_script_name = "GameObject Turnin" -- name of script to run after each character
cycle_script_name = "" -- name of script to run once this script finishes
return_location = "auto" -- where toons go after running script. same as using /li return_location


--[[ This is where you put your character list if you choose to NOT use the external one
-- If use_external_character_list is set to true then this list is completely skipped
-- Can start from current toon and go to the end of the list (!!when gameobject is fixed again)
-- Add your toons here or external list like so

local character_list = {
    "Example Character@Server",
    "John Doe@Balmung",
}
]]

    local character_list = {
}

-- #####################################
-- #  DON'T TOUCH ANYTHING BELOW HERE  #
-- # UNLESS YOU KNOW WHAT YOU'RE DOING #
-- #####################################

char_list = "vac_char_list.lua"

snd_config_folder = os.getenv("appdata") .. "\\XIVLauncher\\pluginConfigs\\SomethingNeedDoing\\"
vac_config_folder = snd_config_folder .. "\\VAC\\"
load_functions_file_location = os.getenv("appdata") .. "\\XIVLauncher\\pluginConfigs\\SomethingNeedDoing\\vac_functions.lua"
LoadFunctions = loadfile(load_functions_file_location)
LoadFunctions()
LoadFileCheck()

if not CheckPluginsEnabled("AutoRetainer", "TeleporterPlugin", "Lifestream", "PandorasBox", "SomethingNeedDoing", "TextAdvance", "vnavmesh", "YesAlready") then
    return -- Stops script as plugins not available
end

if HasPlugin("YesAlready") then --this can be (un)commented if needed
    PauseYesAlready()
end

LogInfo("[APL] ##############################")
LogInfo("[APL] Starting script...")
LogInfo("[APL] snd_config_folder: " .. snd_config_folder)
LogInfo("[APL] char_list: " .. char_list)
LogInfo("[APL] SNDConf+Char: " .. snd_config_folder .. "" .. char_list)
LogInfo("[APL] ##############################")

if use_external_character_list then
    local char_data = dofile(snd_config_folder .. char_list)
    character_list = char_data.character_list
end


function RelogAndDoThing()
    -- Find the index of the currently logged-in character
    -- local current_char_name = GetCharacterName(true)!!gameobject fix
    local start_index = 1

    --[[for index, char in ipairs(character_list) do
        if char == current_char_name then
            start_index = index
            if start_index == #character_list then
                start_index = 1
            end
            LogInfo("[APL] Starting from character: " .. char .. " at index " .. start_index)
            break
        end
    end]]

    -- Start the loop from the current character's index
    for i = start_index, #character_list do
        local char = character_list[i]
        LogInfo("[APL] Processing char number " .. i)

        if GetCharacterName(true) == char then
            LogInfo("[APL] Already on the right character: " .. char)
        else
            LogInfo("[APL] Logging into: " .. char)

--[[!! skip cause gameobject needs fixing           if not InSanctuary() then
                Teleporter("Limsa Lominsa Lower Decks", "tp")
            end
]]
            --!!RelogCharacter(char) !!!!replacing with below repeat till gameobject fix
            yield("/ays relog " .. char)
            Sleep(7.5) --This is enough time to log out completely and not too long to cut into new logins
            --LoginCheck() !!replacing with below repeat till gameobject fix
            repeat
                Sleep(0.11)
            until IsAddonVisible("NamePlate")
            for k=1, 10 do--!!delete after gameobject fix
                Sleep(2)
            end
        end

--[[!!uncomment after gameobject fix        local char_name = GetCharacterName() .. "@" .. FindWorldByID(GetHomeWorld())

        for j = 1, 500 do
            Sleep(0.5)
            if IsPlayerAvailable() then
                break
            end
        end]]

        --Run the script for the current character
        yield("/snd run " .. char_script_name)
        Sleep(1) -- this is needed for the script to start
        yield("/li "..return_location)
        for k = 1, 20 do--!! 60 sec to go wherever, delete after gameobject fix
            Sleep(3)
        end
        yield("/wait 3")
    end
end

RelogAndDoThing()
Sleep(1) --!! just in case, may not be needed
yield("/snd run "..cycle_script_name)