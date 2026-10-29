GlowstickManager = class( nil )

GlowstickManager.Lifetime = 40 * 1800 -- 30 minutes
GlowstickManager.InteractableTriggerRadius = 0.3

function GlowstickManager.server_onCreate( self )
    self.sv = {}
    self.sv.readyWorlds = {}
    self.sv.saved = sm.storage.load( STORAGE_CHANNEL_GLOWSTICK_MANAGER )
    if self.sv.saved == nil then
        self.sv.saved = {
            triggers = {},
            triggerIdCounter = 1
        }
    end
    self.network:setClientData( self.sv.saved )

    g_glowstickManager = self
end

function GlowstickManager.Sv_WorldReady( world )
    if g_glowstickManager then
        sm.event.sendToScriptableObject( g_glowstickManager.scriptableObject, "sv_e_worldReady", world, sm.event.types.instant )
    end
end

function GlowstickManager.sv_e_worldReady( self, world )
    self.sv.readyWorlds[world.id] = true
end

function GlowstickManager.Sv_WorldUnloaded( world )
    if g_glowstickManager then
        sm.event.sendToScriptableObject( g_glowstickManager.scriptableObject, "sv_e_worldUnloaded", world, sm.event.types.instant )
    end
end

function GlowstickManager.sv_e_worldUnloaded( self, world )
    self.sv.readyWorlds[world.id] = nil
end

function GlowstickManager.client_onCreate( self )
    self.cl = {
        triggers = {},
        readyWorlds = {},
    }

    g_glowstickManagerClient = self
end

function GlowstickManager.Cl_WorldReady( world )
    if g_glowstickManagerClient then
        sm.event.sendToScriptableObject( g_glowstickManagerClient.scriptableObject, "cl_e_worldReady", world, sm.event.types.instant )
    end
end

function GlowstickManager.cl_e_worldReady( self, world )
    if self.cl.readyWorlds[world.id] then
        return
    end
    self.cl.readyWorlds[world.id] = true
    if self.cl.clientData then
        self:client_onClientDataUpdate( self.cl.clientData )
    end
end

function GlowstickManager.client_onLocalPlayerChangedWorld( self )

    -- Cant swap world in creative
   if CreativeGame ~= nil then
        return
    end

    -- The local player can only be in one world at a time on the client; a
    -- world becomes ready again when its terrain reloads via Cl_WorldReady.

    self.cl.readyWorlds = {}

    local currentWorld = sm.localPlayer.getWorld()
    if currentWorld then
        self:cl_e_worldReady( currentWorld )
    end
end

