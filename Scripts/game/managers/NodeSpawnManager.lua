dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

NodeSpawnManager = class( nil )

local RangeBasedBudget = 15 -- Number of range based spawns checks allowed per tick
local NodeTickCooldown = 80 -- How often (in ticks) we are allowed to check the same node

function NodeSpawnManager.server_onCreate( self )
    g_nodeSpawnManager = self
    self.sv = {}
    self.sv.saved = sm.storage.load( STORAGE_CHANNEL_QUEST_SPAWN_MANAGER ) or {}
    self.sv.saved.primedTriggers = self.sv.saved.primedTriggers or {}
    self.sv.saved.expendedSpawners = self.sv.saved.expendedSpawners or {}
    self.sv.saved.areaLocationTriggers = self.sv.saved.areaLocationTriggers or {}
    self:sv_save()

    self.sv.inactiveUnitSpawners = {}
    self.sv.inactiveHarvestableSpawners = {}
    self.sv.inactiveQuestEventSpawners = {}
    self.sv.inactiveBlueprintSpawners = {}
    self.sv.discoveredRangeSpawns = {}
end

function NodeSpawnManager.sv_save( self )
    sm.storage.save( STORAGE_CHANNEL_QUEST_SPAWN_MANAGER, self.sv.saved )
end

function NodeSpawnManager.Sv_ActivateManualSpawnsInArea( centerPos, halfExtents, world, triggerName )
    if g_nodeSpawnManager then
        g_nodeSpawnManager:sv_activateManualSpawnsInArea( centerPos, halfExtents, world, triggerName )
    end
end

