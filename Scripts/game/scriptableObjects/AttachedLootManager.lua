dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )

AttachedLootManager = class( nil )

AttachedLootManager.InteractableSphereRadius = 0.3
AttachedLootManager.MaximumAttachedLootCount = 300

function AttachedLootManager.server_onCreate( self )
    g_AttachedLootManager = self
    self.sv = {}
    self.sv.saved = sm.storage.load( STORAGE_CHANNEL_ATTACHED_LOOT_MANAGER )
    if self.sv.saved == nil then
        self.sv.saved = {
            triggerIdCounter = 0,
            kinematics = {},
            temporaryKinematics = {}
        }
    end
    self:sv_setClientData()
end

function AttachedLootManager.server_onUnload( self )
    for initialHash, _ in pairs( self.cl.kinematics ) do
        if self.sv.saved.temporaryKinematics[initialHash] == true then
            self.sv.saved.kinematics[initialHash] = nil
            self.sv.saved.temporaryKinematics[initialHash] = nil
        end
    end
    sm.storage.save( STORAGE_CHANNEL_ATTACHED_LOOT_MANAGER, self.sv.saved )
end

function AttachedLootManager.sv_onCellLoaded( self, x, y )
    local harvestables = sm.cell.getHarvestables( x, y )
    for _, harvestable in ipairs( harvestables ) do
        if harvestable:isKinematic() then
            local initialHash = harvestable:getInitialHash()
            if self.sv.saved.kinematics[initialHash] ~= nil then
                sm.event.sendToScriptableObject( self.scriptableObject, "sv_e_attachedLootHostLoaded" )
                return
            end
        end
    end
end

function AttachedLootManager.sv_e_attachedLootHostLoaded( self )
    self:sv_setClientData()
end

function AttachedLootManager.sv_setClientData( self )       
    local lootCount = 0
    for hash, kinematicInstance in pairs( self.sv.saved.kinematics ) do
        kinematicInstance.harv = sm.harvestable.getKinematicByInitialHash( hash )
        lootCount = lootCount + kinematicInstance.count
    end
    if lootCount > AttachedLootManager.MaximumAttachedLootCount then
        local list = {}
        for hash, kinematicInstance in pairs( self.sv.saved.kinematics ) do
            table.insert( list, { hash, kinematicInstance.tick } )
        end
        table.sort( list, function( a, b )
            return a[2] < b[2] -- sort by tick
        end )
        for _, value in ipairs( list ) do
            local count = self.sv.saved.kinematics[value[1]].count
            self.sv.saved.kinematics[value[1]] = nil
            lootCount = lootCount - count
            if lootCount <= AttachedLootManager.MaximumAttachedLootCount then
                break
            end
        end
    end

    self.network:setClientData( self.sv.saved.kinematics )
end

function AttachedLootManager.sv_e_createLoot( self, projectileInput )
    if projectileInput.target ~= nil and not sm.exists( projectileInput.target ) then
        sm.log.error( "AttachedLootManager had no target" )
        return
    end
    local isKinematic = projectileInput.target and type( projectileInput.target ) == "Harvestable" and projectileInput.target:isKinematic()
    if not isKinematic then
        sm.log.error( "AttachedLootManager received non kinematic target" )
        return
    end

    local kinematicInitialHash = projectileInput.target:getInitialHash()

    if self.sv.saved.kinematics[kinematicInitialHash] == nil then
        self.sv.saved.kinematics[kinematicInitialHash] = {
            tick = nil,
            count = 0,
            loot = {}
        }
        local kinematic = sm.harvestable.getKinematicByInitialHash( kinematicInitialHash )
        if kinematic and not kinematic:isCellKinematic() then
            self.sv.saved.temporaryKinematics[kinematicInitialHash] = true
        end
    end

    local positionOffset = projectileInput.target:transformPoint( projectileInput.pos )
    local localNormal = projectileInput.target:transformDirection( projectileInput.normal )    

    self.sv.saved.kinematics[kinematicInitialHash].loot[self.sv.saved.triggerIdCounter] = {
        pos = positionOffset,
        normal = localNormal,
        uid = projectileInput.uid,
        qty = projectileInput.qty
    }
    self.sv.saved.kinematics[kinematicInitialHash].tick = sm.game.getCurrentTick()
    self.sv.saved.kinematics[kinematicInitialHash].count = self.sv.saved.kinematics[kinematicInitialHash].count + 1
    self.sv.saved.triggerIdCounter = self.sv.saved.triggerIdCounter + 1

    sm.storage.save( STORAGE_CHANNEL_ATTACHED_LOOT_MANAGER, self.sv.saved )
    self:sv_setClientData()
