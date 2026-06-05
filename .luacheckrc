-- luacheck configuration for HelloWarrior (World of Warcraft Classic Era addon).
-- WoW runs on Lua 5.1. From the addon root, run:  luacheck .

std = "lua51"

-- Macro/format strings and secure snippets push some lines long; line length
-- is stylistic, not a correctness signal here.
max_line_length = false

-- Silence unused-argument noise: event handlers (event, ...), OnUpdate(self,
-- elapsed), secure-template callbacks and the implicit `self` all legitimately
-- ignore some of their parameters.
unused_args = false

ignore = {
    "211/ADDON_NAME",  -- `local ADDON_NAME, ns = ...` idiom; name unused in most files
    "432/self",        -- inner callbacks (OnClick/OnDragStart/...) take their own `self`
}

-- True globals this addon owns or mutates. Everything else lives on the `ns`
-- table threaded in via `local _, ns = ...`.
globals = {
    "HelloWarriorDB",        -- SavedVariables
    "HelloWarriorCharDB",    -- SavedVariablesPerCharacter
    "SlashCmdList",          -- we install a handler key
    "SLASH_HELLOWARRIOR1",
    "SLASH_HELLOWARRIOR2",
}

-- WoW Classic Era API surface used by the addon. Read-only: indexing is fine,
-- assignment would be a real mistake worth flagging.
read_globals = {
    -- Frames / UI
    "CreateFrame",
    "UIParent",
    "GameTooltip",
    "GameTooltip_Hide",
    "Settings",
    "ReloadUI",
    "RegisterStateDriver",
    "InCombatLockdown",
    "print",
    "C_Timer",
    "Enum",
    -- Action-button proc-glow overlay (Blizzard FrameXML globals)
    "ActionButton_ShowOverlayGlow",
    "ActionButton_HideOverlayGlow",
    "ActionButton_OverlayGlowAnimOutFinished",
    -- Spell / ability info
    "GetSpellInfo",
    "GetSpellCooldown",
    "GetSpellPowerCost",
    "IsUsableSpell",
    -- Stances
    "GetShapeshiftForm",
    -- Talents
    "GetNumTalentTabs",
    "GetNumTalents",
    "GetTalentInfo",
    -- Units
    "UnitClass",
    "UnitPower",
    "UnitExists",
    "UnitIsDead",
    "UnitHealth",
    "UnitHealthMax",
    "UnitBuff",
    "UnitDebuff",
    "UnitGUID",
    -- Combat log / timing
    "CombatLogGetCurrentEventInfo",
    "GetTime",
    -- WoW Lua extensions
    "wipe",
}
