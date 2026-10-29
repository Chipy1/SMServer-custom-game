dofile( "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Ticker.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BreachState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/VoxelBreachState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/CombatAttackState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/CombatFollowAttackState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_meleeattacks.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/BaseUnit.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/PatrolManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/PatrolState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_explosions.lua" )

FarmbotUnit = class( BaseUnit )

local RoamStartTimeMin = 40 * 4 -- 4 seconds
local RoamStartTimeMax = 40 * 8 -- 8 seconds
local VoiceTickTimeMin = 40 * 5.0
local VoiceTickTimeMax = 40 * 9.0
local ChaseTickTime = 40 * 2.5
local SprintRange = 25.0
local CombatAttackRange = 3.25 -- Range where the unit will perform attacks
local CombatFollowRange = 10.0 -- Range where the unit will follow and attack the player
local FireRange = 16.0
local FireLaneWidth = 0.8
local ShotsPerBarrage = 3
local RangedHeightDiff = 3  -- Height difference where the farmbot considers the target position to be hard to reach
local RangedPitchAngle = 10 -- Angle in degrees where the farmbot considers the target position to be hard to reach
local DeathExplosionTime = 4.5
local AllyRange = 20.0
local MeleeBreachLevel = 9
local HearRange = 40.0
local VoxelDigRadius = 2.8
local VoxelDigStrength = 1.9

