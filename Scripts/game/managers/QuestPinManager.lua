dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

QuestPinManager = class()

-- server

function QuestPinManager.server_onCreate( self )
    g_questPinManagerServer = self
    self.sv = {}
    self.sv.addedPins = {}
    self.sv.watchedUuids = {}
    self.sv.interactableDataList = {}
    self.sv.isDirty = false
end

function QuestPinManager.server_onFixedUpdate( self )
    if self.sv.isDirty then
        self.sv.isDirty = false
        self.network:setClientData( self.sv )
    end
end

function QuestPinManager.Sv_AddWatchedUuid( uuid, pinType, worldOffset )
    if g_questPinManagerServer then
        g_questPinManagerServer:sv_addWatchedUuid( uuid, pinType, worldOffset )
    end
end

function QuestPinManager.sv_addWatchedUuid( self, uuid, pinType, worldOffset )
    self.sv.watchedUuids[uuid] = { pinType = pinType, worldOffset = worldOffset }
    local shapesInGame = QuestEntityManager.Sv_GetInteractablesWithUuid( uuid )
    for _,interactable in pairs( shapesInGame ) do
        self.sv.interactableDataList[interactable.id] = true
        g_questPinManagerServer:sv_addPin( { host = interactable.shape, world = interactable.shape.body:getWorld(), pinType = pinType, hostType = type( interactable.shape ), uuid = uuid, worldOffset = worldOffset } )
    end
end

function QuestPinManager.Sv_RemoveWatchedUuid( uuid )
    if g_questPinManagerServer then
        g_questPinManagerServer:sv_removeWatchedUuid( uuid )
    end
end

function QuestPinManager.sv_removeWatchedUuid( self, uuid )
    self.sv.watchedUuids[uuid] = nil
    if self.sv.addedPins["Shape"] then
        for hostId,pinData in pairs( self.sv.addedPins["Shape"] ) do
            if uuid == pinData.uuid then
                g_questPinManagerServer:sv_removePin ({ hostId = hostId, hostType = "Shape" } )
            end
        end
    end
end

function QuestPinManager.Sv_AddPin( host, world, pinType, worldOffset )
    local hostType = type(host)
    local uuid = nil
    if hostType == "Shape" then
        uuid = host.uuid
    end

    g_questPinManagerServer:sv_addPin( { host = host, world = world, pinType = pinType, hostType = hostType, uuid = uuid, worldOffset = worldOffset } )
end

function QuestPinManager.sv_addPin( self, data )
    if self.sv.addedPins[data.hostType] == nil then
        self.sv.addedPins[data.hostType] = {}
    end
    self.sv.addedPins[data.hostType][data.host.id] = { world = data.world, pinType = data.pinType, host = data.host, uuid = data.uuid, worldOffset = data.worldOffset }
    self.sv.isDirty = true
end

function QuestPinManager.Sv_RemovePin( hostId, hostType )
    g_questPinManagerServer:sv_removePin( { hostId = hostId, hostType = hostType } )
end

function QuestPinManager.sv_removePin( self, data )
    if self.sv.addedPins[data.hostType] then
        self.sv.addedPins[data.hostType][data.hostId] = nil
        self.sv.isDirty = true
    end
end

function QuestPinManager.Sv_InteractableCreated( interactable )
    if g_questManagerServer then
        g_questPinManagerServer:sv_interactableCreated( interactable )
    end
end

function QuestPinManager.sv_interactableCreated( self, interactable )
    for uuid,pinData in pairs( self.sv.watchedUuids ) do
        if interactable.shape then
            if uuid == interactable.shape.uuid then
                self.sv.interactableDataList[interactable.id] = true
                self:sv_addPin( { host = interactable.shape, world = interactable.shape.body:getWorld(), pinType = pinData.pinType, hostType = type( interactable.shape ), uuid = uuid, worldOffset = pinData.worldOffset } )
            end
        end
    end
end

