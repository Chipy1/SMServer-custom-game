dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Ticker.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/BreachState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/VoxelBreachState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/CombatAttackState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/CircleFollowState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/BaseUnit.lua"
dofile "$SURVIVAL_DATA/Scripts/game/managers/PatrolManager.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PatrolState.lua"

HaybotUnit = class( BaseUnit )

local WaterTumbleTickTime = 3.0 * 40
local AllyRange = 20.0
local MeleeBreachLevel = 9
local HearRange = 40.0
local SwimSelfdestructTickTime = 40 * 8.0
local CirclingRange = 20.0
local ResetPatternTickDuration = 40 * 5 -- Resets attack pattern after 5 seconds away from melee range

local StabRange = 2.2
local SwipeRange = 2.0

local VoxelDigRadius = 1.2
local VoxelDigStrength = 1.0

function HaybotUnit.server_onCreate( self )
	
	self.target = nil
	self.previousTarget = nil
	self.lastTargetPosition = nil
	self.ambushPosition = nil
	self.isDirty = false
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.stats == nil then
		self.saved.stats = { hp = 100, maxhp = 100 }
	end

	InitRobotParams( self )
	self.storage:save( self.saved )

	sm.message.subscribe( MESSAGE_TYPES.GENERAL.ProjectileHit, "sv_m_projectileHit" )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.ProjectileFire, "sv_m_projectileFire" )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.Collision, "sv_m_collision" )

	self.unit.eyeHeight = self.unit.character:getHeight() * 0.75
	
	self.unit.visionFrustum = {
		{ 3.0, math.rad( 80.0 ), math.rad( 80.0 ) },
		{ 20.0, math.rad( 40.0 ), math.rad( 35.0 ) },
		{ 40.0, math.rad( 20.0 ), math.rad( 20.0 ) }
	}
	self.unit:setWhiskerData( 3, math.rad( 60.0 ), 1.5, 5.0 )
	self.noiseScale = 1.0
	self.impactCooldownTicks = 0
	
	self.stateTicker = Ticker()
	self.stateTicker:init()

	-- Idle	
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"
	self.idleState.randomEventCooldownMin = 4
	self.idleState.randomEventCooldownMax = 6
	self.idleState.randomEvents = { { name = "idlespecial01", time = 4.0, interruptible = true, chance = 0.5 },
									{ name = "idlespecial02", time = 7.5, interruptible = true, chance = 0.5 } }
	
	-- Stagger
	self.staggeredEventState = self.unit:createState( "wait" )
	self.staggeredEventState.debugName = "staggeredState"
	self.staggeredEventState.time = 0.1
	self.staggeredEventState.interruptible = false
	self.stagger = 0.0
	self.staggerProjectile = 0.5
	self.staggerMelee = 1.0
	self.staggerCooldownTickTime = 1.65 * 40
	self.staggerCooldownTicks = 0
	
	-- Circle follow
	self.circleFollowState = CircleFollowState()
	self.circleFollowState:sv_onCreate( self.unit, 3.7, 7.0, CirclingRange, 40 * 2, 40 * 10, 40 * 1.5, 40 * 3.5, 40 * 1.0, 40 * 2.0 )
	self.circleFollowState:sv_setWaterAvoidance( true )
	self.circleFollowState.debugName = "circleFollowState"

	-- Roam
	self.roamStartTimeMin = 40 * 4 -- 4 seconds
	self.roamStartTimeMax = 40 * 8 -- 8 seconds
	self.roamTimer = Timer()
	self.roamTimer:start( math.random( self.roamStartTimeMin, self.roamStartTimeMax ) )
	self.roamState = self.unit:createState( "roam" )
	self.roamState.debugName = "roam"
	self.roamState.tetherPosition = self.unit.character.worldPosition
	self.roamState.roamCenterOffset = 0.0
	self.roamState.waterAvoidance = true
	self.roamState.customData = { onUnitUpdateOnly = true }

	-- Pathing
	self.pathingState = PathingState()
	self.pathingState:sv_onCreate( self.unit )
	self.pathingState:sv_setTolerance( 1.0 )
	self.pathingState:sv_setMovementType( "sprint" )
	self.pathingState:sv_setRaider( self.saved.raider )
	self.pathingState:sv_setWaterAvoidance( true )
	self.pathingState.debugName = "pathingState"
	
	-- Attacks
	self.attackState01 = self.unit:createState( "meleeAttack" )
	self.attackState01.meleeType = melee_haybotpitchforkswipe
	self.attackState01.event = "attack01"
	self.attackState01.damage = 20
	self.attackState01.attackRange = SwipeRange
	self.attackState01.animationCooldown = 1.65 * 40
	self.attackState01.attackCooldown = 0.3 * 40
	self.attackState01.globalCooldown = 0.0 * 40
	self.attackState01.attackDelay = 0.3 * 40
	self.attackState01.debugName = "attackState01"
	
	self.attackState02 = self.unit:createState( "meleeAttack" )
	self.attackState02.meleeType = melee_haybotpitchfork
	self.attackState02.event = "attack02"
	self.attackState02.damage = 20
	self.attackState02.attackRange = StabRange
	self.attackState02.animationCooldown = 0.825 * 40
	self.attackState02.attackCooldown = 2.0 * 40
	self.attackState02.globalCooldown = 0.0 * 40
	self.attackState02.attackDelay = 0.15 * 40
	self.attackState02.debugName = "attackState02"
	
	self.attackState03 = self.unit:createState( "meleeAttack" )
	self.attackState03.meleeType = melee_haybotpitchfork
	self.attackState03.event = "attack03"
	self.attackState03.damage = 20
	self.attackState03.attackRange = StabRange
	self.attackState03.animationCooldown = 0.925 * 40
	self.attackState03.attackCooldown = 2.0 * 40
	self.attackState03.globalCooldown = 0.0 * 40
	self.attackState03.attackDelay = 0.15 * 40
	self.attackState03.debugName = "attackState03"
	
	self.attackStateSprint01 = self.unit:createState( "meleeAttack" )
	self.attackStateSprint01.meleeType = melee_haybotpitchfork
	self.attackStateSprint01.event = "sprintattack01"
	self.attackStateSprint01.damage = 20
	self.attackStateSprint01.attackRange = 2
	self.attackStateSprint01.animationCooldown = 0.8 * 40
	self.attackStateSprint01.attackCooldown = 3.0 * 40
	self.attackStateSprint01.globalCooldown = 0.0 * 40
	self.attackStateSprint01.attackDelay = 0.3 * 40
	self.attackStateSprint01.debugName = "attackStateSprint01"
	
	-- Combat
	self.combatAttackState = CombatAttackState()
	self.combatAttackState:sv_onCreate( self.unit )
	self.stateTicker:addState( self.combatAttackState )
	self.combatAttackState:sv_addAttack( self.attackState02 )
	self.combatAttackState:sv_addAttack( self.attackState01 )
	self.combatAttackState:sv_addAttack( self.attackState03 )
	self.combatAttackState:sv_addAttack( self.attackState01 )
	self.combatAttackState.debugName = "combatAttackState"
	self.combatAttackState:setSequential( true )
	--self.combatAttackState:sv_addAttack( self.attackStateSprint01 )
	self.combatRange = 1.8 -- Range where the unit will perform attacks
	
	self.combatTicks = 0
	self.combatTicksAttack = 20 * 40
	self.combatTicksBerserk = 50 * 40
	self.combatTicksAttackCost = 20 * 40

	self.nextFakeAggroMin = 4 * 40
	self.nextFakeAggroMax = 6 * 40
	self.nextFakeAggro = math.random( self.nextFakeAggroMin, self.nextFakeAggroMax )
	
	self.nextAggroMin = 10 * 40
	self.nextAggroMax = 16 * 40
	self.nextAggro = math.random( self.nextAggroMin, self.nextAggroMax )
	
	-- Breach
	self.breachState = BreachState()
	self.breachState:sv_onCreate( self.unit, math.ceil( 40 * 2.0 ) )
	self.stateTicker:addState( self.breachState )
	self.breachState:sv_setBreachRange( self.combatRange )
	self.breachState:sv_setBreachLevel( MeleeBreachLevel )
	--self.breachState:sv_addAttack( self.attackState02 )
	self.breachState:sv_addAttack( self.attackState03 )
	self.breachState.debugName = "breachState"

	-- Voxel Breach
	self.voxelBreachState = VoxelBreachState()
	self.voxelBreachState:sv_onCreate( self.unit, math.ceil( 40 * 3.0 ) )
	self.stateTicker:addState( self.voxelBreachState )
	self.voxelBreachState:sv_addAttack( self.attackState03 )
	self.voxelBreachState:sv_setDigRadius( VoxelDigRadius )
	self.voxelBreachState:sv_setDigStrength( VoxelDigStrength )
	self.voxelBreachState.debugName = "voxelBreachState"
	
	-- Combat approach
	self.combatApproachState = self.unit:createState( "positioning" )
	self.combatApproachState.debugName = "combatApproachState"
	self.combatApproachState.timeout = 0.5
	self.combatApproachState.tolerance = self.combatRange
	self.combatApproachState.avoidance = false
	self.combatApproachState.movementType = "sprint"
	self.pathingCombatRange = 1.5 -- Range where the unit will approach the player without obstacle checking
	self.combatApproachState.debugName = "combatApproachState"
	
	-- Avoid
	self.avoidState = self.unit:createState( "positioning" )
	self.avoidState.debugName = "avoid"
	self.avoidState.timeout = 1.5
	self.avoidState.tolerance = 0.5
	self.avoidState.avoidance = false
	self.avoidState.movementType = "walk"
	self.avoidCount = 0
	self.avoidLimit = 3
	self.avoidState.debugName = "avoidState"

	-- LookAt
	self.lookAtState = self.unit:createState( "positioning" )
	self.lookAtState.debugName = "lookAt"
	self.lookAtState.timeout = 3.0
	self.lookAtState.tolerance = 0.5
	self.lookAtState.avoidance = false
	self.lookAtState.movementType = "stand"
	self.lookAtState.debugName = "lookAtState"
	
	-- Swim
	self.swimState = self.unit:createState( "followDirection" )
	self.swimState.debugName = "swim"
	self.swimState.avoidance = false
	self.swimState.movementType = "walk"
	self.lastStablePosition = nil
	self.swimSelfdestructTimer = Timer()
	self.swimSelfdestructTimer:start( SwimSelfdestructTickTime )
	self.swimState.debugName = "swimState"

	-- Tumble
	initTumble( self )
	
	-- Crushing
	initCrushing( self, DEFAULT_CRUSH_TICK_TIME )
	
	-- Flee
	self.raidFlee = self.unit:createState( "flee" )
	self.raidFlee.movementAngleThreshold = math.rad( 180 )
	self.raidFlee.maxFleeTime = 0.0
	self.raidFlee.maxDeviation = 45 * math.pi / 180

	-- Patrol
	self.patrolState = PatrolState()
	self.patrolState:sv_onCreate( self.unit, self.saved.patrolKey )
	self.patrolState.debugName = "patrolState"

	self.griefTimer = Timer()
	self.griefTimer:start( 40 * 9.0 )

	self.voxelBreachCooldownTicks = 0
	
	self.currentState = self.idleState
	self.currentState:start()

	self.lastTickNearPlayer = sm.game.getCurrentTick()
