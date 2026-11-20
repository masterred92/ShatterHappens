# Shatter Happens

A Fingers of Frost and Ice Lance ledger for Frost Mages on **WoW: Forever** (Interface 16001). Version 1.0.1. Part of Kenny's
Frost Suite, and it works alone.

ShatterPulse, MageProcs and Shadowflare already flash Fingers of Frost and Frozen targets. This keeps the ledger they don't, per
fight and per session:

- **Fingers of Frost:** gained and spent. A buff that runs out unused counts as expired, not spent.
- **Ice Lances:** inside a Frozen / Fingers window, outside one, or `?` when the game hides whether a window was up. A Lance is
  only called "out" when the box could see both that Fingers was down and that your target wasn't frozen.
- **After combat:** Ice Lance's damage, its share of your damage and the average per Lance, read from Blizzard's own damage
  meter. When the meter has no separate Ice Lance line, the box says `counting procs only`. There's no "biggest hit": hit sizes
  are hidden on Forever.

A **Reset** button clears the session (hidden in combat). The optional live pulse (`FINGERS!` / `FROZEN!`) is **off by default
when ShatterPulse, MageProcs or Shadowflare is loaded**, so you never get two flashes for the same thing.

## What it can see

The game hides some combat information from addons. The box picks the best source it's allowed and says when something is hidden:

| | Best | Fallback | Last resort |
| --- | --- | --- | --- |
| Fingers of Frost | the buff itself, when readable: real charges | the game's own spell alert on Ice Lance: alert windows, not charges | `Fingers hidden` |
| Frozen target | Frost Nova / Frostbite on your target, when readable | (none) | Lances count as `?` instead of "out" |
| Ice Lance casts | your own cast events | (none) | (none) |
| Damage | Blizzard's damage meter, after combat only (its numbers are hidden in combat) | (none) | `counting procs only` |

Whether the game shows its Ice Lance alert for Fingers of Frost can only be seen in game. `/frost shatter debug` shows what
was picked and why.

## Commands

The Frost Suite has no per-addon slash commands, only `/frost <sub>`. That keeps the risk of clashing with other addons low.

- `/frost shatter meter`: the last fight's damage meter lines for you, with Ice Lance marked
- `/frost shatter pulse auto|on|off`: the live pulse (auto = off when ShatterPulse, MageProcs or Shadowflare is loaded)
- `/frost shatter reset`: clear the session (out of combat)
- `/frost shatter debug`: what the box can see
- `/frost lock | unlock | scale 0.8-1.4 | reset | debug`: the shared dock

## Checks

`tests/run.sh <wow-ui-source>`, `tools/verify_unit_events.py <wow-ui-source>`, `tools/check_suite_lib.sh <frost-suite-lib folder>`, `tools/verify_media.sh`.
Spell IDs come from the game's data tables for build 1.60.1.70862.

MIT licence. Uses the game's own textures only, and casts, targets or moves nothing.
