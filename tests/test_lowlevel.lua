-- ShatterHappens: low-level characters (FrostSuite r5). A level 1 Mage (Fireball, Frost Armor), a mid-level Mage with only some
-- spells, and a non-Mage: loads quietly, never shows made-up data, says when to learn what it needs, "Hide until I learn"
-- is saved per character, and the box comes back by itself (no hand-cleared flags) on each event: SPELLS_CHANGED alone,
-- LEARNED_SPELL_IN_SKILL_LINE alone, PLAYER_LEVEL_UP alone, and PLAYER_REGEN_ENABLED after a change skipped in combat.
-- tests/test_lowlevel_reload.lua covers a /reload with the choice already saved.
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local check = W.check
W.level, W.known = 1, { [133] = true, [168] = true }   -- level 1: Fireball and Frost Armor
local ns = W.loadAddon(".", "ShatterHappens")
W.fire("PLAYER_LOGIN"); W.advance(2)
local FS = _G.FrostSuite_1_0
local row = FS.rows.ShatterHappens
local ME = "Kenny-TestRealm"
local function quiet(label)
  local bad = false
  for _, p in ipairs(W.prints) do if p:find("WARNING") or p:lower():find("error") then bad = true end end
  check(#ns.Core.errors == 0 and not bad, label .. ": no Lua errors, nothing alarming in chat")
end
local function learnLine() return row.state == "learn" and row.learnText and row.learnText.shown and row.learnText.text_ or nil end
local function saved() return KennyShatterHappensDB.hideUntilLearned ~= nil and KennyShatterHappensDB.hideUntilLearned[ME] == true end
local function fight(ids)
  W.combat = true; W.fire("PLAYER_REGEN_DISABLED")
  for _, id in ipairs(ids or { 133 }) do W.S.cast(id) end
  W.advance(3)
end
local function peace() W.combat = false; W.fire("PLAYER_REGEN_ENABLED"); W.advance(3) end
local function know(ids, yes) for _, id in ipairs(ids) do W.known[id] = yes and true or nil end end
local function works() return row.state == "idle" and row.headText == "No fights yet." and ns.SH.reset.shown end

-- A. Level 1: one calm line, quiet; it steps aside in combat and comes back after
check(learnLine() == "Learn Ice Lance at level 20", "level 1: 'Learn Ice Lance at level 20'")
check(row.h == 64 and not row.head.shown and not row.bar.shown and (row.statusText or "") == "", "one line in a 64 px box: no headline, bar or status")
check(row.learnBtn.shown and row.learnBtn.text_ == "Hide until I learn", "with its small button")
quiet("level 1 login")
fight()
check(not row.shown and not row.learnBtn.shown, "level 1 in combat: hidden, no button")
quiet("level 1 combat")
peace()
check(learnLine() == "Learn Ice Lance at level 20" and row.learnBtn.shown, "after combat the line and button are back")

-- B. Hide until I learn: hidden and saved for this character
row.learnBtn.scripts.OnClick(row.learnBtn)
check(row.state == "hidden" and saved(), "Hide until I learn: hidden, saved for this character")
FS.Layout(); check(not row.shown, "takes no slot in the dock")

-- C. SPELLS_CHANGED alone with only part of what it needs: still hidden, choice kept, the need moves on
W.level = 14; know({ 116, 122 }, true); W.fire("SPELLS_CHANGED"); W.advance(2)
check(row.state == "hidden" and saved(), "level 14, partial spells: still hidden, choice kept")
check(FS.NeedText(ns.SH.need) == "Learn Ice Lance at level 20", "the line it would show now: 'Learn Ice Lance at level 20'")

-- D. LEARNED_SPELL_IN_SKILL_LINE alone: the box comes back by itself and forgets the choice
W.level = 20; know({ 1312002 }, true)
W.fire("LEARNED_SPELL_IN_SKILL_LINE", 1312002); W.advance(2)
check(works() and not saved(), "LEARNED_SPELL_IN_SKILL_LINE alone: back by itself, choice cleared (not by hand)")
check(not row.learnText.shown and not row.learnBtn.shown, "no learn line or button once it works")
quiet("learned")

-- E. SPELLS_CHANGED alone, both ways (unlearned, e.g. a talent reset; then learned again)
W.level = 14; know({ 1312002 }, false)
W.fire("SPELLS_CHANGED"); W.advance(2)
check(learnLine() == "Learn Ice Lance at level 20", "SPELLS_CHANGED alone: the line comes back when the spell is gone")
know({ 1312002 }, true)
W.fire("SPELLS_CHANGED"); W.advance(2)
check(works() and learnLine() == nil, "SPELLS_CHANGED alone: the box works again")

-- F. PLAYER_LEVEL_UP alone: the line follows the new level (the event's level, before UnitLevel catches up)
know({ 1312002 }, false)
W.fire("SPELLS_CHANGED"); W.advance(2)
check(learnLine() == "Learn Ice Lance at level 20", "back to the learn line at level 14")
W.fire("PLAYER_LEVEL_UP", 21); W.advance(2)
check(learnLine() == "Learn Ice Lance from your trainer", "PLAYER_LEVEL_UP alone: 'Learn Ice Lance from your trainer'")

-- G. Learned during combat (SPELLS_CHANGED is skipped in combat): PLAYER_REGEN_ENABLED picks it up
row.learnBtn.scripts.OnClick(row.learnBtn)
check(row.state == "hidden" and saved(), "hidden again")
W.combat = true; W.fire("PLAYER_REGEN_DISABLED")
know({ 1312002 }, true)
W.fire("SPELLS_CHANGED"); W.advance(1)
W.combat = false; W.fire("PLAYER_REGEN_ENABLED"); W.advance(3)
check(works() and not saved(), "learned in combat: back by itself after combat")
quiet("mid level")

-- H. Not a Mage: never a learn line, never an error
W.class = "WARRIOR"; W.known = {}; W.level = 1; W.fire("SPELLS_CHANGED"); W.fire("PLAYER_LEVEL_UP", 2); W.advance(2)
check(row.state == "hidden" and not learnLine(), "non-Mage: hidden, no learn line")
fight({ 78 }); peace()
quiet("non-Mage")
W.class = nil
check(KennyShatterHappensDB.session.fights == 0, "fights before Ice Lance (and the non-Mage fight) are not counted")
check(not ns.SH.reset.shown or row.state ~= "learn", "the Reset button never sits over the learn button")
W.done("ShatterHappens low level")
