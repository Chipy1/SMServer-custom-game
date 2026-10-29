dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/SwimDirectionState.lua" )

SwimMoveState = class( BaseState )

local DefaultTolerance = 1.0

-- State specific functions

function SwimMoveState.sv_onCreate( self, unit )
	self.unit = unit
	self.destination = nil
	self.tolerance = DefaultTolerance
	self.movementType = "walk"

	-- Idle	
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Swim Direction
	self.swimDirectionState = SwimDirectionState()
	self.swimDirectionState:sv_onCreate( unit )
	self.swimDirectionState.debugName = "swimDirectionState"

	self.currentState = self.idleState
end

function SwimMoveState.sv_setMovementType( self, movementType )
	self.swimDirectionState:sv_setMovementType( movementType )
end

function SwimMoveState.sv_setDestination( self, destination )
	self.destination = destination
end

function SwimMoveState.sv_setTolerance( self, tolerance )
	self.tolerance = tolerance
end

--[[API functions]]

function SwimMoveState.start( self )
	self.started = true
end

function SwimMoveState.stop( self )
	self.started = false
end

function SwimMoveState.onFixedUpdate( self, dt )

	self.currentState:onFixedUpdate( dt )

	local prevState = self.currentState
	self.currentState = self.idleState
	if self.destination then
		local toDestination = self.destination - self.unit.character.worldPosition
		if toDestination:length2() > self.tolerance * self.tolerance then
			self.swimDirectionState:sv_setDirection( toDestination:safeNormalize( self.unit:getCurrentMovementDirection() ) )
			self.currentState = self.swimDirectionState
		end
	end

	if self.currentState ~= prevState then
		prevState:stop()
		self.currentState:start()
	end
end

function SwimMoveState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function SwimMoveState.isDone( self )
	return self.currentState == self.idleState, ""
end

function SwimMoveState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function SwimMoveState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function SwimMoveState.getMovementType( self )
	return self.currentState:getMovementType()
end

function SwimMoveState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function SwimMoveState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end