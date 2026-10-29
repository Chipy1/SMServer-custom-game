dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/ParentedKinematicRoot.lua" )

BosstrainSideCart = class( ParentedKinematicRoot )

BosstrainSideCart.executionOrder = 100

function BosstrainSideCart.server_onCreate( self )
    ParentedKinematicRoot.server_onCreate( self )
    DrillbotManager.Sv_RegisterKinematic( self.harvestable:getWorld(), self.harvestable, self.params )
end

function BosstrainSideCart.server_onFixedUpdate( self, timeStep )
    ParentedKinematicRoot.server_onFixedUpdate( self, timeStep )

    for _, instance in pairs( self.sv.trackInstances ) do
		if not instance.updateData.playForward then

            DrillbotManager.Sv_SideCartDestroyed( self.harvestable:getWorld(), self.params.storageTag )
            self.harvestable:destroy()
        end
	end
end

function BosstrainSideCart.client_onClientDataUpdate( self, data, channel )
    ParentedKinematicRoot.client_onClientDataUpdate( self, data, channel )
end

function BosstrainSideCart.client_onCreate( self )
    ParentedKinematicRoot.client_onCreate( self )
end

function BosstrainSideCart.client_onFixedUpdate( self )
    if sm.isHost then
        return
    end
    ParentedKinematicRoot.client_onFixedUpdate( self )
end
