dofile( "$GAME_DATA/Scripts/game/managers/EffectManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

MininghubLightManager = class( nil )
MininghubLightManager.isSaveObject = true

local LightsOnDelayTicks = 9.1 * 40  -- Wait for kinematic arms to fully deploy

-- server

function MininghubLightManager.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.activationTick = sm.game.getCurrentTick()
        self.sv.saved.params = self.params
        self.storage:save( self.sv.saved )
    end

    local position = self.sv.saved.params.position
    local world = self.scriptableObject.world
    self.sv.tileKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, position )

    -- If already completed (reload safety), schedule destruction
    if TileStorageManager.Sv_GetValueInSubTable( self.sv.tileKey, TILESTORAGE_FLAGS_TABLE, "minehub:lights.activated" ) then
        self.scriptableObject:destroy()
        return
    end
 
    
    -- Persistently activate the light kinematics (auto-activate when their cells load)
    if sm.game.getCurrentTick() == self.sv.saved.activationTick then
        KinematicManager.Sv_Activate( self.sv.tileKey, "mininghub.pylon" )
        KinematicManager.Sv_Activate( self.sv.tileKey, "activateLights", { persistent = true } )
        EffectManager.Sv_ActivateEventEffect( world, "effectEvent.lightActivation", position )
    end

    -- Cinematic (skipped for now)
    -- EffectManager.Sv_PlayNamedCinematic( { name = "cinematic.minehublights", callbackData = { world = self.sv.saved.overworld } } )
end

function MininghubLightManager.server_onFixedUpdate( self )
    if sm.game.getCurrentTick() - self.sv.saved.activationTick >= LightsOnDelayTicks then
        local position = self.sv.saved.params.position
        local world = self.scriptableObject.world

        -- Set the lights.activated tilestorage flag (handles ts:show / ts:hide on future cell loads)
        SetTileStorageFlag( self.sv.tileKey, "minehub:lights.activated" )
        
        sm.event.sendToGame( "sv_reloadTile", { pos = position, world = world } )
        
        -- Update effects for already-loaded cells in this tile
        EffectManager.Sv_UpdateTagFilteredEffectsForTile( world, position, { "minehub:lights.activated" } )

        -- Update render settings for the mininghub zone
        sm.event.sendToWorld( world, "sv_e_lightUpMininghub", { zoneId = world:getZoneId( position ) } )

        -- Notify quest that lights are on
        QuestManager.Sv_SendEvent( "mininghub_lights_on" )

        self.scriptableObject:destroy()
    end
end