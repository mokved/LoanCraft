-- Minimal World of Warcraft: Forever client stub for testing LoanCraft outside the game (Lua 5.1).
-- Simulates timers, events, frames, trades, mail and hidden addon messages between clients.
local Clock = { t = 1800000000, gt = 1000 }
SIM = { clock = Clock, outbox = {}, chat = {}, popups = {}, whispers = {}, raid = {},
  inbox = {}, sent = {}, frames = {}, timers = {}, errors = {} }

function GetServerTime() return Clock.t end
function GetTime() return Clock.gt end
date = os.date
time = function() return Clock.t end
tinsert = table.insert
unpack = unpack or table.unpack

PLAYER_MONEY_VALUE = 10000000 -- 1000g
function GetMoney() return PLAYER_MONEY_VALUE end
function GetBuildInfo() return "1.60.1", "70000", "Nov 1 2026", 16001 end
SIM.units = {}
function UnitName(u)
  local n = (u == "player" and PLAYER_NAME) or (u == "NPC" and SIM.tradePartner) or SIM.units[u]
  if not n then return nil end
  local a, b = n:match("^(%S+) (%S+)$")
  return a or n, b
end
function GetUnitName(u, full)
  if u == "NPC" then return SIM.tradePartner end
  if u == "player" then return PLAYER_NAME end
  return SIM.units[u]
end
function GetNumGroupMembers() local n = 0 for k in pairs(SIM.units) do if k:match("^party") then n = n + 1 end end return n > 0 and n + 1 or 0 end
function IsShiftKeyDown() return SIM.shift end
function GetCursorPosition() return 0, 0 end
function GetCoinTextureString(c) return "COINS(" .. c .. ")" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function Mixin(o, ...) for _, m in ipairs({...}) do for k, v in pairs(m) do o[k] = v end end return o end
BackdropTemplateMixin = {}
YES, NO = "Yes", "No"
function SetItemRef(link, text, button) SIM.whoSent = link end
SIM.tradeItems = false
function GetTradePlayerItemInfo(i) if SIM.tradeItems and i == 1 then return "Linen Cloth" end end
function GetTradeTargetItemInfo(i) return nil end
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) SIM.tooltipHook = fn end }
Enum = { TooltipDataType = { Unit = 2 } }
function GetNormalizedRealmName() return "Stormrage" end
function GetRealmName() return "Stormrage" end
function UnitIsPlayer(u) return SIM.units[u] ~= nil end
function UnitExists(u) return SIM.units[u] ~= nil end
function IsInRaid() return false end
function IsInGuild() return false end
function InCombatLockdown() return false end
C_FriendList = { GetNumFriends = function() return 0 end }
function geterrorhandler() return function(e) table.insert(SIM.errors, tostring(e)); print("LUA ERROR: " .. tostring(e)) end end

-- Frames
local noop = function() end
local methods = {}
methods.SetScript = function(self, k, fn) self._scripts[k] = fn end
methods.GetScript = function(self, k) return self._scripts[k] end
methods.Show = function(self) self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end
methods.Hide = function(self) self._shown = false end
methods.IsShown = function(self) return self._shown end
methods.SetText = function(self, t)
  self._text = t
  if self._scripts.OnTextChanged then self._scripts.OnTextChanged(self, false) end
