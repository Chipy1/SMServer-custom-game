dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/ParentedKinematic.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DrillbotManager.lua" )

BosstrainParentedKinematic = class( ParentedKinematic )

function BosstrainParentedKinematic.server_onCreate( self )
    ParentedKinematic.server_onCreate( self )
    DrillbotManager.Sv_RegisterKinematic( self.harvestable:getWorld(), self.harvestable, self.params )
end