end

-- host client only
function AttachedLootManager.cl_trigger_onHostUnload( self, triggerId, lastPosition, lastRotation )
    if sm.isHost and self.cl.triggerToTemporaryKinematic then
        local hostHash = self.cl.triggerToTemporaryKinematic[triggerId]
        if hostHash  then
            self.network:sendToServer( "sv_n_clearKinematic", hostHash )
            self.cl.triggerToTemporaryKinematic[triggerId] = nil
        end
    end
end

function AttachedLootManager.sv_n_clearKinematic( self, initialHash )
    self.sv.saved.kinematics[initialHash] = nil
    self.sv.saved.temporaryKinematics[initialHash] = nil
    sm.storage.save( STORAGE_CHANNEL_ATTACHED_LOOT_MANAGER, self.sv.saved )
end

function AttachedLootManager.sv_n_harvest( self, params, player )
    if self.sv.saved.kinematics[params.initialHash] == nil or self.sv.saved.kinematics[params.initialHash].loot[params.lootInstance] == nil then
        return
    end

    local lootInstance = self.sv.saved.kinematics[params.initialHash].loot[params.lootInstance]
    local container = player:getInventory()
    if sm.container.beginTransaction() then
        sm.container.collect( container, lootInstance.uid, lootInstance.qty )
        if sm.container.endTransaction() then
            sm.event.sendToPlayer( player, "sv_e_onLoot", { uuid = lootInstance.uid, quantity = lootInstance.qty, pos = params.pos -  sm.vec3.new( 0,0,0.3 ) } )

            --remove loot
            self.sv.saved.kinematics[params.initialHash].loot[params.lootInstance] = nil
            self.sv.saved.kinematics[params.initialHash].count = self.sv.saved.kinematics[params.initialHash].count - 1
            assert( self.cl.kinematics[params.initialHash].count >= 0 )

            --remove kinematic if none attached
            if self.sv.saved.kinematics[params.initialHash].count == 0 then
                self.sv.saved.kinematics[params.initialHash] = nil
            end
            sm.storage.save( STORAGE_CHANNEL_ATTACHED_LOOT_MANAGER, self.sv.saved )

            self.network:sendToClients( "cl_n_destroyLoot", params )
        else
            self.network:sendToClient( player, "cl_n_onInventoryFull" )
        end
    end
end


-- CLIENT

function AttachedLootManager.client_onCreate( self )
    g_attachedLootManagerClient = self
    self.cl = {
        kinematics = {}
    }
end

