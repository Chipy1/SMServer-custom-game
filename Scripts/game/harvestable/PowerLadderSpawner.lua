dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/powerladder_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/harvestable/PowerLadderRail.lua" )

PowerLadderSpawner = class( )

PowerLadderSpawner.powerLadderHandleUuid = sm.uuid.new( "446df892-0b0c-42c9-8625-9d94f8ba53ea" )

local InteractCooldownTicks = 20
local MaximumHandlebarNodeSearchDistance = 5

function PowerLadderSpawner.server_onCreate( self )
    self.sv = {}
    self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
    self.sv.saved = self.storage:load()
    if not self.sv.saved then
        self.sv.saved = { active = false, railTag = GetRailTag( self.tags ) }
        if self.params then
            self.sv.saved.backwards = self.params.backwards
        end
        if self.sv.saved.railTag == nil then
            self.sv.saved.active = true
            sm.log.warning( "PowerLadderSpawner missing rail tag! Assuming active state but rail will not react." )
        else
            local powerTag = "ts:rail:powered:"
            if string.sub( self.sv.saved.railTag, 1, string.len( powerTag ) ) == powerTag then
                self.sv.saved.active = true -- powered rails start active
            else
                local tileKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
                local rail = GetRailStorage( tileKey, self.sv.saved.railTag )
                if rail then
                    TileStorageManager.Sv_SetValueInSubTable( tileKey, POWERLADDER_RAIL_TABLE, self.sv.saved.railTag, rail )
                    self.sv.saved.active = rail.powered
                end
            end
        end
        self.storage:save( self.sv.saved )
    end

    
    local node = FindClosestMatchingNode( self.harvestable:getPosition(), { "HANDLEBARTRACK" }, MaximumHandlebarNodeSearchDistance )
    if node then
        self.sv.handlebarTrack = node
    end

    if self.sv.saved then
        self:sv_setClientData()
    end
end

function PowerLadderSpawner.sv_setClientData( self )
    self.network:setClientData( { active = self.sv.saved.active, handlebarTrackNode = self.sv.handlebarTrack } )
end

function PowerLadderSpawner.server_onFixedUpdate( self )
    if self.sv.saved.active == false and self.sv.saved.railTag then
        -- for now the rails don't power off again once powered on
        local rail = GetRailStorage( self.sv.tileStorageKey, self.sv.saved.railTag )
        if rail and rail.powered == true then
            self.sv.saved.active = true
            self.storage:save( self.sv.saved )
            self:sv_setClientData()
        end
    end
    
    -- special case for boss warehouse rails
    if TileStorageManager.Sv_SyncedGetValueInSubTable( self.sv.tileStorageKey, TILESTORAGE_FLAGS_TABLE, "destroyed" ) == true then
        self.harvestable:destroy()
        --send to all the rail parts
        local rail = GetRailStorage( self.sv.tileStorageKey, self.sv.saved.railTag )
        if rail and rail.collection then
            for _, railPart in pairs( rail.collection ) do
                if sm.exists( railPart ) then
                    sm.event.sendToHarvestable( railPart, "sv_e_destroyRail" )
                end
            end
            TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, POWERLADDER_RAIL_TABLE, self.sv.saved.railTag, nil )
        end
    end

    if self.sv.handlebarTrack == nil then
        local node = FindClosestMatchingNode( self.harvestable:getPosition(), { "HANDLEBARTRACK" }, MaximumHandlebarNodeSearchDistance )
        if node then
            self.sv.handlebarTrack = node
            self:sv_setClientData()
        end
    end
end

function PowerLadderSpawner.sv_n_spawn( self, args )
    if self.sv.handlebarTrack then
        if self.sv.handlebarTrack.params == nil then
            sm.log.error( "Handlebar track params missing!" )
            return
        end
        if self.sv.handlebarTrack.params.track then
            local lift = sm.harvestable.createHarvestable( PowerLadderSpawner.powerLadderHandleUuid,
                self.sv.handlebarTrack.position, self.sv.handlebarTrack.rotation )
            if lift then
                lift:setParams( { track = self.sv.handlebarTrack.params.track, rider = args.rider, railTag = self.sv.saved.railTag, backwards = self.sv.saved.backwards } )
            end
            return
        end
    end
    sm.log.error( "Lift spawner track not found" )
end

function PowerLadderSpawner.client_onCreate( self, character )
    self.cl = {}
    self.cl.active = false
    self.cl.interactTick = 0
end

function PowerLadderSpawner.client_onClientDataUpdate( self, data )
    self.cl.active = data.active
    if self.cl.active and data.handlebarTrackNode then
        if self.cl.initInteraction then
            return
        end
        local triggerSize = sm.vec3.new( 1.5, 0.5, 0.25 )
        local triggerRotation = data.handlebarTrackNode.rotation
        local triggerPosition = data.handlebarTrackNode.position
        self.cl.interactionTrigger = sm.areaTrigger.createBox( triggerSize, triggerPosition, triggerRotation, nil, nil, nil, sm.areaTrigger.areaTriggerProxyType.interactable )
        self.cl.interactionTrigger:bindCanInteract( "cl_t_canInteract", self )
        self.cl.interactionTrigger:bindOnInteract( "cl_t_onInteract", self )
        self.cl.interactionEffect = sm.effect.createEffect( "WarehouseLadder - Handle_preview" )
        self.cl.interactionEffect:setPosition( triggerPosition )
        self.cl.interactionEffect:setRotation( triggerRotation )
        self.cl.interactionEffect:start()
        self.cl.initInteraction = true
    end
end

function PowerLadderSpawner.client_onDestroy( self )
    if self.cl.interactionTrigger then
        self.cl.interactionTrigger:destroy()
        self.cl.interactionTrigger = nil
    end
    if self.cl.interactionEffect then
        self.cl.interactionEffect:stopImmediate()
        self.cl.interactionEffect:destroy()
        self.cl.interactionEffect = nil
    end
end

function PowerLadderSpawner.cl_t_canInteract( self, _, character )






    if self.cl.active then
        if character:getCharacterType() == unit_mechanic and not character:isTumbling() then
            sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "#{INTERACTION_USE}" )
            return true
        end
    end
	return false
end

function PowerLadderSpawner.cl_t_onInteract( self, _, character, state )
    local currentTick = sm.game.getCurrentTick()
	if state == true and currentTick - self.cl.interactTick > InteractCooldownTicks then
        self.cl.interactTick = currentTick
        self.network:sendToServer( "sv_n_spawn", { rider = character } )
	end
end