dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Ticker.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/BaseTotebotUnit.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/IdleRoamState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/ToteRedIgniteState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/managers/PatrolManager.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PatrolState.lua"

TotebotRedUnit = class( BaseTotebotUnit )

local IgniteRange = 35.0 -- Range where the unit will ignite
local ExplodeRange = 2.0 -- Range where the unit will explode
local ExplosionRunRange = 3.0 -- Range where there unit will begin speeding up
local ExplodeTickCountdown = 16 * 40 -- Time until the unit will automatically explode after ignited
local PreExplodeTime = 2.5
local ExplosionBreachLevel = 7
local ExplosionDestructionRadius = 3.0
local ExplosionImpulseRadius = 6.0
local ExplosionImpulseMagnitude = 25

local PushbackHorizontalForce = 25
local PushbackVerticalForce = 7
local HitStunDuration = 0.5

local AllyRange = 20.0
local HearRange = 20.0

local KnockbackTickInvulnerability = 0.5 * 40
local PlasmaDamageMultiplier = 2

function TotebotRedUnit.server_onCreate( self )
	BaseTotebotUnit.server_onCreate( self )

	self.target = nil
	self.previousTarget = nil
	self.lastTargetPosition = nil
	self.ambushPosition = nil
	self.ignoreAnimals = true
	self.isIgnited = false
	self.countDownStarted = false
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.stats == nil then
		self.saved.stats = { hp = 40, maxhp = 40 }
	end

	InitRobotParams( self )
	self.storage:save( self.saved )

	self.unit.eyeHeight = self.unit.character:getHeight() * 0.75
	self.unit.visionFrustum = {
		{ 3.0, math.rad( 80.0 ), math.rad( 80.0 ) },
		{ 10.0, math.rad( 40.0 ), math.rad( 35.0 ) },
		{ 20.0, math.rad( 20.0 ), math.rad( 20.0 ) }
	}
	self.unit:setWhiskerData( 3, math.rad( 60.0 ), 1.5, 5.0 )
	self.noiseScale = 1.0
	self.impactCooldownTicks = 0

	self.isInCombat = false
	self.combatTimer = Timer()
	self.combatTimer:start( 40 * 12 )
	self.lastKnockTick = 0

	-- Idle / Roam
	self.idleRoamState = IdleRoamState()
	self.idleRoamState:sv_onCreate( self.unit, self.homePosition )
	self.idleRoamState.debugName = "idleRoamState"
	self.idleRoamState.roamState.waterAvoidance = false
	self.idleRoamState.roamState.roamCenterOffset = 0.0

	-- Idle	
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Guard
	self.guardState = self.unit:createState( "positioning" )
	self.guardState.debugName = "guard"
	self.guardState.timeout = 3.0
	self.guardState.tolerance = 0.1
	self.guardState.avoidance = false
	self.guardState.movementType = "stand"

	-- Pathing
	self.pathingState = PathingState()
	self.pathingState:sv_onCreate( self.unit )
	self.pathingState:sv_setTolerance( 1.0 )
	self.pathingState:sv_setMovementType( "walk" )
	self.pathingState:sv_setWaterAvoidance( false )
	self.pathingState.debugName = "pathingState"
	self.pathingState:sv_setWaterAvoidance( true )

	-- Ignite state
	self.igniteState = ToteRedIgniteState()
	self.igniteState:sv_onCreate( self.unit )
	self.igniteState.debugName = "igniteState"

	-- Explode Pathing
	self.explodePathingState = PathingState()
	self.explodePathingState:sv_onCreate( self.unit )
	self.explodePathingState:sv_setTolerance( ExplodeRange )
	self.explodePathingState:sv_setMovementType( "sprint" )
	self.explodePathingState:sv_setWaterAvoidance( false )
	self.explodePathingState:sv_setWhiskerAvoidance( false )
	self.explodePathingState.debugName = "explodePathingState"
	self.explodePathingState:sv_setWaterAvoidance( true )
	self.explodePathingState:sv_setTimeout( 1.5 )

	-- Explode state
	self.explodeEventState = self.unit:createState( "wait" )
	self.explodeEventState.debugName = "explodeEventState"
	self.explodeEventState.name = "preexplode_start"
	self.explodeEventState.time = PreExplodeTime
	self.explodeEventState.interruptible = false

	self.explodePosition = nil
	self.explodeTimer = Timer()
	self.explodeTimer:start( ExplodeTickCountdown )

	-- Hit stun state
	self.hitStunState = self.unit:createState( "wait" )
	self.hitStunState.debugName = "hitStunState"
	self.hitStunState.name = "jump"
	self.hitStunState.time = HitStunDuration
	self.hitStunState.interruptible = false

	-- LookAt
	self.lookAtState = self.unit:createState( "positioning" )
	self.lookAtState.debugName = "lookAt"
	self.lookAtState.timeout = 3.0
	self.lookAtState.tolerance = 0.5
	self.lookAtState.avoidance = false
	self.lookAtState.movementType = "stand"

	-- Flee
	self.raidFlee = self.unit:createState( "flee" )
	self.raidFlee.movementAngleThreshold = math.rad( 180 )
	self.raidFlee.maxFleeTime = 0.0
	self.raidFlee.maxDeviation = 45 * math.pi / 180
	self.raidFlee.debugName = "raidFlee"

	-- Patrol
	self.patrolState = PatrolState()
	self.patrolState:sv_onCreate( self.unit, self.saved.patrolKey )
	self.patrolState.debugName = "patrolState"

	-- Tumble
	initTumble( self )

	-- Crushing
	initCrushing( self, DEFAULT_CRUSH_TICK_TIME )

	if self.saved.stationary and self.saved.guardDirection then
		self.guardState.desiredDirection = self.saved.guardDirection
		self.currentState = self.guardState
	else
		self.currentState = self.idleState
	end

	self.currentState:start()
