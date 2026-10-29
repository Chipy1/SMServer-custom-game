dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/JumpMoveState.lua" )

JumpFleeState = class( PathingState )


-- State specific functions

function JumpFleeState.sv_onCreate( self, unit )
	self.unit = unit

	self.movementDirection = sm.vec3.new( 0, 1, 0 )

	-- Move state
	self.jumpMoveState = JumpMoveState()
	self.jumpMoveState:sv_onCreate( self.unit )
	self.jumpMoveState.debugName = "jumpMoveState"
	self.jumpMoveState:sv_setDirection( self.movementDirection )

	self.currentState = self.jumpMoveState
end

--[[API functions]]

function JumpFleeState.start( self )
	self.started = true
	local closestPlayerCharacter = GetClosestPlayerCharacter( self.unit.character.worldPosition, self.unit.character:getWorld() )
	if closestPlayerCharacter then
		self.movementDirection = ( self.unit.character.worldPosition - closestPlayerCharacter.worldPosition ):safeNormalize( self.movementDirection )
	end
	self.jumpMoveState:sv_setDirection( self.movementDirection )
	self.currentState:stop()
	self.currentState = self.jumpMoveState
	self.currentState:start()
	self.done = nil
end

function JumpFleeState.stop( self )
	self.started = false
	self.currentState:stop()
end

function JumpFleeState.onFixedUpdate( self, timeStep )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	local closestPlayerCharacter = GetClosestPlayerCharacter( self.unit.character.worldPosition, self.unit.character:getWorld() )
	if closestPlayerCharacter then
		self.movementDirection = ( self.unit.character.worldPosition - closestPlayerCharacter.worldPosition ):safeNormalize( self.movementDirection )
	end
	self.jumpMoveState:sv_setDirection( self.movementDirection )

	if self.currentState then
		self.currentState:onFixedUpdate( timeStep )
	end
end

function JumpFleeState.onUnitUpdate( self, dt )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end
end

function JumpFleeState.isDone( self )
	return false, ""
end

function JumpFleeState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function JumpFleeState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function JumpFleeState.getMovementType( self )
	return self.currentState:getMovementType()
end

function JumpFleeState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function JumpFleeState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end