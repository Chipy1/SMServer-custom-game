dofile( "$SURVIVAL_DATA/Scripts/game/scriptableObjects/AttachedLootManager.lua" )

KinematicBase = class( nil )

function KinematicBase.client_onCreate( self )
	AttachedLootManager.Cl_KinematicCreated( self.harvestable )
end


