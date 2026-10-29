dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
--TODO add animations or remove
DualVolleyBombState = class( BaseState )

local ProjectileUuid = projectile_trashbomb_green
local ProjectileDamage = 30
local StartupDelay = 40 * 0.0
local FireInterval = 40 * 0.76
local VolleysPerAttack = 4
local BombWarningTickTime = 40 * 5
local GunSpreadDegrees = 5

function DualVolleyBombState.sv_onCreate( self, unit, isRightSide )
	self.unit = unit
	self.lookDirection = sm.vec3.new( 0, 1, 0 )
	self.worldPosition = sm.vec3.zero()
	self.stageIndex = 1
	self.isRightSide = isRightSide

	self.waitState = self.unit:createState( "wait" )
	self.waitState.debugName = "waitState"
	self.waitState.time = 5.0
	self.waitState.interruptible = false

	self.fireTimer = Timer()
	self.timesFired = 0
end

function DualVolleyBombState.refresh( self ) end

function DualVolleyBombState.sv_setLookDirection( self, lookDirection )
	self.lookDirection = lookDirection
end

function DualVolleyBombState.sv_setPosition( self, worldPosition )
	self.worldPosition = worldPosition
end

function DualVolleyBombState.sv_setTarget( self, target )
	self.target = target
end

function DualVolleyBombState.sv_setStage( self, stageIndex )
	self.stageIndex = stageIndex
end

function DualVolleyBombState.sv_updateVolleyBombardment( self )
	if self.timesFired < VolleysPerAttack then
		self.fireTimer:tick()
		if self.fireTimer:done() then
			self.fireTimer:start( FireInterval)

			-- Spawn bomb warnings through the trashbot character
			local deathTick = sm.game.getCurrentTick() + BombWarningTickTime
			local bombWarnings = { { position = self.target.worldPosition, deathTick = deathTick } }

			-- Calculate projectile velocity needed to hit the target
			local fromToTarget = self.target.worldPosition - self.worldPosition
			local fromToTargetNorm = fromToTarget:safeNormalize( self.lookDirection )
			local aimDot = math.max( fromToTargetNorm:dot( sm.vec3.new( 0, 0, 1 ) ), 0 )
			local velocityExtremeVertical = math.sqrt( sm.vec3.new( 0, 0, fromToTarget.z ):length() * 10 * 4 )
			local velocityExtremeHorizontal = math.sqrt( sm.vec3.new( fromToTarget.x, fromToTarget.y, 0 ):length() * 10 )
			local projectileVelocity = velocityExtremeHorizontal * math.sqrt( 1.0 -  aimDot ) + velocityExtremeVertical * math.sqrt( aimDot )

			-- Fire bombs in an arc
			local _, highAngleVector = sm.projectile.solveBallisticArc( self.worldPosition, self.target.worldPosition, projectileVelocity, GRAVITY )
			if highAngleVector then
				local highAngleVectorWithSpread = sm.noise.gunSpread( highAngleVector, GunSpreadDegrees )
				sm.projectile.projectileAttack( ProjectileUuid, ProjectileDamage, self.worldPosition, highAngleVectorWithSpread, self.unit )
				self.timesFired = self.timesFired + 1
			end
		end
	end
end

--[[API functions]]

function DualVolleyBombState.start( self )
	self.waitState:start()
	self.fireTimer:start( StartupDelay )
	self.timesFired = 0
end

function DualVolleyBombState.stop( self )
	self.waitState:stop()
end

function DualVolleyBombState.onFixedUpdate( self, dt )
	self.target = sm.exists( self.target ) and self.target or nil
	self.waitState:onFixedUpdate( dt )
	if self.target then
		self:sv_updateVolleyBombardment()
	end
end

function DualVolleyBombState.onUnitUpdate( self, dt )
	self.waitState:onUnitUpdate( dt )
end

function DualVolleyBombState.isDone( self )
	return self.waitState:isDone()
end

function DualVolleyBombState.getMovementDirection( self )
	return self.waitState:getMovementDirection()
end

function DualVolleyBombState.getFacingDirection( self )
	return self.waitState:getFacingDirection()
end

function DualVolleyBombState.getMovementType( self )
	return self.waitState:getMovementType()
end

function DualVolleyBombState.getWantsJump( self )
	return false
end