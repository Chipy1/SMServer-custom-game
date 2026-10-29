dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

MinerbotRoamingState = class( BaseState )

local MaxDistance = 14.0
local MinDistance = 3.0
local Tolerance = 0.5
local MinIdleTickTime = 40 * 3.0
local MaxIdleTickTime = 40 * 7.0
local MaxRoamingTickTime = 40 * 3.0

-- State specific functions

function MinerbotRoamingState.sv_onCreate( self, unit, homePosition )
	self.unit = unit

	self.movementDirection = sm.vec3.new( 0, 1, 0 )
	self.homePosition = homePosition or self.unit.character.worldPosition
	self:calculateNewDestination()
	self.idleTimer = Timer()
	self.roamTimer = Timer()

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"
	self.idleState.randomEventCooldownMin = 4
	self.idleState.randomEventCooldownMax = 6
	self.idleState.randomEvents = { { name = "idlespecial01", time = 3.2, interruptible = false, chance = 0.8 },
									{ name = "idlespecial03", time = 4.8, interruptible = false, chance = 0.2 } }

	-- Movement
	self.flyMoveState = FlyMoveState()
	self.flyMoveState:sv_onCreate( self.unit )
	self.flyMoveState:sv_setMovementType( "walk" )
	self.flyMoveState.debugName = "flyMoveState"

	self.currentState = self.idleState
end

function MinerbotRoamingState.calculateNewDestination( self )
	local randomDistance = MinDistance + ( MaxDistance - MinDistance ) * math.random()
	local distanceVector = sm.vec3.new( 0, randomDistance, 0 )
	local randomOffset = distanceVector:rotateZ( math.rad( math.random() * 360 ) )
	local wantedDestination = self.homePosition + randomOffset

	local hit, result = sm.physics.spherecast( self.homePosition, wantedDestination, 0.25, self.unit.character, sm.physics.filter.static )
	if hit then
		wantedDestination = result.pointWorld
	end
	hit, result = sm.physics.spherecast( self.unit.character.worldPosition, wantedDestination, 0.24, self.unit.character, sm.physics.filter.static )
	if hit then
		wantedDestination = result.pointWorld
	end

	self.destination = wantedDestination
end

--[[API functions]]

function MinerbotRoamingState.start( self )
	self.started = true
	self.idleTimer:start( math.random( MinIdleTickTime, MaxIdleTickTime ) )
	self.roamTimer:start( MaxRoamingTickTime )
	self.currentState:stop()
	self.currentState = self.idleState
	self.currentState:start()
end

function MinerbotRoamingState.stop( self )
	self.started = false
	self.currentState:stop()
end

function MinerbotRoamingState.onFixedUpdate( self, timeStep )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	if self.currentState then
		self.currentState:onFixedUpdate( timeStep )
	end

	local nextState = self.currentState
	local done, result = self.currentState:isDone()
	if self.currentState == self.idleState and done then
		self.idleTimer:tick()
		if self.idleTimer:done() then
			self:calculateNewDestination()
			local direction = ( self.destination - self.unit.character.worldPosition ):safeNormalize( sm.vec3.zero() )
			self.flyMoveState:sv_setDirection( direction )
			nextState = self.flyMoveState
			self.roamTimer:start( MaxRoamingTickTime )
		end
	elseif self.currentState == self.flyMoveState then
		local distance2 = ( self.destination - self.unit.character.worldPosition ):length2()
		self.roamTimer:tick()
		if self.roamTimer:done() or distance2 <= Tolerance * Tolerance then
			nextState = self.idleState
			self.idleTimer:start( math.random( MinIdleTickTime, MaxIdleTickTime ) )
		end
	end

	if self.currentState ~= nextState then
		self.currentState:stop()
		self.currentState = nextState
		self.currentState:start()
	end
end

function MinerbotRoamingState.onUnitUpdate( self, dt )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end
end

function MinerbotRoamingState.isDone( self )
	return true, ""
end

function MinerbotRoamingState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function MinerbotRoamingState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function MinerbotRoamingState.getMovementType( self )
	return self.currentState:getMovementType()
end

function MinerbotRoamingState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function MinerbotRoamingState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end