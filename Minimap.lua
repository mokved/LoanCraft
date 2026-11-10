-- LoanCraft: minimap button with status light, data broker feed, player tooltips
local _, ns = ...
local W = ns.W
local M = {}
ns.Minimap = M
local btn

local LEVEL_COLOR = {
  [3] = { 1, 0.15, 0.15 },  -- something is overdue
  [2] = { 1, 0.6, 0.05 },   -- due within a day
  [1] = { 0.3, 0.65, 1 },   -- needs a decision
}

local function place()
  local angle = math.rad(ns.db.minimap.angle or 200)
  local r = (Minimap:GetWidth() / 2) + 6
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function showTooltip(owner, tt)
  tt = tt or GameTooltip
  if owner then tt:SetOwner(owner, "ANCHOR_LEFT") end
  tt:AddLine("LoanCraft", 1, 0.82, 0)
  local owedToMe, iOwe = ns.Totals()
  tt:AddDoubleLine("Owed to you", ns.Money(owedToMe), 0.8, 0.8, 0.8, 0.3, 1, 0.3)
  tt:AddDoubleLine("You owe", ns.Money(iOwe), 0.8, 0.8, 0.8, 1, 0.4, 0.4)
  local alerts = ns.Alerts()
  if #alerts > 0 then
    tt:AddLine(" ")
    for i = 1, math.min(8, #alerts) do
      local a = alerts[i]
      local c = LEVEL_COLOR[a.level]
      tt:AddLine(a.text, c[1], c[2], c[3], true)
    end
    if #alerts > 8 then tt:AddLine(("...and %d more"):format(#alerts - 8), 0.6, 0.6, 0.6) end
  else
    tt:AddLine("Nothing due soon.", 0.6, 0.6, 0.6)
  end
  tt:AddLine(" ")
  tt:AddLine("|cffffffffClick|r open  ·  |cffffffffShift-click|r new loan  ·  |cffffffffRight-click|r menu", 0.6, 0.6, 0.6, true)
  if owner then tt:Show() end
end

local function menu(anchor)
  local pending = #ns.PendingTransfers()
  W.Menu(anchor, {
    { text = "LoanCraft", title = true },
    { text = "New loan...", func = function() ns.UI.OpenNewLoan() end },
    { text = "Review transfers" .. (pending > 0 and (" (" .. pending .. ")") or ""), disabled = pending == 0,
      func = function() ns.Prompt.ReviewPending() end },
    { text = "Ledger", func = function() ns.UI.Open("ledger") end },
    { text = "People", func = function() ns.UI.Open("people") end },
    { text = "Options", func = function() ns.UI.ToggleOptions() end },
  })
end

function M.Build()
  if btn or not Minimap then return end
  btn = CreateFrame("Button", "LoanCraftMinimapButton", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
  icon:SetSize(17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  btn.icon = icon
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  -- coloured ring that pulses when something is due or overdue
  btn.glow = btn:CreateTexture(nil, "OVERLAY", nil, 7)
  btn.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  btn.glow:SetBlendMode("ADD")
  btn.glow:SetSize(58, 58)
  btn.glow:SetPoint("CENTER", icon, "CENTER", 0, 0)
  btn.glow:Hide()
  btn.pulse = btn.glow:CreateAnimationGroup()
  btn.pulse:SetLooping("BOUNCE")
  local a = btn.pulse:CreateAnimation("Alpha")
  a:SetFromAlpha(1)
  a:SetToAlpha(0.2)
  a:SetDuration(0.9)

  -- number badge
  btn.badge = CreateFrame("Frame", nil, btn)
  btn.badge:SetSize(14, 14)
  btn.badge:SetPoint("TOPRIGHT", 2, 0)
  btn.badge:SetFrameLevel(btn:GetFrameLevel() + 3)
  btn.badge.bg = btn.badge:CreateTexture(nil, "ARTWORK")
  btn.badge.bg:SetAllPoints()
  btn.badge.bg:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
  btn.badge.text = btn.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  btn.badge.text:SetPoint("CENTER", 0, 0)
  btn.badge:Hide()

  btn:SetScript("OnClick", function(self, button)
    GameTooltip:Hide()
    if button == "RightButton" then menu(self)
    elseif IsShiftKeyDown() then ns.UI.OpenNewLoan()
    elseif #ns.Prompt.queue == 0 and #ns.PendingTransfers() > 0 then ns.Prompt.ReviewPending(); ns.UI.Open()
    else ns.UI.Toggle() end
  end)
  btn:SetScript("OnEnter", function(self) showTooltip(self) end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      px, py = px / scale, py / scale
      ns.db.minimap.angle = math.deg(math.atan2(py - my, px - mx))
      place()
    end)
  end)
  btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  place()
end

function M.Update()
  -- ponytail: always shown, it's the only way in (no slash commands)
  if not btn then return end
  btn:Show()
  local alerts, top = ns.Alerts()
  if top > 0 then
    local c = LEVEL_COLOR[top]
    btn.glow:SetVertexColor(c[1], c[2], c[3])
    btn.glow:Show()
    if top >= 2 then
      if not btn.pulse:IsPlaying() then btn.pulse:Play() end
    else
      btn.pulse:Stop()
      btn.glow:SetAlpha(0.8)
    end
    btn.badge.bg:SetVertexColor(c[1] * 0.8, c[2] * 0.8, c[3] * 0.8)
    btn.badge.text:SetText(#alerts > 9 and "9+" or tostring(#alerts))
    btn.badge:Show()
  else
    btn.pulse:Stop()
    btn.glow:Hide()
    btn.badge:Hide()
  end
end

---------------------------------------------------------------------------
-- Data broker (Titan Panel, ElvUI, Bazooka... if one is installed)
---------------------------------------------------------------------------
local broker
local function setupBroker()
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  if not LDB then return end
  broker = LDB:NewDataObject("LoanCraft", {
    type = "data source",
    text = "LoanCraft",
    icon = "Interface\\Icons\\INV_Misc_Coin_02",
    OnClick = function(self, button)
      if button == "RightButton" then menu(self) else ns.UI.Toggle() end
    end,
    OnTooltipShow = function(tt) showTooltip(nil, tt) end,
  })
end

local function updateBroker()
  if not broker then return end
  local owedToMe, iOwe = ns.Totals()
  local _, top = ns.Alerts()
  local mark = top == 3 and "|cffff3030!|r " or top == 2 and "|cffff9900!|r " or ""
  broker.text = ("%s|cff40ff40+%s|r |cffff6060-%s|r"):format(mark, ns.Money(owedToMe), ns.Money(iOwe))
end

---------------------------------------------------------------------------
-- "Owes you 50g" on player tooltips
---------------------------------------------------------------------------
local function onUnitTooltip(tt)
  if not ns.db or not ns.db.settings.unitTooltips or InCombatLockdown() then return end
  local _, unit = tt:GetUnit()
  if not unit or ns.Secret(unit) then return end
  local name = ns.UnitFull(unit)
  if not name or ns.Same(name, ns.Me()) then return end
  local me = ns.Me()
  local owesMe, iOwe = ns.Owed(me, name), ns.Owed(name, me)
  if owesMe > 0 then
    local soon = ns.OpenLoans(me, name)[1]
    tt:AddLine(("LoanCraft: owes you %s (%s)"):format(ns.Money(owesMe), soon and ns.Plain(ns.DueText(soon)) or ""), 0.3, 1, 0.3)
  end
  if iOwe > 0 then
    local soon = ns.OpenLoans(name, me)[1]
    tt:AddLine(("LoanCraft: you owe them %s (%s)"):format(ns.Money(iOwe), soon and ns.Plain(ns.DueText(soon)) or ""), 1, 0.45, 0.45)
  end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
    if tt == GameTooltip then pcall(onUnitTooltip, tt) end
  end)
elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
  GameTooltip:HookScript("OnTooltipSetUnit", function(tt) pcall(onUnitTooltip, tt) end)
end

ns.OnLogin(function()
  M.Build()
  setupBroker()
  M.Update()
  updateBroker()
end)
ns.OnChange(function()
  M.Update()
  updateBroker()
end)
