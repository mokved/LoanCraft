-- LoanCraft: core data model (names, money, loans, interest, ledger, stats)
local ADDON, ns = ...
_G.LoanCraft = ns

ns.PREFIX = "LoanCraft"
-- Stamped into the TOC by the CurseForge packager at release time
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local tocVersion = GetMeta and GetMeta(ADDON, "Version")
ns.VERSION = (tocVersion and not tocVersion:find("@", 1, true)) and tocVersion or "dev"
local DAY = 86400
ns.DAY = DAY

local INTERFACE = select(4, GetBuildInfo()) or 0
-- WoW: Forever (1.60.x, interface 16001): no realms, characters are "First Last"
ns.IS_FOREVER = INTERFACE >= 16000 and INTERFACE < 20000

local DEFAULT_SETTINGS = {
  autoTrade = true,        -- watch trades
  autoMail = true,         -- watch mail
  repayMode = "ask",       -- "ask": confirm each repayment, "auto": count repayments automatically
  askNewLoans = true,      -- offer to record gold you hand over as a loan
  autoSync = true,         -- share records with the other player's LoanCraft
  loginReminders = true,
  peerReminders = true,    -- your LoanCraft nudges an overdue borrower's LoanCraft
  whisperReminders = false,-- whisper overdue borrowers who don't run LoanCraft
  payButtons = true,       -- LoanCraft panels on the mailbox and trade window
  unitTooltips = true,     -- "Owes you 50g" on player tooltips
  sounds = true,
  defaultRate = 0,         -- interest, percent per period
  defaultPeriod = 7,       -- interest period, days
  defaultDue = 14,         -- due date, days from now (0 = none)
  defaultLateFee = 0,      -- percent added once when a loan goes overdue
}
ns.DEFAULT_SETTINGS = DEFAULT_SETTINGS

---------------------------------------------------------------------------
-- Events and change notifications
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    eventFrame:RegisterEvent(event)
  end
  table.insert(handlers[event], fn)
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event]) do
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()(err) end
  end
end)

