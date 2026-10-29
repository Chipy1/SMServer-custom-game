dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Ticker.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/BaseUnit.lua"
dofile "$SURVIVAL_DATA/Scripts/game/managers/PatrolManager.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PatrolState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/TapebotRangedState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/RangedRaidPathingState.lua"

TapebotUnit = class( BaseUnit )

local AllyRange = 20.0
local SuppressionFireTickTime = 4 * 40
local RandomRaidFireTickIntervalMin = 0 * 40
local RandomRaidFireTickIntervalMax = 2 * 40
local HearRange = 40.0
local SwimSelfdestructTickTime = 40 * 8.0

local RepositionTickDelay = 40 * 10
local RepositionTickDuration = 40 * 2

local StationaryWallHackTickDuration = 40 * 5 -- Continue tracking target for 5 seconds after losing sight

function TapebotUnit.server_onCreate( self )
	self.target = nil
	self.previousTarget = nil
	self.wallHackTarget = nil
	self.lastTargetPosition = nil
	self.ambushPosition = nil
	self.stationaryWallHackStart = 0
	
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.stats == nil then
		self.saved.stats = { hp = 40, maxhp = 40 }
	end

	self.isDirty = false

	InitRobotParams( self )
	if self.saved.patrolling == nil then
		self.saved.patrolling = true
	end
	self.storage:save( self.saved )

	sm.message.subscribe( MESSAGE_TYPES.GENERAL.ProjectileHit, "sv_m_projectileHit" )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.ProjectileFire, "sv_m_projectileFire" )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.Collision, "sv_m_collision" )

	self.robotModel = "standard"
	if self.data then
		if self.data.robotModel then
			self.robotModel = self.data.robotModel
		end
	end
	self.projectileBreachLevel = TAPEBOT_MODEL_SETTINGS[self.robotModel].projectileBreachLevel

	-- Lower the attack range if the projectiles are slow
	local maxProjectileVelocity = TAPEBOT_MODEL_SETTINGS[self.robotModel].projectileVelocity
	local maxRange = maxProjectileVelocity * maxProjectileVelocity * math.sin( 2 * math.rad( 45 ) ) / GRAVITY
	local rangeMargin = 5
	self.attackRange = math.min( 40.0, math.max( rangeMargin, maxRange - rangeMargin ) )
	self.fireLaneWidth = 0.6
	self.predictedVelocity = sm.vec3.new( 0, 0, 0 )
	self.isRanged = true

	self.unit.eyeHeight = self.unit.character:getHeight() * 0.75
	self.unit.visionFrustum = {
		{ 16.0, math.rad( 80.0 ), math.rad( 50.0 ) },
		{ 26.0, math.rad( 40.0 ), math.rad( 35.0 ) },
		{ 40.0, math.rad( 20.0 ), math.rad( 20.0 ) }
	}
	self.unit:setWhiskerData( 4, math.rad( 70.0 ), 1.0, 4.75 )
	self.noiseScale = 1.0
	self.impactCooldownTicks = 0
	
	self.isInCombat = false
	self.combatTimer = Timer()
	self.combatTimer:start( 40 * 12 )
	if self.params then
		self.spawnTick = sm.game.getCurrentTick()
	end
	
	-- Idle	
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"
	
	-- Roam
	self.roamStartTimeMin = 40 * 4 -- 4 seconds
	self.roamStartTimeMax = 40 * 8 -- 8 seconds
	self.roamTimer = Timer()
	self.roamTimer:start( math.random( self.roamStartTimeMin, self.roamStartTimeMax ) )
	self.roamState = PathingState()
	self.roamState:sv_onCreate( self.unit )
	self.roamState:sv_setMovementType( "walk" )
	self.roamState:sv_setTolerance( 1.5 )
	self.roamState.debugName = "roam"
	self.roamState:sv_setWaterAvoidance( true )
	
	--LookPositioning
	self.positioning = self.unit:createState( "positioning" )
	self.positioning.tolerance = 0.5
	self.positioning.debugName = "positioning"
	
	-- Pathing
	self.pathingState = PathingState()
	self.pathingState:sv_onCreate( self.unit )
	self.pathingState:sv_setMovementType( "sprint" )
	self.pathingState.debugName = "pathingState"
	self.pathingState:sv_setWaterAvoidance( true )

	-- Raid Pathing
	self.raidPathingState = RangedRaidPathingState()
	self.raidPathingState:sv_onCreate( self.unit )
	self.raidPathingState:sv_setMovementType( "walk" )
	self.raidPathingState:sv_setTargetDistance( self.attackRange * 0.7 )
	self.raidPathingState:sv_setRaidPoint( self.saved.raidCenter )
	self.raidPathingState.debugName = "raidPathingState"
	self.raidPathingState:sv_setWaterAvoidance( true )

	-- RangedAttack
	self.rangedAttack = TapebotRangedState()
	self.rangedAttack:sv_onCreate( self.unit, self.robotModel )
	self.rangedAttack:sv_setSpawnTick( self.spawnTick )
	self.rangedAttack.debugName = "rangedAttack"
	
	self.suppressionFireTimer = Timer()
	self.suppressionFireTimer:start( SuppressionFireTickTime )
	self.suppressionFireTimer.count = SuppressionFireTickTime

	self.randomRaidFireTimer = Timer()
	self.randomRaidFireTimer:start( math.random( RandomRaidFireTickIntervalMin, RandomRaidFireTickIntervalMax ) )

	-- LookAt
	self.lookAtState = self.unit:createState( "positioning" )
	self.lookAtState.debugName = "lookAt"
	self.lookAtState.timeout = 3.0
	self.lookAtState.tolerance = 0.5
	self.lookAtState.avoidance = false
	self.lookAtState.movementType = "stand"

	-- Guard
	self.guardState = self.unit:createState( "positioning" )
	self.guardState.debugName = "guard"
	self.guardState.timeout = 3.0
	self.guardState.tolerance = 0.1
	self.guardState.avoidance = false
	self.guardState.movementType = "stand"
	
	-- Raid reposition
	self.raidRepositionState = self.unit:createState( "followDirection" )
	self.raidRepositionState.debugName = "raidReposition"
	self.raidRepositionState.movementType = "walk"
	self.raidRepositionState.avoidance = true
	self.raidRepositionTimer = Timer()
	self.raidRepositionTimer:start( RepositionTickDuration )

	self.raidGuardRepositionTimer = Timer()
	self.raidGuardRepositionTimer:start( RepositionTickDelay )

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

	self.swimSelfdestructTimer = Timer()
	self.swimSelfdestructTimer:start( SwimSelfdestructTickTime )

	-- Tumble
	initTumble( self )
	
	-- Crushing
	initCrushing( self, DEFAULT_CRUSH_TICK_TIME )
	
	if self.saved.stationary and self.saved.guardDirection then
		self.guardState.desiredDirection = self.saved.guardDirection
	end

	if not self.saved.raider then
		self.currentState = self.idleState
	else
		self.currentState = self.raidPathingState
	end
	self.currentState:start()