end

function TotebotRedUnit.server_onRefresh( self )
end

function TotebotRedUnit.server_onFixedUpdate( self, dt )
	BaseUnit.server_onFixedUpdate( self )

	if updateCrushing( self ) then
		self:sv_onDeath( sm.vec3.new( 0, 0, 0 ) )
	end

	updateTumble( self )
	if self.isInCombat then
		self.airTicks = 0
	else
		updateAirTumble( self, self.idleState )
	end

	if self.currentState then
		if self.target and not sm.exists( self.target ) then
			self.target = nil
		end

		local facingDirection = self.currentState:getFacingDirection()
		if self.currentState == self.igniteState and self.explodePosition then
			facingDirection = ( self.explodePosition - self.unit.character.worldPosition ):safeNormalize( facingDirection )
		end

		self.currentState:onFixedUpdate( dt )
		self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		self.unit:setMovementType( self.currentState:getMovementType() )
		self.unit:setFacingDirection( facingDirection )
		self.unit:setWantsJump( self.currentState:getWantsJump() )

		if self.isInCombat then
			self.combatTimer:tick()
		end

		if self.explodePosition then
			self.explodeTimer:tick()
		end

		self.impactCooldownTicks = math.max( self.impactCooldownTicks - 1, 0 )
	end

	-- Update target for totebot character
	if self.target ~= self.previousTarget then
		self:sv_updateCharacterTarget()
		self.previousTarget = self.target
	end
	if self.isDirty then
		self.storage:save( self.saved )
		self.isDirty = false
	end
end

function TotebotRedUnit.server_onCharacterChangedColor( self, color )
	if self.saved.color ~= color then
		self.saved.color = color
		self.storage:save( self.saved )
	end
end

