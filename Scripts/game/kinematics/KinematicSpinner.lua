dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/KinematicBase.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

KinematicSpinner = class( KinematicBase )

local Friction = 0.75
local MaxAngularSpeed = 50.0
local MinAngularSpeed = -50.0
local MeleeImpulse = 30.0
local ProjectileImpulse = 20.0
local CollisionImpulse = 1.5
local SpinAxis = sm.vec3.new( 0, 0, 1 ):normalize()

function KinematicSpinner.server_onCreate( self )
	self.sv = {}

	self.sv.angularRotation = 0
	self.sv.angularSpeed = 0
	self.network:setClientData( { angularRotation = self.sv.angularRotation, angularSpeed = self.sv.angularSpeed } )

	self.sv.unlocked = true

	if g_tileStorageManager then
		self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )

		if self.params and self.params.lockTag and self.params.lockTag ~= "" then
			self.sv.unlocked = false
			local keyLock = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.lockTag )
			if keyLock then
				self.sv.unlocked = keyLock.unlocked
			end
		end
	end
end

function KinematicSpinner.server_onFixedUpdate( self, timeStep )
	if self.sv == nil then
		return
	end
	if not self.sv.unlocked then
		if g_tileStorageManager then
			if self.params and self.params.lockTag and self.params.lockTag ~= "" then
				local keyLock = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.lockTag )
				if keyLock then
					self.sv.unlocked = keyLock.unlocked
				end
			end
		end
		if not self.sv.unlocked then return end
	end

	local angularRotation, angularSpeed = self:spinUpdate( timeStep, self.sv.angularRotation, self.sv.angularSpeed )
	self.sv.angularRotation = angularRotation
	self.sv.angularSpeed = angularSpeed

	if g_tileStorageManager then
		if self.params and self.params.keyTag and self.params.keyTag ~= "" then
			local unlockSpeed = self.params.unlockSpeed and self.params.unlockSpeed or FLT_EPSILON
			if math.abs( self.sv.angularSpeed ) >= unlockSpeed then
				TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.keyTag, true )
			end
		end
	end
end

function KinematicSpinner.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	self:sv_addTorque( collisionPosition, ( otherPointVelocity ):safeNormalize( sm.vec3.new( 0, 0, 0 ) ) * CollisionImpulse )
end

function KinematicSpinner.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if attacker.character then
		self:sv_addTorque( hitPos, hitDirection * MeleeImpulse )
	end
end

function KinematicSpinner.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if damage > 0 then
		self:sv_addTorque( hitPos, hitVelocity:safeNormalize( sm.vec3.new( 0, 0, 0 ) ) * ProjectileImpulse )
	end
end

function KinematicSpinner.client_onCreate( self )
	KinematicBase.client_onCreate( self )
	self.cl = {}
	self.cl.angularRotation = 0
	self.cl.angularSpeed = 0
end

function KinematicSpinner.client_onClientDataUpdate( self, clientData )
	if self.cl == nil then
		self.cl = {}
	end

	self.cl.angularRotation = clientData.angularRotation
	self.cl.angularSpeed = clientData.angularSpeed
end

function KinematicSpinner.client_onFixedUpdate( self, timeStep )
	if sm.isHost then
		return
	end

	local angularRotation, angularSpeed = self:spinUpdate( timeStep, self.cl.angularRotation, self.cl.angularSpeed )
	self.cl.angularRotation = angularRotation
	self.cl.angularSpeed = angularSpeed
end

function KinematicSpinner.spinUpdate( self, time, angularRotation, angularSpeed )

	if angularSpeed >= FLT_EPSILON or angularSpeed <= -FLT_EPSILON then
		angularSpeed = math.max( math.min( angularSpeed, MaxAngularSpeed ), MinAngularSpeed )
		angularRotation = angularRotation + angularSpeed * time
		local integral, fraction = math.modf( angularRotation / ( math.pi * 2 ) )
		angularRotation = fraction * ( math.pi * 2 )

		angularSpeed = angularSpeed - angularSpeed * Friction * time

		local worldRotation = sm.quat.angleAxis( angularRotation, SpinAxis ) * self.harvestable.initialRotation
		self.harvestable:setRotation( worldRotation )
	end

	return angularRotation, angularSpeed
end

function KinematicSpinner.sv_addTorque( self, position, impulse )
	if not self.sv.unlocked then return end

	local relativePosition = position - self.harvestable.worldPosition
	local torqueImpulse = relativePosition:cross( impulse )

	local scale = self.harvestable:getScale()
	local scaleVolumeMultiplier = 0.25 / ( ( scale.x * scale.y * scale.z ) ^ ( 1 / 3 ) )
	torqueImpulse = torqueImpulse * scaleVolumeMultiplier

	-- Extract only the angular impulse around the SpinAxis
	local projectedTorqueImpulse = SpinAxis * SpinAxis:dot( torqueImpulse )
	local directionalSign = SpinAxis:dot( projectedTorqueImpulse:safeNormalize( sm.vec3.new( 0, 0, 0 ) ) )
	local angularImpulse = projectedTorqueImpulse:length() * directionalSign

	self.sv.angularSpeed = self.sv.angularSpeed + angularImpulse
	self.sv.angularSpeed = math.max( math.min( self.sv.angularSpeed, MaxAngularSpeed ), MinAngularSpeed )

	self.network:setClientData( { angularRotation = self.sv.angularRotation, angularSpeed = self.sv.angularSpeed } )
end