function GlowstickManager.server_onFixedUpdate( self )
    if IsEmptyTable( self.sv.saved.triggers ) then
        return
    end

    local currentTick = sm.game.getCurrentTick()

    -- gather timed out
    local timedOutTriggers = {}
    for managerId, trigger in pairs( self.sv.saved.triggers ) do
        if self.sv.readyWorlds[trigger.input.world.id] and currentTick >= trigger.destroyTick then
            timedOutTriggers[#timedOutTriggers+1] = managerId
        end
    end

    if #timedOutTriggers > 0 then
        for _, managerId in ipairs( timedOutTriggers ) do
            self.sv.saved.triggers[managerId] = nil
        end
        sm.storage.save( STORAGE_CHANNEL_GLOWSTICK_MANAGER, self.sv.saved )
        self.network:setClientData( self.sv.saved )
    end
end

function GlowstickManager.cl_hostLoaded( self )
    self:client_onClientDataUpdate( self.cl.clientData )
end

function GlowstickManager.Sv_CreateGlowstick( input )
	if g_glowstickManager then
        sm.event.sendToScriptableObject( g_glowstickManager.scriptableObject, "sv_e_createTrigger", input, sm.event.types.instant )
	end
end

function GlowstickManager.sv_e_createTrigger( self, input )

    if not self.sv.readyWorlds[input.world.id] then
        return
    end

    if input.target ~= nil and not sm.exists( input.target ) then
        return
    end

    local destroyTick
    if input.lifetime then
        destroyTick = sm.game.getCurrentTick() + input.lifetime
    else
        destroyTick = sm.game.getCurrentTick() + self.Lifetime
    end

    local isKinematic = input.target and type( input.target ) == "Harvestable" and input.target:isKinematic()
    local kinematicInitialHash = nil
    if isKinematic then
        kinematicInitialHash = input.target:getInitialHash()
    end

    local id = self.sv.saved.triggerIdCounter
    self.sv.saved.triggers[id] = {
        input = input,
        destroyTick = destroyTick,
        isHostKinematic = isKinematic,
        kinematicInitialHash = kinematicInitialHash
    }

    if input.target and type( input.target ) ~= "VoxelTerrain" then
        local positionOffset = input.target:transformPoint( input.hitPos )
        local localNormal = input.target:transformDirection( input.hitNormal )
        self.sv.saved.triggers[self.sv.saved.triggerIdCounter].localNormal = localNormal
        self.sv.saved.triggers[self.sv.saved.triggerIdCounter].positionOffset = positionOffset
    end

    self.sv.saved.triggerIdCounter = self.sv.saved.triggerIdCounter + 1
    sm.storage.save( STORAGE_CHANNEL_GLOWSTICK_MANAGER, self.sv.saved )

    self.network:setClientData( self.sv.saved )
end

function GlowstickManager.cl_attachedTrigger( self, trigger )
    local target = trigger.input.target

    trigger.areaTrigger = sm.areaTrigger.createAttachedSphere( target, GlowstickManager.InteractableTriggerRadius, trigger.positionOffset,
        sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), trigger.localNormal ), nil, nil, sm.areaTrigger.areaTriggerProxyType.interactable )

    if sm.isHost then
        trigger.areaTrigger:bindOnHostUnload( "cl_trigger_onHostUnload", self )
    end
    trigger.areaTrigger:bindOnHostDestroy( "cl_trigger_onHostDestroy", self )
    trigger.areaTrigger:bindCanInteract( "cl_trigger_canInteract", self )
    trigger.areaTrigger:bindCanErase( "cl_trigger_clientCanErase", self )
    trigger.areaTrigger:bindOnErase( "cl_trigger_onErase", self )

    trigger.glowEffect = sm.effect.createEffect( "GlowstickProjectile - Hit", target )
    trigger.glowEffect:setOffsetPosition( trigger.positionOffset - ( trigger.localNormal * 0.1 ) )
    trigger.glowEffect:setOffsetRotation( sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), trigger.localNormal ) )
    trigger.glowEffect:start()
end

function GlowstickManager.cl_detachedTrigger( self, trigger )
    trigger.areaTrigger = sm.areaTrigger.createSphere( GlowstickManager.InteractableTriggerRadius, trigger.input.hitPos, sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), trigger.input.hitNormal ),
        sm.areaTrigger.filter.voxelTerrain, nil, trigger.input.world, sm.areaTrigger.areaTriggerProxyType.interactable )

    trigger.areaTrigger:bindCanInteract( "cl_trigger_canInteract", self )
    trigger.areaTrigger:bindCanErase( "cl_trigger_clientCanErase", self )
    if sm.isHost then
        trigger.areaTrigger:bindOnDestroy( "cl_trigger_onDestroy", self )
    end
    trigger.areaTrigger:bindOnErase( "cl_trigger_onErase", self )

    trigger.glowEffect = sm.effect.createEffect( "GlowstickProjectile - Hit" )
    trigger.glowEffect:setWorld( trigger.input.world )
    trigger.glowEffect:setPosition( trigger.input.hitPos - sm.vec3.new( 0, 0, 0.1 ) )
    trigger.glowEffect:setRotation( sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), trigger.input.hitNormal ) )
    trigger.glowEffect:start()
end


