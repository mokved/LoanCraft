-- LoanCraft: shared UI pieces (panels, coin input, player picker, lists, menus)
local _, ns = ...
local W = {}
ns.W = W

local FLAT = "Interface\\Buttons\\WHITE8x8"
W.FLAT = FLAT
W.C = {
  bg = { 0.055, 0.055, 0.07, 0.97 },
  border = { 0.42, 0.34, 0.14, 1 },
  header = { 0.13, 0.11, 0.06, 1 },
  row = { 1, 1, 1, 0.035 },
  rowAlt = { 1, 1, 1, 0.065 },
  hover = { 1, 0.82, 0, 0.12 },
  green = { 0.25, 0.85, 0.3 },
  red = { 0.95, 0.3, 0.3 },
  orange = { 1, 0.6, 0.1 },
  blue = { 0.35, 0.65, 1 },
}

---------------------------------------------------------------------------
-- Basics
---------------------------------------------------------------------------
function W.Text(parent, font, text, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  if text then fs:SetText(text) end
  if r then fs:SetTextColor(r, g, b) end
  fs:SetJustifyH("LEFT")
  return fs
end

-- Form field label: light grey, so gold stays for selection and key numbers
function W.Label(parent, text)
  return W.Text(parent, "GameFontNormalSmall", text, 0.78, 0.78, 0.78)
end

function W.Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h or 22)
  b:SetText(text)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function W.Tip(frame, title, ...)
  local lines = { ... }
  frame:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(type(title) == "function" and title() or title, 1, 0.82, 0)
    for _, l in ipairs(lines) do GameTooltip:AddLine(l, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function W.Backdrop(f, bg, border)
  if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
  f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
  f:SetBackdropColor(unpack(bg or W.C.bg))
  f:SetBackdropBorderColor(unpack(border or W.C.border))
end

-- Opaque fill under a backdrop: the backdrop's own center comes out see-through in game
function W.Fill(f, c)
  local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  t:SetPoint("TOPLEFT", 1, -1)
  t:SetPoint("BOTTOMRIGHT", -1, 1)
  t:SetColorTexture(c[1], c[2], c[3], 1)
  return t
end

-- A movable dialog window with a title bar and close button
function W.Panel(name, w, h, title, parent)
  local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  W.Backdrop(f)
  W.Fill(f, W.C.bg)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:Hide()
  if name then tinsert(UISpecialFrames, name) end
  local bar = f:CreateTexture(nil, "ARTWORK")
  bar:SetColorTexture(unpack(W.C.header))
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(28)
  local icon = f:CreateTexture(nil, "OVERLAY")
  icon:SetSize(18, 18)
  icon:SetPoint("TOPLEFT", 8, -6)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.title = W.Text(f, "GameFontNormal", title)
  f.title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetSize(24, 24)
  f.close:SetPoint("TOPRIGHT", -3, -3)
  return f
end

-- Show `dlg` over `owner`: one strata up so the two never interleave, centred on
-- the owner, with the owner dimmed. Clicking the dimmed area closes the dialog.
function W.Modal(dlg, owner)
  dlg:SetFrameStrata("FULLSCREEN")
  dlg:SetFrameLevel(20)
  local shade = CreateFrame("Button", nil, UIParent)
  shade:SetFrameStrata("FULLSCREEN")
  shade:SetFrameLevel(1)
  W.Fill(shade, { 0, 0, 0 }):SetAlpha(0.55)
  shade:SetScript("OnClick", function() dlg:Hide() end)
  shade:Hide()
  dlg:HookScript("OnShow", function()
    local o = owner()
    if not (o and o:IsShown()) then return end
    dlg:ClearAllPoints()
    dlg:SetPoint("CENTER", o, "CENTER")
    shade:ClearAllPoints()
    shade:SetAllPoints(o)
    shade:Show()
  end)
  dlg:HookScript("OnHide", function() shade:Hide() end)
end

function W.Check(parent, label, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb.label = W.Text(cb, "GameFontHighlight", label)
  cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
  if onClick then cb:SetScript("OnClick", function(self) onClick(self, self:GetChecked() and true or false) end) end
  return cb
end

function W.Input(parent, width, numeric)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width, 20)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEnterPressed", e.ClearFocus)
  e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  return e
end

-- Small flat toggle/tab button
function W.Tab(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h or 22)
  W.Backdrop(b, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.12 })
  b.text = W.Text(b, "GameFontNormalSmall", text)
  b.text:SetPoint("CENTER")
  b.text:SetJustifyH("CENTER")
  b:SetScript("OnEnter", function(self) if not self.active then self:SetBackdropColor(1, 0.82, 0, 0.10) end end)
  b:SetScript("OnLeave", function(self) if not self.active then self:SetBackdropColor(1, 1, 1, 0.04) end end)
  b:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
  function b:SetActive(on)
    self.active = on
    self:SetBackdropColor(on and 1 or 1, on and 0.82 or 1, on and 0 or 1, on and 0.22 or 0.04)
    self:SetBackdropBorderColor(on and 1 or 1, on and 0.82 or 1, on and 0 or 1, on and 0.6 or 0.12)
    self.text:SetTextColor(on and 1 or 0.85, on and 0.9 or 0.85, on and 0.5 or 0.85)
  end
  b:SetActive(false)
  return b