end
methods.GetText = function(self) return self._text end
methods.SetChecked = function(self, v) self._checked = v end
methods.GetChecked = function(self) return self._checked end
methods.GetParent = function(self) return self._parent end
methods.RegisterEvent = function(self, e) self._events[e] = true end
methods.UnregisterEvent = function(self, e) self._events[e] = nil end
methods.Cancel = function(self) self.cancelled = true end
local newObj
methods.CreateFontString = function(self) return newObj(nil, self) end
methods.CreateTexture = function(self) return newObj(nil, self) end
methods.CreateAnimationGroup = function(self) return newObj(nil, self) end
methods.CreateAnimation = function(self) return newObj(nil, self) end
methods.IsPlaying = function(self) return self._playing end
methods.Play = function(self) self._playing = true end
methods.Stop = function(self) self._playing = false end
methods.GetWidth = function(self) return self._w or 300 end
methods.SetWidth = function(self, w) self._w = w end
methods.GetHeight = function(self) return self._h or 300 end
methods.SetHeight = function(self, h) self._h = h end
methods.GetStringHeight = function() return 12 end
methods.GetStringWidth = function() return 80 end
methods.GetFrameLevel = function() return 5 end
methods.GetCenter = function() return 100, 100 end
methods.GetEffectiveScale = function() return 1 end
methods.GetVerticalScroll = function() return 0 end
methods.IsMouseOver = function() return false end
methods.HasFocus = function(self) return SIM.focus == self end
methods.SetFocus = function(self) SIM.focus = self end
methods.ClearFocus = function(self) if SIM.focus == self then SIM.focus = nil end end
methods.IsVisible = function(self) return self._shown end
methods.SetShown = function(self, v) if v then self:Show() else self:Hide() end end
methods.SetVertexColor = function(self, r, g, b) self._color = {r, g, b} end
methods.AddLine = function(self, t) self._lines = self._lines or {}; table.insert(self._lines, t) end
methods.GetUnit = function(self) return SIM.tooltipName, SIM.tooltipUnit end
methods.HookScript = function(self, k, fn)
  local old = self._scripts[k]
  self._scripts[k] = function(...) if old then old(...) end fn(...) end
end
local mt = { __index = function(t, k)
  if methods[k] then return methods[k] end
  if type(k) == "string" and k:match("^%u") then return noop end
  return nil
end }
newObj = function(name, parent)
  local o = setmetatable({ _scripts = {}, _events = {}, _shown = true, _text = "", _parent = parent }, mt)
  if name then _G[name] = o end
  table.insert(SIM.frames, o)
  return o
end
function CreateFrame(kind, name, parent, template)
  return newObj(name, parent)
end
UIParent = newObj("UIParent")
Minimap = newObj("Minimap")
UISpecialFrames = {}
GameTooltip = newObj("GameTooltip")
DEFAULT_CHAT_FRAME = newObj("DEFAULT_CHAT_FRAME")
DEFAULT_CHAT_FRAME.AddMessage = function(self, msg) table.insert(SIM.chat, msg) end
RaidWarningFrame = newObj("RaidWarningFrame")
ChatTypeInfo = { RAID_WARNING = {} }
SOUNDKIT = { RAID_WARNING = 8959 }
PlaySound = noop
function RaidNotice_AddMessage(f, text) table.insert(SIM.raid, text) end
SlashCmdList = {}
OKAY, CANCEL = "Okay", "Cancel"
ERR_TRADE_COMPLETE = "Trade complete."
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."

function FireEvent(event, ...)
  for _, f in ipairs(SIM.frames) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end

-- Timers
C_Timer = {
  After = function(sec, fn) table.insert(SIM.timers, { at = Clock.gt + sec, fn = fn }) end,
  NewTicker = function(sec, fn)
    local tk = newObj()
    tk.interval, tk.fn, tk.at, tk.ticker = sec, fn, Clock.gt + sec, true
    table.insert(SIM.timers, tk)
    return tk
  end,
}
function Advance(sec)
  local target = Clock.gt + sec
  while true do
    local best
    for _, tm in ipairs(SIM.timers) do
      if not tm.cancelled and not tm.done and tm.at <= target and (not best or tm.at < best.at) then best = tm end
    end
    if not best then break end
    local dt = best.at - Clock.gt
    if dt > 0 then Clock.gt = Clock.gt + dt; Clock.t = Clock.t + math.floor(dt) end
    if best.ticker then best.at = best.at + best.interval else best.done = true end
    best.fn()
  end
  local dt = target - Clock.gt
  Clock.gt = target
  Clock.t = Clock.t + math.floor(dt)
end
-- Jump the server clock without running timers (days passing while logged out)
function Jump(sec)
  Clock.t = Clock.t + sec
  Clock.gt = Clock.gt + sec
  for _, tm in ipairs(SIM.timers) do if tm.at < Clock.gt then tm.at = Clock.gt end end
end

