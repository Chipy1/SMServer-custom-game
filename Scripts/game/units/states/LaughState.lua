dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

LaughState = class( BaseState )

local LaughTime = 5.0

function LaughState.sv_onCreate( self, unit )
	self.unit = unit
	self.lookDirection = sm.vec3.new( 0, 1, 0 )
	self.stageIndex = 1

	self.laughEventState = self.unit:createState( "wait" )
	self.laughEventState.debugName = "laughEventState"
	self.laughEventState.name = "laugh"
	self.laughEventState.time = LaughTime
	self.laughEventState.interruptible = false

	self.laughFinishedEventState = self.unit:createState( "wait" )
	self.laughFinishedEventState.debugName = "laughFinishedEventState"
	self.laughFinishedEventState.name = "endLaugh"
	self.laughFinishedEventState.time = 0.5
	self.laughFinishedEventState.interruptible = false

	self.currentState = self.laughEventState
end

function LaughState.refresh( self ) end

function LaughState.sv_setLookDirection( self, lookDirection )
	self.lookDirection = lookDirection
end

function LaughState.sv_setPosition( self, worldPosition ) end

function LaughState.sv_setTarget( self, target )
	self.target = target
end

function LaughState.sv_setStage( self, stageIndex )
	self.stageIndex = stageIndex
end

--[[API functions]]

function LaughState.start( self )
	self.currentState:stop()
	self.currentState = self.laughEventState
	self.currentState:start()
end

function LaughState.stop( self )
	self.currentState:stop()
end

function LaughState.onFixedUpdate( self, dt )
	self.target = sm.exists( self.target ) and self.target or nil
	self.currentState:onFixedUpdate( dt )
	if self.currentState == self.laughEventState then
		local done, _ = self.currentState:isDone()
		if done then
			self.currentState:stop()
			self.currentState = self.laughFinishedEventState
			self.currentState:start()
		end
	end
end

function LaughState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function LaughState.isDone( self )
	if self.currentState == self.laughFinishedEventState then
		local done, _ = self.currentState:isDone()
		return done, "finished"
	elseif self.currentState == self.laughEventState then
		return false, "laugh"
	end
	return true, "unknown state"
end

function LaughState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function LaughState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function LaughState.getMovementType( self )
	return self.currentState:getMovementType()
end

function LaughState.getWantsJump( self )
	return false
end