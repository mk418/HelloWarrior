# HelloWarrior — Design Document

A lean, opinionated ability manager for World of Warcraft Classic Era Warriors. It lays out your abilities by role (DPS / tank), recommends the next press, dances stances for you inside secure macros, and surfaces the combat info a warrior actually watches — swing timer, rage, range — without ever casting for you. Companion to HelloHealer / HelloTotems; same conventions.

---

## Design philosophy

1. **Zero-config first launch.** Detect Warrior + spellbook, apply sensible defaults, ready to fight. A settings panel exists but is one screen, not twelve.
2. **Reliability over features.** Secure templates where possible, no clever in-combat reconfiguration, no Blizzard monkey-patching. The addon is **purely additive** — it never hides or touches Blizzard's or DragonflightUI's bars.
3. **You decide what to press; the addon makes it smart and fast.** It recommends and lays out; it never auto-casts or bots. Every cast comes from a secure button you click (or keybind), so click-to-cast stays legal in combat.

---

## Layout

```
                       MELEE / CHARGE / OUT              <- range readout (coloured)
        ┌────────────┬───────────────────────┬─────────┐
        │ ⛨  ⚔  ☠     │   rage bar  (top half) │  DPS /  │  header row
        │ stances    │   swing timer (bottom) │  TANK   │
        ├────────────┴───────────────────────┴─────────┤
        │ [ranged] [Battle][Demo][Intim] [racial] [swap]│  shouts, racials, off-hand swap
        ├───────────────────────────────────────────────┤
        │ [■][■][■][■][■][■][■]                          │  ability grid
        │ [■][■][■][■][■][■][■]                          │  (role-adaptive, collapses
        │ [■][■][■][■][■]                                │   hidden talents)
        └───────────────────────────────────────────────┘
```

- One **draggable container** holds everything; **locked by default** (`/hw pos unlock` to move, a faint backdrop marks "move mode").
- The **ability grid** swaps its whole macro set between DPS and tank via a secure snippet; hidden talents collapse within each row. DPS auto-wraps at 7/row; tank uses an explicit row layout.
- The **shouts row** carries the shouts, a weapon-adaptive ranged button, the player's **own race racials** (Stoneform, Blood Fury, …) appended after the shouts, and an **off-hand swap** button at the end.
- The **header** packs the stance buttons (left), the role toggle (right), and a stacked **rage bar + swing timer** between them.

## Current scope (implemented)

