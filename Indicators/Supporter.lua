local _, Cell = ...
local F = Cell.funcs
local A = Cell.animations
local CreateFrame = Cell335_CreateFrame or CreateFrame

-------------------------------------------------
-- pool
-------------------------------------------------
local pool

local function creationFunc()
    local f = CreateFrame("Frame")
    f:Hide()

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface/AddOns/Cell/Media/star.png")
    tex:SetAllPoints(f)

    local ag = f:CreateAnimationGroup()
    ag:SetScript("OnFinished", function()
        if pool:IsActive(f) then
            pool:Release(f)
        end
    end)

    -- in -------------------------------------------------------------------- --
    local in_t = ag:CreateAnimation("Translation")
    in_t:SetOrder(1)
    in_t:SetDuration(0.3)
    if in_t.SetSmoothing then in_t:SetSmoothing("IN_OUT") end

    local in_s = ag:CreateAnimation("Scale")
    in_s:SetOrder(1)
    in_s:SetScaleFrom(0, 0)
    in_s:SetScaleTo(1, 1)
    in_s:SetDuration(0.3)

    local in_a = ag:CreateAnimation("Alpha")
    in_a:SetOrder(1)
    if in_a.SetFromAlpha then in_a:SetFromAlpha(0) end
    if in_a.SetToAlpha then in_a:SetToAlpha(1) end
    in_a:SetDuration(0.3)

    local in_spinning = ag:CreateAnimation("Rotation")
    in_spinning:SetOrder(1)
    in_spinning:SetDegrees(-360)
    in_spinning:SetDuration(0.5)
    in_spinning:SetEndDelay(0.5)

    -- main ------------------------------------------------------------------ --
    local main_s1 = ag:CreateAnimation("Scale")
    main_s1:SetOrder(2)
    main_s1:SetScaleTo(1.25, 1.25)
    main_s1:SetDuration(0.2)

    local main_t1 = ag:CreateAnimation("Translation")
    main_t1:SetOffset(0, 5)
    main_t1:SetDuration(0.1)
    main_t1:SetOrder(2)
    if main_t1.SetSmoothing then main_t1:SetSmoothing("OUT") end

    local main_t2 = ag:CreateAnimation("Translation")
    main_t2:SetOffset(0, -5)
    main_t2:SetDuration(0.1)
    main_t2:SetOrder(2)
    if main_t2.SetSmoothing then main_t2:SetSmoothing("IN") end
    main_t2:SetStartDelay(0.1)
    main_t2:SetEndDelay(0.25)

    local main_s2 = ag:CreateAnimation("Scale")
    main_s2:SetOrder(3)
    main_s2:SetScaleTo(1.25, 1.25)
    main_s2:SetDuration(0.2)

    local main_t3 = ag:CreateAnimation("Translation")
    main_t3:SetOffset(0, 5)
    main_t3:SetDuration(0.1)
    main_t3:SetOrder(3)
    if main_t3.SetSmoothing then main_t3:SetSmoothing("OUT") end

    local main_t4 = ag:CreateAnimation("Translation")
    main_t4:SetOffset(0, -5)
    main_t4:SetDuration(0.1)
    main_t4:SetOrder(3)
    if main_t4.SetSmoothing then main_t4:SetSmoothing("IN") end
    main_t4:SetStartDelay(0.1)
    main_t4:SetEndDelay(0.5)

    -- out ------------------------------------------------------------------- --
    local out_s = ag:CreateAnimation("Scale")
    out_s:SetOrder(4)
    out_s:SetScaleTo(0, 0)
    out_s:SetDuration(0.5)
    if out_s.SetSmoothing then out_s:SetSmoothing("IN") end

    local out_spinning = ag:CreateAnimation("Rotation")
    out_spinning:SetOrder(4)
    out_spinning:SetDegrees(-360)
    out_spinning:SetDuration(0.5)

    local out_t = ag:CreateAnimation("Translation")
    out_t:SetOrder(4)
    out_t:SetStartDelay(0.2)
    out_t:SetDuration(0.3)
    if out_t.SetSmoothing then out_t:SetSmoothing("IN_OUT") end

    local out_a = ag:CreateAnimation("Alpha")
    out_a:SetOrder(4)
    if out_a.SetFromAlpha then out_a:SetFromAlpha(1) end
    if out_a.SetToAlpha then out_a:SetToAlpha(0) end
    out_a:SetStartDelay(0.2)
    out_a:SetDuration(0.3)

    function f:Display(x, y)
        in_t:SetOffset(x, y)
        out_t:SetOffset(x, -y)
        f:Show()
        ag:Play()
    end

    return f
