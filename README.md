# HelloWarrior

A lean, opinionated ability manager for WoW Classic Era Warriors. It lays out your abilities by role, recommends the next press, dances stances for you inside secure macros, and surfaces the combat info a warrior actually watches — swing timer, rage, and melee range — without ever casting for you.

> **Heads up** — this is a personal work in progress. I build and evolve it as I play using it, so features land when I need them, design choices reflect my play style, and things may change between releases. Feel free to give it a whirl and leave me some feedback, but don't expect changes that fit your play style if it doesn't fit mine.

## What it does

- **Role-adaptive bars.** One click swaps the whole bar between DPS and tank layouts; abilities you haven't talented collapse away so you only see what you can use.
- **Tells you what to press.** A gold ring marks the highest-value ability to use right now (Revenge / Bloodthirst / Sunder priority, Execute under 20%, proc windows for Overpower and Revenge, …); softer flashes mark the other valid options.
- **Interrupt alert.** When your target starts an interruptible cast, Pummel (in Berserker) or Shield Bash (with a shield equipped) lights up while the kick is off cooldown.
- **Dances stances for you.** Abilities are wrapped in secure stance-dance macros, so e.g. Whirlwind works from any stance. Hold **Ctrl** as DPS to dance into Berserker for abilities that allow it.
- **Strips wasted buffs.** Using an ability drops caster blessings (and Salvation, for tanks) that are wasted on a Rage class.
- **Combat readouts.** A main-hand **swing timer**, a **rage bar** (it throbs near max in combat — and Heroic Strike / Cleave light up — so you dump the excess before it caps), and an in/out-of-**melee range** indicator, plus GCD and cooldown sweeps, an out-of-range tint, a queued-on-next-swing glow for Heroic Strike / Cleave, and a Battle Shout refresh reminder.
- **Racial + ranged button.** Your race's active racial (Stoneform, Blood Fury, War Stomp, …) and a weapon-adaptive ranged-pull button sit on the shouts row.
- **In-combat shield swap.** One button flips your off-hand between your weapon and a shield — shield up for a dangerous moment, then back to dual-wield, mid-fight. It only touches the off-hand, so your main-hand swing timer keeps ticking.
- **Your keybinds.** Bind keys to on-screen slots with a hover-and-press editor; the binding follows the visible button as the layout collapses.

## Usage

- `/hw` — list the commands; `/hw config` opens the settings panel.
- `/hw bars [on|off]` — show or hide the addon bars.
- `/hw pos [lock|unlock|reset]` — lock, move, or recenter the cluster (locked by default; unlock to drag).
- `/hw keys` — enter keybind mode (hover a button, press a key); `/hw keys clear|reset` manage them.
- `/hw swap` — save the off-hand swap toggle: run it with your off-hand weapon equipped, then again with your shield equipped (`/hw swap clear` forgets it). The button then flips between the two; bind it like any other slot.

## Caveats

- Only works on Classic Era, no support for other game versions.
- Loads as a no-op for non-Warrior characters.
- No auto-cast or rotation bot — it recommends and lays out, you press. (A secure button can't read rage, so the Berserker stance dance is opt-in via Ctrl rather than automatic.)
- Purely additive: it never hides or restyles Blizzard's or DragonflightUI's action bars.
- Opinionated defaults. One settings panel, not a twelve-tab profile editor — most things aren't user-tunable on purpose.
- It can't show an exact distance to a target (the Classic API doesn't expose enemy yardage), so the range readout is in-melee / charge-range / out rather than a number.

## License

Released under the [MIT License](LICENSE).
