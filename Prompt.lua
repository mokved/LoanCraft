-- LoanCraft: "What was this gold for?" prompt, and the trade/mail side panels
local _, ns = ...
local W = ns.W

---------------------------------------------------------------------------
-- Transfer prompt (one at a time, queued)
---------------------------------------------------------------------------
local P = { queue = {} }
ns.Prompt = P
local f

local function loanLabel(l)
  return ("%s from %s · %s left"):format(ns.Money(ns.Lent(l)), date("%b %d", l.created), ns.Money(ns.Balance(l)))
end

local function build()
  f = W.Panel("LoanCraftPrompt", 410, 300, "LoanCraft")
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:ClearAllPoints()
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  f.close:SetScript("OnClick", function() P.Later() end)

  f.counter = W.Text(f, "GameFontDisableSmall")
  f.counter:SetPoint("TOPRIGHT", -32, -10)

  f.headline = W.Text(f, "GameFontHighlightLarge")
  f.headline:SetPoint("TOPLEFT", 16, -40)
  f.headline:SetPoint("RIGHT", -16, 0)
  f.context = W.Text(f, "GameFontHighlightSmall")
  f.context:SetPoint("TOPLEFT", f.headline, "BOTTOMLEFT", 0, -6)
  f.context:SetPoint("RIGHT", -16, 0)
  f.context:SetSpacing(2)

  f.options = {}
  for i = 1, 4 do
    local o = CreateFrame("Button", nil, f)
    o:SetHeight(32)
    o.check = CreateFrame("CheckButton", nil, o, "UICheckButtonTemplate")
    o.check:SetSize(24, 24)
    o.check:SetPoint("LEFT", 0, 0)
    o.check:SetScript("OnClick", function() P.Select(i) end)
    o.label = W.Text(o, "GameFontNormal")
    o.label:SetPoint("TOPLEFT", 28, -3)
    o.sub = W.Text(o, "GameFontDisableSmall")
    o.sub:SetPoint("TOPLEFT", o.label, "BOTTOMLEFT", 0, -2)
    o:SetScript("OnClick", function() P.Select(i) end)
    f.options[i] = o
  end

  f.detail = CreateFrame("Frame", nil, f)
  f.detail:SetSize(370, 120)
  f.amountLabel = W.Text(f.detail, "GameFontNormalSmall", "Amount")
  f.amountLabel:SetPoint("TOPLEFT", 0, -4)
  f.amount = W.MoneyInput(f.detail, function() P.UpdatePreview() end)
  f.amount:SetPoint("TOPLEFT", 60, 0)
  f.loanBtn = W.Tab(f.detail, "Soonest due first", 190, 20, function(self) P.PickLoan(self) end)
  f.loanBtn:SetPoint("LEFT", f.amount, "RIGHT", 8, 0)
  f.terms = W.Terms(f.detail, function() P.UpdatePreview() end)
  f.terms:SetPoint("TOPLEFT", 0, -28)
  f.preview = W.Text(f.detail, "GameFontHighlightSmall")
  f.preview:SetPoint("TOPLEFT", 0, -106)

  f.auto = W.Check(f, "")
  f.later = W.Button(f, "Decide later", 110, 24, function() P.Later() end)
  f.later:SetPoint("BOTTOMRIGHT", -16, 14)
  f.ok = W.Button(f, "Confirm", 120, 24, function() P.Confirm() end)
  f.ok:SetPoint("RIGHT", f.later, "LEFT", -8, 0)
end

function P.Current() return P.queue[1] end

function P.Queue(tr, quiet)
  for _, x in ipairs(P.queue) do if x.id == tr.id then return end end
  table.insert(P.queue, tr)
  if not (f and f:IsShown()) then P.Show() end
  if not quiet then ns.Sound() end
  ns.Changed()
end

function P.Remove(tr)
  for i, x in ipairs(P.queue) do
    if x.id == tr.id then
      table.remove(P.queue, i)
      if i == 1 and f and f:IsShown() then
        if P.queue[1] then P.Show() else f:Hide() end
      end
      break
    end
  end
  ns.Changed()
end

