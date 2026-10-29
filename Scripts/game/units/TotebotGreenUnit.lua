dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Ticker.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/BreachState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/CombatAttackState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/VoxelBreachState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/BaseTotebotUnit.lua"
dofile "$SURVIVAL_DATA/Scripts/game/managers/PatrolManager.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PatrolState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/LaunchAttackState.lua"

TotebotGreenUnit = class( BaseTotebotUnit )

local RoamStartTimeMin = 40 * 4 -- 4 seconds
local RoamStartTimeMax = 40 * 8 -- 8 seconds

local CombatAttackRange = 1.0 -- Range where the unit will perform attacks
local CombatApproachRange = 2.25 -- Range where the unit will approach the player without obstacle checking

local StaggerProjectile = 0.5
local StaggerMelee = 1.0
local StaggerCooldownTickTime = 1.65 * 40

local AllyRange = 20.0
local MeleeBreachLevel = 9

local HearRange = 40.0

local MaxHorizontalJumpDistanceSqr = 8.0 ^ 2
local MinHorizontalJumpDistanceSqr = 4.0 ^ 2
local MaxVerticalJumpDistance = 3.0
local JumpCooldownTickTime = 15 * 40
local JumpCounterHitForce = 600
local JumpChancePerSecond = 0.3

local VoxelDigRadius = 1.0
local VoxelDigStrength = 0.75

local NoJumpQuestBotDeathEvent = "event.quest_clear_ruins.defeat_unit" -- special case to prevent quest totebot from jumping off the ruins

