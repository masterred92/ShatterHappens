-- Shatter Happens: a Fingers of Frost and Ice Lance ledger for Frost Mages on WoW: Forever. Written from scratch (MIT).
--
-- ShatterPulse, MageProcs and Shadowflare already flash Fingers of Frost and Frozen targets. This is the ledger they don't
-- keep, the Frost sibling of Gale Count: per fight and per session,
--   Fingers of Frost gained and spent, Ice Lances inside a Frozen / Fingers window and outside it,
-- and after combat Ice Lance's damage, share and average per Lance from Blizzard's own damage meter (C_DamageMeter), or
-- "counting procs only" when the meter has no Ice Lance line. It never shows a biggest hit (hit sizes are secret).
-- The optional live pulse (FINGERS! / FROZEN!) is off by default when ShatterPulse, MageProcs or Shadowflare is loaded.
--
-- What it can see (picked at runtime; /frost shatter debug prints it):
--   Fingers: "aura"  = Fingers of Frost (400669) readable right now: charges gained / spent from its applications; a buff
--                      that runs out unused counts as expired, not spent.
--            "alert" = the game's own spell alert on Ice Lance (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW): counts alert windows
--                      and Lances cast into them, not charges.
--            "none"  = neither: the box says "Fingers hidden".
--   Frozen:  "aura" when Frost Nova / Frostbite on your target is readable right now, else "none".
--   Lances:  your own Ice Lance UNIT_SPELLCAST_SUCCEEDED. A Lance is "in" when a window was visibly up, "out" when both
--            Fingers and the freeze were visibly down, and "unknown" otherwise. Never guessed.
--   Meter:   C_DamageMeter numbers are secret in combat; they are read only after combat, as plain numbers.
local ADDON, ns = ...
local C, Core, FS = ns.Compat, ns.Core, ns.FrostSuite
local L = Core.L

local SH = {}
KennyShatterHappens = SH
ns.SH = SH
local KEY = "ShatterHappens"
local SCHEMA = 1

SH.LANCE = { [1312002] = 1, [400640] = 2, [1240044] = 3, [1240045] = 4, [1240046] = 5, [1240047] = 6 }
SH.FINGERS = 400669
SH.FROZEN = { 122, 865, 6131, 10230, 12494 }
SH.OVERLAY_ADDONS = { "ShatterPulse", "MageProcs", "Shadowflare" }
SH.DEFAULTS = { overlay = "auto" } -- auto = on unless one of SH.OVERLAY_ADDONS is loaded

local db, settings, row
local migrations = {}
local function newCounts() return { gained = 0, spent = 0, expired = 0, inside = 0, outside = 0, unknown = 0, lances = 0 } end
local function newSession() return { gained = 0, spent = 0, expired = 0, inside = 0, outside = 0, unknown = 0, lances = 0,
  fights = 0, lanceDmg = 0, total = 0, measuredLances = 0, since = C.Now() } end
SH.fight = newCounts()
SH.lastFight = nil
SH.modes = { fingers = "none", frozen = "none" }
SH.lit = {}
local fofState -- { inst, apps, exp } of the Fingers buff last seen (aura mode)

local function now() return C.Clock() end
function SH.Session() return db and db.session end

-- ---------- detection ----------
function SH.EvaluateModes()
  local alertAPI = C_SpellActivationOverlay ~= nil and type(C_SpellActivationOverlay.IsSpellOverlayed) == "function"
  SH.modes.fingers = FS.AuraReadableNow(SH.FINGERS, "player") and "aura" or (alertAPI and "alert" or "none")
  local fz = false
  for _, id in ipairs(SH.FROZEN) do if FS.AuraReadableNow(id, "target") then fz = true end end
  SH.modes.frozen = fz and "aura" or "none"
  return SH.modes
end

function SH.OverlayOn()
  local o = settings and settings.overlay or "auto"
  if o == "on" then return true end
  if o == "off" then return false end
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    for _, n in ipairs(SH.OVERLAY_ADDONS) do if FS.Call(C_AddOns.IsAddOnLoaded, n) then return false end end
  end
  return true
end

local function add(field, n)
  n = n or 1
  SH.fight[field] = SH.fight[field] + n
  if db then db.session[field] = db.session[field] + n end
end

local function pulse(text)
  if not SH.OverlayOn() then return end
  FS.Headline(KEY, text, "ShardLilac")
  FS.RequestFlash(KEY, "PULSE")
end