function NodeSpawnManager.sv_activateManualSpawnsInArea( self, centerPos, halfExtents, world, triggerName )
    if self.sv.saved.areaLocationTriggers[world.id.."|"..tostring( centerPos ).."|"..tostring( halfExtents )] then
        return
    end
    local xmin, xmax, ymin, ymax = GetTileRanges( centerPos, world.id )
    local nodesInArea = {}
    local cablebotPocketsInArea = {}

    for x = xmin, xmax do
        for y = ymin, ymax do
            local nodes = sm.cell.getNodesByTag( x, y, "SPAWNABLE_UNIT", world )
            for _,node in ipairs( nodes ) do
                if node.params and node.params.manualSpawn and node.params.triggerName == triggerName then -- triggerName can match on both being nil
                    if IsPositionInBox( node.position, centerPos, halfExtents ) then
                        nodesInArea[#nodesInArea+1] = node
                    end
                end
            end
            local cablebotPocketNodes = sm.cell.getNodesByTag( x, y, "CABLEBOTPOCKET", world )
            for _, node in ipairs( cablebotPocketNodes ) do
                if ( node.params and node.params.triggerName or nil ) == triggerName then -- triggerName can match on both being nil
                    if IsPositionInBox( node.position, centerPos, halfExtents ) then
                        cablebotPocketsInArea[#cablebotPocketsInArea+1] = node
					end
                end
            end
        end
    end

    for _,node in ipairs( nodesInArea ) do
        local unitParams = {}
        unitParams.spawnParams = node.params or {}
        unitParams.spawnParams.temporary = false
        unitParams.spawnParams.roaming = true
        unitParams.node = node
        sm.event.sendToWorld( world, "sv_e_spawnNodeUnit", unitParams, sm.event.types.instant )
    end

    for _, node in ipairs( cablebotPocketsInArea ) do
        sm.event.sendToWorld( world, "sv_e_spawnCablebotPocket", node, sm.event.types.instant )
    end

    self.sv.saved.areaLocationTriggers[world.id.."|"..tostring( centerPos ).."|"..tostring( halfExtents )] = true
end

function NodeSpawnManager.Sv_ActivateSpawnTrigger( triggerName, world, nextLoad )
    if g_nodeSpawnManager then
        g_nodeSpawnManager:sv_activateSpawnTrigger( triggerName, world, nextLoad )
    end
end

function NodeSpawnManager.sv_activateSpawnTrigger( self, triggerName, world, nextLoad )
    self.sv.saved.primedTriggers[triggerName] = true
    if not nextLoad and world ~= nil then
        if self.sv.inactiveUnitSpawners[triggerName] then
            for _,cellPos in ipairs( self.sv.inactiveUnitSpawners[triggerName] ) do
                if world:isCellLoadedServer( cellPos.x, cellPos.y ) then
                    self:sv_spawnUnits( cellPos.x, cellPos.y, world )
                end
            end
        end
        if self.sv.inactiveHarvestableSpawners[triggerName] then
            for _,cellPos in ipairs( self.sv.inactiveHarvestableSpawners[triggerName] ) do
                 if world:isCellLoadedServer( cellPos.x, cellPos.y ) then
                    self:sv_spawnHarvestables( cellPos.x, cellPos.y, world )
                 end
            end
        end
        if self.sv.inactiveQuestEventSpawners[triggerName] then
            for _,cellPos in ipairs( self.sv.inactiveQuestEventSpawners[triggerName] ) do
                 if world:isCellLoadedServer( cellPos.x, cellPos.y ) then
                    self:sv_spawnQuestEventHarvestable( cellPos.x, cellPos.y, world )
                 end
            end
        end
        if self.sv.inactiveBlueprintSpawners[triggerName] then
            for _,cellPos in ipairs( self.sv.inactiveBlueprintSpawners[triggerName] ) do
                 if world:isCellLoadedServer( cellPos.x, cellPos.y ) then
                    self:sv_spawnBlueprint( cellPos.x, cellPos.y, world )
                 end
            end
        end
    end
    self:sv_save()
end

function NodeSpawnManager.Sv_DeactivateSpawnTrigger( triggerName )
    if g_nodeSpawnManager then
        g_nodeSpawnManager:sv_deactivateSpawnTrigger( triggerName )
    end
end

function NodeSpawnManager.sv_deactivateSpawnTrigger( self, triggerName )
    self.sv.saved.primedTriggers[triggerName] = nil
    self.sv.saved.expendedSpawners[triggerName] = nil
    self.sv.inactiveUnitSpawners[triggerName] = nil
    self.sv.inactiveHarvestableSpawners[triggerName] = nil
    self.sv.inactiveQuestEventSpawners[triggerName] = nil
    self.sv.inactiveBlueprintSpawners[triggerName] = nil
    self:sv_save()
end

function NodeSpawnManager.Sv_ResetSpawnTrigger( triggerName )
    if g_nodeSpawnManager then
        g_nodeSpawnManager:sv_resetSpawnTrigger( triggerName )
    end
end

function NodeSpawnManager.sv_resetSpawnTrigger( self, triggerName )
    self.sv.saved.expendedSpawners[triggerName] = nil
    self:sv_save()
end

function NodeSpawnManager.Sv_OnCellLoaded( x, y, world )
    g_nodeSpawnManager:sv_onCellLoaded( x, y, world )
end

function NodeSpawnManager.Sv_OnCellCreated( x, y, world )
    g_nodeSpawnManager:sv_onCellCreated( x, y, world )
end

function NodeSpawnManager.sv_onCellCreated( self, x, y, world )
    local isDirty = false
    
    if self:sv_spawnUnits( x, y, world ) then
        isDirty = true
    end

    if self:sv_spawnHarvestables( x, y, world ) then
        isDirty = true
    end

    if self:sv_spawnQuestEventHarvestable( x, y, world ) then
        isDirty = true
    end

    if self:sv_spawnBlueprint( x, y, world ) then
        isDirty = true
    end

    self:sv_spawnHarvestablePickups( x, y, world )

    if isDirty then
        self:sv_save()
    end
end

function NodeSpawnManager.sv_onCellLoaded( self, x, y , world )
    local isDirty = false
    
    if self:sv_spawnUnits( x, y, world ) then
        isDirty = true
    end

    if self:sv_spawnHarvestables( x, y, world ) then
        isDirty = true
    end

    if self:sv_spawnQuestEventHarvestable( x, y, world ) then
        isDirty = true
    end

    if self:sv_spawnBlueprint( x, y, world ) then
        isDirty = true
    end

    if isDirty then
        self:sv_save()
    end
end

function NodeSpawnManager.Sv_OnCellUnloaded( x, y, world )
    g_nodeSpawnManager:sv_onCellUnloaded( x, y, world )
end

function NodeSpawnManager.sv_onCellUnloaded( self, x, y, world )
    local cellKey = CellKey( x, y )
    if self.sv.discoveredRangeSpawns[world.id] == nil then
        return
    end
    if self.sv.discoveredRangeSpawns[world.id][cellKey] == nil then
        return
    end
    self.sv.discoveredRangeSpawns[world.id][cellKey] = nil
end

function NodeSpawnManager.sv_spawnUnits( self, x, y, world )
    local isDirty = false

    local nodes = sm.cell.getNodesByTag( x, y, "SPAWNABLE_UNIT", world )
    for _,node in ipairs( nodes ) do
        local trigger = node.params.eventName

        local spawnRange = node.params.spawnRange or -1
        local cellKey = CellKey( x, y )
        if trigger then
            if self.sv.saved.primedTriggers[trigger] ~= nil then
                if not self.sv.saved.expendedSpawners[trigger] then
                    self.sv.saved.expendedSpawners[trigger] = {}
                end

                local name = node.params.name
                if not name then
                    name = ""
                    for _,tag in ipairs( node.tags ) do
                        name = name.."|"..tag
                    end
                    name = name.."|"..tostring( node.position )
                end
                name = name.."|"..TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, node.position )
                if name and not self.sv.saved.expendedSpawners[trigger][name] then
                    local unitParams = {}
                    unitParams.spawnParams = node.params
                    unitParams.spawnParams.temporary = false
                    unitParams.spawnParams.roaming = true
                    unitParams.spawnParams.spawnTrigger = trigger
                    unitParams.node = node
                    sm.event.sendToWorld( world, "sv_e_spawnNodeUnit", unitParams )

                    self.sv.saved.expendedSpawners[trigger][name] = true
                    isDirty = true
                end
            else
                if not self.sv.inactiveUnitSpawners[trigger] then
                    self.sv.inactiveUnitSpawners[trigger] = {}
                end
                local cellPos = { x = x, y = y }
                if not isAnyOf( cellPos, self.sv.inactiveUnitSpawners[trigger] ) then -- This doesn't work. Tables don't compare by content
                    self.sv.inactiveUnitSpawners[trigger][#self.sv.inactiveUnitSpawners[trigger]+1] = cellPos
                    isDirty = true
                end
            end
        elseif spawnRange >= 0 then
            local name = node.params.name
            if not name then
                name = ""
                for _,tag in ipairs( node.tags ) do
                    name = name.."|"..tag
                end
                name = name.."|"..tostring( node.position )
            else
                name = name.."|"..TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, node.position )
            end
            if self.sv.saved.expendedSpawners[name] == nil then
                if self.sv.discoveredRangeSpawns[world.id] == nil then
                    self.sv.discoveredRangeSpawns[world.id] = {}
                end
                if self.sv.discoveredRangeSpawns[world.id][cellKey] == nil then
                    self.sv.discoveredRangeSpawns[world.id][cellKey] = {}
                end
                node.customData = { world = world }
                self.sv.discoveredRangeSpawns[world.id][cellKey][name] = node
                isDirty = true
            end
        elseif node.params.singleSpawn and node.params.guaranteed then
            local name = node.params.name
            if not name then
                name = ""
                for _, tag in ipairs( node.tags ) do
                    name = name.."|"..tag
                end
                name = name.."|"..tostring( node.position )
            end
            name = name.."|"..TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, node.position )
            if self.sv.saved.expendedSpawners[name] == nil then
                local unitParams = {}
                unitParams.spawnParams = node.params
                unitParams.node = node
                sm.event.sendToWorld( world, "sv_e_spawnNodeUnit", unitParams )

                self.sv.saved.expendedSpawners[name] = true
                isDirty = true
            end
        end
    end
     return isDirty
