-- LoanCraft: sync with the other player's LoanCraft over hidden addon messages.
--
-- Trust rules (so nobody can erase a debt from someone else's book):
--   * The lender is authoritative for loan terms, payments and forgiveness.
--   * A loan the lender records shows up on the borrower's side as "needs your OK"
--     until the borrower accepts or disputes it.
--   * Payments reported by the borrower are only claims on the lender's side.
--     They are matched against gold the lender's own LoanCraft saw arrive.
local _, ns = ...
local S = {}
ns.Sync = S

local SEP = "~"
local queue, ticker = {}, nil
local recentTargets = {}  -- lower name -> GetTime() of our last whisper to them
local lastHello = {}
local lastPush = {}
local group = {}          -- lower name -> true for my party/raid members

---------------------------------------------------------------------------
-- Sending. Group members get messages over PARTY/RAID (addressed to them),
-- everyone else by addon whisper.
---------------------------------------------------------------------------
local function flush()
  local item = table.remove(queue, 1)
  if not item then
    if ticker then ticker:Cancel(); ticker = nil end
    return
  end
  if item.channel == "WHISPER" then
    recentTargets[item.to:lower()] = GetTime()
    recentTargets[ns.MailName(item.to):lower()] = GetTime()
  end
  pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, item.msg, item.channel, item.channel == "WHISPER" and ns.MailName(item.to) or nil)
end

function S.Send(to, ...)
  if not ns.db or not ns.db.settings.autoSync or not to then return end
  if ns.Same(to, ns.Me()) then return end
  local n = select("#", ...)
  local parts = {}
  for i = 1, n do
    local v = select(i, ...)
    if v == nil then v = "" elseif v == true then v = "1" elseif v == false then v = "0" end
    parts[i] = (tostring(v):gsub(SEP, ""))
  end
  local msg = table.concat(parts, SEP)
  local channel = "WHISPER"
  if group[to:lower()] then
    channel = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
    msg = "@" .. to .. SEP .. msg
  end
  if #msg > 250 then msg = msg:sub(1, 250) end
  table.insert(queue, { to = to, msg = msg, channel = channel })
  if not ticker then ticker = C_Timer.NewTicker(0.2, flush) end
end

-- Hide "No player named X is currently playing" caused by our own hidden pings
local notFoundPattern
local function systemFilter(_, _, msg, ...)
  if ns.Secret(msg) then return false, msg, ... end
  if not notFoundPattern then
    if not ERR_CHAT_PLAYER_NOT_FOUND_S then return false, msg, ... end
    local esc = ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    notFoundPattern = "^" .. esc:gsub("%%%%s", "(.+)") .. "$"
  end
  local who = msg and msg:match(notFoundPattern)
  if who then
    local t = recentTargets[who:lower()]
    if t and GetTime() - t < 10 then return true end
  end
  return false, msg, ...
end
if ChatFrame_AddMessageEventFilter then
  ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", systemFilter)
end

local function updateGroup()
  wipe(group)
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  local raid = IsInRaid and IsInRaid()
  for i = 1, raid and n or math.min(n, 4) do
    local name = ns.UnitFull(raid and ("raid" .. i) or ("party" .. i))
    if name then
      group[name:lower()] = true
      ns.NoteContact(name, "group")
    end
  end
end
ns.On("GROUP_ROSTER_UPDATE", updateGroup)
ns.On("PLAYER_ENTERING_WORLD", updateGroup)
function S.GroupMembers() return group end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
function S.HasAddon(name)
  local t = name and ns.db.peers[name:lower()]
  return t and (ns.Now() - t) < 30 * ns.DAY
end

-- Ping a counterparty; if their LoanCraft answers, both sides exchange state.
function S.Hello(name, force)
  if not name then return end
  local k = name:lower()
  if not force and lastHello[k] and GetTime() - lastHello[k] < 300 then return end
  lastHello[k] = GetTime()
  S.Send(name, "H", ns.VERSION)
end

local function sendLoan(to, loan)
  S.Send(to, "N", loan.id, loan.lender, loan.borrower, loan.principal, loan.ratePct,
    loan.period, loan.created, loan.due or 0, loan.lateFeePct, loan.status)
