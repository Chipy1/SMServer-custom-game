dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

SprayGroundState = class( BaseState )

local SprayInDuration = 1.0
local SprayLoopDuration = 10.0
local SprayOutDuration = 1.0

function SprayGroundState.sv_onCreate( self, unit )
	self.unit = unit
	self.lookDirection = sm.vec3.new( 0, 1, 0 )
	self.stageIndex = 1

	self.sprayGroundStartState = self.unit:createState( "wait" )
	self.sprayGroundStartState.debugName = "sprayGroundStartState"
	self.sprayGroundStartState.name = "sprayground_in"
	self.sprayGroundStartState.time = SprayInDuration
	self.sprayGroundStartState.interruptible = false

	self.sprayGroundLoopState = self.unit:createState( "wait" )
	self.sprayGroundLoopState.debugName = "sprayGroundLoopState"
	self.sprayGroundLoopState.name = "sprayground_loop"
	self.sprayGroundLoopState.time = SprayLoopDuration
	self.sprayGroundLoopState.interruptible = false

	self.sprayGroundFinishState = self.unit:createState( "wait" )
	self.sprayGroundFinishState.debugName = "sprayGroundFinishState"
	self.sprayGroundFinishState.name = "sprayground_out"
	self.sprayGroundFinishState.time = SprayOutDuration
	self.sprayGroundFinishState.interruptible = false

	self.currentState = self.sprayGroundStartState
end

function SprayGroundState.refresh( self ) end

function SprayGroundState.sv_setLookDirection( self, lookDirection )
end

function SprayGroundState.sv_setPosition( self, worldPosition ) end

function SprayGroundState.sv_setTarget( self, target )
	self.target = target
end

function SprayGroundState.sv_setStage( self, stageIndex )
	self.stageIndex = stageIndex
end

--[[API functions]]

function SprayGroundState.start( self )
	self.currentState:stop()
	self.currentState = self.sprayGroundStartState
	self.currentState:start()
	self.unit:sendCharacterEvent( "rotate" )
end

function SprayGroundState.stop( self )
	self.currentState:stop()
	self.unit:sendCharacterEvent( "sprayground_out" )
end

function SprayGroundState.onFixedUpdate( self, dt )
	self.currentState:onFixedUpdate( dt )
		local done, _ = self.currentState:isDone()
		if done then
			self.currentState:stop()
		if self.currentState.name == "sprayground_in" then
			self.currentState = self.sprayGroundLoopState
			self.currentState:start()
		elseif self.currentState.name == "sprayground_loop" then
			self.currentState = self.sprayGroundFinishState
			self.currentState:start()
		end
	end
end

function SprayGroundState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function SprayGroundState.isDone( self )
	if self.currentState == self.sprayGroundFinishState then
		local done, _ = self.currentState:isDone()
		if done then
			self.unit:sendCharacterEvent( "stopRotate" )
		end
		return done, "finished"
	elseif self.currentState == self.sprayGroundStartState or self.currentState == self.sprayGroundLoopState then
		return false, "sprayGround"
	end
	return true, "unknown state"
end

function SprayGroundState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function SprayGroundState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function SprayGroundState.getMovementType( self )
	return self.currentState:getMovementType()
end

function SprayGroundState.getWantsJump( self )
	return false
end

function SprayGroundState.setLoopDuration( self, loopDuration )
	self.sprayGroundLoopState.time = loopDuration
end