end

---------------------------------------------------------------------------
-- Coin input: [ gold ](g) [ss](s) [cc](c)
---------------------------------------------------------------------------
local COIN = {
  "Interface\\MoneyFrame\\UI-GoldIcon",
  "Interface\\MoneyFrame\\UI-SilverIcon",
  "Interface\\MoneyFrame\\UI-CopperIcon",
}

function W.MoneyInput(parent, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(170, 22)
  local boxes = {}
  local function box(width, maxLetters)
    local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetNumeric(true)
    e:SetMaxLetters(maxLetters)
    e:SetJustifyH("RIGHT")
    e:SetTextInsets(0, 6, 0, 0) -- the template's border ends flush with the right edge; keep digits inside it
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    e:SetScript("OnTextChanged", function(self, user)
      if maxLetters == 2 then
        local v = tonumber(self:GetText())
        if v and v > 99 then self:SetText("99") end
      end
      if user and f.onChange then f.onChange(f:GetCopper()) end
    end)
    e:SetScript("OnEnterPressed", function(self)
      self:ClearFocus()
      if f.onEnter then f.onEnter(f:GetCopper()) end
    end)
    boxes[#boxes + 1] = e
    return e
  end
  f.gold = box(62, 7)
  f.silver = box(24, 2)
  f.copper = box(24, 2)
  local prev
  for i, e in ipairs(boxes) do
    if prev then e:SetPoint("LEFT", prev, "RIGHT", 9, 0) else e:SetPoint("LEFT", 5, 0) end
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(13, 13)
    icon:SetTexture(COIN[i])
    icon:SetPoint("LEFT", e, "RIGHT", 1, 0)
    prev = icon
    e:SetScript("OnTabPressed", function(self)
      local j = IsShiftKeyDown() and i - 1 or i + 1
      if boxes[j] then boxes[j]:SetFocus()
      elseif f.onTab then self:ClearFocus(); f.onTab(IsShiftKeyDown()) end
    end)
  end
  f.onChange = onChange

  function f:GetCopper()
    local g = tonumber(self.gold:GetText()) or 0
    local s = math.min(99, tonumber(self.silver:GetText()) or 0)
    local c = math.min(99, tonumber(self.copper:GetText()) or 0)
    return g * 10000 + s * 100 + c
  end
  function f:SetCopper(c)
    c = math.max(0, math.floor((c or 0) + 0.5))
    local g, s, cc = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    self.gold:SetText(g > 0 and tostring(g) or "")
    self.silver:SetText(s > 0 and tostring(s) or "")
    self.copper:SetText(cc > 0 and tostring(cc) or "")
    if self.onChange then self.onChange(self:GetCopper()) end
  end
  function f:Focus() self.gold:SetFocus() end
  function f:ClearAllFocus() for _, e in ipairs(boxes) do e:ClearFocus() end end
  return f
end

---------------------------------------------------------------------------
-- Player picker: type-ahead + categorised dropdown + shift-click names
---------------------------------------------------------------------------
local SRC_TEXT = { trade = "traded", mail = "mail", whisper = "whispered", group = "grouped", loan = "loan" }

function W.Candidates(filter)
  filter = (filter or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local seen, out = {}, {}
  local me = ns.Me()
  local function section(title, list, limit)
    local added, n = false, 0
    for _, it in ipairs(list) do
      local k = it.name and it.name:lower()
      if k and not seen[k] and not ns.Same(it.name, me) and (filter == "" or k:find(filter, 1, true)) then
        if limit and n >= limit then break end
        if not added then out[#out + 1] = { header = title }; added = true end
        seen[k] = true
        n = n + 1
        out[#out + 1] = it
      end
    end
  end

  local target = ns.UnitFull("target")
  section("Target", target and { { name = target, info = "your target" } } or {})

  local people = {}
  for _, p in ipairs(ns.People()) do
    local info
    if p.owesMe > 0 then info = "|cff40ff40owes you " .. ns.Money(p.owesMe) .. "|r"
    elseif p.iOwe > 0 then info = "|cffff6060you owe " .. ns.Money(p.iOwe) .. "|r"
    else info = "past loans" end
    people[#people + 1] = { name = p.name, info = info }
  end
  section("Loan partners", people)

  local recent = {}
  for _, c in pairs(ns.db.contacts) do recent[#recent + 1] = c end
  table.sort(recent, function(a, b) return a.t > b.t end)
  local rlist = {}
  for _, c in ipairs(recent) do
    rlist[#rlist + 1] = { name = c.name, info = (SRC_TEXT[c.src] or c.src or "") .. " " .. ns.Ago(c.t) }
  end
  section("Recent", rlist, filter == "" and 10 or nil)

  local glist = {}
  for name in pairs(ns.Sync.GroupMembers()) do
    local full = ns.FullName(name)
    if full then glist[#glist + 1] = { name = full, info = (IsInRaid and IsInRaid()) and "raid" or "party" } end
  end
  table.sort(glist, function(a, b) return a.name < b.name end)
  section("Party / Raid", glist)

  local on, off = {}, {}
  -- Battle.net friends: the game only tells us their character while they're online in WoW
  if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
    for i = 1, (BNGetNumFriends()) or 0 do
      local acc = C_BattleNet.GetFriendAccountInfo(i)
      local ga = acc and acc.gameAccountInfo
      if ga and ga.isOnline and ga.clientProgram == (BNET_CLIENT_WOW or "WoW") and ga.characterName
        and (not WOW_PROJECT_ID or not ga.wowProjectID or ga.wowProjectID == WOW_PROJECT_ID) then
        local n = ga.characterName
        if not ns.IS_FOREVER and ga.realmName and ga.realmName ~= "" then n = n .. "-" .. ga.realmName end
        local full = ns.FullName(n)
        if full then on[#on + 1] = { name = full, info = "|cff82c5ffonline|r" .. (ga.areaName and (" · " .. ga.areaName) or "") } end
      end
    end
  end
  if C_FriendList and C_FriendList.GetNumFriends then
    for i = 1, C_FriendList.GetNumFriends() do
      local info = C_FriendList.GetFriendInfoByIndex(i)
      local full = info and ns.FullName(info.name)
      if full then
        if info.connected then on[#on + 1] = { name = full, info = "|cff40ff40online|r" .. (info.area and (" · " .. info.area) or "") }
        else off[#off + 1] = { name = full, info = "offline" } end
      end
    end
  end
  for _, x in ipairs(off) do on[#on + 1] = x end
  section("Friends", on)

  if IsInGuild and IsInGuild() and GetNumGuildMembers then
    local on, off = {}, {}
    for i = 1, GetNumGuildMembers() do
      local name, rank, _, _, _, zone, _, _, online = GetGuildRosterInfo(i)
      local full = ns.FullName(name)
      if full then
        if online then on[#on + 1] = { name = full, info = "|cff40ff40online|r · " .. (rank or "") }
        elseif filter ~= "" then off[#off + 1] = { name = full, info = "offline · " .. (rank or "") } end
      end
    end
    table.sort(on, function(a, b) return a.name < b.name end)
    for _, x in ipairs(off) do on[#on + 1] = x end
    section("Guild", on, filter == "" and 40 or 25)
  end
  return out
end

-- Shared suggestion dropdown
local SUG_ROWS, SUG_H = 14, 18
local Suggest = CreateFrame("Frame", "LoanCraftSuggest", UIParent, "BackdropTemplate")
Suggest:SetFrameStrata("FULLSCREEN_DIALOG")
Suggest:SetSize(300, SUG_ROWS * SUG_H + 10)
W.Backdrop(Suggest, { 0.04, 0.04, 0.05, 0.98 })
W.Fill(Suggest, { 0.04, 0.04, 0.05 })
Suggest:Hide()
Suggest:EnableMouseWheel(true)
Suggest.rows, Suggest.items, Suggest.offset, Suggest.sel = {}, {}, 0, nil
W.Suggest = Suggest

for i = 1, SUG_ROWS do
  local r = CreateFrame("Button", nil, Suggest)
  r:SetHeight(SUG_H)
  r:SetPoint("TOPLEFT", 5, -5 - (i - 1) * SUG_H)
  r:SetPoint("TOPRIGHT", -5, -5 - (i - 1) * SUG_H)
  r.hl = r:CreateTexture(nil, "BACKGROUND")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(1, 0.82, 0, 0.18)
  r.hl:Hide()
  r.name = W.Text(r, "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", 4, 0)
  r.info = W.Text(r, "GameFontDisableSmall")
  r.info:SetPoint("RIGHT", -4, 0)
  r.info:SetJustifyH("RIGHT")
  r:SetScript("OnEnter", function(self)
    if self.item and not self.item.header then Suggest.sel = self.index; Suggest:Render() end
  end)
  r:SetScript("OnClick", function(self)
    if self.item and not self.item.header then Suggest.sel = self.index; Suggest:Pick() end
  end)
  Suggest.rows[i] = r
end

function Suggest:Render()
  local items = self.items
  local maxOff = math.max(0, #items - SUG_ROWS)
  self.offset = math.max(0, math.min(self.offset, maxOff))
  for i, r in ipairs(self.rows) do
    local idx = self.offset + i
    local it = items[idx]
    r.item, r.index = it, idx
    if it then
      if it.header then
        r.name:SetText("|cffffd100" .. it.header:upper() .. "|r")
        r.info:SetText("")
        r.hl:Hide()
      else
        r.name:SetText("  " .. it.name)
        r.info:SetText(it.info or "")
        r.hl:SetShown(idx == self.sel)
      end
      r:Show()
    else
      r:Hide()
    end
  end
  local shown = math.min(SUG_ROWS, #items)
  self:SetHeight(math.max(1, shown) * SUG_H + 10)
end

function Suggest:Move(dir)
  local i = self.sel or 0
  repeat i = i + dir until not self.items[i] or not self.items[i].header
  if not self.items[i] then return end
  self.sel = i
  if i <= self.offset then self.offset = i - 2 end
  if i > self.offset + SUG_ROWS then self.offset = i - SUG_ROWS end
  self:Render()
end

function Suggest:Pick()
  local it = self.sel and self.items[self.sel]
  if not it or it.header or not self.owner then return false end
  local owner = self.owner
  self:Hide()
  owner:SetPlayer(it.name)
  return true
end

Suggest:SetScript("OnMouseWheel", function(self, delta)
  self.offset = self.offset - delta * 3
  self:Render()
end)
Suggest:SetScript("OnHide", function(self) self.owner = nil end)

function W.ShowSuggest(owner, text)
  if C_GuildInfo and C_GuildInfo.GuildRoster and IsInGuild and IsInGuild() then pcall(C_GuildInfo.GuildRoster) end
  if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
  local items = W.Candidates(text)
  if #items == 0 then Suggest:Hide(); return end
  Suggest.items, Suggest.offset, Suggest.sel, Suggest.owner = items, 0, nil, owner
  for i, it in ipairs(items) do if not it.header then Suggest.sel = i break end end
  Suggest:ClearAllPoints()
  Suggest:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  Suggest:SetWidth(math.max(owner:GetWidth(), 300))
  Suggest:Render()
  Suggest:Show()
end

W.pickers = {}

function W.NamePicker(parent, width, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width, 22)
  local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  e:SetPoint("LEFT", 5, 0)
  e:SetSize(width - 32, 20)
  e:SetAutoFocus(false)
  f.edit = e
  f.onChange = onChange

  local b = CreateFrame("Button", nil, f)
  b:SetSize(24, 24)
  b:SetPoint("LEFT", e, "RIGHT", 2, 0)
  b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  b:SetScript("OnClick", function()
    if Suggest:IsShown() and Suggest.owner == f then Suggest:Hide()
    else W.ShowSuggest(f, ""); e:SetFocus() end
  end)
  W.Tip(b, "Pick a player", "Target, loan partners, recent trades/mail/whispers, group, friends and guild.",
    "|cffaaaaaaTip: shift-click a name in chat to fill it in.|r")

  e:SetScript("OnTextChanged", function(self, user)
    if user then W.ShowSuggest(f, self:GetText()) end
    if f.onChange then f.onChange(f:GetPlayer()) end
  end)
  e:SetScript("OnEditFocusGained", function() W.activePicker = f end)
  e:SetScript("OnEnterPressed", function(self)
    if Suggest:IsShown() and Suggest.owner == f and Suggest:Pick() then return end
    self:ClearFocus()
  end)
  e:SetScript("OnTabPressed", function(self)
    if Suggest:IsShown() and Suggest.owner == f then Suggest:Pick() end
    self:ClearFocus()
    if f.onTab then f.onTab() end
  end)
  e:SetScript("OnArrowPressed", function(_, key)
    if Suggest.owner ~= f or not Suggest:IsShown() then return end
    if key == "UP" then Suggest:Move(-1) elseif key == "DOWN" then Suggest:Move(1) end
  end)
  e:SetScript("OnEscapePressed", function(self)
    if Suggest.owner == f then Suggest:Hide() end
    self:ClearFocus()
  end)
  e:SetScript("OnEditFocusLost", function()
    C_Timer.After(0.25, function()
      if Suggest.owner == f and not e:HasFocus() and not Suggest:IsMouseOver() then Suggest:Hide() end
    end)
  end)
  f:SetScript("OnHide", function() if Suggest.owner == f then Suggest:Hide() end end)
  f:SetScript("OnShow", function() W.activePicker = f end)

  function f:GetPlayer() return ns.FullName(self.edit:GetText()) end
  function f:SetPlayer(name)
    self.edit:SetText(name and ns.MailName(name) or "")
    self.edit:SetCursorPosition(0)
    if self.onChange then self.onChange(self:GetPlayer()) end
  end
  W.pickers[#W.pickers + 1] = f
  return f
end

-- Shift-click a player name in chat while a picker is open
if hooksecurefunc and SetItemRef then
  hooksecurefunc("SetItemRef", function(link)
    if type(link) ~= "string" or not IsShiftKeyDown() or ns.Secret(link) then return end
    local name = link:match("^player:([^:]+)")
    local p = W.activePicker
    if not (p and p:IsVisible()) then
      p = nil
      for _, x in ipairs(W.pickers) do if x:IsVisible() then p = x end end
    end
    if name and p then
      p:SetPlayer(ns.FullName(name))
      ns.Sound()
    end
  end)
end

---------------------------------------------------------------------------
-- Scrolling list with recycled rows
---------------------------------------------------------------------------
function W.List(parent, rowH, numRows, create, update)
  local f = CreateFrame("Frame", nil, parent)
  f.rows, f.data, f.offset, f.rowH = {}, {}, 0, rowH
  for i = 1, numRows do
    local r = create(f, i)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
    r:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -(i - 1) * rowH)
    r:SetHeight(rowH - 2)
    f.rows[i] = r
  end
  local track = f:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(1, 1, 1, 0.05)
  track:SetPoint("TOPRIGHT", 0, 0)
  track:SetPoint("BOTTOMRIGHT", 0, 0)
  track:SetWidth(4)
  local thumb = f:CreateTexture(nil, "ARTWORK")
  thumb:SetColorTexture(1, 0.82, 0, 0.5)
  thumb:SetWidth(4)
  f.thumb = thumb
  f.empty = W.Text(f, "GameFontDisable")
  f.empty:SetPoint("TOP", 0, -40)
  f.empty:SetJustifyH("CENTER")

  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(self, delta)
    self.offset = self.offset - delta * 2
    self:Refresh()
  end)

  function f:SetData(data, emptyText)
    self.data = data
    self.empty:SetText(#data == 0 and (emptyText or "") or "")
    self:Refresh()
  end
  function f:Refresh()
    local n = #self.rows
    local maxOff = math.max(0, #self.data - n)
    self.offset = math.max(0, math.min(self.offset, maxOff))
    for i, r in ipairs(self.rows) do
      local item = self.data[self.offset + i]
      r.item = item
      if item then update(r, item, self.offset + i); r:Show() else r:Hide() end
    end
    if maxOff > 0 then
      local h = self:GetHeight()
      local th = math.max(20, h * n / #self.data)
      thumb:SetHeight(th)
      thumb:ClearAllPoints()
      thumb:SetPoint("TOPRIGHT", 0, -((h - th) * self.offset / maxOff))
      thumb:Show(); track:Show()
    else
      thumb:Hide(); track:Hide()
    end
  end
  return f
end

-- A list row with hover highlight and zebra striping
function W.Row(parent, i)
  local r = CreateFrame("Button", nil, parent)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.bg:SetColorTexture(unpack(i % 2 == 0 and W.C.rowAlt or W.C.row))
  r.hl = r:CreateTexture(nil, "BORDER")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(unpack(W.C.hover))
  r.hl:Hide()
  r:SetScript("OnEnter", function(self) self.hl:Show(); if self.OnHover then self:OnHover() end end)
  r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
  return r
end

---------------------------------------------------------------------------
-- Context menu
---------------------------------------------------------------------------
local menu = CreateFrame("Frame", "LoanCraftMenu", UIParent, "BackdropTemplate")
menu:SetFrameStrata("FULLSCREEN_DIALOG")
menu:SetFrameLevel(100)
W.Backdrop(menu, { 0.04, 0.04, 0.05, 0.98 })
W.Fill(menu, { 0.04, 0.04, 0.05 })
menu:Hide()
menu.buttons = {}
local blocker = CreateFrame("Button", nil, UIParent)
blocker:SetAllPoints(UIParent)
blocker:SetFrameStrata("FULLSCREEN_DIALOG")
blocker:SetFrameLevel(90)
blocker:Hide()
blocker:SetScript("OnClick", function() menu:Hide() end)
menu:SetScript("OnHide", function() blocker:Hide() end)

function W.Menu(anchor, items)
  local width = 150
  for i, it in ipairs(items) do
    local b = menu.buttons[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetHeight(20)
      b.hl = b:CreateTexture(nil, "BACKGROUND")
      b.hl:SetAllPoints()
      b.hl:SetColorTexture(1, 0.82, 0, 0.18)
      b.hl:Hide()
      b.text = W.Text(b, "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", 8, 0)
      b:SetScript("OnEnter", function(self) if not self.disabled then self.hl:Show() end end)
      b:SetScript("OnLeave", function(self) self.hl:Hide() end)
      menu.buttons[i] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
    b:SetPoint("RIGHT", -4, 0)
    b.disabled = it.disabled or it.title
    local text = it.text
    if it.title then text = "|cffffd100" .. text .. "|r"
    elseif it.disabled then text = "|cff777777" .. text .. "|r"
    elseif it.checked ~= nil then text = (it.checked and "|TInterface\\Buttons\\UI-CheckBox-Check:14:14|t" or "     ") .. text end
    b.text:SetText(text)
    b:SetScript("OnClick", function()
      if b.disabled then return end
      menu:Hide()
      if it.func then it.func() end
    end)
    b:Show()
    width = math.max(width, (b.text:GetStringWidth() or 100) + 24)
  end
  for i = #items + 1, #menu.buttons do menu.buttons[i]:Hide() end
  menu:SetSize(width, #items * 20 + 8)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  blocker:Show()
  menu:Show()
end

---------------------------------------------------------------------------
-- Loan terms editor: interest % per N days, due in N days, late fee %
---------------------------------------------------------------------------
local PERIODS = { 1, 7, 14, 30 }
local DUES = { 3, 7, 14, 30, 0 }

-- col: x where the controls start, so callers can line them up with their own fields
function W.Terms(parent, onChange, col)
  col = col or 64
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(col + 300, 74)
  local function changed() if f.onChange then f.onChange(f:Get()) end end
  f.onChange = onChange

  local l1 = W.Label(f, "Interest")
  l1:SetPoint("TOPLEFT", 0, -4)
  f.rate = W.Input(f, 34)
  f.rate:SetPoint("TOPLEFT", col + 5, 0) -- +5: the input's border starts left of its frame
  f.rate:SetScript("OnTextChanged", changed)
  local pct = W.Text(f, "GameFontHighlightSmall", "% per")
  pct:SetPoint("LEFT", f.rate, "RIGHT", 4, 0)
  f.periodBtn = W.Tab(f, "week", 64, 20, function(self)
    local items = {}
    for _, d in ipairs(PERIODS) do
      items[#items + 1] = { text = ns.PeriodText(d), checked = f.period == d, func = function() f:SetPeriod(d); changed() end }
    end
    W.Menu(self, items)
  end)
  f.periodBtn:SetPoint("LEFT", pct, "RIGHT", 6, 0)
  f.periodBtn.text:SetPoint("CENTER", -7, 0)
  local arrow = f.periodBtn:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(14, 14)
  arrow:SetPoint("RIGHT", -2, 0)
  arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")

  local l2 = W.Label(f, "Due in")
  l2:SetPoint("TOPLEFT", 0, -30)
  f.dueChips = {}
  local prev
  for i, d in ipairs(DUES) do
    local chip = W.Tab(f, d == 0 and "none" or (d .. "d"), 40, 20, function() f:SetDue(d); changed() end)
    if prev then chip:SetPoint("LEFT", prev, "RIGHT", 3, 0) else chip:SetPoint("TOPLEFT", col, -26) end
    chip.days = d
    f.dueChips[i] = chip
    prev = chip
  end
  f.dueBox = W.Input(f, 30)
  f.dueBox:SetPoint("LEFT", prev, "RIGHT", 10, 0)
  f.dueBox:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local v = tonumber(self:GetText())
    if v then f.dueDays = math.max(0, v); f:SyncChips(); changed() end
  end)
  local dl = W.Text(f, "GameFontDisableSmall", "days")
  dl:SetPoint("LEFT", f.dueBox, "RIGHT", 3, 0)

  local l3 = W.Label(f, "Late fee")
  l3:SetPoint("TOPLEFT", 0, -56)
  f.fee = W.Input(f, 34)
  f.fee:SetPoint("TOPLEFT", col + 5, -52)
  f.fee:SetScript("OnTextChanged", changed)
  local fl = W.Text(f, "GameFontDisableSmall", "% added once if it goes overdue")
  fl:SetPoint("LEFT", f.fee, "RIGHT", 4, 0)

  function f:SetPeriod(d)
    self.period = d
    self.periodBtn.text:SetText(ns.PeriodText(d))
  end
  function f:SyncChips()
    for _, c in ipairs(self.dueChips) do c:SetActive(c.days == self.dueDays) end
    if not self.dueBox:HasFocus() then self.dueBox:SetText(self.dueDays > 0 and tostring(self.dueDays) or "") end
  end
  function f:SetDue(d)
    self.dueDays = d
    self:SyncChips()
  end
  function f:Set(t)
    self.rate:SetText(tostring(t.ratePct or 0))
    self:SetPeriod(t.period or 7)
    self:SetDue(t.dueDays or 0)
    self.fee:SetText(tostring(t.lateFeePct or 0))
  end
  function f:Get()
    return {
      ratePct = math.max(0, tonumber(self.rate:GetText()) or 0),
      period = self.period or 7,
      dueDays = self.dueDays or 0,
      lateFeePct = math.max(0, tonumber(self.fee:GetText()) or 0),
    }
  end
  return f
end
