dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"

CombatRoomManager = class( nil )

local combatSetups = dofile( "$SURVIVAL_DATA/ScriptJsonFiles/CombatEncounters/main.combatencounters" )
for _, combatData in pairs( combatSetups ) do
    for _,waveInfo in ipairs( combatData.waves ) do
        local totalSpawnAmount = 0
        for _,spawnInfo in ipairs( waveInfo.spawns ) do
            spawnInfo.delay = math.floor( spawnInfo.delay * 40 )
            if spawnInfo.amount then
                totalSpawnAmount = totalSpawnAmount + spawnInfo.amount
            else
                totalSpawnAmount = totalSpawnAmount + 1
            end
        end
        waveInfo.spawnAmount = totalSpawnAmount
    end
end

function CombatRoomManager.server_onCreate( self )
    g_combatRoomManagerServer = self
    self.sv = {}
    self.sv.saved = sm.storage.load( STORAGE_CHANNEL_COMBATROOM_MANAGER )
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.activeCombatRooms = {}
        self.sv.saved.finishedRooms = {}
        self.sv.saved.failedRooms = {}
        sm.storage.save( STORAGE_CHANNEL_COMBATROOM_MANAGER, self.sv.saved )
    end
    self.sv.activeAreaTriggers = {}
    self.sv.loadHandles = {}
    self.sv.loadedRooms = {}
    self.sv.initializationDone = IsEmptyTable( self.sv.saved.activeCombatRooms )
    self:sv_setClientData()
    self.sv.isDirty = false
end