end

local function sendEvent(to, loan, e)
  S.Send(to, "P", loan.id, e.kind, e.amount, e.t, e.src, e.key)
end

function S.PushLoan(to, loan)
  sendLoan(to, loan)
  for _, e in ipairs(loan.events) do sendEvent(to, loan, e) end
  if ns.IAmLender(loan) then
    if loan.status == "cancelled" then S.Send(to, "X", loan.id) end
  else
    if loan.status == "disputed" then S.Send(to, "D", loan.id)
    elseif loan.confirmed then S.Send(to, "A", loan.id) end
  end
end

function S.PushState(peer, force)
  local k = peer:lower()
  if not force and lastPush[k] and GetTime() - lastPush[k] < 30 then return end
  lastPush[k] = GetTime()
  local now = ns.Now()
  for _, loan in ipairs(ns.MyLoans()) do
    if ns.Same(ns.Other(loan), peer) and (loan.status == "open" or loan.status == "disputed"
        or (loan.changed or 0) > now - 30 * ns.DAY) then
      S.PushLoan(peer, loan)
      if ns.IAmLender(loan) and loan.status == "open" and loan.due and loan.due < now
          and ns.db.settings.peerReminders and now - (ns.db.nudged[loan.id] or 0) > 12 * 3600 then
        ns.db.nudged[loan.id] = now
        S.Send(peer, "R", loan.id)
      end
    end
  end
end

