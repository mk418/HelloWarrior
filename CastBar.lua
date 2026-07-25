local ADDON_NAME, ns = ...

ns.CastBar = {}
local CB = ns.CastBar

local BAR_HEIGHT = 16
local GAP = 4          -- between the bar and the range readout below it
local HOLD = 0.6       -- seconds the bar lingers red after a failed cast

-- Cast bar for the cluster, sitting at the very top of it: above the range
-- readout, which is above the header band.
--
-- WHY HELLOWARRIOR OWNS A CAST BAR AT ALL. Blizzard's PlayerCastingBarFrame is
-- centred just above the action bars, which is exactly where this cluster
-- lives, so the two draw through each other. Positioning Blizzard's out of the
-- way is not really available: it is an Edit Mode system, an anchor set from
-- outside is reverted on every close of Edit Mode, and making one stick means
-- writing Edit Mode's own layout table in an addon's taint context. Drawing our
-- own bar and asking HelloUI to switch Blizzard's off is the cheap direction --
-- and HelloUI does that through Blizzard's own supported call, the same one the
-- client uses when an overlay bar replaces the player's.
--
-- WHAT A WARRIOR ACTUALLY CASTS. Almost no Warrior ability has a cast time; in
-- practice this bar shows bandages, mounts, hearthstones, food and drink, and
-- the odd summoning ritual. That is still worth a bar -- a bandage interrupted
-- by a dot is a real cost -- but do not expect it during a fight.

local function colour(bar, r, g, b)
    bar:SetStatusBarColor(r, g, b)
end

-- Both APIs return times in MILLISECONDS on the same clock as GetTime()*1000.
-- A cast and a channel are mutually exclusive, so one lookup order settles it.
local function castInfo()
    local name, _, _, startMS, endMS = UnitCastingInfo("player")
    if name then
        return name, startMS, endMS, false
    end
    local cname, _, _, cstartMS, cendMS = UnitChannelInfo("player")
    if cname then
        return cname, cstartMS, cendMS, true
    end
    return nil
end

function CB:Build(container)
    if self.bar then return end

    local bar = CreateFrame("StatusBar", "HelloWarrior_CastBar", container)
    bar:SetHeight(BAR_HEIGHT)
    -- Top of the stack. Anchored above the range readout rather than to the
    -- container's top edge, so the two never fight for the same strip -- and
    -- the readout is given an explicit height in AB:Build for exactly this
    -- reason, since an empty FontString measures zero and would let the bar
    -- slide down onto it the moment the text cleared.
    local anchor = ns.ActionBar.rangeText or container
    bar:SetPoint("BOTTOM", anchor, "TOP", 0, GAP)
    bar:SetPoint("LEFT", container, "LEFT", 0, 0)
    bar:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    -- Spell name on the left, countdown on the right: the two things you act on.
    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", bar, "LEFT", 4, 0)
    label:SetPoint("RIGHT", bar, "RIGHT", -40, 0)
    label:SetJustifyH("LEFT")
    self.label = label

    local timer = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timer:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    self.timer = timer

    -- Per-frame, like the swing timer next door: the addon's 0.1s tick is too
    -- coarse for a bar you are watching to time an interrupt against.
    bar:SetScript("OnUpdate", function(self)
        if CB.holdUntil then
            if GetTime() >= CB.holdUntil then
                CB.holdUntil = nil
                self:Hide()
            end
            return
        end
        local startT, endT = CB.startTime, CB.endTime
        if not startT then return end
        local now = GetTime()
        if now >= endT then
            CB:Stop()
            return
        end
        local total = endT - startT
        local elapsed = now - startT
        -- A channel drains rather than fills: the bar should read "how much is
        -- left", which is the opposite direction for the same numbers.
        self:SetValue(CB.channelling and (total - elapsed) or elapsed)
        CB.timer:SetText(("%.1f"):format(endT - now))
    end)

    bar:Hide()
    self.bar = bar
    self:Apply()
end

-- Start (or re-read, after a pushback) whatever the player is casting.
function CB:Start()
    if not self.bar or HelloWarriorCharDB.showCastBar == false then return end

    local name, startMS, endMS, channelling = castInfo()
    if not name then return self:Stop() end

    self.startTime = startMS / 1000
    self.endTime = endMS / 1000
    self.channelling = channelling
    self.holdUntil = nil

    self.bar:SetMinMaxValues(0, self.endTime - self.startTime)
    self.bar:SetValue(channelling and (self.endTime - self.startTime) or 0)
    colour(self.bar, 0.85, 0.70, 0.30)  -- warrior gold, same as the swing timer
    self.label:SetText(name)
    self.bar:Show()
end

function CB:Stop()
    self.startTime, self.endTime, self.channelling = nil, nil, nil
    if self.bar and not self.holdUntil then self.bar:Hide() end
end

-- Interrupted or failed: hold the bar red for a moment instead of vanishing, so
-- a bandage that got broken says so rather than just disappearing.
function CB:Fail(word)
    if not (self.bar and self.startTime) then return end
    self.startTime, self.endTime, self.channelling = nil, nil, nil
    colour(self.bar, 0.9, 0.25, 0.25)
    self.label:SetText(word)
    self.timer:SetText("")
    self.bar:SetValue(select(2, self.bar:GetMinMaxValues()))
    self.holdUntil = GetTime() + HOLD
    self.bar:Show()
end

-- Switched off: hide it and leave it hidden. Nothing else to restore -- the
-- frame is ours, so "off" is simply a bar that never shows.
function CB:Apply()
    if not self.bar then return end
    if HelloWarriorCharDB.showCastBar == false then
        self.startTime, self.holdUntil = nil, nil
        self.bar:Hide()
    end
end

function CB:SetVisible(visible)
    HelloWarriorCharDB.showCastBar = visible and true or false
    self:Apply()
    -- HelloUI hides Blizzard's cast bar only while ours exists AND the cluster
    -- is shown; it re-checks on its own apply pass, so turning ours off gets
    -- Blizzard's back without either addon calling the other.
    if visible then self:Start() end
end

local function onCast(unit)
    if unit ~= "player" then return end
    CB:Start()
end

ns:On("UNIT_SPELLCAST_START", onCast)
ns:On("UNIT_SPELLCAST_CHANNEL_START", onCast)
-- Pushback and channel ticks both just change the times; re-reading the API is
-- simpler and more accurate than adjusting them by hand.
ns:On("UNIT_SPELLCAST_DELAYED", onCast)
ns:On("UNIT_SPELLCAST_CHANNEL_UPDATE", onCast)

local function onStop(unit)
    if unit ~= "player" then return end
    CB:Stop()
end

ns:On("UNIT_SPELLCAST_STOP", onStop)
ns:On("UNIT_SPELLCAST_CHANNEL_STOP", onStop)

ns:On("UNIT_SPELLCAST_INTERRUPTED", function(unit)
    if unit == "player" then CB:Fail("Interrupted") end
end)
ns:On("UNIT_SPELLCAST_FAILED", function(unit)
    if unit == "player" then CB:Fail("Failed") end
end)

-- A cast can be in flight across a zone change (a hearthstone, most obviously),
-- and the START event for it has already been and gone.
ns:On("PLAYER_ENTERING_WORLD", function()
    if CB.bar and castInfo() then CB:Start() end
end)
