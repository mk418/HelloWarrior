local ADDON_NAME, ns = ...

ns.CastBar = {}
local CB = ns.CastBar

-- Blizzard's own player cast bar dimensions, 195x13, deliberately: HelloUI
-- restyles that frame to look like this one for every non-Warrior, and two bars
-- that are meant to be the same bar should not differ in size depending on which
-- addon drew them. It is also simply better than the full-width version this
-- started as - a cast bar as wide as the ability grid reads as a progress bar
-- for the whole cluster.
local BAR_WIDTH = 195
local BAR_HEIGHT = 13
-- Small font for both strings. At 13 tall there is no room for a full-size one:
-- GameFontHighlight's ink stands proud of a 13px bar, which is exactly the
-- overspill HelloUI's version showed once its border art was hidden.
local FONT = "GameFontHighlightSmall"
local GAP = 4          -- between the bar and the header band below it
local TEXT_GAP = 2     -- between the range readout and the bar below it
local SECTION_GAP = 10 -- ActionBar's own spacing, used when the bar is off
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
    bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
    -- Directly above the header band, i.e. immediately over the rage bar. It
    -- was one slot higher to begin with, above the range readout, and that put
    -- it far enough from the cluster to read as a separate thing floating in
    -- space. The readout moves up instead (see Apply) -- it is a single word and
    -- does not mind the distance; a bar you are timing an interrupt against
    -- does.
    --
    -- Centred at a fixed width rather than stretched between the container's
    -- edges: the container's width varies with the player's race (a two-racial
    -- Undead bottom row is 356 wide against a Human's 316), and a cast bar that
    -- changes size per character is not the same bar as HelloUI's.
    bar:SetPoint("BOTTOM", container, "TOP", 0, GAP)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    -- Spell name on the left, countdown on the right: the two things you act on.
    local label = bar:CreateFontString(nil, "OVERLAY", FONT)
    label:SetPoint("LEFT", bar, "LEFT", 4, 0)
    label:SetPoint("RIGHT", bar, "RIGHT", -40, 0)
    label:SetJustifyH("LEFT")
    -- One line, always. Wrapped text in a 13px bar climbs straight out of it.
    if label.SetWordWrap then label:SetWordWrap(false) end
    if label.SetMaxLines then label:SetMaxLines(1) end
    self.label = label

    local timer = bar:CreateFontString(nil, "OVERLAY", FONT)
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
    self.container = container
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

-- The bar owns the strip it inserts, so switching it off has to give that strip
-- back: the range readout sits above the bar when there is one and returns to
-- the container's own top edge when there is not. Otherwise turning the bar off
-- would leave the readout floating over a 20px hole.
function CB:Apply()
    if not self.bar then return end

    local on = HelloWarriorCharDB.showCastBar ~= false

    local rangeText = ns.ActionBar.rangeText
    if rangeText and self.container then
        rangeText:ClearAllPoints()
        if on then
            rangeText:SetPoint("BOTTOM", self.bar, "TOP", 0, TEXT_GAP)
        else
            rangeText:SetPoint("BOTTOM", self.container, "TOP", 0, SECTION_GAP)
        end
    end

    if not on then
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
