dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Ticker.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/MinerbotPathingState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/MinerbotBarrageState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/MinerbotSelfdestructState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/MinerbotRoamingState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/MinerbotDiggingIdleState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/MinerbotUnstuckState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/LookAroundState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/managers/MinerbotWaypointManager.lua"
dofile "$SURVIVAL_DATA/Scripts/game/managers/PatrolManager.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PatrolState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/MinerbotAlertState.lua"

MinerbotUnit = class( BaseUnit )

local AllyRange = 20.0
local HearRange = 40.0

local DesiredFiringDistanceMin = 20.0 -- Abort pathing, to fire at the target, if the target is visible within these distances
local DesiredFiringDistanceMax = 26.0
local DesiredFiringHeight = 10.0
local MiddleDistanceVariance = 1.5 -- An individual variance of the middle of the DesiredFiringDistance +/-

local CombatFireRange = 50.0 -- Max range to fire from
local DesiredFiringAngle = 35.0 -- Attempt to find a position to fire from at the terget with this angle above the target
local ReturnHomeDistance = 96.0 -- Path to the home position if out of combat and further than this distance
local AggroSphereRadius = 14




local CalmSwitchTime = 4.4
local SpawnAnimationDelay = 5.0
local SelfdestructVulnerableTickDelay = 40 -- Time from when hp reaches 0 until the minerbot can be instantly destroyed by a new hit

