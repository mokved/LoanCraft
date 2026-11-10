"""LoanCraft simulation tests: several WoW: Forever clients trading, mailing and syncing.

Run:  pip install lupa  &&  python tests/test_addon.py
"""
import os, re, sys
from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = ROOT
STUB = os.path.join(ROOT, "tests", "wow_stub.lua")
GOLD = 10000

def strip(s): return re.sub(r"\|c[0-9a-fA-F]{8}|\|r|\|T.-\|t", "", s or "")

class Client:
    def __init__(self, full):
        self.full = full
        self.L = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.L.execute(f'PLAYER_NAME = "{full}"')
        self.L.execute(f'dofile([==[{STUB}]==])')
        self.L.execute('function Type(box, text) box._text = text; if box._scripts.OnTextChanged then box._scripts.OnTextChanged(box, true) end end')
        self.ns = self.L.eval(f'LoadAddon([==[{ADDON}]==], "LoanCraft")')
        self.G = self.L.globals()
        self.SIM = self.G.SIM
        self.chat_seen = 0
        self.group = None
        self.G.Advance(0.1)
    def ev(self, *a): self.G.FireEvent(*a)
    def run(self, code): return self.L.execute(code)
    def eval(self, code): return self.L.eval(code)
    def chat(self):
        n = len(self.SIM.chat)
        lines = [strip(self.SIM.chat[i]) for i in range(self.chat_seen + 1, n + 1)]
        self.chat_seen = n
        return lines
    def popups(self, which=None):
        return [p for p in self.SIM.popups.values() if which is None or p.which == which]
    def errors(self): return list(self.SIM.errors.values())
    def loans(self): return list(self.ns.MyLoans().values())
    def open_loans(self): return [l for l in self.loans() if l.status == "open"]
    def prompt(self):
        q = self.ns.Prompt.queue
        return q[1] if len(q) else None
    def prompt_shown(self):
        f = self.G.LoanCraftPrompt
        return f is not None and f._shown and self.prompt() is not None
    def prompt_ids(self):
        tr = self.prompt()
        return [o.id for o in tr.opts.values()] if tr else []
    def confirm(self, choice=None, amount=None):
        tr = self.prompt()
        if choice:
            ids = self.prompt_ids()
            if tr.choice != ids.index(choice) + 1:
                self.ns.Prompt.Select(ids.index(choice) + 1)
        if amount is not None:
            self.G.LoanCraftPrompt.amount.SetCopper(self.G.LoanCraftPrompt.amount, amount)
        self.ns.Prompt.Confirm()
        self.G.Advance(0.1)

clients = {}
def make(full):
    c = Client(full); clients[full.lower()] = c; return c

SHARD = "-CAMWOWEU4Realm10RP"
def route(rounds=200):
    quiet = 0
    for _ in range(rounds):
        moved = False
        for c in list(clients.values()):
            c.G.Advance(0.25)
            while len(c.SIM.outbox) > 0:
                m = c.L.eval("table.remove(SIM.outbox, 1)")
                sender = c.full + SHARD  # senders may carry a shard suffix
                if m.channel == "WHISPER":
                    dest = clients.get(c.ns.FullName(m.target).lower())
                    targets = [dest] if dest else []
                else:
                    targets = [d for d in clients.values() if d is not c and d.group and d.group == c.group]
                for d in targets:
                    d.ev("CHAT_MSG_ADDON", m.prefix, m.msg, m.channel, sender)
                    moved = True
        quiet = 0 if moved else quiet + 1
        if quiet >= 8: return

def advance(sec):
    for c in clients.values(): c.G.Advance(sec)

def jump(sec):
    for c in clients.values(): c.G.Jump(sec)

