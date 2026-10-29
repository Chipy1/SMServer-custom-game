dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/JumpMoveState.lua" )

JumpStompState = class( BaseState )

local MinimumJumpHeight = 2.0
local StompImpulseMagnitude = 25
local MaxStompAngle = 20.0

local PreJumpTimeout = 2.0
local FailTimeoutJump = 2.0
local FailTimeoutStomp = 4.0
local RecoverTime = 0.8

local StompsUntilDisoriented = 2
local DisorientedTime = 5.2

local SmashUuid = sm.uuid.new( "eeeaa198-6b28-11ed-a1eb-0242ac120002" )

local VoxelDigRadius = 2.0
local VoxelDigStrength = 1.0

function JumpStompState.sv_onCreate( self, unit )
	self.unit = unit

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

	self.stompState = self.unit:createState( "wait" )
	self.stompState.debugName = "stompState"
	self.stompState.name = "stomp"
	self.stompState.time = FailTimeoutStomp
	self.stompState.interruptible = false
	self.stompsPerformed = 0

	self.recoverState = self.unit:createState( "wait" )
	self.recoverState.debugName = "recoverState"
	self.recoverState.name = "recover"
	self.recoverState.time = RecoverTime
	self.recoverState.interruptible = false

	self.disorientedState = self.unit:createState( "wait" )
	self.disorientedState.debugName = "disorientedState"
	self.disorientedState.name = "disoriented"
	self.disorientedState.time = DisorientedTime
	self.disorientedState.interruptible = false

	self.currentState = self.stompState
end

function JumpStompState.sv_setTarget( self, target )
	self.target = target
	if sm.exists( self.target ) then
		local radiusOffset = 0.0
		if type( self.target ) == "Character" then
			radiusOffset = self.target:getRadius()
		end
		radiusOffset = radiusOffset + self.unit.character:getRadius()

		local toDestination = ( self.target.worldPosition - self.unit.character.worldPosition )
		local toDestinationFlat = sm.vec3.new( toDestination.x, toDestination.y, 0 )
		local distance = toDestinationFlat:length()
		local adjustedDistance = math.max( distance - radiusOffset, 0 )
		-- Aim beside the target without moving backwards
		self.destination = self.unit.character.worldPosition + toDestination:safeNormalize( sm.vec3.zero() ) * adjustedDistance
	end
end

function JumpStompState.sv_setDestination( self, toPosition )
	self.destination = toPosition
end

--[[API functions]]

function JumpStompState.start( self )
	self.jumpPosition = nil
	self.currentState:stop()
	self.currentState = self.preJumpState
	self.currentState:start()
end

function JumpStompState.stop( self )
	self.currentState:stop()
end

function JumpStompState.sv_startStomp( self )
	self.jumpPosition = self.unit.character.worldPosition
	self.currentState:stop()
	self.currentState = self.stompState
	self.currentState:start()

	-- Stomp impulse
	if not self.unit.character:isOnGround() then
		local impulse = sm.vec3.new( 0, 0, -1 ) * self.unit.character.mass * StompImpulseMagnitude
		sm.physics.applyImpulse( self.unit.character, impulse, true )
	end
end