function MinerbotUnit.server_onCreate( self )
	self.target = nil
	self.previousTarget = nil
	self.lastTargetPosition = nil
	self.ambushPosition = nil
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.stats == nil then
		self.saved.stats = { hp = 140, maxhp = 140 }
	end
	if self.saved.originalSpawnPosition == nil then
		self.saved.originalSpawnPosition = self.unit.character.worldPosition
	end
	if self.saved.originalSpawnDirection == nil then
		self.saved.originalSpawnDirection = self.unit.character.direction
	end

	InitRobotParams( self )
	self.storage:save( self.saved )

	sm.message.subscribe( MESSAGE_TYPES.GENERAL.ProjectileHit, "sv_m_projectileHit" )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.ProjectileFire, "sv_m_projectileFire" )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.Collision, "sv_m_collision" )

	self.unit.eyeHeight = self.unit.character:getHeight() * 0.75
	self.unit.visionFrustum = {
		{ 2.0, math.rad( 85.0 ), math.rad( 85.0 ) },
		{ 90.0, math.rad( 40.0 ), math.rad( 40.0 ) }
	}
	self.unit:setWhiskerData( 3, math.rad( 60.0 ), 1.5, 5.0 )
	self.noiseScale = 1.0
	self.ignoreWaterTarget = true
	self.impactCooldownTicks = 0

	self.isInCombat = false
	self.combatTimer = Timer()
	self.combatTimer:start( 40 * 12 )

	self.desiredPosition = self.unit.character.worldPosition
	self.heightAboveGroundLevel = 0.0

	self.middleDistanceVariance = math.random() * MiddleDistanceVariance * 2 - MiddleDistanceVariance

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Digging Idle
	self.minerbotDiggingIdleState = MinerbotDiggingIdleState()
	self.minerbotDiggingIdleState:sv_onCreate( self.unit, self.saved.originalSpawnPosition, self.saved.originalSpawnDirection )
	self.minerbotDiggingIdleState.debugName = "minerbotDiggingIdleState"

	-- Roaming
	self.minerbotRoamingState = MinerbotRoamingState()
	self.minerbotRoamingState:sv_onCreate( self.unit, self.homePosition )
	self.minerbotRoamingState.debugName = "minerbotRoamingState"

	-- Pathing
	self.minerbotPathingState = MinerbotPathingState()
	self.minerbotPathingState:sv_onCreate( self.unit )
	self.minerbotPathingState.debugName = "minerbotPathingState"

	-- Barrage attack
	self.minerbotBarrageState = MinerbotBarrageState()
	self.minerbotBarrageState:sv_onCreate( self.unit )
	self.minerbotBarrageState.debugName = "minerbotBarrageState"

	-- Selfdestruct
	self.minerbotSelfdestructState = MinerbotSelfdestructState()
	self.minerbotSelfdestructState:sv_onCreate( self.unit )
	self.minerbotSelfdestructState.debugName = "minerbotSelfdestructState"

	-- LookAround
	self.lookAroundState = LookAroundState()
	self.lookAroundState:sv_onCreate( self.unit )
	self.lookAroundState.debugName = "lookAroundState"

	-- Unstuck
	self.minerbotUnstuckState = MinerbotUnstuckState()
	self.minerbotUnstuckState:sv_onCreate( self.unit )
	self.minerbotUnstuckState.debugName = "minerbotUnstuckState"

	-- Crushing
	initCrushing( self, DEFAULT_CRUSH_TICK_TIME )

	-- LookAt (noise)
	self.lookAtNoiseState = self.unit:createState( "positioning" )
	self.lookAtNoiseState.debugName = "lookAtNoiseState"
	self.lookAtNoiseState.timeout = 3.0
	self.lookAtNoiseState.tolerance = 0.5
	self.lookAtNoiseState.avoidance = false
	self.lookAtNoiseState.movementType = "stand"

	-- LookAt (target)
	self.lookAtTargetState = self.unit:createState( "positioning" )
	self.lookAtTargetState.debugName = "lookAtTargetState"
	self.lookAtTargetState.timeout = 3.0
	self.lookAtTargetState.tolerance = 0.5
	self.lookAtTargetState.avoidance = false
	self.lookAtTargetState.movementType = "stand"

	-- Flee
	self.raidFlee = self.unit:createState( "flee" )
	self.raidFlee.movementAngleThreshold = math.rad( 180 )
	self.raidFlee.maxFleeTime = 0.0
	self.raidFlee.maxDeviation = 45 * math.pi / 180

	-- Extra states for delayed alert animations
	self.alert = false

	-- Alert
	self.alertEventState = MinerbotAlertState()
	self.alertEventState:sv_onCreate( self.unit )
	self.alertEventState.debugName = "waitState"

	-- Calm
	self.calmEventState = self.unit:createState( "wait" )
	self.calmEventState.debugName = "waitState"
	self.calmEventState.time = CalmSwitchTime
	self.calmEventState.name = "calm"
	self.calmEventState.interruptible = false

	-- Patrol
	self.patrolState = PatrolState()
	self.patrolState:sv_onCreate( self.unit, self.saved.patrolKey, MinerbotPathingState() )
	self.patrolState.debugName = "patrolState"

	-- Spawn
	self.spawnState = self.unit:createState( "wait" )
	self.spawnState.debugName = "spawnState"
	self.spawnState.time = SpawnAnimationDelay
	self.spawnState.interruptible = false

	if SafeGet( self.params, "spawnAnimation" ) then
		self.unit:sendCharacterEvent( "spawnAnimation" )
		self.currentState = self.spawnState
	else
		if self.saved.stationary then
			self.currentState = self.minerbotDiggingIdleState
		else
			self.currentState = self.idleState
		end
	end

	self.currentState:start()
end

function MinerbotUnit.server_onRefresh( self )
	print( "-- MinerbotUnit refreshed --" )
end

function MinerbotUnit.server_onDestroy( self )
	print( "-- MinerbotUnit terminated --" )
	BaseUnit.server_onDestroy( self )
	self.minerbotPathingState:sv_onDestroy()
end

