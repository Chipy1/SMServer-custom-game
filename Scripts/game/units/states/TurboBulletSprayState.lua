dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

TurboBulletSprayState = class( BaseState )

local MaxAimAngle = math.rad( 90.0 )
local ProjectileUuid = projectile_trashbubble_green
local ProjectileDamage = 1
local ProjectileVelocity = 50
local FireInterval = 2
local SprayTime = 3.5
local GunSpreadDegrees = 7.5
local HoseSpeed = 0.75
local HoseMaxAngle = math.rad( 12.5 )


function TurboBulletSprayState.sv_onCreate( self, unit, isRightSide )
	self.unit = unit
	self.lookDirection = sm.vec3.new( 0, 1, 0 )
	self.worldPosition = sm.vec3.zero()
	self.stageIndex = 1
	self.isRightSide = isRightSide

	self.waitState = self.unit:createState( "wait" )
	self.waitState.debugName = "waitState"
	self.waitState.time = SprayTime
	self.waitState.interruptible = false

	self.fireTimer = Timer()
	self.predictedVelocity = sm.vec3.new( 0, 0, 0 )
	self.hoseFraction = 0.25
end

function TurboBulletSprayState.refresh( self ) end

function TurboBulletSprayState.sv_setLookDirection( self, lookDirection )
	self.lookDirection = lookDirection
end

function TurboBulletSprayState.sv_setPosition( self, worldPosition )
	self.worldPosition = worldPosition
end

function TurboBulletSprayState.sv_setTarget( self, target )
	self.target = target
end

function TurboBulletSprayState.sv_setStage( self, stageIndex )
	self.stageIndex = stageIndex
end

function TurboBulletSprayState.sv_updateTurboBulletSpray( self, dt )
	-- Predict target movement from its velocity
	if self.predictedVelocity:length() > 0 and self.target:getVelocity():length() > self.predictedVelocity:length() then
		self.predictedVelocity = magicPositionInterpolation( self.predictedVelocity, self.target:getVelocity(), dt, 1.0 / 10.0 )
	else
		self.predictedVelocity = self.target:getVelocity()
	end

	self.hoseFraction = ( self.hoseFraction + dt * HoseSpeed ) % 1.0
	self.fireTimer:tick()
	if self.fireTimer:done() then
		self.fireTimer:start( FireInterval )

		-- Predict target position
		local distanceToTarget = ( self.target.worldPosition - self.unit.character.worldPosition ):length()
		local projectileTravelTime = distanceToTarget / ProjectileVelocity
		local expectedTargetMovement = self.predictedVelocity * projectileTravelTime
		local predictedTargetPosition = self.target.worldPosition + expectedTargetMovement

		-- Fire direction
		local fromToTarget = predictedTargetPosition - self.worldPosition
		local aimDirection = fromToTarget:safeNormalize( self.lookDirection )

		-- Hose fire direction
		local flatAimDirection = sm.vec3.new( aimDirection.x, aimDirection.y, 0.0 ):safeNormalize( self.lookDirection )
		local right = flatAimDirection:cross( sm.vec3.new( 0, 0, 1 ) )
		local adjustedHoseFraction = ( TriangleCurve( self.hoseFraction ) - 0.5 ) * 2.0
		aimDirection = aimDirection:rotate( adjustedHoseFraction * HoseMaxAngle, right )

		-- Clamp fire direction
		local aimAngle = clamp( math.acos( self.lookDirection:dot( aimDirection ) ), 0.0, MaxAimAngle )
		local aimRotationVector = ( self.lookDirection:cross( aimDirection ) ):safeNormalize( orthogonal( self.lookDirection ) )
		aimDirection = self.lookDirection:rotate( aimAngle, aimRotationVector )

		-- Fire bullet spray shot
		local fireDirection = sm.noise.gunSpread( aimDirection, GunSpreadDegrees )
		sm.projectile.projectileAttack( ProjectileUuid, ProjectileDamage, self.worldPosition, fireDirection * ProjectileVelocity, self.unit )
	end
end

--[[API functions]]

function TurboBulletSprayState.start( self )
	self.waitState:start()
	self.fireTimer:start( 0 )
end

function TurboBulletSprayState.stop( self )
	self.waitState:stop()
end

function TurboBulletSprayState.onFixedUpdate( self, dt )
	self.target = sm.exists( self.target ) and self.target or nil
	self.waitState:onFixedUpdate( dt )
	if self.target then
		self:sv_updateTurboBulletSpray( dt )
	end
end

function TurboBulletSprayState.onUnitUpdate( self, dt )
	self.waitState:onUnitUpdate( dt )
end

function TurboBulletSprayState.isDone( self )
	return self.waitState:isDone()
end

function TurboBulletSprayState.getMovementDirection( self )
	return self.waitState:getMovementDirection()
end

function TurboBulletSprayState.getFacingDirection( self )
	return self.waitState:getFacingDirection()
end

function TurboBulletSprayState.getMovementType( self )
	return self.waitState:getMovementType()
end

function TurboBulletSprayState.getWantsJump( self )
	return false
end