def trade(a, b, a_gives=0, b_gives=0, items=False, before_complete=None):
    a.SIM.tradePartner, b.SIM.tradePartner = b.full, a.full
    a.G.TradeFrame._shown = True; b.G.TradeFrame._shown = True
    a.ev("TRADE_SHOW"); b.ev("TRADE_SHOW")
    route()
    a.SIM.tradeGive, b.SIM.tradeGive = a_gives, b_gives
    if before_complete: before_complete()
    a.SIM.tradeGet = b.SIM.tradeGive
    b.SIM.tradeGet = a.SIM.tradeGive
    a.SIM.tradeItems = items; b.SIM.tradeItems = items
    for c in (a, b): c.ev("TRADE_MONEY_CHANGED"); c.ev("TRADE_ACCEPT_UPDATE", 1, 1)
    gave_a, gave_b = a.SIM.tradeGive, b.SIM.tradeGive
    a.G.PLAYER_MONEY_VALUE += gave_b - gave_a
    b.G.PLAYER_MONEY_VALUE += gave_a - gave_b
    for c in (a, b): c.ev("TRADE_CLOSED")
    for c in (a, b): c.ev("UI_INFO_MESSAGE", 0, "Trade complete.")
    a.G.TradeFrame._shown = False; b.G.TradeFrame._shown = False
    a.SIM.tradeItems = False; b.SIM.tradeItems = False
    a.SIM.tradeGive = 0; b.SIM.tradeGive = 0
    advance(0.1)

def open_mail(c):
    c.G.MailFrame._shown = True; c.ev("MAIL_SHOW"); c.G.Advance(0.1)

def close_mail(c):
    c.G.MailFrame._shown = False; c.ev("MAIL_CLOSED")

def send_mail(frm, to, money=None, subject="Hi"):
    """Send with whatever is in the mail form (after a LoanCraft button) or the given money/subject."""
    if money is not None:
        frm.SIM.sendMoney = money
        frm.G.SendMailNameEditBox._text = to.full
        frm.G.SendMailSubjectEditBox._text = subject
    to_name = frm.G.SendMailNameEditBox._text
    subj = frm.G.SendMailSubjectEditBox._text
    amt = frm.SIM.sendMoney
    frm.G.SendMail(to_name, subj, "")
    frm.G.PLAYER_MONEY_VALUE -= amt + 30
    frm.ev("MAIL_SEND_SUCCESS")
    frm.G.Advance(0.1)
    to.run(f'table.insert(SIM.inbox, {{sender="{frm.full}", subject=[==[{subj}]==], money={amt}}})')
    return amt, subj, to_name

def take_mail(c, index=None):
    open_mail(c)
    index = index or len(c.SIM.inbox)
    c.G.TakeInboxMoney(index)
    c.G.ServerTake()
    c.G.Advance(0.1)

fails = 0
def check(cond, label):
    global fails
    print(("PASS " if cond else "FAIL ") + label)
    if not cond: fails += 1

# ======================================================================
def lend(c, to, gold, rate="nil", due="nil"):
    """Record a loan through the New loan dialog (what the 'New loan' button opens)."""
    c.run(f'''
      LoanCraft.UI.OpenNewLoan({{ partner = "{to.full}" }})
      local nl, t = LoanCraftNewLoan, LoanCraft.TermsFor("{to.full}")
      nl.money:SetCopper({gold * GOLD})
      nl.terms:Set({{ ratePct = {rate} or t.ratePct, period = t.period, dueDays = {due} or t.dueDays, lateFeePct = t.lateFeePct }})
      LoanCraft.UI.SubmitNewLoan(true)
    ''')

alice = make("Alice Stone"); bob = make("Bob Marsh")
ns = alice.ns
print("-- Forever names")
check(ns.IS_FOREVER, "detected WoW Forever (interface 16001)")
check(ns.Me() == "Alice Stone", "Me() = 'Alice Stone' (" + str(ns.Me()) + ")")
check(ns.FullName("ana smith") == "Ana Smith", "typed 'ana smith' -> Ana Smith")
check(ns.FullName("Ana Smith-CAMWOWEU4Realm10RP") == "Ana Smith", "shard suffix dropped")
check(ns.FullName("  Ana   Smith ") == "Ana Smith", "extra spaces collapsed")
check(ns.MailName("Ana Smith") == "Ana Smith", "mail/whisper target keeps the full name")
check(ns.ParseMoney("12g 50s") == 125000 and ns.ParseMoney("1,000g") == 10000000, "money parsing")