function TotebotGreenUnit.server_onCreate( self )
	BaseTotebotUnit.server_onCreate( self )
	self.target = nil
	self.previousTarget = nil
	self.lastTargetPosition = nil
	self.ambushPosition = nil
	self.predictedVelocity = sm.vec3.new( 0, 0, 0 )
	self.isDirty = false
	self.jumpChancePerSecond = JumpChancePerSecond
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	
	if self.saved.stats == nil then
		if self.params and self.params.overrideHP then
			self.saved.stats = { hp = self.params.overrideHP, maxhp = self.params.overrideHP }
		else
			self.saved.stats = { hp = 40, maxhp = 40 }
		end
	end

	InitRobotParams( self )
	self.storage:save( self.saved )

	self.unit.eyeHeight = self.unit.character:getHeight() * 0.75
	self.unit.visionFrustum = {
		{ 3.0, math.rad( 80.0 ), math.rad( 80.0 ) },
		{ 20.0, math.rad( 40.0 ), math.rad( 35.0 ) },
		{ 40.0, math.rad( 20.0 ), math.rad( 20.0 ) }
	}
	self.unit:setWhiskerData( 3, math.rad( 60.0 ), 1.5, 5.0 )
	self.noiseScale = 1.0
	self.impactCooldownTicks = 0
	
	self.isInCombat = false
	self.combatTimer = Timer()
	self.combatTimer:start( 40 * 12 )

	self.stateTicker = Ticker()
	self.stateTicker:init()
	
	-- Idle	
	self.idleState = self.unit:createState( "idle" )
	self.idleState.randomEventCooldownMin = 3.0 -- tweak here dev values
	self.idleState.randomEventCooldownMax = 8.0 -- tweak here dev values
	self.idleState.randomEvents = { { name = "idlespecial01", chance = 0.4, interruptible = true, time = 6.4 },
									{ name = "idlespecial02", chance = 0.2, interruptible = true, time = 4.0 } }
	self.idleState.debugName = "idleState"
	
	-- Stagger
	self.staggeredEventState = self.unit:createState( "wait" )
	self.staggeredEventState.time = 0.25
	self.staggeredEventState.interruptible = false
	self.staggeredEventState.debugName = "staggeredEventState"
	self.stagger = 0.0
	self.staggerCooldownTicks = 0
	
	-- Roam
	self.roamTimer = Timer()
	self.roamTimer:start( math.random( RoamStartTimeMin, RoamStartTimeMax ) )
	self.roamState = self.unit:createState( "roam" )
	self.roamState.debugName = "roamState"
	self.roamState.tetherPosition = self.unit.character.worldPosition
	self.roamState.waterAvoidance = false
	self.roamState.roamCenterOffset = 0.0
	self.roamState.customData = { onUnitUpdateOnly = true }

	-- Pathing
	self.pathingState = PathingState()
	self.pathingState:sv_onCreate( self.unit )
	self.pathingState:sv_setTolerance( 1.0 )
	self.pathingState:sv_setMovementType( "sprint" )
	self.pathingState:sv_setWaterAvoidance( false )
	self.pathingState:sv_setRaider( self.saved.raider )
	self.pathingState.debugName = "pathingState"
	
	-- Attacks
	self.attackState01 = self.unit:createState( "meleeAttack" )
	self.attackState01.meleeType = melee_totebotattack
	self.attackState01.event = "melee"
	self.attackState01.damage = 15
	self.attackState01.attackRange = 1.15
	self.attackState01.animationCooldown = 0.825 * 40
	self.attackState01.attackCooldown = 1.0 * 40
	self.attackState01.globalCooldown = 0.0 * 40
	self.attackState01.attackDelay = 0.25 * 40
	self.attackState01.power = 3750.0
	
	-- Combat
	self.combatAttackState = CombatAttackState()
	self.combatAttackState:sv_onCreate( self.unit )
	self.stateTicker:addState( self.combatAttackState )
	self.combatAttackState:sv_addAttack( self.attackState01 )
	self.combatAttackState.debugName = "combatAttackState"

	-- Breach
	self.breachState = BreachState()
	self.breachState:sv_onCreate( self.unit, math.ceil( 40 * 2.0 ) )
	self.stateTicker:addState( self.breachState )
	self.breachState:sv_setBreachRange( CombatAttackRange )
	self.breachState:sv_setBreachLevel( MeleeBreachLevel )
	self.breachState:sv_addAttack( self.attackState01 )
	self.breachState.debugName = "breachState"

	-- Voxel Breach
	self.voxelBreachState = VoxelBreachState()
	self.voxelBreachState:sv_onCreate( self.unit, math.ceil( 40 * 3.0 ) )
	self.stateTicker:addState( self.voxelBreachState )
	self.voxelBreachState:sv_addAttack( self.attackState01 )
	self.voxelBreachState:sv_setDigRadius( VoxelDigRadius )
	self.voxelBreachState:sv_setDigStrength( VoxelDigStrength )
	self.voxelBreachState.debugName = "voxelBreachState"

	-- Combat approach
	self.combatApproachState = self.unit:createState( "positioning" )
	self.combatApproachState.debugName = "combatApproachState"
	self.combatApproachState.timeout = 0.5
	self.combatApproachState.tolerance = CombatAttackRange
	self.combatApproachState.avoidance = false
	self.combatApproachState.movementType = "sprint"
	self.combatApproachState.debugName = "combatApproachState"
	
	-- Avoid
	self.avoidState = self.unit:createState( "positioning" )
	self.avoidState.debugName = "avoid"
	self.avoidState.timeout = 1.5
	self.avoidState.tolerance = 0.5
	self.avoidState.avoidance = false
	self.avoidState.movementType = "walk"
	self.avoidState.debugName = "avoidState"
	
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

	-- Jump attack state
	self.launchAttackState = LaunchAttackState()
	self.launchAttackState:sv_onCreate( self.unit )
	self.launchAttackState:sv_setAttack( melee_totebot_jumpattack )
	self.launchAttackState.debugName = "launchAttackState"
	self.launchAttackState.lastJumpTick = -1
	self.launchAttackState.customData = { ignoreAirTumble = true }

	-- Tumble
	initTumble( self )
	
	-- Crushing
	initCrushing( self, DEFAULT_CRUSH_TICK_TIME )
	
	self.griefTimer = Timer()
	self.griefTimer:start( 40 * 9.0 )

	self.voxelBreachCooldownTicks = 0

	self.currentState = self.idleState
	self.currentState:start()
end

function TotebotGreenUnit.server_onDestroy( self )
	BaseUnit.server_onDestroy( self )
	if DEBUG_AI_STATES then
		sm.debugDraw.removeText( "unit_state_" .. self.unit.id )
	end
end

function TotebotGreenUnit.server_onRefresh( self )
end