function FarmbotUnit.server_onCreate( self )
	self.target = nil
	self.previousTarget = nil
	self.lastTargetPosition = nil
	self.lastAimPosition = nil
	self.ambushPosition = nil
	self.predictedVelocity = sm.vec3.new( 0, 0, 0 )
	self.isDirty = false
	self.raidTargetNonVisiblePlayer = true

	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.stats == nil then
		self.saved.stats = { hp = 1500, maxhp = 1500 }
	end

	InitRobotParams( self )
	if self.saved.patrolling == nil then
		self.saved.patrolling = true
	end
	self.storage:save( self.saved )

	sm.message.subscribe( MESSAGE_TYPES.GENERAL.ProjectileHit, "sv_m_projectileHit" )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.ProjectileFire, "sv_m_projectileFire" )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.Collision, "sv_m_collision" )

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

	self.stateTicker = Ticker()
	self.stateTicker:init()

	-- Idle	
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"
	self.idleState.randomEventCooldownMin = 4
	self.idleState.randomEventCooldownMax = 7.5
	self.idleState.randomEvents = { { name = "idlespecial01", time = 6.0, interruptible = true, chance = 0.5 },
		{ name = "idlespecial02", time = 6.0, interruptible = true, chance = 0.5 } }

	-- Roam
	self.roamTimer = Timer()
	self.roamTimer:start( math.random( RoamStartTimeMin, RoamStartTimeMax ) )
	self.roamState = self.unit:createState( "roam" )
	self.roamState.debugName = "roam"
	self.roamState.tetherPosition = self.unit.character.worldPosition
	self.roamState.roamCenterOffset = 0.0
	self.roamState.customData = { onUnitUpdateOnly = true }

	-- Pathing
	self.pathingState = PathingState()
	self.pathingState:sv_onCreate( self.unit )
	self.pathingState:sv_setMovementType( "walk" )
	self.pathingState.debugName = "pathingState"

	-- Attacks
	self.attackState01 = self.unit:createState( "meleeAttack" )
	self.attackState01.meleeType = melee_farmbotswipe
	self.attackState01.event = "kick"
	self.attackState01.damage = 10
	self.attackState01.attackRange = 2.7
	self.attackState01.animationCooldown = 1.0 * 40
	self.attackState01.attackCooldown = 6.0 * 40
	self.attackState01.globalCooldown = 0.0 * 40
	self.attackState01.attackDelay = 0.375 * 40
	self.attackState01.power = 10000.0

	self.attackState02 = self.unit:createState( "meleeAttack" )
	self.attackState02.meleeType = melee_farmbotswipe
	self.attackState02.event = "walkingswipe"
	self.attackState02.damage = 35
	self.attackState02.attackRange = 3.75
	self.attackState02.animationCooldown = 1.86 * 40
	self.attackState02.attackCooldown = 3.0 * 40
	self.attackState02.globalCooldown = 0.0 * 40
	self.attackState02.attackDelay = 0.75 * 40

	self.attackState03 = self.unit:createState( "meleeAttack" )
	self.attackState03.meleeType = melee_farmbotswipe
	self.attackState03.event = "standingswipe"
	self.attackState03.damage = 35
	self.attackState03.attackRange = 3.75
	self.attackState03.animationCooldown = 1.86 * 40
	self.attackState03.attackCooldown = 1.75 * 40
	self.attackState03.globalCooldown = 0.0 * 40
	self.attackState03.attackDelay = 0.75 * 40

	self.attackPartState = self.unit:createState( "meleeAttack" )
	self.attackPartState.meleeType = melee_farmbotbreach
	self.attackPartState.event = "breachattack"
	self.attackPartState.damage = 60
	self.attackPartState.attackRange = 3.75
	self.attackPartState.animationCooldown = 3.66 * 40
	self.attackPartState.attackCooldown = 4.5 * 40
	self.attackPartState.globalCooldown = 5.0 * 40
	self.attackPartState.attackDelay = 1.55 * 40

	self.attackState05 = self.unit:createState( "meleeAttack" )
	self.attackState05.meleeType = melee_farmbotswipe
	self.attackState05.event = "runningswipe"
	self.attackState05.damage = 35
	self.attackState05.attackRange = 3.75
	self.attackState05.animationCooldown = 1.86 * 40
	self.attackState05.attackCooldown = 8.0 * 40
	self.attackState05.globalCooldown = 0.0 * 40
	self.attackState05.attackDelay = 0.75 * 40

	-- Combat
	self.combatAttackState = CombatAttackState()
	self.combatAttackState:sv_onCreate( self.unit )
	self.combatAttackState.debugName = "combatAttackState"
	self.stateTicker:addState( self.combatAttackState )
	self.combatAttackState:sv_addAttack( self.attackState03 )

	-- CombatFollow
	self.combatFollowAttackState = CombatFollowAttackState()
	self.combatFollowAttackState:sv_onCreate( self.unit )
	self.combatFollowAttackState.debugName = "combatFollowAttackState"
	self.stateTicker:addState( self.combatFollowAttackState )
	self.combatFollowAttackState:sv_addAttack( self.attackState01 )
	self.combatFollowAttackState:sv_addAttack( self.attackState02 )

	-- CombatChase
	self.combatChaseAttackState = CombatFollowAttackState()
	self.combatChaseAttackState:sv_onCreate( self.unit )
	self.combatChaseAttackState:sv_setMovementType( "sprint" )
	self.combatChaseAttackState.debugName = "combatChaseAttackState"
	self.stateTicker:addState( self.combatFollowAttackState )
	self.combatChaseAttackState:sv_addAttack( self.attackState05 )

	-- Breach
	self.breachState = BreachState()
	self.breachState:sv_onCreate( self.unit, math.ceil( 40 * 2.0 ) )
	self.breachState.debugName = "breachState"
	self.stateTicker:addState( self.breachState )
	self.breachState:sv_setBreachRange( CombatAttackRange )
	self.breachState:sv_setBreachLevel( MeleeBreachLevel )
	self.breachState:sv_addAttack( self.attackPartState )

	-- Voxel Breach
	self.voxelBreachState = VoxelBreachState()
	self.voxelBreachState:sv_onCreate( self.unit, math.ceil( 40 * 3.0 ) )
	self.stateTicker:addState( self.voxelBreachState )
	self.voxelBreachState:sv_addAttack( self.attackPartState )
	self.voxelBreachState:sv_setDigRadius( VoxelDigRadius )
	self.voxelBreachState:sv_setDigStrength( VoxelDigStrength )
	self.voxelBreachState.debugName = "voxelBreachState"

	-- Aim in
	self.aimInEventState = self.unit:createState( "wait" )
	self.aimInEventState.debugName = "aimInEventState"
	self.aimInEventState.time = 1.0
	self.aimInEventState.interruptible = false
	self.aimInEventState.name = "aimIn"

	-- RangedAttackWait
	self.rangedWaitState = self.unit:createState( "wait" )
	self.rangedWaitState.debugName = "rangedAttackWait"
	self.rangedWaitState.time = 2.0
	self.rangedWaitState.interruptible = false

	-- RangedAttack
	self.rangedAttack = self.unit:createState( "rangedAttack" )
	self.rangedAttack.debugName = "rangedAttack"
	self.rangedAttack.spreadAngle = 5.0
	self.rangedAttack.cooldown = 1.0
	self.rangedAttack.aimTime = 0.0
	self.rangedAttack.projectile = projectile_pesticide
	self.rangedAttack.event = "shoot"
	self.rangedAttack.damage = 4
	self.rangedAttack.offset = sm.vec3.new( -0.75, 1.0, 1.25 )
	self.rangedAttack.velocity = 16
	self.rangedAttack.preferHighAngle = true
	self.rangedAttack.delay = 12

	-- Aim out
	self.aimOutEventState = self.unit:createState( "wait" )
	self.aimOutEventState.debugName = "aimOutEventState"
	self.aimOutEventState.time = 1.0
	self.aimOutEventState.interruptible = false
	self.aimOutEventState.name = "aimOut"

	self.rangedStates = { self.aimInEventState, self.rangedAttack, self.aimOutEventState, self.rangedWaitState }

	-- Destroyed
	self.destroyedEventState = self.unit:createState( "wait" )
	self.destroyedEventState.debugName = "destroyedState"
	self.destroyedEventState.time = DeathExplosionTime
	self.destroyedEventState.interruptible = false
	self.destroyedEventState.name = "explode"

	-- Angry
	self.angryEventState = self.unit:createState( "wait" )
	self.angryEventState.debugName = "angryState"
	self.angryEventState.time = 3.0
	self.angryEventState.interruptible = false
	self.angryEventState.name = "angry"

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
	initCrushing( self, 20 )

	-- Stomp
	self.stompTimer = Timer()
	self.stompTimer:start( 0.375 * 40 )

	-- Chase timer
	self.chaseTicks = 0

	self.voxelBreachCooldownTicks = 0

	self.currentState = self.idleState
	self.currentState:start()

	-- Voice
	self.voiceTimer = Timer()
	self.voiceTimer:start( math.random( VoiceTickTimeMin, VoiceTickTimeMax ) )
