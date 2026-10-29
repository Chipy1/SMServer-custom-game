
AreaReactionManager = class( nil )

function AreaReactionManager.server_onCreate( self )
    g_areaReactionManagerServer = self
    self.sv = {}
    self.sv.saved = sm.storage.load( STORAGE_CHANNEL_AREA_REACTION_MANAGER )
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.completedTriggers = {}
        sm.storage.save( STORAGE_CHANNEL_AREA_REACTION_MANAGER, self.sv.saved )
    end
    self.sv.managedTriggers = {}
    self.sv.dirty = false
end

function AreaReactionManager.server_onUnload( self )
    sm.storage.save( STORAGE_CHANNEL_AREA_REACTION_MANAGER, self.sv.saved )
end

function AreaReactionManager.server_onFixedUpdate( self, timeStep )
    if self.sv.dirty then
        sm.storage.save( STORAGE_CHANNEL_AREA_REACTION_MANAGER, self.sv.saved )
        self.sv.dirty = false
    end
end

function AreaReactionManager.Sv_AlertVoxelDestruction( world, aabbMin, aabbMax )
    if g_areaReactionManagerServer then
        g_areaReactionManagerServer:sv_alertVoxelDestruction( world, aabbMin, aabbMax )
    end
end

function AreaReactionManager.sv_alertVoxelDestruction( self, world, aabbMin, aabbMax )
    local cellX = math.floor( ( aabbMin.x + aabbMax.x ) / ( 2 * 64 ) )
    local cellY = math.floor( ( aabbMin.y + aabbMax.y ) / ( 2 * 64 ) )
    for primaryTag,worlds in pairs( self.sv.managedTriggers ) do
        if primaryTag == "SPAWN_ENEMY_VOLUME_TRIGGER" then
            for x = cellX - 1, cellX + 1 do
                for y = cellY - 1, cellY + 1 do
                    local cellKey = CellKey( x, y )
                    local list = SafeNestedAccess( worlds, world.id, cellKey )
                    if list ~= nil then
                        for id,triggerData in pairs( list ) do
                            if not self.sv.saved.completedTriggers[triggerData.completionKey] and triggerData.params and triggerData.params.reactToVoxelDestruction then
                                local triggerMin = triggerData.areaTrigger:getWorldMin()
                                local triggerMax = triggerData.areaTrigger:getWorldMax()
                                if aabbMin.x <= triggerMax.x and aabbMax.x >= triggerMin.x
                                and aabbMin.y <= triggerMax.y and aabbMax.y >= triggerMin.y
                                and aabbMin.z <= triggerMax.z and aabbMax.z >= triggerMin.z then
                                    local halfExtents = ( triggerMax - triggerMin ) * 0.5
		                            local centerPos = triggerMin + halfExtents
                                    NodeSpawnManager.Sv_ActivateManualSpawnsInArea( centerPos, halfExtents, world, triggerData.params.triggerName )
                                    self.sv.saved.completedTriggers[triggerData.completionKey] = true
                                    self:sv_removeTrigger( primaryTag, world.id, cellKey, id )
                                    self.sv.dirty = true
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function AreaReactionManager.sv_removeTrigger( self, primaryTag, worldId, cellKey, triggerId )
    if self.sv.managedTriggers[primaryTag] and self.sv.managedTriggers[primaryTag][worldId] and self.sv.managedTriggers[primaryTag][worldId][cellKey] then
        if self.sv.managedTriggers[primaryTag][worldId][cellKey][triggerId].areaTrigger then
            self.sv.managedTriggers[primaryTag][worldId][cellKey][triggerId].areaTrigger:destroy()
        end
        self.sv.managedTriggers[primaryTag][worldId][cellKey][triggerId] = nil
    end
end

function AreaReactionManager.Sv_OnCellLoaded( world, x, y )
    if g_areaReactionManagerServer then
        g_areaReactionManagerServer:sv_onCellLoaded( world, x, y )
    end
end