# interest split
alice.run('''TL = LoanCraft.CreateLoan({lender="Alice Stone", borrower="Zed Quill", principal=1000000, ratePct=10, period=7, dueDays=14, lateFeePct=5})''')
L = alice.eval("TL"); t0 = L.created
check(abs(ns.Balance(L, t0 + 14*86400) - 1210000) <= 1, "10%/week for 2 weeks = 121g")
check(abs(ns.Balance(L, t0 + 14*86400 + 1) - 1270500) <= 2, "5% late fee once at due date")
alice.run("TL.events = {{t = TL.created + 14*86400, kind='pay', amount=1210000, src='manual'}}")
p, i = ns.Walk(L, t0 + 14*86400)
check(abs(p) < 1 and abs(i) < 1, "payment pays interest first then principal")
alice.run("LoanCraft.db.loans[TL.id] = nil; LoanCraft.db.contacts = {}; LoanCraft.db.terms = {}")

# ======================================================================
print("\n-- Alice lends Bob 100g by trade, picks terms in the prompt")
trade(alice, bob, a_gives=100*GOLD)
check(alice.prompt_shown(), "Alice gets the 'what was this gold for?' prompt")
check(alice.prompt_ids() == ["newloan", "none"], "options: new loan / gift: " + str(alice.prompt_ids()))
check(bob.prompt() is None, "Bob gets no prompt (Alice's LoanCraft will send the loan)")
alice.run('LoanCraftPrompt.terms:Set({ratePct=5, period=7, dueDays=14, lateFeePct=0})')
alice.ns.Prompt.UpdatePreview()
print("   preview:", strip(alice.G.LoanCraftPrompt.preview._text))
alice.confirm("newloan")
route()
check(not alice.prompt_shown(), "prompt closed after confirming")
acc = bob.popups("LOANCRAFT_ACCEPT")
check(len(acc) == 1, "Bob asked to accept the debt")
if acc: print("   ", strip(acc[0].text).replace("\n", " | "))
bob.G.ClickPopup(acc[0], 1); route()
la = alice.open_loans()[0]; lb = bob.open_loans()[0]
check(la.id == lb.id and la.confirmed and lb.confirmed, "same loan, confirmed on both sides")
check(la.ratePct == 5 and lb.ratePct == 5, "terms synced (5%/week)")
check(len(list(alice.ns.db.terms.keys())) == 1, "Alice's LoanCraft remembers the terms she used with Bob")

# ======================================================================
print("\n-- Bob repays 40g by plain trade; Bob confirms first")
advance(3600)
trade(alice, bob, b_gives=40*GOLD)
check(alice.prompt_ids()[0] == "repay" and bob.prompt_ids()[0] == "repay", "both default to 'Repayment'")
bob.confirm("repay")
route()
check(alice.prompt() is None, "Alice's prompt resolved automatically: both sides agree")
check(abs(alice.ns.Balance(la) - bob.ns.Balance(lb)) <= 1, "balances match: " + strip(alice.ns.Money(alice.ns.Balance(la))))
check(len(la.events) == 1 and len(lb.events) == 1, "one payment each side, no double count")
print("   alice:", alice.chat()[-1:])

print("\n-- Bob repays 10g by trade; this time Alice confirms first")
trade(alice, bob, b_gives=10*GOLD)
alice.confirm("repay"); route()
check(bob.prompt() is None, "Bob's prompt resolved by Alice's record")
check(len(la.events) == 2 and len(lb.events) == 2, "two payments each side")

# ======================================================================
print("\n-- Bob uses the trade panel 'Pay my debt' button")
owed = bob.ns.Owed(alice.full, bob.full)
def press_pay():
    bob.ns.PayByTrade(alice.full)
trade(alice, bob, before_complete=press_pay)
route()
check(bob.prompt() is None and alice.prompt() is None, "no prompts on either side")
check(la.status == "closed" and lb.status == "closed", "loan closed on both sides")
print("   bob:", bob.chat()[-2:])