function CombatRoomManager.server_onFixedUpdate( self )
    if not self.sv.initializationDone then
        local exists = true
        for roomName, combatRoomData in pairs( self.sv.saved.activeCombatRooms ) do
            if combatRoomData ~= nil then
                local created = false
                local allSpawnersLoaded = true
                for _,spawner in ipairs( combatRoomData.spawners ) do
                    if not sm.exists( spawner ) then
                        allSpawnersLoaded = false
                        exists = false
                        break
                    end
                end
                if allSpawnersLoaded then
                    for _,spawner in ipairs( combatRoomData.spawners ) do
                        sm.event.sendToInteractable( spawner, "sv_e_setEncounterActive", true )
                        if not created then
                            self:sv_e_createCombatAreaTrigger( { roomName = roomName, combatRoomData = combatRoomData, spawners = combatRoomData.spawners } )
                            created = true
                        end
                    end
                end
            end
        end
        if exists then
            self.sv.initializationDone = true
        else
            return
        end
    end
    local finishedEncounters = {}
    for roomName, combatRoomData in pairs( self.sv.saved.activeCombatRooms ) do
        if self.sv.loadedRooms[roomName] ~= nil then
            if combatRoomData.enemiesToRespawn ~= nil then
                for _,respawnData in pairs( combatRoomData.enemiesToRespawn ) do
                    sm.event.sendToInteractable( combatRoomData.spawners[respawnData.spawnerIndex], "sv_e_spawn", { uuid = respawnData.uuid, amount = 1, counter = 0 } )
                end
                combatRoomData.enemiesToRespawn = nil
            end
            if combatRoomData.waveCounter <= #combatRoomData.waves then
                for i,spawnInfo in ipairs( combatRoomData.waves[combatRoomData.waveCounter].spawns ) do
                    if combatRoomData.tickCounter == spawnInfo.delay then
                        if combatRoomData.spawners[spawnInfo.spawnerIndex] then
                            sm.event.sendToInteractable( combatRoomData.spawners[spawnInfo.spawnerIndex], "sv_e_spawn", { uuid = spawnInfo.uuid, amount = spawnInfo.amount or 1, counter = 0 } )
                        else
                            sm.log.error( "Spawner with index "..spawnInfo.spawnerIndex.." does not exist in combat room "..roomName )
                        end
                        self.sv.isDirty = true
                    end
                end
                combatRoomData.tickCounter = combatRoomData.tickCounter + 1
                if combatRoomData.tickCounter >= combatRoomData.waveTickDuration then
                    if not self:sv_enemiesRemain( roomName ) then
                        combatRoomData.tickCounter = 0
                        local remainingEnemies = combatRoomData.waves[combatRoomData.waveCounter].spawnAmount - combatRoomData.waveDefeatedCount
                        combatRoomData.waveDefeatedCount = -remainingEnemies
                        combatRoomData.waveCounter = combatRoomData.waveCounter + 1
                        if combatRoomData.waveCounter > #combatRoomData.waves then
                            self.sv.saved.finishedRooms[#self.sv.saved.finishedRooms+1] = roomName
                            self:sv_removeAreaTrigger( roomName )
                            finishedEncounters[#finishedEncounters+1] = roomName
                            for _,spawner in ipairs( combatRoomData.spawners ) do
                                sm.event.sendToInteractable( spawner, "sv_e_setEncounterActive", false )
                            end
                            self.sv.loadedRooms[roomName] = nil
                            sm.effect.playEffect( "Cinematic - Challengemodecomplete_audio", combatRoomData.position, nil, nil, nil, nil, nil, combatRoomData.world ) -- temp
                            if g_kinematicManager then
                                KinematicManager.Sv_Activate( combatRoomData.tileStorageKey, combatRoomData.kinematicFinishTag )
                                KinematicManager.Sv_Activate( combatRoomData.tileStorageKey, combatRoomData.kinematicEventTrigger )
                            end
                            if combatRoomData.tsTagActivation and combatRoomData.tsTagActivation ~= "" then
                                UnsetTileStorageFlag( combatRoomData.tileStorageKey, combatRoomData.tsTagActivation )
                                EffectManager.Sv_UpdateTagFilteredEffectsForTile( combatRoomData.world, combatRoomData.position, { combatRoomData.tsTagActivation } )
                            end
                        else
                            combatRoomData.waveTickDuration = math.floor( combatRoomData.waves[combatRoomData.waveCounter].minimumDuration * 40 )
                            -- new wave sound here
                            sm.effect.playEffect( "Woc - Panic", combatRoomData.position, nil, nil, nil, nil, nil, combatRoomData.world ) -- temp
                        end
                        self.sv.isDirty = true
                    else
                        if combatRoomData.tickCounter > ( combatRoomData.waveTickDuration + 1600 ) then -- failsafe completion if no enemies are left in area after 40 seconds past spawn
                            if self.sv.activeAreaTriggers[roomName] then
                                local contents = self.sv.activeAreaTriggers[roomName]:getContents()
                                local emergencyComplete = #self.sv.activeAreaTriggers[roomName]:getContents() > 0
                                for _,character in ipairs( contents ) do
                                    if not character:isPlayer() then
                                        local unit = character:getUnit()
                                        if self.sv.saved.activeCombatRooms[roomName].currentEnemies[unit.id] then
                                            emergencyComplete = false
                                            break
                                        end
                                    end
                                end
                                if emergencyComplete then
                                    local waveCounter = self.sv.saved.activeCombatRooms[roomName].waveCounter
                                    local waveData = self.sv.saved.activeCombatRooms[roomName].waves[waveCounter]
                                    self.sv.saved.activeCombatRooms[roomName].waveDefeatedCount = waveData.spawnAmount
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    for _,roomName in ipairs( finishedEncounters ) do
        self.sv.saved.activeCombatRooms[roomName] = nil
    end

    if self.sv.isDirty then
        self:sv_setClientData()
        sm.storage.save( STORAGE_CHANNEL_COMBATROOM_MANAGER, self.sv.saved )
        self.sv.isDirty = false
    end
end

function CombatRoomManager.sv_setClientData( self )
    local rooms = self:sv_getActiveAndFinishedRooms()
    self.network:setClientData( rooms )
end

function CombatRoomManager.sv_getActiveAndFinishedRooms( self )
    local rooms = {}
    for roomName, values in pairs( self.sv.saved.activeCombatRooms ) do
        if values ~= nil then
            rooms[#rooms+1] = roomName
        end
    end
    for _, roomName in ipairs( self.sv.saved.finishedRooms ) do
        rooms[#rooms+1] = roomName
    end
    return rooms
end

function CombatRoomManager.sv_removeAreaTrigger( self, roomName )
    sm.areaTrigger.destroy( self.sv.activeAreaTriggers[roomName] )
    self.sv.activeAreaTriggers[roomName] = nil
end

function CombatRoomManager.sv_enemiesRemain( self, roomName )
    local waveCounter = self.sv.saved.activeCombatRooms[roomName].waveCounter
    local waveData = self.sv.saved.activeCombatRooms[roomName].waves[waveCounter]
    return waveData.spawnAmount - self.sv.saved.activeCombatRooms[roomName].waveDefeatedCount > waveData.spawnAmount - waveData.spawnAmount * waveData.minimumClearRequirement
end

function CombatRoomManager.sv_characterLeftCombatArea( self, trigger, characterTable )
    
    local roomName = nil
    for connectedRoom, activeTrigger in pairs( self.sv.activeAreaTriggers ) do
        if activeTrigger == trigger then
            roomName = connectedRoom
        end
    end
    if roomName == nil then
        sm.log.error( "Player left combat area not connected to an existing room" )
        return
    end
    for _,character in ipairs( characterTable ) do
        if sm.exists( character ) and not character:isPlayer() then
            self:sv_enemyDefeated( roomName, character:getUnit().id ) -- handle enemies who are knocked out as defeated
            return
        end
    end
    local contents = trigger:getContents()
    if not TriggerContentsContainsAnyPlayer( contents ) then
    
        local combatRoomData = self.sv.saved.activeCombatRooms[roomName]
        if combatRoomData.activatedFromTriggerZone then
            KinematicManager.Sv_Activate( combatRoomData.tileStorageKey, combatRoomData.kinematicFinishTag )
        end
        KinematicManager.Sv_Activate( combatRoomData.tileStorageKey, combatRoomData.kinematicEventTrigger )
        if combatRoomData.tsTagActivation and combatRoomData.tsTagActivation ~= "" then
            UnsetTileStorageFlag( combatRoomData.tileStorageKey, combatRoomData.tsTagActivation )
            EffectManager.Sv_UpdateTagFilteredEffectsForTile( combatRoomData.world, combatRoomData.position, { combatRoomData.tsTagActivation } )
        end
        if combatRoomData.buttonTag then
            KinematicManager.Sv_Activate( combatRoomData.tileStorageKey, combatRoomData.buttonTag )
        end

        for _,spawner in ipairs( combatRoomData.spawners ) do
            if sm.exists( spawner ) then
                sm.event.sendToInteractable( spawner, "sv_e_setEncounterActive", false )
            end
        end
        self.sv.loadedRooms[roomName] = nil
        
        combatRoomData.enemiesToRespawn = combatRoomData.currentEnemies
        combatRoomData.currentEnemies = {}

        self.sv.saved.failedRooms[roomName] = combatRoomData
        self.sv.saved.activeCombatRooms[roomName] = nil
        sm.areaTrigger.destroy( trigger )
        self.sv.activeAreaTriggers[roomName] = nil
        for _,character in ipairs( contents ) do
            if sm.exists( character ) then
                sm.unit.forceDestroy( character:getUnit() )
            end
        end
        self.sv.isDirty = true
    end
end

function CombatRoomManager.server_onUnload( self )
    sm.storage.save( STORAGE_CHANNEL_COMBATROOM_MANAGER, self.sv.saved )
end

function CombatRoomManager.Sv_ActivateCombatRoom( node, triggerObject )
    g_combatRoomManagerServer:sv_activateCombatRoom( node, triggerObject )
end

function CombatRoomManager.sv_activateCombatRoom( self, node, triggerObject )
    local combatRoomData = {}
    if self.sv.saved.failedRooms[node.params.roomNameTag] == nil then
        combatRoomData = DeepCopy( combatSetups[node.params.preset] )
        combatRoomData.tickCounter = 0
        combatRoomData.waveCounter = 1
        combatRoomData.waveTickDuration = math.floor( combatRoomData.waves[1].minimumDuration * 40 )
        combatRoomData.position = node.position
        combatRoomData.scale = node.scale / 2
        combatRoomData.rotation = node.rotation
        combatRoomData.world = node.params.world
        combatRoomData.currentEnemies = {}
        combatRoomData.waveDefeatedCount = 0
        combatRoomData.kinematicEventTrigger = node.params.kinematicEventTrigger
        combatRoomData.kinematicFinishTag = node.params.kinematicFinishTag
        combatRoomData.buttonTag = node.params.buttonTag
        combatRoomData.tsTagActivation = node.params.tsTagActivation

        if type( triggerObject ) == "table" then
            combatRoomData.activatedFromTriggerZone = true
            combatRoomData.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( node.params.world, triggerObject.position )
        else
            combatRoomData.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( triggerObject )
        end
        local value = TileStorageManager.Sv_GetValue( combatRoomData.tileStorageKey, "combatroom"..node.params.roomNameTag )
        if value == nil or value.spawners == nil then
            print( "No growlab bot spawners existed in the tile" )
            return
        end
        combatRoomData.spawners = value.spawners
    else
        combatRoomData = self.sv.saved.failedRooms[node.params.roomNameTag]
    end
    for _,spawner in ipairs( combatRoomData.spawners ) do
        sm.event.sendToInteractable( spawner, "sv_e_setEncounterActive", true )
    end

    sm.effect.playEffect( "Elevator - Keycarduse", node.position, nil, nil, nil, nil, nil, combatRoomData.world ) -- temp sound
    self.sv.saved.activeCombatRooms[node.params.roomNameTag] = combatRoomData
    self.sv.isDirty = true
    if g_kinematicManager then
        KinematicManager.Sv_Activate( combatRoomData.tileStorageKey, combatRoomData.kinematicEventTrigger )
        if combatRoomData.buttonTag then
            KinematicManager.Sv_Activate( combatRoomData.tileStorageKey, combatRoomData.buttonTag )
        end
        if combatRoomData.activatedFromTriggerZone then
            KinematicManager.Sv_Activate( combatRoomData.tileStorageKey, combatRoomData.kinematicFinishTag )
        end
    end
    
    if combatRoomData.tsTagActivation and combatRoomData.tsTagActivation ~= "" then
        SetTileStorageFlag( combatRoomData.tileStorageKey, combatRoomData.tsTagActivation )
        EffectManager.Sv_UpdateTagFilteredEffectsForTile( node.params.world, node.position, { combatRoomData.tsTagActivation } )
    end

    sm.event.sendToScriptableObject( self.scriptableObject, "sv_e_createCombatAreaTrigger", { roomName = node.params.roomNameTag, combatRoomData = combatRoomData, spawners = self.sv.saved.activeCombatRooms[node.params.roomNameTag].spawners } )
end

function CombatRoomManager.sv_e_createCombatAreaTrigger( self, data )
    self.sv.activeAreaTriggers[data.roomName] = sm.areaTrigger.createBox( data.combatRoomData.scale, data.combatRoomData.position, data.combatRoomData.rotation, sm.areaTrigger.filter.character, nil, data.combatRoomData.world )
    self.sv.activeAreaTriggers[data.roomName]:bindOnExit( "sv_characterLeftCombatArea" )

    if #data.spawners > 0 then
        if self.sv.loadHandles[data.roomName] == nil then
            self.sv.loadHandles[data.roomName] = { handles = {}, counter = 0 }
        end
        for _,spawner in pairs( data.spawners ) do
            local x = math.floor( spawner.shape.worldPosition.x / 64 )
            local y = math.floor( spawner.shape.worldPosition.y / 64 )
            self.sv.loadHandles[data.roomName].handles[#self.sv.loadHandles[data.roomName].handles+1] = data.combatRoomData.world:loadCellWithHandle( x, y, "sv_cellLoaded", { roomName = data.roomName } )
        end
    end
end

function CombatRoomManager.sv_cellLoaded( self, _, _, _, params )
    if self.sv.loadHandles[params.roomName].counter == nil then
        self.sv.loadHandles[params.roomName].counter = 0
    end
    self.sv.loadHandles[params.roomName].counter = self.sv.loadHandles[params.roomName].counter + 1
    if self.sv.loadHandles[params.roomName].counter == #self.sv.loadHandles[params.roomName].handles then
        self.sv.loadedRooms[params.roomName] = true
    end
end

function CombatRoomManager.Sv_IsRoomActive( roomName )
    return g_combatRoomManagerServer:sv_isRoomActive( roomName )
end

function CombatRoomManager.sv_isRoomActive( self, roomName )
    local rooms = self:sv_getActiveAndFinishedRooms()
    return isAnyOf( roomName, rooms )
end

function CombatRoomManager.Sv_RegisterEnemy( roomName, enemyId, enemyType, spawnerIndex )
    g_combatRoomManagerServer:sv_registerEnemy( roomName, enemyId, enemyType, spawnerIndex )
end

function CombatRoomManager.sv_registerEnemy( self, roomName, enemyId, enemyType, spawnerIndex )
    if self.sv.saved.activeCombatRooms[roomName] ~= nil then
        self.sv.saved.activeCombatRooms[roomName].currentEnemies[enemyId] = { uuid = enemyType, spawnerIndex = spawnerIndex }
        self.sv.isDirty = true
    end
end

function CombatRoomManager.Sv_EnemyDefeated( roomName, enemyId )
    g_combatRoomManagerServer:sv_enemyDefeated( roomName, enemyId )
end

function CombatRoomManager.sv_enemyDefeated( self, roomName, enemyId )
    if self.sv.saved.activeCombatRooms[roomName] ~= nil then
        if self.sv.saved.activeCombatRooms[roomName].currentEnemies[enemyId] == nil then
            return
        end
        self.sv.saved.activeCombatRooms[roomName].currentEnemies[enemyId] = nil
        self.sv.saved.activeCombatRooms[roomName].waveDefeatedCount = self.sv.saved.activeCombatRooms[roomName].waveDefeatedCount + 1
        self.sv.isDirty = true
    end
end

function CombatRoomManager.Sv_ReleaseHandle( roomName )
    sm.event.sendToScriptableObject( g_combatRoomManagerServer.scriptableObject, "sv_e_releaseHandle", roomName )
end

function CombatRoomManager.sv_e_releaseHandle( self, roomName )
    if self.sv.loadHandles[roomName] ~= nil and self.sv.loadHandles[roomName].handles then
        for _,handle in ipairs( self.sv.loadHandles[roomName].handles ) do
            handle:release()
            handle = nil
        end
    end
    self.sv.loadedRooms[roomName] = nil
end

-- Client

function CombatRoomManager.client_onCreate( self )
    g_combatRoomManagerClient = self
    self.cl = {}
    self.cl.activeCombatRoomNames = {}
end

function CombatRoomManager.client_onClientDataUpdate( self, data )
    self.cl.activeCombatRoomNames = data
end

function CombatRoomManager.Cl_IsRoomActive( roomName )
    return g_combatRoomManagerClient:cl_isRoomActive( roomName )
end

function CombatRoomManager.cl_isRoomActive( self, roomName )
    return isAnyOf( roomName, self.cl.activeCombatRoomNames ) 
end