dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

ExplosionTriggerManager = class( nil )

function ExplosionTriggerManager.server_onCreate( self )
    g_explosionTriggerManagerServer = self

    self.sv = {}
    self.sv.createdTriggers = {}

    self.sv.saved = sm.storage.load( STORAGE_CHANNEL_EXPLOSION_MANAGER )
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.triggeredExplosions = {}
        self.sv.saved.delayedExplosions = {}
        sm.storage.save( STORAGE_CHANNEL_EXPLOSION_MANAGER, self.sv.saved )
    end
end

function ExplosionTriggerManager.server_onUnload( self )
	sm.storage.save( STORAGE_CHANNEL_EXPLOSION_MANAGER, self.sv.saved )
end
function ExplosionTriggerManager.Sv_OnCellLoaded( x, y, world )
    if g_explosionTriggerManagerServer then
        g_explosionTriggerManagerServer:sv_onCellLoaded( x, y, world )
    end
end

function ExplosionTriggerManager.sv_onCellLoaded( self, x, y, world )
    local nodes = sm.cell.getNodesByTag( x, y, "EXPLOSION_TRIGGER", world )
    local cellKey = CellKey( x, y )
    for _,node in ipairs( nodes ) do
        if node.params.explosionTag ~= "" then
            if self.sv.createdTriggers[world.id.."|"..cellKey] == nil then
                self.sv.createdTriggers[world.id.."|"..cellKey] = {}
            end
            local areaTrigger = sm.areaTrigger.createBox( node.scale / 2, node.position, node.rotation, sm.areaTrigger.filter.character )
            areaTrigger:bindOnEnter( "trigger_onEnter", self )
            self.sv.createdTriggers[world.id.."|"..cellKey][areaTrigger.id] = { areaTrigger = areaTrigger, explosionTag = node.params.explosionTag }
        end
    end
end

function ExplosionTriggerManager.Sv_OnCellUnloaded( x, y, world )
    if g_explosionTriggerManagerServer then
        g_explosionTriggerManagerServer:sv_onCellUnloaded( x, y, world )
    end
end

function ExplosionTriggerManager.sv_onCellUnloaded( self, x, y, world )
    local cellKey = CellKey( x, y )
    if self.sv.createdTriggers[world.id.."|"..cellKey] ~= nil then
        for _,triggerData in pairs( self.sv.createdTriggers[world.id.."|"..cellKey] ) do
            sm.areaTrigger.destroy( triggerData.areaTrigger )
        end
        self.sv.createdTriggers[world.id.."|"..cellKey] = nil
    end
end

function ExplosionTriggerManager.trigger_onEnter( self, trigger, results )
    if not TriggerResultContainsAnyPlayer( results ) then
        return
    end
    local triggerPos = trigger:getWorldPosition()
    local cellX = math.floor( triggerPos.x / 64 )
    local cellY = math.floor( triggerPos.y / 64 )
    local xMin,xMax,yMin,yMax = GetTileRanges( triggerPos, trigger.world.id )
    local cellKey = CellKey( cellX, cellY )
    if self.sv.createdTriggers[trigger.world.id.."|"..cellKey] ~= nil then
        local explosionTag = self.sv.createdTriggers[trigger.world.id.."|"..cellKey][trigger.id].explosionTag
        local tileKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( trigger.world, triggerPos )
        local tileExplosionKey = explosionTag.."|"..tileKey
        if not self.sv.saved.triggeredExplosions[tileExplosionKey] then
            local triggered = false
            for x = xMin, xMax do
                for y = yMin, yMax do
                    local nodes = sm.cell.getNodesByTag( x, y, "EXPLOSION_POINT", trigger.world )
                    for _,node in ipairs( nodes ) do
                        if node.params and node.params.explosionTag and node.params.explosionTag == explosionTag
                            and TileStorageManager.Sv_GetTileStorageKeyFromPosition( trigger.world, node.position ) == tileKey then
                            local explosionLevel = node.params.explosionLevel or 1
                            local damage = ( node.params.damage and node.params.damage > 0 ) and node.params.damage or nil
                            local explosionRadius = node.scale.x / 2
                            if node.params.delay ~= 0.0 then
                                local delayedExplosionData = {}
                                delayedExplosionData.node = node
                                delayedExplosionData.world = trigger.world
                                delayedExplosionData.tickCounter = 0
                                delayedExplosionData.level = explosionLevel
                                delayedExplosionData.radius = explosionRadius
                                delayedExplosionData.delay = math.floor( node.params.delay * 40 )
                                delayedExplosionData.damage = damage
                                self.sv.saved.delayedExplosions[#self.sv.saved.delayedExplosions+1] = delayedExplosionData
                            else
                                sm.physics.explode( node.position, explosionLevel, explosionRadius, explosionRadius, explosionLevel * 3, explosionRadius < 2.5 and "PropaneTank - ExplosionSmall" or "PropaneTank - ExplosionBig", nil, nil, nil, damage )
                            end
                            triggered = true
                        end
                    end
                end
            end
            if triggered then
                self.sv.saved.triggeredExplosions[tileExplosionKey] = true
                sm.storage.save( STORAGE_CHANNEL_EXPLOSION_MANAGER, self.sv.saved )
            end
        end
    end
end

function ExplosionTriggerManager.server_onFixedUpdate( self )
    for i, explosionData in reverse_ipairs( self.sv.saved.delayedExplosions ) do
        explosionData.tickCounter = explosionData.tickCounter + 1
        if explosionData.tickCounter >= explosionData.delay then
            sm.physics.explode( explosionData.node.position, explosionData.level, explosionData.radius, explosionData.radius, explosionData.level * 3, explosionData.radius < 2.5 and "PropaneTank - ExplosionSmall" or "PropaneTank - ExplosionBig", nil, nil, explosionData.world, explosionData.damage )
            table.remove( self.sv.saved.delayedExplosions, i )
            sm.storage.save( STORAGE_CHANNEL_EXPLOSION_MANAGER, self.sv.saved )
        end
    end
end