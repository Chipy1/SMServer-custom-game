dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

MinerbotAlertState = class( BaseState )

local AlertSwitchTime = 0

-- State specific functions

function MinerbotAlertState.sv_onCreate( self, unit )
	self.unit = unit

	-- Alert
	self.alertEventState = self.unit:createState( "wait" )
	self.alertEventState.debugName = "waitState"
	self.alertEventState.time = AlertSwitchTime
	self.alertEventState.name = "alert"
	self.alertEventState.interruptible = false
end

function MinerbotAlertState.sv_setTarget( self, target )
	self.target = target
	if sm.exists( self.target ) then
		self.targetPosition = self.target.worldPosition
	else
		self.targetPosition = nil
	end
end

function MinerbotAlertState.sv_setTargetPosition( self, targetPosition )
	self.targetPosition = targetPosition
	self.target = nil
end

--[[API functions]]

function MinerbotAlertState.start( self )
	self.started = true
	self.alertEventState:start()
end

function MinerbotAlertState.stop( self )
	self.started = false
	self.alertEventState:stop()
end

function MinerbotAlertState.onFixedUpdate( self, timeStep )
	local character = self.unit.character
	if not sm.exists( character ) then return end
	self.alertEventState:onFixedUpdate( timeStep )

	if sm.exists( self.target ) then
		self.targetPosition = self.target.worldPosition
	end
end

function MinerbotAlertState.onUnitUpdate( self, dt )
	self.alertEventState:onUnitUpdate( dt )
end

function MinerbotAlertState.isDone( self )
	return self.alertEventState:isDone()
end

function MinerbotAlertState.getMovementDirection( self )
	return self.alertEventState:getMovementDirection()
end

function MinerbotAlertState.getFacingDirection( self )
	if self.targetPosition  then
		return ( self.targetPosition - self.unit.character.worldPosition ):safeNormalize( self.unit.character.direction )
	end
	return self.unit.character.direction
end

function MinerbotAlertState.getMovementType( self )
	return self.alertEventState:getMovementType()
end

function MinerbotAlertState.getWantsJump( self )
	return self.alertEventState:getWantsJump()
end

function MinerbotAlertState.getWantsCrouch( self )
	return self.alertEventState:getWantsCrouch()
end