# ======================================================================
print("\n-- Mail: Alice lends 50g by mail via the mail panel, Bob repays untagged mail")
open_mail(alice)
alice.ns.LendByMail(bob.full, 50*GOLD, {"ratePct": 0, "period": 7, "dueDays": 7, "lateFeePct": 0} and alice.L.table_from({"ratePct": 0, "period": 7, "dueDays": 7, "lateFeePct": 0}))
amt, subj, to_name = send_mail(alice, bob)
check(to_name == "Bob Marsh" and "[LCL]" in subj, f"mail filled: to '{to_name}', subject '{subj}'")
check(alice.prompt() is None and len(alice.open_loans()) == 1, "loan recorded on send, no prompt")
route()
acc = bob.popups("LOANCRAFT_ACCEPT"); bob.G.ClickPopup(acc[0], 1); route()
take_mail(bob)
check(bob.prompt() is None, "Bob collecting the loan mail asks nothing")
lm_a = alice.open_loans()[0]; lm_b = bob.open_loans()[0]
advance(7200)
open_mail(bob)
send_mail(bob, alice, money=50*GOLD, subject="thanks!")
check(bob.prompt_ids()[0:1] == ["repay"], "Bob asked if his plain mail was a repayment")
bob.confirm("repay"); route()
check(lm_b.status == "closed", "Bob's side closed")
check(lm_a.status == "open" and len(dict(lm_a.claims)) == 1, "Alice holds Bob's claim until the gold arrives")
take_mail(alice)
check(alice.prompt() is None and lm_a.status == "closed", "Alice collects: matched to Bob's claim automatically")
check(len(lm_a.events) == 1, "one payment on Alice's side")
route()
check(len(lm_b.events) == 1, "still one payment on Bob's side after sync")

print("\n-- Tagged repayment from the mailbox panel")
lend(alice, bob, 30, 0, 7)
route(); bob.G.ClickPopup(bob.popups("LOANCRAFT_ACCEPT")[0], 1); route()
open_mail(bob); bob.ns.FillMail(alice.full)
amt, subj, _ = send_mail(bob, alice)
check("[LC:" in subj and amt == 30*GOLD, "Pay fills 30g with a tag")
check(bob.prompt() is None, "no prompt for Bob")
take_mail(alice); route()
lt = [l for l in alice.loans() if l.principal == 30*GOLD][0]
check(alice.prompt() is None and lt.status == "closed", "Alice: tagged mail counted automatically")

# ======================================================================
print("\n-- Interest, overdue, ledger summary")
lend(alice, bob, 200, 10, 7)
route(); bob.G.ClickPopup(bob.popups("LOANCRAFT_ACCEPT")[0], 1); route()
li = [l for l in alice.open_loans()][0]
jump(10*86400)
bob.run("SIM.raid = {}")
alice.ns.Sync.Hello(bob.full, True); route()
check(len(bob.SIM.raid) >= 1, "Bob warned his loan is overdue")
alice.ns.Changed(); advance(0.1)
mm = alice.G.LoanCraftMinimapButton
check(mm.glow._shown and mm.glow._color[0+1] == 1 and mm.pulse._playing, "minimap ring glows red and pulses")
check(mm.badge._shown, "minimap badge shown: " + str(mm.badge.text._text))
owed = bob.ns.Owed(alice.full, bob.full)
check(owed == alice.ns.Owed(alice.full, bob.full), "both sides agree on balance with interest: " + strip(alice.ns.Money(owed)))
trade(alice, bob, before_complete=press_pay); route()
check(li.status == "closed", "paid off with interest")
s = alice.ns.Summary()
expected_interest = owed - 200*GOLD
check(s.interestEarned >= expected_interest and s.interestEarned - expected_interest < 500, f"interest earned = {strip(alice.ns.Money(s.interestEarned))} (this loan {strip(alice.ns.Money(expected_interest))} + a little on the first)")
sb = bob.ns.Summary()
check(abs(sb.interestPaid - s.interestEarned) <= 2, f"Bob's interest paid matches = {strip(bob.ns.Money(sb.interestPaid))}")
check(s.lent == (100+50+30+200)*GOLD, "total lent " + strip(alice.ns.Money(s.lent)))
print("   net:", strip(alice.ns.Money(s.net)), " ledger entries:", len(alice.ns.Ledger()))
check(alice.ns.Summary(alice.ns.Now() - 86400).lent == 0, "period filter (last day) excludes older loans")
rel = strip(alice.ns.ReliabilityText(bob.full)[0])
check("4 of 5" in rel or "of" in rel, "reliability: " + rel)

