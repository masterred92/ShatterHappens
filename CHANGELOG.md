# Changelog

## 1.0.1 (Nov 20, 2026)

- Layout fixes (FrostSuite-1.0 r4, shared by the suite): a status too long to sit beside the title moves to its own line instead of running into it, and box heights fit their text.
- The Reset button sits below all text (102 px before any fight, 116 px after one).
- TOC icon is now Fingers of Frost (`Ability_Mage_WintersGrasp`, 236227), the same icon as the box.

## 1.0.0 (Nov 20, 2026)

First release, part of the Frost Suite.

- Per fight and session: Fingers of Frost gained / spent / expired, and Ice Lances inside / outside a window (or `?` when hidden).
- After combat: Ice Lance damage, share and average per Lance from Blizzard's damage meter, or `counting procs only`.
- Reset button (hidden in combat). Optional live pulse, off by default when ShatterPulse, MageProcs or Shadowflare is loaded.
- `/frost shatter meter | pulse auto|on|off | reset | debug`. Docks with the other Frost Suite boxes.
