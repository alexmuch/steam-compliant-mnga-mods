-- Pregame ready check UI (.claude/docs/ready-check.md), created and destroyed
-- by the mngareadycheck Shine extension; it only exists while a check runs.
--
--   * Centre READY button for eligible players who are not ready yet (only the
--     two commanders during the commander phase). It takes the mouse cursor
--     (CS-style accept prompt) with a stable Shine mouse owner and gives it
--     back as soon as the button hides. When another cursor is already visible
--     (commander, overhead spectator) it uses that one without claiming.
--   * "SPECTATE" button to the right of READY, for field players (Teams/Ready
--     Room, not commanders) who would rather spectate: the cursor stops them
--     walking to the spectator entrance. Shown with the READY button when the
--     server says CanSpectate.
--   * Middle-right countdown panel, shown to everyone while a check runs.
--
-- Layers (2026-10-08): the READY and SPECTATE buttons draw above Shine SGUI
-- windows (poker, match3, chatbox, help) so they stay visible, and drop to
-- kGUILayerPlayerHUDForeground4 while the scoreboard is open so the
-- scoreboard covers them. Clicks are taken by the plugin's wrapper around
-- MouseTracker_SendKeyEvent (HandleKey), which runs before SGUI's MouseTracker
-- listener, so a click on the button never reaches a window underneath it. The panel stays on Foreground4.
-- The READY button pulses (fill + breathing halo) and has two comet trails
-- running round its border; it animates every frame only while shown.
-- Shared mouse rules: .codex/docs/shared-mouse-ownership-contract.md

class 'GUIMNGAReadyCheck' (GUIScript)

local kReadyTexture = PrecacheAsset("ui/mnga_administration/gameready.dds")
local kMouseOwner = "MNGAReadyCheckButton"
local kUpdateInterval = 0.1
local kRequestHoldTime = 2

-- Mirrors Plugin.Phase in shine/extensions/mngareadycheck/shared.lua.
local kPhaseIdle, kPhaseCommanders, kPhasePool, kPhaseOpen, kPhaseVote, kPhaseWaiting = 0, 1, 2, 3, 4, 5

local kButtonColor = Color(0.05, 0.35, 0.12, 0.9)
local kButtonBorderColor = Color(0.35, 1, 0.5, 0.95)
local kSpectateColor = Color(0.18, 0.18, 0.2, 0.9)
local kSpectateBorderColor = Color(0.7, 0.7, 0.75, 0.95)
local kPanelColor = Color(0, 0, 0, 0.6)
local kTitleColor = Color(0.4, 1, 0.55, 1)
local kTextColor = Color(1, 1, 1, 1)
local kReadyColor = Color(0.4, 1, 0.55, 1)
local kNotReadyColor = Color(1, 0.55, 0.3, 1)
local kTimeColor = Color(1, 0.85, 0.3, 1)

-- READY button animation.
local kClickSound = "sound/NS2.fev/common/button_click" -- precached by vanilla InterfaceSounds_Client
local kPulseRate = 0.9 -- Hz, fill/halo breathing
local kButtonPulseColor = Color(0.1, 0.55, 0.2, 0.95)
local kGlowColor = Color(0.35, 1, 0.5, 1)
local kGlowAlpha = { 0.22, 0.12, 0.06 } -- inner to outer
local kGlowPad = 5 -- GUIScale'd px per halo step at full pulse
local kCometCount = 2
local kCometPeriod = 2.6 -- seconds per lap
-- Pieces of one comet as fractions of the perimeter, tail (behind) to head.
local kCometPieces = {
    { offset = 0.00, length = 0.05, color = Color(0.4, 1, 0.55, 0.35) },
    { offset = 0.05, length = 0.05, color = Color(0.6, 1, 0.7, 0.7) },
    { offset = 0.10, length = 0.04, color = Color(0.92, 1, 0.94, 1) },
}

local function Log(message, ...)
    Shared.Message("[readycheck] " .. string.format(message, ...))
