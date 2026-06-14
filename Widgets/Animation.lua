local addonName, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

---@class CellAnimations
local A = Cell.animations
local CreateFrame = Cell335_CreateFrame or CreateFrame

-----------------------------------------
-- forked from ElvUI
-----------------------------------------
local FADEFRAMES, FADEMANAGER = {}, CreateFrame('FRAME')


FADEMANAGER.interval = 0.025

-----------------------------------------
-- fade manager onupdate
-----------------------------------------
local function Fading(_, elapsed)
    FADEMANAGER.timer = (FADEMANAGER.timer or 0) + elapsed

    if FADEMANAGER.timer > FADEMANAGER.interval then
        FADEMANAGER.timer = 0

        for frame, info in next, FADEFRAMES do
            if frame:IsVisible() then
                info.fadeTimer = (info.fadeTimer or 0) + (elapsed + FADEMANAGER.interval)
            else -- faster for hidden frames
                info.fadeTimer = info.timeToFade + 1
            end

            if info.fadeTimer < info.timeToFade then
                if info.mode == 'IN' then
                    frame:SetAlpha((info.fadeTimer / info.timeToFade) * info.diffAlpha + info.startAlpha)
                else
                    frame:SetAlpha(((info.timeToFade - info.fadeTimer) / info.timeToFade) * info.diffAlpha + info.endAlpha)
                end
            else
                frame:SetAlpha(info.endAlpha)
                -- NOTE: remove from FADEFRAMES
                if frame and FADEFRAMES[frame] then
                    if frame.fade then
                        frame.fade.fadeTimer = nil
                    end
                    FADEFRAMES[frame] = nil
                end
            end
        end

        if not next(FADEFRAMES) then
            -- print("FINISHED FADING!")
            FADEMANAGER:SetScript('OnUpdate', nil)
        end
    end
end

-----------------------------------------
-- fade
-----------------------------------------
local function FrameFade(frame, info)
    frame:SetAlpha(info.startAlpha)

    if not frame:IsProtected() then
        frame:Show()
    end

    if not FADEFRAMES[frame] then
        FADEFRAMES[frame] = info
        FADEMANAGER:SetScript('OnUpdate', Fading)
    else
        FADEFRAMES[frame] = info
    end
end

function A.FrameFadeIn(frame, timeToFade, startAlpha, endAlpha)
    if frame.fade then
        frame.fade.fadeTimer = nil
    else
        frame.fade = {}
    end

    frame.fade.mode = 'IN'
    frame.fade.timeToFade = timeToFade
    frame.fade.startAlpha = startAlpha
    frame.fade.endAlpha = endAlpha
    frame.fade.diffAlpha = endAlpha - startAlpha

    FrameFade(frame, frame.fade)
end

function A.FrameFadeOut(frame, timeToFade, startAlpha, endAlpha)
    if frame.fade then
        frame.fade.fadeTimer = nil
    else
        frame.fade = {}
    end

    frame.fade.mode = 'OUT'
    frame.fade.timeToFade = timeToFade
    frame.fade.startAlpha = startAlpha
    frame.fade.endAlpha = endAlpha
    frame.fade.diffAlpha = startAlpha - endAlpha

    FrameFade(frame, frame.fade)
end

-----------------------------------------
-- fade in/out on mouseover/mouseout
-----------------------------------------
function A.ApplyFadeInOutToParent(parent, condition, ...)
    for _, f in pairs({...}) do
        f:SetHitRectInsets(-2, -2, -2, -2)

        f:HookScript("OnEnter", function()
            if condition() then
                A.FrameFadeIn(parent, 0.25, parent:GetAlpha(), 1)
            end
        end)

        f:HookScript("OnLeave", function()
            if condition() then
                A.FrameFadeOut(parent, 0.25, parent:GetAlpha(), 0)
            end
        end)
    end
end

-----------------------------------------
-- add fade in/out
-----------------------------------------
function A.CreateFadeIn(frame, fromAlpha, toAlpha, duration, delay, onFinished)
    local fadeIn = frame:CreateAnimationGroup()
    frame.fadeIn = fadeIn
    fadeIn.alpha = fadeIn:CreateAnimation("Alpha")
    if fadeIn.alpha.SetFromAlpha then fadeIn.alpha:SetFromAlpha(fromAlpha) end
    if fadeIn.alpha.SetToAlpha then fadeIn.alpha:SetToAlpha(toAlpha) end
    fadeIn.alpha:SetDuration(duration)
    if delay then fadeIn.alpha:SetStartDelay(delay) end

    fadeIn:SetScript("OnPlay", function()
        if frame.fadeOut then
            frame.fadeOut:Stop()
        end
    end)

    if onFinished then
        fadeIn:SetScript("OnFinished", onFinished)
    end

    function frame:FadeIn()
        frame:Show()
        fadeIn:Play()
    end
end