function QuestPinManager.Sv_InteractableDestroyed( interactable )
    g_questPinManagerServer:sv_interactableDestroyed( interactable )
end

function QuestPinManager.sv_interactableDestroyed( self, interactable )
    if self.sv.interactableDataList[interactable.id] then
        self:sv_removePin( { hostId = interactable.id, hostType = "Shape" } )
        self.sv.interactableDataList[interactable.id] = nil
    end
end

-- client
local UpdateTickFrequency = 40 * 5
function QuestPinManager.client_onCreate( self )
    g_questPinManagerClient = self
    self.cl = {}
    self.cl.activeEffectList = {}
    self.cl.missingHosts = {}
    self.cl.tickCounter = 0
end

function QuestPinManager.cl_addPin( self, host, hostId, world, pinType, hostType, worldOffset )
    if sm.exists( host ) then
        local effect = sm.effect.createEffect( pinType )
        effect:setWorld( world )
        effect:setHost( host )
        if worldOffset then
            effect:setOffsetPosition( worldOffset )
        end
        effect:setHostAxisIgnore( sm.effect.axis.all )

        effect:start()
        self.cl.activeEffectList[hostType][host.id] = effect
    else
        if self.cl.missingHosts[hostType] == nil then
            self.cl.missingHosts[hostType] = {}
        end
        local pinData = {}
        pinData.world = world
        pinData.pinType = pinType
        pinData.worldOffset = worldOffset
        pinData.host = host
        self.cl.missingHosts[hostType][hostId] = pinData
    end
end

function QuestPinManager.client_onFixedUpdate( self )

    self.cl.tickCounter = self.cl.tickCounter + 1

    if self.cl.tickCounter >= UpdateTickFrequency then
        self.cl.tickCounter = 0
        local placedPins = {}
        for hostType,hostIdList in pairs( self.cl.missingHosts ) do
            for hostId,pinData in pairs( hostIdList ) do
                if sm.exists( pinData.host ) then
                    self:cl_addPin( pinData.host, hostId, pinData.world, pinData.pinType, hostType, pinData.worldOffset )
                    if placedPins[hostType] == nil then
                        placedPins[hostType] = {}
                    end
                    placedPins[hostType][hostId] = true
                end
            end
        end
        for hostType,hostIdList in pairs( placedPins ) do
            for hostId,_ in pairs( hostIdList ) do
                self.cl.missingHosts[hostType][hostId] = nil
            end
        end
    end
end

function QuestPinManager.client_onClientDataUpdate( self, data )
    for hostType,pinDataList in pairs( data.addedPins ) do
        if self.cl.activeEffectList[hostType] == nil then
            self.cl.activeEffectList[hostType] = {}
        end
        for hostId,pinData in pairs( pinDataList ) do
            if self.cl.activeEffectList[hostType][hostId] == nil or not sm.exists( self.cl.activeEffectList[hostType][hostId] ) or not self.cl.activeEffectList[hostType][hostId]:isPlaying() then
                self:cl_addPin( pinData.host, hostId, pinData.world, pinData.pinType, hostType, pinData.worldOffset )
            end
        end
    end
    local hostIdsToRemove = {}
    for hostType,idList in pairs( self.cl.activeEffectList ) do
        if hostIdsToRemove[hostType] == nil then
            hostIdsToRemove[hostType] = {}
        end
        for hostId,effect in pairs( idList ) do
            if data.addedPins[hostType][hostId] == nil then
                if sm.exists( effect ) and effect:isPlaying() then
                    effect:destroy()
                end
                hostIdsToRemove[hostType][#hostIdsToRemove[hostType]+1] = hostId
            end
            if self.cl.missingHosts[hostType] then
                self.cl.missingHosts[hostType][hostId] = nil
            end
        end
    end
    for hostType,idList in pairs( hostIdsToRemove ) do
        for _,hostId in ipairs( idList ) do
            self.cl.activeEffectList[hostType][hostId] = nil
        end
    end
end