end

function FarmbotUnit.server_onRefresh( self )
end

function FarmbotUnit.server_onDestroy( self )
	BaseUnit.server_onDestroy( self )
	if DEBUG_AI_STATES then
		sm.debugDraw.removeText( "unit_state_" .. self.unit.id )
	end
end

function FarmbotUnit.server_onFixedUpdate( self, dt )
	BaseUnit.server_onFixedUpdate( self )

	if not sm.exists( self.unit ) then
		return
	end

	self.stateTicker:tick()

	if updateCrushing( self ) then
		self:sv_onDeath()
	end

	updateTumble( self )

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

		self:updateAim( dt )
		if not self.currentState.customData or not self.currentState.customData.onUnitUpdateOnly then
			self.currentState:onFixedUpdate( dt )
		end

		self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		local currentMovementType = self.currentState:getMovementType()
		self.unit:setMovementType( currentMovementType )
		self.unit:setFacingDirection( self.currentState:getFacingDirection() )

		if self.currentState == self.idleState then
			self.roamTimer:tick()
		end

		if self.isInCombat then
			self.combatTimer:tick()
		end

		self.impactCooldownTicks = math.max( self.impactCooldownTicks - 1, 0 )
		self.voxelBreachCooldownTicks = math.max( self.voxelBreachCooldownTicks - 1, 0 )

		if self.currentState == self.combatFollowAttackState or self.currentState == self.combatChaseAttackState or self.currentState == self.pathingState then
			self.stompTimer:tick()
			if self.stompTimer:done() then
				self.stompTimer:reset()
				sm.melee.meleeAttack( melee_farmbotstep, 3, self.unit.character.worldPosition + self.unit.character.direction * 0.875 - sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.375 ), self.unit.character.direction * 1.75,
					self.unit, 0, 4000 )
			end
		else
			self.stompTimer:reset()
		end

		self.chaseTicks = math.max( self.chaseTicks - 1, 0 )

		self.voiceTimer:tick()
		if self.voiceTimer:done() then
			self.voiceTimer:start( math.random( VoiceTickTimeMin, VoiceTickTimeMax ) )
			local effectParams = {}
			if not self.isInCombat then
				if currentMovementType == "stand" then
					effectParams.Voice = 1
				else
					effectParams.Voice = 2
				end
			else
				if currentMovementType == "stand" then
					effectParams.Voice = 3
				elseif currentMovementType == "walk" then
					effectParams.Voice = 4
				elseif currentMovementType == "sprint" then
					effectParams.Voice = 5
				end
			end
			sm.event.sendToCharacter( self.unit.character, "sv_e_characterEffect", { effectName = "Farmbot - Voice", effectParams = effectParams } )
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