function AreaReactionManager.sv_onCellLoaded( self, world, x, y )
    local nodes = sm.cell.getNodesByTag( x, y, "AREA_REACTION_TRIGGER", world )
    local cellKey = CellKey( x, y )
    for index,node in ipairs( nodes ) do
        local tileKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, node.position )
        local completionKey = tileKey.."|"..cellKey.."|"..index
        if self.sv.saved.completedTriggers[completionKey] == nil then
            local primaryTag = nil
            for _,tag in ipairs( node.tags ) do
                if tag ~= "AREA_REACTION_TRIGGER" then
                    primaryTag = tag
                    break
                end
            end
            if primaryTag then
                local areaTrigger = self:sv_createAreaTrigger( node )
                if self.sv.managedTriggers[primaryTag] == nil then
                    self.sv.managedTriggers[primaryTag] = {}
                end
                if self.sv.managedTriggers[primaryTag][world.id] == nil then
                    self.sv.managedTriggers[primaryTag][world.id] = {}
                end
                if self.sv.managedTriggers[primaryTag][world.id][cellKey] == nil then
                    self.sv.managedTriggers[primaryTag][world.id][cellKey] = {}
                end
                self.sv.managedTriggers[primaryTag][world.id][cellKey][areaTrigger.id] = { areaTrigger = areaTrigger, params = node.params, index = index, completionKey = completionKey }
            else
                sm.log.error( "AreaReactionManager:sv_onCellLoaded - AreaReactionTrigger node is missing identifier tag" )
            end
        end
    end
end

function AreaReactionManager.Sv_OnCellUnloaded( world, x, y )
    if g_areaReactionManagerServer then
        g_areaReactionManagerServer:sv_onCellUnloaded( world, x, y )
    end
end

function AreaReactionManager.sv_onCellUnloaded( self, world, x, y )
    local cellKey = CellKey( x, y )
    for primaryTag,worlds in pairs( self.sv.managedTriggers ) do
        local list = SafeNestedAccess( worlds, world.id, cellKey )
        if list ~= nil then
            for _,triggerData in pairs( list ) do
                sm.areaTrigger.destroy( triggerData.areaTrigger )
            end
            self.sv.managedTriggers[primaryTag][world.id][cellKey] = nil
        end
    end
end

function AreaReactionManager.sv_createAreaTrigger( self, node )
    local areaTrigger = sm.areaTrigger.createBox( node.scale / 2, node.position, node.rotation, sm.areaTrigger.filter.character )
    areaTrigger:bindOnEnter( "sv_t_onEnter", self )
    return areaTrigger
end

function AreaReactionManager.sv_t_onEnter( self, trigger, results )
    local playerFound, playerCharacter = self:sv_resultsContainsPlayer( results )
    if not playerFound or not sm.exists( playerCharacter ) then
        return
    end
    local activatedTrigger = nil
    local world = trigger:getWorld()
	local position = trigger:getWorldPosition()
    local cellX = math.floor( position.x / 64 )
    local cellY = math.floor( position.y / 64 )
    local cellKey = CellKey( cellX, cellY )
    local tileKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, position )
    local tag = nil
    for primaryTag,worlds in pairs( self.sv.managedTriggers ) do
        local triggerData = SafeNestedAccess( worlds, world.id, cellKey, trigger.id )
        if triggerData ~= nil then
            if triggerData.areaTrigger == trigger then
                activatedTrigger = triggerData
                tag = primaryTag
                break
            end
        end
    end
    if activatedTrigger then
        local activationAllowed = false
        if activatedTrigger.params and not activatedTrigger.params.repeatable and not self.sv.saved.completedTriggers[activatedTrigger.completionKey] then
            self.sv.saved.completedTriggers[activatedTrigger.completionKey] = true
            sm.storage.save( STORAGE_CHANNEL_AREA_REACTION_MANAGER, self.sv.saved )
            activationAllowed = true
        elseif activatedTrigger.params == nil or activatedTrigger.params.repeatable then
            activationAllowed = true
        end
        if activationAllowed then
            local triggerData = {
                tileKey = tileKey,
                areaTrigger = activatedTrigger.areaTrigger,
                world = world,
                cellX = cellX,
                cellY = cellY,
                nodeParams = activatedTrigger.params,
                nodeTag = tag
            }
            self:sv_handleTriggers( triggerData )
        end
    end
end

