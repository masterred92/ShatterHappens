-- Shatter Happens: the Fingers / Ice Lance ledger in each detection mode, the meter after combat, the overlay rule.
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local S = W.S
local check = W.check
local ns = W.loadAddon(".", "ShatterHappens")
W.fire("PLAYER_LOGIN")
local SH, FS = ns.SH, _G.FrostSuite_1_0
local row = FS.rows.ShatterHappens
local FOF, LANCE, NOVA = 400669, 1240047, 10230

local function reset()
  W.combat = false; W.fire("PLAYER_REGEN_ENABLED"); W.advance(100)
  S.install(W); W.sounds = {}; W.prints = {}; W.meter = nil; W.loaded = nil
  FS.lastSound = -100; FS.flashKey = nil
  SH.ResetSession(); KennyShatterHappensDB.alertSeen = nil; SH.lit = {}
  W.fire("PLAYER_LOGIN")
end
local function fight() W.combat = true; W.fire("PLAYER_REGEN_DISABLED") end
local function endFight() W.combat = false; W.fire("PLAYER_REGEN_ENABLED"); W.advance(1.1) end

check(row.headText == "No fights yet." and SH.reset.shown, "idle: No fights yet + Reset button")

-- 1. Strict client (auras secret in combat, alert available): alert windows, Lances in/out.
reset(); fight()
check(SH.modes.fingers == "alert" and SH.modes.frozen == "none", "strict: Fingers by alert, Frozen hidden")
check(not SH.reset.shown, "Reset hidden in combat")
S.cast(LANCE)
check(SH.fight.unknown == 1 and SH.fight.outside == 0, "before any alert was seen: a Lance is unknown, never 'out'")
S.glow(LANCE, true)
check(SH.fight.gained == 1 and FS.Glowing() == "ShatterHappens" and row.headText == "FINGERS!", "alert window: gained + live pulse")
S.cast(LANCE); S.glow(LANCE, false)
check(SH.fight.inside == 1 and SH.fight.spent == 1, "Lance into the alert: inside + spent")
check(not row.lineText[1]:find("expired"), "alert mode can't see expiry: not shown")
S.cast(LANCE)
check(SH.fight.unknown == 2, "no alert but Frozen hidden: unknown, not 'out'")
W.meter = { total = 10000, rows = { { 116, 6000 }, { LANCE, 4000 } } }
endFight()
check(SH.lastFight and SH.lastFight.split and SH.lastFight.lance == 4000, "after combat: Ice Lance from the meter")
check(row.lineText[3]:find("40%%") and row.lineText[3]:find("avg 1333"), "share 40% and avg per Lance")
check(SH.reset.shown and KennyShatterHappensDB.session.fights == 1, "Reset back after combat, session counts the fight")

-- 2. Meter without an Ice Lance line: counting procs only. Secret meter: nil + 'secret'.
fight(); W.meter = { total = 5000, rows = { { 116, 5000 } } }; endFight()
check(row.lineText[3] == "counting procs only (the meter has no Ice Lance line)", "no Ice Lance line: counting procs only")
local secret = {}; W.secret[secret] = true
local m, why = SH.ReadMeter({ totalAmount = secret, combatSpells = {} })
check(m == nil and why == "secret", "secret meter numbers are never read")

-- 3. Never-secret Fingers and Frost Nova: charges from the buff, Lances in/out known.
reset(); S.never[FOF] = true; S.never[NOVA] = true; S.never[122] = true; S.never[865] = true; S.never[6131] = true; S.never[12494] = true
W.target = true; fight()
check(SH.modes.fingers == "aura" and SH.modes.frozen == "aura", "never-secret: Fingers + Frozen by aura")
S.cast(LANCE)
check(SH.fight.outside == 1, "Fingers down + target not frozen: out")
S.gain(FOF, 1, 15); S.update(FOF, 2)
check(SH.fight.gained == 2, "two charges gained")
S.update(FOF, 1); S.cast(LANCE)
check(SH.fight.spent == 1 and SH.fight.inside == 1, "a charge spent, Lance inside")
S.drop(FOF)
check(SH.fight.spent == 2 and SH.fight.expired == 0, "buff consumed early: spent")
S.gain(FOF, 1, 15); W.advance(15.2); S.drop(FOF)
check(SH.fight.expired == 1, "buff ran out: expired, not spent")
check(row.lineText[1]:find("spent 2 · expired 1", 1, true) ~= nil, "expired charges shown on the Fingers line")
S.unitGain("target", NOVA, 0, 8); S.cast(LANCE)
check(SH.fight.inside == 2, "Lance into Frost Nova: inside")
endFight()
check(SH.lastFight and not SH.lastFight.split and row.lineText[3] == "counting procs only (the meter has no Ice Lance line)", "empty meter: counting procs only")

-- 4. Nothing visible: Fingers hidden.
reset(); _G.C_SpellActivationOverlay = nil; fight()
check(SH.modes.fingers == "none" and row.lineText[1]:find("Fingers hidden") and row.statusText == "counting procs only", "no aura, no alert: Fingers hidden")
S.cast(LANCE)
check(SH.fight.unknown == 1, "hidden: Lance unknown")
endFight()

-- 5. Overlay off by default with ShatterPulse / MageProcs / Shadowflare loaded; /frost shatter pulse on overrides.
reset(); W.loaded = { MageProcs = true }
check(SH.OverlayOn() == false, "MageProcs loaded: live pulse off")
W.loaded = nil
check(SH.OverlayOn() == true, "alone: live pulse on")
W.loaded = { Shadowflare = true }; SH.Slash("pulse on")
check(SH.OverlayOn() == true, "pulse on overrides")
SH.Slash("pulse auto")
check(KennyShatterHappensDB.settings.overlay == nil, "auto is the default (not stored)")

-- 6. Reset refuses in combat; slash commands print.
fight()
check(SH.ResetSession() == false, "no reset in combat")
endFight()
check(SH.ResetSession() == true and KennyShatterHappensDB.session.fights == 0, "reset out of combat")
W.prints = {}; SH.Slash("debug"); SH.Slash("meter")
check(#W.prints >= 7, "debug + meter print")

-- 7. Not a Mage: hidden.
reset(); W.class = "WARRIOR"; W.fire("SPELLS_CHANGED")
check(row.state == "hidden", "non-Mage: hidden")
W.class = nil

W.done("ShatterHappens")
