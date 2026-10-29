dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

DestructionSwayState = class( BaseState )

local DestroyInDuration = 2.0

function DestructionSwayState.sv_onCreate( self, unit )
	self.unit = unit
	self.lookDirection = sm.vec3.new( 0, 1, 0 )
	self.stageIndex = 1

	self.destructionSwayInState = self.unit:createState( "wait" )
	self.destructionSwayInState.debugName = "destructionSwayInState"
	self.destructionSwayInState.name = "neardeath_in"
	self.destructionSwayInState.time = DestroyInDuration
	self.destructionSwayInState.interruptible = false

	self.destructionSwayLoopState = self.unit:createState( "wait" )
	self.destructionSwayLoopState.debugName = "destructionSwayLoopState"
	self.destructionSwayLoopState.name = "neardeath_loop"
	self.destructionSwayLoopState.time = 60 -- 1 minute
	self.destructionSwayLoopState.interruptible = false

	self.currentState = self.destructionSwayInState
end

function DestructionSwayState.refresh( self ) end

function DestructionSwayState.sv_setLookDirection( self, lookDirection )
end

function DestructionSwayState.sv_setPosition( self, worldPosition ) end

function DestructionSwayState.sv_setTarget( self, target )
	self.target = target
end

function DestructionSwayState.sv_setStage( self, stageIndex )
	self.stageIndex = stageIndex
end

--[[API functions]]

function DestructionSwayState.start( self )
	self.currentState:stop()
	self.currentState = self.destructionSwayInState
	self.currentState:start()
end

function DestructionSwayState.stop( self )
	self.currentState:stop()
end

function DestructionSwayState.onFixedUpdate( self, dt )
	self.currentState:onFixedUpdate( dt )
		local done, _ = self.currentState:isDone()
		if done then
			self.currentState:stop()
		if self.currentState == self.destructionSwayInState then
			self.currentState = self.destructionSwayLoopState
			self.currentState:start()
		elseif self.currentState == self.destructionSwayLoopState then
		end
	end
end

function DestructionSwayState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function DestructionSwayState.isDone( self )
	if self.currentState == self.destructionSwayLoopState then
		local done, _ = self.currentState:isDone()
		return done, "finished"
	end
	return false, ""
end

function DestructionSwayState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function DestructionSwayState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function DestructionSwayState.getMovementType( self )
	return self.currentState:getMovementType()
end

function DestructionSwayState.getWantsJump( self )
	return false
end