dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/SwimMoveState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/DrillAttack.lua" )

TorpedoAttackState = class( BaseState )

local MaxSwimTickTime = 40 * 10 -- Abort swimming if stuck
local TorpedoCommitDistance2 = 4 * 4 -- Lock onto the last target position when this close, giving the player a chance to dodge
local FinishedMinDelay = 0.9
local FinishedMaxDelay = 1.4

local FleeDepth = -8
local FleeRandomOffsetMin = 1
local FleeRandomOffsetMax = 3

function TorpedoAttackState.sv_onCreate( self, unit )
	self.unit = unit
	self.target = nil
	self.targetPosition = nil

	self.abortTimer = Timer()
	self.abortTimer:start( MaxSwimTickTime )

	-- Damages shapes and characters in front while torpedoing.
	self.drillAttack = DrillAttack()
	self.drillAttack:sv_onCreate( unit )

	-- Initial
	self.initialState = self.unit:createState( "wait" )
	self.initialState.debugName = "initialState"
	self.initialState.time = 1.0
	self.initialState.interruptible = false

	-- Movement
	self.torpedoState = SwimMoveState()
	self.torpedoState:sv_onCreate( unit )
	self.torpedoState.debugName = "torpedoState"
	self.torpedoState:sv_setMovementType( "sprint" )

	-- Recover
	self.recoverState = self.unit:createState( "wait" )
	self.recoverState.debugName = "recoverState"
	self.recoverState.time = 0.5
	self.recoverState.interruptible = false

	-- Movement
	self.moveAwayState = SwimMoveState()
	self.moveAwayState:sv_onCreate( unit )
	self.moveAwayState.debugName = "moveAwayState"
	self.moveAwayState:sv_setMovementType( "walk" )

	-- Finished
	self.finishedState = self.unit:createState( "wait" )
	self.finishedState.debugName = "finishedState"
	self.finishedState.time = math.random() * ( FinishedMaxDelay - FinishedMinDelay ) + FinishedMinDelay
	self.finishedState.interruptible = false

	self.currentState = self.initialState
end

function TorpedoAttackState.sv_setTarget( self, target )
	self.target = target
	if sm.exists( self.target ) then
		self.targetPosition = self.target.worldPosition
	end
end

function TorpedoAttackState.sv_setTargetPosition( self, targetPosition )
	self.target = nil
	self.targetPosition = targetPosition
end

function TorpedoAttackState.sv_updateMoveAwayPosition( self )
	local offset = sm.vec3.new( 0, math.random( FleeRandomOffsetMin, FleeRandomOffsetMax ), FleeDepth ):rotateZ( math.rad( math.random() * 360 ) )
	local from = self.unit.character.worldPosition
	local to = self.unit.character.worldPosition + offset
	local hit, result = sm.physics.spherecast( from, to, self.unit.character:getRadius(), self.unit.character )
	if hit then
		local destination = result.pointWorld - result.directionWorld:safeNormalize( sm.vec3.zero() ) * self.unit.character:getRadius()
		self.moveAwayState:sv_setDestination( destination )
	else
		self.moveAwayState:sv_setDestination( to )
	end
end

--[[API functions]]

function TorpedoAttackState.start( self )
	self.currentState:stop()
	self.currentState = self.initialState
	self.currentState:start()
	self.abortTimer:reset()
	self.committed = false
end

function TorpedoAttackState.stop( self )
	self.drillAttack:sv_setActive( false )
	self.currentState:stop()
end

function TorpedoAttackState.onFixedUpdate( self, dt )
	self.currentState:onFixedUpdate( dt )

	if sm.exists( self.target ) then
		self.targetPosition = self.target.worldPosition
	end
	if self.targetPosition and not self.committed then
		self.torpedoState:sv_setDestination( self.targetPosition )
	elseif self.committed and self.currentState ~= self.torpedoState then
		self.committed = false
	end

	self.drillAttack:sv_setActive( self.currentState == self.torpedoState )
	self.drillAttack:sv_onFixedUpdate( dt )

	local prevState = self.currentState
	if self.unit.character:isSwimming() and not self.unit.character:isTumbling() and self.targetPosition then
		local done, result = self.currentState:isDone()
		if self.currentState == self.initialState then
			if done then
				self.abortTimer:reset()
				self.currentState = self.torpedoState
			end
		elseif self.currentState == self.torpedoState then
			self.abortTimer:tick()
			self.committed = self.committed or ( self.targetPosition - self.unit.character.worldPosition ):length2() <= TorpedoCommitDistance2
			if done then
				self.currentState = self.recoverState
			elseif self.abortTimer:done() then
				self.currentState = self.finishedState
			end
		elseif self.currentState == self.recoverState then
			if done then
				self.abortTimer:reset()
				self:sv_updateMoveAwayPosition()
				self.currentState = self.moveAwayState
			end
		elseif self.currentState == self.moveAwayState then
			self.abortTimer:tick()
			if done or self.abortTimer:done() then
				self.currentState = self.finishedState
			end
		elseif self.currentState == self.finishedState then
			if done then
				self.currentState = self.initialState
			end
		end
	else
		-- End the attack when tumbling
		self.currentState = self.finishedState
	end

	if self.currentState ~= prevState then
		prevState:stop()
		self.currentState:start()
	end
end

function TorpedoAttackState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function TorpedoAttackState.isDone( self )
	if self.currentState == self.finishedState then
		return true, ""
	end
	return false, ""
end

function TorpedoAttackState.getMovementDirection( self )
	local stateMovementDirection = self.currentState:getMovementDirection()
	if isAnyOf( self.currentState, { self.initialState, self.recoverState, self.finishedState } ) then
		if self.targetPosition then
			return ( self.targetPosition - self.unit.character.worldPosition ):safeNormalize( stateMovementDirection )
		end
	end
	return stateMovementDirection
end

function TorpedoAttackState.getFacingDirection( self )
	local stateFacingDirection = self.currentState:getFacingDirection()
	if isAnyOf( self.currentState, { self.initialState, self.recoverState, self.finishedState } ) then
		if self.targetPosition then
			return ( self.targetPosition - self.unit.character.worldPosition ):safeNormalize( stateFacingDirection )
		end
	end
	return stateFacingDirection
end

function TorpedoAttackState.getMovementType( self )
	return self.currentState:getMovementType()
end

function TorpedoAttackState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function TorpedoAttackState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end