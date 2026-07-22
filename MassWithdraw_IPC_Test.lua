--[[
MassWithdraw IPC / chat-command smoke test

Mass Withdraw's IPC channels ("MassWithdraw.SetFilter" etc.) aren't reachable via
SND's "IPC.<Name>.<Method>()" sugar -- that only exists for the handful of plugins
SND ships a hand-written C# integration for (AutoRetainer, Questionable, vnavmesh,
...), and Mass Withdraw isn't one of them. Instead this reaches the raw Dalamud IPC
directly via Svc.PluginInterface:GetIpcSubscriber<...>(name), the same "hard IPC"
technique from https://github.com/Erisen8974/snd_scripts/blob/main/hard_ipc.lua,
simplified to just what's needed here (no external require()s).

Exercises every chat command and IPC method as of v1.0.4.0, echoes PASS/FAIL per
check, and restores whatever filter selection you had before the test ran.

Does NOT run "/masswithdraw withdrawall" / StartWithdrawAll -- that actually drives
the character and needs you standing at a retainer bell, so it's left as a manual
step (see the message printed at the end).
]]

import "System"

-- Finds IDalamudPluginInterface.GetIpcSubscriber<T1,...,TN,TRet> for the given
-- generic arity via reflection (Lua can't express a generic method call directly).
local function GetIpcSubscriberMethod(genericArgCount)
    local pluginInterfaceType = Svc.PluginInterface:GetType()
    local methods = pluginInterfaceType:GetMethods()
    for i = 0, methods.Length - 1 do
        local m = methods[i]
        if m.Name == "GetIpcSubscriber" and m.IsGenericMethodDefinition and m:GetGenericArguments().Length == genericArgCount then
            return m
        end
    end
    error("GetIpcSubscriber<" .. genericArgCount .. " args> not found on IDalamudPluginInterface")
end

-- channelName: e.g. "MassWithdraw.SetFilter"
-- typeNames: CLR type names in generic-argument order; the LAST one is the return
-- type for a Func channel, or an unused placeholder (e.g. "System.Object") for a
-- pure Action channel.
local function GetIpc(channelName, typeNames)
    local types = {}
    for i, name in ipairs(typeNames) do
        types[i] = Type.GetType(name)
    end
    local genericMethod = GetIpcSubscriberMethod(#typeNames)
    local made = genericMethod:MakeGenericMethod(luanet.make_array(Type, types))
    local args = luanet.make_array(Object, { channelName })
    local subscriber = made:Invoke(Svc.PluginInterface, args)
    if subscriber == nil then
        error("IPC channel not found: " .. channelName)
    end
    return subscriber
end

local ipcSetFilter           = GetIpc("MassWithdraw.SetFilter",           { "System.String", "System.Boolean", "System.Boolean" })
local ipcGetFilter            = GetIpc("MassWithdraw.GetFilter",            { "System.String", "System.Boolean" })
local ipcToggleFilter         = GetIpc("MassWithdraw.ToggleFilter",         { "System.String", "System.Boolean" })
local ipcClearFilters         = GetIpc("MassWithdraw.ClearFilters",         { "System.Object" })
local ipcGetFilterNames       = GetIpc("MassWithdraw.GetFilterNames",       { "System.String[]" })
local ipcStartWithdrawAll     = GetIpc("MassWithdraw.StartWithdrawAll",     { "System.Boolean" })
local ipcCancelWithdrawAll    = GetIpc("MassWithdraw.CancelWithdrawAll",    { "System.Boolean" })
local ipcIsWithdrawAllRunning = GetIpc("MassWithdraw.IsWithdrawAllRunning", { "System.Boolean" })

local function Check(name, passed, detail)
    if passed then
        yield("/echo [MassWithdraw Test] PASS - " .. name)
    else
        local suffix = detail ~= nil and (" (" .. tostring(detail) .. ")") or ""
        yield("/echo [MassWithdraw Test] FAIL - " .. name .. suffix)
    end
end

-- GetFilterNames returns a real (0-based) CLR string[], not a Lua table -- index
-- it directly rather than with ipairs/#.
local names = ipcGetFilterNames:InvokeFunc()
local nameCount = names ~= nil and names.Length or 0
Check("GetFilterNames returns the 6 known filters", nameCount == 6, nameCount)

if nameCount == 0 then
    yield("/echo [MassWithdraw Test] GetFilterNames returned nothing usable, aborting.")
    return
end

-- Remember the player's actual selection so the test can restore it afterward.
local originalState = {}
for i = 0, nameCount - 1 do
    local n = names[i]
    originalState[n] = ipcGetFilter:InvokeFunc(n)
end

-- "/masswithdraw filter clear"
yield("/masswithdraw filter clear")
yield("/wait 0.2")
local allCleared = true
for i = 0, nameCount - 1 do
    if ipcGetFilter:InvokeFunc(names[i]) then allCleared = false end
end
Check('"filter clear" clears every filter', allCleared)

-- "/masswithdraw filter <name> on|off|toggle", verified via the IPC getter
local sample = names[0]

yield("/masswithdraw filter " .. sample .. " on")
yield("/wait 0.2")
Check('"filter ' .. sample .. ' on" enables it', ipcGetFilter:InvokeFunc(sample) == true)

yield("/masswithdraw filter " .. sample .. " off")
yield("/wait 0.2")
Check('"filter ' .. sample .. ' off" disables it', ipcGetFilter:InvokeFunc(sample) == false)

yield("/masswithdraw filter " .. sample .. " toggle")
yield("/wait 0.2")
Check('"filter ' .. sample .. ' toggle" re-enables it', ipcGetFilter:InvokeFunc(sample) == true)

-- IPC SetFilter/GetFilter/ToggleFilter round-trip for every filter
ipcClearFilters:InvokeAction()
local roundTripOk = true
for i = 0, nameCount - 1 do
    local n = names[i]
    ipcSetFilter:InvokeFunc(n, true)
    if ipcGetFilter:InvokeFunc(n) ~= true then roundTripOk = false end

    local toggled = ipcToggleFilter:InvokeFunc(n)
    if toggled ~= false or ipcGetFilter:InvokeFunc(n) ~= false then roundTripOk = false end
end
Check("SetFilter/GetFilter/ToggleFilter round-trip for every filter", roundTripOk)

-- Unknown filter names should be rejected, not silently accepted
Check("SetFilter rejects an unknown filter name", ipcSetFilter:InvokeFunc("not_a_real_filter_xyz", true) == false)
Check("ToggleFilter on an unknown name returns false, not an error", ipcToggleFilter:InvokeFunc("not_a_real_filter_xyz") == false)

-- Withdraw-all state queries (non-invasive -- doesn't actually start anything)
Check("IsWithdrawAllRunning reports false when idle", ipcIsWithdrawAllRunning:InvokeFunc() == false)
Check("CancelWithdrawAll with nothing running returns false", ipcCancelWithdrawAll:InvokeFunc() == false)

-- Restore whatever filters were actually selected before this test ran
ipcClearFilters:InvokeAction()
for i = 0, nameCount - 1 do
    local n = names[i]
    if originalState[n] then
        ipcSetFilter:InvokeFunc(n, true)
    end
end

yield("/echo [MassWithdraw Test] Done. \"withdrawall\"/StartWithdrawAll were not exercised --")
yield("/echo [MassWithdraw Test] run \"/masswithdraw withdrawall\" manually near a retainer bell to verify the live batch.")
