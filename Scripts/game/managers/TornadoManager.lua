dofile("$SURVIVAL_DATA/Scripts/game/managers/WorldManager.lua")

TornadoManager = class()

local TornadoRadius = 6.0
local TornadoHeight = 7.0
local TornadoMovementSpeed = 5
local TornadoRotationSpeed = 0.1
local DistanceFromCenterModifier = 5.0

-- Characters
local TornadoPlayerVerticalImpulse = sm.vec3.new( 0, 0, 40 )
local TornadoPlayerHorizontalForce = 25

local MaxAffectedCharacterMass = 2000
local MaxHorizontalMassForce = 500
local CharacterVerticalModifier = 0.28
local CharacterHorizontalModifier = 1.2
local HorizontalDeviationPercentage = 40

-- Creations
local TornadoCreationVerticalForce = sm.vec3.new( 0, 0, 1700 )
local TornadoCreationHorizontalForce = 500
local CreationMaxImpulsePerBody = 4000
local MaxAllowedMass = 10000

local TornadoDimensions = sm.vec3.new( TornadoRadius, TornadoRadius, TornadoHeight )
local TornadoRaycastOffset = sm.vec3.new( 0, 0, 128 )
local TornadoHeightOffset = sm.vec3.new( 0, 0, TornadoHeight )
local RaycastFilter = sm.physics.filter.terrainSurface + sm.physics.filter.waterArea

local SyncTickInterval = 5 * 40
local SaveFrequency = 10 * 40
local TornadoUnloadTicks = 30 * 40
local TornadoSpawnChance = 0.1
local TornadoCellRespawnTicks = DAYCYCLE_TIME_TICKS
-- Server

local NonTumbleUnits = {
    unit_minerbot,
    unit_scannerbot,
    unit_trashball_green,
    unit_trashball_purple,
    unit_trashbot,
    unit_trashbot2,
    unit_farmbot
}

local EnvironmentTypes = {
    sand = 1,
    grass = 2,
    leaves = 3,
    water = 4
}
local EnvironmentCheckFrequency = 2 * 40

local function setPosAndDir( position, direction, targetDirection, world )
    position = position + direction * TornadoMovementSpeed * 0.025
    local success, result = sm.physics.raycast( position + TornadoRaycastOffset, position - TornadoRaycastOffset, nil, RaycastFilter, world )
    if success then
        position = result.pointWorld
    end
    local lengthSqr = ( direction - targetDirection ):length2()
    if lengthSqr > 0.0001 then
        local angle = math.acos( direction:dot( targetDirection ) ) or 1
        local rotation = sm.vec3.cross( direction, targetDirection )
        if rotation.z < 0 then
            angle = -angle
        end
        local newDirection = direction:rotate( angle * TornadoRotationSpeed * 0.025, sm.vec3.new( 0, 0, 1 ) )
        direction = newDirection:safeNormalize( sm.vec3.new( 1, 0, 0 ) )
    end
    return position, direction, targetDirection
end


































function TornadoManager.server_onCreate( self )
    g_tornadoManagerServer = self
    self.sv = {}
    self.sv.activeTornadoes = {}
    self.sv.syncCounter = 0
    self.sv.saveCounter = 0
    self.sv.desertCells = {}
    self.sv.world = nil
    self.sv.unloadedTornadoes = {}

    self.sv.saved = sm.storage.load( STORAGE_CHANNEL_TORNADO_MANAGER )
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.tornadoSaveData = {}
        self.sv.saved.tornadoIdCounter = 1
        self.sv.saved.visitedTornadoCells = {}
        sm.storage.save( STORAGE_CHANNEL_TORNADO_MANAGER, self.sv.saved )
    end
end

