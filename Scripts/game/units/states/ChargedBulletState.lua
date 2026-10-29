dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

ChargedBulletState = class( BaseState )

local ProjectileDamage = 30
local ProjectileVelocity = 40
local MaxAimAngle = math.rad( 80.0 )

function ChargedBulletState.sv_onCreate( self, unit, isRightSide )
	self.unit = unit
	self.lookDirection = sm.vec3.new( 0, 1, 0 )
	self.worldPosition = sm.vec3.zero()
	self.stageIndex = 1
	self.isRightSide = isRightSide

	self.projectileUuid = projectile_trashchargedbullet_green
	if not self.isRightSide then
		self.projectileUuid = projectile_trashchargedbullet_purple
	end

	self.chargingState = self.unit:createState( "wait" )
	self.chargingState.debugName = "chargingState"
	self.chargingState.name = isRightSide and "chargeBulletRight" or "chargeBulletLeft"
	self.chargingState.time = 3.5
	self.chargingState.interruptible = false

	self.shootState = self.unit:createState( "wait" )
	self.shootState.debugName = "shootState"
	self.shootState.name = isRightSide and "shootChargedBulletRight" or "shootChargedBulletLeft"
	self.shootState.time = 0.5
	self.shootState.interruptible = false

	self.currentState = self.chargingState
end

function ChargedBulletState.refresh( self ) end

function ChargedBulletState.sv_setLookDirection( self, lookDirection )
	self.lookDirection = lookDirection
end

function ChargedBulletState.sv_setPosition( self, worldPosition )
	self.worldPosition = worldPosition
end

function ChargedBulletState.sv_setTarget( self, target )
	self.target = target
end

function ChargedBulletState.sv_setStage( self, stageIndex )
	self.stageIndex = stageIndex
end

function ChargedBulletState.sv_shootChargedBullet( self )
	-- Predict target position
	local distanceToTarget = ( self.target.worldPosition - self.unit.character.worldPosition ):length()
	local projectileTravelTime = distanceToTarget / ProjectileVelocity
	local targetVelocity = self.target.velocity
	local targetAlmostZeroZVelocity = sm.vec3.new( targetVelocity.x, targetVelocity.y, targetVelocity.z * 0.1 )
	local expectedTargetMovement = targetAlmostZeroZVelocity * projectileTravelTime
	local predictedTargetPosition = self.target.worldPosition + expectedTargetMovement

	-- Aim direction
	local fromToTarget = self.target.worldPosition - self.worldPosition
	local aimDirection = fromToTarget:safeNormalize( self.lookDirection )

	-- Find ballistic arc direction
	local lowAngleVector, _ = sm.projectile.solveBallisticArc( self.worldPosition, predictedTargetPosition, ProjectileVelocity, GRAVITY )
	if lowAngleVector then
		aimDirection = lowAngleVector:safeNormalize( aimDirection )
	end

	-- Clamp fire direction
	local aimAngle = clamp( math.acos( self.lookDirection:dot( aimDirection ) ), 0.0, MaxAimAngle )
	local aimRotationVector = ( self.lookDirection:cross( aimDirection ) ):safeNormalize( orthogonal( self.lookDirection ) )
	local aimDirectionClamped = self.lookDirection:rotate( aimAngle, aimRotationVector )

	sm.projectile.projectileAttack( self.projectileUuid, ProjectileDamage, self.worldPosition, aimDirectionClamped * ProjectileVelocity, self.unit )
end

--[[API functions]]

function ChargedBulletState.start( self )
	self.currentState:stop()
	self.currentState = self.chargingState
	self.currentState:start()
	self.fired = false
end

function ChargedBulletState.stop( self )
	self.currentState:stop()
end

function ChargedBulletState.onFixedUpdate( self, dt )
	self.target = sm.exists( self.target ) and self.target or nil
	self.currentState:onFixedUpdate( dt )
	if self.currentState == self.chargingState then
		local done, _ = self.currentState:isDone()
		if done then
			self.currentState:stop()
			self.currentState = self.shootState
			self.currentState:start()
			if self.target then
				self:sv_shootChargedBullet()
			end
		end
	end
end

function ChargedBulletState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function ChargedBulletState.isDone( self )
	if self.currentState == self.shootState then
		local done, _ = self.currentState:isDone()
		return done, "fired"
	elseif self.currentState == self.chargingState then
		return false, "charging"
	end
	return true, "unknown state"
end

function ChargedBulletState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function ChargedBulletState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function ChargedBulletState.getMovementType( self )
	return self.currentState:getMovementType()
end

function ChargedBulletState.getWantsJump( self )
	return false
end