function MinerbotUnit.server_onFixedUpdate( self, dt )
	BaseUnit.server_onFixedUpdate( self )

	if self.isInCombat then
		self.combatTimer:tick()
	end

	if updateCrushing( self ) then
		print("'MinerbotUnit' was crushed!")
		self:sv_onDeath()
	end

	if self.currentState then
		if self.target and not sm.exists( self.target ) then
			self.target = nil
		end

		if self.target then
			self.minerbotBarrageState:sv_setTarget( self.target )
		end

		-- Check height above ground
		local sphereRadius = 0.25
		local testDistance = 500.0
		local groundTestPosition = self.unit.character.worldPosition - sm.vec3.new( 0, 0, testDistance )
		local hit, result = sm.physics.spherecast( self.unit.character.worldPosition, groundTestPosition, sphereRadius, self.unit.character, sm.physics.filter.static )
		if hit then
			self.heightAboveGroundLevel = testDistance * result.fraction - self.unit.character:getHeight() * 0.5 + sphereRadius
		end

		self.currentState:onFixedUpdate( dt )
		self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		self.unit:setMovementType( self.currentState:getMovementType() )
		self.unit:setFacingDirection( self.currentState:getFacingDirection() )
		self.unit:setWantsJump( self.currentState:getWantsJump() )
		self.unit:setWantsCrouch( self.currentState:getWantsCrouch() )

		if self.currentState == self.minerbotSelfdestructState then
			-- Immediate reaction to selfdestruct being done
			local done, status = self.currentState:isDone()
			if done then
				self.currentState:stop()
				self.currentState = self.idleState
				self.currentState:start()
				self:sv_onDeath()
			end
		end
	end

	-- Update target for character
	if self.target ~= self.previousTarget then
		self:sv_updateCharacterTarget()
		self.previousTarget = self.target
	end
end

function MinerbotUnit.server_onCharacterChangedColor( self, color )
	if self.saved.color ~= color then
		self.saved.color = color
		self.storage:save( self.saved )
	end
end

