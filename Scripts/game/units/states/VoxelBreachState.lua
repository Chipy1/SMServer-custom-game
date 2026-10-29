-- VoxelBreachState.lua --
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/CombatAttackState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

VoxelBreachState = class( BaseState )

local DEBUG_DRAW_BREACH = true

local NoProgressDig = 6

function VoxelBreachState.sv_onCreate( self, unit, breachTimeoutTicks )
	self.unit = unit

	self.idleState = self.unit:createState( "idle" )

	self.followDirectionState = unit:createState( "followDirection" )
	self.followDirectionState.movementType = "walk"
	self.followDirectionState.maxDeviation = 0
	self.followDirectionState.avoidance = false
	self.followDirectionState.desiredDirection = sm.vec3.new( 0, 1, 0 )

	self.combatAttackState = CombatAttackState()
	self.combatAttackState:sv_onCreate( self.unit )

	self.currentState = self.idleState

	self.digRadius = 1.0
	self.digStrength = 0.5
	self.attackRange = 2.5
	self.closeEnough = 0.5

	self.breachTimeoutTicks = breachTimeoutTicks
	self.breachTimeout = breachTimeoutTicks
	self.attackHitPending = false
	self.lastHitCount = 0
	self.targetPosition = nil
	self.voxelHitPosition = nil
	self.done = nil
	self.noProgressDigCount = 0
end

function VoxelBreachState.refresh( self ) end

function VoxelBreachState.sv_setDestination( self, targetPosition )
	self.targetPosition = targetPosition
	self.done = nil
	self.breachTimeout = self.breachTimeoutTicks
end

function VoxelBreachState.sv_setDigRadius( self, radius )
	self.digRadius = radius
end

function VoxelBreachState.sv_setDigStrength( self, strength )
	self.digStrength = strength
end

function VoxelBreachState.sv_addAttack( self, attackState )
	self.combatAttackState:sv_addAttack( attackState )
end

--[[API functions]]
function VoxelBreachState.start( self )
	self.done = nil
	self.voxelHitPosition = nil
	self.breachTimeout = self.breachTimeoutTicks
	self.attackHitPending = false
	self.lastHitCount = self.combatAttackState.hitCount
	self.noProgressDigCount = 0
	local prevState = self.currentState
	self.currentState = self.idleState
	prevState:stop()
	self.currentState:start()
end

function VoxelBreachState.stop( self )
	self.done = nil
	self.voxelHitPosition = nil
	self.breachTimeout = self.breachTimeoutTicks
	self.attackHitPending = false
	self.lastHitCount = self.combatAttackState.hitCount
	self.noProgressDigCount = 0
	self.currentState:stop()
end

function VoxelBreachState.tick( self )
	self.combatAttackState:tick()

	if self.currentState then
		local done, _ = self:isDone()
		if self.currentState == self.combatAttackState or done then
			self.breachTimeout = self.breachTimeoutTicks
		else
			self.breachTimeout = math.max( self.breachTimeout - 1, 0 )
		end
	end
end

function VoxelBreachState.onFixedUpdate( self, dt )

	if self.currentState then
		self.currentState:onFixedUpdate( dt )
	end
		
	-- Determine if we should dig this frame
	local canDig = false
	if #self.combatAttackState.attacks > 0 then
		-- Attack-synced mode: dig when attack hit is pending
		if self.attackHitPending then
			canDig = true
			self.attackHitPending = false
		end
	end

	if not canDig then
		return
	end

	-- Raycast and dig
	if self.targetPosition then
	
		local voxelBlocked, hitPosition = GetVoxelBreachPosition( self.unit.character, self.targetPosition )
		if voxelBlocked and hitPosition then
			local character = self.unit.character
			local travelDir = ( self.targetPosition - character.worldPosition ):safeNormalize( character.direction )
			local digPosition = hitPosition + travelDir * self.digRadius * 0.5

			if DEBUG_DRAW_BREACH then
				sm.debugDraw.flashSphere( digPosition, self.digRadius, sm.color.new( 1, 0, 0, 0.8 ), 0.1 )
			end
			character:getWorld():sphereVoxelDensitySubtraction( digPosition, self.digRadius, sm.world.voxelFilter.material0, self.digStrength, "sv_voxelBreachResult", { unit = self.unit } )

			self.noProgressDigCount = self.noProgressDigCount + 1
			if self.noProgressDigCount >= NoProgressDig then
				self.done = "timeout"
			end
		end
	end