function S.OnLocalChange(loan)
  if S.applyingRemote or not ns.IsMine(loan) then return end
  local other = ns.Other(loan)
  if S.HasAddon(other) then
    loan.pushPending = true
    C_Timer.After(1, function()
      if loan.pushPending then
        loan.pushPending = nil
        S.PushLoan(other, loan)
      end
    end)
  end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function split(s)
  local t = {}
  for f in (s .. SEP):gmatch("(.-)" .. SEP) do t[#t + 1] = f end
  return t
end

local handlers = {}

handlers.H = function(sender)
  S.Send(sender, "HR", ns.VERSION)
  S.PushState(sender)
end

handlers.HR = function(sender)
  S.PushState(sender)
end

handlers.N = function(sender, f)
  local id, lender, borrower = f[2], ns.FullName(f[3]), ns.FullName(f[4])
  local principal = tonumber(f[5])
  if not id or id == "" or not lender or not borrower or not principal or principal <= 0 then return end
  local me = ns.Me()
  local senderIsLender = ns.Same(sender, lender) and ns.Same(me, borrower)
  local senderIsBorrower = ns.Same(sender, borrower) and ns.Same(me, lender)
  if not senderIsLender and not senderIsBorrower then return end

  local terms = {
    principal = principal,
    ratePct = math.max(0, tonumber(f[6]) or 0),
    period = math.max(1, tonumber(f[7]) or 7),
    created = tonumber(f[8]) or ns.Now(),
    due = tonumber(f[9]) or 0,
    lateFeePct = math.max(0, tonumber(f[10]) or 0),
  }
  if terms.due == 0 then terms.due = nil end
  local status = f[11]

  -- I deleted this loan as its lender: tell the borrower again instead of re-creating it
  if ns.db.deleted[id] then
    if senderIsBorrower then S.Send(sender, "X", id) end
    return
  end

  local loan = ns.db.loans[id]
  -- an id I already have must be between the same two players
  if loan and not (ns.Same(loan.lender, lender) and ns.Same(loan.borrower, borrower)) then return end
  if not loan then
    if status == "cancelled" then return end
    loan = ns.CreateLoan({
      id = id, lender = lender, borrower = borrower, principal = terms.principal,
      ratePct = terms.ratePct, period = terms.period, created = terms.created,
      due = terms.due, lateFeePct = terms.lateFeePct, origin = sender,
      -- a loan someone says *I* owe needs my OK; a borrower admitting a debt doesn't
      confirmed = senderIsBorrower,
    })
    if senderIsLender then
      -- The gold for it arrived in a transfer I haven't sorted out yet? That's this loan.
      local tr = ns.FindTransfer(lender, "in", terms.principal, terms.created, "trade")
      if tr and tr.class == nil and ns.Prompt then ns.Prompt.Resolved(tr, "loan") end
      ns.AskAcceptLoan(loan)
    else
      ns.Print("%s recorded borrowing %s from you (%s).", ns.Short(borrower), ns.Money(principal), ns.TermsText(loan))
    end
    return
  end

  if senderIsLender then
    local changed = loan.principal ~= terms.principal or loan.ratePct ~= terms.ratePct
      or loan.period ~= terms.period or loan.due ~= terms.due or loan.lateFeePct ~= terms.lateFeePct
    if changed then
      local extendedOnly = loan.principal == terms.principal and loan.ratePct == terms.ratePct
        and loan.period == terms.period and loan.lateFeePct == terms.lateFeePct
        and (terms.due == nil or (loan.due and terms.due > loan.due))
      loan.principal, loan.ratePct, loan.period = terms.principal, terms.ratePct, terms.period
      loan.due, loan.lateFeePct, loan.created = terms.due, terms.lateFeePct, terms.created
      if loan.status ~= "cancelled" then
        loan.status = "open"
        ns.CheckClosed(loan)
        if extendedOnly then
          ns.Print("%s extended your loan: %s.", ns.Short(lender), loan.due and date("now due %b %d", loan.due) or "no due date anymore")
        else
          loan.confirmed = false
          ns.AskAcceptLoan(loan, true)
        end
        ns.Touch(loan)
      end
    end
  end
end

handlers.P = function(sender, f)
  local loan = ns.db.loans[f[2] or ""]
  if not loan or not ns.Same(ns.Other(loan), sender) then return end
  local kind, amount, t, src, key = f[3], tonumber(f[4]), tonumber(f[5]), f[6], f[7]
  if (kind ~= "pay" and kind ~= "forgive" and kind ~= "add") or not amount or amount <= 0 or not t then return end
  if key == "" then key = nil end
  local e = { t = t, kind = kind, amount = math.floor(amount), src = (src ~= "" and src or "sync"), key = key }

  if ns.Same(sender, loan.lender) then
    -- The lender's record: trusted.
    if loan.status == "cancelled" or loan.status == "disputed" then return end
    if ns.FindDuplicate(loan, e) then return end
    ns.AddEvent(loan, e)
    if kind == "add" then
      -- more debt needs my OK, just like a new loan
      loan.confirmed = false
      ns.AskAcceptLoan(loan, true)
    elseif kind == "pay" then
      -- Settles the matching gold I sent, if I hadn't sorted it out yet
      local tr = ns.FindTransfer(sender, "out", e.amount, e.t, e.src)
      if tr and tr.class == nil and ns.Prompt then
        ns.Prompt.Resolved(tr, "repay")
        ns.Print("%s's LoanCraft counted your %s as a repayment.", ns.Short(sender), ns.Money(e.amount))
      end
    elseif kind == "forgive" then
      ns.Print("|cff40ff40%s forgave %s of your debt.|r", ns.Short(sender), ns.Money(e.amount))
    end
    return
  end

  -- The borrower says they paid
  if kind ~= "pay" or ns.FindDuplicate(loan, e) then return end
  local tr = ns.FindTransfer(sender, "in", e.amount, e.t, e.src)
  if tr then
    if tr.class == "repay" then return end            -- already counted
    if tr.class == "none" or tr.class == "loan" then return end -- I decided it wasn't a repayment
    -- I saw the gold arrive and they call it a repayment: we agree, no need to ask.
    -- (Trades that also swapped items stay a question: the gold may have paid for them.)
    if not tr.items then
      ns.ResolveTransfer(tr, "repay", { amount = e.amount, key = e.key })
      return
    end
    tr.partnerSays = "repay"
    if ns.Prompt and ns.Prompt.Current() == tr then ns.Prompt.Show() end
    return
  end
  -- Mail: the payment and claim match up when I collect the mail
  if e.src == "mail" then
    for _, x in ipairs(loan.events) do
      if x.src == "mail" and x.amount == e.amount and x.t >= e.t - 60 and x.t <= e.t + 31 * ns.DAY then return end
    end
  end
  local ckey = key or ("C:" .. t .. ":" .. e.amount)
  loan.claims = loan.claims or {}
  if loan.claims[ckey] then return end
  loan.claims[ckey] = e
  ns.Touch(loan)
  if e.src ~= "mail" then ns.AskConfirmClaim(loan, ckey) end
end

handlers.A = function(sender, f)
  local loan = ns.db.loans[f[2] or ""]
  if not loan or not ns.Same(sender, loan.borrower) or not ns.IAmLender(loan) then return end
  if not loan.confirmed or loan.status == "disputed" then
    loan.confirmed = true
    if loan.status == "disputed" then loan.status = "open"; ns.CheckClosed(loan) end
    ns.Print("%s accepted the loan of %s.", ns.Short(sender), ns.Money(loan.principal))
    ns.Touch(loan)
  end
end

handlers.D = function(sender, f)
  local loan = ns.db.loans[f[2] or ""]
  if not loan or not ns.Same(sender, loan.borrower) or not ns.IAmLender(loan) then return end
  if loan.status ~= "disputed" then
    loan.status = "disputed"
    ns.Print("|cffff4040%s disputes the loan of %s.|r Talk to them, then delete or re-create it.", ns.Short(sender), ns.Money(loan.principal))
    ns.Touch(loan)
  end
end

handlers.X = function(sender, f)
  local loan = ns.db.loans[f[2] or ""]
  if not loan or not ns.Same(sender, loan.lender) then return end
  if loan.status ~= "cancelled" then
    loan.status = "cancelled"
    ns.Print("%s cancelled the loan of %s. You no longer owe it.", ns.Short(sender), ns.Money(loan.principal))
    ns.Touch(loan)
  end
end

handlers.R = function(sender, f)
  local loan = ns.db.loans[f[2] or ""]
  if not loan or not ns.Same(sender, loan.lender) or loan.status ~= "open" then return end
  ns.ShowDebtWarning(loan, ("%s is reminding you about your debt."):format(ns.Short(sender)))
end

ns.On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
  if prefix ~= ns.PREFIX or not ns.db or ns.Secret(msg) or ns.Secret(sender) then return end
  sender = ns.FullName(sender)
  if not sender or ns.Same(sender, ns.Me()) then return end
  local f = split(msg)
  if f[1] and f[1]:sub(1, 1) == "@" then
    if not ns.Same(ns.FullName(f[1]:sub(2)), ns.Me()) then return end -- for someone else in the group
    table.remove(f, 1)
  end
  ns.db.peers[sender:lower()] = ns.Now()
  local h = handlers[f[1]]
  if h then
    S.applyingRemote = true
    local ok, err = pcall(h, sender, f)
    S.applyingRemote = false
    if not ok then geterrorhandler()(err) end
  end
end)