function MinerbotUnit.server_onUnitUpdate( self, dt )
	if not sm.exists( self.unit ) then
		return
	end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end

	if CheckFleeFromRaid( self ) then
		return
	end

	-- Only allowed allowed to actively hunt the player once aggroed
	self.ignoreTargetPerception = isAnyOf( self.currentState, { self.idleState, self.minerbotDiggingIdleState, self.minerbotRoamingState } )
	RobotSelectTarget( self, AllyRange, dt )

	-- Check the aggro sphere when without a target
	if self.target == nil and sm.game.getEnableAggro() then





		local closestPlayer = GetClosestPlayer( self.unit.character.worldPosition, AggroSphereRadius, self.unit.character:getWorld() )
		if closestPlayer and sm.exists( closestPlayer.character ) then
			local success, _ = sm.ai.getAimPosition( self.unit.character, closestPlayer.character, AggroSphereRadius, closestPlayer.character:getRadius() )
			if success then
				self.target = closestPlayer.character
				self.lastTargetPosition = self.target.worldPosition
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
		self.lookAtNoiseState.desiredPosition = self.unit.character.worldPosition
		local fromToNoise = self.eventNoisePosition - self.unit.character.worldPosition
		fromToNoise.z = 0
		if fromToNoise:length() >= FLT_EPSILON then
			self.lookAtNoiseState.desiredDirection = fromToNoise:normalize()
		else
			self.lookAtNoiseState.desiredDirection = -self.unit.character.direction
		end
		heardNoise = true
	end
	self.eventNoisePosition = nil


	local targetRadius = 0.0
	if self.target and type( self.target ) == "Character" then
		targetRadius = self.target:getRadius()
	end

	local inCombatFireRange
	local inCombatDesiredFireRange
	local inCombatLOS
	if self.target then
		local fromToTarget = self.target.worldPosition - self.unit.character.worldPosition
		local fromToTargetDistance = fromToTarget:length() - targetRadius
		inCombatFireRange = fromToTargetDistance <= CombatFireRange
		inCombatDesiredFireRange = fromToTargetDistance <= DesiredFiringDistanceMax and fromToTargetDistance >= DesiredFiringDistanceMin and self.heightAboveGroundLevel >= DesiredFiringHeight

		local visionFilter = sm.physics.filter.default
		if self.target:isSeated() then
			visionFilter = bit.band( sm.physics.filter.default, bit.bnot( sm.physics.filter.dynamicBody ) )
		end
		local hit, result = sm.physics.spherecast( self.unit.character.worldPosition, self.target.worldPosition, 0.125, self.unit.character, visionFilter )
		if hit then
			inCombatLOS = result:getCharacter() == self.target
		end
	end

	if self.lastTargetPosition then
		self.lookAtLocation = self.lastTargetPosition
	end

	local atReturnHomeDistance = ( self.unit.character.worldPosition - self.homePosition ):length2() >= ReturnHomeDistance * ReturnHomeDistance

	local prevState = self.currentState
	if self.lastTargetPosition then
		self.isInCombat = true
		self.combatTimer:reset()
	end
	if self.combatTimer:done() then
		self.isInCombat = false
	end
	self.wasInCombat = self.wasInCombat or self.isInCombat

	local canPatrol
	if self.saved.patrolKey then
		canPatrol = PatrolManager.Sv_IsPatrolActive( self.saved.patrolKey )
	end

	local done, status = self.currentState:isDone()
	local abortState = not done and not isAnyOf( self.currentState, { self.alertEventState, self.calmEventState } ) and
	(
		( self.currentState == self.minerbotPathingState and inCombatDesiredFireRange and inCombatLOS ) or
		( self.currentState == self.minerbotPathingState and status == "timedout" ) or
		( self.wasInCombat and not self.isInCombat ) or
		( self.currentState == self.lookAroundState and self.target ) or
		( self.currentState == self.lookAtTargetState and self.target )
	)

	if done or abortState then
		if self.currentState == self.minerbotSelfdestructState then
			self.currentState = self.idleState
			self:sv_onDeath()
		elseif self.currentState == self.minerbotPathingState and status == "timedout" then
			-- Move away from obstacles
			self.currentState = self.minerbotUnstuckState
		else
			if self.isInCombat then
				-- InCombat states
				if not self.alert then
					if self.target then
						self.alertEventState:sv_setTarget( self.target )
					else
						self.alertEventState:sv_setTargetPosition( self.lastTargetPosition )
					end
					self.currentState = self.alertEventState
					self.alert = true
				elseif self.currentState == self.minerbotPathingState then
					-- Finished pathing to firing position
					-- Look at target
					local lookAtDirection = self.unit.character.direction
					if self.lookAtLocation then
						local fromTo = self.lookAtLocation - self.unit.character.worldPosition
						local flatFromTo = sm.vec3.new( fromTo.x, fromTo.y, 0 )
						lookAtDirection = flatFromTo:safeNormalize( lookAtDirection )
					end
					self.lookAtTargetState.desiredDirection = lookAtDirection
					self.currentState = self.lookAtTargetState
				elseif self.currentState == self.lookAtTargetState then
					if inCombatFireRange and inCombatLOS then
						-- Open fire
						self.minerbotBarrageState:sv_setTarget( self.target )
						self.currentState = self.minerbotBarrageState
					elseif self.lastTargetPosition then
						-- Bad firing conditions
						-- Try pathing again
						self.minerbotPathingState:sv_setDestination( self:calculateFiringPosition( self.lastTargetPosition, false ) )
						self.currentState = self.minerbotPathingState
						self.lastTargetPosition = nil
					else
						-- Lost the target
						-- Look around
						self.currentState = self.lookAroundState
					end
				else
					-- Just started combat or finished lookAroundState or minerbotBarrageState
					if self.currentState == self.minerbotBarrageState then
						local lastAttackedPosition = self.minerbotBarrageState:sv_getLastAttackedPosition()
						if lastAttackedPosition then
							-- Move in on last attacked position
							self.minerbotPathingState:sv_setDestination( self:calculateFiringPosition( lastAttackedPosition, true ) )
							self.currentState = self.minerbotPathingState
						else
							-- Look at last target location (fallback if minerbotBarrageState has been aborted)
							local lookAtDirection = self.unit.character.direction
							if self.lookAtLocation then
								local fromTo = self.lookAtLocation - self.unit.character.worldPosition
								local flatFromTo = sm.vec3.new( fromTo.x, fromTo.y, 0 )
								lookAtDirection = flatFromTo:safeNormalize( lookAtDirection )
							end
							self.lookAtTargetState.desiredDirection = lookAtDirection
							self.currentState = self.lookAtTargetState
						end
					elseif self.lastTargetPosition then
						-- Pathing to firing position
						self.minerbotPathingState:sv_setDestination( self:calculateFiringPosition( self.lastTargetPosition, true ) )
						self.currentState = self.minerbotPathingState
						self.lastTargetPosition = nil
					else
						-- No target, or close to last seen position
						-- Look around state
						self.currentState = self.lookAroundState
						self.lastTargetPosition = nil
					end
				end
			else
				-- NonCombat states
				if self.alert then
					self.alertEventState:sv_setTargetPosition( nil )
					self.currentState = self.calmEventState
					self.alert = false
				elseif self.wasInCombat or atReturnHomeDistance then
					self.wasInCombat = false
					-- Pathing home
					self.minerbotPathingState:sv_setDestination( self.homePosition )
					self.currentState = self.minerbotPathingState
				elseif isAnyOf( self.currentState, { self.idleState, self.minerbotDiggingIdleState, self.minerbotRoamingState, self.patrolState } ) then
					if heardNoise then
						self.currentState = self.lookAtNoiseState
					elseif canPatrol then
						self.currentState = self.patrolState
					else
						if self.saved.stationary then
							self.currentState = self.minerbotDiggingIdleState
						else
							self.currentState = self.minerbotRoamingState
						end
					end
				else
					if self.saved.stationary then
						self.currentState = self.minerbotDiggingIdleState
					else
						self.currentState = self.idleState
					end
				end
			end
		end
	end

	if prevState ~= self.currentState then
		prevState:stop()
		self.currentState:start()
	end