function TotebotRedUnit.server_onUnitUpdate( self, dt )
	if not sm.exists( self.unit ) then
		return
	end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end

	if CheckFleeFromRaid( self ) then
		return
	end

	if self.unit.character:isTumbling() then
		return
	end

	RobotSelectTarget( self, AllyRange, dt )

	if self.saved.raidPosition and not self.target and sm.exists( self.unit.character ) then
		local raidSpots = RaidManager.Sv_GetPlantLocations( self.unit.character:getWorld().id, self.saved.raidKey )
		local closestSpot = nil
		if #raidSpots > 0 and ( self.saved.randomPlotTarget == nil or self.saved.randomPlotTarget > #raidSpots ) then
			self.saved.randomPlotTarget = math.random( #raidSpots )
			self.isDirty = true
			closestSpot = raidSpots[self.saved.randomPlotTarget]
		end
		if closestSpot then
			self.homePosition = closestSpot + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 )
			if self.lastTargetPosition == nil or ( ( self.lastTargetPosition - closestSpot ):length2() > ( RAIDER_TARGETING_RADIUS * 1.5 ) ) then
				local attackableShape, attackPosition = FindAttackableShape( closestSpot, RAIDER_TARGETING_RADIUS, 10 )
				if attackableShape and attackPosition then
					sm.debugDraw.flashSphere( attackPosition, 0.5, sm.color.new( 1, 0, 0 ), 10 )
					self.lastTargetPosition = attackPosition
				elseif self.unit.character then
					self.pathingState:sv_setDestination( closestSpot )
					self.saved.raidPosition = closestSpot
					self.lastTargetPosition = closestSpot
				end
			end
		end
	end

	-- Check for positions acquired from noise
	local noiseShape = g_unitManager:sv_getClosestNoiseShape( self.unit.character.worldPosition, HearRange )
	if noiseShape and self.eventNoisePosition == nil then
		self.eventNoisePosition = noiseShape.worldPosition
	end
	local heardNoise = false
	if self.eventNoisePosition then
		self.lookAtState.desiredPosition = self.unit.character.worldPosition
		local fromToNoise = self.eventNoisePosition - self.unit.character.worldPosition
		fromToNoise.z = 0
		if fromToNoise:length() >= FLT_EPSILON then
			self.lookAtState.desiredDirection = fromToNoise:normalize()
		else
			self.lookAtState.desiredDirection = -self.unit.character.direction
		end
		heardNoise = true
	end
	self.eventNoisePosition = nil

	-- Update pathingState destination
	if self.currentState == self.pathingState then
		if self.lastTargetPosition then
			self.pathingState:sv_setDestination( self.lastTargetPosition )
		end
	end

	-- Check ignite / explode status

	if self.target or self.lastTargetPosition then
		local targetLocation = self.target and self.target.worldPosition or self.lastTargetPosition
		local fromToTarget = targetLocation - self.unit.character.worldPosition
		local targetRadius = 0.0
		if self.target and type( self.target ) == "Character" then
			targetRadius = self.target:getRadius()
		end
		local myRadius = self.unit.character:getRadius()

		local inIgniteRange = sm.vec3.new( fromToTarget.x, fromToTarget.y, 0 ):length() - targetRadius - myRadius <= IgniteRange
		if inIgniteRange then
			self:sv_ignite( targetLocation )
		end
		if self.explodePosition then
			self.explodePosition = targetLocation
		end
	end
	local inExplodeRange = false
	if self.explodePosition then
		local fromToTarget = self.explodePosition - self.unit.character.worldPosition
		local targetRadius = 0.0
		if self.target and type( self.target ) == "Character" then
			targetRadius = self.target:getRadius()
		end
		local myRadius = self.unit.character:getRadius()

		inExplodeRange = sm.vec3.new( fromToTarget.x, fromToTarget.y, 0 ):length() - targetRadius - myRadius <= ExplosionRunRange
		self.explodePathingState:sv_setDestination( self.explodePosition )
	end
	local shouldExplode = inExplodeRange or self.explodeTimer:done()

	-- Breach check
	local shouldCheckBreach = isAnyOf( self.currentState, { self.explodePathingState, self.pathingState })
	if shouldCheckBreach then
		local nextTargetPosition
		if self.target then
			nextTargetPosition = self.target.worldPosition
		elseif self.lastTargetPosition then
			nextTargetPosition = self.lastTargetPosition
		end
		-- Always check for breachable in front of the unit
		if nextTargetPosition == nil then
			nextTargetPosition = self.unit.character.worldPosition + self.unit.character.direction
		end
		if nextTargetPosition then
			local breachDepth = 0.25
			local leveledNextTargetPosition = sm.vec3.new( nextTargetPosition.x, nextTargetPosition.y, self.unit.character.worldPosition.z )
			local valid, breachPosition, breachObject = sm.ai.getBreachablePosition( self.unit, leveledNextTargetPosition, breachDepth + self.unit.character:getRadius(), ExplosionBreachLevel )
			if valid and breachPosition and ( breachObject and not ( type( breachObject ) == "Harvestable" ) ) then
				-- Start or finish exploding
				if self.explodePosition == nil then
					self.explodePosition = breachPosition
				end
				shouldExplode = true
			end

			-- Voxel breach check - explode when blocked by voxel terrain
			if not shouldExplode then
				local voxelBlocked, voxelHitPos = GetVoxelBreachPosition( self.unit.character, nextTargetPosition )
				if voxelBlocked then
					if self.explodePosition == nil then
						self.explodePosition = voxelHitPos
					end
					shouldExplode = true
				end
			end
		end
	end

	local prevState = self.currentState
	local prevInCombat = self.isInCombat
	if self.lastTargetPosition then
		self.isInCombat = true
		self.combatTimer:reset()
	end
	if self.combatTimer:done() then
		self.isInCombat = false
	end

	local canPatrol
	if self.saved.patrolKey then
		canPatrol = PatrolManager.Sv_IsPatrolActive( self.saved.patrolKey )
	end

	local restartState = false
	local done, result = self.currentState:isDone()
	local abortState = 	( not isAnyOf( self.currentState, { self.explodeEventState, self.igniteState, self.explodePathingState, self.hitStunState } ) ) and
						(
							( prevInCombat and self.combatTimer:done() ) or
							( self.currentState == self.lookAtState and self.isInCombat ) or
							( isAnyOf( self.currentState, { self.idleState, self.idleRoamState } ) and heardNoise ) or
							( shouldExplode )
						)
	if ( done or abortState ) then
		-- Select state
		if self.currentState == self.hitStunState then
			if self.countDownStarted then
				self.currentState = self.explodeEventState
			elseif self.isIgnited then
				self.currentState = self.explodePathingState
			else
				self.currentState = self.igniteState
				self.isIgnited = true
			end
		elseif self.currentState == self.explodeEventState then
			self:sv_onDeath( sm.vec3.new( 0, 0, 1 ) )
		elseif self.currentState == self.explodePathingState then
			if result == "failed" then
				shouldExplode = true
			end
			if shouldExplode then
				self.currentState = self.explodeEventState
				self.countDownStarted = true
			elseif done then
				restartState = true
			end
		elseif self.currentState == self.igniteState then
			if self.explodePosition then
				self.currentState = self.explodePathingState
				self.explodePathingState:sv_setDestination( self.explodePosition )
			else
				-- Nowhere to go, explode immediately
				self.currentState = self.explodeEventState
				self.countDownStarted = true
			end
		elseif self.isInCombat then
			-- Select combat state
			if self.lastTargetPosition then
				if self.currentState == self.pathingState and done then
					restartState = true
				end
				self.currentState = self.pathingState
				self.pathingState:sv_setDestination( self.lastTargetPosition )
				self.lastTargetPosition = nil
			else
				-- No target information
				self.isInCombat = false
			end
		else
			-- Select non-combat state
			if self.saved.ambusher then
				self.currentState = self.idleState
			elseif heardNoise then
				self.currentState = self.lookAtState
			elseif self.saved.stationary then
				self.currentState = self.guardState
			elseif canPatrol then
				self.currentState = self.patrolState
			else
				self.currentState = self.idleRoamState
			end
		end
	end

	if prevState ~= self.currentState or restartState then
		prevState:stop()
		self.currentState:start()
	end