function TornadoManager.sv_save( self )
    local tornadoSaveData = {}
    for tornadoId, data in pairs( self.sv.activeTornadoes ) do
        tornadoSaveData[tornadoId] = { position = data.position, direction = data.direction, targetDirection = data.targetDirection, tick = data.tick, creationTick = data.creationTick, previousCell = data.previousCell }
    end
    for _, data in pairs( self.sv.unloadedTornadoes ) do
        tornadoSaveData[self.sv.saved.tornadoIdCounter] = { position = data.position, direction = data.direction, targetDirection = data.targetDirection, tick = data.tick, creationTick = data.creationTick, previousCell = data.previousCell }
        self.sv.saved.tornadoIdCounter = self.sv.saved.tornadoIdCounter + 1
    end
    self.sv.saved.tornadoSaveData = tornadoSaveData
    sm.storage.save( STORAGE_CHANNEL_TORNADO_MANAGER, self.sv.saved )
    self.sv.saved.tornadoSaveData = {}
end

function TornadoManager.server_onUnload( self )
    self:sv_save()
end

function TornadoManager.sv_loadDeserts( self )
	-- Load overworld cell data
	local worldId = 1 -- Overworld only
	local worldCellData = GetCellDataStorage( worldId )
	for y, yData in pairs( worldCellData ) do
		for x, xyData in pairs( yData ) do
			local isDesert = valueExists( xyData.tags, "DESERT" )
			if isDesert then
				local cellKey = CellKey( x, y )
				self.sv.desertCells[cellKey] = sm.vec3.new( x * 64 + 32, y * 64 + 32, 0 )
			end
		end
	end
	self.sv.desertsLoaded = true
end

function TornadoManager.Sv_OnCellLoaded( world, x, y )
    if g_tornadoManagerServer then
        g_tornadoManagerServer:sv_onCellLoaded( world, x, y )
    end
end

