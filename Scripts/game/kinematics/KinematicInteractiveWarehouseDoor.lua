dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

KinematicInteractiveWarehouseDoor = class( KinematicInteractiveDoor )

function KinematicInteractiveWarehouseDoor.sv_n_activateKinematics( self )
	if not ProgressionManager.Sv_IsWarehouseConsoleUnlocked() then
		return
	end
	KinematicInteractiveDoor.sv_n_activateKinematics( self )
end

function KinematicInteractiveWarehouseDoor.client_canInteract( self, character )
	if ProgressionManager.Cl_IsWarehouseConsoleUnlocked() then
		return KinematicInteractiveDoor.client_canInteract( self, character )
	end
	return false
end