function AttachedLootManager.client_onClientDataUpdate( self, data )
    if IsEmptyTable( data ) then
        return
    end

    for kinematicHash, _ in pairs( self.cl.kinematics ) do
        if data[kinematicHash] == nil then
            self.cl.kinematics[kinematicHash] = nil
        end
    end

    -- then update our data to match what does exist on the server
    for kinematicHash, kinematicInstance in pairs( data ) do
        if self.cl.kinematics[kinematicHash] == nil then
            self.cl.kinematics[kinematicHash] = kinematicInstance --received new kinematic with attachments
        end
        self.cl.kinematics[kinematicHash].count = kinematicInstance.count -- how many pieces of loot are attached to the kinematic
        self.cl.kinematics[kinematicHash].harv = kinematicInstance.harv -- this tells us which kinematic currently exists on the server with this hash, nil if none

        for managerId, lootInstance in pairs( kinematicInstance.loot ) do
            if self.cl.kinematics[kinematicHash].loot[managerId] == nil then
                self.cl.kinematics[kinematicHash].loot[managerId] = kinematicInstance.loot[managerId]
            end
            if self.cl.kinematics[kinematicHash].harv ~= nil then
                if sm.exists( self.cl.kinematics[kinematicHash].harv ) then
                    if not sm.exists( self.cl.kinematics[kinematicHash].loot[managerId].areaTrigger) then
                        self:cl_attachedLoot( self.cl.kinematics[kinematicHash].loot[managerId], self.cl.kinematics[kinematicHash].harv ) -- if the loot has not been created client side, do it now
                    end
                end
            end
        end
    end
end

function AttachedLootManager.cl_attachedLoot( self, loot, harvestable )
    loot.areaTrigger = sm.areaTrigger.createAttachedSphere( harvestable, self.InteractableSphereRadius,
        loot.pos + (loot.normal * 0.25 ), nil, nil, nil, sm.areaTrigger.areaTriggerProxyType.interactable )

    if sm.isHost and not harvestable.isCellKinematic then
        self.cl.triggerToTemporaryKinematic = self.cl.triggerToTemporaryKinematic or {}
        self.cl.triggerToTemporaryKinematic[loot.areaTrigger.id] = harvestable:getInitialHash()
    end

    loot.areaTrigger:bindCanInteract( "cl_trigger_canInteract", self )
    loot.areaTrigger:bindCanErase( "cl_trigger_clientCanErase", self )
    loot.areaTrigger:bindOnErase( "cl_trigger_onErase", self )
    loot.areaTrigger:bindOnInteract( "cl_trigger_onInteract", self )
    if sm.isHost then
        loot.areaTrigger:bindOnHostUnload( "cl_trigger_onHostUnload", self )
    end
    loot.areaTrigger:setEraseTime( 0.0 )
    loot.areaTrigger:setDestroyOnErase( false )
    
    local scale = 0.25
    local lootUid = loot.uid
    if sm.item.isTool( lootUid ) then
		lootUid = GetToolProxyItem( lootUid )
	end

    if lootUid == obj_outfitpackage_common then
		loot.itemEffect = sm.effect.createEffect( "Loot - OutfitCommonGlowItem", harvestable )
	elseif lootUid == obj_outfitpackage_rare then
		loot.itemEffect = sm.effect.createEffect( "Loot - OutfitRareGlowItem", harvestable )
	elseif lootUid == obj_outfitpackage_epic then
		loot.itemEffect = sm.effect.createEffect( "Loot - OutfitEpicGlowItem", harvestable )
	else
		if lootUid then
			local bounds = sm.item.getShapeSize( lootUid )
			scale = sm.construction.constants.subdivideRatio / ( ( bounds.x + bounds.y + bounds.z ) / 3.0 );
		end
		if self.cl.epic then
			loot.itemEffect = sm.effect.createEffect( "EpicLoot - GlowItem", harvestable )
		else
			loot.itemEffect = sm.effect.createEffect( "Loot - GlowItem", harvestable )
		end
	end

    if lootUid then
        loot.itemEffect:setParameter( "uuid", lootUid )
        loot.itemEffect:setParameter( "Color", sm.shape.getShapeTypeColor( lootUid ) )
    end

    loot.itemEffect:setScale( sm.vec3.new( scale, scale, scale ) )
    loot.itemEffect:setOffsetPosition( loot.pos + (loot.normal * 0.25 ) )
    loot.itemEffect:setOffsetRotation( sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, -1 ) ) )
    loot.itemEffect:start()
end

