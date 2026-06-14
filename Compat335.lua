-- Compat335.lua: Compatibility shims for WoW 3.3.5a (Interface 30300)
-- Loaded FIRST in the TOC to provide missing APIs before any other file runs.
--
-- SAFETY: This file must NEVER modify globals like CreateFrame or touch
-- widget metatables. Only safe global table/function shims go here.

------------------------------------------------------------
-- Fix cursorOffset crash in Blizzard's ScrollingEdit_OnUpdate
-- UIPanelTemplates.lua:365 does arithmetic on self.cursorOffset when nil,
-- causing C stack overflow that locks keyboard/mouse input.
-- Must run BEFORE any addon errors can trigger the error frame.
------------------------------------------------------------
if ScrollingEdit_OnUpdate then
    local origScrollUpdate = ScrollingEdit_OnUpdate
    ScrollingEdit_OnUpdate = function(self, elapsed, ...)
        if not self.cursorOffset then
            self.cursorOffset = 0
        end
        return origScrollUpdate(self, elapsed, ...)
    end
end
if ScrollingEdit_OnTextChanged then
    local origScrollTextChanged = ScrollingEdit_OnTextChanged
    ScrollingEdit_OnTextChanged = function(self, ...)
        if not self.cursorOffset then
            self.cursorOffset = 0
        end
        return origScrollTextChanged(self, ...)
    end
end