function GlowstickManager.client_onClientDataUpdate( self, data )
    -- if new area triggers have been added, create them here
    self.cl.clientData = data

    for managerId, trigger in pairs( data.triggers ) do
        if self.cl.readyWorlds[trigger.input.world.id] and ( self.cl.triggers[managerId] == nil or ( self.cl.triggers[managerId].areaTrigger == nil and self.cl.triggers[managerId].input.target ) ) then
            self.cl.triggers[managerId] = trigger
            local voxelTarget = type( trigger.input.target ) == "VoxelTerrain"

            if (not voxelTarget) and trigger.input.target then
                if trigger.isHostKinematic and not sm.exists( trigger.input.target ) then
                    local kinematicByHash = sm.harvestable.getKinematicByInitialHash( trigger.kinematicInitialHash )
                    if kinematicByHash then
                        trigger.input.target = kinematicByHash
                    end
                end
                if sm.exists( trigger.input.target ) then
                    self:cl_attachedTrigger( self.cl.triggers[managerId] )
                end
            elseif voxelTarget or trigger.input.target == nil then
                self:cl_detachedTrigger( self.cl.triggers[managerId] )
                if voxelTarget then
                    self.cl.triggers[managerId].areaTrigger:setVoxelDestructible( true )
                end
            end
        end
    end

    -- if client has any triggers that are not in the data from server, remove them.
    for managerId, trigger in pairs( self.cl.triggers ) do
        if not data.triggers[managerId] then
            if trigger.areaTrigger and sm.exists( trigger.areaTrigger ) then
                sm.areaTrigger.destroy( trigger.areaTrigger )
            end
            if trigger.glowEffect and sm.exists( trigger.glowEffect ) then
                trigger.glowEffect:destroy()
            end
            trigger.areaTrigger = nil
            trigger.glowEffect = nil
        end
    end
end

function GlowstickManager.client_onFixedUpdate( self )
    for managerId, trigger in pairs( self.cl.triggers ) do
        if self.cl.readyWorlds[trigger.input.world.id] and self.cl.triggers[managerId].input.world == sm.localPlayer.getWorld() then
            if self.cl.triggers[managerId].areaTrigger == nil then
                if ( trigger.isHostKinematic and sm.harvestable.getKinematicByInitialHash( trigger.kinematicInitialHash ) ) or sm.exists( trigger.input.target ) then
                    self:cl_hostLoaded()
                    break
                end
            end
        end
    end
end

function GlowstickManager.cl_trigger_canInteract( self )
    if not sm.localPlayer.secondaryInteractBusy() then
        sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Attack", true ), "#{INTERACTION_DESTROY}" )
    end
    return true
end

function GlowstickManager.cl_trigger_clientCanErase( self )
    return true
end

-- removes the areatrigger and effect but does not remove the glowstick instance.
function GlowstickManager.cl_remove( self, triggerId )
    for managerId, trigger in pairs( self.cl.triggers ) do
        if trigger.areaTrigger and trigger.areaTrigger.id == triggerId then
            if trigger.areaTrigger and sm.exists( trigger.areaTrigger ) then
                sm.areaTrigger.destroy( trigger.areaTrigger )
            end
            if trigger.glowEffect and sm.exists( trigger.glowEffect ) then
                trigger.glowEffect:destroy()
            end
            trigger.areaTrigger = nil
            trigger.glowEffect = nil
            break
        end
    end
end

-- when the shape is unloaded on the host, remove the areatrigger and effect
function GlowstickManager.cl_trigger_onHostUnload( self, triggerId, lastPosition, lastRotation )
    assert( sm.isHost )
    self:cl_remove( triggerId )
end

-- when the shape is destroyed on the host, issue a destroy. if destroyed on a client, only remove.
function GlowstickManager.cl_trigger_onHostDestroy( self, triggerId, lastPosition, lastRotation, world )
    if sm.isHost then
        for managerId, value in pairs( self.cl.triggers ) do
            if value.areaTrigger and value.areaTrigger.id == triggerId then
                self.network:sendToServer( "sv_n_destroy", { id = managerId, position = lastPosition, world = world } )
                break
            end
        end
    else
        self:cl_remove( triggerId )
    end
