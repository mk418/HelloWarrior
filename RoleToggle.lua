local ADDON_NAME, ns = ...

ns.RoleToggle = {}
local RT = ns.RoleToggle

local WIDTH = 64
local HEIGHT = 22

function RT:Build(parent, bar)
    if self.frame then return end

    -- Macros for each direction. The toggle's macrotext is swapped by the
    -- flip button's _onclick after each click so the next click casts the
    -- correct stance for the new role.
    local TO_TANK = "/cast [nostance:2] Defensive Stance\n/click HelloWarriorRoleFlip"
    local TO_DPS  = "/cast [nostance:3] Berserker Stance\n/click HelloWarriorRoleFlip"

    -- Visible toggle: macro casts the appropriate stance then /clicks the
    -- hidden flip button to swap roles in restricted env.
    local btn = CreateFrame("Button", "HelloWarriorRoleToggle", parent or UIParent, "SecureActionButtonTemplate")
    btn:SetSize(WIDTH, HEIGHT)
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", (HelloWarriorCharDB.role == "tank") and TO_DPS or TO_TANK)

    -- Hidden flip button: SecureHandlerClickTemplate so its _onclick runs in
    -- restricted env and is combat-legal.
    local flip = CreateFrame("Button", "HelloWarriorRoleFlip", btn, "SecureHandlerClickTemplate")
    flip:Hide()
    flip:RegisterForClicks("AnyUp")
    flip:SetFrameRef("bar", bar)
    flip:SetFrameRef("toggle", btn)
    flip:SetAttribute("toTankMacro", TO_TANK)
    flip:SetAttribute("toDpsMacro",  TO_DPS)
    flip:SetAttribute("_onclick", [[
        local bar = self:GetFrameRef("bar")
        if not bar then return end
        local cur = bar:GetAttribute("baseRole") or "dps"
        local new = (cur == "tank") and "dps" or "tank"
        bar:SetAttribute("baseRole", new)
        bar:RunAttribute("UpdateRole")
        local toggle = self:GetFrameRef("toggle")
        if toggle then
            if new == "tank" then
                toggle:SetAttribute("macrotext", self:GetAttribute("toDpsMacro"))
            else
                toggle:SetAttribute("macrotext", self:GetAttribute("toTankMacro"))
            end
        end
    ]])

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    btn.label = label

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