function TotebotGreenUnit.server_onFixedUpdate( self, dt )
	-- Remove the unit when the death timestamp is reached
	BaseUnit.server_onFixedUpdate( self )

	if self.unit.character:isSwimming() then
		self.roamState.cliffAvoidance = false
		self.pathingState:sv_setCliffAvoidance( false )
	else
		self.roamState.cliffAvoidance = true
		self.pathingState:sv_setCliffAvoidance( true )
	end
	
	self.stateTicker:tick()
	
	if updateCrushing( self ) then
		self:sv_onDeath( sm.vec3.new( 0, 0, 0 ) )
	end
	
	updateTumble( self )
	if not self.currentState.customData or not self.currentState.customData.ignoreAirTumble then
		updateAirTumble( self, self.idleState )
	end
	
	self.griefTimer:tick()

	self.voxelBreachCooldownTicks = math.max( self.voxelBreachCooldownTicks - 1, 0 )

	if self.currentState then
		if self.target and not sm.exists( self.target ) then
			self.target = nil
		end

		-- Predict target velocity
		if self.target and type( self.target ) == "Character" then
			if self.predictedVelocity:length() > 0 and self.target:getVelocity():length() > self.predictedVelocity:length() then
				self.predictedVelocity = magicPositionInterpolation( self.predictedVelocity, self.target:getVelocity(), dt, 1.0 / 10.0 )
			else
				self.predictedVelocity = self.target:getVelocity()
			end
		else
			self.predictedVelocity = sm.vec3.new( 0, 0, 0 )
		end

		if not self.currentState.customData or not self.currentState.customData.onUnitUpdateOnly then
			self.currentState:onFixedUpdate( dt )
		end
		
		self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		self.unit:setMovementType( self.currentState:getMovementType() )
		self.unit:setFacingDirection( self.currentState:getFacingDirection() )
		
		-- Random roaming during idle
		if self.currentState == self.idleState then
			self.roamTimer:tick()
		end

		if self.isInCombat then
			self.combatTimer:tick()
		end

		self.staggerCooldownTicks = math.max( self.staggerCooldownTicks - 1, 0 )
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

function TotebotGreenUnit.server_onCharacterChangedColor( self, color )
	if self.saved.color ~= color then
		self.saved.color = color
		self.storage:save( self.saved )
	end
end