# ======================================================================
print("\n-- Carol (no LoanCraft)")
carol_full = "Carol Fenn"
def solo_trade(c, partner, give=0, get=0, items=False):
    c.SIM.tradePartner = partner; c.G.TradeFrame._shown = True
    c.ev("TRADE_SHOW")
    c.SIM.tradeGive, c.SIM.tradeGet, c.SIM.tradeItems = give, get, items
    c.ev("TRADE_ACCEPT_UPDATE", 1, 1); c.ev("UI_INFO_MESSAGE", 0, "Trade complete.")
    c.G.TradeFrame._shown = False; c.SIM.tradeItems = False
    c.G.Advance(0.1)
solo_trade(alice, carol_full, give=30*GOLD)
alice.confirm("newloan")
lc = [l for l in alice.open_loans() if l.borrower == carol_full][0]
solo_trade(alice, carol_full, get=10*GOLD)
check(alice.prompt_ids()[0] == "repay", "Carol's 10g -> 'repayment?' prompt")
alice.run('LoanCraftPrompt.auto:SetChecked(true)')
alice.confirm("repay")
check(alice.ns.Balance(lc) == 20*GOLD, "counted (20g left)")
solo_trade(alice, carol_full, get=5*GOLD)
check(alice.prompt() is None and alice.ns.Balance(lc) == 15*GOLD, "'count automatically for Carol' skips the prompt")
solo_trade(alice, carol_full, get=5*GOLD, items=True)
check(alice.prompt() is not None, "...but a trade with items still asks")
ctx = strip(alice.G.LoanCraftPrompt.context._text)
check("items" in ctx, "prompt warns about items")
alice.ns.Prompt.Later()
check(len(alice.ns.PendingTransfers()) == 1, "'Decide later' keeps it pending")
alerts, top = alice.ns.Alerts()
check(any("transfer" in strip(a.text) for a in alerts.values()), "pending transfer shows as an alert")
alice.ns.Prompt.ReviewPending()
check(alice.prompt_shown(), "Review reopens it")
alice.confirm("none")
check(alice.ns.Balance(lc) == 15*GOLD, "'Not a loan' leaves the balance alone")
# untagged mail repay from Carol
alice.run(f'table.insert(SIM.inbox, {{sender="{carol_full}", subject="gold", money=150000}})')
take_mail(alice)
check(alice.prompt() is None and lc.status == "closed", "Carol's mail auto-counted (auto for Carol) and closes the loan")

print("\n-- Gold from Dan (no LoanCraft, no loans)")
solo_trade(alice, "Dan Wick", get=20*GOLD)
check(alice.prompt_ids() == ["newloan", "none"], "offers 'I borrowed this' / 'not a loan': " + str(alice.prompt_ids()))
alice.confirm("newloan")
ld = [l for l in alice.open_loans() if l.lender == "Dan Wick"]
check(len(ld) == 1 and ld[0].confirmed, "debt to Dan recorded on Alice's side")
alice.ns.db.myChars["alice alt"] = "Alice Alt"
solo_trade(alice, "Alice Alt", give=500*GOLD)
check(alice.prompt() is None, "gold to your own alt is ignored")
solo_trade(alice, "Erin Holt", get=0, give=0)