function FarmbotUnit.server_onCharacterChangedColor( self, color )
	if self.saved.color ~= color then
		self.saved.color = color
		self.storage:save( self.saved )
	end
end

function FarmbotUnit.updateAim( self, dt )
	self.canShootTarget = false
	if self.target and sm.exists( self.target ) and type( self.target ) == "Character" and not self.target:isDowned() then
		local success, aimPoint = sm.ai.getAimPosition( self.unit.character, self.target, FireRange, FireLaneWidth )
		if success then
			-- Predict target movement from its velocity
			local distanceToTarget = (aimPoint - self.unit.character.worldPosition):length()
			local predictionScale = distanceToTarget / math.max( self.rangedAttack.velocity, 1.0 )
			self.rangedAttack.aimPoint = aimPoint + self.predictedVelocity * predictionScale
		elseif self.lastAimPosition then
			self.rangedAttack.aimPoint = self.lastAimPosition
		end
		self.canShootTarget = success
		self.lastAimPosition = self.rangedAttack.aimPoint
	elseif self.lastAimPosition then
		self.rangedAttack.aimPoint = self.lastAimPosition
	end
	return false
end

function FarmbotUnit.server_onUnitUpdate( self, dt )
	if not sm.exists( self.unit ) then
		return
	end

	if self.saved.stats.hp <= 0 and self.currentState ~= self.destroyedEventState then
		self:sv_onDeath()
	end

	if self.unit.character:isTumbling() and self.currentState ~= self.destroyedEventState then
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

	RobotSelectTarget( self, AllyRange, dt )

	-- Raiders without a target search for shapes to destroy
	if self.saved.raidPosition and not self.ambushPosition and not self.lastTargetPosition and not self.target then
		local attackableShape, attackPosition = FindAttackableShape( self.saved.raidPosition, RAIDER_TARGETING_RADIUS, MeleeBreachLevel )
		if attackableShape and attackPosition then
			self.lastTargetPosition = attackPosition
		end
	end

	-- Units with destroyShape spawn param set will attack nearby shapes if they have no player to attack
	if self.saved.destroyShapes and not self.lastTargetPosition and not self.target then
		local attackableShape, attackPosition = FindAttackableShape( self.unit.character.worldPosition, RAIDER_TARGETING_RADIUS, MeleeBreachLevel )
		if attackableShape and attackPosition then
			self.lastTargetPosition = attackPosition
		end
	end

	local inFireRange = false
	local atUnreachableHeight = false
	local inCombatFollowRange = false
	local inCombatAttackRange = false
	local inSprintRange = false

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

		inFireRange = fromToTarget:length() - targetRadius <= FireRange
		inCombatFollowRange = fromToTarget:length() - targetRadius <= CombatFollowRange
		inCombatAttackRange = fromToTarget:length() - targetRadius <= CombatAttackRange
		inSprintRange = fromToTarget:length() - targetRadius >= SprintRange

		local flatFromToTarget = sm.vec3.new( fromToTarget.x, fromToTarget.y, 0 )
		flatFromToTarget = (flatFromToTarget:length() >= FLT_EPSILON) and flatFromToTarget:normalize() or self.unit.character.direction
		local flatDesiredDirection = sm.vec3.new( desiredDirection.x, desiredDirection.y, 0 )
		flatDesiredDirection = (flatDesiredDirection:length() >= FLT_EPSILON) and flatDesiredDirection:normalize() or self.unit.character.direction

		local pitchAngle = math.deg( math.acos( flatFromToTarget:dot( fromToTarget:normalize() ) ) )
		atUnreachableHeight = pitchAngle >= RangedPitchAngle and math.abs( fromToTarget.z ) >= RangedHeightDiff

		self.combatAttackState:sv_setAttackDirection( flatDesiredDirection ) -- Turn ongoing attacks toward moving players
	end

	-- Chase far-away targets
	if self.currentState ~= self.angryEventState and inSprintRange then
		self.chaseTicks = ChaseTickTime
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
	local directPath = false
	if self.lastTargetPosition then
		local directPathDistance = 7.0
		local fromToTarget = self.lastTargetPosition - self.unit.character.worldPosition
		local distance = fromToTarget:length()
		if distance <= directPathDistance then
			directPath = sm.ai.directPathAvailable( self.unit, self.lastTargetPosition, directPathDistance )
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
	local breachStatic = false
	local voxelBreachDestination = nil
	if self.isInCombat then
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
			local valid, breachPosition, breachObject = sm.ai.getBreachablePosition( self.unit, leveledNextTargetPosition, breachDepth + self.unit.character:getRadius(), MeleeBreachLevel )
			if valid and breachPosition then
				local flatFromToNextTarget = leveledNextTargetPosition
				flatFromToNextTarget.z = 0
				if flatFromToNextTarget:length() <= 0 then
					flatFromToNextTarget = sm.vec3.new( 0, 1, 0 )
				end
				breachDestination = nextTargetPosition + flatFromToNextTarget:normalize() * (breachDepth + self.unit.character:getRadius())
				if (type( breachObject ) == "Lift" or type( breachObject ) == "Harvestable") and sm.exists( breachObject ) then
					breachStatic = true
				elseif type( breachObject ) == "Shape" and sm.exists( breachObject ) then
					breachStatic = breachObject.body:isStatic()
				end
			end

			-- Voxel breach check
			if not breachDestination and self.voxelBreachCooldownTicks <= 0 then
				local voxelBlocked, voxelHitPos = GetVoxelBreachPosition( self.unit.character, nextTargetPosition )
				if voxelBlocked then
					voxelBreachDestination = nextTargetPosition
				end
			end
		else
			self.isInCombat = false
		end
	end

	-- Check ranged option
	if self.lastAimPosition == nil and self.lastTargetPosition then
		self.lastAimPosition = self.lastTargetPosition
	end
	local shouldShoot = (inFireRange and atUnreachableHeight and self.canShootTarget) and not ( self.currentState == self.raidFlee )

	local canPatrol
	if self.saved.patrolKey then
		canPatrol = PatrolManager.Sv_IsPatrolActive( self.saved.patrolKey )
	end

	local done, result = self.currentState:isDone()
	local abortState = (self.currentState ~= self.destroyedEventState and self.currentState ~= self.angryEventState and self.currentState ~= self.combatAttackState) and
		(not isAnyOf( self.currentState, self.rangedStates )) and
		(
			(shouldShoot) or
			(self.currentState == self.pathingState and (inCombatFollowRange or inCombatAttackRange) and self.isInCombat) or
			(prevInCombat and self.combatTimer:done()) or
			(self.currentState == self.pathingState and breachDestination) or
			(self.currentState == self.pathingState and voxelBreachDestination) or
			(self.currentState == self.breachState and directPath) or
			(self.currentState == self.voxelBreachState and directPath) or
			(self.chaseTicks > 0 and inSprintRange and self.currentState ~= self.combatChaseAttackState) or
			(self.currentState == self.combatChaseAttackState and self.chaseTicks <= 0) or
			(self.currentState == self.lookAtState and self.isInCombat) or
			(self.currentState == self.roamState and heardNoise)
		)
	if (done or abortState) then
		if self.currentState == self.destroyedEventState then
			self:sv_onDeath()
		elseif self.currentState == self.aimInEventState then
			-- Fire projectiles
			self.currentState = self.rangedAttack
		elseif self.currentState == self.rangedAttack then
			if self.rangedAttack.shotsFired >= ShotsPerBarrage then
				-- Wait for the next barrage
				self.currentState = self.rangedWaitState
			end
		elseif self.currentState == self.rangedWaitState then
			if shouldShoot then
				-- Fire projectiles
				self.currentState = self.rangedAttack
			else
				-- Stop aiming
				self.currentState = self.aimOutEventState
				self.lastAimPosition = nil
			end
		elseif self.currentState == self.pathingState and result == "failed" then
			self.lookAtState.desiredDirection = -self.unit.character.direction
			self.lookAtState.desiredPosition = self.unit.character.worldPosition
			self.currentState = self.lookAtState
			self.roamTimer:start( math.random( RoamStartTimeMin, RoamStartTimeMax ) )
		elseif self.isInCombat and not prevInCombat then
			self.currentState = self.angryEventState
			self.chaseTicks = ChaseTickTime
		elseif shouldShoot then
			-- Start aiming
			self.currentState = self.aimInEventState
		elseif breachDestination and (breachStatic or self.target == nil) then
			-- Start breaching path obstacle
			self.breachState:sv_setDestination( breachDestination )
			self.currentState = self.breachState
		elseif voxelBreachDestination and not directPath then
			-- Start breaching voxel terrain
			self.voxelBreachState:sv_setDestination( voxelBreachDestination )
			self.currentState = self.voxelBreachState
		elseif self.currentState == self.voxelBreachState and result == "timeout" then
			-- Voxel breach failed, cooldown before retrying
			self.voxelBreachCooldownTicks = 40 * 3
			self.currentState = self.pathingState
		elseif self.isInCombat then
			-- Select combat state

			if self.target and self.chaseTicks > 0 then
				self.combatChaseAttackState:sv_setTarget( self.target )
				self.currentState = self.combatChaseAttackState
			elseif self.target and inCombatAttackRange then
				self.currentState = self.combatAttackState
			elseif self.target and inCombatFollowRange then
				self.combatFollowAttackState:sv_setTarget( self.target )
				self.currentState = self.combatFollowAttackState
			elseif self.lastTargetPosition then
				if self.currentState ~= self.pathingState then
					self.pathingState:sv_setDestination( self.lastTargetPosition )
				end
				self.currentState = self.pathingState
				self.lastTargetPosition = nil
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
			elseif self.roamTimer:done() and not (self.currentState == self.idleState and result == "started") then
				self.roamTimer:start( math.random( RoamStartTimeMin, RoamStartTimeMax ) )
				self.currentState = self.roamState
			elseif not (self.currentState == self.roamState and result == "roaming") then
				self.currentState = self.idleState
			end
		end
	end

	if prevState ~= self.currentState then
		if (prevState == self.roamState and self.currentState ~= self.idleState) or (prevState == self.idleState and self.currentState ~= self.roamState) then
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

function FarmbotUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
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
		self:sv_takeDamage( damage, impact, hitPos )
	end
end

function FarmbotUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
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
		local effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -hitDirection )
		sm.effect.playEffect( "Sledgehammer - NoProgress", hitPos, nil, effectRotation )
		if teamOpponent then
			local impact = hitDirection * 6
			self:sv_takeDamage( damage, impact, hitPos )
		end
	end
end

function FarmbotUnit.server_onExplosion( self, center, destructionLevel, radius, damage, src, explosionuuid )
	if not sm.exists( self.unit ) then
		return
	end
	local explosionDamage = self.saved.stats.maxhp * 0.25 -- base explosion damage
	if explosionuuid == EXPLOSIONS.explosion_cornade then
		explosionDamage = self.saved.stats.maxhp * 0.20 -- cornade explosion damage
	end
	local impact = (self.unit:getCharacter().worldPosition - center):safeNormalize( sm.vec3.new( 0, 0, 1 ) ) * 6
	self:sv_takeDamage( explosionDamage, impact, self.unit:getCharacter().worldPosition )
end

function FarmbotUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
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

	local collisionDamageMultiplier = 4.0 -- 4x collision damage. 1/4 maxhp to CharacterCollision for fall damage calculation.
	local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision( self.unit.character, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, self.saved.stats.maxhp / collisionDamageMultiplier,
		nil, self.velocityBuffer, self.velocityBufferIndex )
	damage = damage * collisionDamageMultiplier
	if damage > 0 or tumbleTicks > 0 then
		self.impactCooldownTicks = 6
	end
	if damage > 0 then
		self:sv_takeDamage( damage, collisionNormal, collisionPosition )

		if self.saved.stats.hp <= 0 then
			--Achievement check
			RoadRageAchievementCheck(other)
		end
	end
	if tumbleTicks > 0 then
		if self.currentState ~= self.destroyedEventState then
			self.unit:sendCharacterEvent( "tumble" )
			if startTumble( self, tumbleTicks, self.idleState, tumbleVelocity ) then
				if type( other ) == "Shape" and sm.exists( other ) and other.body:isDynamic() then
					sm.physics.applyImpulse( other.body, impactReaction * other.body.mass, true, collisionPosition - other.body.worldPosition )
				end
			end
		end
	end
