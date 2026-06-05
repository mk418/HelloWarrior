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

    -- Active highlight: yellow ring (border, not fill).
    local ring = CreateFrame("Frame", nil, btn)
    ring:SetAllPoints(btn)
    ring:Hide()
    local function edge()
        local t = ring:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetVertexColor(1, 0.85, 0, 1)
        t:SetBlendMode("ADD")
        return t
    end
    local th = 2
    local top = edge(); top:SetHeight(th)
    top:SetPoint("TOPLEFT", -th, th); top:SetPoint("TOPRIGHT", th, th)
    local bot = edge(); bot:SetHeight(th)
    bot:SetPoint("BOTTOMLEFT", -th, -th); bot:SetPoint("BOTTOMRIGHT", th, -th)
    local left = edge(); left:SetWidth(th)
    left:SetPoint("TOPLEFT", -th, 0); left:SetPoint("BOTTOMLEFT", -th, 0)
    local right = edge(); right:SetWidth(th)
    right:SetPoint("TOPRIGHT", th, 0); right:SetPoint("BOTTOMRIGHT", th, 0)
    btn.activeBorder = ring

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(STANCE_NAMES[stanceId])
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

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
    for i = 1, 3 do
        local btn = self.buttons[i]
        if GetSpellInfo(STANCE_NAMES[i]) then
            btn:Show()
            if i == current then
                btn.icon:SetVertexColor(1, 1, 1)
                btn.activeBorder:Show()
            else
                btn.icon:SetVertexColor(0.5, 0.5, 0.5)
                btn.activeBorder:Hide()
            end
        else
            btn:Hide()
        end
    end
end

ns:On("UPDATE_SHAPESHIFT_FORM", function() SI:Refresh() end)
ns:On("SPELLS_CHANGED", function() SI:Refresh() end)