end

-- when anyone erases a glowstick, issue a destroy
function GlowstickManager.cl_trigger_onErase( self, triggerId, lastPosition, lastRotation, world )
    for managerId, value in pairs( self.cl.triggers ) do
        if value.areaTrigger and value.areaTrigger.id == triggerId then
            self.network:sendToServer( "sv_n_destroy", { id = managerId, position = lastPosition, world = world } )
            break
        end
    end
end

-- destroyed by voxel addition
function GlowstickManager.cl_trigger_onDestroy( self, triggerId, lastPosition, lastRotation, world )
    assert( sm.isHost)
    for managerId, value in pairs( self.cl.triggers ) do
        if value.areaTrigger and value.areaTrigger.id == triggerId then
            self.network:sendToServer( "sv_n_destroy", { id = managerId, position = lastPosition, world = world } )
            break
        end
    end
end

function GlowstickManager.sv_n_destroy( self, data )
    sm.effect.playEffect( "GlowstickProjectile - Bounce", data.position, nil, nil, nil, nil, nil, data.world )

    self.sv.saved.triggers[data.id] = nil
    sm.storage.save( STORAGE_CHANNEL_GLOWSTICK_MANAGER, self.sv.saved )
    self.network:setClientData( self.sv.saved )
end

function GlowstickManager.Sv_GetGlowstickIds( aabbMin, aabbMax, inout_glowstickIds, getOnlyOnVoxels )
    if g_glowstickManager then
        g_glowstickManager:sv_getGlowstickIds( aabbMin, aabbMax, inout_glowstickIds, getOnlyOnVoxels )
    end
end

function GlowstickManager.sv_getGlowstickIds( self, aabbMin, aabbMax, inout_glowstickIds, getOnlyOnVoxels )
    for managerId, trigger in pairs( self.sv.saved.triggers ) do
        if getOnlyOnVoxels == false or ( trigger.input.target and type( trigger.input.target ) == "VoxelTerrain" ) then
			local pos = trigger.input.hitPos
			if pos.x >= aabbMin.x and pos.y >= aabbMin.y and pos.z >= aabbMin.z and pos.x <= aabbMax.x and pos.y <= aabbMax.y and pos.z <= aabbMax.z then
                inout_glowstickIds[managerId] = true
            end
        end
    end
end

function GlowstickManager.Sv_CheckVoxelContact( glowstickIds )
    if g_glowstickManager then
        sm.event.sendToScriptableObject( g_glowstickManager.scriptableObject, "sv_e_checkVoxelContact", glowstickIds )
    end
end


-- loop over area triggers and check if they are attached to a voxel terrain that has been destroyed
function GlowstickManager.sv_e_checkVoxelContact( self, ids )
    local destroyedTriggers = {}
    for managerId, _ in pairs( ids ) do
        local clientTrigger = self.cl.triggers[managerId]
        local hostClientTrigger = clientTrigger and clientTrigger.areaTrigger
        if hostClientTrigger and sm.exists( hostClientTrigger ) then
            if not hostClientTrigger:hasVoxelTerrainContact() then
                destroyedTriggers[#destroyedTriggers+1] = managerId
            end
        end
    end

    if #destroyedTriggers > 0 then
        for _, managerId in pairs( destroyedTriggers ) do
            if self.sv.saved.triggers[managerId] then
                local hitPos = self.sv.saved.triggers[managerId].input.hitPos
                local world = self.sv.saved.triggers[managerId].input.world
                sm.effect.playEffect( "GlowstickProjectile - Bounce", hitPos, nil, nil, nil, nil, nil, world )
                self.sv.saved.triggers[managerId] = nil
            end
        end
        sm.storage.save( STORAGE_CHANNEL_GLOWSTICK_MANAGER, self.sv.saved )
        self.network:setClientData( self.sv.saved )
    end
end