end

function FarmbotUnit.sv_updateCharacterTarget( self )
	if self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_e_updateTarget", { target = self.target } )
	end
end

function FarmbotUnit.sv_takeDamage( self, damage, impact, hitPos, source )
	if self.saved.stats.hp > 0 and damage > 0 then
		self.saved.stats.hp = self.saved.stats.hp - damage
		self.saved.stats.hp = math.max( self.saved.stats.hp, 0 )
		local effectRotation = sm.quat.identity()
		if hitPos and impact and impact:length() >= FLT_EPSILON then
			effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -impact:normalize() )
		end

		if self.saved.stats.hp <= 0 then
			self.unit.character:setTumbling( false )
			startTumble( self, self.destroyedEventState.time * 40, self.destroyedEventState, self.unit.character.velocity + sm.vec3.new( 0, 0, 2.5 ) )
		else
			local currentTick = sm.game.getCurrentTick()
			if source ~= "plasma" or not self.lastPlasmaDrillEffectTick or currentTick - self.lastPlasmaDrillEffectTick >= PLASMA_BOT_HIT_EFFECT_TICK_THRESHOLD then
				self.lastPlasmaDrillEffectTick = currentTick
				sm.effect.playEffect( "Farmbot - Hit", hitPos, nil, effectRotation )
			end
			self.storage:save( self.saved )
		end
	end
