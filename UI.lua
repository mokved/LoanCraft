-- LoanCraft: main window (Loans / People / Ledger), dialogs, options, slash commands
local _, ns = ...
local W = ns.W
local UI = {}
ns.UI = UI

local frame
local state = { tab = "loans", showClosed = false, person = nil, period = 0 }

---------------------------------------------------------------------------
-- Small dialogs: record a payment / lend more
---------------------------------------------------------------------------
local payDlg
local function submitPayment()
  local d = payDlg
  local amount = d.money:GetCopper()
  if amount <= 0 then ns.Print("Enter an amount."); return end
  local loan = d.loan
  if d.mode == "add" then
    ns.AddEvent(loan, { t = ns.Now(), kind = "add", amount = amount, src = "manual" })
    ns.Print("Added %s. %s now owe%s %s.", ns.Money(amount), ns.IAmLender(loan) and ns.Short(loan.borrower) or "You",
      ns.IAmLender(loan) and "s" or "", ns.Money(ns.Balance(loan)))
  else
    local applied, left = ns.ApplyPayment(loan.lender, loan.borrower, amount, { src = "manual", loanId = loan.id })
    ns.Print("Recorded %s.%s", ns.Money(applied), left > 0 and (" (" .. ns.Money(left) .. " more than owed wasn't counted)") or "")
  end
  d:Hide()
end

function UI.OpenPayment(loan, mode)
  if not payDlg then
    payDlg = W.Panel("LoanCraftPayment", 340, 150, "Record a payment")
    W.Modal(payDlg, function() return frame end)
    payDlg.text = W.Text(payDlg, "GameFontHighlight")
    payDlg.text:SetPoint("TOPLEFT", 16, -40)
    payDlg.text:SetPoint("RIGHT", -16, 0)
    payDlg.money = W.MoneyInput(payDlg)
    payDlg.money:SetPoint("TOPLEFT", 12, -66)
    payDlg.full = W.Tab(payDlg, "All", 44, 20, function() payDlg.money:SetCopper(payDlg.max) end)
    payDlg.full:SetPoint("LEFT", payDlg.money, "RIGHT", 8, 0)
    payDlg.half = W.Tab(payDlg, "Half", 44, 20, function() payDlg.money:SetCopper(math.floor(payDlg.max / 2)) end)
    payDlg.half:SetPoint("LEFT", payDlg.full, "RIGHT", 4, 0)
    payDlg.ok = W.Button(payDlg, "Record", 110, 24, submitPayment)
    payDlg.ok:SetPoint("BOTTOMRIGHT", -16, 14)
    payDlg.money.onEnter = submitPayment
    payDlg.hint = W.Text(payDlg, "GameFontDisableSmall", "Trades and mail are counted automatically; use this for anything else.")
    payDlg.hint:SetPoint("BOTTOMLEFT", 16, 42)
    payDlg.hint:SetPoint("RIGHT", -16, 0)
  end
  local d = payDlg
  d.loan, d.mode = loan, mode or "pay"
  local lender, who = ns.IAmLender(loan), ns.Short(ns.Other(loan))
  if d.mode == "add" then
    d.title:SetText("Lend more")
    d.text:SetText(lender and ("Add to %s's loan (they owe %s):"):format(who, ns.Money(ns.Balance(loan)))
      or ("You borrowed more from %s:"):format(who))
    d.max = GetMoney()
    d.full:Hide(); d.half:Hide()
    d.ok:SetText("Add to loan")
  else
    d.title:SetText("Record a payment")
    d.text:SetText(lender and ("%s paid you (owes %s):"):format(who, ns.Money(ns.Balance(loan)))
      or ("You paid %s (you owe %s):"):format(who, ns.Money(ns.Balance(loan))))
    d.max = ns.Balance(loan)
    d.full:Show(); d.half:Show()
    d.ok:SetText("Record")
  end
  d.money:SetCopper(d.mode == "pay" and d.max or 0)
  d:Show()
  d.money:Focus()
end

---------------------------------------------------------------------------
-- New loan dialog
---------------------------------------------------------------------------
local nl
local COL = 96 -- x where every New loan control starts (labels sit at 16)