------------------------------------------------------------
-- C_Timer shim (After / NewTimer / NewTicker via OnUpdate)
------------------------------------------------------------
if not C_Timer then
    C_Timer = {}

    local activeTimers = {}
    local timerFrame = CreateFrame("Frame")
    local nextId = 1

    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        local now = GetTime()
        local toRemove = {}
        for id, timer in pairs(activeTimers) do
            if now >= timer.fireAt then
                timer.func()
                if timer.ticker then
                    timer.fireAt = now + timer.interval
                    if timer.cancelled then
                        toRemove[#toRemove + 1] = id
                    end
                else
                    toRemove[#toRemove + 1] = id
                end
            end
        end
        for _, id in ipairs(toRemove) do
            activeTimers[id] = nil
        end
        if not next(activeTimers) then
            self:Hide()
        end
    end)
    timerFrame:Hide()

    function C_Timer.After(delay, func)
        local id = nextId
        nextId = nextId + 1
        activeTimers[id] = {
            fireAt = GetTime() + delay,
            func = func,
            ticker = false,
        }
        timerFrame:Show()
    end

    function C_Timer.NewTimer(delay, func)
        local id = nextId
        nextId = nextId + 1
        local handle = { cancelled = false }
        function handle:Cancel()
            self.cancelled = true
            activeTimers[id] = nil
        end
        activeTimers[id] = {
            fireAt = GetTime() + delay,
            func = func,
            ticker = false,
        }
        timerFrame:Show()
        return handle
    end

    function C_Timer.NewTicker(interval, func, iterations)
        local id = nextId
        nextId = nextId + 1
        local count = 0
        local handle = { cancelled = false }
        function handle:Cancel()
            self.cancelled = true
            activeTimers[id] = nil
        end
        local function wrappedFunc()
            if handle.cancelled then return end
            count = count + 1
            func(handle)
            if iterations and count >= iterations then
                handle:Cancel()
            end
        end
        activeTimers[id] = {
            fireAt = GetTime() + interval,
            func = wrappedFunc,
            ticker = true,
            interval = interval,
            cancelled = false,
        }
        local entry = activeTimers[id]
        function handle:Cancel()
            self.cancelled = true
            entry.cancelled = true
            activeTimers[id] = nil
        end
        timerFrame:Show()
        return handle
    end
end

------------------------------------------------------------
-- Mixin shim
------------------------------------------------------------
if not Mixin then
    function Mixin(object, ...)
        for i = 1, select("#", ...) do
            local mixin = select(i, ...)
            if mixin then
                for k, v in pairs(mixin) do
                    object[k] = v
                end
            end
        end
        return object
    end
end

if not CreateFromMixins then
    function CreateFromMixins(...)
        return Mixin({}, ...)
    end
end

------------------------------------------------------------
-- SmoothStatusBarMixin shim
------------------------------------------------------------
if not SmoothStatusBarMixin then
    SmoothStatusBarMixin = {}
    function SmoothStatusBarMixin:ResetSmoothedValue(value)
        self.targetValue = value or 0
        self:SetValue(self.targetValue)
    end
    function SmoothStatusBarMixin:SetSmoothedValue(value)
        self.targetValue = value or 0
        -- 3.3.5a: no smooth interpolation, just set immediately
        self:SetValue(self.targetValue)
    end
    function SmoothStatusBarMixin:SetMinMaxSmoothedValue(min, max)
        self:SetMinMaxValues(min, max)
        local currValue = self:GetValue()
        if currValue > max then
            self:SetValue(max)
            self.targetValue = max
        end
    end
end

------------------------------------------------------------
-- UnitInPartyIsAI shim
------------------------------------------------------------
if not UnitInPartyIsAI then
    UnitInPartyIsAI = function() return false end
end

------------------------------------------------------------
-- PixelUtil shim
------------------------------------------------------------
if not PixelUtil then
    PixelUtil = {}
    function PixelUtil.SetPoint(frame, point, relativeTo, relativePoint, x, y)
        frame:SetPoint(point, relativeTo, relativePoint, x or 0, y or 0)
    end
    function PixelUtil.SetWidth(frame, width)
        frame:SetWidth(width)
    end
    function PixelUtil.SetHeight(frame, height)
        frame:SetHeight(height)
    end
    function PixelUtil.SetSize(frame, width, height)
        frame:SetSize(width, height)
    end
    function PixelUtil.GetNearestPixelSize(uiUnitSize, layoutScale, minPixels)
        if layoutScale and layoutScale > 0 then
            local pixels = uiUnitSize * layoutScale
            local physicalPixels = (minPixels and pixels < minPixels) and minPixels or pixels
            return physicalPixels / layoutScale
        end
        return uiUnitSize
    end
    function PixelUtil.GetPixelToUIUnitFactor(layoutScale)
        if layoutScale and layoutScale > 0 then
            return 1.0 / layoutScale
        end
        return 1.0
    end
end

------------------------------------------------------------
-- Enum shim (partial)
------------------------------------------------------------
if not Enum then
    Enum = {}
end
if not Enum.SummonStatus then
    Enum.SummonStatus = {
        None = 0,
        Pending = 1,
        Accepted = 2,
        Declined = 3,
    }
end

------------------------------------------------------------
-- string.split shim
------------------------------------------------------------
if not string.split then
    string.split = function(sep, str, max)
        return strsplit(sep, str, max)
    end
end

------------------------------------------------------------
-- CreateTexturePool / CreateFramePool shims
------------------------------------------------------------
if not CreateTexturePool then
    function CreateTexturePool(parent, layer, subLayer, textureTemplate, resetterFunc)
        local pool = {
            parent = parent,
            layer = layer,
            subLayer = subLayer,
            textureTemplate = textureTemplate,
            resetterFunc = resetterFunc,
            active = {},
            inactive = {},
        }
        function pool:Acquire()
            local tex = table.remove(self.inactive)
            local new = tex == nil
            if new then
                tex = self.parent:CreateTexture(nil, self.layer)
                if self.subLayer then
                    tex:SetDrawLayer(self.layer, self.subLayer)
                end
            end
            tex:Show()
            self.active[tex] = true
            return tex, new
        end
        function pool:Release(tex)
            if self.resetterFunc then
                self.resetterFunc(self, tex)
            else
                tex:Hide()
                tex:ClearAllPoints()
            end
            self.active[tex] = nil
            table.insert(self.inactive, tex)
        end
        function pool:ReleaseAll()
            for tex in pairs(self.active) do
                if self.resetterFunc then
                    self.resetterFunc(self, tex)
                else
                    tex:Hide()
                    tex:ClearAllPoints()
                end
                table.insert(self.inactive, tex)
            end
            wipe(self.active)
        end
        function pool:GetNumActive()
            local count = 0
            for _ in pairs(self.active) do count = count + 1 end
            return count
        end
        function pool:EnumerateActive()
            return pairs(self.active)
        end
        return pool
    end
end

if not CreateFramePool then
    function CreateFramePool(frameType, parent, template, resetterFunc)
        local pool = {
            frameType = frameType,
            parent = parent,
            template = template,
            resetterFunc = resetterFunc,
            active = {},
            inactive = {},
        }
        function pool:Acquire()
            local f = table.remove(self.inactive)
            local new = f == nil
            if new then
                f = CreateFrame(self.frameType, nil, self.parent)
            end
            f:Show()
            self.active[f] = true
            return f, new
        end
        function pool:Release(frame)
            if self.resetterFunc then
                self.resetterFunc(self, frame)
            else
                frame:Hide()
                frame:ClearAllPoints()
            end
            self.active[frame] = nil
            table.insert(self.inactive, frame)
        end
        function pool:ReleaseAll()
            for frame in pairs(self.active) do
                if self.resetterFunc then
                    self.resetterFunc(self, frame)
                else
                    frame:Hide()
                    frame:ClearAllPoints()
                end
                table.insert(self.inactive, frame)
            end
            wipe(self.active)
        end
        function pool:GetNumActive()
            local count = 0
            for _ in pairs(self.active) do count = count + 1 end
            return count
        end
        function pool:EnumerateActive()
            return pairs(self.active)
        end
        return pool
    end
end

------------------------------------------------------------
-- C_Item shim (partial)
------------------------------------------------------------
if not C_Item then
    C_Item = {}
end
if not C_Item.IsItemInRange then
    C_Item.IsItemInRange = function(itemID, unit)
        if _G.IsItemInRange then
            return _G.IsItemInRange(itemID, unit)
        end
        return nil
    end
end
if not C_Item.IsUsableItem then
    C_Item.IsUsableItem = function(itemID)
        if _G.IsUsableItem then
            return _G.IsUsableItem(itemID)
        end
        return true, false -- usable=true, noMana=false
    end
end

------------------------------------------------------------
-- C_TooltipInfo shim (stub)
------------------------------------------------------------
if not C_TooltipInfo then
    C_TooltipInfo = {}
    C_TooltipInfo.GetSpellByID = function() return nil end
end

------------------------------------------------------------
-- AuraUtil shim
------------------------------------------------------------
if not AuraUtil then
    AuraUtil = {}
    function AuraUtil.FindAura(predicate, unit, filter, ...)
        for i = 1, 40 do
            local name, rank, icon, count, debuffType, duration,
                  expirationTime, caster, isStealable, shouldConsolidate,
                  spellId = UnitAura(unit, i, filter)
            if not name then break end
            if predicate(name, rank, icon, count, debuffType, duration,
                         expirationTime, caster, isStealable, shouldConsolidate,
                         spellId, ...) then
                return name, rank, icon, count, debuffType, duration,
                       expirationTime, caster, isStealable, shouldConsolidate, spellId
            end
        end
        return nil
    end
    function AuraUtil.ForEachAura(unit, filter, maxCount, func)
        for i = 1, maxCount or 40 do
            local name, rank, icon, count, debuffType, duration,
                  expirationTime, caster, isStealable, shouldConsolidate,
                  spellId = UnitAura(unit, i, filter)
            if not name then break end
            if func(name, icon, count, debuffType, duration,
                    expirationTime, caster, isStealable, shouldConsolidate, spellId) then
                break
            end
        end
    end
    function AuraUtil.FindAuraByName(name, unit, filter)
        return AuraUtil.FindAura(
            function(auraName) return auraName == name end,
            unit, filter
        )
    end
end

------------------------------------------------------------
-- C_NamePlate shim
------------------------------------------------------------
if not C_NamePlate then
    C_NamePlate = {}
    function C_NamePlate.GetNamePlates()
        return {}
    end
end

------------------------------------------------------------
-- GetPhysicalScreenSize shim
------------------------------------------------------------
if not GetPhysicalScreenSize then
    GetPhysicalScreenSize = function()
        local res = ({GetScreenResolutions()})[GetCurrentResolution()]
        if res then
            local w, h = string.match(res, "(%d+)x(%d+)")
            if w and h then
                return tonumber(w), tonumber(h)
            end
        end
        return 1920, 1080
    end
end

------------------------------------------------------------
-- GetNumClasses / GetClassInfo shims (Cata+ API)
-- In 3.3.5a: 10 classes (no Monk/DH/Evoker), highest ID = 11 (Druid, 10 is skipped)
------------------------------------------------------------
if not GetNumClasses then
    function GetNumClasses()
        return 11 -- highest classID in WotLK (Druid)
    end
end

if not GetClassInfo then
    local classData = {
        [1]  = { "Warrior",      "WARRIOR" },
        [2]  = { "Paladin",      "PALADIN" },
        [3]  = { "Hunter",       "HUNTER" },
        [4]  = { "Rogue",        "ROGUE" },
        [5]  = { "Priest",       "PRIEST" },
        [6]  = { "Death Knight", "DEATHKNIGHT" },
        [7]  = { "Shaman",       "SHAMAN" },
        [8]  = { "Mage",         "MAGE" },
        [9]  = { "Warlock",      "WARLOCK" },
        [11] = { "Druid",        "DRUID" },
    }
    function GetClassInfo(classID)
        local info = classData[classID]
        if info then
            local localized = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[info[2]]
            return localized or info[1], info[2], classID
        end
        return nil, nil, nil
    end
end

------------------------------------------------------------
-- GetClassColor shim (returns r, g, b, colorStr)
------------------------------------------------------------
if not GetClassColor then
    function GetClassColor(classFile)
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if cc then
            local colorStr = format("ff%02x%02x%02x", cc.r*255, cc.g*255, cc.b*255)
            return cc.r, cc.g, cc.b, colorStr
        end
        return 0.7, 0.7, 0.7, "ffb2b2b2"
    end
end

------------------------------------------------------------
-- WrapTextInColorCode shim
------------------------------------------------------------
if not WrapTextInColorCode then
    function WrapTextInColorCode(text, colorHexStr)
        if colorHexStr and #colorHexStr >= 8 then
            return "|c" .. colorHexStr .. text .. "|r"
        end
        return text
    end
end

------------------------------------------------------------
-- SOUNDKIT shim (Legion+ constant table)
------------------------------------------------------------
if not SOUNDKIT then
    SOUNDKIT = {
        U_CHAT_SCROLL_BUTTON = 1115,
        IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
        IG_MAINMENU_OPTION_CHECKBOX_OFF = 857,
        IG_CHARACTER_INFO_TAB = 841,
        READY_CHECK = 8960,
        IG_MAINMENU_OPEN = 850,
        IG_MAINMENU_CLOSE = 851,
    }
end

------------------------------------------------------------
-- Clamp shim
------------------------------------------------------------
if not Clamp then
    function Clamp(value, minValue, maxValue)
        if value < minValue then return minValue end
        if value > maxValue then return maxValue end
        return value
    end
end

------------------------------------------------------------
-- DevTools_Dump shim
------------------------------------------------------------
if not DevTools_Dump then
    DevTools_Dump = function(value)
        if type(value) == "table" then
            print("<table>")
        else
            print(tostring(value))
        end
    end
end

------------------------------------------------------------
-- AnimateTexCoords shim (used by LibCustomGlow ButtonGlow)
------------------------------------------------------------
if not AnimateTexCoords then
    function AnimateTexCoords(texture, textureWidth, textureHeight, frameWidth, frameHeight, numFrames, elapsed, throttle)
        if not texture._acIndex then
            texture._acIndex = 0
            texture._acElapsed = 0
        end
        texture._acElapsed = texture._acElapsed + elapsed
        if texture._acElapsed < (throttle or 0.01) then return end
        texture._acElapsed = 0
        texture._acIndex = (texture._acIndex + 1) % numFrames
        local cols = math.floor(textureWidth / frameWidth)
        local row = math.floor(texture._acIndex / cols)
        local col = texture._acIndex % cols
        local l = col * frameWidth / textureWidth
        local r = l + frameWidth / textureWidth
        local t = row * frameHeight / textureHeight
        local b = t + frameHeight / textureHeight
        texture:SetTexCoord(l, r, t, b)
    end
end

------------------------------------------------------------
-- CreateObjectPool shim (Shadowlands+)
------------------------------------------------------------
if not CreateObjectPool then
    function CreateObjectPool(creationFunc, resetterFunc)
        local pool = {
            active = {},
            inactive = {},
            creationFunc = creationFunc,
            resetterFunc = resetterFunc,
        }
        function pool:Acquire()
            local obj = table.remove(self.inactive)
            if not obj then
                obj = self.creationFunc(self)
            end
            self.active[obj] = true
            return obj
        end
        function pool:Release(obj)
            if self.active[obj] then
                self.active[obj] = nil
                if self.resetterFunc then self.resetterFunc(self, obj) end
                table.insert(self.inactive, obj)
            end
        end
        function pool:IsActive(obj)
            return self.active[obj] ~= nil
        end
        function pool:ReleaseAll()
            for obj in pairs(self.active) do
                if self.resetterFunc then self.resetterFunc(self, obj) end
                table.insert(self.inactive, obj)
            end
            wipe(self.active)
        end
        function pool:GetNumActive()
            local c = 0
            for _ in pairs(self.active) do c = c + 1 end
            return c
        end
        function pool:EnumerateActive()
            return pairs(self.active)
        end
        return pool
    end
end

------------------------------------------------------------
-- CreateVector2D shim
------------------------------------------------------------
if not CreateVector2D then
    function CreateVector2D(x, y)
        return {
            x = x, y = y,
            GetXY = function(self) return self.x, self.y end,
        }
    end
end

------------------------------------------------------------
-- RegisterAddonMessagePrefix shim (Cata+ API, used by AceComm)
-- In 3.3.5a addon message prefixes don't need registration.
------------------------------------------------------------
if not RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix = function() return true end
end

------------------------------------------------------------
-- C_ChatInfo: intentionally NOT shimmed.
-- Cell's ChatThrottleLib v31 detects C_ChatInfo and takes
-- a modern code path that breaks 3.3.5a. Keeping C_ChatInfo
-- nil forces the 3.3.5a fallback path.
------------------------------------------------------------

------------------------------------------------------------
-- Widget method stubs (SetIgnoreParentAlpha, SetAtlas, etc.)
-- Each section wrapped in pcall — if metatable access fails
-- on this client, that section is silently skipped.
-- Cell will get Lua errors at those call sites but won't
-- crash the game or break other addons.
------------------------------------------------------------

------------------------------------------------------------
-- SAFE metatable patches: ONLY for widget types NOT used by
-- the secure frame system. Frame/Button/CheckButton/Slider/
-- EditBox metatables MUST NOT be modified — doing so taints
-- the secure environment and breaks keybindings in 3.3.5a.
------------------------------------------------------------

-- SetShown on FontString/Texture (they share a different metatable from Frame)
-- Textures and FontStrings are NOT secure frame types — safe to patch.
pcall(function()
    local f = CreateFrame("Frame")
    local t = f:CreateTexture()
    local mt = getmetatable(t)
    if mt and mt.__index and type(mt.__index) == "table" then
        if not mt.__index.SetShown then
            mt.__index.SetShown = function(self, shown)
                if shown then self:Show() else self:Hide() end
            end
        end
    end
    local fs = f:CreateFontString()
    local fmt = getmetatable(fs)
    if fmt and fmt.__index and type(fmt.__index) == "table" then
        if not fmt.__index.SetShown then
            fmt.__index.SetShown = function(self, shown)
                if shown then self:Show() else self:Hide() end
            end
        end
    end
end)

-- Cooldown frame stubs — Cooldown may share the Frame metatable
-- on some builds, so wrap in pcall and test keyboard after.
pcall(function()
    local f = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
    local mt = getmetatable(f)
    if mt and mt.__index and type(mt.__index) == "table" then
        if not mt.__index.SetSwipeColor then
            mt.__index.SetSwipeColor = function() end
        end
        if not mt.__index.SetDrawSwipe then
            mt.__index.SetDrawSwipe = function() end
        end
        if not mt.__index.SetUseCircularEdge then
            mt.__index.SetUseCircularEdge = function() end
        end
        if not mt.__index.SetDrawBling then
            mt.__index.SetDrawBling = function() end
        end
        if not mt.__index.SetDrawEdge then
            mt.__index.SetDrawEdge = function() end
        end
        if not mt.__index.SetEdgeTexture then
            mt.__index.SetEdgeTexture = function() end
        end
        if not mt.__index.SetHideCountdownNumbers then
            mt.__index.SetHideCountdownNumbers = function() end
        end
    end
end)

-- StatusBar stubs — StatusBar is not a secure frame type.
pcall(function()
    local sb = CreateFrame("StatusBar", nil, UIParent)
    local mt = getmetatable(sb)
    if mt and mt.__index and type(mt.__index) == "table" then
        if not mt.__index.SetReverseFill then
            mt.__index.SetReverseFill = function() end
        end
        if not mt.__index.SetRotatesTexture then
            mt.__index.SetRotatesTexture = function() end
        end
        if not mt.__index.SetFillStyle then
            mt.__index.SetFillStyle = function() end
        end
    end
end)

-- SetAtlas on textures — Texture is not a secure frame type.
pcall(function()
    local t = UIParent:CreateTexture()
    local mt = getmetatable(t)
    if mt and mt.__index and type(mt.__index) == "table" then
        if not mt.__index.SetAtlas then
            mt.__index.SetAtlas = function(self)
                self:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
        end
    end
end)

------------------------------------------------------------
-- Per-instance patching for Frame/Button types
-- These methods can NOT go on the shared metatable without
-- causing secure taint. Instead, Cell applies them to each
-- frame instance after creation via Cell335_PatchFrame().
------------------------------------------------------------
function Cell335_PatchFrame(f)
    if not f then return f end
    if not f.SetShown then
        f.SetShown = function(self, shown)
            if shown then self:Show() else self:Hide() end
        end
    end
    if not f.SetIgnoreParentAlpha then
        f.SetIgnoreParentAlpha = function() end
    end
    if not f.SetIgnoreParentScale then
        f.SetIgnoreParentScale = function() end
    end
    if not f.SetEnabled then
        f.SetEnabled = function(self, enabled)
            if enabled then
                if self.Enable then self:Enable() end
            else
                if self.Disable then self:Disable() end
            end
        end
    end
    return f
end

------------------------------------------------------------
-- Cell335_CreateFrame: wrapper that auto-patches new frames.
-- Usage: add "local CreateFrame = Cell335_CreateFrame or CreateFrame"
-- at the top of each Cell .lua file to auto-patch all frames.
------------------------------------------------------------
function Cell335_CreateFrame(frameType, name, parent, ...)
    local templates = ...
    local f = CreateFrame(frameType, name, parent, ...)
    -- 3.3.5a: NEVER patch secure group/unit frames — writing to their table
    -- taints the secure environment, breaking SecureGroupHeaderTemplate
    -- child creation. Only skip the specific templates that manage units.
    local isSecure = templates and (
        string.find(templates, "SecureGroupHeaderTemplate") or
        string.find(templates, "SecureGroupPetHeaderTemplate")
    )
    if not isSecure then
        Cell335_PatchFrame(f)
    end
    -- 3.3.5a: child frames default to level 0, which puts them BELOW
    -- a parent that has a high frame level for mouse hit-testing.
    -- Modern WoW gives children automatic priority; 3.3.5a does not.
    -- Fix: set child level = parent level + 1 so children receive clicks.
    -- Skip for secure frames to avoid taint.
    if not isSecure and parent and type(parent) == "table" and parent.GetFrameLevel then
        f:SetFrameLevel(parent:GetFrameLevel() + 1)
    end
    return f
end

-- MaskTexture stubs — global fallback + metatable patches for all widget types
-- Global stub creator: any widget can call Cell_CreateMaskTexture(self) as fallback
local function _stubMaskTexture(parent)
    local d = {}
    d.SetTexture = function() end
    d.SetPoint = function() end
    d.SetAllPoints = function() end
    d.Show = function() end
    d.Hide = function() end
    d.IsShown = function() return true end
    d.ClearAllPoints = function() end
    d.GetPoint = function() return "CENTER", parent, "CENTER", 0, 0 end
    return d
end

-- Try to patch CreateMaskTexture onto every known widget type metatable
local _patchedMTs = {}
local function _patchMaskMethods(widget)
    local mt = getmetatable(widget)
    if mt and mt.__index and type(mt.__index) == "table" and not _patchedMTs[mt] then
        _patchedMTs[mt] = true
        if not mt.__index.CreateMaskTexture then
            mt.__index.CreateMaskTexture = function(self) return _stubMaskTexture(self) end
        end
        if not mt.__index.AddMaskTexture then
            mt.__index.AddMaskTexture = function() end
        end
        if not mt.__index.RemoveMaskTexture then
            mt.__index.RemoveMaskTexture = function() end
        end
        if not mt.__index.GetNumMaskTextures then
            mt.__index.GetNumMaskTextures = function() return 0 end
        end
        if not mt.__index.GetMaskTexture then
            mt.__index.GetMaskTexture = function() return nil end
        end
    end
end

-- Patch Frame, StatusBar, Cooldown, Button, and Texture metatables
pcall(function()
    local f = CreateFrame("Frame")
    _patchMaskMethods(f)
    local t = f:CreateTexture()
    _patchMaskMethods(t)
    local fs = f:CreateFontString()
    _patchMaskMethods(fs)
end)
pcall(function()
    local sb = CreateFrame("StatusBar")
    _patchMaskMethods(sb)
end)
pcall(function()
    local cd = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
    _patchMaskMethods(cd)
end)
pcall(function()
    local btn = CreateFrame("Button")
    _patchMaskMethods(btn)
end)

-- Animation stubs: SetChildKey, SetToFinalAlpha, SetFromAlpha, SetToAlpha, SetSmoothing
pcall(function()
    local f = CreateFrame("Frame")
    local g = f:CreateAnimationGroup()
    local a = g:CreateAnimation("Alpha")
    local amt = getmetatable(a)
    if amt and amt.__index and type(amt.__index) == "table" then
        if not amt.__index.SetChildKey then
            amt.__index.SetChildKey = function(self, key)
                self._childKey = key
            end
        end
        -- Modern WoW uses SetFromAlpha/SetToAlpha; 3.3.5a uses SetChange(delta).
        -- We store the from/to values and compute delta when the animation plays.
        if not amt.__index.SetFromAlpha then
            amt.__index.SetFromAlpha = function(self, fromAlpha)
                self._fromAlpha = fromAlpha
                if self._toAlpha and self.SetChange then
                    pcall(self.SetChange, self, self._toAlpha - fromAlpha)
                end
            end
        end
        if not amt.__index.SetToAlpha then
            amt.__index.SetToAlpha = function(self, toAlpha)
                self._toAlpha = toAlpha
                if self._fromAlpha and self.SetChange then
                    pcall(self.SetChange, self, toAlpha - self._fromAlpha)
                end
            end
        end
        if not amt.__index.SetSmoothing then
            amt.__index.SetSmoothing = function() end
        end
    end
    -- Stub SetSmoothing + SetChildKey on other animation types too
    -- LibCustomGlow calls SetChildKey on Scale and FlipBook animations, not just Alpha.
    for _, animType in ipairs({"Translation", "Scale", "Rotation", "FlipBook"}) do
        pcall(function()
            local anim = g:CreateAnimation(animType)
            local mt2 = getmetatable(anim)
            if mt2 and mt2.__index and type(mt2.__index) == "table" then
                if not mt2.__index.SetSmoothing then
                    mt2.__index.SetSmoothing = function() end
                end
                if not mt2.__index.SetChildKey then
                    mt2.__index.SetChildKey = function(self, key)
                        self._childKey = key
                    end
                end
            end
        end)
    end

    local gmt = getmetatable(g)
    if gmt and gmt.__index and type(gmt.__index) == "table" then
        if not gmt.__index.SetToFinalAlpha then
            gmt.__index.SetToFinalAlpha = function() end
        end
    end
end)

------------------------------------------------------------
-- CreateColor shim + SetGradient compat
------------------------------------------------------------
-- Modern WoW: texture:SetGradient("VERTICAL", CreateColor(r,g,b,a), CreateColor(r,g,b,a))
-- 3.3.5a:     texture:SetGradient("VERTICAL", minR, minG, minB, maxR, maxG, maxB)
-- We provide CreateColor and hook SetGradient to unpack color objects automatically.

if not CreateColor then
    local ColorMixin = {}
    ColorMixin.__index = ColorMixin

    function ColorMixin:GetRGB()
        return self.r, self.g, self.b
    end

    function ColorMixin:GetRGBA()
        return self.r, self.g, self.b, self.a
    end

    function ColorMixin:SetRGBA(r, g, b, a)
        self.r = r or 0
        self.g = g or 0
        self.b = b or 0
        self.a = a or 1
    end

    function ColorMixin:GenerateHexColor()
        return format("ff%02x%02x%02x", self.r * 255, self.g * 255, self.b * 255)
    end

    function ColorMixin:GenerateHexColorMarkup()
        return "|c" .. self:GenerateHexColor()
    end

    function ColorMixin:WrapTextInColorCode(text)
        return self:GenerateHexColorMarkup() .. text .. "|r"
    end

    function ColorMixin:IsEqualTo(other)
        if not other then return false end
        return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a
    end

    function CreateColor(r, g, b, a)
        local c = setmetatable({}, ColorMixin)
        c.r = r or 0
        c.g = g or 0
        c.b = b or 0
        c.a = a or 1
        return c
    end
end

-- Hook SetGradient on Texture metatable to accept both old and new call conventions
do
    local hooked = false
    local f = CreateFrame("Frame")
    local t = f:CreateTexture()
    local mt = getmetatable(t)
    if mt and mt.__index then
        local origSetGradient = mt.__index.SetGradient
        if origSetGradient then
            mt.__index.SetGradient = function(self, orientation, a1, a2, a3, a4, a5, a6)
                -- New style: SetGradient("DIR", colorObj1, colorObj2)
                if type(a1) == "table" and a1.r then
                    local c1 = a1
                    local c2 = a2
                    return origSetGradient(self, orientation, c1.r, c1.g, c1.b, c2.r, c2.g, c2.b)
                end
                -- Old style: SetGradient("DIR", r1, g1, b1, r2, g2, b2)
                return origSetGradient(self, orientation, a1, a2, a3, a4, a5, a6)
            end
            hooked = true
        end
    end
    f:Hide()
end

------------------------------------------------------------
-- IsInRaid / IsInGroup shims
-- Modern API; 3.3.5a uses GetNumRaidMembers() / GetNumPartyMembers()
------------------------------------------------------------
if not IsInRaid then
    IsInRaid = function()
        return (GetNumRaidMembers() or 0) > 0
    end
end
if not IsInGroup then
    IsInGroup = function(category)
        -- 3.3.5a has no instance groups — LE_PARTY_CATEGORY_INSTANCE always false
        if category == 2 then return false end
        return (GetNumPartyMembers() or 0) > 0 or (GetNumRaidMembers() or 0) > 0
    end
end
if not GetNumGroupMembers then
    GetNumGroupMembers = function()
        local raid = GetNumRaidMembers() or 0
        if raid > 0 then return raid end
        local party = GetNumPartyMembers() or 0
        if party > 0 then return party + 1 end -- +1 for player
        return 0
    end
end
if not GetNumSubgroupMembers then
    GetNumSubgroupMembers = function()
        return GetNumPartyMembers() or 0
    end
end

------------------------------------------------------------
-- GetNormalizedRealmName shim
-- Modern API; 3.3.5a only has GetRealmName(). Normalized = spaces removed.
------------------------------------------------------------
if not GetNormalizedRealmName then
    GetNormalizedRealmName = function()
        local realm = GetRealmName()
        if realm then
            return realm:gsub("%s", "")
        end
        return ""
    end
end

------------------------------------------------------------
-- FontString:GetContentHeight shim
-- Modern method; 3.3.5a equivalent is GetStringHeight().
------------------------------------------------------------
do
    local fs = UIParent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local mt = getmetatable(fs)
    if mt and mt.__index and type(mt.__index) == "table" and not mt.__index.GetContentHeight then
        mt.__index.GetContentHeight = function(self)
            return self:GetStringHeight() or 0
        end
    end
    fs:Hide()
end

------------------------------------------------------------
-- UnitIsGroupLeader / UnitIsGroupAssistant shims
-- ALWAYS override: ChromieCraft may have built-in versions that don't
-- work correctly (same pattern as UnitClassBase).
-- 3.3.5a native APIs: UnitIsPartyLeader / UnitIsRaidOfficer
------------------------------------------------------------
do
    local _UnitIsPartyLeader = UnitIsPartyLeader
    local _UnitIsRaidOfficer = UnitIsRaidOfficer
    UnitIsGroupLeader = function(unit)
        return _UnitIsPartyLeader and _UnitIsPartyLeader(unit)
    end
    UnitIsGroupAssistant = function(unit)
        if _UnitIsRaidOfficer then return _UnitIsRaidOfficer(unit) end
        return false
    end
end

------------------------------------------------------------
-- IsEveryoneAssistant shim
-- Doesn't exist in 3.3.5a; always return false
------------------------------------------------------------
if not IsEveryoneAssistant then
    IsEveryoneAssistant = function() return false end
end

------------------------------------------------------------
-- UnitInOtherParty shim
-- Doesn't exist in 3.3.5a; always return false
------------------------------------------------------------
if not UnitInOtherParty then
    UnitInOtherParty = function(unit)
        return false
    end
end

------------------------------------------------------------
-- CombatLogGetCurrentEventInfo shim
-- Modern WoW (8.0+) uses CombatLogGetCurrentEventInfo() inside CLEU handlers.
-- In 3.3.5a, CLEU passes args directly to the event handler.
-- This shim captures the args via an early-registering frame.
-- 3.3.5a CLEU format: timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...
-- Modern format adds: hideCaster (arg3), sourceRaidFlags (arg7), destRaidFlags (arg11)
-- We insert dummy values to match the modern format that Cell expects.
------------------------------------------------------------
if not CombatLogGetCurrentEventInfo then
    local _cleuArgs = {}
    local _cleuFrame = CreateFrame("Frame")
    _cleuFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    _cleuFrame:SetScript("OnEvent", function(self, event, timestamp, subEvent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...)
        -- Insert dummy values: hideCaster=false after subEvent, sourceRaidFlags=0 after sourceFlags, destRaidFlags=0 after destFlags
        _cleuArgs = {timestamp, subEvent, false, sourceGUID, sourceName, sourceFlags, 0, destGUID, destName, destFlags, 0, ...}
    end)
    CombatLogGetCurrentEventInfo = function()
        return unpack(_cleuArgs)
    end
end

------------------------------------------------------------
-- UnitInPhase shim (modern)
-- Doesn't exist in 3.3.5a; everyone is in the same phase on private servers
------------------------------------------------------------
if not UnitInPhase then
    UnitInPhase = function(unit) return true end
end

------------------------------------------------------------
-- UnitHasIncomingResurrection shim (Cata+)
------------------------------------------------------------
if not UnitHasIncomingResurrection then
    UnitHasIncomingResurrection = function(unit) return false end
end

------------------------------------------------------------
-- UnitPhaseReason shim (modern)
------------------------------------------------------------
if not UnitPhaseReason then
    UnitPhaseReason = function(unit) return nil end
end

------------------------------------------------------------
-- C_IncomingSummon shim (modern)
------------------------------------------------------------
if not C_IncomingSummon then
    C_IncomingSummon = {
        HasIncomingSummon = function(unit) return false end,
        IncomingSummonStatus = function(unit) return 0 end,
    }
end

------------------------------------------------------------
-- IsInInstance shim
-- 3.3.5a has IsInInstance but some builds may not; safe to check.
------------------------------------------------------------
-- IsInInstance exists in 3.3.5a, no shim needed

------------------------------------------------------------
-- UnitGroupRolesAssigned shim (Cata+)
-- 3.3.5a doesn't have dungeon roles; return "NONE"
------------------------------------------------------------
if not UnitGroupRolesAssigned then
    UnitGroupRolesAssigned = function(unit) return "NONE" end
end

------------------------------------------------------------
-- GetSpecialization shim (Cata+)
-- 3.3.5a uses GetActiveTalentGroup / GetPrimaryTalentTree
------------------------------------------------------------
if not GetSpecialization then
    GetSpecialization = function()
        if GetActiveTalentGroup then
            return GetActiveTalentGroup()
        end
        return 1
    end
end

------------------------------------------------------------
-- UnitClassBase shim (modern convenience)
-- Returns just the classFile token (uppercase, e.g. "SHAMAN").
-- ALWAYS override: ChromieCraft 3.3.5a has a built-in UnitClassBase that
-- returns the LOCALIZED name ("Shaman") instead of the token ("SHAMAN"),
-- which breaks RAID_CLASS_COLORS lookups and makes health bars white.
------------------------------------------------------------
do
    local CLASS_IDS = {WARRIOR=1,PALADIN=2,HUNTER=3,ROGUE=4,PRIEST=5,DEATHKNIGHT=6,SHAMAN=7,MAGE=8,WARLOCK=9,DRUID=11}
    UnitClassBase = function(unit)
        local _, classFile = UnitClass(unit)
        return classFile, CLASS_IDS[classFile]
    end
end

------------------------------------------------------------
-- C_UnitAuras shim (modern)
-- Used for aura queries; provide basic fallback table
------------------------------------------------------------
if not C_UnitAuras then
    C_UnitAuras = {
        GetAuraDataByIndex = function() return nil end,
        GetAuraDataByAuraInstanceID = function() return nil end,
        GetAuraDataBySpellName = function() return nil end,
        GetAuraSlots = function() return nil end,
        GetAuraDataBySlot = function() return nil end,
        GetBuffDataByIndex = function() return nil end,
        GetDebuffDataByIndex = function() return nil end,
        GetPlayerAuraBySpellID = function() return nil end,
        IsAuraFilteredOutByInstanceID = function() return false end,
        AddPrivateAuraAnchor = function() return 0 end,
        RemovePrivateAuraAnchor = function() end,
        AddPrivateAuraAppliedSound = function() end,
    }
end

------------------------------------------------------------
-- AuraUtil shim (modern)
------------------------------------------------------------
if not AuraUtil then
    AuraUtil = {
        FindAuraByName = function(name, unit, filter)
            -- scan buffs/debuffs for matching name
            if not unit then unit = "player" end
            if not filter then filter = "HELPFUL" end
            for i = 1, 40 do
                local n, rank, icon, count, debuffType, duration, expirationTime, caster, isStealable, shouldConsolidate, spellId = UnitAura(unit, i, filter)
                if not n then break end
                if n == name then
                    return n, rank, icon, count, debuffType, duration, expirationTime, caster, isStealable, shouldConsolidate, spellId
                end
            end
            return nil
        end,
        ForEachAura = function(unit, filter, maxCount, func)
            for i = 1, maxCount or 40 do
                local n = UnitAura(unit, i, filter)
                if not n then break end
                func(UnitAura(unit, i, filter))
            end
        end,
    }
end

------------------------------------------------------------
-- UnitDetailedThreatSituation shim
-- Exists in 3.3.5a as UnitDetailedThreatSituation; check just in case
------------------------------------------------------------
-- UnitDetailedThreatSituation exists in 3.3.5a, no shim needed

------------------------------------------------------------
-- UnitHasVehicleUI / UnitInVehicle shims
-- Vehicles exist in 3.3.5a but the functions may differ
------------------------------------------------------------
if not UnitHasVehicleUI then
    UnitHasVehicleUI = function(unit) return false end
end
if not UnitInVehicle then
    UnitInVehicle = function(unit) return false end
end

------------------------------------------------------------
-- LibHealComm: enable by default on 3.3.5a
-- UnitGetIncomingHeals doesn't exist natively; LibHealComm is the only source.
-- This runs before snippets, but snippets can override it to false if needed.
------------------------------------------------------------
if CELL_USE_LIBHEALCOMM == nil then
    CELL_USE_LIBHEALCOMM = true
end

------------------------------------------------------------
-- UnitGetIncomingHeals / UnitGetTotalAbsorbs / UnitGetTotalHealAbsorbs
-- These are Cata+ APIs. In 3.3.5a, heal prediction uses LibHealComm.
-- Provide no-op shims so Cell doesn't crash; it already has LibHealComm support.
------------------------------------------------------------
if not UnitGetIncomingHeals then
    UnitGetIncomingHeals = function(unit, healer)
        return 0
    end
end
if not UnitGetTotalAbsorbs then
    UnitGetTotalAbsorbs = function(unit)
        return 0
    end
end
if not UnitGetTotalHealAbsorbs then
    UnitGetTotalHealAbsorbs = function(unit)
        return 0
    end
end

------------------------------------------------------------
-- RegisterAttributeDriver / UnregisterAttributeDriver
-- Modern WoW uses RegisterAttributeDriver; 3.3.5a has
-- RegisterStateDriver instead. We delegate state-visibility
-- to the native API (it just shows/hides frames, no taint risk).
-- Other attributes are no-op'd to avoid keybinding taint.
------------------------------------------------------------
if not RegisterAttributeDriver then
    RegisterAttributeDriver = function(frame, attribute, conditional)
        if attribute == "state-visibility" and RegisterStateDriver then
            RegisterStateDriver(frame, "visibility", conditional)
        end
        -- other attributes: no-op to avoid taint
    end
end
if not UnregisterAttributeDriver then
    UnregisterAttributeDriver = function(frame, attribute)
        if attribute == "state-visibility" and UnregisterStateDriver then
            UnregisterStateDriver(frame, "visibility")
        end
    end
end

------------------------------------------------------------
-- IsEncounterInProgress shim (Cata+)
-- 3.3.5a doesn't have this; return false
------------------------------------------------------------
if not IsEncounterInProgress then
    IsEncounterInProgress = function() return false end
end

------------------------------------------------------------
-- Event Translation Helper (safe, NO metatable hooks)
-- 3.3.5a is missing many events. Instead of hooking the
-- Frame metatable (which taints secure frames on 3.3.5a),
-- we provide a helper that files call to register the
-- 3.3.5a equivalents alongside the modern event names.
-- Each file also adds old event names to its OnEvent checks.
------------------------------------------------------------
CELL335_EVENT_ALIASES = {
    -- GROUP_ROSTER_UPDATE -> 3.3.5a split events
    ["GROUP_ROSTER_UPDATE"] = {"PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE"},
    -- UNIT_POWER_FREQUENT -> 3.3.5a per-type power events
    ["UNIT_POWER_FREQUENT"] = {"UNIT_MANA", "UNIT_RAGE", "UNIT_ENERGY", "UNIT_RUNIC_POWER", "UNIT_FOCUS"},
    -- UNIT_MAXPOWER -> 3.3.5a per-type max power events
    ["UNIT_MAXPOWER"] = {"UNIT_MAXMANA", "UNIT_MAXRAGE", "UNIT_MAXENERGY", "UNIT_MAXRUNIC_POWER", "UNIT_MAXFOCUS"},
}

-- Register a modern event + its 3.3.5a fallbacks.
-- Also installs method aliases on the frame for self[event]() dispatch.
function Cell335_RegisterEvent(frame, event)
    local aliases = CELL335_EVENT_ALIASES[event]
    if aliases then
        -- Modern event doesn't exist on 3.3.5a — register only the aliases
        for _, oldEvent in ipairs(aliases) do
            frame:RegisterEvent(oldEvent)
            -- Lazy method alias: when PARTY_MEMBERS_CHANGED fires and
            -- handler uses self[event](self,...), look up the modern name.
            if not rawget(frame, oldEvent) then
                rawset(frame, oldEvent, function(self, ...)
                    local fn = rawget(self, event)
                    if fn then return fn(self, ...) end
                end)
            end
        end
    else
        -- No alias mapping — register as-is (event exists on 3.3.5a)
        frame:RegisterEvent(event)
    end
end

-- Unregister a modern event + its 3.3.5a fallbacks.
function Cell335_UnregisterEvent(frame, event)
    local aliases = CELL335_EVENT_ALIASES[event]
    if aliases then
        for _, oldEvent in ipairs(aliases) do
            frame:UnregisterEvent(oldEvent)
        end
    else
        frame:UnregisterEvent(event)
    end
end

-- Check if an event name is GROUP_ROSTER_UPDATE or one of its 3.3.5a equivalents
function Cell335_IsGroupRosterEvent(event)
    return event == "GROUP_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE"
end

-- Check if an event name is UNIT_POWER_FREQUENT or one of its 3.3.5a equivalents
function Cell335_IsPowerFreqEvent(event)
    return event == "UNIT_POWER_FREQUENT" or event == "UNIT_MANA" or event == "UNIT_RAGE"
        or event == "UNIT_ENERGY" or event == "UNIT_RUNIC_POWER" or event == "UNIT_FOCUS"
end

-- Check if an event name is UNIT_MAXPOWER or one of its 3.3.5a equivalents
function Cell335_IsMaxPowerEvent(event)
    return event == "UNIT_MAXPOWER" or event == "UNIT_MAXMANA" or event == "UNIT_MAXRAGE"
        or event == "UNIT_MAXENERGY" or event == "UNIT_MAXRUNIC_POWER" or event == "UNIT_MAXFOCUS"
end

------------------------------------------------------------
-- LE_PARTY_CATEGORY constants (Cata+)
------------------------------------------------------------
if not LE_PARTY_CATEGORY_HOME then
    LE_PARTY_CATEGORY_HOME = 1
end
if not LE_PARTY_CATEGORY_INSTANCE then
    LE_PARTY_CATEGORY_INSTANCE = 2
end

------------------------------------------------------------
-- WOW_PROJECT constants
------------------------------------------------------------
if not WOW_PROJECT_WRATH_CLASSIC then
    WOW_PROJECT_WRATH_CLASSIC = 11
end
if not WOW_PROJECT_ID then
    WOW_PROJECT_ID = WOW_PROJECT_WRATH_CLASSIC
end

------------------------------------------------------------
-- UnitBuff / UnitDebuff signature shim (Cell-scoped)
-- 3.3.5a returns: name, rank, icon, count, debuffType, duration, expirationTime, source, isStealable, shouldConsolidate, spellId
-- Modern returns:  name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, ...
-- Strip "rank" (pos 2) so Cell callers using the modern signature work.
-- Stored as Cell335_UnitBuff / Cell335_UnitDebuff to avoid breaking other
-- addons (e.g. VuhDo) that expect the native 3.3.5a signature with rank.
------------------------------------------------------------
------------------------------------------------------------
-- FontString:IsTruncated() shim
-- Doesn't exist in 3.3.5a. Approximate by comparing string
-- width to the region width. Patch via metatable so ALL
-- FontStrings get it automatically.
------------------------------------------------------------
do
    local testFrame = CreateFrame("Frame")
    local testFS = testFrame:CreateFontString()
    local mt = getmetatable(testFS)
    if mt and mt.__index and not mt.__index.IsTruncated then
        mt.__index.IsTruncated = function(self)
            return self:GetStringWidth() > (self:GetWidth() + 0.5)
        end
    end
    testFrame:Hide()
end

------------------------------------------------------------
do
    local _origUnitBuff = UnitBuff
    function Cell335_UnitBuff(unit, ...)
        local name, rank, icon, count, debuffType, duration, expirationTime, source, isStealable, shouldConsolidate, spellId = _origUnitBuff(unit, ...)
        if not name then return nil end
        duration = tonumber(duration) or 0
        expirationTime = tonumber(expirationTime) or 0
        return name, icon, count, debuffType, duration, expirationTime, source, isStealable, shouldConsolidate, spellId
    end

    local _origUnitDebuff = UnitDebuff
    function Cell335_UnitDebuff(unit, ...)
        local name, rank, icon, count, debuffType, duration, expirationTime, source, isStealable, shouldConsolidate, spellId = _origUnitDebuff(unit, ...)
        if not name then return nil end
        duration = tonumber(duration) or 0
        expirationTime = tonumber(expirationTime) or 0
        return name, icon, count, debuffType, duration, expirationTime, source, isStealable, shouldConsolidate, spellId
    end
end