end

function TotebotRedUnit.ApplyDamagePushback( self, pushDirection )
	local tick = sm.game.getCurrentTick()
	if tick - self.lastKnockTick >= KnockbackTickInvulnerability then
		self.lastKnockTick = tick
		sm.physics.applyImpulse( self.unit.character, ( pushDirection * self.unit.character.mass * PushbackHorizontalForce ) + ( sm.vec3.new( 0, 0, 1 ) * self.unit.character.mass * PushbackVerticalForce ), true )
	end
end

function TotebotRedUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if not sm.exists( self.unit ) or not sm.exists( attacker ) then
		return
	end
	local teamOpponent = false
	if type( attacker ) == "Unit" then
		if not SurvivalGame then
			teamOpponent = not InSameTeam( attacker, self.unit )
		end
	end

	if type( attacker ) == "Player" or type( attacker ) == "Shape" or teamOpponent then
		if projectileUuid == projectile_water then
			self.explodeTimer:reset()
			self.igniteState:reset()
			self.isIgnited = false
			self.countDownStarted = false
			self.unit:sendCharacterEvent( "roaming" )
			sm.event.sendToCharacter( self.unit.character, "sv_e_extinguish" )
			local target = self.target
			local eventTarget = nil
			if type( attacker ) == "Player" or type( attacker ) == "Unit" then
				eventTarget = attacker:getCharacter()
			elseif type( attacker ) == "Shape" then
				eventTarget = attacker
			end
			if self.eventTarget == nil then
				self.eventTarget = eventTarget
			end
			if target and sm.exists( target ) or eventTarget then
				self.explodePosition = target and target.worldPosition or eventTarget.worldPosition
				self.currentState:stop()
				self.currentState = self.igniteState
				self.currentState:start()
				self.isIgnited = true
			end
			self.unit:sendCharacterEvent( "reset" )
			return
		end
		if damage > 0 then
			if type( attacker ) == "Player" then
				g_ambienceManager:triggerCombatMusic()
			end
			local pushDirection = ComputePushbackDirection( self.unit.character, hitVelocity )
			if self.isIgnited then
				self.currentState:stop()
				self.currentState = self.hitStunState
				self.currentState:start()
			end
			self:ApplyDamagePushback( pushDirection )
			local eventTarget
			if type( attacker ) == "Player" or type( attacker ) == "Unit" then
				eventTarget = attacker:getCharacter()
			elseif type( attacker ) == "Shape" then
				eventTarget = attacker
			end
			if self.eventTarget == nil then
				self.eventTarget = eventTarget
			end
			if eventTarget then
				self:sv_ignite( eventTarget.worldPosition )
			end
			local impact = hitVelocity:normalize() * 6
			self:sv_takeDamage( damage, impact, hitPos )
		end
	end
