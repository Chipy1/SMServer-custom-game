std = std or {}

local isServerMode = sm.isServerMode
local exists = sm.exists
local tostring = tostring
local error = error
local pairs = pairs
local type = type

local areThisGame = { Game = true }

local event = {
    Character        = sm.event.sendToCharacter,
    Harvestable      = sm.event.sendToHarvestable,
    Interactable     = sm.event.sendToInteractable,
    Player           = sm.event.sendToPlayer,
    ScriptableObject = sm.event.sendToScriptableObject,
    Tool             = sm.event.sendToTool,
    Unit             = sm.event.sendToUnit,
    World            = sm.event.sendToWorld
}
local event_Game = sm.event.sendToGame

local INTERNAL_EVENT_RECEIVER = "__ier:" .. tostring(sm.uuid.generateRandom())
local INTERNAL_BROADCAST_RECEIVER = "__ibr:" .. tostring(sm.uuid.generateRandom())

-- ============================================================================
-- Internal instance factory
-- ============================================================================
local newInstance
if sm.isHost then
    function newInstance(self)
        local InstanceMetatable = class()
        InstanceMetatable.__index = function(s, k)
            local ctx
            if isServerMode() then
                ctx = self.server
            else
                ctx = self.client
            end
            if ctx then
                local val = ctx[k]
                if val ~= nil then
                    return val
                end
            end
            return self[k]
        end
        return InstanceMetatable
    end
else
    function newInstance(self)
        local InstanceMetatable = class()
        InstanceMetatable.__index = function(s, k)
            local ctx = self.client
            if ctx then
                local val = ctx[k]
                if val ~= nil then
                    return val
                end
            end
            return self[k]
        end
        return InstanceMetatable
    end
end
std.class_newInstance = newInstance

-- Creates a lightweight wrapper object with its own metatable.
local function makeWrapper(index)
    local metatable = class()
    metatable.__index = index
    local tbl = metatable()
    tbl.__metatable = metatable
    return tbl
end

-- ============================================================================
-- Event System
-- ============================================================================
local eventIndex = {}

std.event = {
    receiver_name = INTERNAL_EVENT_RECEIVER
}

-- Internal event dispatcher.
local function eventReceiver(self, token, caller)
    if eventIndex[token] then
        local data = eventIndex[token]
        eventIndex[token] = nil
        local en = data.callback
        local fn = self.event[en] or self.shared.event[en]
        if fn then
            return fn(self, data.data, caller)
        end
    else
        error("NotAuthorizedCall")
    end
end

-- Generate secure wrappers for all supported sm.event targets.
for _, v in pairs({
    "Character", "Harvestable", "Interactable", "Player",
    "ScriptableObject", "Tool", "Unit", "World"
}) do
    local ev = event[v]
    std.event["sendTo" .. v] = function(target, callback, data, eventType, pauseSave)
        local token = tostring(sm.uuid.generateRandom())
        eventIndex[token] = {
            callback = callback,
            data = data
        }
        ev(target, INTERNAL_EVENT_RECEIVER, token, eventType, pauseSave)
    end
end

function std.event.sendToGame(callback, data, eventType, pauseSave)
    local token = tostring(sm.uuid.generateRandom())
    eventIndex[token] = {
        callback = callback,
        data = data
    }
    event_Game(INTERNAL_EVENT_RECEIVER, token, eventType, pauseSave)
end

-- Resolves target type and forwards event to the correct API.
local function event_Auto(target, callback, data, eventType, pauseSave)
    if target and callback then
        local typed = event[type(target)]
        if typed then
            return typed(target, callback, data, eventType, pauseSave)
        elseif areThisGame[target] then
            return event_Game(callback, data, eventType, pauseSave)
        end
    end
    return false
end

sm.event.sendToAuto = event_Auto

-- Automatic target type detection wrapper.
function std.event.sendToAuto(target, callback, data, eventType, pauseSave)
    local token = tostring(sm.uuid.generateRandom())
    eventIndex[token] = {
        callback = callback,
        data = data
    }
    if event_Auto(target, INTERNAL_EVENT_RECEIVER, token, eventType, pauseSave) then
        return true
    end
    eventIndex[token] = nil
    return false
