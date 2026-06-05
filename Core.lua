local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME

ns.eventFrame = CreateFrame("Frame")
ns.eventHandlers = {}

-- Single gate for the whole addon. ADDON_LOADED + PLAYER_LOGIN always
-- fire — they're how we read saved variables and decide whether to
-- enable. After PLAYER_LOGIN any other event is dispatched only when
-- ns.enabled is true (set below for Warrior only). Non-Warriors get the
-- addon as a no-op: no frames, no hooks, no event volume.
ns.eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event ~= "ADDON_LOADED" and event ~= "PLAYER_LOGIN" and not ns.enabled then
        return
    end
    local handlers = ns.eventHandlers[event]
    if not handlers then return end
    for i = 1, #handlers do
        handlers[i](...)
    end
end)

function ns:On(event, fn)
    if not ns.eventHandlers[event] then
        ns.eventHandlers[event] = {}
        ns.eventFrame:RegisterEvent(event)
    end
    table.insert(ns.eventHandlers[event], fn)
end

ns.eventFrame:RegisterEvent("ADDON_LOADED")
ns.eventFrame:RegisterEvent("PLAYER_LOGIN")

ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    ns.Config:Init()
end)

ns:On("PLAYER_LOGIN", function()
    local _, class = UnitClass("player")
    ns.playerClass = class
    if class ~= "WARRIOR" then return end
    ns.enabled = true
    ns.Config:CreatePanel()
    print("|cffc79c6eHelloWarrior|r loaded")
end)

SLASH_HELLOWARRIOR1 = "/hw"
SLASH_HELLOWARRIOR2 = "/hellowarrior"
SlashCmdList["HELLOWARRIOR"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    local cmd, arg = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd or ""

    if cmd == "reset" then
        HelloWarriorDB = nil
        HelloWarriorCharDB = nil
        ReloadUI()
    elseif cmd == "config" then
        if not ns.enabled then return end
        ns.Config:OpenPanel()
    elseif cmd == "bars" then
        if not ns.enabled then return end
        if arg == "on" then ns.ActionBar:SetHWBarsVisible(true)
        elseif arg == "off" then ns.ActionBar:SetHWBarsVisible(false)
        else ns.ActionBar:SetHWBarsVisible(not HelloWarriorCharDB.showHWBars) end
    elseif cmd == "blizz" then
        if not ns.enabled then return end
        if arg == "on" then ns.ActionBar:SetBlizzardBarsHidden(false)
        elseif arg == "off" then ns.ActionBar:SetBlizzardBarsHidden(true)
        else ns.ActionBar:SetBlizzardBarsHidden(not HelloWarriorCharDB.hideBlizzardBars) end
    elseif cmd == "keys" then
        if not ns.enabled then return end
        if arg == "clear" then ns.Keybinds:ClearAll()
        elseif arg == "reset" then ns.Keybinds:ResetDefaults()
        else ns.Keybinds:ToggleMode() end
    else
        print("|cffc79c6eHelloWarrior|r commands:")
        print("  /hw config | /hw reset")
        print("  /hw bars on|off  (HelloWarrior bars)")
        print("  /hw blizz on|off (Blizzard bars)")
        print("  /hw keys [clear|reset] (edit keybindings)")
    end
end