end

function MinerbotUnit.calculateFiringPosition( self, targetPosition, useWaypoints )

	local firingPosition = targetPosition

	-- TODO distance check?
	local waypoint = nil
	if useWaypoints then
		-- Find a node close to the targetPosition
		waypoint = MinerbotWaypointManager.Sv_GetWaypoint( targetPosition, self.unit.character:getWorld() )
	end
	if waypoint then
		firingPosition = waypoint.position
	else
		-- Fallback option
		-- Find a position close to the targetPosition that can fire at the targetPosition
		local fromTargetToSelf = self.unit.character.worldPosition - targetPosition
		local flatFromTargetToSelf = sm.vec3.new( fromTargetToSelf.x, fromTargetToSelf.y, 0 ):safeNormalize( sm.vec3.new( 0, 1, 0 ) )
		local fromTargetToSelfRight = flatFromTargetToSelf:cross( sm.vec3.new( 0, 0, 1 ) )
		local direction = flatFromTargetToSelf:rotate( math.rad( DesiredFiringAngle ), fromTargetToSelfRight )
		local testDestination = targetPosition + direction * DesiredFiringDistanceMax

		-- Test from target to firing position
		local hit, result = sm.physics.spherecast( targetPosition, testDestination, 0.25, self.unit.character, sm.physics.filter.static )
		if hit then
			firingPosition = result.pointWorld - result.directionWorld:safeNormalize( sm.vec3.zero() ) * self.unit.character:getRadius()
		else
			local middleDistance = ( DesiredFiringDistanceMin + ( DesiredFiringDistanceMax - DesiredFiringDistanceMin ) * 0.5 ) + self.middleDistanceVariance
			firingPosition = targetPosition + direction * middleDistance
		end
	end

	return firingPosition
end

function MinerbotUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
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
		if damage > 0 then
			if type( attacker ) == "Player" then
				g_ambienceManager:triggerCombatMusic()
			end

			if self.eventTarget == nil then
				if type( attacker ) == "Player" or type( attacker ) == "Unit" then
					self.eventTarget = attacker:getCharacter()
				elseif type( attacker ) == "Shape" then
					self.eventTarget = attacker
				end
			end
		end
		local impact = hitVelocity:normalize() * 6
		self:sv_hitReaction( impact )
		self:sv_takeDamage( damage, impact, hitPos )
	end
end

function MinerbotUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
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
		if self.eventTarget == nil then
			self.eventTarget = attackingCharacter
		end

		local impact = hitDirection * 6
		self:sv_hitReaction( impact )
		self:sv_takeDamage( damage, impact, hitPos )
	end
end

