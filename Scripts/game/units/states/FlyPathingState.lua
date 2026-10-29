dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/FlyMoveState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/FlightPathfinding.lua" )

FlyPathingState = class( BaseState )




local MaxThinkTickTime = 40 * 4
local SelfMaxPosDiff = 10 -- Max allowed distance diff from the pathfinder's starting position before restarting
local TargetMaxPosDiff = 7.5 -- Max allowed distance diff from the pathfinder's target position before restarting
local SameNodeTimeoutTickTime = 3 * 40 -- Max allowed time to spend inside the same node before pathing is considered to have failed

-- State specific functions

function FlyPathingState.sv_onCreate( self, unit )
	self.unit = unit
	self.destination = self.unit.character.worldPosition
	self.pathNodeSize = 1

	self.thinkTimer = Timer()
	self.thinkTimer:start( MaxThinkTickTime )
	
	self.sameNodeTimer = Timer()
	self.sameNodeTimer:start( SameNodeTimeoutTickTime )

	-- Pathfinding
	self.activePathfinder = nil
	self.bestPath = nil

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Movement
	self.flyMoveState = FlyMoveState()
	self.flyMoveState:sv_onCreate( self.unit )
	self.flyMoveState:sv_setMovementType( "walk" )
	self.flyMoveState.debugName = "flyMoveState"

	self.currentState = self.idleState
end

function FlyPathingState.sv_onDestroy( self )





	if self.activePathfinder then
		self.activePathfinder:reset()
		self.activePathfinder = nil
	end
end

function FlyPathingState.sv_setMovementType( self, movementType )
	self.flyMoveState:sv_setMovementType( movementType )
end

function FlyPathingState.sv_setDestination( self, toPosition )
	self.destination = toPosition
end

function FlyPathingState.sv_setPathNodeSize( self, nodeSize )
	self.pathNodeSize = nodeSize
end

function FlyPathingState.sv_getSubDirection( self )
	if self.currentState == self.flyMoveState then
		return self.flyMoveState:getMovementDirection()
	end
	return nil
end

-- AiState common interface

function FlyPathingState.start( self )
	self.done = nil
	self.started = true
	self.nodeDestination = nil
	self.characterNodePosition = nil
	self.previousCharacterPosition = nil
end

function FlyPathingState.stop( self )
	self.started = false
	self.currentState:stop()
	if self.activePathfinder then
		self.activePathfinder:reset()
		self.activePathfinder = nil
	end
	self.sameNodeTimer:reset()
	self.thinkTimer:reset()




end


