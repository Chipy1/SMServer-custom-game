dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

JumpMoveState = class( BaseState )

local PreJumpTimeout = 2.0
local FailTimeoutJump = 2.0
local FailTimeoutAir = 4.0
local RecoverTime = 0.8

-- State specific functions

function JumpMoveState.sv_onCreate( self, unit )
	self.unit = unit
	self.movementType = "sprint"
	self.movementDirection = self.unit:getCurrentMovementDirection()

	self.preJumpState = self.unit:createState( "wait" )
	self.preJumpState.debugName = "preJumpState"
	self.preJumpState.name = "preJump"
	self.preJumpState.time = PreJumpTimeout
	self.preJumpState.interruptible = false

	self.jumpState = self.unit:createState( "wait" )
	self.jumpState.debugName = "jumpState"
	self.jumpState.name = "jump"
	self.jumpState.time = FailTimeoutJump
	self.jumpState.interruptible = false

	self.airState = self.unit:createState( "wait" )
	self.airState.debugName = "airState"
	self.airState.time = FailTimeoutAir
	self.airState.interruptible = false

	self.recoverState = self.unit:createState( "wait" )
	self.recoverState.debugName = "recoverState"
	self.recoverState.name = "recover"
	self.recoverState.time = RecoverTime
	self.recoverState.interruptible = false

	self.currentState = self.preJumpState
end

function JumpMoveState.sv_setMovementType( self, movementType )
	self.movementType = movementType
end

function JumpMoveState.sv_setDirection( self, direction )
	self.movementDirection = direction
end

function JumpMoveState.sv_checkCeiling( self )
	local fromPosition = self.unit.character.worldPosition
	local margin = 0.25
	local radius = self.unit.character:getRadius()
	local heightOffset = self.unit.character:getHeight() * 0.5 - radius + margin
	local toPosition = fromPosition + sm.vec3.new( 0, 0, heightOffset )
	local filter = sm.physics.filter.terrainAsset + sm.physics.filter.voxelTerrain + sm.physics.filter.staticBody + sm.physics.filter.dynamicBody + sm.physics.filter.harvestable
	local success, _ = sm.physics.spherecast( fromPosition, toPosition, radius, self.unit.character, filter )
	return success
end

-- AiState common interface

function JumpMoveState.start( self )
	self.started = true
	self.jumpPosition = nil
	self.currentState:stop()
	self.currentState = self.preJumpState
	self.currentState:start()
end

function JumpMoveState.stop( self )
	self.started = false
	self.currentState:stop()
end

function JumpMoveState.onFixedUpdate( self, dt )
	local done, _ = self.currentState:isDone()
	self.currentState:onFixedUpdate( dt )

	if self.currentState == self.preJumpState then
		if self.unit.character:isOnGround() then
			-- Prepared to jump
			self.jumpPosition = self.unit.character.worldPosition
			self.currentState:stop()
			self.currentState = self.jumpState
			self.currentState:start()
		end
	elseif self.currentState == self.jumpState then
		if not self.unit.character:isOnGround() then
			-- Jumping
			self.currentState:stop()
			self.currentState = self.airState
			self.currentState:start()
		end
	elseif self.currentState == self.airState then
		if self.unit.character:isOnGround() then
			-- Landed
			self.currentState:stop()
			self.currentState = self.recoverState
			self.currentState:start()
		end
	elseif self.currentState == self.recoverState then
		if done and self.unit.character:isOnGround() then
			self.currentState:stop()
			self.currentState = self.preJumpState
			self.currentState:start()
		end
	end
end

function JumpMoveState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function JumpMoveState.isDone( self )
	local done, _ = self.currentState:isDone()

	if self.currentState == self.preJumpState then
		if done then
			return true, "noground"
		else
			return false, "preparing"
		end
	elseif self.currentState == self.jumpState then
		if done then
			return true, "jumpfailed"
		else
			return false, "jumping"
		end
	elseif self.currentState == self.airState then
		if done then
			return true, "landingfailed"
		else
			return false, "airtime"
		end
	elseif self.currentState == self.recoverState then
		if done then
			return true, "recovered"
		else
			return false, "recovering"
		end
	end

	return true, "unknown state"
end

function JumpMoveState.getMovementDirection( self )
	return self.movementDirection
end

function JumpMoveState.getFacingDirection( self )
	return self.movementDirection
end

function JumpMoveState.getMovementType( self )
	local jumpMovement = not self.unit.character:isOnGround() and isAnyOf( self.currentState, { self.jumpState, self.airState } )
	if jumpMovement then
		return self.movementType
	end
	return "stand"
end

function JumpMoveState.getWantsJump( self )
	return self.currentState == self.jumpState
end

function JumpMoveState.getWantsCrouch( self )
	return false
end