end

local function resetterFunc(_, f)
    f:Hide()
end

pool = CreateObjectPool(creationFunc, resetterFunc)

local function Display(b)
    local f = pool:Acquire()
    f:SetParent(b.widgets.indicatorFrame)
    -- f:SetFrameLevel(b:GetFrameLevel()+200)
    f:SetPoint("CENTER", b, "BOTTOMLEFT")

    local size = max(min(b:GetHeight(), b:GetWidth()), 64)
    f:SetSize(size, size)

    f:Display(ceil(b:GetWidth()/2), ceil(b:GetHeight()/2))
    -- f:FadeIn()
    -- C_Timer.After(3, f.FadeOut)
end

-------------------------------------------------
-- mvp pool (FlipBook animations are retail-only, stub for 3.3.5a)
-------------------------------------------------
local stubPool = { Acquire = function() return nil end, Release = function() end, IsActive = function() return false end, ReleaseAll = function() end }
local mvpPool = stubPool

local function DisplayMVP(b)
    local f = mvpPool:Acquire()
    if not f then return end
    f:SetParent(b.widgets.indicatorFrame)
    f:SetPoint("CENTER")
    f.mask:SetAllPoints(b.widgets.indicatorFrame)

    f:FadeIn()
end

-------------------------------------------------
-- goat pool (FlipBook animations are retail-only, stub for 3.3.5a)
-------------------------------------------------
local goatPool = stubPool

local function DisplayGOAT(b)
    local f = goatPool:Acquire()
    if not f then return end
    f:SetParent(b.widgets.indicatorFrame)
    f:SetPoint("BOTTOMRIGHT")
    f.mask:SetAllPoints(b.widgets.indicatorFrame)

    f:FadeIn()
end

-------------------------------------------------
-- events
-------------------------------------------------
local eventFrame = CreateFrame("Frame")
-- 3.3.5a: FIRST_FRAME_RENDERED doesn't exist, register GROUP_ROSTER_UPDATE directly
if Cell335_RegisterEvent then
    Cell335_RegisterEvent(eventFrame, "GROUP_ROSTER_UPDATE")
else
    eventFrame:RegisterEvent("FIRST_FRAME_RENDERED")
end

local displays = {
    [true] = Display,
    ["mvp"] = DisplayMVP,
    ["goat"] = DisplayGOAT,
}

local function Check()
    pool:ReleaseAll()
    mvpPool:ReleaseAll()
    goatPool:ReleaseAll()

    -- Cell.wowSupporters[Cell.vars.playerNameFull] = true

    if IsInGroup() then
        for unit in F.IterateGroupMembers() do
            local fullName = F.UnitFullName(unit)
            if Cell.wowSupporters[fullName] then
                F.HandleUnitButton("unit", unit, displays[Cell.wowSupporters[fullName]])
            end
        end
    else
        if Cell.wowSupporters[Cell.vars.playerNameFull] then
            F.HandleUnitButton("unit", "player", displays[Cell.wowSupporters[Cell.vars.playerNameFull]])
        end
    end
end

local timer, members
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "FIRST_FRAME_RENDERED" then
        eventFrame:UnregisterEvent("FIRST_FRAME_RENDERED")
        Cell335_RegisterEvent(eventFrame, "GROUP_ROSTER_UPDATE")
    end

    if timer then
        timer:Cancel()
        timer = nil
    end

    if InCombatLockdown() then return end

    local newMembers = GetNumGroupMembers()
    if members ~= newMembers then
        members = newMembers
        timer = C_Timer.NewTimer(5, Check)
    end
end)