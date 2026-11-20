-- ShatterHappens: /reload with "Hide until I learn" already saved (FrostSuite r5). The saved choice is honoured on load, another
-- character's choice is not, and the box comes back by itself once the spell is learned.
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local check = W.check
W.level, W.known = 1, { [133] = true, [168] = true }
KennyShatterHappensDB = { hideUntilLearned = { ["Kenny-TestRealm"] = true, ["Alt-TestRealm"] = true } }   -- as saved before the reload
local ns = W.loadAddon(".", "ShatterHappens")
W.fire("PLAYER_LOGIN"); W.advance(2)
local FS = _G.FrostSuite_1_0
local row = FS.rows.ShatterHappens
local function know(ids, yes) for _, id in ipairs(ids) do W.known[id] = yes and true or nil end end

check(row.state == "hidden" and not (row.learnText and row.learnText.shown), "after /reload: still hidden, no learn line")
FS.Layout(); check(not row.shown, "takes no slot")
check(#ns.Core.errors == 0, "no Lua errors on load")
W.level = 20; know({ 116, 122 }, true); know({ 1312002 }, true)
W.fire("SPELLS_CHANGED"); W.advance(2)
check(row.state == "idle" and row.headText == "No fights yet." and ns.SH.reset.shown and KennyShatterHappensDB.hideUntilLearned["Kenny-TestRealm"] == nil, "learned: back by itself, this character's choice cleared")
check(KennyShatterHappensDB.hideUntilLearned["Alt-TestRealm"] == true, "another character's choice is kept")
W.level = 1; know({ 116, 122 }, false); know({ 1312002 }, false)
W.fire("SPELLS_CHANGED"); W.advance(2)
check(row.state == "learn" and row.learnText.shown and row.learnBtn.shown, "only another character hid it: this one shows the line")
W.done("ShatterHappens reload")
