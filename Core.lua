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
-- once per button, then SetShine(btn, on) to toggle. Two client generations:
-- 1.15.9+ ships AutoCastOverlayTemplate (16 sparkle textures in a parentArray);
-- older builds ship AutoCastShineTemplate, whose OnLoad fills its sparkles from
-- _G[name .. i] -- so THAT frame needs a globally-unique name, derived from the
-- button's. The btn._shineOn guard means the on-transition work (which re-seeds
-- the sparkles on every call) fires only on an off->on flip, so SetShine is
-- safe to call every tick. Self-disables (no-op, no error) if neither shine
-- API exists on this build.
--
-- On 1.15.9+ we animate the sparkles OURSELVES instead of calling the
-- template's ShowAutoCastEnabled: that method registers the frame in the
-- global AutoCastOverlayManager.activeShines list, and Blizzard's own secure
-- paths scan that list (the pet bar's Add/RemoveActiveShine tInsertUnique/
-- tDeleteItem-scan it on every update) -- an addon-tainted entry there taints
-- them and draws ADDON_ACTION_BLOCKED when they go on to call protected
-- functions (e.g. PetActionBar:SetShownBase). The animator below replicates
-- the manager's exact marching math (same speeds, same four-phase orbit) on
-- our own frame's sparkles only, so no Blizzard-shared state is ever touched.
local SHINE_SPEEDS = { 2, 4, 6, 8 }

local function shineOnUpdate(self, elapsed)
    local timers = self._timers
    for i = 1, 4 do
        local t = timers[i] + elapsed
        if t > SHINE_SPEEDS[i] * 4 then t = t - SHINE_SPEEDS[i] * 4 end
        timers[i] = t
    end
    local distance = self:GetWidth()
    local sparkles = self.sparkles
    for i = 1, 4 do
        local timer, speed = timers[i], SHINE_SPEEDS[i]
        if timer <= speed then
            local p = timer / speed * distance
            sparkles[i]:SetPoint("CENTER", self, "TOPLEFT", p, 0)
            sparkles[4 + i]:SetPoint("CENTER", self, "BOTTOMRIGHT", -p, 0)
            sparkles[8 + i]:SetPoint("CENTER", self, "TOPRIGHT", 0, -p)
            sparkles[12 + i]:SetPoint("CENTER", self, "BOTTOMLEFT", 0, p)
        elseif timer <= speed * 2 then
            local p = (timer - speed) / speed * distance
            sparkles[i]:SetPoint("CENTER", self, "TOPRIGHT", 0, -p)
            sparkles[4 + i]:SetPoint("CENTER", self, "BOTTOMLEFT", 0, p)
            sparkles[8 + i]:SetPoint("CENTER", self, "BOTTOMRIGHT", -p, 0)
            sparkles[12 + i]:SetPoint("CENTER", self, "TOPLEFT", p, 0)
        elseif timer <= speed * 3 then
            local p = (timer - speed * 2) / speed * distance
            sparkles[i]:SetPoint("CENTER", self, "BOTTOMRIGHT", -p, 0)
            sparkles[4 + i]:SetPoint("CENTER", self, "TOPLEFT", p, 0)
            sparkles[8 + i]:SetPoint("CENTER", self, "BOTTOMLEFT", 0, p)
            sparkles[12 + i]:SetPoint("CENTER", self, "TOPRIGHT", 0, -p)
        else
            local p = (timer - speed * 3) / speed * distance
            sparkles[i]:SetPoint("CENTER", self, "BOTTOMLEFT", 0, p)
            sparkles[4 + i]:SetPoint("CENTER", self, "TOPRIGHT", 0, -p)
            sparkles[8 + i]:SetPoint("CENTER", self, "TOPLEFT", p, 0)
            sparkles[12 + i]:SetPoint("CENTER", self, "BOTTOMRIGHT", -p, 0)
        end
    end
end

function ns:AttachShine(btn, size)
    local shine
    if AutoCastOverlayMixin then  -- 1.15.9+
        shine = CreateFrame("Frame", nil, btn, "AutoCastOverlayTemplate")
        -- The overlay template also carries the golden pet-autocast corner
        -- arrows; we only want the marching sparkles.
        if shine.Corners then shine.Corners:Hide() end
        -- Local-animator eligibility: exactly the 16 sparkles the orbit math
        -- expects. If Blizzard reshapes the template the cue degrades to
        -- nothing rather than erroring every frame.
        shine._localAnim = (shine.sparkles and #shine.sparkles == 16) or false
    elseif AutoCastShine_AutoCastStart then
        shine = CreateFrame("Frame", btn:GetName() .. "Shine", btn, "AutoCastShineTemplate")
    else
        return  -- shine API absent on this build: the cue self-disables
    end
    shine:SetSize(size, size)
    shine:SetPoint("CENTER", btn, "CENTER", 0, 0)
    shine:SetFrameLevel((btn:GetFrameLevel() or 0) + 4)
    shine:Hide()
    btn._shine = shine
    btn._shineOn = false
    return shine
end

function ns:SetShine(btn, on, r, g, b)
    local shine = btn._shine
    if not shine then return end
    on = on and true or false
    if btn._shineOn == on then return end
    if on then
        shine:Show()
        if shine._localAnim then  -- 1.15.9+ overlay, driven locally
            -- The template's OnLoad tints the sparkles autocast-yellow;
            -- re-tint on the way on so our custom colour survives (the legacy
            -- start call took r,g,b directly).
            for _, sparkle in ipairs(shine.sparkles) do
                if r then sparkle:SetVertexColor(r, g, b) end
                sparkle:Show()
            end
            shine._timers = { 0, 0, 0, 0 }
            shine:SetScript("OnUpdate", shineOnUpdate)
        elseif AutoCastShine_AutoCastStart then
            AutoCastShine_AutoCastStart(shine, r, g, b)
        end
    else
        if shine._localAnim then
            shine:SetScript("OnUpdate", nil)
            for _, sparkle in ipairs(shine.sparkles) do
                sparkle:Hide()
            end
        elseif AutoCastShine_AutoCastStop then
            AutoCastShine_AutoCastStop(shine)
        end
        shine:Hide()
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