end

function TapebotUnit.server_onRefresh( self )
end

function TapebotUnit.server_onFixedUpdate( self, dt )
	BaseUnit.server_onFixedUpdate( self )
	if not sm.exists( self.unit ) then
		return
	end
	
	if updateCrushing( self ) then
		self:sv_onDeath( sm.vec3.new( 0, 0, 0 ) )
	end
	
	updateTumble( self )
	updateAirTumble( self, self.idleState )
	
	if self.currentState then
		if self.saved.raider and self.currentState == self.guardState then
			self.raidGuardRepositionTimer:tick()
		elseif self.saved.raider and self.currentState == self.raidRepositionState then
			self.raidRepositionTimer:tick()
		end

		self.canShootTarget = self:updateAim( dt )
		self.currentState:onFixedUpdate( dt )
		if self.unit.character:isSwimming() then
			self.swimSelfdestructTimer:tick()
			if not self.unit.character:isTumbling() then
				startTumble( self, SwimSelfdestructTickTime, self.idleState )
			end
			if self.swimSelfdestructTimer:done() then
				self:sv_onDeath( sm.vec3.new( 0, 0, 1 ) )
				self.swimSelfdestructTimer:stop()
			end
		else
			self.swimSelfdestructTimer:reset()
		end
	
		local raidWalk = self.saved.raider and self.target == nil and ( self.currentState == self.pathingState or self.currentState == self.raidPathingState )
		if self.currentState == self.guardState then
			self.unit:setMovementDirection( self.saved.guardDirection or self.currentState:getMovementDirection() )
		else
			self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		end
		self.unit:setMovementType( raidWalk and "walk" or self.currentState:getMovementType() )
		self.unit:setFacingDirection( self.currentState:getFacingDirection() )
		
		if self.currentState == self.idleState then
			self.roamTimer:tick()
		end
		
		if self.isInCombat then
			self.combatTimer:tick()
		end

		if not self.suppressionFireTimer:done() then
			self.suppressionFireTimer:tick()
		end

		if ( self.saved.raider or g_unitManager:sv_getHostSettings().aggroCreations ) and self.currentState ~= self.rangedAttack and self.target == nil and self.suppressionFireTimer:done() then
			self.randomRaidFireTimer:tick()
			if self.randomRaidFireTimer:done() then
				local attackableShape, attackPosition = FindAttackableShape( self.unit.character.worldPosition, self.attackRange, self.projectileBreachLevel )
				if attackableShape and attackPosition then
					self.rangedAttack:sv_setAimPoint( attackPosition )
					self.suppressionFireTimer:reset()
				end
				self.randomRaidFireTimer:start( math.random( RandomRaidFireTickIntervalMin, RandomRaidFireTickIntervalMax ) )
			end
		end
		
		self.impactCooldownTicks = math.max( self.impactCooldownTicks - 1, 0 )
	end
	
	if self.saved.stationary and TAPEBOT_MODEL_SETTINGS[self.robotModel].stationaryWallHack then
		if self.target == nil and self.previousTarget ~= nil and self.wallHackTarget == nil then
			self.wallHackTarget = self.previousTarget
			self.stationaryWallHackStart = sm.game.getCurrentTick()
		end
		if self.wallHackTarget and sm.exists( self.wallHackTarget ) then
			if sm.game.getCurrentTick() - self.stationaryWallHackStart <= StationaryWallHackTickDuration then
				return
			else
				self.wallHackTarget = nil
				self.target = nil
			end
		end
	end
	-- Update target for character
	if self.target ~= self.previousTarget then
		self:sv_updateCharacterTarget()
		self.previousTarget = self.target
	end
	if self.isDirty then
		self.storage:save( self.saved )
		self.isDirty = false
	end
