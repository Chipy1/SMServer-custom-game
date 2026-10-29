dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

local EncounterList = dofile( "$SURVIVAL_DATA/ScriptJsonFiles/CombatEncounters/main.combatencounters" )

CombatEncounterManager = class( nil )
local DistanceTickUpdateRate = 5 * 40
local AcceptedRangeSquared = 140 * 140

function CombatEncounterManager.server_onCreate( self )
    g_combatEncounterManager = self
    self.sv = {}
    self.sv.encounterNodes = {}
    self.sv.tickCounter = 0
    self.sv.nonSpawnTickCounter = 0
    self.sv.saved = sm.storage.load( STORAGE_CHANNEL_DYNAMIC_COMABT_MANAGER )
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.encounters = {}
        self.sv.saved.nonSpawningEncounters = {}
        sm.storage.save( STORAGE_CHANNEL_DYNAMIC_COMABT_MANAGER, self.sv.saved )
    else
        self.sv.setupComplete = false
    end
    self.sv.isDirty = false
end

function CombatEncounterManager.server_onFixedUpdate( self )

    if not self.sv.setupComplete and g_questManagerServer then
        for name,_ in pairs( self.sv.saved.encounters ) do
            self:sv_registerEvent( name )
        end
        for name,_ in pairs( self.sv.saved.nonSpawningEncounters ) do
            self:sv_registerEvent( name )
        end
        self.sv.setupComplete = true
    end

    if not IsEmptyTable( self.sv.saved.encounters ) then
        local clearedEncounters = {}
        for name,encounterData in pairs( self.sv.saved.encounters ) do
            if encounterData.active then
                if encounterData.waveCounter <= #encounterData.waves then
                    for _,spawnInfo in ipairs( encounterData.waves[encounterData.waveCounter].spawns ) do
                        if encounterData.tickCounter == spawnInfo.delay then
                            local spawnParams = {}
                            spawnParams.uuid = spawnInfo.uuid
                            spawnParams.roaming = spawnInfo.roaming or false
                            spawnParams.deathEvent = name
                            spawnParams.destroyShapes = true
                            spawnParams.center = encounterData.position
                            spawnParams.minRange = encounterData.minRange
                            spawnParams.maxRange = encounterData.maxRange
                            spawnParams.marked = encounterData.marked
                            if encounterData.spawnNodes[spawnInfo.spawnerIndex] then
                                spawnParams.spawnPoint = encounterData.spawnNodes[spawnInfo.spawnerIndex].position
                                spawnParams.rotation = encounterData.spawnNodes[spawnInfo.spawnerIndex].rotation
                            end
                            sm.event.sendToWorld( encounterData.world, "sv_e_spawnCombatEncounterUnit", spawnParams )
                            self.sv.isDirty = true
                        end
                    end
                    encounterData.tickCounter = encounterData.tickCounter + 1
                    if encounterData.tickCounter >= encounterData.waveTickDuration then
                        if self:sv_canAdvanceWave( name ) then
                            encounterData.tickCounter = 0
                            encounterData.defeatedEnemies = 0
                            encounterData.waveCounter = encounterData.waveCounter + 1
                            if encounterData.subscriber and encounterData.newWaveFunction and sm.exists( encounterData.subscriber ) then
                                SendEvent( encounterData.subscriber, encounterData.newWaveFunction, name )
                            end
                            if encounterData.waveCounter > #encounterData.waves then
                                clearedEncounters[#clearedEncounters+1] = name
                                if encounterData.subscriber and encounterData.finishFunction and sm.exists( encounterData.subscriber ) then
                                    SendEvent( encounterData.subscriber, encounterData.finishFunction, name )
                                end
                                --TODO play done sound if we should have any
                            else
                                encounterData.waveTickDuration = math.floor( encounterData.waves[encounterData.waveCounter].minimumDuration * 40 )
                                --TODO new wave sound here if we should have any
                            end
                            self.sv.isDirty = true
                        end
                    end
                end
            end
        end

        for _,name in ipairs( clearedEncounters ) do
            QuestManager.Sv_UnsubscribeEvent( name, self.scriptableObject )
            self.sv.saved.encounters[name] = nil
        end
    end

    if not IsEmptyTable( self.sv.saved.nonSpawningEncounters ) then
        self.sv.nonSpawnTickCounter = self.sv.nonSpawnTickCounter + 1
        local completedEncounters = {}
        if self.sv.nonSpawnTickCounter >= 40 then
            self.sv.nonSpawnTickCounter = 0
            for name,encounterData in pairs( self.sv.saved.nonSpawningEncounters ) do
                if encounterData.defeatedEnemies >= encounterData.targetCount then
                    if encounterData.subscriber and encounterData.finishFunction and sm.exists( encounterData.subscriber ) then
                        SendEvent( encounterData.subscriber, encounterData.finishFunction, name )
                    end
                    completedEncounters[#completedEncounters+1] = name
                    self.sv.isDirty = true
                end
            end
        end
        for _,name in ipairs( completedEncounters ) do
            self.sv.saved.nonSpawningEncounters[name] = nil
        end
    end
    self.sv.tickCounter = self.sv.tickCounter + 1
    if self.sv.tickCounter >= DistanceTickUpdateRate then
        self.sv.tickCounter = 0
        self:sv_checkPlayerRanges()
    end

    if self.sv.isDirty then
        sm.storage.save( STORAGE_CHANNEL_DYNAMIC_COMABT_MANAGER, self.sv.saved )
        self.sv.isDirty = false
    end
end

function CombatEncounterManager.sv_checkPlayerRanges( self )

    local isAnyPlayerInRange = function( playerList, encounterData, name )
        local anyInRange = false
        for _,player in ipairs( playerList ) do
            if sm.exists( player.character ) then
                local playerPos = player.character:getWorldPosition()
                if ( playerPos - encounterData.position ):length2() <= AcceptedRangeSquared then
                    anyInRange = true
                end
            end
        end
        return anyInRange
    end

    local setActiveState = function( encounterData, state )
        if not encounterData.active == state then
            encounterData.active = state
            self.sv.isDirty = true
        end
    end

    local activePlayers = sm.player.getAllPlayers()
    for name,encounterData in pairs( self.sv.saved.encounters ) do
        if isAnyPlayerInRange( activePlayers, encounterData, name ) then
           setActiveState( encounterData, true )
        else
            setActiveState( encounterData, false )
        end
    end
    for name,encounterData in pairs( self.sv.saved.nonSpawningEncounters ) do
        if isAnyPlayerInRange( activePlayers, encounterData, name ) then
           setActiveState( encounterData, true )
        else
            setActiveState( encounterData, false )
        end
    end
end

function CombatEncounterManager.sv_canAdvanceWave( self, name )
    local encounterData = self.sv.saved.encounters[name]
    local waveInfo = encounterData.waves[encounterData.waveCounter]

    local defeatedEnemiesNeeded = math.floor( ( waveInfo.spawnAmount + encounterData.remainder ) * waveInfo.minimumClearRequirement )
    if encounterData.defeatedEnemies >= defeatedEnemiesNeeded then
        encounterData.remainder = waveInfo.spawnAmount - encounterData.defeatedEnemies + encounterData.remainder
        return true
    else
        return false
    end
end

function CombatEncounterManager.Sv_StartEncounter( params )
    g_combatEncounterManager:sv_startEncounter( params )
end

function CombatEncounterManager.sv_startEncounter( self, params )
    local encounterData = EncounterList[params.preset]
    encounterData.position = params.position
    encounterData.world = params.world
    encounterData.tickCounter = 0
    encounterData.waveCounter = 1
    encounterData.subscriber = params.subscriber
    encounterData.finishFunction = params.finishFunction
    encounterData.newWaveFunction = params.newWaveFunction
    encounterData.enemyDefeatedFunction = params.enemyDefeatedFunction
    encounterData.defeatedEnemies = 0
    encounterData.remainder = 0
    encounterData.active = true
    encounterData.waveTickDuration = math.floor( encounterData.waves[1].minimumDuration * 40 )
    encounterData.minRange = params.minRange or 40
    encounterData.maxRange = params.maxRange or 80
    if params.marked ~= nil then
        encounterData.marked = params.marked
    else
        encounterData.marked = true
    end

    if params.kinematicEventTrigger then
        local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( params.world, params.position )
        if tileStorageKey ~= nil then
            KinematicManager.Sv_Activate( tileStorageKey, params.kinematicEventTrigger )
        else
            sm.log.warning( "CombatEncounterManager: Failed to compute tileStorageKey for kinematicEventTrigger at position: " .. tostring( params.position ) .. " in world: " .. tostring( params.world.id ) )
        end
    end

    local nearbyNodes = {}

    local xMin, xMax, yMin, yMax = GetTileRanges( params.position, params.world.id )
    for x = xMin, xMax do
        for y = yMin, yMax do
            local nodes = sm.cell.getNodesByTag( x, y, "COMBAT_SPAWN_POINT", params.world )
            for _, node in ipairs( nodes ) do
                nearbyNodes[math.floor( node.params.spawnerIndex )] = node
            end
        end
    end

    encounterData.spawnNodes = nearbyNodes
    self.sv.saved.encounters[params.name] = encounterData
    self:sv_registerEvent( params.name )

    sm.storage.save( STORAGE_CHANNEL_DYNAMIC_COMABT_MANAGER, self.sv.saved )
end

function CombatEncounterManager.Sv_StartNonSpawningEncounter( params )
    g_combatEncounterManager:sv_startNonSpawningEncounter( params )
end

function CombatEncounterManager.sv_startNonSpawningEncounter( self, params )
    local encounterData = {}
    encounterData.position = params.position
    encounterData.subscriber = params.subscriber
    encounterData.finishFunction = params.finishFunction
    encounterData.enemyDefeatedFunction = params.enemyDefeatedFunction
    encounterData.defeatedEnemies = 0
    encounterData.active = true
    encounterData.targetCount = params.targetCount
    encounterData.world = params.world

    self.sv.saved.nonSpawningEncounters[params.name] = encounterData
    self:sv_registerEvent( params.name )
    sm.storage.save( STORAGE_CHANNEL_DYNAMIC_COMABT_MANAGER, self.sv.saved )
end

function CombatEncounterManager.sv_e_handleEvent( self, data )
    if self.sv.saved.encounters[data.event] ~= nil then
        self.sv.saved.encounters[data.event].defeatedEnemies = self.sv.saved.encounters[data.event].defeatedEnemies + 1
        if self.sv.saved.encounters[data.event].enemyDefeatedFunction and sm.exists( self.sv.saved.encounters[data.event].subscriber ) then
            SendEvent( self.sv.saved.encounters[data.event].subscriber, self.sv.saved.encounters[data.event].enemyDefeatedFunction )
        end
    elseif self.sv.saved.nonSpawningEncounters[data.event] ~= nil then
        self.sv.saved.nonSpawningEncounters[data.event].defeatedEnemies = self.sv.saved.nonSpawningEncounters[data.event].defeatedEnemies + 1
        if self.sv.saved.nonSpawningEncounters[data.event].enemyDefeatedFunction and sm.exists( self.sv.saved.nonSpawningEncounters[data.event].subscriber ) then
            SendEvent( self.sv.saved.nonSpawningEncounters[data.event].subscriber, self.sv.saved.nonSpawningEncounters[data.event].enemyDefeatedFunction )
        end
    end
    sm.storage.save( STORAGE_CHANNEL_DYNAMIC_COMABT_MANAGER, self.sv.saved )
end

function CombatEncounterManager.sv_registerEvent( self, name )
    QuestManager.Sv_SubscribeEvent( name, self.scriptableObject, "sv_e_handleEvent" )
end