end

function VoxelBreachState.onUnitUpdate( self, dt )
	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end
	local prevState = self.currentState

	-- Detect attack hit via hit counter
	if #self.combatAttackState.attacks > 0 then
		if self.combatAttackState.hitCount > self.lastHitCount then
			self.attackHitPending = true
			self.lastHitCount = self.combatAttackState.hitCount
		end
	end

	-- Check if we've reached the destination
	if self.targetPosition then
		local xyDistance = ( sm.vec3.new( self.targetPosition.x, self.targetPosition.y, 0 ) - sm.vec3.new( self.unit.character.worldPosition.x, self.unit.character.worldPosition.y, 0 ) ):length()
		if xyDistance <= self.closeEnough then
			self.targetPosition = nil
			self.done = "breached"
		end
	end

	-- Spherecast to check if voxel obstruction still exists (uses character radius so hole must be large enough to walk through)
	self.voxelHitPosition = nil
	if self.targetPosition then
		local voxelBlocked, voxelHitPos = GetVoxelBreachPosition( self.unit.character, self.targetPosition )
		self.voxelHitPosition = voxelHitPos
	end

	-- Select state
	if self.breachTimeout <= 0 then
		self.done = "timeout"
		self.currentState = self.idleState
	elseif self.voxelHitPosition then
		local distToVoxel = ( self.voxelHitPosition - self.unit.character.worldPosition ):length()
		if distToVoxel <= self.attackRange then
			-- Close enough to attack the voxel wall
			local desiredDirection = ( self.voxelHitPosition - self.unit.character.worldPosition ):safeNormalize( self.unit.character.direction )
			if #self.combatAttackState.attacks > 0 then
				-- Attack-synced mode: use combat attack animation
				self.combatAttackState:sv_setAttackDirection( desiredDirection )
				self.currentState = self.combatAttackState
			else
				-- Cooldown-based mode: face the wall and dig on timer
				self.followDirectionState.desiredDirection = desiredDirection
				self.currentState = self.followDirectionState
			end
		else
			-- Walk towards the voxel wall
			if self.targetPosition then
				local desiredDirection = ( self.targetPosition - self.unit.character.worldPosition ):safeNormalize( self.unit.character.direction )
				if math.abs( desiredDirection.z ) == 1 then
					desiredDirection = self.unit.character.direction
				end
				self.followDirectionState.desiredDirection = desiredDirection
				self.currentState = self.followDirectionState
			end
		end
	elseif self.currentState == self.combatAttackState then
		-- Let the attack animation finish before switching
		local attackDone, _ = self.combatAttackState:isDone()
		if attackDone then
			self.done = "breached"
			self.currentState = self.idleState
		end
	elseif self.targetPosition then
		-- No voxel in the way, we breached through
		self.done = "breached"
		self.currentState = self.idleState
	else
		self.currentState = self.idleState
	end

	if prevState ~= self.currentState then
		prevState:stop()
		self.currentState:start()
	end
end

function VoxelBreachState.isDone( self )
	return self.done == "breached" or self.done == "timeout", self.done
end

function VoxelBreachState.getMovementDirection( self )
	if self.targetPosition then
		local desiredDirection = ( self.targetPosition - self.unit.character.worldPosition ):safeNormalize( sm.vec3.new( 0, 1, 0 ) )
		if math.abs( desiredDirection.z ) == 1 then
			desiredDirection = sm.vec3.new( 0, 1, 0 )
		end
		return desiredDirection
	end
	return self.unit.character.direction
end

function VoxelBreachState.getFacingDirection( self )
	if self.voxelHitPosition then
		local desiredDirection = ( self.voxelHitPosition - self.unit.character.worldPosition ):safeNormalize( sm.vec3.new( 0, 1, 0 ) )
		if math.abs( desiredDirection.z ) == 1 then
			desiredDirection = sm.vec3.new( 0, 1, 0 )
		end
		return desiredDirection
	elseif self.targetPosition then
		local desiredDirection = ( self.targetPosition - self.unit.character.worldPosition ):safeNormalize( sm.vec3.new( 0, 1, 0 ) )
		if math.abs( desiredDirection.z ) == 1 then
			desiredDirection = sm.vec3.new( 0, 1, 0 )
		end
		return desiredDirection
	end
	return self.unit.character.direction
end

function VoxelBreachState.getMovementType( self )
	return self.currentState:getMovementType()
end

function VoxelBreachState.getWantsJump( self )
	return false
end