**Casting & layout**
- Role-adaptive DPS/tank bars; one secure button per slot, macro swapped by a `SecureHandlerStateTemplate` snippet on role toggle.
- **Stance-dance macros** — `/cast [nostance:N] <Stance>` then `/cast <Ability>`, so abilities work from any stance. DPS holds **Ctrl** to opt into a Berserker dance (a secure button can't read rage, so the rage-losing switch is opt-in); tanks always dance into Defensive where applicable.
- Single click-edge (`AnyUp`) so a press fires the macro once (not twice).
- **Buff auto-cancel** — ability macros `/cancelaura` wasted caster blessings (and Salvation for tanks) so they fall off as you engage.
- Weapon-adaptive **ranged button** (`[worn:Guns]…` picks Shoot/Throw).
- **In-combat off-hand swap** — one secure button toggles the off-hand between a saved weapon and a saved shield via a single self-evaluating `/equipslot [equipped:Shields] 17 <weapon>; 17 <shield>` macro (one conditional, one equip → no mid-macro bounce, no state machine, no in-combat `SetAttribute`). Only the off-hand changes, so the main-hand swing timer is untouched. Define the two ends by snapshotting your gear with `/hw swap` (once per item). The same secure `/equipslot` path is the only combat-legal swap — Equipment Manager is `#nocombat` and `EquipItemByName` only picks the item up onto the cursor in combat.

**Recommendation engine** (`Helper:Compute`)
- Priority-ranked **gold "optimal" ring** for the single best GCD press, plus soft flashes for other valid options.
- Flash rules: `off_cd`, `rage` threshold, `proc` window (Revenge/Overpower, from the combat log), `target_hp` (Execute), `nodebuff` (Sunder ≤5 stacks), `nobuff` + `refresh` (Battle Shout, glows 10s before expiry), `helper` (Bloodrage when the top pick is unaffordable), `independent` (off-GCD presses like Shield Block), `interrupt` (Pummel / Shield Bash glow when the target is mid-interruptible-cast and the kick is ready — fails open, since the not-interruptible flag is unreliable on 1.15.x).
- Affordability accounts for rage **after** a stance switch (Tactical Mastery retention).
- **On-next-swing abilities** (Heroic Strike / Cleave) are kept out of the optimal competition — they're queued in parallel, not pressed instead of a GCD ability — so Bloodthirst/Sunder win the recommendation while tanking.

**Combat info**
- **Swing timer** — main-hand, fills toward the next swing, hitbox-driven from the combat log (`SWING_*` plus the `SPELL_*` events for Heroic Strike / Cleave / Slam, which replace the white swing), rescaled on haste changes, with a seconds readout.
- **Rage bar** — current rage with a number, stacked with the swing timer in the header; throbs from red toward a hot warning colour at ≥80% rage in combat (the **rage-cap warning**), and **Heroic Strike / Cleave light up** at the same threshold so you dump the excess into them before it wastes. One shared trigger (`Helper:IsRageCapping`) fires both.
- **Melee-range indicator** — green `MELEE` / gold `CHARGE` / red `OUT`, hitbox-aware via `IsSpellInRange` of a real targeted melee ability; blank with no target.
- **Per-button out-of-range red tint**, GCD + cooldown sweeps, **queued-on-next-swing** autocast shine on Heroic Strike / Cleave, **active-stance** shine, rage/usability icon tint, stance-requirement corner badges.

**Controls**
- Addon-managed, **position-following keybindings** (override `CLICK` bindings remapped to whatever button sits in each on-screen slot), with a hover-and-press editor (`/hw keys`); disabled while the bars are hidden.
- Position lock/unlock/reset; show/hide the addon bars.

## Out of scope

- Auto-cast / "smart rotation" / botting. The addon recommends; you press.
- Hiding or restyling Blizzard / DragonflightUI / other action bars.
- Anything that touches non-Warrior gameplay.

---

## File structure

```
HelloWarrior/
├── HelloWarrior.toc
├── .luacheckrc             -- lua51 + WoW API surface for `luacheck .`
├── Core.lua                -- namespace, event dispatcher (ns:On, warrior gate),
│                              slash commands, shared ns:AttachShine/SetShine
├── Config.lua              -- saved-variable schema + defaults, settings panel
├── Abilities.lua           -- dps/tank/shout/racial catalogs, stance IDs, flash
│                              rules, tank row layout, unwanted-buff lists
├── Helper.lua              -- recommendation engine (Compute), proc windows,
│                              rage cost, range/aura/debuff evaluation
├── StanceIndicator.lua     -- the three stance buttons + active-stance shine
├── RoleToggle.lua          -- DPS/TANK toggle (secure flip handler)
├── ActionBar.lua           -- the cluster: buttons, layout, macros, glow/shine,
│                              cooldown/rage/range tint, range readout, rage bar,
│                              position/lock, the 0.1s ticker
├── SwingTimer.lua          -- main-hand swing timer
└── Keybinds.lua            -- position-following override bindings + keybind mode
```

Unlike HelloTotems (which ships a `Bindings.xml`), HelloWarrior binds at runtime via `SetOverrideBindingClick` so keys can follow the *visible* slot as hidden talents collapse the layout.

## Technical foundation

- **Secure cast path.** Buttons are `SecureActionButtonTemplate` with `type = "macro"`; the role swap runs in a `SecureHandlerStateTemplate` snippet (`SetAttribute`/`RunAttribute` only — both whitelisted in the restricted environment). All secure (re)configuration happens out of combat; `Relayout`, keybind `Apply`, and macro refresh no-op under `InCombatLockdown` and re-run on `PLAYER_REGEN_ENABLED`.
- **Non-secure overlays** (textures, status bars, font strings, the autocast shine) are toggled freely, including in combat — none are protected.
- **Shared shine** (`ns:AttachShine` / `ns:SetShine`) wraps Blizzard's `AutoCastShineTemplate`; a per-frame guard starts/stops the sparkle once per transition so the 0.1s ticker doesn't re-seed it.
- **Aura reads** use `C_UnitAuras` named `AuraData` fields (`.name`, `.expirationTime`) rather than positional `UnitBuff` returns, which are ambiguous on 1.15.x (the legacy `rank` slot shifts `expirationTime`).
- **One event frame**, `ns:On(event, fn)` dispatch, gated so non-Warriors load the addon as a no-op.
- `luacheck .` is clean (lua51 std, WoW API in `read_globals`).

## Ideas / TODO

Reactive combat cues:
- **Sound cues (opt-in)** — a short sound on Overpower/Revenge proc, entering Execute range, or an interrupt becoming available. (The interrupt *visual* alert already ships; this would be the optional audio half.)
- **Interrupt banner (opt-in)** — an optional on-screen banner / sound to pair with the existing Pummel·Shield Bash interrupt glow, for when a button flash isn't loud enough.

Maintenance tracking (extends the Sunder / Battle Shout upkeep flashes):
- **Debuff upkeep flashes** — Thunder Clap (attack-speed slow), Demoralizing Shout (AP reduction), Rend — flash when missing/expiring on the target.
- **Sunder stack readout** — show `3/5` on the Sunder button, not just the flash.

Tank:
- **Defensive prompt** — when health drops low, surface Shield Wall / Last Stand.

Polish / QoL:
- **Per-indicator toggles** — config checkboxes to enable/disable the swing timer, rage bar, and range readout individually.
- **Tooltips** on the new bars/indicators; a bolder **Execute-phase** cue under 20%.
- **Off-hand swing timer** for dual-wield Fury (the detection already reads the `isOffHand` flag); **parry-haste** modelling on the swing timer (40% reduction, 20% floor).

## Known constraints (Classic Era 1.15.x)

- **No exact yardage to a hostile target** — the API only exposes boolean range checks, so the range readout is in/out-of-melee (+ a charge band), never a number.
- **On-next-swing abilities have no queryable range** — `IsSpellInRange("Heroic Strike")` returns `nil`, so the melee readout uses a real targeted melee ability (Sunder Armor / Rend / Hamstring …) as its reference.
- **Charge/Intercept range checks are stance-restricted** (can read `nil` out of the required stance) and only report the *max*-range boundary, not the too-close dead zone; the charge band degrades to `OUT` rather than guess.
- **Secure frames can't be repositioned or reconfigured in combat**, and rage can't be read in the restricted environment — hence the opt-in (hold-Ctrl) Berserker dance rather than an automatic rage-aware one.
