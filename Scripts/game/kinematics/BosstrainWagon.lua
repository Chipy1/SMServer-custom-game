dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/ParentedKinematicRoot.lua" )

BosstrainWagon = class( ParentedKinematicRoot )

BosstrainWagon.executionOrder = 100

function BosstrainWagon.server_onCreate( self )
    ParentedKinematicRoot.server_onCreate( self )

    if not self.sv.readFromStorage then
        self:sv_e_setActiveTracks( { tracksToActivate = { "idle" }, tracksToDeactivate = {} } )
    end

    DrillbotManager.Sv_RegisterKinematic( self.harvestable:getWorld(), self.harvestable, self.params )
    self.network:setClientData( { storageTag = self.params.storageTag }, 4 )
end

function BosstrainWagon.sv_e_setActiveTracks( self, args )
    self.sv.transition = 0
    self.sv.transitionTime = args.transitionTime or 1
    args.tracksToDeactivate = args.tracksToDeactivate or {}
    args.tracksToActivate = args.tracksToActivate or {}

    self.sv.tracksToActivate = args.tracksToActivate
    self.sv.tracksToDeactivate = args.tracksToDeactivate

    self:sv_store()
end

function BosstrainWagon.sv_e_hideWagon( self )
    self.network:sendToClients( "cl_n_hide" )
end

function BosstrainWagon.server_onFixedUpdate( self, timeStep )
    ParentedKinematicRoot.server_onFixedUpdate( self, timeStep )

    if self.sv.transition and self.sv.transition < self.sv.transitionTime then
        self.sv.transition = min( self.sv.transitionTime, self.sv.transition + timeStep )
        local p = inverseLerp( 0, self.sv.transitionTime, self.sv.transition )

        local fnWeight = function ( trackName )
            if isAnyOf( trackName, self.sv.tracksToActivate ) then -- maps instead?
                return p
            elseif isAnyOf( trackName, self.sv.tracksToDeactivate ) then
                return 1 - p
            else
                return 0
            end
        end

        local trackWeights = {}
        for trackName, instance in pairs( self.sv.trackInstances ) do
            table.insert( trackWeights, { trackName = trackName, weight = fnWeight( trackName ) } )
        end

        self:sv_setTrackWeights( trackWeights )
    end

	for trackName, instance in pairs( self.sv.trackInstances ) do
		if isAnyOf( trackName, { "down_flip", "down_transition" } ) and not instance.updateData.playForward then
            self.harvestable:destroy()
        end
	end
end

function BosstrainWagon.client_onClientDataUpdate( self, data, channel )
    ParentedKinematicRoot.client_onClientDataUpdate( self, data, channel )
    if channel == 4 then
        self.cl.storageTag = data.storageTag
        DrillbotManager.Cl_RegisterCreatedCart( self.harvestable:getWorld(), self.harvestable, self.cl.storageTag )
    end
end

function BosstrainWagon.client_onCreate( self )
    ParentedKinematicRoot.client_onCreate( self )
end

function BosstrainWagon.client_onFixedUpdate( self )
    if sm.isHost then
        return
    end
    ParentedKinematicRoot.client_onFixedUpdate( self )
end