end

local function CreateText(font, alignX, color)
    local item = GUIManager:CreateTextItem()
    item:SetFontName(font)
    item:SetScale(GetScaledVector())
    GUIMakeFontScale(item)
    item:SetTextAlignmentX(alignX)
    item:SetTextAlignmentY(GUIItem.Align_Center)
    item:SetColor(color)
    return item
end

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function IsScoreboardOpen()
    local scoreboard = ClientUI and ClientUI.GetScript and ClientUI.GetScript("GUIScoreboard")
    return scoreboard ~= nil and scoreboard.visible == true and not scoreboard.hiddenOverride
end

-- Shine's vote menu (not an SGUI window) takes the screen's attention while
-- open; clicks wait until it closes.
local function IsVoteMenuOpen()
    local menu = Shine.VoteMenu
    return menu ~= nil and menu.GetIsVisible ~= nil and menu:GetIsVisible() == true
end

local function GetItemLayer(item)
    return item and item.GetLayer and item:GetLayer() or 0
end

local function IsMouseOverWindow(window, minLayer)
    if not window:GetIsVisible() or window.IgnoreMouseFocus then return false end
    if GetItemLayer(window.Background) <= minLayer then return false end
    if window.AlwaysInMouseFocus or window:HasMouseEntered() then return true end
    return window.Background ~= nil and window:MouseIn(window.Background) == true
end

-- Name of a visible SGUI window drawn above minLayer and under the cursor, or
-- nil. The buttons normally sit above every SGUI window, so this only catches
-- windows with an OverrideLayer above them.
local function GetSGUIWindowUnderMouse(minLayer)
    local SGUI = Shine and Shine.GUI
    local windows = SGUI and SGUI.Windows
    if not windows then return nil end
    for i = SGUI.NumWindows or #windows, 1, -1 do
        local window = windows[i]
        if window then
            local ok, over = pcall(IsMouseOverWindow, window, minLayer)
            if ok and over then
                return window.Class or window.ClassName or tostring(window)
            end
        end
    end
    return nil
end

-- Above every SGUI window (BaseLayer + window index) and below the main menu.
local function GetTopLayer()
    local SGUI = Shine and Shine.GUI
    local base = SGUI and tonumber(SGUI.BaseLayer) or 501
    local mainMenu = GetLayerConstant and GetLayerConstant("MainMenu", 1000) or 1000
    return math.max(kGUILayerPlayerHUDForeground4, math.min(base + 250, mainMenu - 10))
end

local function IsMainMenuOpen()
    return MainMenu_GetIsOpened ~= nil and MainMenu_GetIsOpened() == true
end

-- Returns a short reason when a click on the button must go to something
-- drawn above it, or nil when the click is the button's. Called only on a
-- click inside the button. SGUI windows (poker, match3, chat) are below the
-- button and do not block it; the scoreboard does (it covers the screen).
local function GetClickBlocker(buttonLayer)
    if IsMainMenuOpen() then return "main_menu" end
    if IsScoreboardOpen() then return "scoreboard" end
    if IsVoteMenuOpen() then return "vote_menu" end
    local window = GetSGUIWindowUnderMouse(buttonLayer)
    if window then return "sgui_window:" .. tostring(window) end
    return nil
end

