local ADDON_NAME, ns = ...

ns.StanceIndicator = {}
local SI = ns.StanceIndicator

local SIZE = 24
local GAP = 4

local STANCE_NAMES = {
    [1] = "Battle Stance",
    [2] = "Defensive Stance",
    [3] = "Berserker Stance",
}

local function stanceIcon(sid)
    local _, _, icon = GetSpellInfo(ns.Abilities.STANCE_SPELL_ID[sid])
    return icon
end

local function createStanceButton(parent, stanceId)
    local btn = CreateFrame("Button", "HelloWarriorStance" .. stanceId, parent, "SecureActionButtonTemplate")
    btn:SetSize(SIZE, SIZE)
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("spell", STANCE_NAMES[stanceId])

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()
    icon:SetTexture(stanceIcon(stanceId))
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(STANCE_NAMES[stanceId])
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    -- Active-stance cue: the shared pet-autocast spinning shine, lit on whichever
    -- stance you're currently in (toggled in SI:Refresh).
    ns:AttachShine(btn, SIZE)

    return btn
end

function SI:Build(parent)
    if self.frame then return end
    local frame = CreateFrame("Frame", "HelloWarriorStanceIndicator", parent or UIParent)
    frame:SetSize(3 * SIZE + 2 * GAP, SIZE)
    self.frame = frame
    self.buttons = {}
    for i = 1, 3 do
        local btn = createStanceButton(frame, i)
        if i == 1 then
            btn:SetPoint("LEFT", frame, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", self.buttons[i - 1], "RIGHT", GAP, 0)
        end
        self.buttons[i] = btn
    end
    self:Refresh()
end

function SI:Refresh()
    if not self.frame then return end
    local current = GetShapeshiftForm()
    local inCombat = InCombatLockdown()
    for i = 1, 3 do
        local btn = self.buttons[i]
        local learned = GetSpellInfo(STANCE_NAMES[i]) ~= nil
        if not inCombat then
            if learned then btn:Show() else btn:Hide() end
        end
        if learned then
            btn.icon:SetVertexColor(i == current and 1 or 0.5, i == current and 1 or 0.5, i == current and 1 or 0.5)
        end
        -- Shine the active stance. Safe in combat (texture/anim toggle, not
        -- protected), so it runs even when the Show/Hide above is skipped.
        ns:SetShine(btn, learned and i == current, 0.45, 0.8, 1.0)
    end
end

ns:On("PLAYER_REGEN_ENABLED", function() SI:Refresh() end)

ns:On("UPDATE_SHAPESHIFT_FORM", function() SI:Refresh() end)
ns:On("SPELLS_CHANGED", function() SI:Refresh() end)