end

function FarmbotUnit.sv_voxelBreachResult( self, destruction, params )
	local removedAny = destruction and destruction.remDensities and #destruction.remDensities > 0
	if removedAny then
		self.voxelBreachState.noProgressDigCount = 0
	end
end

function FarmbotUnit.sv_onDeath( self )
	local character = self.unit:getCharacter()
	if not self.destroyed then
		g_unitManager:sv_addDeathMarker( character.worldPosition )
		self.saved.stats.hp = 0
		self.unit:destroy()
		-- Create explosion
		sm.physics.explode( character.worldPosition, 7, 2, 6, 25, "Farmbot - Destroyed", nil, { Color = self.unit.character:getColor() }, nil, 35 )
		self.unit:sendCharacterEvent( "death" )
		if SurvivalGame then
			local loot = SelectLoot( "lootsource_farmbot", nil, self.saved.lootType )
			SpawnLoot( self.unit, loot )
			if QuestManager.Sv_IsQuestComplete( "quest_warehouse_destruction" ) and math.random() < 0.5 then
				SpawnLoot( self.unit, { { uuid = ITEMS.obj_survivalobject_keycard, quantity = 1, questItem = true } } )
			end
		end
		BaseUnit.sv_onDeath( self );
		self.destroyed = true
	end
end
