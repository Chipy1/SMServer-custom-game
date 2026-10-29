dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/KinematicBase.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

KinematicSpinnerKey = class( KinematicBase )

local CounterSpin = 20.0
local MeleeImpulse = 30.0
local ProjectileImpulse = 20.0
local ProjectileTickCooldown = 20
local SpinAxis = sm.vec3.new( 0, 0, 1 ):normalize()
local AngularSpeedForEffect = 15.0

local minimumRotations = 3

function KinematicSpinnerKey.server_onCreate( self )
	self.sv = {}

	self.sv.angularRotation = 0
	self.sv.angularSpeed = 0
	
	self.sv.progress = 0.0
	self.sv.stopWhenOpen = self.params.stopWhenOpen or false
	self.sv.unlocked = false
	self.sv.isDirty = false
	self.sv.direction = 1
	self.sv.lastProjectileHitTick = 0

	self.sv.initialHash = self.harvestable:getInitialHash()

	if self.params.spinnerValues then
		self.sv.turnsToUnlock = math.max( self.params.spinnerValues.turnsToUnlock, minimumRotations )
		self.sv.maxRotationSpeed = self.params.spinnerValues.maxRotationSpeed
		self.sv.minRotationSpeed = self.params.spinnerValues.minRotationSpeed
		self.sv.releaseSpeed = self.params.spinnerValues.releaseSpeed
		self.sv.kinematicActivation = self.params.spinnerValues.kinematicActivation
	else
		self.sv.turnsToUnlock = 7
		self.sv.maxRotationSpeed = 100
		self.sv.minRotationSpeed = -2
		self.sv.releaseSpeed = -240
		self.sv.kinematicActivation = nil
	end

	self.sv.setInStorage = false
	
	if g_tileStorageManager then
		self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )

		local group = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_SPINNER_DOOR_TABLE, self.params.keyTag )
		group = SafeSet( group, "spinner", self.harvestable )
		TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_SPINNER_DOOR_TABLE, self.params.keyTag, group )
		

		self.sv.setInStorage = true

		local stored = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.initialHash )
		if stored ~= nil then
			self.sv.direction = stored.direction
			if stored.unlocked then
				self.sv.progress = 1.0
				self.sv.unlocked = true
			elseif stored.progress ~= nil then
				self.sv.progress = stored.progress
			end
		end

		self.sv.isDirty = true
		self.sv.angularRotation = self.sv.turnsToUnlock * ( math.pi * 2 ) * self.sv.progress
	end
	self.network:setClientData( { progress = self.sv.progress, unlocked = self.sv.unlocked }, 1 )
	self.network:setClientData( { angularRotation = self.sv.angularRotation, angularSpeed = self.sv.angularSpeed, direction = self.sv.direction }, 2 )
	self.network:setClientData( { turnsToUnlock = self.sv.turnsToUnlock, releaseSpeed = self.sv.releaseSpeed, minRotationSpeed = self.sv.minRotationSpeed, maxRotationSpeed = self.sv.maxRotationSpeed }, 3 )
end

function KinematicSpinnerKey.server_onFixedUpdate( self, timeStep )
	if self.sv == nil then
		return
	end

	if not self.sv.setInStorage then
		if g_tileStorageManager then
			self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
			
			local group = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_SPINNER_DOOR_TABLE, self.params.keyTag )
			group = SafeSet( group, "spinner", self.harvestable )
			TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_SPINNER_DOOR_TABLE, self.params.keyTag, group )

			self.sv.setInStorage = true
		end
	end
	if not self.sv.unlocked then
		
		local angularRotation, angularSpeed = self:spinUpdate( timeStep, self.sv.angularRotation, self.sv.angularSpeed, self.sv.turnsToUnlock, self.sv.releaseSpeed, self.sv.minRotationSpeed, self.sv.maxRotationSpeed, self.sv.direction )
		self.sv.angularRotation = angularRotation
		self.sv.angularSpeed = angularSpeed
		self.sv.progress = self.sv.angularRotation / ( self.sv.turnsToUnlock * ( math.pi * 2 ) )
		if self.sv.stopWhenOpen then
			self.sv.unlocked = self.sv.progress == 1
			if self.sv.unlocked then
				self.sv.angularSpeed = 0
				self.sv.unlocked = true
				self.sv.isDirty = true
				if self.params.keyTag then
					local keyCount = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_COUNTER_TABLE, self.params.keyTag ) or 0
					keyCount = keyCount + 1
					SetKeyLockCounterValue( self.sv.tileStorageKey, self.params.keyTag, keyCount )
				end
				if self.sv.kinematicActivation ~= nil then
					KinematicManager.Sv_Activate( self.sv.tileStorageKey, self.sv.kinematicActivation )
				end
			end
		end
	end
	if self.sv.isDirty then
		self.network:setClientData( { progress = self.sv.progress, unlocked = self.sv.unlocked }, 1 )
		self.network:setClientData( { angularRotation = self.sv.angularRotation, angularSpeed = self.sv.angularSpeed, direction = self.sv.direction }, 2 )
		self.sv.isDirty = false
	end
