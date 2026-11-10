-- LoanCraft: gold moving by trade and mail, the trade/mail side panels,
-- confirmation popups and reminders.
local _, ns = ...
local W = ns.W

---------------------------------------------------------------------------
-- Popups
---------------------------------------------------------------------------
local function popup(def)
  def.text = "%s"
  def.timeout = 0
  def.whileDead = true
  def.hideOnEscape = true
  def.preferredIndex = 3
  if def.OnAlt then def.OnButton3 = def.OnAlt end
  return def
end

local openPopups = {}
local function clearTag(self)
  local d = self.data
  if d and d.tag then openPopups[d.tag] = nil end
end

StaticPopupDialogs["LOANCRAFT_ACCEPT"] = popup({
  button1 = "Accept", button2 = "Later", button3 = "Dispute",
  multiple = 1,
  OnHide = clearTag,
  OnAccept = function(_, d)
    local loan = ns.db.loans[d.id]
    if not loan then return end
    loan.confirmed = true
    if loan.status == "disputed" then loan.status = "open" end
    ns.Touch(loan)
    ns.Sync.Send(loan.lender, "A", loan.id)
  end,
  OnAlt = function(_, d)
    local loan = ns.db.loans[d.id]
    if not loan then return end
    loan.status = "disputed"
    ns.Touch(loan)
    ns.Sync.Send(loan.lender, "D", loan.id)
    ns.Print("You disputed the loan from %s.", ns.Short(loan.lender))
  end,
})

StaticPopupDialogs["LOANCRAFT_CLAIM"] = popup({
  button1 = "Yes, count it", button2 = "No",
  multiple = 1,
  OnHide = clearTag,
  OnAccept = function(_, d)
    local loan = ns.db.loans[d.id]
    local c = loan and loan.claims and loan.claims[d.key]
    if not c then return end
    loan.claims[d.key] = nil
    ns.AddEvent(loan, { t = c.t, kind = "pay", amount = c.amount, src = c.src, key = c.key or d.key })
  end,
  OnCancel = function(_, d)
    local loan = ns.db.loans[d.id]
    local c = loan and loan.claims and loan.claims[d.key]
    if c then c.rejected = true; ns.Touch(loan) end
  end,
})

StaticPopupDialogs["LOANCRAFT_CONFIRM"] = popup({
  button1 = YES or "Yes", button2 = NO or "No",
  OnAccept = function(_, d) if d and d.onAccept then d.onAccept() end end,
})

function ns.ShowPopup(which, text, data)
  if data and data.tag then
    if openPopups[data.tag] then return end
    openPopups[data.tag] = true
  end
  local p = StaticPopup_Show(which, text, nil, data)
  if not p and data and data.tag then openPopups[data.tag] = nil end
  return p
end

function ns.Confirm(text, onAccept)
  ns.ShowPopup("LOANCRAFT_CONFIRM", text, { onAccept = onAccept })
end

function ns.AskAcceptLoan(loan, changed)
  if loan.status ~= "open" then return end
  local text = ("%s %s that you borrowed %s.\n%s\n\nAccept this debt?"):format(
    ns.Short(loan.lender), changed and "changed a loan: they say" or "recorded", ns.Money(ns.Lent(loan)), ns.TermsText(loan))
  ns.ShowPopup("LOANCRAFT_ACCEPT", text, { id = loan.id, tag = "A" .. loan.id })
end

function ns.AskConfirmClaim(loan, key)
  local c = loan.claims[key]
  local text = ("%s says they paid you %s (%s, %s).\nCount it toward their debt?"):format(
    ns.Short(loan.borrower), ns.Money(c.amount), c.src or "manual", date("%b %d %H:%M", c.t))
  ns.ShowPopup("LOANCRAFT_CLAIM", text, { id = loan.id, key = key, tag = "C" .. loan.id .. key })
end

