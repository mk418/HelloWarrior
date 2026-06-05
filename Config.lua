local ADDON_NAME, ns = ...

ns.Config = {}
local Config = ns.Config

local accountDefaults = {}

local charDefaults = {
    role = "dps",
    hideBlizzardBars = true,
    showHWBars = true,
}

local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                applyDefaults(target[k], v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            applyDefaults(target[k], v)
        end
    end
end

function Config:Init()
    HelloWarriorDB = HelloWarriorDB or {}
    HelloWarriorCharDB = HelloWarriorCharDB or {}
    applyDefaults(HelloWarriorDB, accountDefaults)
    applyDefaults(HelloWarriorCharDB, charDefaults)
end

function Config:CreatePanel()
    local panel = CreateFrame("Frame")
    panel.name = "HelloWarrior"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("HelloWarrior")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Ability manager for Classic Era Warriors.")

    local roleLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    roleLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -24)
    roleLabel:SetText("Role:")

    local tankBtn = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
    tankBtn:SetPoint("LEFT", roleLabel, "RIGHT", 12, 0)
    tankBtn.text = tankBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    tankBtn.text:SetPoint("LEFT", tankBtn, "RIGHT", 4, 0)
    tankBtn.text:SetText("Tank")

    local dpsBtn = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
    dpsBtn:SetPoint("LEFT", tankBtn.text, "RIGHT", 16, 0)
    dpsBtn.text = dpsBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    dpsBtn.text:SetPoint("LEFT", dpsBtn, "RIGHT", 4, 0)
    dpsBtn.text:SetText("DPS")

    local function makeCheckbox(parent, label, anchorTo, yGap)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yGap or -8)
        cb.label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.label:SetText(label)
        return cb
    end

    local hwBarsCB = makeCheckbox(panel, "Show HelloWarrior bars", roleLabel, -16)
    local blizzBarsCB = makeCheckbox(panel, "Hide Blizzard action bars", hwBarsCB, -4)

    local function sync()
        local role = HelloWarriorCharDB.role or "dps"
        tankBtn:SetChecked(role == "tank")
        dpsBtn:SetChecked(role == "dps")
        hwBarsCB:SetChecked(HelloWarriorCharDB.showHWBars ~= false)
        blizzBarsCB:SetChecked(HelloWarriorCharDB.hideBlizzardBars == true)
    end
    tankBtn:SetScript("OnClick", function() ns.ActionBar:SetRole("tank"); sync() end)
    dpsBtn:SetScript("OnClick", function() ns.ActionBar:SetRole("dps"); sync() end)
    hwBarsCB:SetScript("OnClick", function(self) ns.ActionBar:SetHWBarsVisible(self:GetChecked()); sync() end)
    blizzBarsCB:SetScript("OnClick", function(self) ns.ActionBar:SetBlizzardBarsHidden(self:GetChecked()); sync() end)
    panel:SetScript("OnShow", sync)

    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", blizzBarsCB, "BOTTOMLEFT", 0, -16)
    help:SetJustifyH("LEFT")
    help:SetText(
        "Slash commands:\n" ..
        "  /hw config - open this panel\n" ..
        "  /hw tank | /hw dps | /hw toggle - role\n" ..
        "  /hw bars on|off - HelloWarrior bars\n" ..
        "  /hw blizz on|off - Blizzard bars\n" ..
        "  /hw reset - reset all saved variables and reload"
    )

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        self.category = category
    end

    self.panel = panel
end

function Config:OpenPanel()
    if Settings and Settings.OpenToCategory and self.category then
        Settings.OpenToCategory(self.category:GetID())
    end
end
