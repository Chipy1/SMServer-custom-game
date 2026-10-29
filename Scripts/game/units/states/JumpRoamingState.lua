dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/JumpMoveState.lua" )

JumpRoamingState = class( BaseState )

local MaxDistance = 14.0
local MinDistance = 4.0
local StandTolerance = 1.0
local WalkTolerance = 2.0
local MinIdleTickTime = 40 * 3.0
local MaxIdleTickTime = 40 * 7.0
local MaxRoamingTickTime = 40 * 12.0

-- State specific functions

function JumpRoamingState.sv_onCreate( self, unit, homePosition )
	self.unit = unit

	self.movementDirection = sm.vec3.new( 0, 1, 0 )
	self.homePosition = homePosition or self.unit.character.worldPosition

	self.idleTimer = Timer()
	self.roamTimer = Timer()

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Move state
	self.jumpMoveState = JumpMoveState()
	self.jumpMoveState:sv_onCreate( self.unit )
	self.jumpMoveState.debugName = "jumpMoveState"

	-- Roam state, used to get a destination
	self.roamState = self.unit:createState( "roam" )
	self.roamState.debugName = "roamState"
	self.roamState.tetherPosition = self.homePosition
	self.roamState.waterAvoidance = true
	self.roamState.maxRadius = MaxDistance
	self.roamState.minRadius = MinDistance
	self.roamState.roamCenterOffset = 0.0
	self.roamState.maxTetherDistance = MaxDistance
	self.roamState.customData = { onUnitUpdateOnly = true }
	self.roamState:start() -- Calculate new destination

	self.currentState = self.idleState
end

--[[API functions]]

function JumpRoamingState.start( self )
	self.started = true
	self.idleTimer:start( math.random( MinIdleTickTime, MaxIdleTickTime ) )
	self.roamTimer:start( MaxRoamingTickTime )
	self.currentState:stop()
	self.currentState = self.idleState
	self.currentState:start()
end

function JumpRoamingState.stop( self )
	self.started = false
	self.currentState:stop()
end

function JumpRoamingState.onFixedUpdate( self, timeStep )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	if self.currentState then
		if not self.currentState.customData or not self.currentState.customData.onUnitUpdateOnly then
			self.currentState:onFixedUpdate( timeStep )
		end
	end

	local nextState = self.currentState
	if self.currentState == self.idleState then
		self.idleTimer:tick()
		if self.idleTimer:done() then
			self.roamState:start() -- Calculate new destination
			local direction = ( self.roamState.currentDestination - self.unit.character.worldPosition ):safeNormalize( sm.vec3.zero() )
			self.jumpMoveState:sv_setDirection( direction )
			nextState = self.jumpMoveState
			self.roamTimer:start( MaxRoamingTickTime )
		end
	elseif self.currentState == self.jumpMoveState then
		self.roamTimer:tick()
		if self.unit.character:isOnGround() then
			local direction = ( self.roamState.currentDestination - self.unit.character.worldPosition ):safeNormalize( sm.vec3.zero() )
			self.jumpMoveState:sv_setDirection( direction )

			local distance2 = ( self.roamState.currentDestination - self.unit.character.worldPosition ):length2()
			if self.roamTimer:done() or distance2 <= StandTolerance * StandTolerance then
				nextState = self.idleState
				self.idleTimer:start( math.random( MinIdleTickTime, MaxIdleTickTime ) )
			end
		end
	end

	if self.currentState ~= nextState then
		self.currentState:stop()
		self.currentState = nextState
		self.currentState:start()
	end
end

function JumpRoamingState.onUnitUpdate( self, dt )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
		if self.currentState.customData and self.currentState.customData.onUnitUpdateOnly then
			self.currentState:onFixedUpdate( dt )
		end
	end
end

function JumpRoamingState.isDone( self )
	return true, ""
end

function JumpRoamingState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function JumpRoamingState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function JumpRoamingState.getMovementType( self )
	if not self.unit.character:isOnGround() then
		local diff = self.roamState.currentDestination - self.unit.character.worldPosition
		diff.z = 0
		local distance2 = diff:length2()
		if distance2 > WalkTolerance * WalkTolerance then
			return "sprint"
		elseif distance2 > StandTolerance * StandTolerance then
			return "walk"
		end
	end
	return "stand"
end

function JumpRoamingState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function JumpRoamingState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end