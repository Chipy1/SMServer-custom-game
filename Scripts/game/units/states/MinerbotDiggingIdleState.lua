dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

MinerbotDiggingIdleState = class( BaseState )

local MaxDistance = 3.0

-- State specific functions

function MinerbotDiggingIdleState.sv_onCreate( self, unit, diggingPosition, diggingDirection )
	self.unit = unit

	self.movementDirection = sm.vec3.new( 0, 1, 0 )
	self.diggingPosition = diggingPosition or self.unit.character.worldPosition
	self.diggingDirection = diggingDirection or self.unit.character.direction

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"
	self.idleState.randomEventCooldownMin = 0
	self.idleState.randomEventCooldownMax = 1
	self.idleState.randomEvents = { { name = "idlespecial02", time = 4.8, interruptible = false, chance = 0.85 },
									{ name = "idlespecial03", time = 4.8, interruptible = false, chance = 0.15 } }

	-- Movement
	self.flyMoveState = FlyMoveState()
	self.flyMoveState:sv_onCreate( self.unit )
	self.flyMoveState:sv_setMovementType( "walk" )
	self.flyMoveState.debugName = "flyMoveState"

	self.currentState = self.idleState
end

--[[API functions]]

function MinerbotDiggingIdleState.start( self )
	self.started = true
	self.currentState:stop()
	self.currentState = self.idleState
	self.currentState:start()
end

function MinerbotDiggingIdleState.stop( self )
	self.started = false
	self.currentState:stop()
end

function MinerbotDiggingIdleState.onFixedUpdate( self, timeStep )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	if self.currentState then
		self.currentState:onFixedUpdate( timeStep )
	end
end

function MinerbotDiggingIdleState.onUnitUpdate( self, dt )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end

	local fromTo = self.diggingPosition - self.unit.character.worldPosition
	local distance2 = fromTo:length2()
	local direction = fromTo:safeNormalize( sm.vec3.zero() )
	self.flyMoveState:sv_setDirection( direction )

	local nextState = self.currentState
	local done, result = self.currentState:isDone()
	if self.currentState == self.idleState and done then
		-- Check distance from dig site
		if distance2 > MaxDistance * MaxDistance then
			nextState = self.flyMoveState
		end
	elseif self.currentState == self.flyMoveState then
		if distance2 <= MaxDistance * MaxDistance then
			nextState = self.idleState
		end
	end

	if self.currentState ~= nextState then
		self.currentState:stop()
		self.currentState = nextState
		self.currentState:start()
	end
end

function MinerbotDiggingIdleState.isDone( self )
	return true, ""
end

function MinerbotDiggingIdleState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function MinerbotDiggingIdleState.getFacingDirection( self )
	return self.diggingDirection
end

function MinerbotDiggingIdleState.getMovementType( self )
	return self.currentState:getMovementType()
end

function MinerbotDiggingIdleState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function MinerbotDiggingIdleState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end