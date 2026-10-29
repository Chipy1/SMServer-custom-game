dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

FlyMoveState = class( BaseState )

-- State specific functions

function FlyMoveState.sv_onCreate( self, unit )
	self.unit = unit
	self.movementType = "walk"
	self.movementDirection = self.unit:getCurrentMovementDirection()
end

function FlyMoveState.sv_onDestroy( self ) end

function FlyMoveState.sv_setMovementType( self, movementType )
	self.movementType = movementType
end

function FlyMoveState.sv_setDirection( self, direction )
	self.movementDirection = direction
end

-- AiState common interface

function FlyMoveState.start( self )
	self.started = true
end

function FlyMoveState.stop( self )
	self.started = false
end

function FlyMoveState.onFixedUpdate( self, timeStep ) end

function FlyMoveState.onUnitUpdate( self, dt ) end

function FlyMoveState.isDone( self )
	return false, ""
end

function FlyMoveState.getMovementDirection( self )
	return self.movementDirection
end

function FlyMoveState.getFacingDirection( self )
	return self.movementDirection
end

function FlyMoveState.getMovementType( self )
	return self.movementType
end

function FlyMoveState.getWantsJump( self )
	return false
end

function FlyMoveState.getWantsCrouch( self )
	return false
end