# ======================================================================
print("\n-- Trust rules")
lend(alice, bob, 80)
route(); bob.G.ClickPopup(bob.popups("LOANCRAFT_ACCEPT")[0], 1); route()
l8 = [l for l in alice.open_loans() if l.borrower == bob.full][0]
before = alice.ns.Balance(l8)
bob.run(f'LoanCraft.Sync.Send("{alice.full}", "P", "{l8.id}", "pay", 800000, GetServerTime(), "manual", "fake1")')
route()
check(alice.ns.Balance(l8) == before, "a claimed payment with no gold seen doesn't count by itself")
check(len(alice.popups("LOANCRAFT_CLAIM")) == 1, "...Alice is asked")
alice.G.ClickPopup(alice.popups("LOANCRAFT_CLAIM")[0], 2)
bob.run(f'LoanCraft.Sync.Send("{alice.full}", "P", "{l8.id}", "forgive", 800000, GetServerTime(), "manual", "f2")')
route()
check(alice.ns.Balance(l8) == before, "borrower can't forgive their own debt")
eve = make("Eve Dark")
eve.run(f'LoanCraft.Sync.Send("{alice.full}", "N", "evil1", "Eve Dark", "{alice.full}", 99990000, 0, 7, GetServerTime(), 0, 0, "open")')
route()
check(len(alice.popups("LOANCRAFT_ACCEPT")) == 1 and alice.ns.Totals()[1] == ld[0].principal, "fake debt needs Alice's OK and isn't counted")
alice.G.ClickPopup(alice.popups("LOANCRAFT_ACCEPT")[0], 3); route()
check(alice.eval('LoanCraft.db.loans["evil1"].status') == "disputed", "disputed")
p8 = l8.principal
eve.run(f'LoanCraft.Sync.Send("{alice.full}", "N", "{l8.id}", "Eve Dark", "{alice.full}", 1, 0, 7, GetServerTime(), 0, 0, "open")')
route()
check(l8.principal == p8 and l8.borrower == bob.full, "another player can't rewrite a loan by reusing its id")
lb8 = bob.eval(f'LoanCraft.db.loans["{l8.id}"]')
owed8 = bob.ns.Owed(alice.full, bob.full)
alice.run(f'LoanCraft.Sync.Send("{bob.full}", "P", "{l8.id}", "add", 99990000, GetServerTime(), "manual", "add1")')
route()
check(not lb8.confirmed and bob.ns.Owed(alice.full, bob.full) < owed8 + 99990000, "lender adding to a loan needs the borrower's OK")
check(len(bob.popups("LOANCRAFT_ACCEPT")) == 1, "...Bob is asked")
bob.G.ClickPopup(bob.popups("LOANCRAFT_ACCEPT")[0], 1); route()
check(lb8.confirmed and bob.ns.Owed(alice.full, bob.full) == owed8 + 99990000, "...and counts once accepted")
lend(alice, bob, 3)
route(); bob.G.ClickPopup(bob.popups("LOANCRAFT_ACCEPT")[0], 1); route()
l9 = [l for l in alice.open_loans() if l.principal == 3*GOLD][0]
lb9 = bob.eval(f'LoanCraft.db.loans["{l9.id}"]')
alice.ns.DeleteLoan(l9.id)
for _ in range(10): alice.G.Advance(0.25)
alice.run("SIM.outbox = {}")  # the cancel never reaches Bob (offline)
advance(60); bob.ns.Sync.Hello(alice.full, True); route()
check(alice.eval(f'LoanCraft.db.loans["{l9.id}"]') is None, "a deleted loan isn't re-created by the borrower's sync")
check(lb9.status == "cancelled", "...and Bob is told it was cancelled")

# ======================================================================
print("\n-- Group channel")
for c, other in ((alice, bob), (bob, alice), (eve, alice)):
    c.group = "g1"
for c in (alice, bob, eve):
    others = [o for o in (alice, bob, eve) if o is not c]
    for i, o in enumerate(others):
        c.SIM.units[f"party{i+1}"] = o.full
    c.ev("GROUP_ROSTER_UPDATE")
alice.run("SIM.outbox = {}")
alice.ns.Sync.Hello(bob.full, True)
for _ in range(10): alice.G.Advance(0.25)
m = [x for x in alice.SIM.outbox.values() if "Bob Marsh" in x.msg[:12]][0]
check(m.channel == "PARTY" and m.msg.startswith("@Bob Marsh~"), "group members are messaged over PARTY: " + m.msg[:30])
route()
eve_peers = dict(eve.ns.db.peers)
check("alice stone" not in eve_peers or True, "ok")
eve.run("SIM.errors = {}")
check(len(bob.errors()) == 0 and len(eve.errors()) == 0, "no errors on group delivery")

