dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/BabyWocManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/EffectManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )

BabyWocFollowerState = class( BaseState )

local WantTeleportDistance2 = 16 * 16 -- When this far away from the player, count up the timer toteleport to them instead of pathing
local TeleportArriveDistance = 5 -- When teleporting, try to get this close to the player
local WantTeleportTime = 1.0 * 40

local SprintDistance2 = 10 * 10
local StopSprintDistance2 = 5 * 5
local DesiredFollowDistance = 3.0 -- Distance from the player to arrive at
local StartFollowDistance2 = 4.0 * 4.0 -- Distance to start following
local PathingTolerance = 0.5 -- Excluding the character's radius

-- Detect if stuck within this radius for the specified amount of time
local StuckDistance = 0.5
local UnstuckTime = 10.0 * 40

function BabyWocFollowerState.sv_onCreate( self, unit, customPathingState )
	self.unit = unit

	self.catchingUp = false
	self.sprinting = false

	self.wantTeleportTimer = Timer()
	self.wantTeleportTimer:start( WantTeleportTime )

	self.stuckTimer = Timer()
	self.stuckTimer:start( UnstuckTime )
	self.stuckCenterPosition = nil

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"
	self.idleState.randomEventCooldownMin = 6.0
	self.idleState.randomEventCooldownMax = 20.0
	self.idleState.randomEvents = { { name = "cow_eat_grass", time = 4.0, interruptible = false, chance = 0.03},
                                    { name = "idlespecial01", time = 4.0, interruptible = false, chance = 0.3 },
									{ name = "idlespecial02", time = 3.0, interruptible = false, chance = 0.3 },
                                    { name = "moo", chance = 0.4 } }

	-- Pathing
	if customPathingState then
		self.pathingState = customPathingState
	else
		self.pathingState = PathingState()
	end
	self.pathingState:sv_onCreate( self.unit )
	self.pathingState:sv_setTolerance( self.unit.character:getRadius() + PathingTolerance )
	self.pathingState:sv_setMovementType( "walk" )
	self.pathingState:sv_setWaterAvoidance( false )
	self.pathingState:sv_setCliffAvoidance( true )
	self.pathingState.debugName = "pathingState"

	self.currentState = self.idleState
	self.currentState:start()
end

--[[API functions]]
function BabyWocFollowerState.start( self )
	self.currentState:stop()
	self.currentState = self.idleState
	self.currentState:start()

	self.sprinting = false
end

function BabyWocFollowerState.stop( self )
	self.currentState:stop()
end

function BabyWocFollowerState.onFixedUpdate( self, dt )
	self.currentState:onFixedUpdate( dt )

	if self.currentState == self.pathingState then
		self.stuckCenterPosition = self.stuckCenterPosition or self.unit.character.worldPosition
		local distanceToStuckposition2 = ( self.stuckCenterPosition - self.unit.character.worldPosition ):length2()
		if distanceToStuckposition2 > StuckDistance * StuckDistance then
			self.stuckTimer:reset()
			self.stuckCenterPosition = nil
		else
			self.stuckTimer:tick()
		end

		local playerToFollow = BabyWocManager.Sv_GetPlayerToFollow()
		if playerToFollow then
			local characterToFollow = sm.exists( playerToFollow.character ) and playerToFollow.character or nil
			if characterToFollow then
				local distanceToPlayer2 = sm.vec3.getDistanceSquared( self.unit.character.worldPosition, characterToFollow.worldPosition )
				if distanceToPlayer2 < WantTeleportDistance2 then
					self.wantTeleportTimer:reset()
				else
					self.wantTeleportTimer:tick()
					if self.wantTeleportTimer:done() then
						if self:tryToTeleport() then
							self.wantTeleportTimer:reset()
						end
					end
				end
			end
		end
	else
		self.stuckTimer:reset()
		self.wantTeleportTimer:reset()
	end
end