end

function TotebotRedUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if not sm.exists( self.unit ) or not sm.exists( attacker ) then
		return
	end
	local teamOpponent = false
	if type( attacker ) == "Unit" then
		if not SurvivalGame then
			teamOpponent = not InSameTeam( attacker, self.unit )
		end
	end

	if type( attacker ) == "Player" or teamOpponent then
		if type( attacker ) == "Player" then
			g_ambienceManager:triggerCombatMusic()
		end

		local attackingCharacter = attacker:getCharacter()
		self:sv_ignite( attackingCharacter.worldPosition )
		if self.eventTarget == nil then
			self.eventTarget = attackingCharacter
		end
		local pushDirection = ComputePushbackDirection( self.unit.character, hitDirection )
		if self.isIgnited then
			self.currentState:stop()
			self.currentState = self.hitStunState
			self.currentState:start()
		end
		self:ApplyDamagePushback( pushDirection )
		local impact = hitDirection * 6
		self:sv_takeDamage( damage, impact, hitPos )
	end
end

function TotebotRedUnit.server_onExplosion( self, center, destructionLevel )
	if not sm.exists( self.unit ) then
		return
	end
	local impact = ( self.unit:getCharacter().worldPosition - center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) ) * 6
	self:sv_takeDamage( self.saved.stats.maxhp, impact, self.unit:getCharacter().worldPosition )