function FlyPathingState.onFixedUpdate( self, timeStep )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	if self.currentState then
		self.currentState:onFixedUpdate( timeStep )
	end

	-- Create initial pathfinder
	if self.activePathfinder == nil then
		self.activePathfinder = FlightPathfinding()
		self.activePathfinder:init( character.worldPosition, self.destination, self.pathNodeSize )
	end

	-- Check if the pathfinder needs to be recreated
	self.characterNodePosition = self.activePathfinder:getNodePosition( character.worldPosition )
	self.nodeDestination = self.activePathfinder:getNodePosition( self.destination )
	local startDistanceDiff = ( self.activePathfinder.startPosition - self.characterNodePosition ):length()
	local targetDistanceDiff = ( self.activePathfinder.targetPosition - self.nodeDestination ):length()
	if startDistanceDiff > SelfMaxPosDiff or targetDistanceDiff > TargetMaxPosDiff then
		self.activePathfinder:reset()
		self.activePathfinder = FlightPathfinding()
		self.activePathfinder:init( character.worldPosition, self.destination, self.pathNodeSize )
		self.thinkTimer:reset()
	end

	-- Update the pathfinder and select the path closest to the destination
	local blocked = false
	if not isAnyOf( self.done, { "arrived", "blocked", "timedout" } ) then
		self.activePathfinder:tick()
	end
	local path, result = self.activePathfinder:result()
	if result == "finished" then
		-- Finished, restart
		self.activePathfinder:reset()
		self.activePathfinder = FlightPathfinding()
		self.activePathfinder:init( character.worldPosition, self.destination, self.pathNodeSize )
		self.thinkTimer:reset()
	end
	blocked = result == "blocked"
	if #path >= 2 then
		if self.bestPath == nil then
			self.bestPath = path
		else
			if self.nodeDestination then
				local bestDistance2 = ( self.bestPath[#self.bestPath] - self.nodeDestination ):length2()
				local currentDistance2 = ( path[#path] - self.nodeDestination ):length2()
				if currentDistance2 < bestDistance2 then
					self.bestPath = path
				end
			end
		end
	end

	-- Find subdestination to get the current direction
	local subDestination = self.nodeDestination
	if self.bestPath and #self.bestPath >= 2 then
		local movementSpeed = self.unit.character:getCurrentMovementSpeed()
		local stepLength = movementSpeed * timeStep * 5
		local totalLength, _ = lengthOfLines( self.bestPath )
		local fraction = closestFractionInLines( self.bestPath, self.unit.character.worldPosition )
		local nextFraction = totalLength >= FLT_EPSILON and clamp( fraction + ( stepLength / totalLength ), 0.0, 1.0 ) or 1.0
		subDestination = pointInLines( self.bestPath, nextFraction )
	end
	local subDirection = ( subDestination - character.worldPosition ):safeNormalize( self.unit:getCurrentMovementDirection( ))
	self.flyMoveState:sv_setDirection( subDirection )

	-- Check if character is stuck in the same node
	if self.previousCharacterPosition then
		if self.activePathfinder:inSameNode( self.characterNodePosition, self.previousCharacterPosition ) then
			self.sameNodeTimer:tick()
		else
			self.sameNodeTimer:reset()
		end
	else
		self.sameNodeTimer:reset()
	end
	self.previousCharacterPosition = self.characterNodePosition
	local stuckInSameNode = self.sameNodeTimer:done()

	-- Check if done
	if self.activePathfinder:inSameNode( self.characterNodePosition, self.nodeDestination ) then
		self.done = "arrived"
	elseif blocked or stuckInSameNode then
		if stuckInSameNode or self.bestPath == nil or self.activePathfinder:inSameNode( self.characterNodePosition, self.bestPath[#self.bestPath] ) then
			-- Blocked, nowhere to go
			self.done = "blocked"
		else
			-- Blocked, but can get closer
			self.done = "blockedpathing"
		end
	elseif self.bestPath and #self.bestPath >= 2 then
		if self.activePathfinder:inSameNode( self.characterNodePosition, self.bestPath[#self.bestPath] ) then
			-- Thinking, has reached the end of a partial path
			self.done = "thinking"
		else
			self.done = "pathing"
		end
	else
		self.done = nil
	end

	-- Timeout while no progress can be made
	if self.done == "thinking" then
		self.thinkTimer:tick()
		if self.thinkTimer:done() then
			self.done = "timedout"
		end
	elseif not self.done == "timedout" then
		self.thinkTimer:reset()
	end

	-- Select state
	local nextState = self.currentState
	if isAnyOf( self.done, { "pathing", "blockedpathing" } ) then
		nextState = self.flyMoveState
	else
		nextState = self.idleState
	end
	if self.currentState ~= nextState then
		self.currentState:stop()
		self.currentState = nextState
		self.currentState:start()
	end

























end

function FlyPathingState.onUnitUpdate( self, dt )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end
end

function FlyPathingState.isDone( self )
	return isAnyOf( self.done, { "arrived", "blocked", "timedout" } ), self.done
end

function FlyPathingState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function FlyPathingState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function FlyPathingState.getMovementType( self )
	if self.done == "thinking" then
		return "stand"
	end
	return self.currentState:getMovementType()
end

function FlyPathingState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function FlyPathingState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end