end

function NodeSpawnManager.sv_spawnHarvestables( self, x, y, world )
    local isDirty = false
    local nodes = sm.cell.getNodesByTags( x, y, { "*DRILL_SPAWNER_SPAWN" }, world )
    for _, node in ipairs( nodes ) do
        local trigger = node.params.trigger
        if trigger ~= nil then
            if self.sv.saved.primedTriggers[trigger] then
                if not self.sv.saved.expendedSpawners[trigger] then
                    self.sv.saved.expendedSpawners[trigger] = {}
                end
                local nodeKey = node.params.name.."|"..TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, node.position )
                if not self.sv.saved.expendedSpawners[trigger][nodeKey] then
					local direction = node.rotation * sm.vec3.new( 0, 1, 0 )
					local drillDistance = node.params.drillSpawner.spawns.drillDistance or 10
					local params = { destination = node.position, units = {} }
					for _,unit in ipairs( node.params.drillSpawner.spawns.units ) do
						for _ = 1, unit.amount do
							params.units[#params.units+1] = unit.uuid
						end
					end
					sm.event.sendToWorld( world, "sv_spawnHarvestable", { uuid = kin_drillspawner, position = node.position - direction * drillDistance, quat = node.rotation, harvestableParams = params } )
                    self.sv.saved.expendedSpawners[trigger][nodeKey] = true
                    isDirty = true
                end
            else
                if not self.sv.inactiveHarvestableSpawners[trigger] then
                    self.sv.inactiveHarvestableSpawners[trigger] = {}
                end
                local cellPos = { x = x, y = y }
                if not isAnyOf( cellPos, self.sv.inactiveHarvestableSpawners[trigger] ) then
                    self.sv.inactiveHarvestableSpawners[trigger][#self.sv.inactiveHarvestableSpawners[trigger]+1] = cellPos
                    isDirty = true
                end
            end
        end
    end
    return isDirty
end

function NodeSpawnManager.sv_spawnHarvestablePickups( self, x, y, world )
    local nodes = sm.cell.getNodesByTag( x, y, "HARVESTABLE_LOGBOOK_PICKUP", world )

    for _, node in ipairs( nodes ) do
        local params = {}
        params.harvestableParams = { logUuid = node.params.logbookEntryUuid, displayItemUuid = sm.uuid.new( node.params.displayItemUuid ) }
        params.uuid = hvs_loot_logbook_entry
        
        params.position = node.position

        params.quat = sm.quat.identity()
        sm.event.sendToWorld( world, "sv_spawnHarvestable", params )
    end
end

function NodeSpawnManager.sv_spawnQuestEventHarvestable( self, x, y, world )
    local nodes = sm.cell.getNodesByTag( x, y, "HARVESTABLE_QUEST_PICKUP_EVENT", world )
    local isDirty = false

    for _,node in ipairs( nodes ) do
        local trigger = node.params.trigger
        if trigger ~= nil then
            if self.sv.saved.primedTriggers[trigger] then
                if not self.sv.saved.expendedSpawners[trigger] then
                    self.sv.saved.expendedSpawners[trigger] = {}
                end
                local nodeKey = node.params.name.."|"..TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, node.position )
                if not self.sv.saved.expendedSpawners[trigger][nodeKey] then
                    self.sv.saved.expendedSpawners[trigger][nodeKey] = true
                    local params = {}
                    params.harvestableParams = { questName = node.params.questName, questEvent = node.params.questEvent,
                     displayItemUuid = sm.uuid.new( node.params.displayItemUuid ), spawnEffect = node.params.spawnEffect,
                     interactEffect = node.params.interactEffect, delay = node.params.delayInMinutes }
                    params.uuid = hvs_loot_quest_event
                    params.position = node.position
                    params.quat = sm.quat.identity()
                    sm.event.sendToWorld( world, "sv_spawnHarvestable", params )
                    isDirty = true
                end
            else
                if not self.sv.inactiveQuestEventSpawners[trigger] then
                    self.sv.inactiveQuestEventSpawners[trigger] = {}
                end
                local cellPos = { x = x, y = y }
                if not isAnyOf( cellPos, self.sv.inactiveQuestEventSpawners[trigger] ) then
                    self.sv.inactiveQuestEventSpawners[trigger][#self.sv.inactiveQuestEventSpawners[trigger]+1] = cellPos
                    isDirty = true
                end
            end
        end
    end
    return isDirty
end

function NodeSpawnManager.sv_spawnBlueprint( self, x, y, world )
    local nodes = sm.cell.getNodesByTag( x, y, "BLUEPRINT_SPAWN", world )
    local isDirty = false

    for _,node in ipairs( nodes ) do
        local trigger = node.params.trigger
        if trigger ~= nil then
            if self.sv.saved.primedTriggers[trigger] then
                if not self.sv.saved.expendedSpawners[trigger] then
                    self.sv.saved.expendedSpawners[trigger] = {}
                end
                local nodeKey = node.params.name.."|"..TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, node.position )
                if not self.sv.saved.expendedSpawners[trigger][nodeKey] then
                    self.sv.saved.expendedSpawners[trigger][nodeKey] = true

                    if node.params.blueprintPath and node.params.blueprintPath ~= "" then
                        local bodies = sm.creation.importFromFile( world, node.params.blueprintPath, node.position, sm.quat.identity() )
                        if node.params.burning then
                            local shapeCount = 0
                            for _,body in ipairs( bodies ) do
                                shapeCount = shapeCount + #body:getShapes()
                            end
                            for _,body in ipairs( bodies ) do
                                local shapes = body:getShapes()
                                local targetFireAmount = math.floor( math.max( 1, shapeCount * ( 0.2 ) ) )
                                local fireCount = 0
                                for _,shape in ipairs( shapes ) do
                                    shape:setBurning( true )
                                    fireCount = fireCount + 1
                                    if fireCount >= targetFireAmount then
                                        break
                                    end
                                end
                            end
                        end
                    elseif node.params.singleShape and node.params.singleShape ~= "" then
                        local shapeUuid = sm.uuid.new( node.params.singleShape )
                        local shape = sm.shape.createPart( shapeUuid, node.position, node.rotation, false, true, world )
                        if node.params.burning then
                            shape:setBurning( true )
                        end
                    end

                    isDirty = true
                end
            else
                if not self.sv.inactiveBlueprintSpawners[trigger] then
                    self.sv.inactiveBlueprintSpawners[trigger] = {}
                end
                local cellPos = { x = x, y = y }
                if not isAnyOf( cellPos, self.sv.inactiveBlueprintSpawners[trigger] ) then
                    self.sv.inactiveBlueprintSpawners[trigger][#self.sv.inactiveBlueprintSpawners[trigger]+1] = cellPos
                    isDirty = true
                end
            end
        end
    end
    return isDirty
end

function NodeSpawnManager.server_onFixedUpdate( self )
    local currentTick = sm.game.getCurrentTick()
    local budget = RangeBasedBudget
    local players = sm.player.getAllPlayers()
    local dirty = false
    local clearOutList = {}
    for worldId,worldList in pairs( self.sv.discoveredRangeSpawns ) do
        for cellKey,nameList in pairs( worldList ) do
            for name,node in pairs( nameList ) do
                if budget <= 0 then
                    goto continue
                end
                
                local spawnRange = node.params.spawnRange
                local lastTick = node.customData.lastTick or 0
                if currentTick - lastTick > NodeTickCooldown then
                    node.customData.lastTick = currentTick
                    local isVisible = false
                    local isInRange = false
                    for _,player in ipairs( players ) do
                        local playerCharacter = player:getCharacter()
                        if playerCharacter and playerCharacter:getWorld().id == worldId then
                            local playerPos = player:getCharacter():getWorldPosition()
                            local distanceSqr = ( playerPos - node.position ):length2()
                            if distanceSqr <= ( spawnRange * spawnRange ) then
                                isInRange = true
                                --raycast to see if line of sight is broken
                                local hit, result = sm.physics.raycast( playerPos, node.position, nil, sm.physics.filter.default - sm.physics.filter.character, node.customData.world )
                                budget = budget - 1
                                if not hit then
                                    isVisible = true
                                    break -- if any player sees the node we don't spawn it
                                end
                            end
                        end
                    end
                    if not isVisible and isInRange then
                        local unitParams = {}
                        unitParams.spawnParams = node.params or {}
                        unitParams.spawnParams.temporary = false
                        unitParams.spawnParams.roaming = true
                        unitParams.node = node
                        sm.event.sendToWorld( node.customData.world, "sv_e_spawnNodeUnit", unitParams )

                        self.sv.saved.expendedSpawners[name] = true
                        dirty = true
                        clearOutList[#clearOutList+1] = { worldId = worldId, cellKey = cellKey, name = name }
                    end
                end
            end
        end
    end
    ::continue::
    for _,entry in ipairs( clearOutList ) do
        self.sv.discoveredRangeSpawns[entry.worldId][entry.cellKey][entry.name] = nil
    end

    if dirty then
        self:sv_save()
    end
end
