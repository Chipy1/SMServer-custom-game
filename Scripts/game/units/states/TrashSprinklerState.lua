dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

TrashSprinklerState = class( BaseState )

local SprayUuid = sm.uuid.new( "03ee5415-10e4-432a-be06-183c53a17d33" )
local RotationRads = 90 * math.pi / 180

local SprinklerInDuration = 1
local DefaultSprinklerLoopDuration = 40
local SprinklerOutDuration = 1

function TrashSprinklerState.sv_onCreate( self, unit, isRightSide )
	self.unit = unit
	self.lookDirection = sm.vec3.new( 0, 1, 0 )
	self.worldPosition = sm.vec3.zero()
	self.stageIndex = 1
	self.isRightSide = isRightSide
	self.clockwise = true

	self.sprinklerInState = self.unit:createState( "wait" )
	self.sprinklerInState.debugName = "sprinklerInState"
	self.sprinklerInState.name = self.isRightSide and "sprinkler_right_in" or "sprinkler_left_in"
	self.sprinklerInState.time = SprinklerInDuration
	self.sprinklerInState.interruptible = false

	self.sprinklerLoopState = self.unit:createState( "wait" )
	self.sprinklerLoopState.debugName = "sprinklerLoopState"
	self.sprinklerLoopState.name = self.isRightSide and "sprinkler_right_loop" or "sprinkler_left_loop"
	self.sprinklerLoopState.time = DefaultSprinklerLoopDuration
	self.sprinklerLoopState.interruptible = false

	self.sprinklerOutState = self.unit:createState( "wait" )
	self.sprinklerOutState.debugName = "sprinklerOutState"
	self.sprinklerOutState.name = self.isRightSide and "sprinkler_right_out" or "sprinkler_left_out"
	self.sprinklerOutState.time = SprinklerOutDuration
	self.sprinklerOutState.interruptible = false

	self.currentState = self.sprinklerInState

	self.scriptable = nil
	self.aborted = false

	self.spawn = false
end

function TrashSprinklerState.refresh( self ) end

function TrashSprinklerState.sv_setLookDirection( self, lookDirection )
	self.lookDirection = lookDirection
end

function TrashSprinklerState.sv_setPosition( self, worldPosition )
	self.worldPosition = worldPosition
end

function TrashSprinklerState.sv_setTarget( self, target )
	self.target = target
end

function TrashSprinklerState.sv_setStage( self, stageIndex )
	self.stageIndex = stageIndex
end

function TrashSprinklerState.sv_updateTrashSpray( self )
	if self.spawn then
		self.spawn = false

		-- Spawn trash spray
		local spawnPos = self.unit.character:getTpBonePos( "root_jnt" )
		if not spawnPos then
			local heightOffset = sm.vec3.new( 0, 0, -1.25 )
			spawnPos = self.unit.character.worldPosition + heightOffset
		end
		local newDirection = self.lookDirection
		if self.isRightSide then
			newDirection = newDirection:rotateZ( RotationRads )
		else
			newDirection = newDirection:rotateZ( -RotationRads )
		end

		local params = { position = spawnPos, direction = newDirection, firePosition = self.worldPosition, clockwise = self.clockwise, duration = math.floor( self.sprinklerLoopState.time * 40 ), isRightSide = self.isRightSide }
		self.scriptable = sm.scriptableObject.createScriptableObject( SprayUuid, params, self.unit.character:getWorld() )
	end
end

--[[API functions]]

function TrashSprinklerState.start( self )
	self.currentState:stop()
    self.currentState = self.sprinklerInState
    self.currentState:start()
	self.spawn = false
end

function TrashSprinklerState.stop( self )
	if self.currentState then
        self.currentState:stop()
    end
end

function TrashSprinklerState.onFixedUpdate( self, dt )
	self.target = sm.exists( self.target ) and self.target or nil
	self.currentState:onFixedUpdate( dt )
		local done, _ = self.currentState:isDone()
		if done then
			self.currentState:stop()
			if self.currentState.debugName == "sprinklerInState" then
				self.currentState = self.sprinklerLoopState
				self.currentState:start()
				self.spawn = true
			elseif self.currentState.debugName == "sprinklerLoopState" then
				self.currentState = self.sprinklerOutState
				self.currentState:start()
				self.sprinklerLoopState.time = DefaultSprinklerLoopDuration
			end
		end
	self:sv_updateTrashSpray()
end

function TrashSprinklerState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function TrashSprinklerState.isDone( self )
	if self.currentState == self.sprinklerOutState then
		return self.currentState:isDone()
	elseif self.currentState == self.sprinklerInState or self.currentState == self.sprinklerLoopState then
		return false, "sprinklerActive"
	end
	return true, "unknown state"

end

function TrashSprinklerState.getWantsJump( self )
	return false
end

function TrashSprinklerState.setLoopDuration( self, loopDuration )
	self.sprinklerLoopState.time = loopDuration
end

function TrashSprinklerState.setClockwise( self, clockwise )
	self.clockwise = clockwise
end

function TrashSprinklerState.abort( self )
	if self.scriptable ~= nil and self.aborted == false then
		self.aborted = true
		sm.event.sendToScriptableObject( self.scriptable, "sv_e_abort" )
		self.currentState:stop()
		self.currentState = self.sprinklerOutState
		self.currentState:start()
	end
end