end

function HaybotUnit.server_onDestroy( self )
	BaseUnit.server_onDestroy( self )
	if DEBUG_AI_STATES then
		sm.debugDraw.removeText( "unit_state_" .. self.unit.id )
	end
end

function HaybotUnit.server_onRefresh( self )
end

function HaybotUnit.server_onFixedUpdate( self, dt )
	BaseUnit.server_onFixedUpdate( self )
	
	self.stateTicker:tick()
	
	if updateCrushing( self ) then
		self:sv_onDeath( sm.vec3.new( 0, 0, 0 ) )
	end

	updateTumble( self )
	updateAirTumble( self, self.idleState )
	
	self.griefTimer:tick()

	self.voxelBreachCooldownTicks = math.max( self.voxelBreachCooldownTicks - 1, 0 )

	local currentTargetPosition
	if self.target and sm.exists( self.target ) then
		currentTargetPosition = self.target.worldPosition
	else
		self.avoidCount = 0
	end
	if self.currentState then
		if not self.currentState.customData or not self.currentState.customData.onUnitUpdateOnly then
			self.currentState:onFixedUpdate( dt )
		end
	
		self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		self.unit:setMovementType( self.currentState:getMovementType() )
		if self.currentState ~= self.swimState and not self.unit.character:isSwimming() then
			self.swimSelfdestructTimer:reset()
			if currentTargetPosition and self.currentState ~= self.combatAttackState and self.currentState ~= self.breachState and self.currentState ~= self.avoidState and self.currentState ~= self.raidFlee then
				self.unit:setFacingDirection( ( currentTargetPosition - self.unit.character.worldPosition ):normalize() )
			else
				self.unit:setFacingDirection( self.currentState:getFacingDirection() )
			end
		else
			self.swimSelfdestructTimer:tick()
			if self.swimSelfdestructTimer:done() then
				self:sv_onDeath( sm.vec3.new( 0, 0, 1 ) )
				self.swimSelfdestructTimer:stop()
			end
		end
		
		-- Random roaming during idle
		if self.currentState == self.idleState then
			self.roamTimer:tick()
		end
		
		-- Always aggro when next to the target
		local closeCombat = false
		if self.target and sm.exists( self.target ) then
			local fromToTarget = self.target.worldPosition - self.unit.character.worldPosition
			local distance = fromToTarget:length()
			if type( self.target ) == "Character" then
				distance = distance - self.target:getRadius()
			end
			if distance <= self.pathingCombatRange then
				closeCombat = true
			end
		end
		
		-- Decrease aggro with time
		self.combatTicks = math.max( self.combatTicks - 1, closeCombat and 1 or 0 )
		
		self.staggerCooldownTicks = math.max( self.staggerCooldownTicks - 1, 0 )
		self.impactCooldownTicks = math.max( self.impactCooldownTicks - 1, 0 )
		
		-- Occasionally add random aggro for fakeouts and small attacks
		if self.currentState == self.circleFollowState then
			-- Real attack
			self.nextAggro = self.nextAggro - 1
			if self.nextAggro <= 0 then
				self.nextAggro = math.random( self.nextAggroMin, self.nextAggroMax )
				self.combatTicks = math.max( self.combatTicks, self.combatTicksAttack )
			end

			-- Fake attack
			self.nextFakeAggro = self.nextFakeAggro - 1
			if self.nextFakeAggro <= 0 then
				self.nextFakeAggro = math.random( self.nextFakeAggroMin, self.nextFakeAggroMax )
				self.circleFollowState:sv_rush( 16 ) -- Sprint toward target during the given tick time
				self.avoidCount = 0
			end
		end
		
	end
	
	-- Update target for haybot character
	if self.target ~= self.previousTarget then
		self:sv_updateCharacterTarget()
		self.previousTarget = self.target
	end
	if self.isDirty then
		self.storage:save( self.saved )
		self.isDirty = false
	end