function MinerbotUnit.server_onExplosion( self, center, destructionLevel )
	if not sm.exists( self.unit ) then
		return
	end
	local impact = ( self.unit:getCharacter().worldPosition - center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) ) * 6
	self:sv_hitReaction( impact )
	self:sv_takeDamage( self.saved.stats.maxhp * ( destructionLevel / 10 ), impact, self.unit:getCharacter().worldPosition )
end

function MinerbotUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if not sm.exists( self.unit ) then
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
		if not sm.exists( other ) then
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
		print("'MinerbotUnit' took", damage, "collision damage")
		self:sv_takeDamage(damage, collisionNormal, collisionPosition)

		--Achievement check
		if self.saved.stats.hp <= 0 then
			RoadRageAchievementCheck( other )
		end
	end
end

function MinerbotUnit.server_onCollisionCrush( self )
	if not sm.exists( self.unit ) then
		return
	end
	onCrush( self )
end

function MinerbotUnit.sv_e_hitHead( self, params )
	local impact = params.hitVelocity:safeNormalize( sm.vec3.zero() ) * 6
	self:sv_takeDamage( params.damage, impact, params.hitPos )
	if self.eventNoisePosition == nil then
		-- "Hear" attacker
		self.eventNoisePosition = params.hitPos
	end
	self.unit:sendCharacterEvent( "hithead" )
end

function MinerbotUnit.sv_updateCharacterTarget( self )
	if self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_e_updateTarget", { target = self.target } )
	end
end

function MinerbotUnit.sv_hitReaction( self, impact )
	-- Hit reaction
	local characterDirection = self.unit.character.direction
	local hitNormal = ( -impact ):safeNormalize( characterDirection )
	local angleDeterminant = characterDirection.x * hitNormal.y - characterDirection.y * hitNormal.x
	if angleDeterminant >= FLT_EPSILON then
		self.unit:sendCharacterEvent( "hitright" )
	else
		self.unit:sendCharacterEvent( "hitleft" )
	end
end

function MinerbotUnit.sv_takeDamage( self, damage, impact, hitPos, source )
	if damage > 0 then
		if self.saved.stats.hp > 0 then
			self.saved.stats.hp = self.saved.stats.hp - damage
			self.saved.stats.hp = math.max( self.saved.stats.hp, 0 )
			--print( "'MinerbotUnit' received:", damage, "damage.", self.saved.stats.hp, "/", self.saved.stats.maxhp, "HP" )

			if self.unit.character then
				sm.event.sendToCharacter( self.unit.character, "sv_e_updateDamage", { damage = self.saved.stats.hp / self.saved.stats.maxhp } )
			end

			local effectRotation = sm.quat.identity()
			if hitPos and impact and impact:length() >= FLT_EPSILON then
				effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -impact:normalize() )
			end
			local currentTick = sm.game.getCurrentTick()
			if source ~= "plasma" or not self.lastPlasmaDrillEffectTick or currentTick - self.lastPlasmaDrillEffectTick >= PLASMA_BOT_HIT_EFFECT_TICK_THRESHOLD then
				self.lastPlasmaDrillEffectTick = currentTick
				sm.effect.playEffect( "Minerbot - Spudgunimpact", hitPos, nil, effectRotation )
			end

			if self.saved.stats.hp <= 0 then
				self:sv_prepareSelfdestruct()
			else
				self.storage:save( self.saved )
			end
		elseif self.selfdestructTickTimestamp and sm.game.getCurrentTick() >= self.selfdestructTickTimestamp + SelfdestructVulnerableTickDelay then
			self:sv_onDeath()
		end
	end
end

