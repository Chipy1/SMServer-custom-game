dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/PatrolManager.lua" )

PatrolState = class( BaseState )

local AnchorSprintDistance2 = 8 * 8
local AnchorZoneDistance2 = 3 * 3

function PatrolState.sv_onCreate( self, unit, patrolKey, customPathingState )
	self.unit = unit
	self.patrolKey = patrolKey

	self.destination = self.unit.character.worldPosition
	self.leaderTolerance = math.max( self.unit.character:getHeight(), self.unit.character:getRadius() )
	self.followerTolerance = self.unit.character:getRadius()

	-- Pathing
	if customPathingState then
		self.pathingState = customPathingState
	else
		self.pathingState = PathingState()
	end
	self.pathingState:sv_onCreate( self.unit )
	self.pathingState:sv_setWaterAvoidance( false )
	self.pathingState.debugName = "pathingState"
	self.movementType = "stand"
	self.facing = self.unit.character.direction
	self.catchUpSprint = false
	self.status = "idle"
end

--[[API functions]]
function PatrolState.start( self )
	self.pathingState:sv_setDestination( self.destination )
	self.pathingState:start()
end

function PatrolState.stop( self )
	self.pathingState:stop()
end

function PatrolState.onFixedUpdate( self, dt )
	self.pathingState:onFixedUpdate( dt )

	if self.catchUpSprint then
		local distance2 = ( self.destination - self.unit.character.worldPosition ):length2()
		self.catchUpSprint = distance2 <= AnchorZoneDistance2
	end
end

function PatrolState.handleMovement( self, dt )

	local done, result = self.pathingState:isDone()
	if result == "failed" then
		-- Restart if pathing fails
		self.pathingState:stop()
		self.destination = self.unit.character.worldPosition
		self.pathingState:sv_setDestination( self.destination )
		self.pathingState:start()
		self.status = "failed"
		return
	end

	self.destination = self.unit.character.worldPosition
	local canPatrol
	local patrolLeader
	local patrolDestination
	local patrolAnchor
	if self.patrolKey then
		canPatrol = PatrolManager.Sv_IsPatrolActive( self.patrolKey )
		patrolLeader = PatrolManager.Sv_GetPatrolLeader( self.patrolKey )
		patrolDestination = PatrolManager.Sv_GetPatrolDestination( self.patrolKey )
		patrolAnchor = PatrolManager.Sv_GetPatrolAnchor( self.patrolKey )
	end
	if canPatrol and patrolLeader and patrolDestination and patrolAnchor then
		local isLeader = self.unit == patrolLeader
		self.pathingState:sv_setTolerance( isLeader and self.leaderTolerance or self.followerTolerance  )
		if PatrolManager.Sv_IsPatrolLocked( self.patrolKey, self.unit.character:getWorld(), self.unit.character.worldPosition ) then
			self.status = "locked"
			self.movementType = "stand"
		else
			-- Patrol movement
			self.status = isLeader and "leader" or "follower"

			local selfAnchor = patrolAnchor
			local selfDestination = patrolDestination
			if not isLeader then
				-- offset anchor
				local offsetFromLeader = PatrolManager.Sv_GetFollowerOffset( self.unit )
				if offsetFromLeader then
					selfAnchor = patrolAnchor + offsetFromLeader
					selfDestination = patrolDestination + offsetFromLeader
				end
			end
			-- face towards destination
			self.facing = ( selfDestination - self.unit.character.worldPosition ):safeNormalize( self.facing )

			local selfDistanceToAnchor2 = ( selfAnchor - self.unit.character.worldPosition ):length2()
			local selfDistanceToDestination2 = ( selfDestination - self.unit.character.worldPosition ):length2()
			local anchorDistanceToDestination2 = ( selfDestination - selfAnchor ):length2()

			if selfDistanceToAnchor2 <= AnchorZoneDistance2 then
				-- Within anchor zone
				if anchorDistanceToDestination2 < selfDistanceToDestination2 then
					-- Anchor is closer to destination, move towards destination
					self.destination = selfDestination
					self.movementType = "walk"
				else
					-- Character is closer to destination, wait for anchor to catch up or pass
					self.destination = selfDestination
					self.movementType = "stand"
				end
				self.catchUpSprint = false
			else
				-- Outside anchor zone
				if anchorDistanceToDestination2 < selfDistanceToDestination2 then
					-- Anchor is closer to destination, move towards anchor
					self.destination = selfAnchor
					if selfDistanceToAnchor2 >= AnchorSprintDistance2 or self.catchUpSprint then
						-- Far away from anchor, sprint to catch up
						self.movementType = "sprint"
						self.catchUpSprint = true
					else
						self.movementType = "walk"
					end
				else
					-- Character is closer to destination, wait for anchor to catch up or pass
					self.destination = selfDestination
					self.movementType = "stand"
					self.catchUpSprint = false
				end
			end
		end
	else
		self.status = "idle"
		self.movementType = "stand"
	end
	self.pathingState:sv_setDestination( self.destination )
end

function PatrolState.onUnitUpdate( self, dt )
	self.pathingState:onUnitUpdate( dt )
	self:handleMovement( dt )
end

function PatrolState.isDone( self )
	return true, self.status
end

function PatrolState.getMovementDirection( self )
	return self.pathingState:getMovementDirection()
end

function PatrolState.getFacingDirection( self )
	return self.facing
end

function PatrolState.getMovementType( self )
	return self.movementType
end

function PatrolState.getWantsJump( self )
	return self.pathingState:getWantsJump()
end

function PatrolState.getWantsCrouch( self )
	return self.pathingState:getWantsCrouch()
end