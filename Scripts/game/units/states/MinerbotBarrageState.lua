dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/RayProjectileManager.lua" )

MinerbotBarrageState = class( BaseState )

local WindupTime = 1.6
local BarrageAmount = 100
local FireTickInterval = 3
local FireSpread = 5
local ProjectileDistance = 96.0
local ProjectileDamage = 1
local DestructionLevel = 2
local ProjectileFallbackHeightOffset = sm.vec3.new( 0, 0, -1.75 )
local ProjectileFallbackForwardOffset = 0.75
local OffsetDistance = 7         -- How far away the projectile will land with maximum offset
local OffsetFractionDelta = 0.06 -- How much closer the next shot will be in fraction

-- State specific functions

function MinerbotBarrageState.sv_onCreate( self, unit )
	self.unit = unit

	self.lastAttackedPosition = nil
	self.target = nil
	self.projectilesLeft = BarrageAmount

	self.offsetFraction = 0.0

	self.fireTimer = Timer()
	self.animationIsFiring = false
end

function MinerbotBarrageState.sv_setTarget( self, target )
	self.target = target
	if sm.exists( self.target ) then
		self.targetPosition = self.target.worldPosition
	else
		self.targetPosition = nil
	end
end

function MinerbotBarrageState.sv_setTargetPosition( self, targetPosition )
	self.targetPosition = targetPosition
	self.target = nil
end

function MinerbotBarrageState.sv_getLastAttackedPosition( self )
	return self.lastAttackedPosition
end

function MinerbotBarrageState.sv_updateBarrage( self )
	if self.predictedTargetPosition and sm.exists( self.unit.character ) and self.projectilesLeft > 0 then
		if not self.animationIsFiring then
			self.animationIsFiring = true
			self.unit:sendCharacterEvent( "startbarrage" )
		end
		self.fireTimer:tick()
		if self.fireTimer:done() then
			self.fireTimer:start( FireTickInterval )

			-- Fire closer each time
			self.offsetFraction = math.max( self.offsetFraction - OffsetFractionDelta, 0 )

			-- Fire direction and position	
			local firePosition = self.unit.character:getTpBonePos( "pejnt_shoot" )
			if firePosition == nil then
				local lookDirection = self.unit.character.direction
				local forward = sm.vec3.new( lookDirection.x, lookDirection.y, 0.0 ):safeNormalize( sm.vec3.new( 0, 1, 0 ) )
				local directionOffset = forward * ProjectileFallbackForwardOffset
				firePosition = self.unit.character.worldPosition + ProjectileFallbackHeightOffset + directionOffset
			end
			local fromToTarget = self.predictedTargetPosition - firePosition
			local aimDirection = fromToTarget:safeNormalize( sm.vec3.new( 0, 0, -1 ) )
			local fireDirection = aimDirection
			fireDirection = sm.noise.gunSpread( aimDirection, FireSpread )

			-- Fire ray shot
			RayProjectileManager.Sv_FireRayProjectile( firePosition, firePosition + fireDirection * ProjectileDistance,
				self.unit.character, ProjectileDamage, DestructionLevel, "minerbotprojectile" )
			self.lastAttackedPosition = self.predictedTargetPosition
			self.projectilesLeft = self.projectilesLeft - 1
		end
	else
		if self.animationIsFiring then
			self.animationIsFiring = false
			self.unit:sendCharacterEvent( "stopbarrage" )
		end
	end
end

--[[API functions]]

function MinerbotBarrageState.start( self )
	self.started = true
	self.fireTimer:start( WindupTime * 40 )
	self.projectilesLeft = BarrageAmount
	self.offsetFraction = 1.0
end

function MinerbotBarrageState.stop( self )
	self.started = false
	if self.animationIsFiring then
		self.animationIsFiring = false
		self.unit:sendCharacterEvent( "stopbarrage" )
	end
	self.lastAttackedPosition = nil
end

function MinerbotBarrageState.onFixedUpdate( self, timeStep )
	local character = self.unit.character
	if not sm.exists( character ) then return end

	if sm.exists( self.target ) then
		self.targetPosition = self.target.worldPosition
	end

	if self.targetPosition then
		local leveledSelfPosition = sm.vec3.new( self.unit.character.worldPosition.x, self.unit.character.worldPosition.y,
			self.targetPosition.z )
		local levelFromTo = leveledSelfPosition - self.targetPosition
		local leveledDirection = levelFromTo:safeNormalize( sm.vec3.new( 0, 1, 0 ) )
		local clampedOffsetDistance = math.min( levelFromTo:length(), OffsetDistance )
		local offsetTargetPosition = self.targetPosition + leveledDirection * clampedOffsetDistance
		self.predictedTargetPosition = sm.vec3.lerp( self.targetPosition, offsetTargetPosition, self.offsetFraction )
	end

	self:sv_updateBarrage()
end

function MinerbotBarrageState.isDone( self )
	return self.projectilesLeft <= 0, ""
end

function MinerbotBarrageState.getFacingDirection( self )
	if self.targetPosition and sm.exists( self.unit.character ) then
		local fromToTarget = self.targetPosition - self.unit.character.worldPosition
		return fromToTarget:safeNormalize( sm.vec3.new( 0, 0, -1 ) )
	end
	return BaseState:getFacingDirection()
end

function MinerbotBarrageState.getMovementType( self )
	return "stand"
end

function MinerbotBarrageState.getWantsJump( self )
	return false
end

function MinerbotBarrageState.getWantsCrouch( self )
	return false
end
