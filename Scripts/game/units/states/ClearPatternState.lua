dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

ClearPatternState = class( BaseState )

local LaughTime = 5.0
local ClearTimeTickes = math.floor( 40 * 2.5 )

function ClearPatternState.sv_onCreate( self, unit )
	self.unit = unit
	self.lookDirection = sm.vec3.new( 0, 1, 0 )
	self.stageIndex = 1

	self.clearPatternEventState = self.unit:createState( "wait" )
	self.clearPatternEventState.debugName = "clearPatternEventState"
	self.clearPatternEventState.name = "laugh"
	self.clearPatternEventState.time = LaughTime
	self.clearPatternEventState.interruptible = false

	self.clearPatternFinishedEventState = self.unit:createState( "wait" )
	self.clearPatternFinishedEventState.debugName = "clearPatternFinishedEventState"
	self.clearPatternFinishedEventState.name = "endLaugh"
	self.clearPatternFinishedEventState.time = 0.5
	self.clearPatternFinishedEventState.interruptible = false

	self.currentState = self.clearPatternEventState
end

function ClearPatternState.refresh( self ) end

function ClearPatternState.sv_setLookDirection( self, lookDirection )
	self.lookDirection = lookDirection
end

function ClearPatternState.sv_setPosition( self, worldPosition ) end

function ClearPatternState.sv_setTarget( self, target )
	self.target = target
end

function ClearPatternState.sv_setStage( self, stageIndex )
	self.stageIndex = stageIndex
end

--[[API functions]]

function ClearPatternState.start( self )
	self.unit:sendCharacterEvent( "removeProjectiles" )
	self.currentState:stop()
	self.currentState = self.clearPatternEventState
	self.currentState:start()
end

function ClearPatternState.stop( self )
	self.currentState:stop()
end

function ClearPatternState.onFixedUpdate( self, dt )
	self.target = sm.exists( self.target ) and self.target or nil
	self.currentState:onFixedUpdate( dt )
	if self.currentState == self.clearPatternEventState then
		local done, _ = self.currentState:isDone()
		if done then
			self.currentState:stop()
			self.currentState = self.clearPatternFinishedEventState
			self.currentState:start()
		end
	end
end

function ClearPatternState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function ClearPatternState.isDone( self )
	if self.currentState == self.clearPatternFinishedEventState then
		local done, _ = self.currentState:isDone()
		return done, "finished"
	elseif self.currentState == self.clearPatternEventState then
		return false, "laugh"
	end
	return true, "unknown state"
end

function ClearPatternState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function ClearPatternState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function ClearPatternState.getMovementType( self )
	return self.currentState:getMovementType()
end

function ClearPatternState.getWantsJump( self )
	return false
end