end

function KinematicSpinnerKey.server_onUnload( self )
	TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.initialHash, { unlocked = self.sv.unlocked, progress = self.sv.progress, direction = self.sv.direction } )
end

function KinematicSpinnerKey.sv_e_release( self )
	if self.sv.unlocked then
		self.sv.unlocked = false
		self.sv.angularSpeed = self.sv.releaseSpeed * self.sv.direction
		self.sv.isDirty = true
	end
end

function KinematicSpinnerKey.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if attacker.character and not self.sv.unlocked then
		self:sv_addTorque( hitPos, hitDirection * MeleeImpulse )
	end
end

function KinematicSpinnerKey.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	local currentTick = sm.game.getCurrentTick()
	if currentTick - self.sv.lastProjectileHitTick >= ProjectileTickCooldown then
		self.sv.lastProjectileHitTick = currentTick
		if damage > 0 and not self.sv.unlocked then
			self:sv_addTorque( hitPos, hitVelocity:safeNormalize( sm.vec3.new( 1, 0, 0 ) ) * ProjectileImpulse )
		end
	end
end

function KinematicSpinnerKey.client_onCreate( self )
	KinematicBase.client_onCreate( self )
	self.cl = {}
	self.cl.angularRotation = 0
	self.cl.angularSpeed = 0
	self.cl.progress = 0.0
	self.cl.unlocked = false
	self.cl.turnsToUnlock = 1
	self.cl.forwards = true
	self.cl.spinEffect = sm.effect.createEffect( "Growlab - Kinematicspinnerswirl", self.harvestable, nil, sm.effect.axis.yaxis )
	self.cl.spinEffect:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( -90, 0, 0 ) ) )
	self.cl.spinAudio = sm.effect.createEffect( "Growlab - Kinematicspinneraudio", self.harvestable )
	self.cl.direction = 1
end

function KinematicSpinnerKey.client_onDestroy( self )
	self.cl.spinEffect:destroy()
	self.cl.spinAudio:destroy()
end

function KinematicSpinnerKey.client_onClientDataUpdate( self, clientData, channel )
	if self.cl == nil then
		self.cl = {}
	end

	if channel == 1 then
		self.cl.progress = clientData.progress
		self.cl.unlocked = clientData.unlocked
		if self.cl.unlocked then
			self.cl.spinEffect:stop()
			self.cl.spinAudio:stopBreakSustain()
		end
		self.harvestable.clientPublicData = { progress = self.cl.progress, speed = self.cl.angularSpeed }
	elseif channel == 2 then
			self.cl.angularRotation = clientData.angularRotation
			self.cl.angularSpeed = clientData.angularSpeed
			self.cl.direction = clientData.direction
	elseif channel == 3 then
		self.cl.turnsToUnlock = clientData.turnsToUnlock
		self.cl.releaseSpeed = clientData.releaseSpeed
		self.cl.minRotationSpeed = clientData.minRotationSpeed
		self.cl.maxRotationSpeed = clientData.maxRotationSpeed
	end
end