end

function TapebotUnit.updateAim( self, dt )
	if self.target and sm.exists( self.target ) and type( self.target ) == "Character" and not self.target:isDowned() then
		local success, aimPoint = sm.ai.getAimPosition( self.unit.character, self.target, self.attackRange, self.fireLaneWidth, self.projectileBreachLevel )
		if success then
			self.wallHackTarget = nil
		end
		if success or self.wallHackTarget then
			if self.wallHackTarget then
				aimPoint = self.wallHackTarget.worldPosition
			end
			-- Predict target movement from its velocity
			if self.predictedVelocity:length() > 0 and self.target:getVelocity():length() > self.predictedVelocity:length() then
				self.predictedVelocity = magicPositionInterpolation( self.predictedVelocity, self.target:getVelocity(), dt, 1.0 / 10.0 )
			else
				self.predictedVelocity = self.target:getVelocity()
			end
			local distanceToTarget = ( aimPoint - self.unit.character.worldPosition ):length()
			local predictionScale = distanceToTarget / math.max( TAPEBOT_MODEL_SETTINGS[self.robotModel].projectileVelocity, 1.0 )
			self.rangedAttack:sv_setAimPoint( aimPoint + self.predictedVelocity * predictionScale )
			return true
		end
	elseif self.target and sm.exists( self.target ) and type( self.target ) == "Harvestable" then
		local success, aimPoint = sm.ai.getAimPosition( self.unit.character, self.target, self.attackRange, self.fireLaneWidth )
		if success then
			self.rangedAttack:sv_setAimPoint( aimPoint )
			return true
		end
	end
	return false