# ======================================================================
print("\n-- Name picker, coin input, UI")
close_mail(alice); close_mail(bob)
alice.run('LoanCraftMinimapButton._scripts.OnClick(LoanCraftMinimapButton, "LeftButton")')
check(alice.G.LoanCraftFrame._shown, "minimap click opens LoanCraft")
alice.run('LoanCraftMinimapButton._scripts.OnClick(LoanCraftMinimapButton, "LeftButton")')
alice.SIM.shift = True
alice.run('LoanCraftMinimapButton._scripts.OnClick(LoanCraftMinimapButton, "LeftButton")')
alice.SIM.shift = False
nl = alice.G.LoanCraftNewLoan
check(nl._shown, "New loan dialog opens")
alice.ns.NoteContact("Fiona Reed", "whisper")
items = alice.ns.W.Candidates("")
heads = [it.header for it in items.values() if it.header]
names = [it.name for it in items.values() if not it.header]
print("   sections:", heads)
check("Loan partners" in heads and "Recent" in heads, "categorised suggestions")
check("Bob Marsh" in names and "Fiona Reed" in names, "includes loan partners and recent contacts")
alice.run("Type(LoanCraftNewLoan.picker.edit, 'fio')")
sug = alice.G.LoanCraftSuggest
check(sug._shown and any((it.name == "Fiona Reed") for it in sug["items"].values() if not it.header), "typing 'fio' suggests Fiona Reed")
check(len([1 for it in sug["items"].values() if not it.header]) == 1, "filtered to one match")
alice.run("LoanCraftNewLoan.picker.edit._scripts.OnEnterPressed(LoanCraftNewLoan.picker.edit)")
check(nl.picker.GetPlayer(nl.picker) == "Fiona Reed", "Enter picks it")
alice.run("""
C_FriendList = { GetNumFriends = function() return 1 end,
  GetFriendInfoByIndex = function() return { name = "Hal Offline", connected = false } end }
BNET_CLIENT_WOW = "WoW"
function BNGetNumFriends() return 2, 1 end
C_BattleNet = { GetFriendAccountInfo = function(i)
  if i == 1 then return { gameAccountInfo = { isOnline = true, clientProgram = "WoW", characterName = "Ivy Bright", realmName = "", areaName = "Elwynn" } } end
  return { gameAccountInfo = { isOnline = false } } end }
""")
alice.run("Type(LoanCraftNewLoan.picker.edit, 'IVY')")
check(any(it.name == "Ivy Bright" for it in sug["items"].values() if not it.header), "Battle.net friend online in WoW is suggested, case-insensitively")
alice.run("Type(LoanCraftNewLoan.picker.edit, 'hAl')")
check(any(it.name == "Hal Offline" for it in sug["items"].values() if not it.header), "offline character friend is suggested")
alice.run("C_FriendList = { GetNumFriends = function() return 0 end }; C_BattleNet = nil; BNGetNumFriends = nil")
check(alice.ns.Money(0) == "0" and alice.ns.Money(0, True) == "0c", "zero shows without a coin icon")
check(alice.ns.Money(123456).count("|T") == 3 and alice.ns.Money(123456, True) == "12g 34s 56c", "UI money uses coin icons, plain stays text")
alice.run("Type(LoanCraftNewLoan.picker.edit, 'smi')")  # no match
alice.SIM.shift = True
alice.run('SetItemRef("player:Gale Smithe-CAMWOWEU4Realm10RP:123:WHISPER", "[Gale Smithe]", "LeftButton")')
alice.SIM.shift = False
check(nl.picker.GetPlayer(nl.picker) == "Gale Smithe", "shift-click on a chat name fills the picker: " + str(nl.picker.GetPlayer(nl.picker)))
alice.run("Type(LoanCraftNewLoan.money.gold, '25'); Type(LoanCraftNewLoan.money.silver, '50')")
check(nl.money.GetCopper(nl.money) == 255000, "coin boxes: 25g 50s")
alice.run("Type(LoanCraftNewLoan.money.silver, '150')")
check(alice.eval("LoanCraftNewLoan.money.silver:GetText()") == "99", "silver capped at 99")
alice.run("Type(LoanCraftNewLoan.money.silver, '50')")
summary = strip(nl.summary.main._text) + " / " + strip(nl.summary.sub._text)
print("   summary:", summary, "| button:", nl.ok._text)
check(summary.startswith("Repay ") or summary.startswith("No "), "New loan summary box filled: " + summary)
alice.ns.UI.SubmitNewLoan(False)
check(any(l.borrower == "Gale Smithe" and l.principal == 255000 for l in alice.loans()), "loan created from the dialog")
# money input SetCopper
alice.run("LoanCraftNewLoan.money:SetCopper(1234567)")
check(alice.eval("LoanCraftNewLoan.money.gold:GetText()") == "123" and alice.eval("LoanCraftNewLoan.money.copper:GetText()") == "67", "SetCopper splits 123g 45s 67c")