function JumpStompState.onFixedUpdate( self, dt )
	local done, _ = self.currentState:isDone()
	if done then return	end
	self.currentState:onFixedUpdate( dt )

	if sm.exists( self.target ) then
		local radiusOffset = 0.0
		if type( self.target ) == "Character" then
			radiusOffset = self.target:getRadius()
		end
		radiusOffset = radiusOffset + self.unit.character:getRadius()

		local toDestination = ( self.target.worldPosition - self.unit.character.worldPosition )
		local toDestinationFlat = sm.vec3.new( toDestination.x, toDestination.y, 0 )
		local distance = toDestinationFlat:length()
		local adjustedDistance = math.max( distance - radiusOffset, 0 )
		-- Aim beside the target without moving backwards
		self.destination = self.unit.character.worldPosition + toDestination:safeNormalize( sm.vec3.zero() ) * adjustedDistance
	end

	if self.currentState == self.preJumpState then
		if self.unit.character:isOnGround() then
			local currentTick = sm.game.getCurrentTick()
			self.startedTick = self.startedTick or currentTick
			local readyToStart = currentTick >= self.startedTick + RecoverTime * 40
			if readyToStart then
				self.startedTick = nil
				self.jumpPosition = self.unit.character.worldPosition
				self.currentState:stop()
				self.currentState = self.jumpState
				self.currentState:start()
			end
		end
	elseif self.currentState == self.jumpState then
		if not self.unit.character:isOnGround() then
			if self.unit.character.velocity.z <= 0 then
				local jumpHeight = self.jumpPosition and math.abs( self.jumpPosition.z - self.unit.character.worldPosition.z ) or 0
				if jumpHeight >= MinimumJumpHeight then
					-- Stomp impulse
					local down = sm.vec3.new( 0, 0, -1 )
					local stompDirection = self.destination and ( self.destination - self.unit.character.worldPosition ):safeNormalize( down ) or down
					local stompDirectionXY = sm.vec3.new( stompDirection.x, stompDirection.y, 0 ):safeNormalize( sm.vec3.new( 0, 1, 0 ) )
					local right = stompDirectionXY:cross( -down )
					local stompAngle = clamp( math.deg( math.acos( down:dot( stompDirection ) ) ), 0, MaxStompAngle )
					local impulseDirection = down:rotate( math.rad( stompAngle ), right )

					local impulse = impulseDirection * self.unit.character.mass * StompImpulseMagnitude
					sm.physics.applyImpulse( self.unit.character, impulse, true )
					self.currentState:stop()
					self.currentState = self.stompState
					self.currentState:start()
				end
			end
		end
	elseif self.currentState == self.stompState then
		if self.unit.character:isOnGround() then
			-- Stomp landing
			local heightOffset = sm.vec3.new( 0, 0, -self.unit.character:getHeight() * 0.5 )
			local feetPosition = self.unit.character.worldPosition + heightOffset
			local params = { position = feetPosition, smasher = self.unit, normal = sm.vec3.new( 0, 0, 1 ) }
			sm.scriptableObject.createScriptableObject( SmashUuid, params, self.unit.character:getWorld() )
			self.stompsPerformed = self.stompsPerformed + 1

			self.unit.character:getWorld():sphereVoxelDensitySubtraction( feetPosition, VoxelDigRadius, sm.world.voxelFilter.material0, VoxelDigStrength )

			self.currentState:stop()
			if self.stompsPerformed >= StompsUntilDisoriented then
				self.stompsPerformed = 0
				self.currentState = self.disorientedState
			else
				self.currentState = self.recoverState
			end
			self.currentState:start()
		end
	elseif self.currentState == self.recoverState then
		local done, _ = self.currentState:isDone()
		if done then
			self.currentState:stop()
			self.currentState = self.preJumpState
			self.currentState:start()
		end
	end
end

function JumpStompState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function JumpStompState.isDone( self )
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
	elseif self.currentState == self.stompState then
		if done then
			return true, "stompfailed"
		else
			return false, "stomping"
		end
	elseif self.currentState == self.recoverState then
		if done then
			return true, "recovered"
		else
			return false, "recovering"
		end
	elseif self.currentState == self.disorientedState then
		if done then
			return true, "disorientedStateDone"
		else
			return false, "disoriented"
		end
	end

	return true, "unknown state"
end

function JumpStompState.getMovementDirection( self )
	if self.destination then
		return ( self.destination - self.unit.character.worldPosition ):safeNormalize( self.currentState:getMovementDirection() )
	end
	return self.currentState:getMovementDirection()
end

function JumpStompState.getFacingDirection( self )
	if self.destination then
		return ( self.destination - self.unit.character.worldPosition ):safeNormalize( self.currentState:getFacingDirection() )
	end
	return self.currentState:getFacingDirection()
end

function JumpStompState.getMovementType( self )
	local isJumping = self.currentState == self.jumpState or ( self.currentState == self.stompState and not self.unit.character:isOnGround() )
	if isJumping then
		if self.destination then
			local fromTo = self.destination - self.unit.character.worldPosition
			local distanceXY = sm.vec3.new( fromTo.x, fromTo.y, 0 ):length()
			if distanceXY <= self.unit.character:getRadius() then
				return "stand"
			else
				if distanceXY < 2 then
					return "walk"
				else
					return "sprint"
				end
			end
		end
	end
	return self.currentState:getMovementType()
end

function JumpStompState.getWantsJump( self )
	return self.currentState == self.jumpState
end