function AreaReactionManager.sv_handleTriggers( self, triggerData )
    if triggerData.nodeTag == "TAGGED_EFFECT_TRIGGER" then
        SetTileStorageFlag( triggerData.tileKey, triggerData.nodeParams.tag )
        EffectManager.Sv_UpdateTagFilteredEffectsForTile( triggerData.world, triggerData.areaTrigger:getWorldPosition(), { triggerData.nodeParams.tag } )
    elseif triggerData.nodeTag == "RELOAD_TILE_TAG" then
        self:sv_reloadTile( triggerData )
    elseif triggerData.nodeTag == "SPAWN_ENEMY_TRIGGER" then
        NodeSpawnManager.Sv_ActivateSpawnTrigger( triggerData.nodeParams.eventName, triggerData.world )
    elseif triggerData.nodeTag == "SPAWN_ENEMY_VOLUME_TRIGGER" then
		local triggerName = triggerData.nodeParams and triggerData.nodeParams.triggerName or nil
		local triggerMin = triggerData.areaTrigger:getWorldMin()
		local triggerMax = triggerData.areaTrigger:getWorldMax()
        local halfExtents = ( triggerMax - triggerMin ) * 0.5
		local centerPos = triggerMin + halfExtents
        NodeSpawnManager.Sv_ActivateManualSpawnsInArea( centerPos, halfExtents, triggerData.world, triggerName )
    elseif triggerData.nodeTag == "DRILL_SPAWNER_ENCOUNTER" then
        self:sv_drillSpawnerEncounter( triggerData )
    elseif triggerData.nodeTag == "COMBAT_ENCOUNTER_TRIGGER" then
        self:sv_combatEncounter( triggerData )
    end
    if triggerData.nodeParams == nil or not triggerData.nodeParams.repeatable then
        self:sv_removeTrigger( triggerData.nodeTag, triggerData.world.id, CellKey( triggerData.cellX, triggerData.cellY ), triggerData.areaTrigger.id )
    end
end

function AreaReactionManager.sv_e_forwardClientMessages( self, params )
    self.network:sendToClients( params.clientFunction, params )
end

function AreaReactionManager.sv_reloadTile( self, triggerData )
    SetTileStorageFlag( triggerData.tileKey, triggerData.nodeParams.tag )
    local position = triggerData.areaTrigger:getWorldPosition()
    EffectManager.Sv_UpdateTagFilteredEffectsForTile( triggerData.world, position, { triggerData.nodeParams.tag } )
    local xMin,xMax,yMin,yMax = GetTileRanges( position, triggerData.world.id )
    if xMin == nil or xMax == nil or yMin == nil or yMax == nil then
        sm.log.warning( "AreaReactionManager.sv_reloadTile - Failed to get tile ranges for position " .. tostring(position) .. " in world " .. tostring(triggerData.world.id) )
        return
    end
    local params = {
        xMin = xMin,
        xMax = xMax,
        yMin = yMin,
        yMax = yMax,
        world = triggerData.world,
        clientFunction = "cl_n_reloadTile"
    }
    sm.event.sendToScriptableObject( g_areaReactionManagerServer.scriptableObject, "sv_e_forwardClientMessages", params )
end

function AreaReactionManager.sv_resultsContainsPlayer( self, results )
	for _,result in ipairs( results ) do
		if sm.exists( result ) then
			if result:isPlayer() then
				return true, result
			end
		end
	end
	return false, nil
end

function AreaReactionManager.sv_drillSpawnerEncounter( self, triggerData )
    local uid = sm.uuid.new( "6fd85483-29c3-4d08-a700-58acb158b880" )
    sm.scriptableObject.createScriptableObject( uid, { position = triggerData.areaTrigger:getWorldPosition(), amount = triggerData.nodeParams.amount }, triggerData.world )
end

function AreaReactionManager.sv_combatEncounter( self, triggerData )
    local encounterParams = {
        position = triggerData.areaTrigger:getWorldPosition(),
        world = triggerData.world,
        kinematicEventTrigger = triggerData.nodeParams.kinematicEventTrigger,
        name = tostring( triggerData.areaTrigger:getWorldPosition() )..tostring( triggerData.world ),
        preset = triggerData.nodeParams.preset,
        marked = false
    }
    CombatEncounterManager.Sv_StartEncounter( encounterParams )
end

-- Client

function AreaReactionManager.cl_n_reloadTile( self, params )
    for x = params.xMin, params.xMax do
        for y = params.yMin, params.yMax do
            sm.world.reloadCell( params.world, x, y )
        end
    end
end