local function updateNewLoan()
  if not nl then return end
  local partner = nl.picker:GetPlayer()
  if partner then
    local rel, st = ns.ReliabilityText(partner)
    local bits = {}
    -- amber when the existing debt runs the same way as the new loan: worth a second look
    if st.owesMe > 0 then bits[#bits + 1] = (nl.lent and "|cffff9900already owes you " or "|cff40ff40owes you ") .. ns.Money(st.owesMe) .. "|r" end
    if st.iOwe > 0 then bits[#bits + 1] = (nl.lent and "|cffff6060you owe " or "|cffff9900you already owe ") .. ns.Money(st.iOwe) .. "|r" end
    if nl.lent then bits[#bits + 1] = rel end
    nl.info:SetText(table.concat(bits, "  ·  "))
  else
    nl.info:SetText("|cffaaaaaaType a name, click the arrow to pick, or shift-click a name in chat.|r")
  end
  local t = nl.terms:Get()
  local amount = nl.money:GetCopper()
  local due, late = ns.ProjectDue(amount, t.ratePct, t.period, t.dueDays, t.lateFeePct)
  local rate = t.ratePct > 0 and ("%s%% per %s, compounding"):format(t.ratePct, ns.PeriodText(t.period)) or nil
  local s = nl.summary
  if amount <= 0 then
    s.main:SetText("|cff888888Enter an amount to see what " .. (nl.lent and "they'll" or "you'll") .. " owe.|r")
    s.sub:SetText("")
  elseif due then
    s.main:SetText(("Repay |cffffd100%s|r by %s"):format(ns.Money(due), date("%b %d", ns.Now() + t.dueDays * ns.DAY)))
    local bits = {}
    if late and late ~= due then bits[#bits + 1] = "|cffff9900" .. ns.Money(late) .. " if late|r" end
    bits[#bits + 1] = rate or "no interest"
    s.sub:SetText(table.concat(bits, "  ·  "))
  else
    s.main:SetText(rate and "No due date" or "No interest, no due date")
    s.sub:SetText(rate and ("Interest keeps growing until repaid (" .. rate .. ")") or "")
  end
  -- What the main button does
  local via
  if nl.lent and partner then
    if ns.trade.partner and ns.Same(ns.trade.partner, partner) and TradeFrame and TradeFrame:IsShown() then via = "trade"
    elseif MailFrame and MailFrame:IsShown() then via = "mail" end
  end
  nl.via = via
  if via == "trade" then
    nl.ok:SetText("Put in trade")
    nl.record:Show()
  elseif via == "mail" then
    nl.ok:SetText("Put in mail")
    nl.record:Show()
  else
    nl.ok:SetText("Record loan")
    nl.record:Hide()
  end
end

local function setDirection(lent)
  nl.lent = lent
  nl.lendTab:SetActive(lent)
  nl.borrowTab:SetActive(not lent)
  nl.playerLabel:SetText(lent and "Borrower" or "Lender")
  updateNewLoan()
end

local function buildNewLoan()
  nl = W.Panel("LoanCraftNewLoan", 420, 360, "New loan")
  W.Modal(nl, function() return frame end)
  nl.lendTab = W.Tab(nl, "I'm lending", 120, 22, function() setDirection(true) end)
  nl.lendTab:SetPoint("TOPLEFT", 16, -38)
  nl.borrowTab = W.Tab(nl, "I'm borrowing", 120, 22, function() setDirection(false) end)
  nl.borrowTab:SetPoint("LEFT", nl.lendTab, "RIGHT", 6, 0)

  nl.playerLabel = W.Label(nl, "Borrower")
  nl.playerLabel:SetPoint("TOPLEFT", 16, -78)
  nl.picker = W.NamePicker(nl, 308, function(name)
    if name and nl.lent and not nl.termsTouched then nl.terms:Set(ns.TermsFor(name)) end
    updateNewLoan()
  end)
  nl.picker:SetPoint("TOPLEFT", COL, -73)
  nl.info = W.Text(nl, "GameFontHighlightSmall")
  nl.info:SetPoint("TOPLEFT", COL, -98)
  nl.info:SetPoint("RIGHT", -16, 0)

  W.Label(nl, "Amount"):SetPoint("TOPLEFT", 16, -124)
  nl.money = W.MoneyInput(nl, updateNewLoan)
  nl.money:SetPoint("TOPLEFT", COL, -119)
  nl.picker.onTab = function() nl.money:Focus() end

  nl.terms = W.Terms(nl, function() nl.termsTouched = true; updateNewLoan() end, COL - 16)
  nl.terms:SetPoint("TOPLEFT", 16, -150)

  -- The outcome of the form, so it gets its own box
  local s = CreateFrame("Frame", nil, nl, "BackdropTemplate")
  W.Backdrop(s, { 1, 0.82, 0, 0.06 }, { 1, 0.82, 0, 0.3 })
  s:SetPoint("TOPLEFT", 16, -232)
  s:SetPoint("RIGHT", -16, 0)
  s:SetHeight(44)
  s.main = W.Text(s, "GameFontHighlight")
  s.main:SetPoint("TOPLEFT", 10, -8)
  s.sub = W.Text(s, "GameFontHighlightSmall")
  s.sub:SetPoint("BOTTOMLEFT", 10, 8)
  nl.summary = s

  W.Label(nl, "Note"):SetPoint("TOPLEFT", 16, -294)
  nl.note = W.Input(nl, 302)
  nl.note:SetPoint("TOPLEFT", COL + 5, -289)
  nl.note:SetMaxLetters(60)

  nl.ok = W.Button(nl, "Record loan", 130, 24, function() UI.SubmitNewLoan(false) end)
  nl.ok:SetPoint("BOTTOMRIGHT", -16, 14)
  nl.record = W.Button(nl, "Just record it", 120, 24, function() UI.SubmitNewLoan(true) end)
  nl.record:SetPoint("RIGHT", nl.ok, "LEFT", -8, 0)
  nl.money.onEnter = function() UI.SubmitNewLoan(false) end
end

function UI.OpenNewLoan(pre)
  pre = pre or {}
  if not nl then buildNewLoan() end
  nl.termsTouched = false
  nl.picker:SetPlayer(pre.partner or ns.UnitFull("target"))
  nl.money:SetCopper(pre.amount or 0)
  nl.note:SetText("")
  local partner = nl.picker:GetPlayer()
  local t = (pre.lent ~= false) and ns.TermsFor(partner) or { ratePct = 0, period = 7, dueDays = ns.db.settings.defaultDue, lateFeePct = 0 }
  nl.terms:Set(t)
  nl.termsTouched = false
  setDirection(pre.lent ~= false)
  nl:Show()
  if partner then nl.money:Focus() else nl.picker.edit:SetFocus() end
end

function UI.SubmitNewLoan(recordOnly)
  local partner = nl.picker:GetPlayer()
  local amount = nl.money:GetCopper()
  if not partner or ns.Same(partner, ns.Me()) then ns.Print("Pick the other player first."); return end
  if amount <= 0 then ns.Print("Enter an amount."); return end
  local t = nl.terms:Get()
  if not recordOnly and nl.via then
    local ok = nl.via == "trade" and ns.LendByTrade(partner, amount, t) or ns.LendByMail(partner, amount, t)
    if ok then nl:Hide() end
    return
  end
  local me = ns.Me()
  local loan = ns.CreateLoan({
    lender = nl.lent and me or partner, borrower = nl.lent and partner or me, principal = amount,
    ratePct = t.ratePct, period = t.period, dueDays = t.dueDays, lateFeePct = t.lateFeePct,
    note = nl.note:GetText() ~= "" and nl.note:GetText() or nil, src = "manual",
  })
  ns.Print("Recorded: %s %s %s (%s).", nl.lent and "you lent" or "you borrowed", ns.Money(amount),
    (nl.lent and "to " or "from ") .. ns.Short(partner), ns.TermsText(loan))
  if nl.lent then ns.Sync.Hello(partner, true) end
  nl:Hide()
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
local exportDlg
function UI.Export()
  if not exportDlg then
    exportDlg = W.Panel("LoanCraftExport", 520, 360, "Export ledger (Ctrl+C to copy)")
    W.Modal(exportDlg, function() return frame end)
    local sf = CreateFrame("ScrollFrame", nil, exportDlg)
    sf:SetPoint("TOPLEFT", 14, -38)
    sf:SetPoint("BOTTOMRIGHT", -14, 14)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject("ChatFontNormal")
    eb:SetWidth(490)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() exportDlg:Hide() end)
    sf:SetScrollChild(eb)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d)
      local max = math.max(0, eb:GetHeight() - self:GetHeight())
      self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 40)))
    end)
    exportDlg.eb = eb
  end
  local lines = { "date,type,player,amount_gold,interest_gold,via" }
  for _, e in ipairs(ns.Ledger(state.person)) do
    lines[#lines + 1] = ("%s,%s,%s,%.4f,%.4f,%s"):format(date("%Y-%m-%d %H:%M", e.t), e.kind, ns.Short(e.partner),
      e.amount / 10000, (e.interest or 0) / 10000, e.src or "")
  end
  exportDlg.eb:SetText(table.concat(lines, "\n"))
  exportDlg:Show()
  exportDlg.eb:SetFocus()
  exportDlg.eb:HighlightText()
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
local loansList, peopleList, ledgerList, ledgerSummary