function TornadoManager.sv_onCellLoaded( self, world, x, y )
    if self.sv.world == nil then
        self.sv.world = world
    end
    local nodes = sm.cell.getNodesByTag( x, y, "TORNADO", world )
    local cellKey = CellKey( x, y )
    local currentTick = sm.game.getCurrentTick()
    for index,data in reverse_ipairs( self.sv.unloadedTornadoes ) do
        if cellKey == data.previousCell then
            if not ( ( currentTick - data.creationTick ) >= TornadoCellRespawnTicks ) then
                local trigger = sm.areaTrigger.createBox( TornadoDimensions, data.position + TornadoHeightOffset, sm.quat.identity(), sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.character, nil, world )
                trigger:bindOnStay( "trigger_onTornadoStayServer", self )
                self.sv.activeTornadoes[self.sv.saved.tornadoIdCounter] = { tick = currentTick, creationTick = data.creationTick, trigger = trigger, position = data.position, direction = data.direction, targetDirection = data.targetDirection, previousCell = cellKey, tickCounter = EnvironmentCheckFrequency }
                self.sv.saved.tornadoIdCounter = self.sv.saved.tornadoIdCounter + 1
            end
            self.sv.unloadedTornadoes[index] = nil
            self.sv.dirty = true
        end
    end
    if #nodes > 0 then
        if self.sv.saved.visitedTornadoCells[cellKey] == nil or ( ( currentTick - self.sv.saved.visitedTornadoCells[cellKey] ) > TornadoCellRespawnTicks ) then
            self.sv.saved.visitedTornadoCells[cellKey] = currentTick
        else
            return
        end
        for _, node in ipairs( nodes ) do
            local random = math.random()
            if random < TornadoSpawnChance then
                local position = node.position
                local multiplier = math.random() > 0.5 and 1 or -1
                local direction = sm.vec3.new( math.random() * multiplier, math.random() * multiplier, 0 ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
                local targetDirection = sm.vec3.new( math.random() * multiplier, math.random() * multiplier, 0 ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
                local trigger = sm.areaTrigger.createBox( TornadoDimensions, position + TornadoHeightOffset, sm.quat.identity(), sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.character, nil, world )
                trigger:bindOnStay( "trigger_onTornadoStayServer", self )
                self.sv.activeTornadoes[self.sv.saved.tornadoIdCounter] = { tick = currentTick, creationTick = currentTick, trigger = trigger, position = position, direction = direction, targetDirection = targetDirection, previousCell = cellKey, tickCounter = EnvironmentCheckFrequency }
                self.sv.saved.tornadoIdCounter = self.sv.saved.tornadoIdCounter + 1
            end
        end
        self.sv.dirty = true
    end
end

function TornadoManager.sv_sendClientData( self )
    if g_tornadoManagerServer then
        sm.event.sendToScriptableObject( g_tornadoManagerServer.scriptableObject, "sv_e_sendClientData" )
    end
end

function TornadoManager.sv_e_sendClientData( self )
    local data = {}
    for tornadoId,tornadoData in pairs( self.sv.activeTornadoes ) do
        data[tornadoId] = {
            position = tornadoData.position,
            direction = tornadoData.direction,
            targetDirection = tornadoData.targetDirection,
            tick = tornadoData.tick,
            needsUpdate = shallowcopy( tornadoData.needsUpdate ),
            environments = tornadoData.environments
            }
            tornadoData.needsUpdate = false
    end
    self.network:setClientData( data )
end

function TornadoManager.Sv_OnWorldFixedUpdate( world )
    if g_tornadoManagerServer then
        g_tornadoManagerServer:sv_OnWorldFixedUpdate( world )
    end
end

function TornadoManager.sv_unloadTornado( self, tornadoId )
    local data = self.sv.activeTornadoes[tornadoId]
    self.sv.unloadedTornadoes[#self.sv.unloadedTornadoes+1] = { position = data.position, direction = data.direction, targetDirection = data.targetDirection, tick = data.tick, creationTick = data.creationTick, previousCell = data.previousCell }
    data.trigger:destroy()
    self.sv.activeTornadoes[tornadoId] = nil
    self.sv.dirty = true
end

function TornadoManager.sv_OnWorldFixedUpdate( self, world )
    if self.sv.world == nil then
        self.sv.world = world
    end
    if self.sv.dirty then
        self:sv_sendClientData()
        self.sv.dirty = false
    end
    if not self.sv.desertsLoaded and g_overworldTerrainLoaded then
        self:sv_loadDeserts()
    end
    local currentTick = sm.game.getCurrentTick()
    local tornadoesToUnload = {}
    for tornadoId, data in pairs( self.sv.activeTornadoes ) do
        if not ( ( currentTick - data.creationTick ) >= TornadoCellRespawnTicks ) then
            data.position, data.direction, data.targetDirection = setPosAndDir( data.position, data.direction, data.targetDirection, self.sv.world )
            local x = math.floor( data.position.x / 64 )
            local y = math.floor( data.position.y / 64 )
            local currentCell = CellKey( x, y )

            if not self.sv.world:isCellLoadedServer( x, y ) then
                if data.unloadedTickCounter == nil then
                    data.unloadedTickCounter = 0
                end
                data.unloadedTickCounter = data.unloadedTickCounter + 1
                if data.unloadedTickCounter >= TornadoUnloadTicks then
                    tornadoesToUnload[#tornadoesToUnload+1] = tornadoId
                end
            end
            data.trigger:setWorldPosition( data.position + TornadoHeightOffset )
            if currentCell ~= data.previousCell and not IsEmptyTable( self.sv.desertCells ) then
                local cellAheadX = math.floor( ( data.position.x + data.targetDirection.x * 64 ) / 64 )
                local cellAheadY = math.floor( ( data.position.y + data.targetDirection.y * 64 ) / 64 )
                local cellAheadKey = CellKey( cellAheadX, cellAheadY )
                if not self.sv.desertCells[cellAheadKey] or not self.sv.world:isCellLoadedServer( cellAheadX, cellAheadY ) then
                    local nearbyDesertCellCenterPoints = {}
                    for i = -1, 1 do
                        for j = -1, 1 do
                            local key = CellKey( x + i, y + j )
                            local cellCenterPos = self.sv.desertCells[key]
                            if cellCenterPos and self.sv.world:isCellLoadedServer( x + i, y + j ) then
                                local newDirection = ( cellCenterPos - sm.vec3.new( data.position.x, data.position.y, 0 ) ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
                                nearbyDesertCellCenterPoints[#nearbyDesertCellCenterPoints+1] = newDirection
                            end
                        end
                    end
                    if #nearbyDesertCellCenterPoints > 0 then
                        local direction = nearbyDesertCellCenterPoints[math.random( 1, #nearbyDesertCellCenterPoints )]
                        data.targetDirection = direction
                        data.needsUpdate = true
                        self.sv.dirty = true
                    end
                end
                data.previousCell = currentCell
            end
            data.tickCounter = data.tickCounter + 1
            if data.tickCounter >= EnvironmentCheckFrequency then
                data.tickCounter = 0
                local success,result = sm.physics.raycast( data.position + sm.vec3.new( 0, 0, 1 ), data.position - sm.vec3.new( 0, 0, 1 ), nil, sm.physics.filter.waterArea, self.sv.world )
                local previousEnvironments = shallowcopy( data.environments ) or {}
                data.environments = {}
                if success then
                    local color = sm.color.new( 0, 0.5, 1 )
                    local userData = result:getAreaTrigger():getUserData()
                    if userData.chemical then
                        color = sm.color.new( 1, 0.4, 0.7, 1 )
                    elseif userData.oil then
                        color = sm.color.new( 0, 0, 0, 1 )
                    end
                    data.environments[EnvironmentTypes.water] = color
                end
                if self.sv.desertCells[currentCell] then
                    data.environments[EnvironmentTypes.sand] = true
                elseif not data.environments[EnvironmentTypes.water] then
                    data.environments[EnvironmentTypes.grass] = true
                end
                local contents = sm.physics.getSphereContacts( data.position + TornadoHeightOffset, TornadoRadius * 1.5, self.sv.world )
                for _,harvestable in ipairs( contents.harvestables ) do
                    if harvestable:getType() == "tree" then
                        data.environments[EnvironmentTypes.leaves] = harvestable:getColor()
                        break
                    end
                end
                for _,value in pairs( EnvironmentTypes ) do
                    if data.environments[value] ~= previousEnvironments[value] then
                        data.needsUpdate = true
                        self.sv.dirty = true
                        break
                    end
                end
            end
            data.tick = currentTick
        else
            self.sv.activeTornadoes[tornadoId] = nil
            self.sv.dirty = true
        end
    end

    for _,tornadoId in ipairs( tornadoesToUnload ) do
        self:sv_unloadTornado( tornadoId )
    end

    if not IsEmptyTable( self.sv.activeTornadoes ) then
        self.sv.syncCounter = self.sv.syncCounter + 1
        if self.sv.syncCounter >= SyncTickInterval then
            self.sv.syncCounter = 0
            self.sv.dirty = true
        end
    end
    if not IsEmptyTable( self.sv.saved.tornadoSaveData ) then
        for tornadoId, data in pairs( self.sv.saved.tornadoSaveData ) do
            local x = math.floor( data.position.x / 64 )
            local y = math.floor( data.position.y / 64 )
            local cellKey = CellKey( x, y )
            local cellIsLoaded = world:isCellLoadedServer( x, y )
            if not ( ( currentTick - data.creationTick ) >= TornadoCellRespawnTicks ) then
                if cellIsLoaded then
                    local trigger = sm.areaTrigger.createBox( TornadoDimensions, data.position + TornadoHeightOffset, sm.quat.identity(), sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.character, nil, world )
                    trigger:bindOnStay( "trigger_onTornadoStayServer", self )
                    self.sv.activeTornadoes[tornadoId] = { tick = sm.game.getCurrentTick(), creationTick = data.creationTick, trigger = trigger, position = data.position, direction = data.direction, targetDirection = data.targetDirection, previousCell = cellKey, tickCounter = data.tickCounter }
                else
                    self.sv.unloadedTornadoes[#self.sv.unloadedTornadoes+1] = { position = data.position, direction = data.direction, targetDirection = data.targetDirection, tick = sm.game.getCurrentTick(), creationTick = data.creationTick, previousCell = cellKey, tickCounter = data.tickCounter }
                end
            end
        end
        self.sv.dirty = true
        self.sv.saved.tornadoSaveData = {}
    end
    if IsEmptyTable( self.sv.activeTornadoes ) then
        self.sv.saved.tornadoIdCounter = 1
    end
    self.sv.saveCounter = self.sv.saveCounter + 1
    if self.sv.saveCounter >= SaveFrequency then
        self:sv_save()
        self.sv.saveCounter = 0
    end
end

function TornadoManager.trigger_onTornadoStayServer( self, trigger, results )
    for _,result in ipairs( results ) do
        if sm.exists( result ) and type( result ) == "Character" and not result:isPlayer() and not isAnyOf( result:getCharacterType(), NonTumbleUnits ) then
            if not result:isTumbling() then
                result:setTumbling( true )
            end
        end
    end
end

function TornadoManager.Sv_OnCellUnloaded( x, y )
    if g_tornadoManagerServer then
        g_tornadoManagerServer:sv_onCellUnloaded( x, y )
    end
end

function TornadoManager.sv_onCellUnloaded( self, x, y )
    local cellKey = CellKey( x, y )
    local removedIds = {}
    for tornadoId, data in pairs( self.sv.activeTornadoes ) do
        if data.previousCell == cellKey then
           removedIds[#removedIds+1] = tornadoId
        end
    end
    for _,tornadoId in ipairs( removedIds ) do
        self:sv_unloadTornado( tornadoId )
    end
end

local function CalculateImpulse( result, trigger )
    local impulse = sm.vec3.new( 0, 0, 0 )
    local targetPos = result:getWorldPosition()
    local isBody = type( result ) == "Body"
    if isBody then
        targetPos = result:getCenterOfMassPosition()
    end
    targetPos.z = 0
    local tornadoPos = trigger:getWorldPosition()
    tornadoPos.z = 0
    local direction = ( targetPos - tornadoPos ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
    local crossDirection = ( sm.vec3.cross( direction, sm.vec3.new( 0, 0, 1 ) ) ):rotateZ( math.rad( -40 ) )
    local distanceFromCenter = direction:length()
    crossDirection = crossDirection - ( direction * distanceFromCenter * DistanceFromCenterModifier )

    if type( result ) == "Character" then
        local vertical = TornadoPlayerVerticalImpulse
        local horizontal = crossDirection * TornadoPlayerHorizontalForce
        if not result:isPlayer() then
            local mass = result:getMass()
            if mass <= 0 then
                mass = 1
            end
            local massMultiplier = mass / MaxHorizontalMassForce + 0.5 -- higher horizontal mass force for heavier characters
            if mass > MaxAffectedCharacterMass then
                return nil
            end
            vertical = sm.vec3.new( 0, 0, 1 ) * mass * CharacterVerticalModifier
            horizontal = crossDirection * TornadoPlayerHorizontalForce * CharacterHorizontalModifier * massMultiplier * ( 1 + math.random( -HorizontalDeviationPercentage, HorizontalDeviationPercentage ) * 0.01 )
        end
        impulse = vertical + horizontal
    elseif isBody then
        impulse = {}
        local allBodies = result:getCreationBodies()
        local totalMass = 1
        for _,body in ipairs( allBodies ) do
            totalMass = totalMass + body:getMass()
        end
        if totalMass > MaxAllowedMass then
            return nil
        end
        for _,body in ipairs( allBodies ) do
            local mass = body:getMass()
            if mass <= 0 then
                mass = 1
            end
            impulse[body.id] = ClampVector( ( ( TornadoCreationVerticalForce + crossDirection * TornadoCreationHorizontalForce ) * ( mass / totalMass ) ), CreationMaxImpulsePerBody )
        end
    else
        sm.log.error( "TornadoManager:CalculateImpulse - Unknown type:", type( result ) )
    end
    return impulse
end

-- Client

function TornadoManager.client_onCreate( self )
    g_tornadoManagerClient = self
    self.cl = {}
    self.cl.tornadoData = {}
    self.cl.triggersToIds = {}
    self.cl.world = WorldManager.Cl_GetWorld( "overworld" )
    self.cl.delayedSyncData = nil
end

function TornadoManager.cl_handleSyncData( self, data )
    if data ~= nil then
        local serverTick = sm.game.getServerTick()
        for tornadoId,tornadoData in pairs( data ) do
            if self.cl.tornadoData[tornadoId] == nil then
                local position = tornadoData.position
                local direction = tornadoData.direction
                local targetDirection = tornadoData.targetDirection
                local effect = sm.effect.createEffect( "Environment - Tornado" )
                local environmentEffects = {
                    [EnvironmentTypes.sand] = { effect = sm.effect.createEffect( "Environment - Tornado_sand" ), color = nil },
                    [EnvironmentTypes.grass] = { effect = sm.effect.createEffect( "Environment - Tornado_grass" ), color = nil },
                    [EnvironmentTypes.leaves] = { effect = sm.effect.createEffect( "Environment - Tornado_leaves" ), color = nil },
                    [EnvironmentTypes.water] = { effect = sm.effect.createEffect( "Environment - Tornado_water"), color = nil }
                }
                
                local tickDif = serverTick - tornadoData.tick
                for _ = 1, tickDif do
                    position, direction, targetDirection = setPosAndDir( position, direction, targetDirection, self.cl.world )
                end
                effect:setPosition( position )
                effect:setWorld( self.cl.world )
                effect:start()
                for _, envEffectData in pairs( environmentEffects ) do
                    envEffectData.effect:setPosition( position )
                    envEffectData.effect:setWorld( self.cl.world )
                end
                if tornadoData.environments then
                    for type,value in pairs( tornadoData.environments ) do
                        if value ~= nil then
                            if type == EnvironmentTypes.leaves or type == EnvironmentTypes.water then
                                environmentEffects[type].effect:setParameter( "Color", value )
                            end
                            environmentEffects[type].effect:start()
                        end
                    end
                end
                self.cl.tornadoData[tornadoId] = { effect = effect, environmentEffects = environmentEffects, position = position, direction = direction, targetDirection = targetDirection }
            elseif self.cl.tornadoData[tornadoId] and tornadoData.needsUpdate then
                local tickDif = serverTick - tornadoData.tick
                for _ = 1, tickDif do
                    self.cl.tornadoData[tornadoId].position, self.cl.tornadoData[tornadoId].direction, self.cl.tornadoData[tornadoId].targetDirection = setPosAndDir( tornadoData.position, tornadoData.direction, tornadoData.targetDirection, self.cl.world )
                end
                self.cl.tornadoData[tornadoId].effect:setPosition( tornadoData.position )
                self.cl.tornadoData[tornadoId].tick = tornadoData.tick
                if tornadoData.environments then
                    for type,value in pairs( tornadoData.environments ) do
                        if type == EnvironmentTypes.leaves or type == EnvironmentTypes.water then
                            if self.cl.tornadoData[tornadoId].environmentEffects[type].color ~= value then
                                self.cl.tornadoData[tornadoId].environmentEffects[type].effect:stop()
                                self.cl.tornadoData[tornadoId].environmentEffects[type].effect:setParameter( "Color", value )
                            end
                        end
                        if value and not self.cl.tornadoData[tornadoId].environmentEffects[type].effect:isPlaying() then
                            self.cl.tornadoData[tornadoId].environmentEffects[type].effect:start()
                        end
                    end
                    for type,effectData in pairs( self.cl.tornadoData[tornadoId].environmentEffects ) do
                        if tornadoData.environments[type] == nil or not tornadoData.environments[type] then
                            effectData.effect:stop()
                        end
                    end
                else
                    for _,effectData in pairs( self.cl.tornadoData[tornadoId].environmentEffects ) do
                        if effectData.effect:isPlaying() then
                            effectData.effect:stop()
                        end
                    end
                end
            end
        end
        for tornadoId,_ in pairs( self.cl.tornadoData ) do
            if data[tornadoId] == nil then
                self.cl.tornadoData[tornadoId].effect:stop()
                for _,effectData in pairs( self.cl.tornadoData[tornadoId].environmentEffects ) do
                    effectData.effect:stop()
                end
                if self.cl.tornadoData[tornadoId].trigger then
                    self.cl.tornadoData[tornadoId].trigger:destroy()
                end
                self.cl.tornadoData[tornadoId] = nil
            end
        end
    end
end

function TornadoManager.client_onClientDataUpdate( self, data )
    if self.cl.world == nil then
        self.cl.world = WorldManager.Cl_GetWorld( "overworld" )
    end
    if self.cl.world == nil then
        self.cl.delayedSyncData = data
        return
    end
    self:cl_handleSyncData( data )
end

function TornadoManager.Cl_OnWorldFixedUpdate( world )
    if g_tornadoManagerClient then
        g_tornadoManagerClient:cl_onWorldFixedUpdate( world )
    end
end

function TornadoManager.cl_onWorldFixedUpdate( self, world )
    if self.cl.world == nil then
        self.cl.world = world
    end
    if not self.cl.world then
        return
    end
    if self.cl.delayedSyncData then
        self:cl_handleSyncData( self.cl.delayedSyncData )
        self.cl.delayedSyncData = nil
    end
    for tornadoId,data in pairs( self.cl.tornadoData ) do
        if data.trigger == nil then
            local trigger = sm.areaTrigger.createBox( TornadoDimensions, data.position + TornadoHeightOffset, sm.quat.identity(), sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.character, nil, world )
            trigger:bindOnStay( "trigger_onTornadoStayClient", self )
            trigger:bindOnEnter( "trigger_onTornadoEnterClient", self )
            data.trigger = trigger
            self.cl.triggersToIds[trigger.id] = tornadoId
        end
        data.position, data.direction, data.targetDirection = setPosAndDir( data.position, data.direction, data.targetDirection, self.cl.world )
        data.effect:setPosition( data.position )
        for _,effectData in pairs( data.environmentEffects ) do
            effectData.effect:setPosition( data.position )
        end
        data.trigger:setWorldPosition( data.position + TornadoHeightOffset )
    end
end

function TornadoManager.trigger_onTornadoStayClient( self, trigger, results )
    local affectedCreationIds = {}
    if sm.exists( trigger ) then
        for _, result in ipairs( results ) do
            if sm.exists( result ) then
                local impulse = CalculateImpulse( result, trigger )
                if not impulse then
                    return
                end
                if type( result ) == "Character" then
                    if result:isTumbling() then
                        result:applyTumblingImpulse( impulse )
                    else
                        sm.physics.applyImpulse( result, impulse, true )
                    end
                elseif type( result ) == "Body" then
                    local creationId = result:getCreationId()
                    if not affectedCreationIds[creationId] then
                        affectedCreationIds[creationId] = true
                        local allBodies = result:getCreationBodies()
                        for _,body in ipairs( allBodies ) do
                            sm.physics.applyImpulse( body, impulse[body.id], true )
                        end
                    end
                end
            end
        end
    end
end

function TornadoManager.trigger_onTornadoEnterClient( self, trigger, results )
    local tornadoId = self.cl.triggersToIds[trigger.id]
    if tornadoId == nil then
        return
    end
    if self.cl.tornadoData[tornadoId] == nil then
        return
    end
    for _, result in ipairs( results ) do
        if sm.exists( result ) then
            if type( result ) == "Character" then
                sm.effect.playEffect( "Environment - Pickup", result.worldPosition, nil, nil, nil, { Size = 0.5 } )
            elseif type( result ) == "Body" then
                if self.cl.tornadoData[tornadoId].creationEffectTicks == nil then
                    self.cl.tornadoData[tornadoId].creationEffectTicks = {}
                end
                if self.cl.tornadoData[tornadoId].creationEffectTicks[result:getCreationId()] == nil or ( sm.game.getCurrentTick() - self.cl.tornadoData[tornadoId].creationEffectTicks[result:getCreationId()] ) >= 80 then
                    self.cl.tornadoData[tornadoId].creationEffectTicks[result:getCreationId()] = sm.game.getCurrentTick()

                    local allBodies = result:getCreationBodies()
                    local totalMass = 1
                    for _,body in ipairs( allBodies ) do
                        totalMass = totalMass + body:getMass()
                    end
                    if totalMass > MaxAllowedMass then
                        return
                    end
                    sm.effect.playEffect( "Environment - Pickup", result.worldPosition, nil, nil, nil, { Size = totalMass / MaxAllowedMass } )
                end
            end
        end
    end
end