dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

-- Chain two events together without sending a stop event
ToteRedIgniteState = class( BaseState )

local IgniteTime = 1.0
local EruptTime = 1.0

function ToteRedIgniteState.sv_onCreate( self, unit )
	self.unit = unit

	self.igniteEventState = self.unit:createState( "wait" )
	self.igniteEventState.debugName = "igniteEventState"
	self.igniteEventState.name = "ignite"
	self.igniteEventState.time = IgniteTime
	self.igniteEventState.interruptible = false

	self.eruptEventState = self.unit:createState( "wait" )
	self.eruptEventState.debugName = "eruptEventState"
	self.eruptEventState.name = "erupt"
	self.eruptEventState.time = EruptTime
	self.eruptEventState.interruptible = false

	self.currentState = self.igniteEventState
end

--[[API functions]]

function ToteRedIgniteState.start( self )
	self.currentState = self.igniteEventState
	self.currentState:start()
end

function ToteRedIgniteState.reset( self )
	self.igniteEventState.time = IgniteTime
	self.eruptEventState.time = EruptTime
end

function ToteRedIgniteState.stop( self ) end

function ToteRedIgniteState.onFixedUpdate( self, dt )
	self.currentState:onFixedUpdate( dt )

	if self.currentState == self.igniteEventState then
		local done, result = self.currentState:isDone()
		if done then
			self.currentState = self.eruptEventState
			self.currentState:start()
			self.unit:sendCharacterEvent( "alerted" )
		end
	end
end

function ToteRedIgniteState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function ToteRedIgniteState.isDone( self )
	local done, result = self.currentState:isDone()
	if self.currentState == self.eruptEventState then
		return done, result
	end
	return false, result
end

function ToteRedIgniteState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function ToteRedIgniteState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function ToteRedIgniteState.getMovementType( self )
	return self.currentState:getMovementType()
end

function ToteRedIgniteState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function ToteRedIgniteState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end