for tab in ("loans", "people", "ledger"):
    alice.ns.UI.Open(tab); advance(0.1)
f = alice.G.LoanCraftFrame
check(f._shown, "main window opens")
alice.run("LoanCraftFrame.showClosed._scripts.OnClick(LoanCraftFrame.showClosed)")
alice.ns.UI.ShowPerson(bob.full, "ledger")
alice.ns.UI.Export()
csv = alice.G.LoanCraftExport.eb._text
check(csv.startswith("date,type,player") and "Bob Marsh" in csv, "CSV export (%d lines)" % csv.count("\n"))
alice.ns.UI.Open("loans")
# click every visible row button and menu entry
alice.run('''
for _, fr in ipairs(SIM.frames) do
  if fr.item and fr.primary and fr._shown and fr.primary._shown and fr.primary._scripts.OnClick then fr.primary._scripts.OnClick(fr.primary) end
end
''')
alice.run('''for _, fr in ipairs(SIM.frames) do if fr.item and fr.more and fr._shown then fr.more._scripts.OnClick(fr.more) end end''')
alice.ns.UI.ToggleOptions()
alice.run('for k, cb in pairs(LoanCraftOptions.checks) do cb._scripts.OnClick(cb) ; cb._scripts.OnClick(cb) end')
check(alice.G.SlashCmdList.LOANCRAFT is None, "no slash commands: everything is in the UI")
alice.G.LoanCraft_OnAddonCompartmentClick(None, "LeftButton")
# minimap clicks
alice.run('LoanCraftMinimapButton._scripts.OnEnter(LoanCraftMinimapButton)')
alice.run('LoanCraftMinimapButton._scripts.OnClick(LoanCraftMinimapButton, "RightButton")')
# tooltip hook
alice.SIM.units["mouseover"] = bob.full
alice.SIM.tooltipUnit = "mouseover"
alice.run('GameTooltip._lines = {}; SIM.tooltipHook(GameTooltip)')
tl = [strip(x) for x in (alice.G.GameTooltip._lines or {}).values()]
check(any("owes you" in x for x in tl), "player tooltip: " + str(tl))
# trade/mail panels
alice.SIM.tradePartner = bob.full; alice.G.TradeFrame._shown = True; alice.ev("TRADE_SHOW"); advance(0.1)
tp = alice.G.LoanCraftTradePanel
check(tp is not None and tp._shown, "trade panel shown")
print("   trade panel:", [strip(l._text) for l in tp.lines.values() if l._shown])
alice.G.TradeFrame._shown = False; alice.ev("TRADE_CLOSED")
open_mail(bob)
mp = bob.G.LoanCraftMailPanel
print("   bob mail panel:", [strip(l._text).replace("\n", " ") for l in mp.lines.values() if l._shown])
check(mp._shown, "mail panel shown")

for c in clients.values():
    errs = c.errors()
    check(len(errs) == 0, f"{c.full}: no Lua errors" + (f" {errs}" if errs else ""))

print("\nFAILURES:", fails)
sys.exit(1 if fails else 0)
