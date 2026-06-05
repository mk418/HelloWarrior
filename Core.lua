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

-- Shared "shine" cue: Blizzard's pet-autocast spinning sparkles. AttachShine
-- once per (named) button, then SetShine(btn, on) to toggle. The shine frame
-- needs a globally-unique name -- its template OnLoad fills its sparkles from
-- _G[name .. i] -- so we derive it from the button's name. The btn._shineOn
-- guard means AutoCastShine_AutoCastStart (which re-seeds the sparkles on every
-- call) fires only on an off->on transition, so SetShine is safe to call every
-- tick. Self-disables (no-op, no error) if the shine API is absent on this build.
function ns:AttachShine(btn, size)
    local shine = CreateFrame("Frame", btn:GetName() .. "Shine", btn, "AutoCastShineTemplate")
    shine:SetSize(size, size)
    shine:SetPoint("CENTER", btn, "CENTER", 0, 0)
    shine:SetFrameLevel((btn:GetFrameLevel() or 0) + 4)
    shine:Hide()
    btn._shine = shine
    btn._shineOn = false
    return shine
end

function ns:SetShine(btn, on, r, g, b)
    if not btn._shine then return end
    on = on and true or false
    if btn._shineOn == on then return end
    if on then
        btn._shine:Show()
        if AutoCastShine_AutoCastStart then AutoCastShine_AutoCastStart(btn._shine, r, g, b) end
    else
        if AutoCastShine_AutoCastStop then AutoCastShine_AutoCastStop(btn._shine) end
        btn._shine:Hide()
    end
    btn._shineOn = on
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
    elseif cmd == "pos" then
        if not ns.enabled then return end
        if arg == "reset" then
            ns.ActionBar:ResetPosition()
            print("|cffc79c6eHelloWarrior|r position reset.")
        elseif arg == "lock" then
            ns.ActionBar:SetLocked(true)
            print("|cffc79c6eHelloWarrior|r position locked.")
        elseif arg == "unlock" then
            ns.ActionBar:SetLocked(false)
            print("|cffc79c6eHelloWarrior|r position unlocked -- drag the cluster to move it.")
        else
            local nowLocked = not HelloWarriorCharDB.locked
            ns.ActionBar:SetLocked(nowLocked)
            print("|cffc79c6eHelloWarrior|r position " ..
                (nowLocked and "locked." or "unlocked -- drag the cluster to move it."))
        end
    elseif cmd == "keys" then
        if not ns.enabled then return end
        if arg == "clear" then ns.Keybinds:ClearAll()
        elseif arg == "reset" then ns.Keybinds:ResetDefaults()
        else ns.Keybinds:ToggleMode() end
    elseif cmd == "swap" then
        if not ns.enabled then return end
        if arg == "clear" then ns.ActionBar:ClearOffhandSwap()
        else ns.ActionBar:SaveOffhandSwap() end
    else
        print("|cffc79c6eHelloWarrior|r commands:")
        print("  /hw config || /hw reset")
        print("  /hw bars [on||off]  (HelloWarrior bars)")
        print("  /hw pos [lock||unlock||reset]")
        print("  /hw keys [clear||reset] (edit keybindings)")
        print("  /hw swap [clear] (save off-hand weapon/shield toggle)")
    end
end
