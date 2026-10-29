dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

KinematicTrackLock = class( KinematicRailObject )

function KinematicTrackLock.server_onCreate( self )
	KinematicRailObject.sv_init( self )

	self.sv.initialHash = self.harvestable:getInitialHash()

	self.params.onlyForward = true

	if g_tileStorageManager then
		self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
		
		self.sv.unlocked = false
		local stored = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.initialHash )
		if stored then
			self.sv.unlocked = stored.unlocked
		end

		local storageValues = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.initialHash )
		if storageValues then
			self.sv.updateData.speed = storageValues.speed or 0.0
			self.sv.updateData.acceleration = 0
			self.sv.updateData.distance = storageValues.distance
			local kinematicPosition, kinematicRotation = self:getTransform( self.sv.updateData.distance, self.sv.trackData )
			self.harvestable:setPosition( kinematicPosition )
			self.harvestable:setRotation( kinematicRotation )
			self.network:setClientData( self.sv.updateData, 2 )
		end
	end

	if self.params.showPin and self.sv.updateData.distance == 0.0 then
		if g_questPinManagerServer then
			QuestPinManager.Sv_AddPin( self.harvestable, self.harvestable:getWorld(), "SmashPin", sm.vec3.new( 0, 0, 1.2 ) )
		end
	end

	self.network:setClientData( { params = self.params }, 1 )
	self.harvestable.publicData = { isRailKinematic = true }
end

function KinematicTrackLock.server_onUnload( self )
	local values = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.initialHash ) or {}
	values.distance = self.sv.updateData.distance
	values.speed = self.sv.updateData.speed
	TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.initialHash, values )
end

function KinematicTrackLock.server_onFixedUpdate( self )
	if self.sv == nil then
		return
	end
	if self.sv.updateData.speed ~= 0.0 then
		self.sv.updateData = self:trackUpdate( self.sv.trackData, self.sv.trackSettings, self.sv.updateData )
	end

	if not self.sv.unlocked then
		if g_tileStorageManager then
			if self.params and self.params.lockTag and self.params.lockTag ~= "" then
				self.sv.unlocked = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.lockTag ) == true
			end
		end
		if not self.sv.unlocked then return end
	end
end

function KinematicTrackLock.sv_n_lockKinematic( self )
	if self.params and self.params.kinematicEventTrigger then
		g_kinematicManager:sv_activate( self.sv.tileStorageKey, self.params.kinematicEventTrigger )
	end
	if g_tileStorageManager then
		if self.params and self.params.keyTag and self.params.keyTag ~= "" then
			local unlockCount = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_COUNTER_TABLE, self.params.keyTag )
			if unlockCount == nil then
				unlockCount = 1
			else
				unlockCount = unlockCount + 1
			end
			SetKeyLockCounterValue( self.sv.tileStorageKey, self.params.keyTag, unlockCount )
			TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.keyTag, true )
		end
		TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.initialHash, { unlocked = true, distance = self.sv.trackData.distances[#self.sv.trackData.distances] } )
	end
end

function KinematicTrackLock.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if attacker.character then
		if self.data and self.data.soundEffect then
			sm.effect.playEffect( self.data.soundEffect, self.harvestable.position )
		end
		local forwardDirection = self:getDirection( self.sv.updateData.distance, self.sv.trackData )

		local MeleeImpulse = self.data and self.data.meleeImpulse and self.data.meleeImpulse or 15.0
		if forwardDirection:dot( hitDirection ) > 0.1 then
			self.sv.updateData.speed = self.sv.updateData.speed + MeleeImpulse
			self.sv.updateData.serverTick = sm.game.getServerTick()
			self.network:setClientData( self.sv.updateData, 2 )
		end
	end
	self:sv_removePin()
end

function KinematicTrackLock.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if damage == 0 then
		return
	end

	local hitDirection = hitVelocity:safeNormalize( sm.vec3.new( 0, 0, 0 ) )

	local forwardDirection = self:getDirection( self.sv.updateData.distance, self.sv.trackData )

	local ProjectileImpulse = self.data and self.data.projectileImpulse and self.data.projectileImpulse or 5.0
	if forwardDirection:dot( hitDirection ) > 0.1 then
		self.sv.updateData.speed = self.sv.updateData.speed + ProjectileImpulse
		self.sv.updateData.serverTick = sm.game.getServerTick()
		self.network:setClientData( self.sv.updateData, 2 )
	end
	self:sv_removePin()
end

function KinematicTrackLock.sv_removePin( self )
	if self.params.showPin then
		if g_questPinManagerServer then
			QuestPinManager.Sv_RemovePin( self.harvestable.id, type( self.harvestable ) )
		end
	end
end

-- overriding KinematicRailObject to remove all onCollision response.
function KinematicTrackLock.server_onCollision()
end