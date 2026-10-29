dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/KinematicAutoDoor.lua" )

KinematicMultiLockDoor = class( KinematicAutoDoor )

function KinematicMultiLockDoor.server_onFixedUpdate( self )
	Kinematic.server_onFixedUpdate( self )
	if g_tileStorageManager then
		local count = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_COUNTER_TABLE, self.params.keyTag )
		if count then
			if count and count ~= self.params.lockCount then
				return
			end
		else
			return
		end
	end
	if not self:sv_isMoving() then
		local shouldBeOpen = #self.sv.areaTrigger:getContents() > 0
		local progressData = self.sv.trackInstances["track"].progressData
		local onFirstNode = progressData.segmentIndex == 1 and progressData.segmentProgress == 0
		if shouldBeOpen == onFirstNode then
			self:sv_activate()
		end
	end
	if not self.sv.isUnlocked then
		self.sv.isUnlocked = true
		self.network:setClientData( { open = nil, unlocked = self.sv.isUnlocked }, 3 )
	end
end