-- Aura mode: read the Fingers buff and turn changes into gained / spent / expired charges.
function SH.ScanFingers()
  if SH.modes.fingers ~= "aura" then return end
  local a, ok = FS.ReadAura("player", SH.FINGERS)
  if not ok then return end
  if a then
    local cur = { inst = FS.AuraField(a, "auraInstanceID"), apps = math.max(1, FS.AuraField(a, "applications") or 1),
      exp = FS.AuraField(a, "expirationTime") }
    local was = fofState
    if not was or (cur.inst and was.inst and cur.inst ~= was.inst) then
      add("gained", cur.apps); pulse(L["FINGERS!"])
    elseif cur.apps > was.apps then add("gained", cur.apps - was.apps); pulse(L["FINGERS!"])
    elseif cur.apps < was.apps then add("spent", was.apps - cur.apps) end
    fofState = cur
  elseif fofState then
    if fofState.exp and fofState.exp - now() > 0.5 then add("spent", fofState.apps) else add("expired", fofState.apps) end
    fofState = nil
  end
end

-- true / false / nil (can't tell)
function SH.FingersUp()
  if SH.modes.fingers == "aura" then
    local a, ok = FS.ReadAura("player", SH.FINGERS)
    if ok then return a ~= nil end
  end
  if SH.modes.fingers ~= "none" and C_SpellActivationOverlay then
    for id in pairs(SH.LANCE) do
      if SH.lit[id] or FS.Call(C_SpellActivationOverlay.IsSpellOverlayed, id) == true then return true end
    end
    if db and db.alertSeen then return false end
  end
  return nil
end
function SH.Frozen()
  if SH.modes.frozen ~= "aura" or (UnitExists and not UnitExists("target")) then return nil end
  local all = true
  for _, id in ipairs(SH.FROZEN) do
    local a, ok = FS.ReadAura("target", id)
    if ok and a then return true end
    if not ok then all = false end
  end
  if all then return false end
  return nil
end

function SH.OnLance(spellID)
  local fof, frozen = SH.FingersUp(), SH.Frozen()
  add("lances")
  if fof or frozen then add("inside") elseif fof == false and frozen == false then add("outside") else add("unknown") end
  if SH.modes.fingers == "alert" and (SH.lit[spellID] or fof) then add("spent") end
  SH.lit[spellID] = nil
end

function SH.OnGlow(show, spellID)
  if C.IsSecret(spellID) or not SH.LANCE[spellID] then return end
  if show then
    if db then db.alertSeen = true end
    if not SH.lit[spellID] and SH.modes.fingers == "alert" then add("gained"); pulse(L["FINGERS!"]) end
    SH.lit[spellID] = true
  else SH.lit[spellID] = nil end
  SH.Paint()
end

-- ---------- Blizzard's damage meter (after combat only) ----------
local function playerGUID() return UnitGUID and UnitGUID("player") end
function SH.MeterSource()
  local M = C_DamageMeter
  if not (M and M.GetCombatSessionSourceFromType) then return nil end
  local cur = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
  local dmg = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
  local ok, src = pcall(M.GetCombatSessionSourceFromType, cur, dmg, playerGUID())
  if ok and type(src) == "table" then return src end
  return nil
end
-- { total, lance, rows } in plain numbers, or nil, why ("secret" in combat, "no meter data").
function SH.ReadMeter(src)
  src = src or SH.MeterSource()
  if type(src) ~= "table" then return nil, "no meter data" end
  local total = C.SafeNumber(src.totalAmount)
  if not total then return nil, "secret" end
  local out = { total = total, lance = 0, rows = {}, split = false }
  for _, sp in ipairs(type(src.combatSpells) == "table" and src.combatSpells or {}) do
    local id, amount = C.SafeNumber(sp.spellID), C.SafeNumber(sp.totalAmount)
    if not (id and amount) then return nil, "secret" end
    out.rows[#out.rows + 1] = { spellID = id, amount = amount }
    if SH.LANCE[id] then out.lance = out.lance + amount; out.split = true end
  end
  table.sort(out.rows, function(x, y) return x.amount > y.amount end)
  return out
end

function SH.Short(n)
  if not n then return "-" end
  if AbbreviateNumbers then local ok, s = pcall(AbbreviateNumbers, n); if ok and type(s) == "string" then return s end end
  return tostring(math.floor(n + 0.5))
end

-- ---------- fights ----------
function SH.StartFight()
  SH.fight = newCounts()
  SH.EvaluateModes()
  fofState = nil
  SH.ScanFingers()
  if SH.reset then SH.reset:Hide() end
  SH.Paint()
end

function SH.EndFight()
  local f = SH.fight
  local m = SH.ReadMeter()
  local res = { counts = f, metered = m ~= nil, split = m and m.split, total = m and m.total, lance = m and m.split and m.lance or nil }
  if db then
    db.session.fights = db.session.fights + 1
    if m and m.split then
      db.session.lanceDmg = db.session.lanceDmg + m.lance
      db.session.total = db.session.total + m.total
      db.session.measuredLances = db.session.measuredLances + f.lances
      db.meterSplits = true
    end
  end
  SH.lastFight = res
  if SH.reset and not C.InCombat() then SH.reset:Show() end
  SH.Paint()
  return res
end

function SH.ResetSession()
  if C.InCombat() then return false end
  db.session = newSession()
  SH.lastFight = nil
  SH.Paint()
  return true
end

-- ---------- box ----------
local function pct(a, b) return (b and b > 0) and ("%d%%"):format(math.floor(a / b * 100 + 0.5)) or "-" end
function SH.Lines()
  local f = SH.fight
  local fingers = SH.modes.fingers == "none" and L["Fingers hidden"]
    or ((SH.modes.fingers == "alert" and L["alerts"] or L["gained"]) .. " " .. f.gained .. " · " .. L["spent"] .. " " .. f.spent)
  local lances = ("%d %s · %d %s"):format(f.inside, L["in window"], f.outside, L["out"]) .. (f.unknown > 0 and (" · %d ?"):format(f.unknown) or "")
  return "|cffffd100" .. L["Fingers:"] .. "|r " .. fingers, "|cffffd100" .. L["Lances:"] .. "|r " .. lances
end

function SH.Paint()
  if not row then return end
  if not SH.known then FS.State(KEY, "hidden"); return end
  FS.ClearLines(KEY)
  local fl, ll = SH.Lines()
  if C.InCombat() then
    if FS.Glowing() ~= KEY then FS.Headline(KEY, L["this fight"], "ShardLilac") end
    FS.Line(KEY, 1, fl); FS.Line(KEY, 2, ll)
    FS.Status(KEY, SH.modes.fingers == "none" and L["counting procs only"] or "", "Mist")
    FS.State(KEY, "active")
    return
  end
  local r = SH.lastFight
  if not r then
    FS.Headline(KEY, L["No fights yet."], "Mist")
    FS.Line(KEY, 1, L["Use Frost spells and your Fingers of Frost show up here."])
  else
    FS.Headline(KEY, L["last fight"], "ShardLilac")
    FS.Line(KEY, 1, fl); FS.Line(KEY, 2, ll)
    if r.split then
      FS.Line(KEY, 3, ("|cffffd100%s|r %s (%s) · %s %s"):format(L["Ice Lance:"], SH.Short(r.lance), pct(r.lance, r.total),
        L["avg"], r.counts.lances > 0 and SH.Short(r.lance / r.counts.lances) or "-"))
    else
      FS.Line(KEY, 3, r.metered and L["counting procs only (the meter has no Ice Lance line)"] or L["counting procs only"])
    end
  end
  local s = db.session
  FS.Status(KEY, ("%s %d"):format(L["fights"], s.fights), "Mist")
  FS.State(KEY, "idle")
end

function SH.MeterLines()
  local m, why = SH.ReadMeter()
  if not m then return { "meter: " .. tostring(why) .. (why == "secret" and " (numbers are secret in combat; try after the fight)" or "") } end
  local out = { ("meter: total %s, Ice Lance %s (%s), lists Ice Lance separately: %s"):format(SH.Short(m.total), SH.Short(m.lance),
    pct(m.lance, m.total), tostring(m.split)) }
  for i = 1, math.min(8, #m.rows) do
    local r = m.rows[i]
    out[#out + 1] = ("  %d: %s%s"):format(r.spellID, SH.Short(r.amount), SH.LANCE[r.spellID] and " (Ice Lance)" or "")
  end
  return out
end

function SH.DetectionLines()
  SH.EvaluateModes()
  local s = db and db.session or newSession()
  local out = {
    ("Fingers: %s  (aura = charges from the buff, alert = the game's Ice Lance alert windows, none = hidden)"):format(SH.modes.fingers),
    ("Frozen target: %s  (aura = Frost Nova / Frostbite on your target read, none = hidden)"):format(SH.modes.frozen),
    ("live pulse: %s (setting %s; off by default when ShatterPulse, MageProcs or Shadowflare is loaded)"):format(tostring(SH.OverlayOn()), tostring(settings and settings.overlay)),
    ("Fingers 400669 aura secrecy: %s (0 = never secret); Ice Lance alert seen: %s"):format(tostring(FS.AuraSecrecy(SH.FINGERS)), tostring(db and db.alertSeen or false)),
    ("session: %d fights, gained %d, spent %d, expired %d, lances %d in / %d out / %d ?"):format(s.fights, s.gained, s.spent, s.expired, s.inside, s.outside, s.unknown),
    ("session meter: Ice Lance %s of %s, meter lists Ice Lance separately: %s"):format(SH.Short(s.lanceDmg), SH.Short(s.total), tostring(db and db.meterSplits)),
  }
  return out
end

function SH.Slash(msg)
  local cmd, a = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  if cmd == "meter" then for _, l in ipairs(SH.MeterLines()) do Core.Print(l) end
  elseif cmd == "pulse" and (a == "auto" or a == "on" or a == "off") then settings.overlay = a; Core.Print(L["live pulse:"] .. " " .. a)
  elseif cmd == "reset" then Core.Print(SH.ResetSession() and L["session reset"] or L["not in combat"])
  elseif cmd == "debug" then for _, l in ipairs(SH.DetectionLines()) do Core.Print(l) end
  else Core.Print("/frost shatter meter | pulse auto|on|off | reset | debug") end
end

-- ---------- wiring ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
for _, e in ipairs({ "PLAYER_LOGIN", "SPELLS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
  "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" }) do ev:RegisterEvent(e) end
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterUnitEvent("UNIT_AURA", "player", "target")

SH.known = true
local function refresh()
  if not C.InCombat() then SH.known = FS.IsMage() and FS.KnowsAny(SH.LANCE) ~= false end
  SH.EvaluateModes(); SH.Paint()
end
local handlers = {
  PLAYER_LOGIN = refresh, SPELLS_CHANGED = refresh,
  PLAYER_REGEN_DISABLED = SH.StartFight,
  PLAYER_REGEN_ENABLED = function() C_Timer.After(1, function() Core.SafeCall("endFight", SH.EndFight) end) end,
  PLAYER_TARGET_CHANGED = function() SH.EvaluateModes() end,
  UNIT_AURA = function(unit)
    if unit == "player" then SH.ScanFingers(); SH.Paint()
    elseif unit == "target" then
      local fz = SH.Frozen()
      if fz and not SH.frozenSeen then pulse(L["FROZEN!"]) end
      SH.frozenSeen = fz or nil
    end
  end,
  UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if unit ~= "player" or C.IsSecret(spellID) or not SH.LANCE[spellID] then return end
    SH.OnLance(spellID); SH.Paint()
  end,
  SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = function(id) SH.OnGlow(true, id) end,
  SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = function(id) SH.OnGlow(false, id) end,
}
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    db = Core.Migrate(KennyShatterHappensDB, migrations, SCHEMA)
    db.session = db.session or newSession()
    db.settings = db.settings or {}
    KennyShatterHappensDB = db
    settings = Core.Settings(db.settings, SH.DEFAULTS)
    row = FS.Register(KEY, db, { title = L["Shatter Happens"], slash = SH.Slash, help = "meter | pulse auto|on|off | reset | debug", debug = Core.PrintDebug })
    local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    b:SetSize(96, 18)
    b:SetPoint("BOTTOMLEFT", 8, 7)
    b:SetText(L["Reset"])
    b:SetScript("OnClick", function() SH.ResetSession() end)
    b:SetShown(not C.InCombat()) -- also hidden after a /reload in combat
    SH.reset = b
    Core.SafeCall("refresh", refresh)
    return
  end
  local h = handlers[event]
  if h and db then Core.SafeCall(event, h, ...) end
end)

Core.Setup({ cmd = "/frost shatter",
  required = { "C_Timer.After", "C_DamageMeter.GetCombatSessionSourceFromType" },
  optional = { "C_UnitAuras.GetPlayerAuraBySpellID", "C_UnitAuras.GetUnitAuraBySpellID", "C_Secrets.HasSecretRestrictions",
    "C_Secrets.GetSpellAuraSecrecy", "C_Secrets.ShouldSpellAuraBeSecret", "C_SpellActivationOverlay.IsSpellOverlayed",
    "C_AddOns.IsAddOnLoaded", "C_SpellBook.IsSpellKnown", "AbbreviateNumbers", "UnitGUID" },
  db = function() return db end,
  firstRun = { L["Shatter Happens is ready: a Fingers of Frost and Ice Lance ledger, with Ice Lance's share from the damage meter after each fight."] },
  debugLines = function() return SH.DetectionLines() end })