end

function HaybotUnit.server_onCharacterChangedColor( self, color )
	if self.saved.color ~= color then
		self.saved.color = color
		self.storage:save( self.saved )
	end
end

function HaybotUnit.server_onUnitUpdate( self, dt )
	
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

	local previousTarget = self.target
	RobotSelectTarget( self, AllyRange, dt )
	local foundTarget = self.target and self.target ~= previousTarget

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
			if self.lastTargetPosition == nil or ( ( self.lastTargetPosition - closestSpot ):length2() > ( RAIDER_TARGETING_RADIUS * 1.5 ) ) then
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
	
	local prevState = self.currentState
	if self.unit.character:isOnGround() and not self.unit.character:isSwimming() then
		self.lastStablePosition = self.unit.character.worldPosition
	end

	local currentTargetPosition
	local inCombatApproachRange = false
	local inCombatAttackRange = false
	if self.target then
		currentTargetPosition = self.target.worldPosition
		local fromToTarget = self.target.worldPosition - self.unit.character.worldPosition
		local distance = fromToTarget:length()
		if type( self.target ) == "Character" then
			distance = distance - self.target:getRadius()
		end
		inCombatApproachRange = distance <= self.pathingCombatRange
		inCombatAttackRange = distance <= self.combatRange

		self.combatAttackState:sv_setAttackDirection( fromToTarget:normalize() ) -- Turn ongoing attacks toward moving players
		local flatCurrentTargetPosition = sm.vec3.new(  currentTargetPosition.x, currentTargetPosition.y, self.unit.character.worldPosition.z )
		self.combatApproachState.desiredPosition = flatCurrentTargetPosition
		self.combatApproachState.desiredDirection = fromToTarget:normalize()
		self.attackState01.attackDirection = fromToTarget:normalize()
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
	
	-- Find dangerous obstacles
	local shouldAvoid = false
	if not self.saved.raider then
		local closestDangerShape, _ = g_unitManager:sv_getClosestDangers( self.unit.character.worldPosition )
		if closestDangerShape then
			local fromToDanger = closestDangerShape.worldPosition - self.unit.character.worldPosition
			local distance = fromToDanger:length()
			if distance <= 3.5 and ( ( self.target and self.avoidCount < self.avoidLimit ) or self.target == nil ) then
				self.avoidState.desiredPosition = self.unit.character.worldPosition - fromToDanger:normalize() * 2
				self.avoidState.desiredDirection = fromToDanger:normalize()
				shouldAvoid = true
			end
		end
	end

	-- Check for direct path
	local directPath
	if self.lastTargetPosition then



		local fromToTarget = self.lastTargetPosition - self.unit.character.worldPosition
		local distance = fromToTarget:length()

		if self.saved.raider and distance >= RAIDER_BREACH_DISTANCE then
			local path = sm.pathfinder.getPath( self.unit.character, self.lastTargetPosition, true, { canSwim = not self.waterAvoidance } )
			if not IsEmptyTable( path ) then
				if ( path[#path].toNode:getPosition() - self.unit.character.worldPosition ):length() >= RAIDER_TARGETING_RADIUS then
					directPath = true
				end
			end
		elseif not self.saved.raider then
			if distance <= 3 then
				directPath = true
			else
				local path = sm.pathfinder.getPath( self.unit.character, self.lastTargetPosition, true, { canSwim = not self.waterAvoidance } )
				if not IsEmptyTable( path ) then
					if ( path[#path].toNode:getPosition() - self.unit.character.worldPosition ):length() <= 3 then
						directPath = true
					end
				end
			end
		end
	end
	
	local allyConfidenceCount = 2
	local combatPathing = self.combatTicks > 0 or ( #self.allyUnits >= allyConfidenceCount and self.lastTargetPosition ) or closestVisibleCrop or closestVisibleWormCharacter
	-- Auto aggressive behaviour if the target is close, but unreachable
	if not directPath and self.lastTargetPosition and not combatPathing then
		combatPathing = true
	end
	self.isInCombat = self.lastTargetPosition ~= nil -- Used for BaseUnit behavior

	-- Update pathingState destination
	if self.currentState == self.pathingState then
		if currentTargetPosition then
			self.pathingState:sv_setDestination( currentTargetPosition )
		elseif self.lastTargetPosition then
			self.pathingState:sv_setDestination( self.lastTargetPosition )
		end
	end
	
	-- Breach check
	local breachDestination = nil
	local voxelBreachDestination = nil

		local nextTargetPosition
		if currentTargetPosition then
			nextTargetPosition = currentTargetPosition
		elseif self.lastTargetPosition then
			nextTargetPosition = self.lastTargetPosition
		end
		-- Always check for breachable in front of the unit or towards raid point
		if nextTargetPosition == nil then
			if self.saved.raider and self.saved.raidPosition then
				nextTargetPosition = self.saved.raidPosition
			else
				nextTargetPosition = self.unit.character.worldPosition + self.unit.character.direction
			end
		end

	if combatPathing then
		
		if nextTargetPosition then
			local breachDepth = 0.25
			local leveledNextTargetPosition = sm.vec3.new( nextTargetPosition.x, nextTargetPosition.y, self.unit.character.worldPosition.z )
			local valid, breachPosition = sm.ai.getBreachablePosition( self.unit, leveledNextTargetPosition, breachDepth, MeleeBreachLevel )
			if valid and breachPosition then
				local flatFromToNextTarget = leveledNextTargetPosition
				flatFromToNextTarget.z = 0
				if flatFromToNextTarget:length() <= 0 then
					flatFromToNextTarget = sm.vec3.new(0, 1, 0 )
				end
				breachDestination = nextTargetPosition + flatFromToNextTarget:normalize() * breachDepth
			end

		
		else
			self.combatTicks = 0
			combatPathing = false
		end
	end

	-- Voxel breach check
	if not breachDestination and self.voxelBreachCooldownTicks <= 0 then
		local voxelBlocked, voxelHitPos = GetVoxelBreachPosition( self.unit.character, nextTargetPosition )
		if voxelBlocked then
			voxelBreachDestination = nextTargetPosition
		end
	end

	local canPatrol
	if self.saved.patrolKey then
		canPatrol = PatrolManager.Sv_IsPatrolActive( self.saved.patrolKey )
	end

	if sm.game.getCurrentTick() - self.lastTickNearPlayer > ResetPatternTickDuration then
		self.combatAttackState:forceAttackIndex( 1 )
	end
	if inCombatAttackRange then
		self.lastTickNearPlayer = sm.game.getCurrentTick()
	end

	local done, result = self.currentState:isDone()
	local abortState = 	( self.currentState ~= self.combatAttackState ) and
						( self.currentState ~= self.attackState01 ) and
						( self.currentState ~= self.avoidState ) and
						(
							( self.currentState == self.pathingState and ( inCombatApproachRange or inCombatAttackRange ) and combatPathing ) or
							( breachDestination and self.currentState ~= self.breachState ) or
							( voxelBreachDestination and self.currentState ~= self.voxelBreachState ) or
							( directPath and self.currentState == self.breachState ) or
							( directPath and self.currentState == self.voxelBreachState ) or
							foundTarget or
							shouldAvoid or
							self.unit.character:isSwimming() or
							( self.currentState == self.lookAtState and self.lastTargetPosition --[[isInCombat--]] ) or
							( self.currentState == self.roamState and heardNoise )
						)

	if ( done or abortState ) then
		-- Reduce aggro with successful attacks
		if self.currentState == self.combatAttackState and ( result == "finished" or result == "ready" ) then
			self.combatTicks = math.max( self.combatTicks - self.combatTicksAttackCost, 0 )
		end
		-- Select state
		if self.unit.character:isSwimming() then
			local landPosition = self.lastStablePosition and self.lastStablePosition or self.homePosition
			if landPosition then
				local landDirection = landPosition - self.unit.character.worldPosition
				landDirection.z = 0
				if landDirection:length() >= FLT_EPSILON then
					landDirection = landDirection:normalize()
				else
					landDirection = sm.vec3.new( 0, 1, 0 )
				end
				self.swimState.desiredDirection = landDirection
			end
			self.currentState = self.swimState
		elseif self.currentState == self.staggeredEventState and self.target then
			self.currentState = self.combatAttackState
		elseif self.currentState == self.idleState and self.saved.raider then
			self.pathingState:sv_setDestination( self.saved.raidPosition )
			self.currentState = self.pathingState
		elseif shouldAvoid then
			if self.currentState ~= self.avoidState  then
				self.avoidCount = math.min( self.avoidCount + 1, self.avoidLimit )
			end
			self.currentState = self.avoidState
		elseif self.currentState == self.combatApproachState and done then
			-- Attack towards the approached target
			self.currentState = self.combatAttackState
		elseif self.currentState == self.pathingState and result == "failed" then
			self.avoidState.desiredDirection = self.unit.character.direction
			self.avoidState.desiredPosition = self.unit.character.worldPosition - self.avoidState.desiredDirection:normalize() * 2
			self.currentState = self.avoidState
		elseif ( self.currentState == self.pathingState and result == "arrived" or self.currentState == self.breachState or self.currentState == self.voxelBreachState ) and not directPath then
			if self.currentState == self.voxelBreachState and result == "timeout" then
				self.voxelBreachCooldownTicks = 40 * 3
				self.circleFollowState:sv_setTargetPosition( self.unit.character.worldPosition + self.unit.character.direction )
				self.currentState = self.circleFollowState
			elseif breachDestination then
				self.breachState:sv_setDestination( breachDestination )
				self.currentState = self.breachState
			elseif voxelBreachDestination then
				self.voxelBreachState:sv_setDestination( voxelBreachDestination )
				self.currentState = self.voxelBreachState
			else
				-- Special check for obstacles or direct routes to players after pathing
				local nextTargetPosition
				if currentTargetPosition then
					nextTargetPosition = currentTargetPosition
				elseif self.lastTargetPosition then
					nextTargetPosition = self.lastTargetPosition
				end
				if nextTargetPosition == nil then
					nextTargetPosition = self.unit.character.worldPosition + self.unit.character.direction
				end
				self.circleFollowState:sv_setTargetPosition( nextTargetPosition )
				self.currentState = self.circleFollowState
			end
		elseif self.currentState == self.pathingState and breachDestination and not directPath then
			-- Start breaching path obstacle
			self.breachState:sv_setDestination( breachDestination )
			self.currentState = self.breachState
		elseif self.currentState == self.pathingState and voxelBreachDestination and not directPath then
			-- Start breaching voxel terrain
			self.voxelBreachState:sv_setDestination( voxelBreachDestination )
			self.currentState = self.voxelBreachState
		elseif combatPathing then
			-- Select combat state
			if currentTargetPosition then
				local fromToTarget = currentTargetPosition - self.unit.character.worldPosition
				local flatCurrentTargetPosition = sm.vec3.new(  currentTargetPosition.x, currentTargetPosition.y, self.unit.character.worldPosition.z )
				local flatFromToTarget = flatCurrentTargetPosition - self.unit.character.worldPosition
				local flatDistance = flatFromToTarget:length()
				if self.target and type( self.target ) == "Character" then
					flatDistance = flatDistance - self.target:getRadius()
				end
				
				if flatDistance <= self.combatRange then
					-- Attack towards target character
					self.combatAttackState:sv_setAttackDirection( fromToTarget:normalize() )
					self.currentState = self.combatAttackState
				elseif flatDistance <= self.pathingCombatRange and self.currentState ~= self.combatAttackState then
					-- Move close to the target to increase the likelihood of a hit
					self.combatApproachState.desiredPosition = flatCurrentTargetPosition
					self.combatApproachState.desiredDirection = fromToTarget:normalize()
					self.currentState = self.combatApproachState
				else
					-- Move towards target character
					if self.currentState ~= self.pathingState then
						self.pathingState:sv_setDestination( currentTargetPosition )
					end
					self.pathingState:sv_setTolerance( 1.0 )
					self.currentState = self.pathingState
				end
			elseif self.lastTargetPosition then
				if self.currentState ~= self.pathingState then
					self.pathingState:sv_setDestination( self.lastTargetPosition )
				end
				self.pathingState:sv_setTolerance( 1.0 )
				self.currentState = self.pathingState
				self.lastTargetPosition = nil
			elseif heardNoise then
				self.currentState = self.lookAtState
				self.roamTimer:start( math.random( self.roamStartTimeMin, self.roamStartTimeMax ) )
			else
				self.currentState = self.idleState
				self.combatTicks = 0
			end
		else
			-- Select non-combat state
			if self.target then
				local distanceToTargetSqr = ( self.target.worldPosition - self.unit.character.worldPosition ):length2()
				if distanceToTargetSqr > CirclingRange * CirclingRange then
					self.pathingState:sv_setDestination( self.target.worldPosition )
					self.pathingState:sv_setTolerance( CirclingRange )
					self.currentState = self.pathingState
				else
					-- Stick close to the target and circle around
					self.circleFollowState:sv_setTargetPosition( self.target.worldPosition )
					local radius = 0.0
					if type( self.target ) == "Character" then
						radius = self.target:getRadius()
					end
					self.circleFollowState:sv_setTargetRadius( radius )
					self.currentState = self.circleFollowState
				end
			elseif self.lastTargetPosition then
				if self.currentState ~= self.pathingState then
					self.pathingState:sv_setDestination( self.lastTargetPosition )
				end
				self.pathingState:sv_setTolerance( 1.0 )
				self.currentState = self.pathingState
				self.lastTargetPosition = nil
			elseif self.saved.ambusher then
				self.currentState = self.idleState
			elseif heardNoise then
				self.currentState = self.lookAtState
				self.roamTimer:start( math.random( self.roamStartTimeMin, self.roamStartTimeMax ) )
			elseif canPatrol then
				self.currentState = self.patrolState
			elseif self.roamTimer:done() and not ( self.currentState == self.idleState and result == "started" ) then
				self.roamTimer:start( math.random( self.roamStartTimeMin, self.roamStartTimeMax ) )
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
			print("change state")
			if self.currentState == self.idleState then
				print("idleState")
			elseif self.currentState == self.pathingState then
				print("pathingState")
			elseif self.currentState == self.roamState then
				print("roamState")
			elseif self.currentState == self.circleFollowState then
				print("circleFollowState")
			elseif self.currentState == self.combatApproachState then
				print("combatApproachState")
			elseif self.currentState == self.staggeredEventState then
				print("staggeredEventState")
			elseif self.currentState == self.combatAttackState then
				print("combatAttackState")
			elseif self.currentState == self.breachState then
				print("breachState")
			else
				print("unknown")
			end
		end
		
	end





























end

function HaybotUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
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
			self:sv_addStagger( self.staggerProjectile )
			if self.eventTarget == nil then
				if type( attacker ) == "Player" or type( attacker ) == "Unit" then
					self.eventTarget = attacker:getCharacter()
				elseif type( attacker ) == "Shape" then
					self.eventTarget = attacker
				end
			end
			self.combatTicks = math.max( self.combatTicks, self.combatTicksBerserk )

			local impact = hitVelocity:normalize() * 6
			self:sv_takeDamage( damage, impact, hitPos )
		end
	end
	if projectileUuid == projectile_water then
		startTumble( self, WaterTumbleTickTime, self.idleState )
		self.unit:sendCharacterEvent("water")

		if (type(attacker) == "Player") then
			sm.achievement.seti("48666dd9-23a3-4d4b-b7cf-d253f088f86e", 1, { attacker:getId() })
		end
	end
end

function HaybotUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
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
		local ZAxis = sm.vec3.new( 0.0, 0.0, 1.0 )

		self:sv_addStagger( self.staggerMelee )
		if self.eventTarget == nil then
			self.eventTarget = attackingCharacter
		end
		self.combatTicks = math.max( self.combatTicks, self.combatTicksBerserk )

		local impact = hitDirection * 6
		self:sv_takeDamage( damage, impact, hitPos )
	end
end

function HaybotUnit.server_onExplosion( self, center, destructionLevel )
	if not sm.exists( self.unit ) then
		return
	end
	local impact = ( self.unit:getCharacter().worldPosition - center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) )
	self:sv_takeDamage( self.saved.stats.maxhp, impact, self.unit:getCharacter().worldPosition )
end

function HaybotUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
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

	local collisionDamageMultiplier = 3.0
	local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision( self.unit.character, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, self.saved.stats.maxhp / collisionDamageMultiplier, nil, self.velocityBuffer, self.velocityBufferIndex )
	damage = damage * collisionDamageMultiplier
	if damage > 0 or tumbleTicks > 0 then
		self.impactCooldownTicks = 6
	end
	if damage > 0 then
		self:sv_takeDamage(damage, collisionNormal, collisionPosition)
		if self.saved.stats.hp <= 0 then
			--Achievement check
			RoadRageAchievementCheck(other)
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

function HaybotUnit.server_onCollisionCrush( self )
	if not sm.exists( self.unit ) then
		return
	end
	onCrush( self )
end

function HaybotUnit.sv_updateCharacterTarget( self )
	if self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_n_updateTarget", { target = self.target } )
	end
end

function HaybotUnit.sv_addStagger( self, stagger )
	
	-- Update stagger
	if self.staggerCooldownTicks <= 0 then
		self.staggerCooldownTicks = self.staggerCooldownTickTime
		self.stagger = self.stagger + stagger
		local triggerStaggered = false
		while self.stagger >= 1.0 do
			self.stagger = self.stagger - 1.0
			triggerStaggered = true
		end
		if triggerStaggered then
			local prevState = self.currentState
			self.currentState = self.staggeredEventState
			prevState:stop()
			self.currentState:start()
		end
	end
	
end

function HaybotUnit.sv_takeDamage( self, damage, impact, hitPos, source )
	if self.saved.stats.hp > 0 and damage > 0 then
		self.saved.stats.hp = self.saved.stats.hp - damage
		self.saved.stats.hp = math.max( self.saved.stats.hp, 0 )
		
		for _, allyUnit in ipairs( self.allyUnits ) do
			if sm.exists( allyUnit ) and allyUnit.character and allyUnit.character:getCharacterType() == unit_haybot then
				sm.event.sendToUnit( allyUnit, "sv_e_allyDamaged", { sendingUnit = self.unit } )
			end
		end
		
		local effectRotation = sm.quat.identity()
		if impact and impact:length() >= FLT_EPSILON then
			effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -impact:normalize() )
		end
		
		if self.saved.stats.hp <= 0 then
			self:sv_onDeath( impact )
		else
			local currentTick = sm.game.getCurrentTick()
			if source ~= "plasma" or not self.lastPlasmaDrillEffectTick or currentTick - self.lastPlasmaDrillEffectTick >= PLASMA_BOT_HIT_EFFECT_TICK_THRESHOLD then
				self.lastPlasmaDrillEffectTick = currentTick
				sm.effect.playEffect( "Haybot - Hit", hitPos, nil, effectRotation )
			end
			self.unit:sendCharacterEvent( "impact" )
			self.storage:save( self.saved )
		end
	end
end

function HaybotUnit.sv_voxelBreachResult( self, destruction, params )
	local removedAny = destruction and destruction.remDensities and #destruction.remDensities > 0
	if removedAny then
		self.voxelBreachState.noProgressDigCount = 0
	end
end

function HaybotUnit.sv_onDeath( self, impact )
	local character = self.unit:getCharacter()
	if not self.destroyed then
		g_unitManager:sv_addDeathMarker( character.worldPosition )
		self.saved.stats.hp = 0
		self.unit:destroy()
		self.unit:sendCharacterEvent( "death" )
		self:sv_spawnParts( impact )
		if SurvivalGame then
			local loot = SelectLoot( "lootsource_haybot", nil, self.saved.lootType )
			SpawnLoot( self.unit, loot )
		end
		BaseUnit.sv_onDeath( self );
		self.destroyed = true
	end
end

function HaybotUnit.sv_spawnParts( self, impact )
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
	local tiltAxis = sm.vec3.new( 0, 1, 0 ):rotateZ( math.rad( math.random( 0, 359 ) ) )
	local tiltRotation = sm.quat.angleAxis( math.rad( math.random( 18, 22 ) ), tiltAxis )
	
	if not g_disableScrapHarvest then
		local scrapBody = sm.body.createBody( bodyPos, tiltRotation, true )
		local scrapShape = scrapBody:createPart( obj_harvest_metal, sm.vec3.new( -1, 2, -1 ), sm.vec3.new( 0, -1, 0 ), sm.vec3.new( 1, 0, 0 ), true )
		scrapShape.color = color
	end
end

function HaybotUnit.sv_e_allyDamaged( self, params )
	if sm.exists( params.sendingUnit ) and sm.exists( self.unit ) and ( params.sendingUnit.character.worldPosition - self.unit.character.worldPosition ):length() <= AllyRange then
		self.circleFollowState:sv_avoid( 30,  params.sendingUnit.character.worldPosition ) -- Sprint evasively during the given tick time
	end
end