local function loanMenu(anchor, loan)
  local lender = ns.IAmLender(loan)
  local who = ns.Short(ns.Other(loan))
  local items = { { text = (lender and "Loan to " or "Loan from ") .. who, title = true } }
  if loan.status == "open" then
    if lender then
      items[#items + 1] = { text = "Record a payment...", func = function() UI.OpenPayment(loan, "pay") end }
      items[#items + 1] = { text = "Lend more...", func = function() UI.OpenPayment(loan, "add") end }
      items[#items + 1] = { text = "Send a reminder", func = function() ns.Remind(loan, true) end }
      items[#items + 1] = { text = "Extend due date by 7 days", func = function() ns.Extend(loan, 7) end }
      items[#items + 1] = { text = "Forgive the rest...", func = function()
        ns.Confirm(("Forgive the remaining %s %s owes you?"):format(ns.Money(ns.Balance(loan)), who), function() ns.Forgive(loan) end)
      end }
    elseif loan.confirmed then
      items[#items + 1] = { text = "Pay now (mail/trade)", func = function() ns.Pay(loan.lender) end }
      items[#items + 1] = { text = "Record a payment I made...", func = function() UI.OpenPayment(loan, "pay") end }
      if not ns.Sync.HasAddon(loan.lender) then
        items[#items + 1] = { text = "Borrowed more...", func = function() UI.OpenPayment(loan, "add") end }
      end
    else
      items[#items + 1] = { text = "Accept or dispute...", func = function() ns.AskAcceptLoan(loan) end }
    end
  end
  items[#items + 1] = { text = "Show " .. who .. "'s history", func = function() UI.ShowPerson(ns.Other(loan), "ledger") end }
  items[#items + 1] = { text = "|cffff6060Delete record...|r", func = function()
    ns.Confirm(("Delete this loan record (%s with %s)?%s"):format(ns.Money(loan.principal), who,
      (lender and loan.status == "open") and "\nIt will be cancelled for them too." or ""), function() ns.DeleteLoan(loan.id) end)
  end }
  W.Menu(anchor, items)
end

local function loanTooltip(row)
  local loan = row.item
  if not loan then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  local lender = ns.IAmLender(loan)
  GameTooltip:AddLine((lender and "Loan to " or "Loan from ") .. ns.Short(ns.Other(loan)), 1, 0.82, 0)
  GameTooltip:AddDoubleLine("Lent", ns.Money(ns.Lent(loan)), 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine("Repaid", ns.Money(ns.Paid(loan)), 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine("Still owed", ns.Money(ns.Balance(loan)), 1, 1, 1, 1, 1, 1)
  local _, i = ns.Walk(loan)
  if i >= 1 then GameTooltip:AddDoubleLine("of which interest", ns.Money(i), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7) end
  GameTooltip:AddLine(ns.TermsText(loan), 0.8, 0.8, 0.8, true)
  GameTooltip:AddLine(date("Started %b %d, %Y", loan.created), 0.8, 0.8, 0.8)
  if loan.note then GameTooltip:AddLine("Note: " .. loan.note, 0.9, 0.9, 0.6, true) end
  if #loan.events > 0 then
    GameTooltip:AddLine(" ")
    for k = math.max(1, #loan.events - 7), #loan.events do
      local e = loan.events[k]
      local label = e.kind == "pay" and "payment" or e.kind == "add" and "lent more" or e.kind
      GameTooltip:AddDoubleLine(date("%b %d %H:%M", e.t) .. "  " .. label .. " (" .. (e.src or "?") .. ")",
        ns.Money(e.amount), 0.8, 0.8, 0.8, 1, 1, 1)
    end
  end
  if lender and loan.status == "open" then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.ReliabilityText(loan.borrower), 1, 1, 1)
  end
  GameTooltip:Show()
end

local function createLoanRow(parent, i)
  local r = W.Row(parent, i)
  r.stripe = r:CreateTexture(nil, "ARTWORK")
  r.stripe:SetPoint("TOPLEFT"); r.stripe:SetPoint("BOTTOMLEFT"); r.stripe:SetWidth(3)
  r.name = W.Text(r, "GameFontNormal")
  r.name:SetPoint("TOPLEFT", 10, -6)
  r.name:SetWidth(210)
  r.sub = W.Text(r, "GameFontHighlightSmall")
  r.sub:SetPoint("BOTTOMLEFT", 10, 7)
  r.sub:SetWidth(260)
  r.amount = W.Text(r, "GameFontHighlight")
  r.amount:SetPoint("TOPRIGHT", -126, -7)
  r.amount:SetJustifyH("RIGHT")
  r.of = W.Text(r, "GameFontDisableSmall")
  r.of:SetPoint("BOTTOMRIGHT", -126, 7)
  r.of:SetJustifyH("RIGHT")
  r.barBg = r:CreateTexture(nil, "ARTWORK")
  r.barBg:SetColorTexture(1, 1, 1, 0.08)
  r.barBg:SetPoint("BOTTOMLEFT", 3, 0); r.barBg:SetPoint("BOTTOMRIGHT", 0, 0); r.barBg:SetHeight(2)
  r.bar = r:CreateTexture(nil, "OVERLAY")
  r.bar:SetPoint("BOTTOMLEFT", 3, 0); r.bar:SetHeight(2)
  r.primary = W.Button(r, "", 72, 22)
  r.primary:SetPoint("RIGHT", -34, 0)
  r.more = W.Button(r, "...", 28, 22)
  r.more:SetPoint("RIGHT", -4, 0)
  r.more:SetScript("OnClick", function(self) loanMenu(self, r.item) end)
  r:RegisterForClicks("AnyUp")
  r:SetScript("OnClick", function(self, button) if self.item then loanMenu(self.more, self.item) end end)
  r.OnHover = loanTooltip
  return r
end

local function updateLoanRow(r, loan)
  local lender = ns.IAmLender(loan)
  local other = ns.Short(ns.Other(loan))
  local owed = ns.Balance(loan)
  local active = loan.status == "open"
  local c = not active and { 0.4, 0.4, 0.4 } or lender and W.C.green or W.C.red
  r.stripe:SetColorTexture(c[1], c[2], c[3], 0.9)
  r.name:SetText(other)
  local pending = 0
  for _, cl in pairs(loan.claims or {}) do if not cl.rejected and cl.src ~= "mail" then pending = pending + 1 end end
  local sub
  if active and not loan.confirmed then
    sub = lender and ("|cffff9900waiting for " .. other .. " to accept|r · " .. ns.DueText(loan)) or "|cffff9900needs your OK|r"
  elseif active and pending > 0 and lender then
    sub = "|cffff9900" .. other .. " says they paid you|r"
  elseif active then
    sub = (lender and "owes you" or "you owe") .. " · " .. ns.DueText(loan)
    if (loan.ratePct or 0) > 0 then sub = sub .. " · " .. loan.ratePct .. "%/" .. ns.PeriodText(loan.period) end
  else
    sub = ns.DueText(loan) .. date(" · %b %d", loan.closedAt or loan.changed or loan.created)
  end
  r.sub:SetText(sub)
  r.amount:SetText(ns.Money(active and owed or ns.Lent(loan)))
  r.of:SetText(active and ("of " .. ns.Money(ns.Lent(loan)) .. " lent") or "")
  local paid = ns.Paid(loan)
  local frac = active and math.min(1, paid / math.max(1, paid + owed)) or 1
  local w = math.max(1, (r:GetWidth() - 3) * frac)
  r.bar:SetWidth(w)
  r.bar:SetColorTexture(c[1], c[2], c[3], 0.8)
  r.bar:SetShown(frac > 0)

  local label, fn
  if active then
    if lender then
      if pending > 0 then
        label, fn = "Review", function() for key, cl in pairs(loan.claims) do if not cl.rejected then ns.AskConfirmClaim(loan, key) end end end
      elseif loan.due and loan.due < ns.Now() then
        label, fn = "Remind", function() ns.Remind(loan, true) end
      else
        label, fn = "Paid...", function() UI.OpenPayment(loan, "pay") end
      end
    elseif not loan.confirmed then
      label, fn = "Review", function() ns.AskAcceptLoan(loan) end
    else
      label, fn = "Pay", function() ns.Pay(loan.lender) end
    end
  end
  if label then
    r.primary:SetText(label)
    r.primary:SetScript("OnClick", fn)
    r.primary:Show()
  else
    r.primary:Hide()
  end
end

local function createPersonRow(parent, i)
  local r = W.Row(parent, i)
  r.name = W.Text(r, "GameFontNormal")
  r.name:SetPoint("TOPLEFT", 10, -6)
  r.sub = W.Text(r, "GameFontHighlightSmall")
  r.sub:SetPoint("BOTTOMLEFT", 10, 7)
  r.sub:SetWidth(330)
  r.pos = W.Text(r, "GameFontHighlight")
  r.pos:SetPoint("TOPRIGHT", -126, -7)
  r.pos:SetJustifyH("RIGHT")
  r.last = W.Text(r, "GameFontDisableSmall")
  r.last:SetPoint("BOTTOMRIGHT", -126, 7)
  r.last:SetJustifyH("RIGHT")
  r.lend = W.Button(r, "Lend", 72, 22)
  r.lend:SetPoint("RIGHT", -34, 0)
  r.more = W.Button(r, "...", 28, 22)
  r.more:SetPoint("RIGHT", -4, 0)
  r.more:SetScript("OnClick", function(self)
    local p = r.item
    local auto = ns.db.autoRepay[p.name:lower()] and true or false
    W.Menu(self, {
      { text = ns.Short(p.name), title = true },
      { text = "Show loans", func = function() UI.ShowPerson(p.name, "loans") end },
      { text = "Show ledger", func = function() UI.ShowPerson(p.name, "ledger") end },
      { text = "Count their repayments automatically", checked = auto, func = function()
        ns.db.autoRepay[p.name:lower()] = (not auto) or nil
      end },
      { text = "Whisper", func = function()
        if ChatFrame_SendTell then ChatFrame_SendTell(ns.MailName(p.name)) end
      end },
      { text = "Sync now", func = function() ns.Sync.Hello(p.name, true) end },
    })
  end)
  r:SetScript("OnClick", function(self) if self.item then UI.ShowPerson(self.item.name, "loans") end end)
  return r
end

local function updatePersonRow(r, p)
  r.name:SetText(ns.Short(p.name))
  local rel, st = ns.ReliabilityText(p.name)
  local bits = {}
  if st.asBorrower > 0 then bits[#bits + 1] = rel end
  if st.borrowed > 0 then bits[#bits + 1] = "lent you " .. ns.Money(st.borrowed) end
  if ns.Sync.HasAddon(p.name) then bits[#bits + 1] = "|cff66aaffLoanCraft|r" end
  r.sub:SetText(table.concat(bits, " · "))
  if p.owesMe > 0 and p.iOwe == 0 then r.pos:SetText("|cff40ff40+|r" .. ns.Money(p.owesMe))
  elseif p.iOwe > 0 and p.owesMe == 0 then r.pos:SetText("|cffff6060-|r" .. ns.Money(p.iOwe))
  elseif p.iOwe > 0 then r.pos:SetText(("|cff40ff40+%s|r / |cffff6060-%s|r"):format(ns.Money(p.owesMe), ns.Money(p.iOwe)))
  else r.pos:SetText("|cffaaaaaasettled|r") end
  r.last:SetText(p.loans .. (p.loans == 1 and " loan" or " loans") .. " · " .. ns.Ago(p.last))
  r.lend:SetScript("OnClick", function() UI.OpenNewLoan({ partner = p.name, lent = true }) end)
end

local KIND = {
  lend = { "Lent to %s", W.C.red, "-" },
  borrow = { "Borrowed from %s", W.C.green, "+" },
  collect = { "%s repaid you", W.C.green, "+" },
  repay = { "You repaid %s", W.C.red, "-" },
  forgive = { "Forgave %s", { 0.6, 0.6, 0.6 }, "" },
  forgiven = { "%s forgave you", { 0.6, 0.6, 0.6 }, "" },
}

local function createLedgerRow(parent, i)
  local r = W.Row(parent, i)
  r.date = W.Text(r, "GameFontDisableSmall")
  r.date:SetPoint("LEFT", 8, 0)
  r.date:SetWidth(78)
  r.text = W.Text(r, "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", 90, 0)
  r.text:SetWidth(290)
  r.amount = W.Text(r, "GameFontHighlightSmall")
  r.amount:SetPoint("RIGHT", -8, 0)
  r.amount:SetJustifyH("RIGHT")
  r.OnHover = function(self)
    local e = self.item
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(KIND[e.kind][1]:format(ns.Short(e.partner)), 1, 0.82, 0)
    GameTooltip:AddLine(date("%A %b %d %Y, %H:%M", e.t), 0.8, 0.8, 0.8)
    GameTooltip:AddDoubleLine("Amount", ns.Money(e.amount), 1, 1, 1, 1, 1, 1)
    if e.interest and e.interest >= 1 then
      GameTooltip:AddDoubleLine("Interest part", ns.Money(e.interest), 1, 1, 1, 1, 1, 1)
      GameTooltip:AddDoubleLine("Principal part", ns.Money(e.principal), 1, 1, 1, 1, 1, 1)
    end
    if e.src then GameTooltip:AddDoubleLine("Via", e.src, 1, 1, 1, 1, 1, 1) end
    GameTooltip:Show()
  end
  return r
end

local function updateLedgerRow(r, e)
  local k = KIND[e.kind]
  r.date:SetText(date("%b %d %H:%M", e.t))
  local text = k[1]:format(ns.Short(e.partner))
  if e.extra then text = text .. " (more)" end
  if e.interest and e.interest >= 100 then text = text .. ("  |cffaaaaaaincl. %s interest|r"):format(ns.Money(e.interest)) end
  if e.src and e.src ~= "manual" and e.src ~= "sync" then text = text .. "  |cff777777" .. e.src .. "|r" end
  r.text:SetText(text)
  local c = k[2]
  r.amount:SetText(("|cff%02x%02x%02x%s%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, k[3], ns.Money(e.amount)))
end

local function stat(parent, label, x, y)
  local l = W.Text(parent, "GameFontDisableSmall", label)
  l:SetPoint("TOPLEFT", x, y)
  local v = W.Text(parent, "GameFontHighlightSmall")
  v:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + 230, y)
  v:SetJustifyH("RIGHT")
  return v
end

local function buildLedgerSummary(parent)
  local s = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  W.Backdrop(s, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 })
  s:SetHeight(112)
  local h1 = W.Text(s, "GameFontNormalSmall", "As lender")
  h1:SetPoint("TOPLEFT", 10, -8)
  local h2 = W.Text(s, "GameFontNormalSmall", "As borrower")
  h2:SetPoint("TOPLEFT", 280, -8)
  s.v = {
    lent = stat(s, "Lent out", 10, -24), collected = stat(s, "Collected", 10, -38),
    interestEarned = stat(s, "Interest earned", 10, -52), writtenOff = stat(s, "Written off", 10, -66),
    outstanding = stat(s, "Still owed to you", 10, -80),
    borrowed = stat(s, "Borrowed", 280, -24), repaid = stat(s, "Repaid", 280, -38),
    interestPaid = stat(s, "Interest paid", 280, -52), forgivenToMe = stat(s, "Forgiven to you", 280, -66),
    iOwe = stat(s, "You still owe", 280, -80),
  }
  s.net = W.Text(s, "GameFontNormal")
  s.net:SetPoint("BOTTOMLEFT", 10, 6)
  s.netHelp = W.Text(s, "GameFontDisableSmall", "interest earned - interest paid - written off + forgiven to you")
  s.netHelp:SetPoint("BOTTOMRIGHT", -10, 8)
  return s
end

local function updateLedgerSummary()
  local since = state.period > 0 and (ns.Now() - state.period * ns.DAY) or nil
  local s = ns.Summary(since, state.person)
  local v = ledgerSummary.v
  v.lent:SetText(ns.Money(s.lent)); v.collected:SetText(ns.Money(s.collected))
  v.interestEarned:SetText("|cff40ff40" .. ns.Money(s.interestEarned) .. "|r")
  v.writtenOff:SetText(s.writtenOff > 0 and ("|cffff6060" .. ns.Money(s.writtenOff) .. "|r") or ns.Money(0))
  v.outstanding:SetText(ns.Money(s.outstanding) .. (s.overdue > 0 and (" |cffff6060(" .. ns.Money(s.overdue) .. " late)|r") or ""))
  v.borrowed:SetText(ns.Money(s.borrowed)); v.repaid:SetText(ns.Money(s.repaid))
  v.interestPaid:SetText(s.interestPaid > 0 and ("|cffff6060" .. ns.Money(s.interestPaid) .. "|r") or ns.Money(0))
  v.forgivenToMe:SetText(ns.Money(s.forgivenToMe)); v.iOwe:SetText(ns.Money(s.iOwe))
  local color = s.net > 0 and "40ff40" or s.net < 0 and "ff6060" or "ffffff"
  ledgerSummary.net:SetText(("Net from loans: |cff%s%s%s|r"):format(color, s.net > 0 and "+" or s.net < 0 and "-" or "", ns.Money(math.abs(s.net))))
end

local function setTab(tab)
  state.tab = tab
  UI.Refresh()
end

function UI.ShowPerson(name, tab)
  UI.Build()
  state.person = name
  state.tab = tab or state.tab
  state.showClosed = true
  frame:Show()
  UI.Refresh()
end

function UI.Build()
  if frame then return end
  frame = W.Panel("LoanCraftFrame", 600, 500, "LoanCraft")

  -- Header stats
  local function bigStat(label, x)
    local l = W.Text(frame, "GameFontDisableSmall", label)
    l:SetPoint("TOPLEFT", x, -38)
    local v = W.Text(frame, "GameFontHighlightLarge")
    v:SetPoint("TOPLEFT", x, -52)
    return v
  end
  frame.owedToMe = bigStat("OWED TO YOU", 18)
  frame.iOwe = bigStat("YOU OWE", 210)
  frame.interest = bigStat("INTEREST EARNED", 400)

  frame.alert = CreateFrame("Button", nil, frame, "BackdropTemplate")
  frame.alert:SetPoint("TOPLEFT", 14, -80)
  frame.alert:SetPoint("TOPRIGHT", -14, -80)
  frame.alert:SetHeight(24)
  frame.alert.text = W.Text(frame.alert, "GameFontHighlightSmall")
  frame.alert.text:SetPoint("LEFT", 10, 0)
  frame.alert.text:SetPoint("RIGHT", -90, 0)
  frame.alert.btn = W.Button(frame.alert, "Review", 76, 18)
  frame.alert.btn:SetPoint("RIGHT", -4, 0)

  -- Everything under the alert; it moves up when there is no alert (see Refresh)
  local body = CreateFrame("Frame", nil, frame)
  body:SetPoint("BOTTOMRIGHT")
  frame.body = body

  -- Tabs
  frame.tabs = {}
  local tabs = { { "loans", "Loans" }, { "people", "People" }, { "ledger", "Ledger" } }
  for i, t in ipairs(tabs) do
    local b = W.Tab(body, t[2], 96, 24, function() setTab(t[1]) end)
    b:SetPoint("TOPLEFT", 14 + (i - 1) * 100, 0)
    frame.tabs[t[1]] = b
  end
  frame.personChip = W.Tab(body, "", 150, 20, function() state.person = nil; UI.Refresh() end)
  frame.personChip:SetPoint("TOPRIGHT", -14, -2)
  W.Tip(frame.personChip, "Click to show everyone")
  frame.showClosed = W.Check(body, "Show repaid", function(_, v) state.showClosed = v; UI.Refresh() end)
  frame.showClosed:SetPoint("TOPLEFT", 320, 0)

  -- Lists
  local area = CreateFrame("Frame", nil, body)
  area:SetPoint("TOPLEFT", 14, -30)
  area:SetPoint("BOTTOMRIGHT", -14, 48)
  frame.area = area

  loansList = W.List(area, 46, 7, createLoanRow, updateLoanRow)
  loansList:SetAllPoints()
  peopleList = W.List(area, 46, 7, createPersonRow, updatePersonRow)
  peopleList:SetAllPoints()

  ledgerSummary = buildLedgerSummary(area)
  ledgerSummary:SetPoint("TOPLEFT")
  ledgerSummary:SetPoint("TOPRIGHT", -10, 0)
  frame.periods = {}
  local periods = { { 0, "All time" }, { 30, "30 days" }, { 7, "7 days" } }
  for i, p in ipairs(periods) do
    local b = W.Tab(area, p[2], 70, 18, function() state.period = p[1]; UI.Refresh() end)
    b:SetPoint("TOPLEFT", (i - 1) * 74, -118)
    b.days = p[1]
    frame.periods[i] = b
  end
  frame.export = W.Tab(area, "Export CSV", 80, 18, function() UI.Export() end)
  frame.export:SetPoint("TOPRIGHT", -10, -118)
  ledgerList = W.List(area, 22, 9, createLedgerRow, updateLedgerRow)
  ledgerList:SetPoint("TOPLEFT", 0, -142)
  ledgerList:SetPoint("BOTTOMRIGHT")

  -- Footer
  W.Button(frame, "New loan", 110, 24, function() UI.OpenNewLoan() end):SetPoint("BOTTOMLEFT", 14, 14)
  W.Tab(frame, "Options", 80, 24, function() UI.ToggleOptions() end):SetPoint("BOTTOMRIGHT", -14, 14)
  frame.footer = W.Text(frame, "GameFontDisableSmall", "Trades and mail with your loan partners are detected automatically.", 0.62, 0.62, 0.62)
  frame.footer:SetPoint("BOTTOM", 0, 20)

  frame:SetScript("OnShow", function() UI.Refresh() end)
  frame:SetScript("OnUpdate", function(self, elapsed)
    self.acc = (self.acc or 0) + elapsed
    if self.acc > 30 then self.acc = 0; UI.Refresh() end
  end)
  ns.OnChange(UI.Refresh)
end

function UI.Refresh()
  if not frame or not frame:IsShown() then return end
  local owedToMe, iOwe = ns.Totals()
  frame.owedToMe:SetText(ns.Money(owedToMe))
  frame.iOwe:SetText(ns.Money(iOwe))
  frame.interest:SetText(ns.Money(ns.Summary().interestEarned))

  local alerts, top = ns.Alerts()
  if #alerts > 0 then
    local a = alerts[1]
    local color = top == 3 and { 0.9, 0.2, 0.2 } or top == 2 and { 1, 0.6, 0.1 } or { 0.3, 0.6, 1 }
    W.Backdrop(frame.alert, { color[1], color[2], color[3], 0.18 }, { color[1], color[2], color[3], 0.6 })
    frame.alert.text:SetText(a.text .. (#alerts > 1 and ("  |cffaaaaaa(+%d more)|r"):format(#alerts - 1) or ""))
    local pending = #ns.PendingTransfers()
    if pending > 0 then
      frame.alert.btn:SetText("Review")
      frame.alert.btn:SetScript("OnClick", function() ns.Prompt.ReviewPending() end)
      frame.alert.btn:Show()
    elseif a.loan then
      frame.alert.btn:SetText("Show")
      frame.alert.btn:SetScript("OnClick", function() UI.ShowPerson(ns.Other(a.loan), "loans") end)
      frame.alert.btn:Show()
    else
      frame.alert.btn:Hide()
    end
    frame.alert:Show()
  else
    frame.alert:Hide()
  end
  frame.body:SetPoint("TOPLEFT", 0, frame.alert:IsShown() and -112 or -82)

  for key, tab in pairs(frame.tabs) do tab:SetActive(key == state.tab) end
  if state.person then
    frame.personChip.text:SetText(ns.Short(state.person) .. "  |cffff6060x|r")
    frame.personChip:Show()
  else
    frame.personChip:Hide()
  end
  frame.showClosed:SetShown(state.tab == "loans")
  frame.showClosed:SetChecked(state.showClosed)

  loansList:SetShown(state.tab == "loans")
  peopleList:SetShown(state.tab == "people")
  local isLedger = state.tab == "ledger"
  ledgerSummary:SetShown(isLedger)
  ledgerList:SetShown(isLedger)
  frame.export:SetShown(isLedger)
  for _, b in ipairs(frame.periods) do b:SetShown(isLedger); b:SetActive(b.days == state.period) end

  if state.tab == "loans" then
    local list = {}
    for _, l in ipairs(ns.MyLoans()) do
      local active = l.status == "open" or l.status == "disputed"
      if (active or (state.showClosed and l.status == "closed")) and (not state.person or ns.Same(ns.Other(l), state.person)) then
        list[#list + 1] = l
      end
    end
    local now = ns.Now()
    local function rank(l)
      if l.status ~= "open" then return 9 end
      if not l.confirmed and not ns.IAmLender(l) then return 0 end
      if l.due and l.due < now then return 1 end
      return 2
    end
    table.sort(list, function(a, b)
      local ra, rb = rank(a), rank(b)
      if ra ~= rb then return ra < rb end
      local da, dbb = a.due or math.huge, b.due or math.huge
      if da ~= dbb then return da < dbb end
      return a.created > b.created
    end)
    loansList:SetData(list, state.person and "No loans with this player." or "No open loans.\nTrade or mail gold to someone, or click New loan.")
  elseif state.tab == "people" then
    local list = {}
    for _, p in ipairs(ns.People()) do
      if not state.person or ns.Same(p.name, state.person) then list[#list + 1] = p end
    end
    peopleList:SetData(list, "Nobody yet. People you lend to or borrow from show up here.")
  else
    updateLedgerSummary()
    local since = state.period > 0 and (ns.Now() - state.period * ns.DAY) or nil
    local list = {}
    for _, e in ipairs(ns.Ledger(state.person)) do
      if not since or e.t >= since then list[#list + 1] = e end
    end
    ledgerList:SetData(list, "No transactions in this period.")
  end
end

function UI.Toggle()
  UI.Build()
  if frame:IsShown() then frame:Hide() else frame:Show() end
end

function UI.Open(tab)
  UI.Build()
  if tab then state.tab = tab end
  frame:Show()
  UI.Refresh()
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local options
local TOGGLES = {
  { "autoTrade", "Watch trades for loans and repayments" },
  { "autoMail", "Watch mail for loans and repayments" },
  { "askNewLoans", "Offer to record gold I hand over as a loan" },
  { "autoSync", "Sync with the other player's LoanCraft" },
  { "payButtons", "LoanCraft panel on the trade window and mailbox" },
  { "unitTooltips", "Show debts on player tooltips" },
  { "loginReminders", "Summary and warnings when I log in" },
  { "peerReminders", "Let my LoanCraft nudge overdue borrowers' LoanCraft" },
  { "whisperReminders", "Whisper overdue borrowers without LoanCraft (once a day)" },
  { "sounds", "Sounds" },
}

local function buildOptions()
  options = W.Panel("LoanCraftOptions", 440, 560, "LoanCraft options")
  options:SetFrameStrata("FULLSCREEN")
  local h = W.Text(options, "GameFontNormal", "When someone repays you (or you repay them)")
  h:SetPoint("TOPLEFT", 16, -40)
  options.ask = W.Check(options, "Ask me each time", function() ns.db.settings.repayMode = "ask"; options.Sync() end)
  options.ask:SetPoint("TOPLEFT", 16, -58)
  options.auto = W.Check(options, "Count it automatically", function() ns.db.settings.repayMode = "auto"; options.Sync() end)
  options.auto:SetPoint("TOPLEFT", 220, -58)

  local y = -92
  options.checks = {}
  for _, t in ipairs(TOGGLES) do
    local cb = W.Check(options, t[2], function(_, v)
      ns.db.settings[t[1]] = v
      ns.Changed()
    end)
    cb:SetPoint("TOPLEFT", 16, y)
    options.checks[t[1]] = cb
    y = y - 24
  end
  local th = W.Text(options, "GameFontNormal", "Default terms for new loans")
  th:SetPoint("TOPLEFT", 16, y - 8)
  options.terms = W.Terms(options, function(t)
    if not options.syncing then
      local s = ns.db.settings
      s.defaultRate, s.defaultPeriod, s.defaultDue, s.defaultLateFee = t.ratePct, t.period, t.dueDays, t.lateFeePct
    end
  end)
  options.terms:SetPoint("TOPLEFT", 16, y - 30)
  local note = W.Text(options, "GameFontDisableSmall", "Players you've lent to before get the terms you used with them last time.")
  note:SetPoint("TOPLEFT", 16, y - 110)
  note:SetPoint("RIGHT", -16, 0)

  function options.Sync()
    local s = ns.db.settings
    options.syncing = true
    options.ask:SetChecked(s.repayMode ~= "auto")
    options.auto:SetChecked(s.repayMode == "auto")
    for k, cb in pairs(options.checks) do cb:SetChecked(s[k]) end
    options.terms:Set({ ratePct = s.defaultRate, period = s.defaultPeriod, dueDays = s.defaultDue, lateFeePct = s.defaultLateFee })
    options.syncing = false
  end
end

function UI.ToggleOptions()
  if not options then buildOptions() end
  if options:IsShown() then options:Hide(); return end
  options.Sync()
  options:Show()
end

-- Entry in the game's Options > AddOns list
ns.OnLogin(function()
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
  pcall(function()
    local p = CreateFrame("Frame")
    local t = W.Text(p, "GameFontNormalLarge", "LoanCraft")
    t:SetPoint("TOPLEFT", 16, -16)
    local d = W.Text(p, "GameFontHighlight", "Track gold loans between players.")
    d:SetPoint("TOPLEFT", 16, -42)
    W.Button(p, "Open LoanCraft", 140, 24, function() UI.Open() end):SetPoint("TOPLEFT", 16, -70)
    W.Button(p, "Options", 140, 24, function() UI.ToggleOptions() end):SetPoint("TOPLEFT", 164, -70)
    local cat = Settings.RegisterCanvasLayoutCategory(p, "LoanCraft")
    Settings.RegisterAddOnCategory(cat)
  end)
end)

---------------------------------------------------------------------------
-- Addon compartment (next to the minimap on clients that have it)
---------------------------------------------------------------------------
function LoanCraft_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then UI.OpenNewLoan() else UI.Toggle() end
end