local listeners = {}
function ns.OnChange(fn) listeners[#listeners + 1] = fn end
local changePending = false
function ns.Changed()
  if changePending then return end
  changePending = true
  C_Timer.After(0, function()
    changePending = false
    for _, fn in ipairs(listeners) do
      local ok, err = pcall(fn)
      if not ok then geterrorhandler()(err) end
    end
  end)
end

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------
function ns.Now()
  return (GetServerTime and GetServerTime()) or time()
end

function ns.Print(fmt, ...)
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  DEFAULT_CHAT_FRAME:AddMessage("|cffe6b422LoanCraft:|r " .. msg)
end

-- Midnight-era clients hide some values ("secret values") from addons in combat
function ns.Secret(v)
  return issecretvalue ~= nil and issecretvalue(v) and true or false
end

function ns.Sound(kind)
  if not (ns.db and ns.db.settings.sounds and PlaySound and SOUNDKIT) then return end
  local id = kind == "warn" and SOUNDKIT.RAID_WARNING or kind == "coin" and (SOUNDKIT.LOOT_WINDOW_COIN_SOUND or SOUNDKIT.IG_BACKPACK_COIN_SELECT)
    or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
  if id then pcall(PlaySound, id) end
end

---------------------------------------------------------------------------
-- Names
--   Forever: "First Last" (unique per region, no realm)
--   Retail:  "Name-Realm"
-- Comparisons are always case-insensitive.
---------------------------------------------------------------------------
local function myRealm()
  local r = GetNormalizedRealmName and GetNormalizedRealmName()
  if (not r or r == "") and GetRealmName then
    r = (GetRealmName() or ""):gsub("[%s%-]", "")
  end
  return r
end

function ns.FullName(name)
  if type(name) ~= "string" or ns.Secret(name) then return nil end
  name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  if name == "" then return nil end
  if ns.IS_FOREVER then
    -- drop any "-Shard" suffix: names are region-unique and contain no hyphens
    name = name:gsub("%-.*$", "")
    name = name:gsub("(%S)(%S*)", function(a, b) return a:upper() .. b end)
    return name ~= "" and name or nil
  end
  name = name:gsub("%s", "")
  local base, realm = name:match("^([^%-]+)%-(.+)$")
  if not base then base, realm = name, myRealm() end
  base = base:sub(1, 1):upper() .. base:sub(2):lower()
  if realm and realm ~= "" then return base .. "-" .. realm end
  return base
end

-- How to show a name
function ns.Short(name)
  if not name then return "?" end
  if ns.IS_FOREVER then return name end
  return name:match("^([^%-]+)") or name
end

-- How to address someone (mail "To:", whispers)
function ns.MailName(name)
  if ns.IS_FOREVER then return name end
  local base, realm = name:match("^([^%-]+)%-(.+)$")
  if base and realm == myRealm() then return base end
  return name
end

function ns.Same(a, b)
  return a ~= nil and b ~= nil and a:lower() == b:lower()
end

function ns.UnitFull(unit)
  if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
  local n = GetUnitName and GetUnitName(unit, true)
  if ns.Secret(n) then return nil end
  if not n or n == "" then
    local a, b = UnitName(unit)
    if ns.Secret(a) or not a then return nil end
    if ns.IS_FOREVER and b and not ns.Secret(b) and b ~= "" then n = a .. " " .. b else n = a end
  end
  return ns.FullName(n)
end

local me
function ns.Me()
  if me then return me end
  local n = GetUnitName and GetUnitName("player", true)
  if not n or n == "" or ns.Secret(n) then
    local a, b = UnitName("player")
    n = (ns.IS_FOREVER and b and b ~= "") and (a .. " " .. b) or a
  end
  local full = ns.FullName(n)
  if ns.loggedIn then me = full end
  return full
end

---------------------------------------------------------------------------
-- Money
---------------------------------------------------------------------------
-- Coin icons for anything shown in the UI; plain = "12g 50s" for text sent to other players (whispers can't carry icons)
local ICON = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
function ns.Money(copper, plain)
  copper = math.floor((copper or 0) + 0.5)
  local neg = copper < 0
  copper = math.abs(copper)
  if copper == 0 and not plain then return "0" end -- a lone copper coin next to 0 reads as a bug
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = (plain and g or BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g) .. (plain and "g" or ICON:format("Gold")) end
  if s > 0 then parts[#parts + 1] = s .. (plain and "s" or ICON:format("Silver")) end
  if c > 0 or #parts == 0 then parts[#parts + 1] = c .. (plain and "c" or ICON:format("Copper")) end
  return (neg and "-" or "") .. table.concat(parts, " ")
end

-- "50", "12.5", "12g 50s", "1250s", "1,000g" -> copper (plain numbers are gold)
function ns.ParseMoney(str)
  if type(str) == "number" then return str >= 0 and math.floor(str * 10000 + 0.5) or nil end
  if type(str) ~= "string" then return nil end
  str = str:lower():gsub("(%d),(%d%d%d)", "%1%2"):gsub(",", "."):gsub("%s", "")
  if str == "" then return nil end
  local n = tonumber(str)
  if n then return n >= 0 and math.floor(n * 10000 + 0.5) or nil end
  local total, matched = 0, false
  local rest = str:gsub("([%d%.]+)([gsc])", function(num, unit)
    local v = tonumber(num)
    if not v then return nil end
    matched = true
    total = total + v * (unit == "g" and 10000 or unit == "s" and 100 or 1)
    return ""
  end)
  if not matched or rest ~= "" then return nil end
  return math.floor(total + 0.5)
end

function ns.Duration(sec)
  sec = math.abs(sec)
  if sec >= DAY then return math.floor(sec / DAY) .. "d" end
  if sec >= 3600 then return math.floor(sec / 3600) .. "h" end
  return math.max(1, math.floor(sec / 60)) .. "m"
end

function ns.Ago(t)
  local d = ns.Now() - t
  if d < 60 then return "just now" end
  return ns.Duration(d) .. " ago"
end

function ns.Plain(s)
  return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
function ns.InitDB()
  LoanCraftDB = LoanCraftDB or {}
  local db = LoanCraftDB
  db.loans = db.loans or {}
  db.settings = db.settings or {}
  for k, v in pairs(DEFAULT_SETTINGS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  db.peers = db.peers or {}       -- [lower name] = last time their LoanCraft answered
  db.nudged = db.nudged or {}     -- [loanId] = last reminder sent
  db.contacts = db.contacts or {} -- [lower name] = {name, t, src}
  db.transfers = db.transfers or {} -- gold seen moving between you and other players
  db.terms = db.terms or {}       -- [lower name] = last terms used with that player
  db.autoRepay = db.autoRepay or {} -- [lower name] = true: count their repayments without asking
  db.myChars = db.myChars or {}   -- your own characters (never asked about)
  db.deleted = db.deleted or {}   -- [loanId] = when I deleted it as lender (so sync can't bring it back)
  db.minimap = db.minimap or { angle = 200 }
  db.version = ns.VERSION
  for _, l in pairs(db.loans) do
    l.events = l.events or {}
    l.claims = l.claims or {}
  end
  ns.db = db
end

---------------------------------------------------------------------------
-- Loans
---------------------------------------------------------------------------
-- loan = { id, lender, borrower, principal, ratePct, period, lateFeePct, created, due,
--          events = {{t, kind = pay|forgive|add|fee, amount, src, key}}, claims = {},
--          status = open|closed|disputed|cancelled, confirmed, origin, changed, note }

function ns.NewId()
  return ("%x%04x"):format(ns.Now(), math.random(0, 65535))
end

function ns.Other(loan)
  if ns.Same(loan.lender, ns.Me()) then return loan.borrower end
  return loan.lender
end
function ns.IAmLender(loan) return ns.Same(loan.lender, ns.Me()) end
function ns.IsMine(loan) return ns.Same(loan.lender, ns.Me()) or ns.Same(loan.borrower, ns.Me()) end

function ns.CreateLoan(o)
  local created = o.created or ns.Now()
  local due = o.due
  if not due and o.dueDays and o.dueDays > 0 then due = created + math.floor(o.dueDays * DAY) end
  if due == 0 then due = nil end
  local loan = {
    id = o.id or ns.NewId(),
    lender = o.lender,
    borrower = o.borrower,
    principal = math.floor(o.principal),
    ratePct = o.ratePct or 0,
    period = math.max(1, o.period or 7),
    lateFeePct = o.lateFeePct or 0,
    created = created,
    due = due,
    events = {},
    claims = {},
    status = o.status or "open",
    confirmed = o.confirmed ~= false,
    origin = o.origin or ns.Me(),
    note = o.note,
    src = o.src,
  }
  ns.db.loans[loan.id] = loan
  if ns.IsMine(loan) then
    ns.NoteContact(ns.Other(loan), "loan")
    if ns.IAmLender(loan) then ns.RememberTerms(loan.borrower, loan) end
  end
  ns.Touch(loan)
  return loan
end

-- Walk a loan's history up to `at`. Interest compounds per period on the whole
-- balance; the late fee is added once at the due date. Payments pay interest
-- first, then principal. onEvent(e, interestPart, principalPart) is called for
-- each payment/forgiveness. Returns principalLeft, interestLeft (floats).
function ns.Walk(loan, at, onEvent)
  at = at or ns.Now()
  local p, i, t = loan.principal, 0, loan.created
  local r = (loan.ratePct or 0) / 100
  local period = math.max(1, loan.period or 7) * DAY
  local feePending = loan.due and (loan.lateFeePct or 0) > 0

  local function grow(to)
    if to > t then
      local total = p + i
      if r > 0 and total > 0 then i = i + total * ((1 + r) ^ ((to - t) / period) - 1) end
      t = to
    end
  end
  local function accrue(to)
    if feePending and to > loan.due then
      grow(loan.due)
      if p + i > 0 then i = i + (p + i) * loan.lateFeePct / 100 end
      feePending = false
    end
    grow(to)
  end

  for _, e in ipairs(loan.events) do
    if e.t > at then break end
    accrue(e.t)
    if e.kind == "fee" then
      i = i + e.amount
    elseif e.kind == "add" then
      p = p + e.amount
    else
      local toI = math.min(e.amount, i)
      local toP = math.min(e.amount - toI, p)
      i, p = i - toI, p - toP
      if onEvent then onEvent(e, toI, toP) end
    end
  end
  accrue(at)
  return p, i
end

function ns.Balance(loan, at)
  local p, i = ns.Walk(loan, at)
  return math.max(0, math.floor(p + i + 0.5))
end

function ns.Lent(loan)
  local sum = loan.principal
  for _, e in ipairs(loan.events) do if e.kind == "add" then sum = sum + e.amount end end
  return sum
end

function ns.Paid(loan)
  local sum = 0
  for _, e in ipairs(loan.events) do if e.kind == "pay" then sum = sum + e.amount end end
  return sum
end

-- Same payment recorded by both sides (or detected twice)?
function ns.FindDuplicate(loan, e)
  for _, x in ipairs(loan.events) do
    if e.key and x.key == e.key then return x end
    if x.kind == e.kind and math.abs(x.t - e.t) <= 600 then
      local tol = math.max(100, math.floor(math.max(x.amount, e.amount) * 0.01))
      if math.abs(x.amount - e.amount) <= tol then return x end
    end
  end
  -- A mail payment: the sender records it when sending, the receiver when collecting
  if e.src == "mail" and e.kind == "pay" then
    for _, x in ipairs(loan.events) do
      if x.src == "mail" and x.kind == "pay" and x.amount == e.amount and not x.matched and x.key ~= e.key
          and math.abs(x.t - e.t) <= 31 * DAY then
        x.matched = e.key or true
        return x
      end
    end
  end
end

function ns.AddEvent(loan, e)
  if ns.FindDuplicate(loan, e) then
    if e.key and loan.claims then loan.claims[e.key] = nil end
    return false
  end
  table.insert(loan.events, e)
  table.sort(loan.events, function(a, b) return a.t < b.t end)
  if e.key and loan.claims then loan.claims[e.key] = nil end
  if e.kind == "add" and loan.status == "closed" then loan.status = "open"; loan.closedAt = nil end
  ns.CheckClosed(loan)
  ns.Touch(loan)
  return true
end

function ns.CheckClosed(loan)
  if loan.status == "open" and ns.Balance(loan) <= 0 then
    loan.status = "closed"
    loan.closedAt = ns.Now()
    if ns.IAmLender(loan) then
      ns.Print("|cff40ff40%s has fully repaid you (%s).|r", ns.Short(loan.borrower), ns.Money(ns.Lent(loan)))
    elseif ns.Same(loan.borrower, ns.Me()) then
      ns.Print("|cff40ff40Loan from %s fully repaid. You're debt-free with them!|r", ns.Short(loan.lender))
    end
    ns.Sound("coin")
  end
end

function ns.Touch(loan)
  if loan then loan.changed = ns.Now() end
  if loan and ns.Sync and ns.Sync.OnLocalChange then ns.Sync.OnLocalChange(loan) end
  ns.Changed()
end

-- Open loans between a lender and a borrower, most urgent first
function ns.OpenLoans(lender, borrower)
  local list = {}
  for _, l in pairs(ns.db.loans) do
    if l.status == "open" and ns.Same(l.lender, lender) and ns.Same(l.borrower, borrower) then
      list[#list + 1] = l
    end
  end
  table.sort(list, function(a, b)
    local da, dbb = a.due or math.huge, b.due or math.huge
    if da ~= dbb then return da < dbb end
    return a.created < b.created
  end)
  return list
end

function ns.Owed(lender, borrower, includeUnconfirmed)
  local sum = 0
  for _, l in ipairs(ns.OpenLoans(lender, borrower)) do
    if l.confirmed or includeUnconfirmed or ns.IAmLender(l) then sum = sum + ns.Balance(l) end
  end
  return sum
end

-- Spread a payment over open loans (or one chosen loan), soonest due first.
-- Returns applied, leftover.
function ns.ApplyPayment(lender, borrower, amount, opts)
  opts = opts or {}
  local t = opts.t or ns.Now()
  local left = amount
  local list = ns.OpenLoans(lender, borrower)
  if opts.loanId then
    local chosen = ns.db.loans[opts.loanId]
    if chosen and chosen.status == "open" then
      for i, l in ipairs(list) do if l == chosen then table.remove(list, i) break end end
      table.insert(list, 1, chosen)
    end
  end
  local n = 0
  for _, loan in ipairs(list) do
    if left <= 0 then break end
    local owed = ns.Balance(loan, t)
    local part = math.min(left, owed)
    if part > 0 then
      n = n + 1
      local key = opts.key and (n > 1 and (opts.key .. "#" .. n) or opts.key) or nil
      ns.AddEvent(loan, { t = t, kind = opts.kind or "pay", amount = part, src = opts.src or "manual", key = key })
      left = left - part
    else
      ns.CheckClosed(loan)
    end
  end
  return amount - left, left
end

function ns.MyLoans()
  local list = {}
  for _, l in pairs(ns.db.loans) do
    if ns.IsMine(l) then list[#list + 1] = l end
  end
  return list
end

function ns.Totals()
  local owedToMe, iOwe = 0, 0
  for _, l in ipairs(ns.MyLoans()) do
    if l.status == "open" then
      if ns.IAmLender(l) then owedToMe = owedToMe + ns.Balance(l)
      elseif l.confirmed then iOwe = iOwe + ns.Balance(l) end
    end
  end
  return owedToMe, iOwe
end

-- Players with active loans (lower name -> name)
function ns.Counterparties()
  local set = {}
  for _, l in ipairs(ns.MyLoans()) do
    if l.status == "open" or l.status == "disputed" then
      local o = ns.Other(l)
      set[o:lower()] = o
    end
  end
  return set
end

-- Everyone you have loan history with, active first
function ns.People()
  local map, list = {}, {}
  for _, l in ipairs(ns.MyLoans()) do
    if l.status ~= "cancelled" then
      local o = ns.Other(l)
      local k = o:lower()
      local p = map[k]
      if not p then
        p = { name = o, owesMe = 0, iOwe = 0, last = 0, loans = 0, open = 0 }
        map[k] = p
        list[#list + 1] = p
      end
      p.loans = p.loans + 1
      p.last = math.max(p.last, l.changed or l.created)
      if l.status == "open" then
        p.open = p.open + 1
        if ns.IAmLender(l) then p.owesMe = p.owesMe + ns.Balance(l)
        elseif l.confirmed then p.iOwe = p.iOwe + ns.Balance(l) end
      end
    end
  end
  table.sort(list, function(a, b)
    local ax, bx = a.owesMe + a.iOwe, b.owesMe + b.iOwe
    if (ax > 0) ~= (bx > 0) then return ax > 0 end
    return a.last > b.last
  end)
  return list
end

function ns.IsMyChar(name)
  return name and ns.db.myChars[name:lower()] ~= nil
end

function ns.DueText(loan)
  if loan.status == "closed" then return "|cff40ff40repaid|r" end
  if loan.status == "cancelled" then return "|cff888888cancelled|r" end
  if loan.status == "disputed" then return "|cffff4040disputed|r" end
  if not loan.due then return "no due date" end
  local left = loan.due - ns.Now()
  if left < 0 then return "|cffff4040overdue " .. ns.Duration(left) .. "|r" end
  if left < DAY then return "|cffff9900due in " .. ns.Duration(left) .. "|r" end
  return "due in " .. ns.Duration(left)
end

function ns.PeriodText(days)
  if days == 1 then return "day" elseif days == 7 then return "week" elseif days == 14 then return "2 weeks"
  elseif days == 30 then return "month" end
  return days .. " days"
end

function ns.TermsText(loan)
  local parts = {}
  if (loan.ratePct or 0) > 0 then
    parts[#parts + 1] = ("%s%% per %s"):format(loan.ratePct, ns.PeriodText(loan.period))
  else
    parts[#parts + 1] = "no interest"
  end
  if loan.due then parts[#parts + 1] = date("due %b %d", loan.due) end
  if (loan.lateFeePct or 0) > 0 then parts[#parts + 1] = loan.lateFeePct .. "% late fee" end
  return table.concat(parts, ", ")
end

-- What a loan would cost if left unpaid until its due date
function ns.ProjectDue(principal, ratePct, period, dueDays, lateFeePct)
  if not dueDays or dueDays <= 0 then return nil end
  local fake = { principal = principal, ratePct = ratePct, period = period, lateFeePct = lateFeePct,
    created = 0, due = math.floor(dueDays * DAY), events = {} }
  return ns.Balance(fake, fake.due), ns.Balance(fake, fake.due + 1)
end

---------------------------------------------------------------------------
-- Contacts, terms memory
---------------------------------------------------------------------------
function ns.NoteContact(name, src)
  if not ns.db or not name or ns.Same(name, ns.Me()) or ns.IsMyChar(name) then return end
  local k = name:lower()
  local c = ns.db.contacts[k] or {}
  c.name, c.t, c.src = name, ns.Now(), src
  ns.db.contacts[k] = c
  -- keep the 80 most recent
  local n, oldestK, oldestT = 0, nil, math.huge
  for key, v in pairs(ns.db.contacts) do
    n = n + 1
    if v.t < oldestT then oldestK, oldestT = key, v.t end
  end
  if n > 80 and oldestK then ns.db.contacts[oldestK] = nil end
end

function ns.TermsFor(name)
  local s = ns.db.settings
  local t = name and ns.db.terms[name:lower()]
  if t then return t end
  return { ratePct = s.defaultRate, period = s.defaultPeriod, dueDays = s.defaultDue, lateFeePct = s.defaultLateFee }
end

function ns.RememberTerms(name, loan)
  local dueDays = loan.due and math.floor((loan.due - loan.created) / DAY + 0.5) or 0
  ns.db.terms[name:lower()] = { ratePct = loan.ratePct, period = loan.period, dueDays = dueDays, lateFeePct = loan.lateFeePct }
end

---------------------------------------------------------------------------
-- Transfers (gold seen moving between you and another player)
---------------------------------------------------------------------------
function ns.RecordTransfer(tr)
  tr.id = tr.id or ns.NewId()
  tr.t = tr.t or ns.Now()
  table.insert(ns.db.transfers, tr)
  while #ns.db.transfers > 300 do table.remove(ns.db.transfers, 1) end
  return tr
end

function ns.PendingTransfers()
  local list = {}
  for _, tr in ipairs(ns.db.transfers) do
    if tr.class == nil then list[#list + 1] = tr end
  end
  return list
end

-- A transfer that matches a payment event (dir "in" = I received)
-- Only matches the same channel: a mail payment never matches an old trade.
function ns.FindTransfer(partner, dir, amount, t, src)
  if src ~= "trade" and src ~= "mail" then return nil end
  local best
  for i = #ns.db.transfers, 1, -1 do
    local tr = ns.db.transfers[i]
    if tr.dir == dir and tr.src == src and ns.Same(tr.partner, partner) then
      local ok
      if src == "mail" then
        -- sent and collected can be days apart; mail amounts are exact
        ok = tr.amount == amount and math.abs(tr.t - t) <= 31 * DAY
      else
        ok = tr.amount >= amount and math.abs(tr.t - t) <= 900
      end
      if ok and (not best or (tr.class == nil and best.class ~= nil)) then best = tr end
    end
  end
  return best
end

---------------------------------------------------------------------------
-- Stats and reliability
---------------------------------------------------------------------------
function ns.PersonStats(name)
  local st = { loans = 0, open = 0, onTime = 0, late = 0, overdueNow = 0, lent = 0, borrowed = 0,
    owesMe = 0, iOwe = 0, last = 0, asBorrower = 0 }
  local now = ns.Now()
  for _, l in ipairs(ns.MyLoans()) do
    if ns.Same(ns.Other(l), name) and l.status ~= "cancelled" then
      st.loans = st.loans + 1
      st.last = math.max(st.last, l.changed or l.created)
      local lender = ns.IAmLender(l)
      if lender then
        st.lent = st.lent + ns.Lent(l)
        st.asBorrower = st.asBorrower + 1
        if l.status == "open" then
          st.open = st.open + 1
          st.owesMe = st.owesMe + ns.Balance(l)
          if l.due and l.due < now then st.overdueNow = st.overdueNow + 1; st.late = st.late + 1 end
        elseif l.status == "closed" then
          if l.due and (l.closedAt or 0) > l.due then st.late = st.late + 1 else st.onTime = st.onTime + 1 end
        end
      else
        st.borrowed = st.borrowed + ns.Lent(l)
        if l.status == "open" then st.open = st.open + 1; if l.confirmed then st.iOwe = st.iOwe + ns.Balance(l) end end
      end
    end
  end
  return st
end

-- One line about how well this player repays you
function ns.ReliabilityText(name)
  local st = ns.PersonStats(name)
  local judged = st.onTime + st.late
  if judged == 0 then
    if st.open > 0 and st.asBorrower > 0 then return "|cffaaaaaaFirst loan still running|r", st end
    return "|cffaaaaaaNo repayment history yet|r", st
  end
  local pct = st.onTime / judged
  local color = pct >= 0.9 and "40ff40" or pct >= 0.6 and "ffd200" or "ff4040"
  local label = pct >= 0.9 and "Reliable" or pct >= 0.6 and "Mostly on time" or "Often late"
  local text = ("|cff%s%s|r · %d of %d repaid on time"):format(color, label, st.onTime, judged)
  if st.overdueNow > 0 then text = text .. (" · |cffff4040%d overdue now|r"):format(st.overdueNow) end
  return text, st
end

---------------------------------------------------------------------------
-- Ledger (derived from loan histories) and profit/loss summary
---------------------------------------------------------------------------
-- entry = { t, kind = lend|borrow|collect|repay|forgive|forgiven, amount, interest, principal, partner, loan, src }
function ns.Ledger(person)
  local entries = {}
  for _, l in ipairs(ns.MyLoans()) do
    if l.status ~= "cancelled" and l.status ~= "disputed" and (l.confirmed or ns.IAmLender(l))
        and (not person or ns.Same(ns.Other(l), person)) then
      local lender, other = ns.IAmLender(l), ns.Other(l)
      entries[#entries + 1] = { t = l.created, kind = lender and "lend" or "borrow", amount = l.principal,
        partner = other, loan = l, src = l.src }
      for _, e in ipairs(l.events) do
        if e.kind == "add" then
          entries[#entries + 1] = { t = e.t, kind = lender and "lend" or "borrow", amount = e.amount,
            partner = other, loan = l, src = e.src, extra = true }
        end
      end
      ns.Walk(l, ns.Now(), function(e, toI, toP)
        local kind
        if e.kind == "forgive" then kind = lender and "forgive" or "forgiven"
        else kind = lender and "collect" or "repay" end
        entries[#entries + 1] = { t = e.t, kind = kind, amount = e.amount, interest = toI, principal = toP,
          partner = other, loan = l, src = e.src, event = e }
      end)
    end
  end
  table.sort(entries, function(a, b) return a.t > b.t end)
  return entries
end

function ns.Summary(since, person)
  local s = { lent = 0, collected = 0, interestEarned = 0, writtenOff = 0, borrowed = 0, repaid = 0,
    interestPaid = 0, forgivenToMe = 0, outstanding = 0, overdue = 0, iOwe = 0, count = 0 }
  for _, e in ipairs(ns.Ledger(person)) do
    if not since or e.t >= since then
      s.count = s.count + 1
      if e.kind == "lend" then s.lent = s.lent + e.amount
      elseif e.kind == "borrow" then s.borrowed = s.borrowed + e.amount
      elseif e.kind == "collect" then s.collected = s.collected + e.amount; s.interestEarned = s.interestEarned + e.interest
      elseif e.kind == "repay" then s.repaid = s.repaid + e.amount; s.interestPaid = s.interestPaid + e.interest
      elseif e.kind == "forgive" then s.writtenOff = s.writtenOff + e.principal
      elseif e.kind == "forgiven" then s.forgivenToMe = s.forgivenToMe + e.principal end
    end
  end
  local now = ns.Now()
  for _, l in ipairs(ns.MyLoans()) do
    if l.status == "open" and (not person or ns.Same(ns.Other(l), person)) then
      if ns.IAmLender(l) then
        local b = ns.Balance(l)
        s.outstanding = s.outstanding + b
        if l.due and l.due < now then s.overdue = s.overdue + b end
      elseif l.confirmed then
        s.iOwe = s.iOwe + ns.Balance(l)
      end
    end
  end
  for k, v in pairs(s) do if type(v) == "number" then s[k] = math.floor(v + 0.5) end end
  s.net = s.interestEarned - s.writtenOff - s.interestPaid + s.forgivenToMe
  return s
end

---------------------------------------------------------------------------
-- Things that need attention (minimap, window header)
---------------------------------------------------------------------------
-- level 3 = overdue, 2 = due within a day, 1 = needs a decision
function ns.Alerts()
  local list, top = {}, 0
  local now = ns.Now()
  local function add(level, text, loan)
    list[#list + 1] = { level = level, text = text, loan = loan }
    if level > top then top = level end
  end
  for _, l in ipairs(ns.MyLoans()) do
    if l.status == "open" then
      local lender, who = ns.IAmLender(l), ns.Short(ns.Other(l))
      if not lender and not l.confirmed then
        add(1, ("%s says you borrowed %s: accept?"):format(who, ns.Money(l.principal)), l)
      elseif l.due and l.due < now then
        add(3, lender and ("%s owes you %s, overdue %s"):format(who, ns.Money(ns.Balance(l)), ns.Duration(now - l.due))
          or ("You owe %s %s, overdue %s"):format(who, ns.Money(ns.Balance(l)), ns.Duration(now - l.due)), l)
      elseif l.due and l.due < now + DAY then
        add(2, lender and ("%s owes you %s, due in %s"):format(who, ns.Money(ns.Balance(l)), ns.Duration(l.due - now))
          or ("You owe %s %s, due in %s"):format(who, ns.Money(ns.Balance(l)), ns.Duration(l.due - now)), l)
      end
      if lender then
        for _, c in pairs(l.claims or {}) do
          if not c.rejected and c.src ~= "mail" then
            add(1, ("%s says they paid you %s"):format(who, ns.Money(c.amount)), l)
          end
        end
      end
    end
  end
  local pending = #ns.PendingTransfers()
  if pending > 0 then add(1, ("%d gold transfer%s to sort out"):format(pending, pending > 1 and "s" or "")) end
  table.sort(list, function(a, b) return a.level > b.level end)
  return list, top
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  ns.InitDB()
end)

ns.On("PLAYER_LOGIN", function()
  if not ns.db then ns.InitDB() end
  ns.loggedIn = true
  local mine = ns.Me()
  if mine then ns.db.myChars[mine:lower()] = mine end
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
  end
  for _, l in pairs(ns.db.loans) do
    if l.status == "open" and ns.IsMine(l) then ns.CheckClosed(l) end
  end
  for _, fn in ipairs(ns.loginHooks or {}) do
    local ok, err = pcall(fn)
    if not ok then geterrorhandler()(err) end
  end
  ns.Changed()
end)

function ns.OnLogin(fn)
  ns.loginHooks = ns.loginHooks or {}
  table.insert(ns.loginHooks, fn)
end