---------------------------------------------------------------------------
-- Finding counterparties who are online
---------------------------------------------------------------------------
local lastScan = 0
function S.ScanOnline()
  if not ns.db or GetTime() - lastScan < 30 then return end
  lastScan = GetTime()
  local cps = ns.Counterparties()
  if not next(cps) then return end
  local function check(name)
    local full = name and ns.FullName(name)
    if full and cps[full:lower()] then S.Hello(full) end
  end
  if IsInGuild and IsInGuild() and GetNumGuildMembers then
    for i = 1, GetNumGuildMembers() do
      local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
      if online then check(name) end
    end
  end
  if C_FriendList and C_FriendList.GetNumFriends then
    for i = 1, C_FriendList.GetNumFriends() do
      local info = C_FriendList.GetFriendInfoByIndex(i)
      if info and info.connected then check(info.name) end
    end
  end
  for name in pairs(group) do check(name) end
end

ns.On("GUILD_ROSTER_UPDATE", S.ScanOnline)
ns.On("FRIENDLIST_UPDATE", S.ScanOnline)
ns.On("GROUP_ROSTER_UPDATE", function() lastScan = 0; S.ScanOnline() end)

ns.OnLogin(function()
  C_Timer.After(10, function()
    for _, name in pairs(ns.Counterparties()) do S.Hello(name) end
  end)
  C_Timer.NewTicker(600, function()
    lastScan = 0
    S.ScanOnline()
    for _, name in pairs(ns.Counterparties()) do S.Hello(name) end
  end)
end)
