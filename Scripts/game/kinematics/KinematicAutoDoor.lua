dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/Kinematic.lua" )

KinematicAutoDoor = class( Kinematic )

function KinematicAutoDoor.server_onCreate( self )
	Kinematic.server_onCreate( self )

	local sensorBounds = sm.vec3.zero()
	if self.data and self.data.sensorBounds then
		sensorBounds = sm.vec3.new( self.data.sensorBounds.x, self.data.sensorBounds.y, self.data.sensorBounds.z )
	end

	if g_tileStorageManager then
		self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
	end

	local min, max = self.harvestable:getLocalAabb()
	local bounds = sm.vec3.new( math.abs( max.x - min.x ), math.abs( max.y - min.y ), math.abs( max.z - min.z ) )

	self.sv.areaTrigger = sm.areaTrigger.createBox( ( bounds * 0.5 ) + sensorBounds, self.harvestable.initialPosition, self.harvestable.initialRotation, sm.areaTrigger.filter.character )

	local isUnlocked = false
	if self.params.isLocked and g_tileStorageManager then
		local brokenLockCount = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_COUNTER_TABLE, self.params.keyTag )
		if brokenLockCount == 3 then
			isUnlocked = true
		end
	end

	local group = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_SPINNER_DOOR_TABLE, self.params.keyTag )
	if group ~= nil then
		if SafeGetExist( group, "sign" ) then
			sm.event.sendToHarvestable( group.sign, "sv_e_receiveDoor", self.harvestable )
		else
			group = SafeSet( group, "door", self.harvestable )
			TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_SPINNER_DOOR_TABLE, self.params.keyTag, group )
		end
	end

	local progressData = self.sv.trackInstances and self.sv.trackInstances["track"] and self.sv.trackInstances["track"].progressData
	local isClosed = progressData.segmentIndex == 1 and progressData.segmentProgress == 0
	self.network:setClientData( { open = not isClosed, unlocked = isUnlocked }, 3 )
end

function KinematicAutoDoor.sv_doorOpen( self )
	if not self:sv_isMoving() then
		-- Check if should start moving
		local shouldBeOpen = #self.sv.areaTrigger:getContents() > 0
		
		local progressData = self.sv.trackInstances["track"].progressData
		assert( progressData ~= nil, "KinematicAutoDoor default track not found" )
		
		local isClosed = progressData.segmentIndex == 1 and progressData.segmentProgress == 0
		if self.params.isLocked and not isClosed then
			return
		end
		if shouldBeOpen == isClosed then
			self:sv_activate()
			local isUnlocked = false
			if self.params.isLocked then
				isUnlocked = true
			end
			self.network:setClientData( { open = isClosed, unlocked = isUnlocked }, 3 )
		end
	end
end

function KinematicAutoDoor.server_onFixedUpdate( self, timeStep )
	Kinematic.server_onFixedUpdate( self )
	if self.params.isLocked and g_tileStorageManager then
		local brokenLockCount = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_COUNTER_TABLE, self.params.keyTag )
		if brokenLockCount then
			if brokenLockCount ~= 3 then
				return
			end
		else
			return
		end
	end
	self:sv_doorOpen()
end

function KinematicAutoDoor.client_onClientDataUpdate( self, data, channel )
	if channel == 3 then
		self.harvestable.clientPublicData = { open = data.open, unlocked = data.unlocked }
	else
		Kinematic.client_onClientDataUpdate( self, data, channel )
	end
end