-- Addon messages
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(p) SIM.prefix = p; return true end,
  SendAddonMessage = function(prefix, msg, channel, target)
    table.insert(SIM.outbox, { prefix = prefix, msg = msg, channel = channel, target = target })
    return true
  end,
}
function SendChatMessage(msg, chatType, lang, target) table.insert(SIM.whispers, { msg = msg, target = target }) end
SIM.chatFilters = {}
function ChatFrame_AddMessageEventFilter(event, fn) table.insert(SIM.chatFilters, fn) end

function hooksecurefunc(name, fn)
  local orig = _G[name]
  _G[name] = function(...)
    local r = { orig(...) }
    fn(...)
    return unpack(r)
  end
end

-- Popups
StaticPopupDialogs = {}
function StaticPopup_Show(which, text1, text2, data)
  local p = newObj()
  p.which, p.text, p.data = which, text1, data
  p.editBox = newObj(nil, p)
  table.insert(SIM.popups, p)
  local d = StaticPopupDialogs[which]
  if d.OnShow then d.OnShow(p) end
  return p
end
function ClickPopup(p, button, editText)
  local d = StaticPopupDialogs[p.which]
  if editText then p.editBox:SetText(editText) end
  for i, x in ipairs(SIM.popups) do if x == p then table.remove(SIM.popups, i) break end end
  if d.OnHide then d.OnHide(p) end
  if button == 1 then d.OnAccept(p, p.data)
  elseif button == 2 then if d.OnCancel then d.OnCancel(p, p.data) end
  else (d.OnButton3 or d.OnAlt)(p, p.data) end
end

-- Trade
TradeFrame = newObj("TradeFrame"); TradeFrame._shown = false
TradePlayerInputMoneyFrame = newObj("TradePlayerInputMoneyFrame")
SIM.tradeGive, SIM.tradeGet = 0, 0
function GetPlayerTradeMoney() return SIM.tradeGive end
function GetTargetTradeMoney() return SIM.tradeGet end
function SetTradeMoney(c) SIM.tradeGive = c end

-- Mail
MailFrame = newObj("MailFrame"); MailFrame._shown = false
SendMailNameEditBox = newObj("SendMailNameEditBox")
SendMailSubjectEditBox = newObj("SendMailSubjectEditBox")
SendMailMoney = newObj("SendMailMoney")
SIM.sendMoney = 0
function MoneyInputFrame_SetCopper(f, c)
  f._copper = c
  if f == SendMailMoney then SIM.sendMoney = c end
  if f == TradePlayerInputMoneyFrame then SIM.tradeGive = c end
end
function MoneyInputFrame_GetCopper(f) return f._copper or 0 end
function GetSendMailMoney() return SIM.sendMoney end
function GetSendMailPrice() return 30 end
MailFrameTab_OnClick = noop
function SendMail(to, subject, body)
  table.insert(SIM.sent, { to = to, subject = subject, money = SIM.sendMoney })
end
function GetInboxHeaderInfo(i)
  local m = SIM.inbox[i]
  if not m then return end
  return nil, nil, m.sender, m.subject, m.money, 0, 30, false, false, false
end
function TakeInboxMoney(i)
  SIM.pendingTake = i
end
function AutoLootMailItem(i) SIM.pendingTake = i end
-- server answers the take
function ServerTake()
  local m = SIM.inbox[SIM.pendingTake]
  SIM.pendingTake = nil
  PLAYER_MONEY_VALUE = PLAYER_MONEY_VALUE + m.money
  m.money = 0
  FireEvent("PLAYER_MONEY")
end

-- Load the addon the way the client does: files in TOC order
function LoadAddon(dir, name)
  local ns = {}
  local toc = assert(io.open(dir .. "/" .. name .. ".toc"))
  for line in toc:lines() do
    line = line:gsub("%s+$", "")
    if line ~= "" and not line:match("^#") then
      local chunk = assert(loadfile(dir .. "/" .. line))
      chunk(name, ns)
    end
  end
  toc:close()
  FireEvent("ADDON_LOADED", name)
  FireEvent("PLAYER_LOGIN")
  return ns
end
