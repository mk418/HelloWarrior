local ADDON_NAME, ns = ...

ns.Abilities = {}
local A = ns.Abilities

-- Stance IDs match GetShapeshiftForm() return values in Classic.
A.STANCE_ID = { battle = 1, defensive = 2, berserker = 3 }
A.STANCE_SPELL = { [1] = "Battle Stance", [2] = "Defensive Stance", [3] = "Berserker Stance" }
-- Spell IDs for stances — used to fetch icons even for unlearned stances.
A.STANCE_SPELL_ID = { [1] = 2457, [2] = 71, [3] = 2458 }

-- World buffs that can flip priority (see `prio_when` below).
A.WORLD_BUFFS = {
    DRAGONSLAYER = "Rallying Cry of the Dragonslayer",
    ZANDALAR     = "Spirit of Zandalar",
}

-- Flash rule shapes:
--   { type = "off_cd" }                                  pulse when the spell is off cooldown
--   { type = "rage",     threshold = N }                 pulse when current rage >= N
--   { type = "proc" }                                    pulse while the ability's proc window is open
--                                                         (e.g. Revenge after dodge/block/parry, Overpower after dodge)
--   { type = "target_hp", lt = N }                       pulse when target HP% < N
--   { type = "nodebuff",  spell = "Sunder Armor", stacks = 5 }
--                                                         pulse unless target has N stacks of `spell`
--   { type = "helper" }                                  Bloodrage; flashed by the rage-helper engine
--
-- `prio` (lower = higher priority). Blank prio → soft-flash only, never "optimal".
-- `prio_when` overrides prio when all listed buffs are present on the player.
-- `talentOnly = true` → button is hidden if the spell isn't in the spellbook
--                      (baseline spells the player hasn't reached the level for show desaturated instead).
-- `stance` is either a string ("any" / "battle" / "defensive" / "berserker")
--          or a list of strings for abilities usable in multiple stances.
--          For multi-stance, the FIRST entry is the default the macro switches into.
-- `mode = "two_press"` opts a button into `[stance:N] Ability; Stance` form
--          (safe-fail, no rage gamble). Default is one-press dance.
-- `combo = { modifier = "shift", use = "ItemName" }` — modifier-click uses an item first.

A.shouts = {
    { name = "Battle Shout",       stance = "any" },
    { name = "Demoralizing Shout", stance = "any" },
    { name = "Challenging Shout",  stance = "any",
      combo = { modifier = "shift", use = "Limited Invulnerability Potion" } },
    { name = "Intimidating Shout", stance = "any" },
    { name = "Piercing Howl",      stance = "any", talentOnly = true },
}

A.tank = {
    { name = "Revenge",        stance = "defensive", flash = { type = "proc" },    prio = 1 },
    { name = "Shield Block",   stance = "defensive", flash = { type = "off_cd" },  prio = 2 },
    { name = "Bloodthirst",    stance = "any", talentOnly = true,
      flash = { type = "off_cd" }, prio = 3 },
    { name = "Sunder Armor",   stance = "any",
      flash = { type = "nodebuff", spell = "Sunder Armor", stacks = 5 }, prio = 4 },
    { name = "Heroic Strike",  stance = "any",       flash = { type = "rage", threshold = 50 }, prio = 5 },
    { name = "Cleave",         stance = "any" },
    { name = "Taunt",          stance = "defensive" },
    { name = "Mocking Blow",   stance = "battle" },
    { name = "Shield Bash",    stance = { "defensive", "battle" } },
    { name = "Intercept",      stance = "berserker" },
    { name = "Bloodrage",      stance = "any",       flash = { type = "helper" } },
    { name = "Death Wish",     stance = "any", talentOnly = true },
    { name = "Shield Wall",    stance = "defensive" },
    { name = "Last Stand",     stance = "any", talentOnly = true },
}

A.dps = {
    { name = "Execute",        stance = { "berserker", "battle" },
      flash = { type = "target_hp", lt = 20 }, prio = 1,
      prio_when = { { buffs = { "Rallying Cry of the Dragonslayer", "Spirit of Zandalar" }, prio = 2 } } },
    { name = "Bloodthirst",    stance = "any", talentOnly = true,
      flash = { type = "off_cd" }, prio = 2,
      prio_when = { { buffs = { "Rallying Cry of the Dragonslayer", "Spirit of Zandalar" }, prio = 1 } } },
    { name = "Mortal Strike",  stance = "battle", talentOnly = true,
      flash = { type = "off_cd" }, prio = 2 },
    { name = "Whirlwind",      stance = "berserker", flash = { type = "off_cd" }, prio = 3 },
    { name = "Overpower",      stance = "battle",    flash = { type = "proc" },   prio = 3 },
    { name = "Heroic Strike",  stance = "any",       flash = { type = "rage", threshold = 50 }, prio = 5 },
    { name = "Hamstring",      stance = { "berserker", "battle" } },
    { name = "Charge",         stance = "battle" },
    { name = "Intercept",      stance = "berserker" },
    { name = "Pummel",         stance = "berserker" },
    { name = "Thunder Clap",   stance = "battle" },
    { name = "Berserker Rage", stance = "berserker" },
    { name = "Bloodrage",      stance = "any",       flash = { type = "helper" } },
    { name = "Recklessness",   stance = "berserker" },
    { name = "Retaliation",    stance = "battle" },
}
