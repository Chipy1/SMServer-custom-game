dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/Kinematic.lua" )

KinematicBridgePart = class( Kinematic )

function KinematicBridgePart.server_onCreate( self )
    Kinematic.server_onCreate( self )
    self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
    
    if TileStorageManager.Sv_SyncedGetValueInSubTable( self.sv.tileStorageKey, TILESTORAGE_FLAGS_TABLE, "raised" ) then
        self.harvestable:destroy()
        return
    end

    if not ( self.params and self.params.eventListen ) then
        sm.log.error( "bridge kinematic event listen missing" )
        return
    end
end

function KinematicBridgePart.server_onFixedUpdate( self, timeStep )

    -- become active when manager appears
    if g_BridgeManager and not self.sv.active then
        self.sv.active = true
    end
    -- remove self when the manager disappears
    if self.sv.active and not g_BridgeManager then
        self.harvestable:destroy()
        return
    end

    Kinematic.server_onFixedUpdate( self, timeStep )
end
    
function KinematicBridgePart.client_onUpdate( self, dt )
    if ( not self.cl.hidden ) and g_BridgeManagerClient and g_BridgeManagerClient:cl_isBridgeRaised() then
        self.cl.hidden = true
        self.harvestable:setSubMeshVisible( "m_uvmaterial_industrial", false )
        self.harvestable:setSubMeshVisible( "m_tiled_concrete02", false )
        self.harvestable:setSubMeshVisible( "m_tiled_metal04", false )
        self.harvestable:setSubMeshVisible( "m_tiled_metal03", false )
    end
end