function MinerbotUnit.sv_prepareSelfdestruct( self )
	self.selfdestructTickTimestamp = sm.game.getCurrentTick()
	if self.target then
		self.minerbotSelfdestructState:sv_setTarget( self.target )
	elseif self.lastTargetPosition then
		self.minerbotSelfdestructState:sv_setTargetPosition( self.lastTargetPosition )
	elseif self.eventTarget then
		self.minerbotSelfdestructState:sv_setTarget( self.eventTarget )
	end
	self.currentState:stop()
	self.currentState = self.minerbotSelfdestructState
	self.currentState:start()

	local minerbotCharacter = self.unit.character
	local color = minerbotCharacter:getColor()
	local directionfixRot = sm.quat.angleAxis( math.rad( 180 ), sm.vec3.new( 0, 1, 0 ) )
	local leftBonePos = minerbotCharacter:getTpBonePos( "l_thruster_spawn_jnt" )
	local leftBoneRot = minerbotCharacter:getTpBoneRot( "l_thruster_spawn_jnt" )
	local thrusterLeft = sm.shape.createPart( obj_robotparts_minerbot_thruster, leftBonePos, leftBoneRot * directionfixRot )
	thrusterLeft.color = color
	local rightBonePos = minerbotCharacter:getTpBonePos( "r_thruster_spawn_jnt" )
	local rightBoneRot = minerbotCharacter:getTpBoneRot( "r_thruster_spawn_jnt" )
	local thrusterRight = sm.shape.createPart( obj_robotparts_minerbot_thruster, rightBonePos, rightBoneRot * directionfixRot )
	thrusterRight.color = color
end

local LootSources1 = {
	{ lootSource = "lootsource_minerbot_t1", weight = 1 },
	{ lootSource = "lootsource_minerbot_t2", weight = 1 },
	{ lootSource = "lootsource_minerbot_t3", weight = 1 },
	{ lootSource = "lootsource_minerbot_mixed1", weight = 1 }
}

local LootSources2 = {
	{ lootSource = "lootsource_minerbot_t2", weight = 1 },
	{ lootSource = "lootsource_minerbot_t3", weight = 1 },
	{ lootSource = "lootsource_minerbot_t4", weight = 1 },
	{ lootSource = "lootsource_minerbot_t5", weight = 0.5 },
	{ lootSource = "lootsource_minerbot_mixed2", weight = 1 }
}

function MinerbotUnit.sv_onDeath( self )
	local character = self.unit:getCharacter()
	if not self.destroyed then
		self.saved.stats.hp = 0
		self.unit:destroy()
		-- Create explosion
		sm.physics.explode( character.worldPosition, 1, 4.0, 12.0, 40, nil, nil, nil, nil, 35, self.unit.character, self.unit.character:getCharacterType() )

		-- Play explosion effect aligned with character direction
		local forward = sm.vec3.new( 0, 1, 0 )
		local characterDirection = sm.vec3.new( self.unit.character.direction.x, self.unit.character.direction.y, 0 ):safeNormalize( forward )
		local rotationRadians = math.acos( clamp( forward:dot( characterDirection ), -1, 1 ) )
		local rotationDeterminant = ( forward.x * characterDirection.y - forward.y * characterDirection.x )
		if rotationDeterminant < 0 then
			rotationRadians = -rotationRadians
		end
		local effectRotation = sm.quat.angleAxis( math.rad( 180 ) + rotationRadians, sm.vec3.new( 0, 0, 1 ) )
		sm.effect.playEffect( "Minerbot - Explosion", character.worldPosition, nil, effectRotation )
		sm.effect.playEffect( "Minerbot - Parts", character.worldPosition, nil, effectRotation, nil, { Color = character:getColor() } )

		self.unit:sendCharacterEvent( "death" )
		if SurvivalGame then
			local lootSources = nil
			local pubData = self.unit.character.world.publicData
			if pubData and pubData.depth and pubData.depth >= 6 then
				lootSources = LootSources2
			else
				lootSources = LootSources1
			end
			local loot
			local totalWeight = 0
			for _, v in ipairs( lootSources ) do
				totalWeight = totalWeight + ( v.weight or 1 )
			end
			local randomValue = math.random() * totalWeight
			totalWeight = 0
			for _, v in ipairs( lootSources ) do
				totalWeight = totalWeight + ( v.weight or 1 )
				if randomValue <= totalWeight then
					loot = SelectLoot( v.lootSource, nil, self.saved.lootType )
					break
				end
			end
			if loot then
				SpawnLoot( self.unit, loot )
			end
		end
		BaseUnit.sv_onDeath( self )
		self.destroyed = true
	end
end
