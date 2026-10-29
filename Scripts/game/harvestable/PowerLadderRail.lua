dofile( "$SURVIVAL_DATA/Scripts/game/powerladder_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

PowerLadderRail = class()

local States = {
    Off = 1,
    On = 2,
    ActiveForward = 3,
    ActiveBackward = 4
}

function PowerLadderRail.server_onCreate( self )
    self.sv = {}

    if self.tags then
        self.sv.railTag = GetRailTag( self.tags )
    end

    self.sv.powered = false
    if self.sv.railTag == nil then
        self.sv.powered = true --cannot track rails without a tag, assume powered
    else
        local powerTag = "ts:rail:powered:"
        if string.sub( self.sv.railTag, 1, string.len( powerTag ) ) == powerTag then
            self.sv.powered = true
        end
        local tileKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
        local rail = GetRailStorage( tileKey, self.sv.railTag )
        if rail then
            rail.collection[self.harvestable:getInitialHash()] = self.harvestable
            TileStorageManager.Sv_SetValueInSubTable( tileKey, POWERLADDER_RAIL_TABLE, self.sv.railTag, rail )        
            self.sv.powered = rail.powered or self.sv.powered
        end
    end

    -- power ladder handles are not saved. this means when the tile is loaded, the handles are gone and the rails will be inactive.
    self.sv.activeCount = 0
    self.network:setClientData( self:sv_getState() )
end

function PowerLadderRail.sv_e_addHandle( self, backwards )
    self.sv.activeCount = self.sv.activeCount + 1
    self.sv.backwards = backwards --last one wins
    self.network:setClientData( self:sv_getState() )
end

function PowerLadderRail.sv_e_removeHandle( self )
    self.sv.activeCount = math.max( 0, self.sv.activeCount - 1 )
    self.network:setClientData( self:sv_getState() )
end

function PowerLadderRail.sv_e_destroyRail( self )
    self.harvestable:destroy()
end

function PowerLadderRail.sv_e_updatePower( self, powered )
    self.sv.powered = powered
    self.network:setClientData( self:sv_getState() )
end

function PowerLadderRail.sv_getState( self )
    if self.sv.powered then
        if self.sv.activeCount > 0 then
            if self.sv.backwards then
                return States.ActiveBackward
            else
                return States.ActiveForward
            end
        else
            return States.On
        end
    else
        return States.Off
    end
end

function PowerLadderRail.client_onCreate( self )
    self.cl = {}
    self.harvestable:setUvFrameIndex( 0 )
end

function PowerLadderRail.client_onClientDataUpdate( self, state )
    self.harvestable:setUvFrameIndex( state - 1 )
end


