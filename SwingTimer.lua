local ADDON_NAME, ns = ...

ns.SwingTimer = {}
local ST = ns.SwingTimer

local BAR_HEIGHT = 12  -- keep in sync with ActionBar.lua SWING_BAR_HEIGHT

-- Main-hand melee swing timer. The bar fills empty->full over the current
-- main-hand swing speed; full == your next auto-attack lands (when to weave a
-- Heroic Strike/Cleave queue or a Slam). Only the main hand is tracked --
-- Heroic Strike, Cleave and Slam all interact with the main-hand swing only;
-- off-hand swings (read via the combat-log isOffHand flag) are filtered out.

-- Build the bar under the ability grid. `gap` is ActionBar's SECTION_GAP.
function ST:Build(container, rowWidth, gap)
    if self.bar then return end

    local bar = CreateFrame("StatusBar", "HelloWarrior_SwingTimer", container)
    bar:SetSize(rowWidth, BAR_HEIGHT)
    -- AB.bar (the ability grid) is TOP-anchored, rowWidth-wide and centred, so
    -- anchoring to its bottom centres the swing bar under the grid. We never
    -- re-anchor in combat, so referencing the secure AB.bar here is taint-free.
    bar:SetPoint("TOP", ns.ActionBar.bar, "BOTTOM", 0, -gap)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.85, 0.70, 0.30)  -- warrior gold
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    self.label = label

    -- Per-frame fill (the 0.1s addon ticker is too coarse for a swing bar).
    bar:SetScript("OnUpdate", function(self)
        local start = ST.swingStart
        if not start then return end
        local dur = ST.swingDuration
        local elapsed = GetTime() - start
        if elapsed >= dur then
            self:SetValue(dur)
            ST.label:SetText("")
        else
            self:SetValue(elapsed)
            ST.label:SetText(string.format("%.1f", dur - elapsed))
        end
    end)

    bar:Hide()  -- idle until a swing fires (shown by StartSwing, hidden on regen)
    self.bar = bar
end

-- (Re)start the main-hand swing cycle from now, at the current swing speed
-- (UnitAttackSpeed already includes haste/slows, so use it directly).
function ST:StartSwing()
    if not self.bar then return end
    local mainSpeed = UnitAttackSpeed("player")
    if not mainSpeed or mainSpeed <= 0 then return end  -- guard the login/first-call transient 0
    self.swingStart = GetTime()
    self.swingDuration = mainSpeed
    self.bar:SetMinMaxValues(0, mainSpeed)
    self.bar:Show()
end

-- Main-hand abilities that REPLACE the white swing. They consume the main-hand
-- swing and reset the timer, but the combat log records them as SPELL_ events
-- (not SWING_), so without this the bar freezes at full while you spam Heroic
-- Strike. Matched by (rank-independent) name, English client like the rest.
local ON_SWING_SPELLS = {
    ["Heroic Strike"] = true,
    ["Cleave"]        = true,
    ["Slam"]          = true,
}

-- Swing detection. Own COMBAT_LOG handler (Helper's only cares about misses and
-- returns early on SWING_DAMAGE); ns:On dispatches to every handler.
ns:On("COMBAT_LOG_EVENT_UNFILTERED", function()
    if not ns.enabled or not ST.bar then return end
    local a = { CombatLogGetCurrentEventInfo() }
    local subevent, sourceGUID = a[2], a[4]
    if sourceGUID ~= ST.playerGUID then return end

    -- isOffHand sits at a different position per subevent (the classic gotcha):
    -- last param (21) for SWING_DAMAGE, the param after missType (13) for
    -- SWING_MISSED. For SPELL_ events a[13] is instead the spell name.
    if subevent == "SWING_DAMAGE" then
        if a[21] then return end           -- off-hand
        ST:StartSwing()                    -- a landed white swing
    elseif subevent == "SWING_MISSED" then
        if a[13] then return end           -- off-hand
        ST:StartSwing()                    -- a missed swing still consumed the swing
    elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_MISSED" then
        if ON_SWING_SPELLS[a[13]] then ST:StartSwing() end  -- HS/Cleave/Slam replaced the swing
    end
end)

-- Cache the player GUID (compare GUIDs, never names).
local function cacheGUID()
    if ns.enabled then ST.playerGUID = UnitGUID("player") end
end
ns:On("PLAYER_LOGIN", cacheGUID)
ns:On("PLAYER_ENTERING_WORLD", cacheGUID)

-- Attack-speed change (Flurry, slows): rescale the in-flight bar so the elapsed
-- fraction is preserved rather than visibly jumping when the buff ends.
ns:On("UNIT_ATTACK_SPEED", function(unit)
    if unit ~= "player" or not ST.swingStart then return end
    local newSpeed = UnitAttackSpeed("player")
    if not newSpeed or newSpeed <= 0 then return end
    local oldSpeed = ST.swingDuration
    local now = GetTime()
    local remaining = (ST.swingStart + oldSpeed - now) * (newSpeed / oldSpeed)
    ST.swingDuration = newSpeed
    ST.swingStart = now + remaining - newSpeed  -- new expiration == now + remaining
    ST.bar:SetMinMaxValues(0, newSpeed)
end)

-- A weapon swap resets the swing in-game; reset to the new full duration. Only
-- while the bar is already active, so an out-of-combat bag change doesn't pop it.
ns:On("UNIT_INVENTORY_CHANGED", function(unit)
    if unit == "player" and ST.bar and ST.bar:IsShown() then ST:StartSwing() end
end)

-- Idle out of combat: hide and clear (a hidden frame's OnUpdate stops firing).
ns:On("PLAYER_REGEN_ENABLED", function()
    if ST.bar then ST.bar:Hide() end
    ST.swingStart = nil
end)