function A.CreateFadeOut(frame, fromAlpha, toAlpha, duration, delay, onFinished)
    local fadeOut = frame:CreateAnimationGroup()
    frame.fadeOut = fadeOut
    fadeOut.alpha = fadeOut:CreateAnimation("Alpha")
    if fadeOut.alpha.SetFromAlpha then fadeOut.alpha:SetFromAlpha(fromAlpha) end
    if fadeOut.alpha.SetToAlpha then fadeOut.alpha:SetToAlpha(toAlpha) end
    fadeOut.alpha:SetDuration(duration)
    if delay then fadeOut.alpha:SetStartDelay(delay) end

    fadeOut:SetScript("OnPlay", function()
        if frame.fadeIn then
            frame.fadeIn:Stop()
        end
    end)

    if onFinished then
        fadeOut:SetScript("OnFinished", onFinished)
    else
        fadeOut:SetScript("OnFinished", function()
            frame:Hide()
        end)
    end

    function frame:FadeOut()
        fadeOut:Play()
    end
end

-----------------------------------------
-- apply fade in/out to menu
-----------------------------------------
function A.ApplyFadeInOutToMenu(anchorFrame, hoverFrame)
    local fadingIn, fadedIn, fadingOut, fadedOut
    anchorFrame.fadeIn = anchorFrame:CreateAnimationGroup()
    anchorFrame.fadeIn.alpha = anchorFrame.fadeIn:CreateAnimation("alpha")
    if anchorFrame.fadeIn.alpha.SetFromAlpha then anchorFrame.fadeIn.alpha:SetFromAlpha(0) end
    if anchorFrame.fadeIn.alpha.SetToAlpha then anchorFrame.fadeIn.alpha:SetToAlpha(1) end
    anchorFrame.fadeIn.alpha:SetDuration(0.5)
    if anchorFrame.fadeIn.alpha.SetSmoothing then anchorFrame.fadeIn.alpha:SetSmoothing("OUT") end
    anchorFrame.fadeIn:SetScript("OnPlay", function()
        anchorFrame.fadeOut:Finish()
        fadingIn = true
    end)
    anchorFrame.fadeIn:SetScript("OnFinished", function()
        fadingIn = false
        fadingOut = false
        fadedIn = true
        fadedOut = false
        anchorFrame:SetAlpha(1)

        if CellDB["general"]["fadeOut"] and not hoverFrame:IsMouseOver() then
            anchorFrame.fadeOut:Play()
        end
    end)

    anchorFrame.fadeOut = anchorFrame:CreateAnimationGroup()
    anchorFrame.fadeOut.alpha = anchorFrame.fadeOut:CreateAnimation("alpha")
    if anchorFrame.fadeOut.alpha.SetFromAlpha then anchorFrame.fadeOut.alpha:SetFromAlpha(1) end
    if anchorFrame.fadeOut.alpha.SetToAlpha then anchorFrame.fadeOut.alpha:SetToAlpha(0) end
    anchorFrame.fadeOut.alpha:SetDuration(0.5)
    if anchorFrame.fadeOut.alpha.SetSmoothing then anchorFrame.fadeOut.alpha:SetSmoothing("OUT") end
    anchorFrame.fadeOut:SetScript("OnPlay", function()
        anchorFrame.fadeIn:Finish()
        fadingOut = true
    end)
    anchorFrame.fadeOut:SetScript("OnFinished", function()
        fadingIn = false
        fadingOut = false
        fadedIn = false
        fadedOut = true
        anchorFrame:SetAlpha(0)

        if hoverFrame:IsMouseOver() then
            anchorFrame.fadeIn:Play()
        end
    end)

    hoverFrame:SetScript("OnEnter", function()
        if not CellDB["general"]["fadeOut"] then return end
        if not (fadingIn or fadedIn) then
            anchorFrame.fadeIn:Play()
        end
    end)
    hoverFrame:SetScript("OnLeave", function()
        if not CellDB["general"]["fadeOut"] then return end
        if hoverFrame:IsMouseOver() then return end
        if not (fadingOut or fadedOut) then
            anchorFrame.fadeOut:Play()
        end
    end)
end

-----------------------------------------
-- blink
-----------------------------------------
function A.CreateBlinkAnimation(region, duration, enableShowHideHook)
    local blink = region:CreateAnimationGroup()
    region.blink = blink

    local alpha = blink:CreateAnimation("Alpha")
    blink.alpha = alpha
    if alpha.SetFromAlpha then alpha:SetFromAlpha(0.25) end
    if alpha.SetToAlpha then alpha:SetToAlpha(1) end
    alpha:SetDuration(duration or 0.5)

    blink:SetLooping("BOUNCE")

    if enableShowHideHook and region.HookScript then
        region:HookScript("OnShow", function()
            blink:Play()
        end)
        region:HookScript("OnHide", function()
            blink:Stop()
        end)
    else
        blink:Play()
    end
end