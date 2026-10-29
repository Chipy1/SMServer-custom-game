dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

SwimDirectionState = class( BaseState )

-- State specific functions

function SwimDirectionState.sv_onCreate( self, unit )
	self.unit = unit
	self.movementType = "walk"
	self.movementDirection = self.unit:getCurrentMovementDirection()
end

function SwimDirectionState.sv_setMovementType( self, movementType )
	self.movementType = movementType
end

function SwimDirectionState.sv_setDirection( self, direction )
	self.movementDirection = direction
end

--[[API functions]]

function SwimDirectionState.start( self )
	self.started = true
end

function SwimDirectionState.stop( self )
	self.started = false
end

function SwimDirectionState.onFixedUpdate( self, dt ) end

function SwimDirectionState.onUnitUpdate( self, dt ) end

function SwimDirectionState.isDone( self )
	return false, ""
end

function SwimDirectionState.getMovementDirection( self )
	return self.movementDirection
end

function SwimDirectionState.getFacingDirection( self )
	return self.movementDirection
end

function SwimDirectionState.getMovementType( self )
	return self.movementType
end

function SwimDirectionState.getWantsJump( self )
	return false
end

function SwimDirectionState.getWantsCrouch( self )
	return false
end