function AttachedLootManager.cl_trigger_canInteract( self, trigger )
    for initialHash, kinematicInstance in pairs( self.cl.kinematics ) do
        for managerId, lootInstance in pairs( kinematicInstance.loot ) do
            if sm.exists( lootInstance.areaTrigger ) and lootInstance.areaTrigger == trigger then
                local keyBindingText = GetInteractionKeybinding()
                sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_PICK_UP} #FFFFC0" .. sm.shape.getShapeTitle( lootInstance.uid ) .. "#FFFFFF"..( lootInstance.qty > 1 and (" x " .. lootInstance.qty ) or "" ) )
                return true
            end
        end
    end
    return false
end

function AttachedLootManager.cl_trigger_clientCanErase( self )
    return true
end

function AttachedLootManager.cl_trigger_onErase( self, triggerId, lastPosition, lastRotation )
    for initialHash, kinematicInstance in pairs( self.cl.kinematics ) do
        for managerId, lootInstance in pairs( kinematicInstance.loot ) do
            if sm.exists( lootInstance.areaTrigger ) and lootInstance.areaTrigger.id == triggerId then
                sm.event.sendToScriptableObject( self.scriptableObject, "cl_e_harvest", { initialHash = initialHash, lootInstance = managerId, pos = lastPosition } )
                break
            end
        end
    end
end

function AttachedLootManager.cl_trigger_onInteract( self, trigger, character, state )
	if state then
        for initialHash, kinematicInstance in pairs( self.cl.kinematics ) do
            for managerId, lootInstance in pairs( kinematicInstance.loot ) do
                if sm.exists( lootInstance.areaTrigger ) and lootInstance.areaTrigger == trigger then
                    sm.event.sendToScriptableObject( self.scriptableObject, "cl_e_harvest", { initialHash = initialHash, lootInstance = managerId, pos = self.cl.kinematics[initialHash].loot[managerId].areaTrigger:getWorldPosition() } )
                    break
                end
            end
        end
	end
end

function AttachedLootManager.cl_e_harvest( self, params )
    self.network:sendToServer( "sv_n_harvest", params )
end

function AttachedLootManager.cl_kinematicCreated( self, kinematic )
    if not sm.isHost then
        local hash = kinematic:getInitialHash()
        if self.cl.kinematics[hash] then
            self:client_onClientDataUpdate( self.cl.kinematics )
        end
    end
end

function AttachedLootManager.cl_n_destroyLoot( self, params )
    if not ( self.cl.kinematics[params.initialHash] and self.cl.kinematics[params.initialHash].loot[params.lootInstance] ) then
        return
    end

    local lootInstance = self.cl.kinematics[params.initialHash].loot[params.lootInstance]

    --remove trigger and effect
    if lootInstance.areaTrigger and sm.exists( lootInstance.areaTrigger ) then
        sm.areaTrigger.destroy( lootInstance.areaTrigger )
    end
    if lootInstance.itemEffect and sm.exists( lootInstance.itemEffect ) then
            lootInstance.itemEffect:destroy()
    end

    --remove loot
    self.cl.kinematics[params.initialHash].loot[params.lootInstance] = nil
    self.cl.kinematics[params.initialHash].count = self.cl.kinematics[params.initialHash].count - 1
    assert( self.cl.kinematics[params.initialHash].count >= 0 )

    --remove kinematic if none attached
    if self.cl.kinematics[params.initialHash].count == 0 then
        self.cl.kinematics[params.initialHash] = nil
    end
end

function AttachedLootManager.Sv_OnCellLoaded( x, y )
    if g_AttachedLootManager then
        g_AttachedLootManager:sv_onCellLoaded( x, y )
    end
end

function AttachedLootManager.Sv_CreateAttachedLoot( projectileInput )
	if g_AttachedLootManager then
        sm.event.sendToScriptableObject( g_AttachedLootManager.scriptableObject, "sv_e_createLoot", projectileInput )
	end
end

function AttachedLootManager.Cl_KinematicCreated( kinematic )
    if g_attachedLootManagerClient then
        g_attachedLootManagerClient:cl_kinematicCreated( kinematic )
    end
end
