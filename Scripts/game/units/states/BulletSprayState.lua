dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

BulletSprayState = class( BaseState )

local MaxAimAngle = math.rad( 90.0 )

local ProjectileDamage = 1.0
local ProjectileVelocity = 35
local StartupDelay = 0
local FireInterval = 1
local SpiralTurns = 3
local SpraySpiralMaxAngle = math.rad( 1.9 )
local SprayEasing = "easeOutCubic"
local SprayTime = 0.7
local InitialTargetOffset = 20.0
local CorrectionDuration = math.floor( 1.0 * 40 )

local SprayInTime = 0.5
local SprayOutTime = 0.5

function BulletSprayState.sv_onCreate( self, unit, isRightSide )
	self.unit = unit
	self.lookDirection = sm.vec3.new( 0, 1, 0 )
	self.worldPosition = sm.vec3.zero()
	self.stageIndex = 1
	self.isRightSide = isRightSide

	self.sprayInState = self.unit:createState( "wait" )
	self.sprayInState.debugName = "bulletSprayInState"
	self.sprayInState.time = SprayInTime
	self.sprayInState.name = isRightSide and "spray_right_in" or "spray_left_in"
	self.sprayInState.interruptible = false

	self.sprayLoopState = self.unit:createState( "wait" )
	self.sprayLoopState.debugName = "bulletSprayLoopState"
	self.sprayLoopState.time = 5
	self.sprayLoopState.name = isRightSide and "spray_right_loop" or "spray_left_loop"
	self.sprayLoopState.interruptible = false

	self.sprayOutState = self.unit:createState( "wait" )
	self.sprayOutState.debugName = "bulletSprayOutState"
	self.sprayOutState.time = SprayOutTime
	self.sprayOutState.name = isRightSide and "spray_right_out" or "spray_left_out"
	self.sprayOutState.interruptible = false

	self.currentState = self.sprayInState
	
	self.offsetDirection = sm.vec3.new( 0.0, 0.0, 0.0 )

	self.fireTimer = Timer()
	self.aimCorrectionTimer = Timer()
	self.spiralOffset = 0
	self.spiralDirectionToggle = math.random( 0, 1 ) > 0
end

function BulletSprayState.refresh( self ) end

function BulletSprayState.sv_setLookDirection( self, lookDirection )
	self.lookDirection = lookDirection
end

function BulletSprayState.sv_setPosition( self, worldPosition )
	self.worldPosition = worldPosition
end

function BulletSprayState.sv_setTarget( self, target )
	self.target = target
end

function BulletSprayState.sv_setStage( self, stageIndex )
	self.stageIndex = stageIndex
end

function BulletSprayState.sv_updateBulletSpray( self )
	self.fireTimer:tick()
	if self.fireTimer:done() then
		self.fireTimer:start( FireInterval )
		
		-- Fire direction
		local fromToTarget = self.target.worldPosition - self.worldPosition
		if self.aimCorrectionTimer:isActive() and self.aimCorrectionTimer:getTick() == 0 then
			self.offsetDirection = sm.vec3.cross( fromToTarget:safeNormalize( self.lookDirection ), self.isRightSide and sm.vec3.new( 0.0, 0.0, 1.0 ) or sm.vec3.new( 0.0, 0.0, -1.0 ) )
		end
		
		local aimCorrection = math.max( InitialTargetOffset - ( self.aimCorrectionTimer:getTick() / CorrectionDuration ) * InitialTargetOffset, 0.0 )
		local aimDirection = ( fromToTarget + self.offsetDirection * aimCorrection ):safeNormalize( self.lookDirection )

		-- Clamp fire direction
		local aimAngle = clamp( math.acos( self.lookDirection:dot( aimDirection ) ), 0.0, MaxAimAngle )
		local aimRotationVector = ( self.lookDirection:cross( aimDirection ) ):safeNormalize( orthogonal( self.lookDirection ) )
		aimDirection = self.lookDirection:rotate( aimAngle, aimRotationVector )

		-- Rotate spiral aim
		local sprayProgress = self.sprayLoopState.elapsedTime / self.sprayLoopState.time
		local outInProgress = math.max( 1 - math.abs( ( sprayProgress * 2 - 1 ) ), 0 )
		local spraySpread = sm.util.easing( SprayEasing, outInProgress ) * SpraySpiralMaxAngle
		local fireDirection = aimDirection:rotate( spraySpread, aimRotationVector )
		local spinProgress = self.spiralOffset + sprayProgress * SpiralTurns * math.pi * 2
		local aimRotationVector = self.spiralDirectionToggle and aimDirection or -aimDirection
		fireDirection = fireDirection:rotate( spinProgress, aimRotationVector )

		self.aimCorrectionTimer:tick()
		-- Fire bullet spray shot
		sm.projectile.projectileAttack( self.isRightSide and projectile_trashbubble_green or projectile_trashbubble_purple , ProjectileDamage, self.worldPosition, fireDirection * ProjectileVelocity, self.unit )
	end
end

--[[API functions]]

function BulletSprayState.start( self )
	self.currentState:stop()
	self.currentState = self.sprayInState
	self.currentState:start()
	self.spiralOffset = math.random() * math.pi * 2
	self.offsetDirection = sm.vec3.new( 0.0, 0.0, 0.0 )
end

function BulletSprayState.stop( self )
	if self.currentState then
		self.currentState:stop()
		self.fireTimer:stop()
		self.aimCorrectionTimer:stop()
		self.unit:sendCharacterEvent( self.sprayOutState.name )
	end
end

function BulletSprayState.onFixedUpdate( self, dt )
	self.target = sm.exists( self.target ) and self.target or nil
	self.currentState:onFixedUpdate( dt )
	local done, _ = self.currentState:isDone()
	if done then
		if self.currentState.debugName == "bulletSprayInState" then
			self.currentState = self.sprayLoopState
			self.currentState:start()
			self.fireTimer:start( StartupDelay )
			self.aimCorrectionTimer:start( CorrectionDuration )
		elseif self.currentState.debugName == "bulletSprayLoopState" then
			self.currentState = self.sprayOutState
			self.currentState:start()
			self.sprayLoopState.time = SprayTime
		end
	end

	if self.target and not done and self.currentState.debugName == "bulletSprayLoopState" then
		self:sv_updateBulletSpray( dt )
	end
end

function BulletSprayState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function BulletSprayState.isDone( self )
	if self.currentState == self.sprayOutState then
		return self.currentState:isDone()
	elseif self.currentState == self.sprayInState or self.currentState == self.sprayLoopState then
		return false, "sprayActive"
	end
	return true, "unknown state"
end

function BulletSprayState.getMovementDirection( self )
	return self.sprayLoopState:getMovementDirection()
end

function BulletSprayState.getFacingDirection( self )
	return self.sprayLoopState:getFacingDirection()
end

function BulletSprayState.getMovementType( self )
	return self.sprayLoopState:getMovementType()
end

function BulletSprayState.getWantsJump( self )
	return false
end

function BulletSprayState.setLoopDuration( self, loopDuration )
	self.sprayLoopState.time = loopDuration
end