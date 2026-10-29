dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/ParentedKinematic.lua" )


BosstrainLock = class( ParentedKinematic )

local DestroyEffect = "Drillbot - Lock_destruct01"

function BosstrainLock.server_onCreate( self )
    ParentedKinematic.server_onCreate( self )
    DrillbotManager.Sv_RegisterKinematic( self.harvestable:getWorld(), self.harvestable, self.params )
end

function BosstrainLock.server_onFixedUpdate( self, timeStep )
    ParentedKinematic.server_onFixedUpdate( self, timeStep )
end

function BosstrainLock.client_onClientDataUpdate( self, data, channel )
    ParentedKinematic.client_onClientDataUpdate( self, data, channel )
end

function BosstrainLock.client_onCreate( self )
    ParentedKinematic.client_onCreate( self )
end

function BosstrainLock.client_onFixedUpdate( self )
    if sm.isHost then
        return
    end
    ParentedKinematic.client_onFixedUpdate( self )
end

function BosstrainLock.sv_destroy( self )
    if self.sv.destroyed then
        return
    end

    local world = self.harvestable:getWorld()
    DrillbotManager.Sv_LockDestroyed( world, { cartIndex = self.params.cartIndex, storageTag = self.params.storageTag } )

    sm.effect.playEffect( DestroyEffect, self.harvestable.worldPosition, nil, self.harvestable.worldRotation )

    self.harvestable:destroy()
    self.sv.destroyed = true
end

function BosstrainLock.sv_e_destroy( self )
    self:sv_destroy()
end

function BosstrainLock.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
    
    sm.effect.playEffect( "audio:event:/coll/barrier", self.harvestable.worldPosition, nil, self.harvestable.worldRotation )
    




end