end

function TotebotRedUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if not sm.exists( self.unit ) then
		return
	end
	if other == nil and not self.unit.character:isTumbling() then
		return
	end
	if type( other ) == "Character" then
		if not sm.exists( other ) then
			return
		end
		local teamOpponent = false
		if not SurvivalGame then
			teamOpponent = not InSameTeam( other, self.unit )
		end
		if other:isPlayer() or teamOpponent then
			if self.eventTarget == nil then
				self.eventTarget = other
			end
		end
	elseif type( other ) == "Shape" then
		if not sm.exists( other ) or ( other.body:isStatic() or other.body:getVelocity():length2() < 10 ) then
			return
		end
		if self.target == nil and self.eventTarget == nil then
			local creationBodies = other.body:getCreationBodies()
			for _, body in ipairs( creationBodies ) do
				local seatedCharacters = body:getAllSeatedCharacter()
				if #seatedCharacters > 0 then
					self.eventTarget = seatedCharacters[1]
					break
				end
			end
		end
	end
	local hitRegularHarvestable = type( other ) == "Harvestable" and sm.exists( other ) and not other:isKinematic()
	if hitRegularHarvestable then
		return
	end
	local hitByRailKinematic = type( other ) == "Harvestable" and sm.exists( other ) and other.publicData and other.publicData.isRailKinematic

	if self.impactCooldownTicks > 0 then
		return
	end

	local collisionDamageMultiplier = 1.0
	
	local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision( self.unit.character, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, self.saved.stats.maxhp / collisionDamageMultiplier, nil, self.velocityBuffer, self.velocityBufferIndex )
	damage = damage * collisionDamageMultiplier
	if damage > 0 or tumbleTicks > 0 then
		self.impactCooldownTicks = 6
	end
	if damage > 0 then
		self:sv_takeDamage(damage, collisionNormal, collisionPosition)
		if self.saved.stats.hp <= 0 then
			--Achievement check
			RoadRageAchievementCheck( other )
		end
	end
	if tumbleTicks > 0 then
		if hitByRailKinematic then
			self:sv_takeDamage( self.saved.stats.maxhp, collisionNormal, collisionPosition )
		else
			if not isAnyOf( self.currentState, { self.igniteState, self.explodePathingState, self.explodeEventState } ) then
				if startTumble( self, tumbleTicks, self.idleState, tumbleVelocity ) then
					if type( other ) == "Shape" and sm.exists( other ) and other.body:isDynamic() then
						sm.physics.applyImpulse( other.body, impactReaction * other.body.mass, true, collisionPosition - other.body.worldPosition )
					end
				end
			end
		end
	end
end

function TotebotRedUnit.server_onCollisionCrush( self )
	if not sm.exists( self.unit ) then
		return
	end
	onCrush( self )
end

function TotebotRedUnit.sv_updateCharacterTarget( self )
	if self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_n_updateTarget", { target = self.target } )
	end
end

function TotebotRedUnit.sv_ignite( self, targetPosition )
	if not isAnyOf( self.currentState, { self.igniteState, self.explodeEventState, self.explodePathingState, self.hitStunState, self.raidFlee } ) then
		self.explodePosition = targetPosition
		self.currentState:stop()
		self.currentState = self.igniteState
		self.currentState:start()
		self.isIgnited = true
	end
end

