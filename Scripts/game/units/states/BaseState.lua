BaseState = class( nil )

--[[API functions]]
function BaseState.start( self ) end

function BaseState.stop( self ) end

function BaseState.onFixedUpdate( self, dt ) end

function BaseState.onUnitUpdate( self, dt ) end

function BaseState.isDone( self )
	return true, ""
end

function BaseState.getMovementDirection( self )
	return sm.vec3.new( 0, 1, 0 )
end

function BaseState.getFacingDirection( self )
	return sm.vec3.new( 0, 1, 0 )
end

function BaseState.getMovementType( self )
	return "stand"
end

function BaseState.getWantsJump( self )
	return false
end

function BaseState.getWantsCrouch( self )
	return false
end