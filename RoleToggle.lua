local ADDON_NAME, ns = ...

ns.RoleToggle = {}
local RT = ns.RoleToggle

local WIDTH = 64
local HEIGHT = 22

function RT:Build(parent, bar)
    if self.frame then return end

    local btn = CreateFrame("Button", "HelloWarriorRoleToggle", parent or UIParent, "SecureHandlerClickTemplate")
    btn:SetSize(WIDTH, HEIGHT)
    btn:RegisterForClicks("AnyUp")
    btn:SetFrameRef("bar", bar)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    btn.label = label

    -- Combat-legal flip: updates bar attribute + re-runs the bar's role snippet.
    btn:SetAttribute("_onclick", [[
        local bar = self:GetFrameRef("bar")
        if not bar then return end
        local cur = bar:GetAttribute("baseRole") or "dps"
        bar:SetAttribute("baseRole", (cur == "tank") and "dps" or "tank")
        bar:RunAttribute("UpdateRole")
    ]])

    -- Non-secure post-click: persist and refresh label.
    btn:HookScript("OnClick", function()
        local role = bar:GetAttribute("baseRole")
        HelloWarriorCharDB.role = role
        RT:Refresh()
        print("|cffc79c6eHelloWarrior|r role: " .. role)
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("HelloWarrior role")
        GameTooltip:AddLine("Click to toggle tank/dps.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Hold Alt to overlay the other role.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    self.frame = btn
    self.bar = bar
    self:Refresh()
end

function RT:Refresh()
    if not self.frame then return end
    local role = HelloWarriorCharDB.role or "dps"
    if role == "tank" then
        self.frame.label:SetText("TANK")
        self.frame.label:SetTextColor(0.4, 0.7, 1)
    else
        self.frame.label:SetText("DPS")
        self.frame.label:SetTextColor(1, 0.4, 0.4)
    end
end