function TotebotRedUnit.sv_e_receiveDamage( self, damageData )
	if not sm.exists( self.unit ) then
		return
	end
	if damageData.source == "plasma" then
		local pushDirection = ComputePushbackDirection( self.unit.character, damageData.impact )
		self:ApplyDamagePushback( pushDirection )
		if self.isIgnited then
			self.currentState:stop()
			self.currentState = self.hitStunState
			self.currentState:start()
		end
		damageData.damage = damageData.damage * PlasmaDamageMultiplier
	end

	BaseUnit.sv_e_receiveDamage( self, damageData )
end


function TotebotRedUnit.sv_takeDamage( self, damage, impact, hitPos, source )
	if damage > 0 then
		local effectRotation = sm.quat.identity()
		if hitPos and impact and impact:length() >= FLT_EPSILON then
			effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -impact:safeNormalize( sm.vec3.new( 0, 0, 0 ) ) )
		end

		if self.saved.stats.hp - damage > 0 then
			local currentTick = sm.game.getCurrentTick()
			if source ~= "plasma" or not self.lastPlasmaDrillEffectTick or currentTick - self.lastPlasmaDrillEffectTick >= PLASMA_BOT_HIT_EFFECT_TICK_THRESHOLD then
				self.lastPlasmaDrillEffectTick = currentTick
				sm.effect.playEffect( "ToteBot - Hit", hitPos, nil, effectRotation )
			end
		end
		
		self:sv_onDamaged( damage, impact )
	end
end

function TotebotRedUnit.sv_onDamaged( self, damage, impact )
	
	self.saved.stats.hp = self.saved.stats.hp - damage
	self.saved.stats.hp = math.max( self.saved.stats.hp, 0 )

	if self.saved.stats.hp <= 0 then
		self:sv_onDeath( impact )
	else
		self.storage:save( self.saved )
	end
end

function TotebotRedUnit.sv_onDeath( self, impact )
	local character = self.unit:getCharacter()
	if not self.destroyed then
		self.unit:sendCharacterEvent( "death" )
		g_unitManager:sv_addDeathMarker( character.worldPosition )
		self.saved.stats.hp = 0
		self.unit:destroy()
		sm.physics.explode( character.worldPosition, ExplosionBreachLevel, ExplosionDestructionRadius, ExplosionImpulseRadius, ExplosionImpulseMagnitude, "Totebotred - Explosion", nil, { Color = self.unit.character:getColor() }, nil, 35 )
		self:sv_spawnParts( impact )
		if SurvivalGame then
			local loot = SelectLoot( "lootsource_totebot_red", nil, self.saved.lootType )
			SpawnLoot( self.unit, loot )
		end
		self.destroyed = true
		BaseUnit.sv_onDeath( self );
	end
end

function TotebotRedUnit.sv_spawnParts( self, impact )
	local character = self.unit:getCharacter()

	local lookDirection = character:getDirection()
	local bodyPos = character.worldPosition
	local bodyRot = sm.quat.identity()
	lookDirection = sm.vec3.new( lookDirection.x, lookDirection.y, 0 )
	if lookDirection:length() >= FLT_EPSILON then
		lookDirection = lookDirection:normalize()
		bodyRot = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), lookDirection  ) --Turn parts sideways
	end
	local bodyOffset = bodyRot * sm.vec3.new( -0.25, 0.25, 0.375 )
	bodyPos = bodyPos - bodyOffset

	local color = self.unit.character:getColor()
	if SurvivalGame then
		if math.random( 1, 15 ) == 1 then
			local headBody = sm.body.createBody( bodyPos, bodyRot, true )
			local headShape = headBody:createPart( ITEMS.obj_interactive_robotsynthhead, sm.vec3.new( 0, 1, 2 ), sm.vec3.new( 0, 1, 0 ), sm.vec3.new( -1, 0, 0 ), true )
			headShape.color = color
			sm.physics.applyImpulse( headShape, impact * headShape.mass, true )
		end
	end
end