function BabyWocFollowerState.tryToTeleport( self )
	-- Teleport to player if far away for too long
	-- Try to place the baby woc between the player and itself at TeleportArriveDistance,
	-- but only if the player can't see the teleport position

	local playerToFollow = BabyWocManager.Sv_GetPlayerToFollow()
	if not playerToFollow then
		return false
	end

	local characterToFollow = sm.exists( playerToFollow.character ) and playerToFollow.character or nil
	if not characterToFollow then
		return false
	end

	-- Calculate direction from player to baby woc
	local playerPos = characterToFollow.worldPosition
	local babyPos = self.unit.character.worldPosition
	local direction = ( babyPos - playerPos ):safeNormalize( sm.vec3.zero() )

	if direction == sm.vec3.zero() then
		return false
	end

	local finalTeleportPos

	-- Calculate teleport position at TeleportArriveDistance
	local teleportPos = playerPos + direction * TeleportArriveDistance

	-- Check if player is facing away from the teleport position
	local playerDirection = characterToFollow.direction
	local directionToTeleport = ( teleportPos - playerPos ):safeNormalize( sm.vec3.zero() )
	local dotProduct = playerDirection:dot( directionToTeleport )

	-- If dot product is negative or zero, player is facing away
	if dotProduct <= 0 then
		-- Player is facing away, safe to teleport
		finalTeleportPos = teleportPos
	end

	-- Check if player can see the teleport position using a raycast
	-- Cast from player's eye position to the teleport position
	local playerEyePos = playerPos + sm.vec3.new( 0, 0, characterToFollow:getHeight() * 0.75 )
	local teleportCheckPos = teleportPos + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 )

	local success, _ = sm.physics.raycast( playerEyePos, teleportCheckPos, characterToFollow )

	-- If raycast hits something, the player can't see the position, safe to teleport
	if success then
		finalTeleportPos = teleportPos
	end

	if finalTeleportPos then
		-- Find the ground at the teleport position
		local worldUp = sm.vec3.new( 0, 0, 1 )
		local verticalCheckOffsetUp = 2
		local verticalCheckOffsetDown = 100

		local groundSuccess, groundResult = sm.physics.spherecast(
			finalTeleportPos + worldUp * verticalCheckOffsetUp,
			finalTeleportPos - worldUp * verticalCheckOffsetDown,
			0.125,
			nil,
			nil,
			characterToFollow:getWorld()
		)

		local allowedGroundTypes = { "terrainSurface",
									"terrainAsset",
									"body",
									"voxelTerrain",
									"lift" }

		if groundSuccess and isAnyOf( groundResult.type, allowedGroundTypes ) then
			finalTeleportPos = groundResult.pointWorld
		else
			-- No valid ground found, don't teleport
			return false
		end

		self.unit.character:setWorldPosition( finalTeleportPos )
		self.currentState:stop()
		self.currentState = self.idleState
		self.currentState:start()
		self.catchingUp = false
		return true
	end

	return false
end

function BabyWocFollowerState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )

	local followerDestination = nil

	local playerToFollow = BabyWocManager.Sv_GetPlayerToFollow()
	if playerToFollow then
		-- Player follower
		local characterToFollow = sm.exists( playerToFollow.character ) and playerToFollow.character or nil
		if characterToFollow then
			local distance2 = sm.vec3.getDistanceSquared( self.unit.character.worldPosition, characterToFollow.worldPosition )
			if distance2 >= StartFollowDistance2 then
				self.catchingUp = true
			elseif distance2 <= DesiredFollowDistance * DesiredFollowDistance then
				self.catchingUp = false
			end
			if distance2 >= SprintDistance2 then
				self.sprinting = true
			elseif distance2 <= StopSprintDistance2 then
				self.sprinting = false
			end

			if self.catchingUp then
				local direction = ( characterToFollow.worldPosition - self.unit.character.worldPosition ):safeNormalize( sm.vec3.zero() )
				followerDestination = characterToFollow.worldPosition - direction * ( DesiredFollowDistance - PathingTolerance )
			end
		else
			self.catchingUp = false
			self.sprinting = false
		end
	end

	-- Update destination
	if followerDestination then
		self.pathingState:sv_setDestination( followerDestination )
	end

	if self.sprinting then
		self.pathingState:sv_setMovementType( "sprint" )
	else
		self.pathingState:sv_setMovementType( "walk" )
	end

	local prevState = self.currentState
	local abortState = ( self.currentState == self.pathingState and self.stuckTimer:done() )
	local done, result = self.currentState:isDone()
	if ( done or abortState ) then
		-- Select state
		if self.currentState == self.pathingState then
			if done and result == "arrived" then
				self.stuckTimer:reset()
				self.catchingUp = false
			end

			if followerDestination then
				if self.stuckTimer:done() then
					-- Pathing is stuck, teleport to objective
					self.unit.character:setWorldPosition( followerDestination )
					self.currentState = self.idleState
					self.stuckTimer:reset()
				elseif result ~= "arrived" then
					-- Pathing has failed, restart
					self.currentState:stop()
					self.currentState:start()
				else
					self.currentState = self.pathingState
				end
			else
				self.currentState = self.idleState
			end
		elseif followerDestination then
			self.currentState = self.pathingState
		else
			self.currentState = self.idleState
		end
	end

	if prevState ~= self.currentState then
		prevState:stop()
		self.currentState:start()
	end

end

function BabyWocFollowerState.isDone( self )
	return true, self.status
end

function BabyWocFollowerState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function BabyWocFollowerState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function BabyWocFollowerState.getMovementType( self )
	return self.currentState:getMovementType()
end

function BabyWocFollowerState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function BabyWocFollowerState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end