function TotebotGreenUnit.server_onUnitUpdate( self, dt )
	
	if not sm.exists( self.unit ) then
		return
	end
	
	if self.currentState then
		self.currentState:onUnitUpdate( dt )

		if self.currentState.customData and self.currentState.customData.onUnitUpdateOnly then
			self.currentState:onFixedUpdate( dt )
		end
	end
	
	if CheckFleeFromRaid( self ) then
		return
	end
	
	if self.unit.character:isTumbling() then
		return
	end

	RobotSelectTarget( self, AllyRange, dt )

	-- Raiders without a target search for shapes to destroy
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
			if self.lastTargetPosition == nil or ( self.lastTargetPosition - closestSpot ):length2() > ( RAIDER_TARGETING_RADIUS * 1.5 ) then
				local attackableShape, attackPosition = FindAttackableShape( closestSpot, RAIDER_TARGETING_RADIUS, MeleeBreachLevel )
				if attackableShape and attackPosition then
					self.lastTargetPosition = attackPosition
				elseif self.unit.character then
					self.pathingState:sv_setDestination( closestSpot )
					self.saved.raidPosition = closestSpot
					self.lastTargetPosition = closestSpot
				end
			end
		end
	end

	-- Units with destroyShape spawn param set will attack nearby shapes if they have no player to attack
	if self.saved.destroyShapes and not self.lastTargetPosition and not self.target then
		local attackableShape, attackPosition = FindAttackableShape( self.unit.character.worldPosition, RAIDER_TARGETING_RADIUS, MeleeBreachLevel )
		if attackableShape and attackPosition then
			self.lastTargetPosition = attackPosition
		end
	end

	-- Cooldown after attacking a crop
	if type( self.target ) == "Harvestable" then
		local _, attackResult = self.combatAttackState:isDone()
		if attackResult == "started" or attackResult == "attacked" then
			self.griefTimer:reset()
		end
	end

	local inCombatApproachRange = false
	local inCombatAttackRange = false

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

	if self.lastTargetPosition then
		local fromToTarget = self.lastTargetPosition - self.unit.character.worldPosition
		local predictionScale = fromToTarget:length() / math.max( self.unit.character.velocity:length(), 1.0 )
		local predictedPosition = self.lastTargetPosition + self.predictedVelocity * predictionScale
		local desiredDirection = predictedPosition - self.unit.character.worldPosition
		local targetRadius = 0.0
		if self.target and type( self.target ) == "Character" then
			targetRadius = self.target:getRadius()
		end

		inCombatApproachRange = fromToTarget:length() - targetRadius <= CombatApproachRange
		inCombatAttackRange = fromToTarget:length() - targetRadius <= CombatAttackRange

		local attackDirection = ( desiredDirection:length() >= FLT_EPSILON ) and desiredDirection:normalize() or self.unit.character.direction
		self.combatAttackState:sv_setAttackDirection( attackDirection ) -- Turn ongoing attacks toward moving players
		self.combatApproachState.desiredPosition = self.lastTargetPosition
		self.combatApproachState.desiredDirection = fromToTarget:normalize()
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

	-- Check for direct path
	local directPath
	if self.lastTargetPosition then



		local fromToTarget = self.lastTargetPosition - self.unit.character.worldPosition
		local distance = fromToTarget:length()
		if distance >= RAIDER_BREACH_DISTANCE then
			local path = sm.pathfinder.getPath( self.unit.character, self.lastTargetPosition, true, { canSwim = not self.waterAvoidance } )
			if not IsEmptyTable( path ) then
				if ( path[#path].toNode:getPosition() - self.unit.character.worldPosition ):length() >= RAIDER_TARGETING_RADIUS then
					directPath = true
				end
			end
		end
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

	-- Breach check
	local breachDestination = nil
	local voxelBreachDestination = nil
	if self.isInCombat and self.currentState ~= self.breachState and self.currentState ~= self.voxelBreachState then
		local nextTargetPosition
		if self.target then
			nextTargetPosition = self.target.worldPosition
		elseif self.lastTargetPosition then
			nextTargetPosition = self.lastTargetPosition
		end
		-- Always check for breachable in front of the unit
		if nextTargetPosition == nil then
			if self.saved.raider and self.saved.raidPosition then
				nextTargetPosition = self.saved.raidPosition
			else
				nextTargetPosition = self.unit.character.worldPosition + self.unit.character.direction
			end
		end
		
		local breachDepth = 0.25
		local leveledNextTargetPosition = sm.vec3.new( nextTargetPosition.x, nextTargetPosition.y, self.unit.character.worldPosition.z )
		local valid, breachPosition, breachObject = sm.ai.getBreachablePosition( self.unit, leveledNextTargetPosition, breachDepth, MeleeBreachLevel )
		if valid and breachPosition then
			local flatFromToNextTarget = leveledNextTargetPosition
			flatFromToNextTarget.z = 0
			if flatFromToNextTarget:length() <= 0 then
				flatFromToNextTarget = sm.vec3.new( 0, 1, 0 )
			end
			breachDestination = nextTargetPosition + flatFromToNextTarget:normalize() * breachDepth
		end

		-- Voxel breach check
		if not breachDestination and self.voxelBreachCooldownTicks <= 0 then
	
			local voxelBlocked, voxelHitPos = GetVoxelBreachPosition( self.unit.character, nextTargetPosition )
			if voxelBlocked then
				voxelBreachDestination = nextTargetPosition
			end
		end
	end

	local wantsJumpAttack = false

	if self.target and self.saved.deathEvent ~= NoJumpQuestBotDeathEvent then
		if self.target and ( sm.game.getCurrentTick() - self.launchAttackState.lastJumpTick >= JumpCooldownTickTime ) then
			local verticalDistance = math.abs( self.target.worldPosition.z - self.unit.character.worldPosition.z )
			if verticalDistance < MaxVerticalJumpDistance then
				local flooredTargetPos = sm.vec3.new( self.target.worldPosition.x, self.target.worldPosition.y, self.unit.character.worldPosition.z )
				local distanceToTarget = ( flooredTargetPos - self.unit.character.worldPosition ):length2()
				if distanceToTarget >= MinHorizontalJumpDistanceSqr and distanceToTarget <= MaxHorizontalJumpDistanceSqr then
					if math.random() < math.min( self.jumpChancePerSecond * dt, self.jumpChancePerSecond ) then
						wantsJumpAttack = true
					end
				end
			end
		end
	end

	local canPatrol
	if self.saved.patrolKey then
		canPatrol = PatrolManager.Sv_IsPatrolActive( self.saved.patrolKey )
	end

	local done, result = self.currentState:isDone()
	local abortState = 	( self.currentState ~= self.combatAttackState ) and
						( self.currentState ~= self.avoidState ) and
						(
							( self.currentState == self.pathingState and ( inCombatApproachRange or inCombatAttackRange ) and self.isInCombat ) or
							( prevInCombat and self.combatTimer:done() ) or
							( self.currentState == self.pathingState and breachDestination ) or
							( self.currentState == self.pathingState and voxelBreachDestination ) or
							( self.currentState == self.breachState and directPath ) or
							( self.currentState == self.lookAtState and self.isInCombat ) or
							( self.currentState == self.roamState and heardNoise ) or
							( self.currentState ~= self.launchAttackState and wantsJumpAttack )
						)

	if ( done or abortState ) then
		-- Select state
		if self.currentState == self.combatApproachState and done then
			-- Attack towards the approached target
			self.currentState = self.combatAttackState
		elseif breachDestination and not directPath then
			-- Start breaching path obstacle
			self.breachState:sv_setDestination( breachDestination )
			self.currentState = self.breachState
		elseif voxelBreachDestination then
			-- Start breaching voxel terrain
			self.voxelBreachState:sv_setDestination( voxelBreachDestination )
			self.currentState = self.voxelBreachState
		elseif self.currentState == self.voxelBreachState and result == "timeout" then
			-- Voxel breach failed, cooldown before retrying
			self.voxelBreachCooldownTicks = 40 * 3
			self.currentState = self.pathingState
		elseif wantsJumpAttack then
			-- Jump attack
			self.launchAttackState.lastJumpTick = sm.game.getCurrentTick()
			self.launchAttackState:sv_setTarget( self.target )
			self.currentState = self.launchAttackState
		elseif self.currentState == self.breachState and directPath then
			-- Continue pathing
			self.currentState = self.pathingState
		elseif self.currentState == self.voxelBreachState and directPath then
			-- Continue pathing after voxel breach, cooldown to prevent immediate re-entry
			self.voxelBreachCooldownTicks = 40 * 3
			self.currentState = self.pathingState
		elseif self.currentState == self.idleState and self.saved.raider then
			self.pathingState:sv_setDestination( self.saved.raidPosition )
			self.currentState = self.pathingState
		elseif self.currentState == self.pathingState and result == "failed" then
			self.avoidState.desiredDirection = self.unit.character.direction
			self.avoidState.desiredPosition = self.unit.character.worldPosition - self.avoidState.desiredDirection:normalize() * 2
			self.currentState = self.avoidState
		elseif self.isInCombat then
			-- Select combat state
			if directPath and ( self.currentState == self.breachState ) then
				self.lastTargetPosition = nil
			elseif self.target and inCombatAttackRange then
				-- Attack towards target character
				self.currentState = self.combatAttackState
			elseif self.target and inCombatApproachRange then
				-- Move close to the target to increase the likelihood of a hit
				self.currentState = self.combatApproachState
			elseif self.lastTargetPosition then
				if self.currentState ~= self.pathingState then
					self.pathingState:sv_setDestination( self.lastTargetPosition )
				else
					self.lastTargetPosition = nil
				end
				self.currentState = self.pathingState
			else
				-- Couldn't find the target
				self.isInCombat = false
			end
		else
			-- Select non-combat state
			if self.saved.ambusher then
				self.currentState = self.idleState
			elseif heardNoise then
				self.currentState = self.lookAtState
				self.roamTimer:start( math.random( RoamStartTimeMin, RoamStartTimeMax ) )
			elseif canPatrol then
				self.currentState = self.patrolState
			elseif self.roamTimer:done() and not ( self.currentState == self.idleState and result == "started" ) then
				self.roamTimer:start( math.random( RoamStartTimeMin, RoamStartTimeMax ) )
				self.currentState = self.roamState
			elseif not ( self.currentState == self.roamState and result == "roaming" ) then
				self.currentState = self.idleState
			end
		end
	end

	if prevState ~= self.currentState then
		if ( prevState == self.roamState and self.currentState ~= self.idleState ) or ( prevState == self.idleState and self.currentState ~= self.roamState ) then
			self.unit:sendCharacterEvent( "alerted" )
		elseif self.currentState == self.idleState and prevState ~= self.roamState then
			self.unit:sendCharacterEvent( "roaming" )
		end
		
		prevState:stop()
		self.currentState:start()
		if DEBUG_AI_STATES then
			print( self.currentState.debugName )
		end
	end

























end

function TotebotGreenUnit.sv_voxelBreachResult( self, destruction, params )
	local removedAny = destruction and destruction.remDensities and #destruction.remDensities > 0
	if removedAny then
		self.voxelBreachState.noProgressDigCount = 0
	end
end

function TotebotGreenUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
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
			self:sv_addStagger( StaggerProjectile )
			if self.eventTarget == nil then
				if type( attacker ) == "Player" or type( attacker ) == "Unit" then
					self.eventTarget = attacker:getCharacter()
				elseif type( attacker ) == "Shape" then
					self.eventTarget = attacker
				end
			end
		end
		local impact = hitVelocity:normalize() * 6
		self:sv_takeDamage( damage, impact, hitPos )
	end
end

function TotebotGreenUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
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
		if self.currentState == self.launchAttackState and not self.unit.character:isOnGround() and not self.unit.character:isTumbling() then
			self.unit.character:setTumbling( true )
			self.unit.character:applyTumblingImpulse( hitDirection * self.unit.character.velocity:length() * JumpCounterHitForce )
		end
		self:sv_addStagger( StaggerMelee )

		local impact = hitDirection * 6
		self:sv_takeDamage( damage, impact, hitPos )
	end
end

function TotebotGreenUnit.server_onExplosion( self, center, destructionLevel )
	if not sm.exists( self.unit ) then
		return
	end
	local impact = ( self.unit:getCharacter().worldPosition - center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) ) * 6
	self:sv_takeDamage( self.saved.stats.maxhp, impact, self.unit:getCharacter().worldPosition )
end

function TotebotGreenUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if not sm.exists( self.unit ) then
		return
	end
	if self.currentState == self.launchAttackState and otherPointVelocity:length2() == 0.0 then
		local dot = sm.vec3.dot( collisionNormal, sm.vec3.new( 0, 0, 1 ) )
		if dot < 0.2 then
			startTumble( self, 80, self.idleState, -self.unit.character.velocity )
		end
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
		self:sv_takeDamage(damage, collisionNormal, collisionPosition)

		if self.saved.stats.hp <= 0  then
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

function TotebotGreenUnit.server_onCollisionCrush( self )
	if not sm.exists( self.unit ) then
		return
	end
	onCrush( self )
end

function TotebotGreenUnit.sv_updateCharacterTarget( self )
	if self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_n_updateTarget", { target = self.target } )
	end
end

function TotebotGreenUnit.sv_addStagger( self, stagger )
	
	-- Update stagger
	if self.staggerCooldownTicks <= 0 then
		self.staggerCooldownTicks = StaggerCooldownTickTime
		self.stagger = self.stagger + stagger
		local triggerStaggered = ( self.stagger >= 1.0 )
		self.stagger = math.fmod( self.stagger, 1.0 )

		if triggerStaggered then
			local prevState = self.currentState
			self.currentState = self.staggeredEventState
			prevState:stop()
			self.currentState:start()
		end
	end
	
end

function TotebotGreenUnit.sv_onDeath( self, impact )
	local character = self.unit:getCharacter()
	if not self.destroyed then
		self.unit:sendCharacterEvent( "death" )
		g_unitManager:sv_addDeathMarker( character.worldPosition )
		self.saved.stats.hp = 0
		self.unit:destroy()
		self:sv_spawnParts( impact )
		if SurvivalGame then
			local loot = SelectLoot( "lootsource_totebot_green", nil, self.saved.lootType )
			SpawnLoot( self.unit, loot )
		end
		self.destroyed = true
		BaseUnit.sv_onDeath( self )
	end
end

function TotebotGreenUnit.sv_spawnParts( self, impact )
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
			local headShape = headBody:createPart( ITEMS.obj_interactive_robotbliphead01, sm.vec3.new( 0, 1, 2 ), sm.vec3.new( 0, 1, 0 ), sm.vec3.new( -1, 0, 0 ), true )
			headShape.color = color
			sm.physics.applyImpulse( headShape, impact * headShape.mass, true )
		end
	end
end