function KinematicSpinnerKey.client_onFixedUpdate( self, timeStep )
	if not self.cl.unlocked then
		local angularRotation, angularSpeed = self:spinUpdate( timeStep, self.cl.angularRotation, self.cl.angularSpeed, self.cl.turnsToUnlock, self.cl.releaseSpeed, self.cl.minRotationSpeed, self.cl.maxRotationSpeed, self.cl.direction )
		self.cl.angularRotation = angularRotation
		self.cl.angularSpeed = angularSpeed
		local progress = self.cl.angularRotation / ( self.cl.turnsToUnlock * ( math.pi * 2 ) )
		if progress ~= self.cl.progress then
			self.cl.progress = progress
			self.harvestable.clientPublicData = { progress = self.cl.progress, speed = self.cl.angularSpeed }
		end

		if math.abs( self.cl.angularSpeed ) >= AngularSpeedForEffect and not self.cl.spinEffect:isPlaying() then
			self.cl.spinEffect:start()
		elseif math.abs( self.cl.angularSpeed ) < AngularSpeedForEffect and self.cl.spinEffect:isPlaying() then
			self.cl.spinEffect:stop()
		end
		if not self.cl.spinAudio:isPlaying() or self.cl.stopped then
			if math.abs( self.cl.angularSpeed ) > 1 then
				self.cl.spinAudio:start()
				self.cl.stopped = false
			end
		else
			if self.cl.angularSpeed == 0 then
				self.cl.stopped = true
				self.cl.spinAudio:stopBreakSustain()
			else
				local soundVelocity = clamp( math.abs( self.cl.angularSpeed ) / 50, 0.0, 1.0 )
				self.cl.spinAudio:setParameter( "velocity", soundVelocity )
				if self.cl.angularSpeed * self.cl.direction < 0 and self.cl.forwards then
					self.cl.forwards = false
					self.cl.spinAudio:setParameter( "spinDirection", "backwards" )
				elseif self.cl.angularSpeed * self.cl.direction > 0 and self.cl.forwards == false then
					self.cl.forwards = true
					self.cl.spinAudio:setParameter( "spinDirection", "forwards" )
				end
			end
		end
	end
end

function KinematicSpinnerKey.spinUpdate( self, time, angularRotation, angularSpeed, turnsToUnlock, releaseSpeed, minRotationSpeed, maxRotationSpeed, direction )
	angularRotation = angularRotation + angularSpeed * direction * time
	local progress = angularRotation / ( turnsToUnlock * ( math.pi * 2 ) )
	angularRotation = math.max( math.min( angularRotation, turnsToUnlock * math.pi * 2 ), 0 )
	angularSpeed = angularSpeed - CounterSpin * direction * time
	local fastDrop = angularSpeed * direction <= releaseSpeed
	local minSpeed = fastDrop and releaseSpeed or minRotationSpeed
	angularSpeed = math.max( math.min( angularSpeed * direction, maxRotationSpeed ),  minSpeed ) * direction

	if progress > 1.0 or progress <= 0.0 then
		angularSpeed = 0.0
	end

	if not sm.isServerMode() then
		local worldRotation = sm.quat.angleAxis( angularRotation * direction, SpinAxis ) * self.harvestable.initialRotation
		self.harvestable:setRotation( worldRotation )
	end

	return angularRotation, angularSpeed
end

function KinematicSpinnerKey.sv_addTorque( self, position, impulse )
	local relativePosition = position - self.harvestable.worldPosition
	local torqueImpulse = relativePosition:cross( impulse )

	local scale = self.harvestable:getScale()
	local scaleVolumeMultiplier = 0.25 / ( ( scale.x * scale.y * scale.z ) ^ ( 1 / 3 ) )
	torqueImpulse = torqueImpulse * scaleVolumeMultiplier

	-- Extract only the angular impulse around the SpinAxis
	local projectedTorqueImpulse = SpinAxis * SpinAxis:dot( torqueImpulse )
	local directionalSign = SpinAxis:dot( projectedTorqueImpulse:safeNormalize( sm.vec3.new( 0, 0, 0 ) ) )
	local angularImpulse = projectedTorqueImpulse:length() * directionalSign

	if self.sv.angularSpeed == 0.0 and self.sv.progress == 0.0 then
		self.sv.direction = directionalSign
	end

	self.sv.angularSpeed = self.sv.angularSpeed + angularImpulse
	if self.sv.direction == 1.0 then
		self.sv.angularSpeed = math.max( math.min( self.sv.angularSpeed, self.sv.maxRotationSpeed ), self.sv.minRotationSpeed )
	else
		self.sv.angularSpeed = math.max( math.min( self.sv.angularSpeed, -self.sv.minRotationSpeed ), -self.sv.maxRotationSpeed )
	end

	self.network:setClientData( { angularRotation = self.sv.angularRotation, angularSpeed = self.sv.angularSpeed, direction = self.sv.direction }, 2 )
end