end

-- ============================================================================
-- Broadcast System
-- ============================================================================
std.broadcast = {
    receiver_name = INTERNAL_BROADCAST_RECEIVER
}

local broadcast_index = {}
local broadcast_registry = {}

function std.broadcast.publish(broadcast, data, eventType, pauseSave)
    local list = broadcast_registry[broadcast]
    if list then
        for target, _ in pairs(list) do
            if target then
                if exists(target) then
                    local ev_func = event[type(target)]
                    if ev_func then
                        local token = tostring(sm.uuid.generateRandom())
                        broadcast_index[token] = {
                            broadcast = broadcast,
                            data = data
                        }
                        ev_func(target, INTERNAL_BROADCAST_RECEIVER, token, eventType, pauseSave)
                    end
                else
                    list[target] = nil
                end
            else
                local token = tostring(sm.uuid.generateRandom())
                broadcast_index[token] = {
                    broadcast = broadcast,
                    data = data
                }
                event_Game(INTERNAL_BROADCAST_RECEIVER, token, eventType, pauseSave)
            end
        end
    end
end

function std.broadcast.subscribe(target, broadcast)
    local list = broadcast_registry[broadcast]
    if not list then
        list = std.weakTable("k")
        broadcast_registry[broadcast] = list
    end
    if target == "Game" then 
        list[false] = true
    else
        if exists(target) and event[type(target)] then
            list[target] = true
        end
    end
end

function std.broadcast.unsubscribe(target, broadcast)
    local list = broadcast_registry[broadcast]
    if list then
        list[target] = nil
    end
end

local function broadcast_receiver(self, token)
    local data = broadcast_index[token]
    if data then
        broadcast_index[token] = nil
        local bn = data.broadcast
        local fn = self.broadcast and self.broadcast[bn]
        if not fn and self.shared and self.shared.broadcast then
            fn = self.shared.broadcast[bn]
        end
        if fn then
            return fn(self, data.data)
        end
    end
end

-- ============================================================================
-- Class Factory
-- ============================================================================
local function ClassCallWrapper(self, ...)
    return self.internal_shared.newInstance(self, ...)
end

function std.class(superClass)
    local SuperClientField = superClass and superClass.client
    local SuperServerField = superClass and superClass.server
    
    local ClassMetatable = class() 
    ClassMetatable.__call = ClassCallWrapper
    ClassMetatable.__index = superClass
    
    local ClassTable = ClassMetatable()
    ClassTable.__metatable = ClassMetatable
    
    local ClientField = makeWrapper(SuperClientField)
    local ServerField = makeWrapper(SuperServerField)
    
    ClassTable.client = ClientField
    ClassTable.server = ServerField
    ClassTable.shared = ClassTable
    
    local InternalClientField = makeWrapper(superClass and superClass.internal_client)
    local InternalServerField = makeWrapper(superClass and superClass.internal_server)
    local InternalSharedField = makeWrapper(superClass and superClass.internal_shared)
    
    ClientField.internal = InternalClientField
    ServerField.internal = InternalServerField
    ClassTable.internal = InternalSharedField
    ClassTable.internal_client = InternalClientField
    ClassTable.internal_server = InternalServerField
    ClassTable.internal_shared = InternalSharedField
    
    InternalSharedField.newInstance = newInstance(ClassTable)
    
    ClientField.event = makeWrapper(SuperClientField and SuperClientField.event)
    ServerField.event = makeWrapper(SuperServerField and SuperServerField.event)
    ClassTable.event = makeWrapper(superClass and superClass.event)
    
    ClientField.broadcast = makeWrapper(SuperClientField and SuperClientField.broadcast)
    ServerField.broadcast = makeWrapper(SuperServerField and SuperServerField.broadcast)
    ClassTable.broadcast = makeWrapper(superClass and superClass.broadcast)
    
    ClassTable[INTERNAL_EVENT_RECEIVER] = eventReceiver
    ClassTable[INTERNAL_BROADCAST_RECEIVER] = broadcast_receiver
    
    return ClassTable
end