-- Settled elsewhere (the other player's LoanCraft)
function P.Resolved(tr, class)
  tr.class = class
  P.Remove(tr)
end

function P.Later()
  local tr = P.Current()
  if tr then table.remove(P.queue, 1) end
  if P.queue[1] then P.Show() elseif f then f:Hide() end
  ns.Changed()
end

function P.ReviewPending()
  for _, tr in ipairs(ns.PendingTransfers()) do P.Queue(tr, true) end
  if P.queue[1] then P.Show() end
end

function P.Show()
  local tr = P.Current()
  if not tr then if f then f:Hide() end return end
  if tr.class ~= nil then P.Remove(tr); return end
  if not f then build() end
  local who = ns.Short(tr.partner)
  f.title:SetText(tr.dir == "in" and "Gold received" or "Gold sent")
  f.counter:SetText(#P.queue > 1 and ("1 of " .. #P.queue) or "")
  f.headline:SetText(tr.dir == "in"
    and ("%s gave you %s"):format(who, ns.Money(tr.amount))
    or ("You gave %s %s"):format(who, ns.Money(tr.amount)))

  local ctx = { ("by %s, %s"):format(tr.src, ns.Ago(tr.t)) }
  local rel = ns.ReliabilityText(tr.partner)
  local st = ns.PersonStats(tr.partner)
  if st.asBorrower > 0 then ctx[#ctx + 1] = rel end
  if tr.items then ctx[#ctx + 1] = "|cffff9900The trade also included items. Check the amount below.|r" end
  if tr.partnerSays == "repay" then ctx[#ctx + 1] = "|cff40ff40" .. who .. "'s LoanCraft marked this as a repayment.|r" end
  f.context:SetText(table.concat(ctx, "\n"))

  tr.opts = ns.TransferOptions(tr)
  -- the only sensible answer left is "not a loan"? done
  if #tr.opts == 1 then tr.class = "none"; P.Remove(tr); return end
  local default = 1
  if tr.partnerSays == "repay" then
    for i, o in ipairs(tr.opts) do if o.id == "repay" then default = i end end
  end
  tr.loanId = nil
  P.Select(default, true)
  f:Show()
end

function P.Select(i, init)
  local tr = P.Current()
  if not tr or not tr.opts[i] then return end
  tr.choice = i
  local o = tr.opts[i]
  local y = -40 - f.headline:GetStringHeight() - 8 - f.context:GetStringHeight() - 12
  for k, row in ipairs(f.options) do
    local opt = tr.opts[k]
    if opt then
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 16, y)
      row:SetPoint("RIGHT", -16, 0)
      row.label:SetText(opt.label)
      row.sub:SetText(opt.sub or "")
      row:SetHeight(opt.sub and 32 or 22)
      row.check:SetChecked(k == i)
      row:Show()
      y = y - (opt.sub and 34 or 24)
    else
      row:Hide()
    end
  end

  local me = ns.Me()
  local lender = (o.id == "repay") == (tr.dir == "in") and me or tr.partner
  local borrower = ns.Same(lender, me) and tr.partner or me
  f.detail:ClearAllPoints()
  f.detail:SetPoint("TOPLEFT", 16, y - 6)
  local detailH = 0
  if o.id == "none" then
    f.detail:Hide()
  else
    f.detail:Show()
    local default = tr.amount
    if o.id == "repay" then default = math.min(tr.amount, ns.Owed(lender, borrower)) end
    f.amount.onChange = nil
    if init or not tr.amountTouched then f.amount:SetCopper(default) end
    f.amount.onChange = function() tr.amountTouched = true; P.UpdatePreview() end
    local loans = (o.id ~= "newloan") and ns.OpenLoans(lender, borrower) or {}
    f.loanBtn:SetShown(#loans > 1)
    f.loanBtn.loans = loans
    local chosen = tr.loanId and ns.db.loans[tr.loanId]
    f.loanBtn.text:SetText(chosen and loanLabel(chosen) or (o.id == "add" and "Newest loan" or "Soonest due first"))
    if o.id == "newloan" then
      f.terms:Show()
      f.terms:Set(ns.TermsFor(tr.partner))
      f.preview:Show()
      detailH = 124
    else
      f.terms:Hide()
      f.preview:Hide()
      detailH = 26
    end
    f.detail:SetHeight(detailH)
  end
  y = y - 6 - detailH - 4

  f.auto:ClearAllPoints()
  if o.id == "repay" then
    f.auto:SetPoint("TOPLEFT", 14, y)
    f.auto.label:SetText(("Count repayments with %s automatically from now on"):format(ns.Short(tr.partner)))
    f.auto:SetChecked(ns.db.autoRepay[tr.partner:lower()] and true or false)
    f.auto:Show()
    y = y - 28
  else
    f.auto:Hide()
  end
  f.ok:SetText(o.id == "none" and "Not a loan" or o.id == "repay" and "Count it" or "Record loan")
  f:SetHeight(-y + 50)
  P.UpdatePreview()
end

function P.PickLoan(btn)
  local tr = P.Current()
  if not tr then return end
  local items = { { text = "Which loan?", title = true },
    { text = "Soonest due first", checked = tr.loanId == nil, func = function() tr.loanId = nil; P.Select(tr.choice) end } }
  for _, l in ipairs(btn.loans or {}) do
    items[#items + 1] = { text = loanLabel(l), checked = tr.loanId == l.id, func = function() tr.loanId = l.id; P.Select(tr.choice) end }
  end
  W.Menu(btn, items)
end

function P.UpdatePreview()
  local tr = P.Current()
  if not f or not tr or not tr.opts or not tr.opts[tr.choice] then return end
  local o = tr.opts[tr.choice]
  if o.id ~= "newloan" then return end
  local t = f.terms:Get()
  local amount = f.amount:GetCopper()
  local due, late = ns.ProjectDue(amount, t.ratePct, t.period, t.dueDays, t.lateFeePct)
  if due then
    f.preview:SetText(("To repay by %s: |cffffffff%s|r%s"):format(date("%b %d", ns.Now() + t.dueDays * ns.DAY),
      ns.Money(due), (late and late ~= due) and ("  ·  " .. ns.Money(late) .. " if late") or ""))
  else
    f.preview:SetText(t.ratePct > 0 and "No due date: interest keeps growing until it's repaid." or "No interest, no due date.")
  end
end

function P.Confirm()
  local tr = P.Current()
  if not tr then return end
  local o = tr.opts[tr.choice]
  local opts = {}
  if o.id ~= "none" then
    opts.amount = f.amount:GetCopper()
    if opts.amount <= 0 then ns.Print("Enter an amount."); return end
    if opts.amount > tr.amount then
      ns.Print("That's more than the %s that changed hands.", ns.Money(tr.amount)); return
    end
    opts.loanId = tr.loanId
  end
  if o.id == "newloan" then
    opts.terms = f.terms:Get()
  end
  if o.id == "repay" then opts.autoPerson = f.auto:GetChecked() and true or false end
  ns.ResolveTransfer(tr, o.id, opts)
end

---------------------------------------------------------------------------
-- Side panels on the trade window and mailbox
---------------------------------------------------------------------------
local Panels = {}
ns.Panels = Panels

local function panelFrame(parent, name)
  local p = CreateFrame("Frame", name, parent, "BackdropTemplate")
  p:SetWidth(230)
  W.Backdrop(p)
  p:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, -30)
  p.title = W.Text(p, "GameFontNormal", "LoanCraft")
  p.title:SetPoint("TOPLEFT", 10, -8)
  p.lines, p.buttons = {}, {}
  p:Hide()
  return p
end

local function reset(p)
  p.y = -30
  p.nl, p.nb = 0, 0
  for _, l in ipairs(p.lines) do l:Hide() end
  for _, b in ipairs(p.buttons) do b:Hide() end
end

local function line(p, text, font)
  p.nl = p.nl + 1
  local l = p.lines[p.nl]
  if not l then
    l = W.Text(p, "GameFontHighlightSmall")
    l:SetWidth(210)
    p.lines[p.nl] = l
  end
  l:SetFontObject(font or "GameFontHighlightSmall")
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", 10, p.y)
  l:SetText(text)
  l:Show()
  p.y = p.y - math.max(12, l:GetStringHeight()) - 4
  return l
end

local function button(p, text, onClick, x, w, sameRow)
  p.nb = p.nb + 1
  local b = p.buttons[p.nb]
  if not b then
    b = W.Button(p, "", 100, 20)
    p.buttons[p.nb] = b
  end
  b:SetText(text)
  b:SetWidth(w or 210)
  b:SetScript("OnClick", onClick)
  b:ClearAllPoints()
  if sameRow then
    b:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, p.y + 18)
  else
    b:SetPoint("TOPLEFT", x or 10, p.y)
    p.y = p.y - 24
  end
  b:Show()
  return b
end

local function finish(p)
  p:SetHeight(-p.y + 8)
  p:Show()
end

local tradePanel, mailPanel

function Panels.UpdateTrade()
  if not (TradeFrame and ns.db.settings.payButtons) then return end
  local partner = ns.trade.partner
  if not partner or ns.IsMyChar(partner) then return Panels.HideTrade() end
  tradePanel = tradePanel or panelFrame(TradeFrame, "LoanCraftTradePanel")
  local p = tradePanel
  reset(p)
  local me = ns.Me()
  local owesMe, iOwe = ns.Owed(me, partner), ns.Owed(partner, me)
  line(p, ns.Short(partner), "GameFontHighlight")
  if owesMe > 0 then
    local soon = ns.OpenLoans(me, partner)[1]
    line(p, ("|cff40ff40Owes you %s|r · %s"):format(ns.Money(owesMe), soon and ns.DueText(soon) or ""))
  end
  if iOwe > 0 then
    local soon = ns.OpenLoans(partner, me)[1]
    line(p, ("|cffff6060You owe them %s|r · %s"):format(ns.Money(iOwe), soon and ns.DueText(soon) or ""))
  end
  local rel, st = ns.ReliabilityText(partner)
  if st.asBorrower > 0 then line(p, rel) end
  if owesMe == 0 and iOwe == 0 and st.loans == 0 then line(p, "|cffaaaaaaNo loans with this player.|r") end
  p.y = p.y - 2
  if iOwe > 0 then
    button(p, "Pay my debt: " .. ns.Money(math.min(iOwe, GetMoney())), function() ns.PayByTrade(partner) end)
  end
  if owesMe > 0 then
    line(p, "|cffaaaaaaGold they put in the trade can count as repayment.|r")
  end
  button(p, "Lend gold...", function() ns.UI.OpenNewLoan({ partner = partner, lent = true, via = "trade" }) end)
  finish(p)
end

function Panels.HideTrade() if tradePanel then tradePanel:Hide() end end

function Panels.UpdateMail()
  if not (MailFrame and MailFrame:IsShown() and ns.db.settings.payButtons) then return end
  mailPanel = mailPanel or panelFrame(MailFrame, "LoanCraftMailPanel")
  local p = mailPanel
  reset(p)
  local me = ns.Me()
  local debts, owed = {}, {}
  for _, person in ipairs(ns.People()) do
    if person.iOwe > 0 then debts[#debts + 1] = person end
    if person.owesMe > 0 then owed[#owed + 1] = person end
  end
  if #debts > 0 then
    line(p, "Your debts", "GameFontNormalSmall")
    for i = 1, math.min(5, #debts) do
      local d = debts[i]
      local soon = ns.OpenLoans(d.name, me)[1]
      line(p, ("%s  |cffff6060%s|r\n|cffaaaaaa%s|r"):format(ns.Short(d.name), ns.Money(d.iOwe), soon and ns.Plain(ns.DueText(soon)) or ""))
      button(p, "Pay", function() ns.FillMail(d.name) end, nil, 50, true)
    end
    p.y = p.y - 4
  end
  if #owed > 0 then
    line(p, "Owed to you", "GameFontNormalSmall")
    for i = 1, math.min(5, #owed) do
      local d = owed[i]
      local soon = ns.OpenLoans(me, d.name)[1]
      line(p, ("%s  |cff40ff40%s|r\n|cffaaaaaa%s|r"):format(ns.Short(d.name), ns.Money(d.owesMe), soon and ns.Plain(ns.DueText(soon)) or ""))
      if soon then button(p, "Remind", function() ns.Remind(soon, true) end, nil, 64, true) end
    end
    p.y = p.y - 4
  end
  if #debts == 0 and #owed == 0 then line(p, "|cffaaaaaaNo open loans.|r") end
  button(p, "Lend by mail...", function()
    local to = SendMailNameEditBox and ns.FullName(SendMailNameEditBox:GetText())
    ns.UI.OpenNewLoan({ partner = to, lent = true, via = "mail" })
  end)
  finish(p)
end

function Panels.HideMail() if mailPanel then mailPanel:Hide() end end

ns.OnChange(function()
  if tradePanel and tradePanel:IsShown() then Panels.UpdateTrade() end
  if mailPanel and mailPanel:IsShown() then Panels.UpdateMail() end
end)