function GUIMNGAReadyCheck:Initialize()
    self.updateInterval = kUpdateInterval
    self.state = { Phase = kPhaseIdle, TimeLeft = 0, ReceivedAt = 0 }
    self.ownsMouse = false
    self.buttonVisible = false
    self.spectateVisible = false
    self.requestedAt = nil
    self.textCache = {}
    self.topLayer = GetTopLayer()
    self.layer = nil

    -- Centre READY button, ~18% of the screen height below centre so it clears
    -- the Ready Room welcome text and Shine's lower-centre notices. The root is
    -- an invisible container; children draw in order: glow halo, border,
    -- button, then the comet trail running along the border.
    local buttonSize = Vector(GUIScale(440), GUIScale(110), 0)
    local border = GUIScale(4)
    local outerSize = buttonSize + Vector(border * 2, border * 2, 0)
    self.buttonOuterSize = outerSize
    self.borderWidth = border
    self.buttonRoot = GUIManager:CreateGraphicItem()
    self.buttonRoot:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.buttonRoot:SetSize(outerSize)
    self.buttonRoot:SetPosition(Vector(-outerSize.x / 2, Client.GetScreenHeight() * 0.18 - outerSize.y / 2, 0))
    self.buttonRoot:SetColor(Color(0, 0, 0, 0))
    self.buttonRoot:SetIsVisible(false)

    -- Breathing halo: stacked translucent rectangles, widest and faintest first.
    self.glow = {}
    for i = #kGlowAlpha, 1, -1 do
        local item = GUIManager:CreateGraphicItem()
        item:SetColor(Color(kGlowColor.r, kGlowColor.g, kGlowColor.b, 0))
        self.buttonRoot:AddChild(item)
        self.glow[i] = item
    end

    self.buttonBorder = GUIManager:CreateGraphicItem()
    self.buttonBorder:SetSize(outerSize)
    self.buttonBorder:SetColor(kButtonBorderColor)
    self.buttonRoot:AddChild(self.buttonBorder)

    self.button = GUIManager:CreateGraphicItem()
    self.button:SetSize(buttonSize)
    self.button:SetPosition(Vector(border, border, 0))
    self.button:SetColor(kButtonColor)
    self.buttonBorder:AddChild(self.button)

    -- Comet trail: kCometCount comets, each kCometPieces pieces (tail first),
    -- each piece one item per border edge so it can bend round corners.
    self.cometPieces = {}
    for c = 1, kCometCount do
        for p = 1, #kCometPieces do
            local def = kCometPieces[p]
            local edges = {}
            for e = 1, 4 do
                local item = GUIManager:CreateGraphicItem()
                item:SetColor(def.color)
                item:SetIsVisible(false)
                self.buttonRoot:AddChild(item)
                edges[e] = item
            end
            self.cometPieces[#self.cometPieces + 1] = { comet = c, offset = def.offset, length = def.length, edges = edges }
        end
    end

    local iconSize = GUIScale(80)
    self.buttonIcon = GUIManager:CreateGraphicItem()
    self.buttonIcon:SetTexture(kReadyTexture)
    self.buttonIcon:SetSize(Vector(iconSize, iconSize, 0))
    self.buttonIcon:SetAnchor(GUIItem.Left, GUIItem.Center)
    self.buttonIcon:SetPosition(Vector(GUIScale(16), -iconSize / 2, 0))
    self.button:AddChild(self.buttonIcon)

    self.buttonTitle = CreateText(Fonts.kAgencyFB_Large, GUIItem.Align_Center, kTextColor)
    self.buttonTitle:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.buttonTitle:SetPosition(Vector(GUIScale(40), -GUIScale(16), 0))
    self.buttonTitle:SetText("READY UP")
    self.button:AddChild(self.buttonTitle)

    self.buttonHint = CreateText(Fonts.kAgencyFB_Small, GUIItem.Align_Center, kTextColor)
    self.buttonHint:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.buttonHint:SetPosition(Vector(GUIScale(40), GUIScale(26), 0))
    self.buttonHint:SetText("click here, or type !ready in chat")
    self.button:AddChild(self.buttonHint)

    -- SPECTATE button, right of the READY button with a small gap.
    local spectateSize = Vector(GUIScale(250), buttonSize.y, 0)
    local gap = GUIScale(20)
    border = GUIScale(3)
    self.spectateBorder = GUIManager:CreateGraphicItem()
    self.spectateBorder:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.spectateBorder:SetSize(spectateSize + Vector(border * 2, border * 2, 0))
    self.spectateBorder:SetPosition(Vector(outerSize.x / 2 + gap,
        Client.GetScreenHeight() * 0.18 - spectateSize.y / 2 - border, 0))
    self.spectateBorder:SetColor(kSpectateBorderColor)
    self.spectateBorder:SetIsVisible(false)

    self.spectateButton = GUIManager:CreateGraphicItem()
    self.spectateButton:SetSize(spectateSize)
    self.spectateButton:SetPosition(Vector(border, border, 0))
    self.spectateButton:SetColor(kSpectateColor)
    self.spectateBorder:AddChild(self.spectateButton)

    self.spectateTitle = CreateText(Fonts.kAgencyFB_Medium, GUIItem.Align_Center, kTextColor)
    self.spectateTitle:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.spectateTitle:SetPosition(Vector(0, -GUIScale(14), 0))
    self.spectateTitle:SetText("GO TO SPECTATOR")
    self.spectateButton:AddChild(self.spectateTitle)

    self.spectateHint = CreateText(Fonts.kAgencyFB_Small, GUIItem.Align_Center, kTextColor)
    self.spectateHint:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.spectateHint:SetPosition(Vector(0, GUIScale(22), 0))
    self.spectateHint:SetText("leave the player pool")
    self.spectateButton:AddChild(self.spectateHint)

    -- Middle-right countdown panel: title, stage, timer, x / y ready.
    -- Kept 20% of screen width in from the right edge so the voice chat
    -- bars and the spectator health panels do not cover it.
    local panelSize = Vector(GUIScale(240), GUIScale(150), 0)
    self.panel = GUIManager:CreateGraphicItem()
    self.panel:SetAnchor(GUIItem.Right, GUIItem.Center)
    self.panel:SetSize(panelSize)
    self.panel:SetPosition(Vector(-panelSize.x - Client.GetScreenWidth() * 0.2, -panelSize.y / 2, 0))
    self.panel:SetColor(kPanelColor)
    self.panel:SetLayer(kGUILayerPlayerHUDForeground4)
    self.panel:SetIsVisible(false)

    local textX = panelSize.x - GUIScale(12)
    local function AddPanelLine(font, y, color)
        local item = CreateText(font, GUIItem.Align_Max, color)
        item:SetAnchor(GUIItem.Left, GUIItem.Top)
        item:SetPosition(Vector(textX, GUIScale(y), 0))
        self.panel:AddChild(item)
        return item
    end
    self.panelTitle = AddPanelLine(Fonts.kAgencyFB_Medium, 20, kTitleColor)
    self.panelTitle:SetText("READY CHECK")
    self.panelPhase = AddPanelLine(Fonts.kAgencyFB_Small, 54, kTextColor)
    self.panelTime = AddPanelLine(Fonts.kAgencyFB_Large, 88, kTimeColor)
    self.panelCount = AddPanelLine(Fonts.kAgencyFB_Medium, 124, kTextColor)

    self:ApplyLayer(false)
    Log("GUI created")
end

function GUIMNGAReadyCheck:Uninitialize()
    self:SetMouseOwned(false, "uninitialize")
    GUI.DestroyItem(self.buttonRoot)
    GUI.DestroyItem(self.spectateBorder)
    GUI.DestroyItem(self.panel)
    self.buttonRoot = nil
    self.buttonBorder = nil
    self.spectateBorder = nil
    self.panel = nil
    Log("GUI destroyed")
end

function GUIMNGAReadyCheck:SetMouseOwned(owned, reason)
    if owned == self.ownsMouse then return end
    local SGUI = Shine and Shine.GUI
    if not SGUI or not SGUI.EnableMouse then return end
    SGUI:EnableMouse(owned, kMouseOwner)
    self.ownsMouse = owned
    Log("mouse %s owner=%s reason=%s MouseObjects=%s", owned and "acquired" or "released",
        kMouseOwner, tostring(reason), tostring(SGUI.MouseObjects))
end

function GUIMNGAReadyCheck:SetState(state)
    self.state = state
    if state.IsReady or not state.Eligible then
        self.requestedAt = nil
    end
    if not self.failed then
        local ok, err = pcall(self.Refresh, self)
        if not ok then
            self.failed = true
            Log("ERROR refresh failed on state, hiding ready check UI: %s", tostring(err))
            pcall(self.SetMouseOwned, self, false, "refresh_error")
        end
    end
end

function GUIMNGAReadyCheck:SetText(item, key, text)
    if self.textCache[key] ~= text then
        self.textCache[key] = text
        item:SetText(text)
    end
end

function GUIMNGAReadyCheck:GetTimeLeft()
    local state = self.state
    -- TimerRate > 1: the server drains Pool/Open faster while the count is green.
    local elapsed = (Shared.GetTime() - (state.ReceivedAt or 0)) * (state.TimerRate or 1)
    return math.max(0, (state.TimeLeft or 0) - elapsed)
end

function GUIMNGAReadyCheck:UpdatePanel()
    local state = self.state
    local phaseText, timeText = "", ""
    if state.Phase == kPhaseCommanders then
        phaseText = "Commanders"
        timeText = (state.TimeLeft or 0) > 0 and FormatTime(math.ceil(self:GetTimeLeft())) or "--:--"
    elseif state.Phase == kPhasePool then
        phaseText = "Players"
        timeText = FormatTime(math.ceil(self:GetTimeLeft()))
    elseif state.Phase == kPhaseOpen then
        phaseText = "Open to queue"
        timeText = FormatTime(math.ceil(self:GetTimeLeft()))
    elseif state.Phase == kPhaseVote then
        phaseText = "Start vote"
        timeText = state.VotePending and "..." or FormatTime(math.ceil(self:GetTimeLeft()))
    elseif state.Phase == kPhaseWaiting then
        phaseText = "Waiting for players"
        timeText = "--:--"
    end
    self:SetText(self.panelPhase, "phase", phaseText)
    self:SetText(self.panelTime, "time", timeText)

    -- "x+y / n ready": x ready slot holders, y ready queued spectators (who
    -- can fill unready slots once Pool ends), so x+y >= n means the game can
    -- start as soon as the swaps run. Commander phase: commanders' counts.
    local ready, needed = state.ReadyCount or 0, state.Needed or 0
    local queueReady = state.QueueReady or 0
    local countText
    if queueReady > 0 then
        countText = string.format("%d+%d / %d ready", ready, queueReady, needed)
    else
        countText = string.format("%d / %d ready", ready, needed)
    end
    self:SetText(self.panelCount, "count", countText)
    local enough = (state.NotReady or 0) == 0 or ready + queueReady >= needed
    self.panelCount:SetColor(enough and kReadyColor or kNotReadyColor)
end

-- Top layer normally; Foreground4 (below the scoreboard) while it is open.
function GUIMNGAReadyCheck:ApplyLayer(scoreboardOpen)
    local layer = scoreboardOpen and kGUILayerPlayerHUDForeground4 or self.topLayer
    if layer == self.layer then return end
    self.layer = layer
    self.buttonRoot:SetLayer(layer)
    self.spectateBorder:SetLayer(layer)
end

-- Positions one comet piece covering perimeter distance [s, s + len) on the
-- border's four edges (clockwise from the top-left corner). Pieces are short,
-- so each edge needs at most one span; a wrap past the corner is tried by
-- shifting the span back one perimeter.
-- Scratch values reused by the per-frame animation (GUIItem setters copy).
local tmpPos = Vector(0, 0, 0)
local tmpSize = Vector(0, 0, 0)
local tmpColor = Color(0, 0, 0, 0)
local kEdgeStarts, kEdgeLengths = {}, {}

local function SetRect(item, x, y, w, h)
    tmpPos.x, tmpPos.y = x, y
    tmpSize.x, tmpSize.y = w, h
    item:SetPosition(tmpPos)
    item:SetSize(tmpSize)
end

local function SetRGBA(item, r, g, b, a)
    tmpColor.r, tmpColor.g, tmpColor.b, tmpColor.a = r, g, b, a
    item:SetColor(tmpColor)
end

local function PlaceCometPiece(edges, s, len, w, h, b)
    local p = 2 * (w + h)
    local starts, lengths = kEdgeStarts, kEdgeLengths
    starts[1], starts[2], starts[3], starts[4] = 0, w, w + h, 2 * w + h
    lengths[1], lengths[2], lengths[3], lengths[4] = w, h, w, h
    for e = 1, 4 do
        local item = edges[e]
        local d0, d1 = starts[e], starts[e] + lengths[e]
        local a, z = math.max(s, d0), math.min(s + len, d1)
        if z <= a then
            a, z = math.max(s - p, d0), math.min(s + len - p, d1)
        end
        if z > a then
            local from, to = a - d0, z - d0
            if e == 1 then
                SetRect(item, from, 0, to - from, b)
            elseif e == 2 then
                SetRect(item, w - b, from, b, to - from)
            elseif e == 3 then
                SetRect(item, w - to, h - b, to - from, b)
            else
                SetRect(item, 0, h - to, b, to - from)
            end
            item:SetIsVisible(true)
        else
            item:SetIsVisible(false)
        end
    end
end

-- Per-frame READY button animation, only while the button shows: the fill and
-- border brighten and dim, the halo breathes outwards, and two comets run
-- clockwise round the border.
function GUIMNGAReadyCheck:Animate()
    local now = Shared.GetTime()
    local pulse = 0.5 + 0.5 * math.sin(now * kPulseRate * 2 * math.pi)

    local c0, c1 = kButtonColor, kButtonPulseColor
    SetRGBA(self.button, c0.r + (c1.r - c0.r) * pulse, c0.g + (c1.g - c0.g) * pulse,
        c0.b + (c1.b - c0.b) * pulse, c0.a + (c1.a - c0.a) * pulse)
    local bc = kButtonBorderColor
    SetRGBA(self.buttonBorder, bc.r, bc.g, bc.b, 0.55 + 0.4 * pulse)

    local step = GUIScale(kGlowPad) * (0.35 + 0.65 * pulse)
    local size = self.buttonOuterSize
    for i = 1, #self.glow do
        local pad = step * i
        local item = self.glow[i]
        SetRect(item, -pad, -pad, size.x + pad * 2, size.y + pad * 2)
        SetRGBA(item, kGlowColor.r, kGlowColor.g, kGlowColor.b, kGlowAlpha[i] * (0.4 + 0.6 * pulse))
    end

    local w, h, b = size.x, size.y, self.borderWidth
    local perimeter = 2 * (w + h)
    local lap = (now / kCometPeriod) % 1
    for i = 1, #self.cometPieces do
        local piece = self.cometPieces[i]
        local s = ((lap + (piece.comet - 1) / kCometCount + piece.offset) % 1) * perimeter
        PlaceCometPiece(piece.edges, s, piece.length * perimeter, w, h, b)
    end
end

function GUIMNGAReadyCheck:Refresh()
    local state = self.state
    local active = state.Phase ~= kPhaseIdle
    local mainMenuOpen = IsMainMenuOpen()
    self.panel:SetIsVisible(active and not mainMenuOpen)
    if active then
        self:UpdatePanel()
    end

    local wantsButton = active and state.Eligible and not state.IsReady
    if wantsButton and self.requestedAt and Shared.GetTime() - self.requestedAt < kRequestHoldTime then
        wantsButton = false
    end

    local showButton = wantsButton and not mainMenuOpen
    if showButton ~= self.buttonVisible then
        self.buttonVisible = showButton
        self.buttonRoot:SetIsVisible(showButton)
        -- Animate every frame while the button shows; idle rate otherwise.
        self.updateInterval = showButton and 0 or kUpdateInterval
        Log("button %s phase=%s eligible=%s ready=%s", showButton and "shown" or "hidden",
            tostring(state.Phase), tostring(state.Eligible), tostring(state.IsReady))
    end

    local showSpectate = showButton and state.CanSpectate == true
    if showSpectate ~= self.spectateVisible then
        self.spectateVisible = showSpectate
        self.spectateBorder:SetIsVisible(showSpectate)
        Log("spectate button %s canSpectate=%s", showSpectate and "shown" or "hidden", tostring(state.CanSpectate))
    end

    if showButton then
        self:ApplyLayer(IsScoreboardOpen())
        self:Animate()
    end

    -- Claim the cursor only while the button shows and no other cursor exists
    -- (contract rule 4: never claim on top of an external cursor).
    if showButton then
        if not self.ownsMouse and not MouseTracker_GetIsVisible() then
            self:SetMouseOwned(true, "button_shown")
        end
    elseif self.ownsMouse then
        self:SetMouseOwned(false, mainMenuOpen and "main_menu" or "button_hidden")
    end
end

function GUIMNGAReadyCheck:Update(deltaTime)
    PROFILE("GUIMNGAReadyCheck:Update")
    -- Never let an error here break the GUIManager update loop for the rest of
    -- the HUD: log once, hide everything and give the mouse back.
    if self.failed then return end
    local ok, err = pcall(self.Refresh, self)
    if not ok then
        self.failed = true
        Log("ERROR refresh failed, hiding ready check UI: %s", tostring(err))
        pcall(self.SetMouseOwned, self, false, "refresh_error")
        if self.buttonRoot then self.buttonRoot:SetIsVisible(false) end
        if self.spectateBorder then self.spectateBorder:SetIsVisible(false) end
        if self.panel then self.panel:SetIsVisible(false) end
    end
end

-- Called from the plugin's MouseTracker_SendKeyEvent wrapper, before SGUI's
-- MouseTracker listener, so a click on a button above a poker/match3/chat
-- window is the button's and the window never sees it. Returns true when the
-- key is consumed, nil otherwise.
function GUIMNGAReadyCheck:HandleKey(key, down)
    if self.failed or key ~= InputKey.MouseButton0 then return nil end
    if not down then
        -- Swallow the release of a click the button took, so an SGUI button
        -- underneath does not fire on mouse-up.
        if self.swallowRelease then
            self.swallowRelease = false
            return true
        end
        return nil
    end
    if not self.buttonVisible or not MouseTracker_GetIsVisible() then return nil end
    local x, y = Client.GetCursorPosScreen()
    local onReady = GUIItemContainsPoint(self.buttonBorder, x, y)
    local onSpectate = not onReady and self.spectateVisible and GUIItemContainsPoint(self.spectateBorder, x, y)
    if not onReady and not onSpectate then return nil end
    local blocker = GetClickBlocker(self.layer or self.topLayer)
    if blocker then
        Log("button click ignored: %s is open", blocker)
        return nil
    end

    -- Both buttons hide until the server answers (or kRequestHoldTime passes).
    self.requestedAt = Shared.GetTime()
    self.swallowRelease = true
    StartSoundEffect(kClickSound)
    local plugin = Shine.Plugins and Shine.Plugins.mngareadycheck
    if plugin and plugin.Enabled then
        if onReady and plugin.RequestReady then
            plugin:RequestReady("button")
        elseif onSpectate and plugin.RequestSpectate then
            plugin:RequestSpectate("button")
        end
    end
    Log("%s button clicked", onReady and "ready" or "spectate")
    pcall(self.Refresh, self)
    return true
end

function GUIMNGAReadyCheck:OnResolutionChanged()
    -- Rebuild at the new scale, keeping the current state and mouse claim
    -- balanced (the claim is released by Uninitialize and re-taken by Refresh).
    local state = self.state
    self:Uninitialize()
    self:Initialize()
    self:SetState(state)
end