end

function TapebotUnit.server_onCharacterChangedColor( self, color )
	if self.saved.color ~= color then
		self.saved.color = color
		self.storage:save( self.saved )
	end
end

function TapebotUnit.server_onUnitUpdate( self, dt )
	
	if not sm.exists( self.unit ) then
		return
	end
	
	if self.unit.character:isTumbling() then
		return
	end
	
	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end

	if CheckFleeFromRaid( self ) then
		return
	end

	RobotSelectTarget( self, AllyRange, dt )
	if self.target == nil and sm.exists( self.wallHackTarget ) then
		self.target = self.wallHackTarget
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

	local targetingPlayer = type( self.target ) == "Character" and self.target:isPlayer()
	local prevState = self.currentState
	local prevInCombat = self.isInCombat
	if targetingPlayer or self.lastTargetPosition or not self.suppressionFireTimer:done() then
		self.isInCombat = true
		self.combatTimer:reset()
	end
	if self.combatTimer:done() then
		self.isInCombat = false
	end
	
	-- Update pathingState destination
	if self.currentState == self.pathingState then
		if self.target then
			local currentTargetPosition = self.target.worldPosition
			if type( self.target ) == "Harvestable" then
				currentTargetPosition = self.target.worldPosition + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 )
			end
			self.pathingState:sv_setDestination( currentTargetPosition )
		elseif self.lastTargetPosition then
			self.pathingState:sv_setDestination( self.lastTargetPosition )
		end
	end

	local canPatrol
	if self.saved.patrolKey then
		canPatrol = PatrolManager.Sv_IsPatrolActive( self.saved.patrolKey )
	end

	local done, result = self.currentState:isDone()
	local abortState = 	( ( self.currentState == self.pathingState or self.currentState == self.roamState or self.currentState == self.guardState or self.currentState == self.raidPathingState or self.currentState == self.raidRepositionState ) and self.canShootTarget and self.isInCombat ) or
						( prevInCombat and self.combatTimer:done() ) or
						( not self.suppressionFireTimer:done() ) or
						( self.currentState == self.lookAtState and self.isInCombat ) or
						( self.currentState == self.roamState and heardNoise ) or
						( self.currentState == self.guardState and self.isInCombat ) or
						( self.raidGuardRepositionTimer:done() ) or
						( self.raidRepositionTimer:done() )
	if done or abortState then
		if self.unit.character:isSwimming() then
			self.currentState = self.idleState
		elseif self.saved.raider and self.currentState == self.raidRepositionState then
			if self.raidRepositionTimer:done() then
				self.raidRepositionTimer:reset()
				self.guardState.desiredDirection = ( self.saved.raidCenter - self.unit.character.worldPosition ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
				self.guardState.desiredPosition = self.saved.raidCenter
				self.currentState = self.guardState
			else
				self.currentState = self.raidRepositionState
			end
		elseif self.saved.raider and self.currentState == self.guardState and self.raidGuardRepositionTimer:done() then
			self.raidGuardRepositionTimer:reset()
			self.currentState = self.raidRepositionState
			local degrees = math.random() > 0.5 and 80 or -80
			self.raidRepositionState.desiredDirection = ( self.saved.raidCenter - self.unit.character.worldPosition ):safeNormalize( sm.vec3.new( 1, 0, 0 ) ):rotateZ( math.rad( degrees ) )
		elseif self.saved.raider and self.currentState == self.guardState and ( self.unit.character.worldPosition - self.saved.raidCenter ):length2() > ( self.attackRange^2 ) then
			self.currentState = self.raidPathingState
		elseif self.saved.raider and self.currentState == self.idleState then
			self.currentState = self.raidPathingState
		elseif self.currentState == self.pathingState and result == "failed" then
			self.lookAtState.desiredDirection = -self.unit.character.direction
			self.lookAtState.desiredPosition = self.unit.character.worldPosition
			self.currentState = self.lookAtState
			self.isInCombat = false
			self.roamTimer:start( math.random( self.roamStartTimeMin, self.roamStartTimeMax ) )
		elseif self.currentState == self.raidPathingState then
			if done then
				self.guardState.desiredDirection = ( self.saved.raidCenter - self.unit.character.worldPosition ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
				self.guardState.desiredPosition = self.saved.raidCenter
				self.currentState = self.guardState
				self.isInCombat = false
			end
		elseif self.isInCombat then
			-- Select combat state
			if not self.suppressionFireTimer:done() then
				self.currentState = self.rangedAttack
			elseif self.target then
				if self.canShootTarget then
					-- Attack towards target character
					self.currentState = self.rangedAttack
					if type( self.target ) == "Character" and self.target:isPlayer() then
						self.suppressionFireTimer:reset()
					end
				else
					-- Pathing towards target character
					if self.currentState ~= self.pathingState then
						self.pathingState:sv_setDestination( self.target.worldPosition )
					end
					if self.saved.raider then
						self.currentState = self.guardState
					elseif not self.saved.stationary then
						self.currentState = self.pathingState
					else
						self.guardState.desiredDirection = self.saved.guardDirection
						self.isInCombat = false
						self.currentState = self.guardState
					end
				end
			elseif self.lastTargetPosition then
				if self.currentState ~= self.pathingState then
					self.pathingState:sv_setDestination( self.lastTargetPosition )
				end
				if self.saved.raider then
					self.currentState = self.guardState
				elseif not self.saved.stationary then
					if not self.saved.raider then
						self.currentState = self.pathingState
					elseif self.target and sm.exists( self.target ) then
						self.currentState = self.raidPathingState
					end
				else
					self.guardState.desiredDirection = self.saved.guardDirection
					self.isInCombat = false
					self.currentState = self.guardState
				end
				self.lastTargetPosition = nil
			else
				-- Wait for deaggro or the next attack
				self.positioning.desiredPosition = self.unit.character.worldPosition
				self.positioning.desiredDirection = self.unit.character.direction
				self.currentState = self.positioning
			end
		else
			-- Select non-combat state
			if self.saved.stationary then
				self.currentState = self.guardState
			elseif heardNoise then
				self.currentState = self.lookAtState
				self.roamTimer:start( math.random( self.roamStartTimeMin, self.roamStartTimeMax ) )
			elseif canPatrol then
				self.currentState = self.patrolState
			elseif self.roamTimer:done() and not ( self.currentState == self.idleState and result == "started" ) then
				self.roamTimer:start( math.random( self.roamStartTimeMin, self.roamStartTimeMax ) )
				if self.saved.patrolling then
					local validPositions = {}
					if self.currentState ~= self.roamState and self.currentState ~= self.positioningState then
						-- Look for roam position near home
						local nodes = sm.pathfinder.getSortedNodes( self.homePosition, 2, 16 )
						if nodes and #nodes > 0 then
							for _, node in ipairs( nodes ) do
								local path = sm.pathfinder.getPath( self.unit.character, node:getPosition() )
								if #path > 0 then
									validPositions[#validPositions+1] = node:getPosition()
								end
							end
						end

						if #validPositions == 0 then
							-- Look for roam position near self
							local nodes = sm.pathfinder.getSortedNodes( self.unit.character.worldPosition, 2, 16 )
							if nodes and #nodes > 0 then
								for _, node in ipairs( nodes ) do
									local path = sm.pathfinder.getPath( self.unit.character, node:getPosition() )
									if #path > 0 then
										validPositions[#validPositions+1] = node:getPosition()
									end
								end
							end
						end
					end
					if #validPositions > 0 then
						self.roamState:sv_setDestination( validPositions[math.random(1, #validPositions)] )
						self.currentState = self.roamState
					elseif self.currentState ~= self.roamState and self.currentState ~= self.positioningState then
						self.positioning.desiredPosition = self.unit.character.worldPosition
						self.positioning.desiredDirection = self.unit.character.direction:rotateZ( math.random() * 2 * math.pi )
						self.currentState = self.positioning
					end
				else
					self.positioning.desiredPosition = self.unit.character.worldPosition
					self.positioning.desiredDirection = self.unit.character.direction:rotateZ( math.random() * 2 * math.pi )
					self.currentState = self.positioning
				end
			elseif not ( self.currentState == self.roamState and result == "roaming" ) then
				self.currentState = self.idleState
			end
		end
		
	end

	if prevState ~= self.currentState then
		local calmStates = {
			self.idleState,
			self.roamState,
			self.positioning
		}
		local wasCalm = isAnyOf( prevState, calmStates )
		local isCalm = isAnyOf( self.currentState, calmStates )

		if wasCalm and not isCalm then
			self.unit:sendCharacterEvent( "alerted" )
		elseif not wasCalm and isCalm then
			self.unit:sendCharacterEvent( "roaming" )
		end

		prevState:stop()
		self.currentState:start()
	end
	
end

function TapebotUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if not sm.exists( self.unit ) or not sm.exists( attacker ) then
		return
	end
	local teamOpponent = false
	if type( attacker ) == "Unit" then
		if not SurvivalGame then
			teamOpponent = not InSameTeam( attacker, self.unit )
		end
	end

	if type( attacker ) == "Player" or ( type( attacker ) == "Shape" and not isTrapProjectile( projectileUuid ) ) or teamOpponent then
		if damage > 0 then
			if self.eventTarget == nil then
				if type( attacker ) == "Player" or type( attacker ) == "Unit" then
					self.eventTarget = attacker:getCharacter()
					if self.saved.stationary then
						self.target = attacker:getCharacter()
						self.currentState = self.rangedAttack
					end
				elseif type( attacker ) == "Shape" then
					self.eventTarget = attacker
				end
			end
		
			local ZAxis = sm.vec3.new( 0.0, 0.0, 1.0 )
			local impact = hitVelocity:normalize() * 6
			
			if type( attacker ) == "Player" then
				g_ambienceManager:triggerCombatMusic()
			end

			if self:nearHead( hitPos ) then
				sm.effect.playEffect( "TapeBot - HeadShot", hitPos, sm.vec3.zero(), sm.vec3.getRotation( ZAxis, hitVelocity:normalize() ) )
				self:sv_takeDamage( self.saved.stats.maxhp, impact )
			else
				if self.saved.stats.hp - damage > 0 then
					sm.effect.playEffect( "TapeBot - Hit", hitPos, sm.vec3.zero(), sm.vec3.getRotation( ZAxis, hitVelocity:normalize() ) )
				end
				self:sv_takeDamage( damage, impact )
			end
		end
	end
end

function TapebotUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
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
		local attackingCharacter = attacker:getCharacter()
		local ZAxis = sm.vec3.new( 0.0, 0.0, 1.0 )
		local impact = hitDirection * 6

		if self.currentState == self.staggeredEventState then
			ApplyKnockback( self.unit.character, hitDirection, power )
		end
		
		if self.eventTarget == nil then
			self.eventTarget = attackingCharacter
		end

		if self.saved.stats.hp - damage > 0 then
			sm.effect.playEffect( "TapeBot - Hit", hitPos, sm.vec3.zero(), sm.vec3.getRotation( ZAxis, hitDirection ) )
		end

		if type( attacker ) == "Player" then
			g_ambienceManager:triggerCombatMusic()
		end
		
		self:sv_takeDamage( damage, impact )
	end
end

function TapebotUnit.server_onExplosion( self, center, destructionLevel, radius, uDamage, src, srcTypeUid )
	if not sm.exists( self.unit ) then
		return
	end
	local impact = ( self.unit:getCharacter().worldPosition - center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) )
	self:sv_takeDamage( self.saved.stats.maxhp, impact, self.unit:getCharacter().worldPosition )
	if self.saved.stats.hp <= 0 then
		if src then
			if isAnyOf(self.unit.character:getCharacterType(),g_tapebots) then
				sm.achievement.pushToContext( "cornade_multikill", { dead = true, explosionType = srcTypeUid },{src:getId()} )
			end
		end
	end
end

function TapebotUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity,
										 collisionNormal )
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
		self:sv_takeDamage( damage, collisionNormal, collisionPosition )
		if self.saved.stats.hp <= 0 then
			--Achievement check
			RoadRageAchievementCheck( other )
		end
	end
	if tumbleTicks > 0 then
		if hitByRailKinematic then
			self:sv_takeDamage( self.saved.stats.maxhp, collisionNormal, collisionPosition )
		else
			if startTumble( self, tumbleTicks, self.idleState, tumbleVelocity ) then
				if type( other ) == "Shape" and sm.exists( other ) and other.body:isDynamic() then
					sm.physics.applyImpulse( other.body, impactReaction * other.body.mass, true, collisionPosition - other.body.worldPosition )
				end
			end
		end
	end
	
end

function TapebotUnit.server_onCollisionCrush( self )
	if not sm.exists( self.unit ) then
		return
	end
	onCrush( self )
end

function TapebotUnit.sv_updateCharacterTarget( self )
	if self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_n_updateTarget", { target = self.target } )
	end
end

function TapebotUnit.sv_takeDamage( self, damage, impact, hitPos, source )
	if self.saved.stats.hp > 0 and damage > 0 then
		self.saved.stats.hp = self.saved.stats.hp - damage
		self.saved.stats.hp = math.max( self.saved.stats.hp, 0 )
		if self.saved.stats.hp <= 0 then
			self:sv_onDeath( impact )
		else
			self.storage:save( self.saved )
			if hitPos then
				local effectRotation = sm.quat.identity()
				if impact and impact:length() >= FLT_EPSILON then
					effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -impact:normalize() )
				end
				local currentTick = sm.game.getCurrentTick()
				if source ~= "plasma" or not self.lastPlasmaDrillEffectTick or currentTick - self.lastPlasmaDrillEffectTick >= PLASMA_BOT_HIT_EFFECT_TICK_THRESHOLD then
					self.lastPlasmaDrillEffectTick = currentTick
					sm.effect.playEffect( "TapeBot - Hit", hitPos, sm.vec3.zero(), effectRotation )
				end
			end
		end
	end
end

function TapebotUnit.sv_onDeath( self, impact )
	local character = self.unit:getCharacter()
	if not self.destroyed then
		self.saved.stats.hp = 0
		self.unit:destroy()
		self:sv_spawnParts( impact )
		self.unit:sendCharacterEvent( "death" )
		if SurvivalGame then
			local loot = SelectLoot( TAPEBOT_MODEL_SETTINGS[self.robotModel].loot, nil, self.saved.lootType )
			SpawnLoot( self.unit, loot )
		end
		BaseUnit.sv_onDeath( self );
		self.destroyed = true
	end
end

function TapebotUnit.sv_spawnParts( self, impact )
	local character = self.unit:getCharacter()

	local lookDirection = character:getDirection()
	local bodyPos = character.worldPosition
	local bodyRot = sm.quat.identity()
	lookDirection = sm.vec3.new( lookDirection.x, lookDirection.y, 0 )
	if lookDirection:length() >= FLT_EPSILON then
		lookDirection = lookDirection:normalize()
		bodyRot = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), lookDirection  ) --Turn tapebot parts sideways
	end
	local bodyOffset = bodyRot * sm.vec3.new( -0.25, 0.25, 0.375 )
	bodyPos = bodyPos - bodyOffset

	local color = self.unit.character:getColor()
	local rightArmBody = sm.body.createBody( bodyPos, bodyRot, true )
	local rightArmShape = rightArmBody:createPart( ITEMS.obj_robotparts_tapebotshooter, sm.vec3.new( 1, 2, 0 ), sm.vec3.new( 0, 1, 0 ), sm.vec3.new( -1, 0, 0 ), true )
	sm.physics.applyImpulse( rightArmShape, impact * rightArmShape.mass, true )
	rightArmShape.interactable:setParams( { projectileUuid = TAPEBOT_MODEL_SETTINGS[self.robotModel].projectile, projectileDamage = TAPEBOT_MODEL_SETTINGS[self.robotModel].armPartDamage } )
	rightArmShape:setColor( color )
end

function TapebotUnit.nearHead( self, hitPos )
	return hitPos.z > self.unit:getCharacter().worldPosition.z + 0.25
end