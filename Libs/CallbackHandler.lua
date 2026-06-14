local addonName, Cell = ...

local callbacks = {}

function Cell.RegisterCallback(eventName, onEventFuncName, onEventFunc)
    if not callbacks[eventName] then callbacks[eventName] = {} end
    callbacks[eventName][onEventFuncName] = onEventFunc
end

function Cell.UnregisterCallback(eventName, onEventFuncName)
    if not callbacks[eventName] then return end
    callbacks[eventName][onEventFuncName] = nil
end

function Cell.UnregisterAllCallbacks(eventName)
    if not callbacks[eventName] then return end
    callbacks[eventName] = nil
end

function Cell.Fire(eventName, ...)
    if not callbacks[eventName] then return end

    for onEventFuncName, onEventFunc in pairs(callbacks[eventName]) do
        local ok, err = pcall(onEventFunc, ...)
        if not ok then
            print("|cffff0000[Cell CB Error]|r " .. eventName .. " / " .. tostring(onEventFuncName) .. ": " .. tostring(err))
        end
    end
end