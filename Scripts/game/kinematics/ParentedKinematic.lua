dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/Kinematic.lua" )

ParentedKinematic = class( Kinematic )

function ParentedKinematic.server_onCreate( self )
    self.sv = {}
    self.sv.parentedKinematic = true

    Kinematic.server_onCreate( self )

    self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
    
    if self.params then
        if self.params.parentedKinematic then
            self.sv.rootName = self.params.parentedKinematic.rootName
        end
        self.sv.name = self.params.name

        if self.params.parentedKinematic then
            self.sv.parentName = self.params.parentedKinematic.parentName
        end

        if self.sv.parentName == nil or self.sv.parentName == "" then
            self.sv.parentName = self.sv.rootName
        end
    end

    self.sv.foundRoot = false

    self:sv_findRootKinematic()
end

function ParentedKinematic.sv_findRootKinematic( self )
    local rootKinematic = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_ROOT_NAME_TABLE, self.sv.rootName )
    if rootKinematic then
        if type( rootKinematic ) == "Harvestable" and sm.exists( rootKinematic ) then
            sm.event.sendToHarvestable( rootKinematic, "sv_e_registerChildKinematic", { kinematic = self.harvestable, parentName = self.sv.parentName, name = self.sv.name } )
            self.sv.foundRoot = true
        end
    end
end

function ParentedKinematic.server_onFixedUpdate( self, timeStep )
    if not self.sv.foundRoot then
        self:sv_findRootKinematic()
    end
    if self.sv.foundRoot then
        Kinematic.server_onFixedUpdate( self, timeStep )
    end
end

function ParentedKinematic.client_onCreate( self )
    self.cl = {}
    self.cl.parentedKinematic = true
    Kinematic.client_onCreate( self )
end

function ParentedKinematic.client_onClientDataUpdate( self, clientData, channel )
    Kinematic.client_onClientDataUpdate( self, clientData, channel )
end