function ns.DeleteLoan(id)
  local loan = ns.db.loans[id]
  if not loan then return end
  if ns.IAmLender(loan) then
    -- ponytail: tombstones never expire; a few bytes per deleted loan
    ns.db.deleted[id] = ns.Now()
    if loan.status == "open" then
      loan.status = "cancelled"
      ns.Sync.Send(loan.borrower, "X", loan.id)
    end
  end
  ns.db.loans[id] = nil
  ns.Changed()
end

function ns.Forgive(loan)
  local owed = ns.Balance(loan)
  if owed <= 0 then return end
  ns.AddEvent(loan, { t = ns.Now(), kind = "forgive", amount = owed, src = "manual" })
  ns.Print("Forgave %s of %s's debt.", ns.Money(owed), ns.Short(loan.borrower))
end

function ns.Extend(loan, days)
  loan.due = (loan.due and math.max(loan.due, ns.Now()) or ns.Now()) + days * ns.DAY
  loan.warnedOverdue, loan.warnedSoon = nil, nil
  ns.Print("%s's loan is now due %s.", ns.Short(loan.borrower), date("%b %d", loan.due))
  ns.Touch(loan)
end

---------------------------------------------------------------------------
-- Deciding what a gold transfer was
---------------------------------------------------------------------------
-- Choices shown for a transfer. dir "in" = I received gold, "out" = I gave gold.
function ns.TransferOptions(tr)
  local P, me, s = tr.partner, ns.Me(), ns.db.settings
  local who = ns.Short(P)
  local owesMe, iOwe = ns.Owed(me, P), ns.Owed(P, me)
  local hasAddon = ns.Sync.HasAddon(P)
  local o = {}
  if tr.dir == "in" then
    if owesMe > 0 then
      o[#o + 1] = { id = "repay", label = "Repayment from " .. who, sub = "They owe you " .. ns.Money(owesMe) }
    end
    if s.askNewLoans and not hasAddon and (tr.src == "trade" or iOwe > 0) then
      if iOwe > 0 then o[#o + 1] = { id = "add", label = "I borrowed more (add to my debt)", sub = "You owe " .. who .. " " .. ns.Money(iOwe) } end
      o[#o + 1] = { id = "newloan", label = "I borrowed this (new loan)", sub = who .. " doesn't use LoanCraft, so it's tracked on your side" }
    end
    o[#o + 1] = { id = "none", label = "Not a loan (sale, gift, other)" }
  else
    if iOwe > 0 then
      o[#o + 1] = { id = "repay", label = "Repayment to " .. who, sub = "You owe them " .. ns.Money(iOwe) }
    end
    if s.askNewLoans then
      if owesMe > 0 then o[#o + 1] = { id = "add", label = "Lend more (add to " .. who .. "'s loan)", sub = "They already owe you " .. ns.Money(owesMe) } end
      o[#o + 1] = { id = "newloan", label = "New loan to " .. who }
    end
    o[#o + 1] = { id = "none", label = "Gift / not a loan" }
  end
  return o
end

function ns.ResolveTransfer(tr, choice, o)
  o = o or {}
  local P, me, who = tr.partner, ns.Me(), ns.Short(tr.partner)
  local amount = math.max(0, math.min(o.amount or tr.amount, tr.amount))
  local iReceived = tr.dir == "in"
  -- for repay/add: who is the lender in this relationship
  local lender, borrower
  if choice == "repay" then
    lender, borrower = iReceived and me or P, iReceived and P or me
  else
    lender, borrower = iReceived and P or me, iReceived and me or P
  end
  tr.class = (choice == "newloan" or choice == "add") and "loan" or choice

  if choice == "repay" and amount > 0 then
    local applied, left = ns.ApplyPayment(lender, borrower, amount,
      { src = tr.src, key = o.key or tr.key, t = tr.t, loanId = o.loanId })
    if applied > 0 then
      local still = ns.Owed(lender, borrower)
      if iReceived then
        ns.Print("%s repaid you %s. %s", who, ns.Money(applied),
          still > 0 and ("They still owe " .. ns.Money(still) .. ".") or "|cff40ff40All paid off!|r")
      else
        ns.Print("You repaid %s %s. %s", who, ns.Money(applied),
          still > 0 and ("You still owe " .. ns.Money(still) .. ".") or "|cff40ff40Debt cleared!|r")
      end
      ns.Sound("coin")
    end
    if left > 0 then
      ns.Print("%s was more than %s owed and wasn't counted.", ns.Money(left), iReceived and "they" or "you")
    end
  elseif choice == "newloan" and amount > 0 then
    local t = o.terms or ns.TermsFor(P)
    local loan = ns.CreateLoan({ lender = lender, borrower = borrower, principal = amount,
      ratePct = t.ratePct, period = t.period, dueDays = t.dueDays, lateFeePct = t.lateFeePct,
      created = tr.t, src = tr.src })
    if iReceived then
      ns.Print("Recorded: you borrowed %s from %s (%s).", ns.Money(amount), who, ns.TermsText(loan))
    else
      ns.Print("Recorded: loan of %s to %s (%s).", ns.Money(amount), who, ns.TermsText(loan))
      ns.Sync.Hello(P, true)
    end
  elseif choice == "add" and amount > 0 then
    local loan = o.loanId and ns.db.loans[o.loanId] or ns.OpenLoans(lender, borrower)[1]
    if loan and loan.status == "open" then
      ns.AddEvent(loan, { t = tr.t, kind = "add", amount = amount, src = tr.src })
      ns.Print("Added %s to the loan (%s now owe%s %s).", ns.Money(amount), iReceived and "you" or who,
        iReceived and "" or "s", ns.Money(ns.Balance(loan)))
    else
      return ns.ResolveTransfer(tr, "newloan", o)
    end
  end
  if o.autoPerson ~= nil then ns.db.autoRepay[P:lower()] = o.autoPerson or nil end
  if ns.Prompt then ns.Prompt.Remove(tr) end
  ns.Changed()
end

-- A Pay/Lend button in LoanCraft says what the next transfer is for
function ns.SetIntent(i)
  i.at = GetTime()
  ns.intent = i
end

local function takeIntent(partner, amount, via)
  local i = ns.intent
  if not i or GetTime() - i.at > 900 or i.via ~= via or not ns.Same(i.partner, partner) then return nil end
  if i.kind == "lend" and i.amount ~= amount then return nil end
  ns.intent = nil
  return i
end

function ns.NewTransfer(tr)
  ns.RecordTransfer(tr)
  local s = ns.db.settings
  if tr.intent then
    local i = tr.intent
    tr.intent = nil
    return ns.ResolveTransfer(tr, i.kind == "lend" and "newloan" or "repay", { terms = i.terms, loanId = i.loanId })
  end
  if tr.tagged then return ns.ResolveTransfer(tr, "repay") end
  if tr.claimKey then return ns.ResolveTransfer(tr, "repay", { key = tr.claimKey }) end
  if tr.loanFunds then tr.class = "loan"; return end

  local opts = ns.TransferOptions(tr)
  if #opts == 1 then tr.class = "none"; return end
  local auto = s.repayMode == "auto" or ns.db.autoRepay[tr.partner:lower()]
  if auto and opts[1].id == "repay" and not tr.items then
    return ns.ResolveTransfer(tr, "repay")
  end
  ns.Prompt.Queue(tr)
end

-- give = gold I handed to partner, get = gold partner handed to me
function ns.HandleTransfer(partner, give, get, src, opts)
  opts = opts or {}
  if not partner or ns.Same(partner, ns.Me()) then return end
  if ns.IsMyChar(partner) then return end -- your own alts
  ns.NoteContact(partner, src)
  if get > 0 then
    ns.NewTransfer({ partner = partner, dir = "in", amount = get, src = src, key = opts.key, t = opts.t,
      items = opts.items, tagged = opts.tagged, claimKey = opts.claimKey, loanFunds = opts.loanFunds })
  end
  if give > 0 then
    ns.NewTransfer({ partner = partner, dir = "out", amount = give, src = src, key = opts.key, t = opts.t,
      items = opts.items, tagged = opts.tagged, loanFunds = opts.loanFunds,
      intent = takeIntent(partner, give, src) })
  end
end

---------------------------------------------------------------------------
-- Trade window
---------------------------------------------------------------------------
local trade = {}
ns.trade = trade

local function tradeHasItems()
  for i = 1, 6 do
    local ok1, a = pcall(GetTradePlayerItemInfo, i)
    local ok2, b = pcall(GetTradeTargetItemInfo, i)
    if (ok1 and a) or (ok2 and b) then return true end
  end
  return false
end

function ns.FillTrade(partner, amount)
  if not (TradeFrame and TradeFrame:IsShown() and trade.partner and ns.Same(trade.partner, partner)) then return false end
  amount = math.min(amount, GetMoney())
  if amount <= 0 then ns.Print("You don't have any gold for that."); return true end
  if MoneyInputFrame_SetCopper and TradePlayerInputMoneyFrame then
    MoneyInputFrame_SetCopper(TradePlayerInputMoneyFrame, amount)
  end
  if SetTradeMoney then pcall(SetTradeMoney, amount) end
  return true, amount
end

function ns.PayByTrade(partner)
  local owe = ns.Owed(partner, ns.Me())
  if owe <= 0 then return false end
  local ok, amount = ns.FillTrade(partner, owe)
  if ok and amount then
    ns.SetIntent({ kind = "pay", partner = partner, amount = amount, via = "trade" })
    ns.Print("Put %s in the trade%s. Click Trade to pay.", ns.Money(amount),
      amount < owe and (" (all you have; you owe " .. ns.Money(owe) .. ")") or "")
  end
  return ok
end

ns.On("TRADE_SHOW", function()
  local name = (GetUnitName and GetUnitName("NPC", true)) or UnitName("NPC")
  trade.partner = ns.FullName(name)
  trade.give, trade.get, trade.done, trade.items = 0, 0, false, false
  if not trade.partner then return end
  ns.Sync.Hello(trade.partner, true)
  ns.NoteContact(trade.partner, "trade")
  if ns.Panels then ns.Panels.UpdateTrade() end
end)

local function snapshot()
  if trade.partner and not trade.done then
    trade.give = GetPlayerTradeMoney() or 0
    trade.get = GetTargetTradeMoney() or 0
    trade.items = tradeHasItems()
  end
end
ns.On("TRADE_MONEY_CHANGED", snapshot)
ns.On("TRADE_PLAYER_ITEM_CHANGED", snapshot)
ns.On("TRADE_TARGET_ITEM_CHANGED", snapshot)
ns.On("TRADE_ACCEPT_UPDATE", snapshot)

ns.On("TRADE_CLOSED", function()
  if ns.Panels then ns.Panels.HideTrade() end
end)

ns.On("UI_INFO_MESSAGE", function(a, b)
  local msg = b or a
  if msg ~= ERR_TRADE_COMPLETE or not trade.partner or trade.done then return end
  trade.done = true
  if not ns.db.settings.autoTrade then return end
  if (trade.give or 0) > 0 or (trade.get or 0) > 0 then
    ns.HandleTransfer(trade.partner, trade.give or 0, trade.get or 0, "trade", { items = trade.items })
  end
end)

---------------------------------------------------------------------------
-- Mail
---------------------------------------------------------------------------
-- Subject tags: [LC:<nonce>] = repayment sent with LoanCraft, [LCL] = loan funds
local function makeNonce()
  return ("%x-%x"):format(ns.Now(), math.random(0, 4095))
end
local function readNonce(subject)
  local nonce = subject and subject:match("%[LC:(%x+%-%x+)%]")
  if not nonce then return nil end
  return nonce, tonumber(nonce:match("^(%x+)"), 16)
end

local pendingInbox = {}
local lastMoney

local function onTakeMoney(index)
  if not ns.db or not ns.db.settings.autoMail or not GetInboxHeaderInfo then return end
  local _, _, sender, subject, money, _, _, _, _, wasReturned = GetInboxHeaderInfo(index)
  if not money or money <= 0 or wasReturned or not sender or ns.Secret(sender) then return end
  local now = GetTime()
  for i = #pendingInbox, 1, -1 do
    local p = pendingInbox[i]
    if now - p.at > 30 then table.remove(pendingInbox, i)
    elseif p.index == index and p.money == money and now - p.at < 3 then return end
  end
  table.insert(pendingInbox, { index = index, sender = ns.FullName(sender), money = money,
    subject = subject or "", at = now })
end

if hooksecurefunc then
  if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", onTakeMoney) end
  if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", onTakeMoney) end
end

function ns.HandleIncomingMail(p)
  local me = ns.Me()
  if not p.sender then return end
  if p.subject:find("[LCL", 1, true) then
    return ns.HandleTransfer(p.sender, 0, p.money, "mail", { loanFunds = true })
  end
  local nonce, t = readNonce(p.subject)
  if nonce then
    return ns.HandleTransfer(p.sender, 0, p.money, "mail", { key = "M:" .. nonce, t = t, tagged = true })
  end
  -- The sender's LoanCraft already told me this mail is a repayment?
  for _, loan in ipairs(ns.OpenLoans(me, p.sender)) do
    for k, c in pairs(loan.claims or {}) do
      if c.src == "mail" and not c.rejected and c.amount == p.money then
        return ns.HandleTransfer(p.sender, 0, p.money, "mail", { claimKey = k, t = c.t })
      end
    end
  end
  ns.HandleTransfer(p.sender, 0, p.money, "mail", { key = "M:" .. p.sender .. ":" .. p.money .. ":" .. ns.Now() })
end

ns.On("PLAYER_MONEY", function()
  local now = GetMoney()
  local delta = now - (lastMoney or now)
  lastMoney = now
  if delta <= 0 or #pendingInbox == 0 then return end
  for i, p in ipairs(pendingInbox) do
    if p.money == delta then
      table.remove(pendingInbox, i)
      ns.HandleIncomingMail(p)
      return
    end
  end
end)

local outgoing
if hooksecurefunc and SendMail then
  hooksecurefunc("SendMail", function(recipient, subject)
    local money = (GetSendMailMoney and GetSendMailMoney())
      or (MoneyInputFrame_GetCopper and SendMailMoney and MoneyInputFrame_GetCopper(SendMailMoney)) or 0
    outgoing = { to = ns.FullName(recipient), money = money or 0, subject = subject or "" }
  end)
end

ns.On("MAIL_SEND_SUCCESS", function()
  local o = outgoing
  outgoing = nil
  if not o or not o.to or o.money <= 0 or not ns.db.settings.autoMail then return end
  if o.subject:find("[LCL", 1, true) then
    -- loan funds sent from the New loan dialog
    return ns.HandleTransfer(o.to, o.money, 0, "mail", {})
  end
  local nonce, t = readNonce(o.subject)
  if nonce then
    return ns.HandleTransfer(o.to, o.money, 0, "mail", { key = "M:" .. nonce, t = t, tagged = true })
  end
  ns.HandleTransfer(o.to, o.money, 0, "mail", { key = "M:" .. makeNonce() })
end)
ns.On("MAIL_FAILED", function() outgoing = nil end)

local function setMail(to, amount, subject)
  if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, nil, 2) end
  SendMailNameEditBox:SetText(ns.MailName(to))
  SendMailSubjectEditBox:SetText(subject)
  MoneyInputFrame_SetCopper(SendMailMoney, amount)
  if SendMailFrame_Update then pcall(SendMailFrame_Update) end
end

function ns.FillMail(lender, amount)
  if not (MailFrame and MailFrame:IsShown()) then return false end
  local owe = ns.Owed(lender, ns.Me())
  if owe <= 0 then return true end
  local postage = GetSendMailPrice and GetSendMailPrice() or 30
  amount = math.min(amount or owe, owe, GetMoney() - postage)
  if amount <= 0 then ns.Print("You don't have enough gold to pay."); return true end
  setMail(lender, amount, ("Loan repayment [LC:%s]"):format(makeNonce()))
  ns.Print("Mail ready: %s to %s%s. Press Send.", ns.Money(amount), ns.Short(lender),
    amount < owe and (" (you owe " .. ns.Money(owe) .. " in total)") or "")
  return true
end

function ns.LendByMail(partner, amount, terms)
  if not (MailFrame and MailFrame:IsShown()) then return false end
  setMail(partner, amount, "Loan from " .. ns.Short(ns.Me()) .. " [LCL]")
  ns.SetIntent({ kind = "lend", partner = partner, amount = amount, terms = terms, via = "mail" })
  ns.Print("Mail ready: lending %s to %s. Press Send and LoanCraft records the loan.", ns.Money(amount), ns.Short(partner))
  return true
end

function ns.LendByTrade(partner, amount, terms)
  local ok, put = ns.FillTrade(partner, amount)
  if not ok then return false end
  if put then
    ns.SetIntent({ kind = "lend", partner = partner, amount = put, terms = terms, via = "trade" })
    ns.Print("Put %s in the trade. Click Trade and LoanCraft records the loan.", ns.Money(put))
  end
  return true
end

ns.On("MAIL_SHOW", function()
  lastMoney = GetMoney()
  if ns.Panels then ns.Panels.UpdateMail() end
end)
ns.On("MAIL_SEND_SUCCESS", function() if ns.Panels then ns.Panels.UpdateMail() end end)
ns.On("MAIL_CLOSED", function() if ns.Panels then ns.Panels.HideMail() end end)

-- "Pay" from anywhere: mailbox or trade if open, otherwise explain
function ns.Pay(lender)
  if ns.FillMail(lender) or ns.PayByTrade(lender) then return end
  ns.Print("Open a mailbox (or trade %s) and click Pay; LoanCraft fills in the gold for you.", ns.Short(lender))
end

-- "Lend" from anywhere: put it in the trade or mail if one is open
function ns.LendNow(partner, amount, terms)
  if trade.partner and ns.Same(trade.partner, partner) and TradeFrame and TradeFrame:IsShown() then
    return ns.LendByTrade(partner, amount, terms), "trade"
  end
  if MailFrame and MailFrame:IsShown() then return ns.LendByMail(partner, amount, terms), "mail" end
  return false
end

---------------------------------------------------------------------------
-- Contacts from whispers
---------------------------------------------------------------------------
ns.On("CHAT_MSG_WHISPER", function(_, sender)
  if ns.Secret(sender) then return end
  local name = ns.FullName(sender)
  if not name then return end
  ns.NoteContact(name, "whisper")
  if ns.Counterparties()[name:lower()] then
    ns.Sync.Hello(name)
    ns.MaybeWhisperReminder(name)
  end
end)
ns.On("CHAT_MSG_WHISPER_INFORM", function(_, target)
  if ns.Secret(target) then return end
  ns.NoteContact(ns.FullName(target), "whisper")
end)

---------------------------------------------------------------------------
-- Reminders
---------------------------------------------------------------------------
function ns.ShowDebtWarning(loan, intro)
  local text = ("%sYou owe %s %s (%s)."):format(intro and (intro .. " ") or "", ns.Short(loan.lender),
    ns.Money(ns.Balance(loan)), ns.Plain(ns.DueText(loan)))
  ns.Print("|cffff4040%s|r", text)
  if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
  end
  ns.Sound("warn")
end

function ns.Remind(loan, manual)
  local other = loan.borrower
  if ns.Sync.HasAddon(other) then
    ns.db.nudged[loan.id] = ns.Now()
    ns.Sync.Send(other, "R", loan.id)
    if manual then ns.Print("Reminder sent to %s's LoanCraft.", ns.Short(other)) end
    return
  end
  if InCombatLockdown() then return end
  local msg = ("Hi! Friendly reminder: you owe me %s for a loan (%s). Thanks! [LoanCraft]"):format(
    ns.Money(ns.Balance(loan), true), ns.Plain(ns.DueText(loan)))
  ns.db.nudged[loan.id] = ns.Now()
  pcall(SendChatMessage, msg, "WHISPER", nil, ns.MailName(other))
  if manual then ns.Print("Whispered %s a reminder.", ns.Short(other)) end
end

function ns.MaybeWhisperReminder(name)
  if not ns.db.settings.whisperReminders or not name then return end
  local now = ns.Now()
  for _, l in ipairs(ns.OpenLoans(ns.Me(), name)) do
    if l.due and l.due < now and not ns.Sync.HasAddon(name) and now - (ns.db.nudged[l.id] or 0) > ns.DAY then
      ns.Remind(l)
      return
    end
  end
end

ns.On("GROUP_ROSTER_UPDATE", function()
  for name in pairs(ns.Sync.GroupMembers()) do
    local full = ns.FullName(name)
    if full and ns.Counterparties()[full:lower()] then ns.MaybeWhisperReminder(full) end
  end
end)

function ns.LoginCheck()
  local now = ns.Now()
  local owedToMe, iOwe = ns.Totals()
  local overdueMine, lateDebtors = {}, {}
  for _, l in ipairs(ns.MyLoans()) do
    if l.status == "open" then
      if ns.IAmLender(l) then
        if l.due and l.due < now then lateDebtors[#lateDebtors + 1] = l end
        for key, c in pairs(l.claims or {}) do
          if not c.rejected and (c.src ~= "mail" or now - c.t > 3 * ns.DAY) then ns.AskConfirmClaim(l, key) end
        end
      else
        if not l.confirmed then ns.AskAcceptLoan(l)
        elseif l.due and l.due < now + ns.DAY then overdueMine[#overdueMine + 1] = l end
      end
    end
  end
  for _, tr in ipairs(ns.PendingTransfers()) do ns.Prompt.Queue(tr, true) end
  if not ns.db.settings.loginReminders then return end
  if owedToMe > 0 or iOwe > 0 then
    ns.Print("Owed to you: %s  |  You owe: %s  (click the minimap coin to open)", ns.Money(owedToMe), ns.Money(iOwe))
  end
  for _, l in ipairs(lateDebtors) do
    ns.Print("%s owes you %s (%s).", ns.Short(l.borrower), ns.Money(ns.Balance(l)), ns.DueText(l))
  end
  for _, l in ipairs(overdueMine) do ns.ShowDebtWarning(l) end
end

ns.OnLogin(function()
  lastMoney = GetMoney()
  C_Timer.After(8, ns.LoginCheck)
  C_Timer.NewTicker(60, function()
    local now = ns.Now()
    for _, l in ipairs(ns.MyLoans()) do
      if l.status == "open" and l.due and (l.confirmed or ns.IAmLender(l)) then
        if l.due < now and not l.warnedOverdue then
          l.warnedOverdue = true
          if ns.IAmLender(l) then
            ns.Print("%s's loan is now overdue. They owe %s.", ns.Short(l.borrower), ns.Money(ns.Balance(l)))
          else
            ns.ShowDebtWarning(l, "Your loan just went overdue!")
          end
        elseif l.due >= now and l.due < now + 3 * 3600 and not l.warnedSoon and not ns.IAmLender(l) then
          l.warnedSoon = true
          ns.Print("|cffff9900Heads up: you owe %s %s, due in %s.|r", ns.Short(l.lender), ns.Money(ns.Balance(l)), ns.Duration(l.due - now))
        end
      end
    end
    ns.Changed()
  end)
end)
