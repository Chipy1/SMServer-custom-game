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
dofile "$SURVIVAL_DATA/Scripts/game/units/states/IdleRoamSwimState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/TorpedoAttackState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/TotebotBlueChargeState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/BreachState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/VoxelBreachState.lua"

TotebotBlueUnit = class( BaseTotebotUnit )

local CombatAttackRange = 1.0 -- Range where the unit will perform attacks
local CombatApproachRange = 2.25 -- Range where the unit will approach the player without obstacle checking
local ChargeSetupRange = 8.0 -- Range where charge state begins windup

local AllyRange = 20.0
local HearRange = 40.0
local MeleeBreachLevel = 9

local PushbackHorizontalForce = 4
local PushbackVerticalForce = 3
local HitStunDuration = 0.5
local KnockbackTickInvulnerability = 0.5 * 40
local RetaliationHitWindow = 1.0 * 40 -- If hit again within this window, retaliate with an instant charge
local RetaliationPushbackForce = 20

local VoxelDigRadius = 1.0
local VoxelDigStrength = 0.75

function TotebotBlueUnit.server_onCreate( self )
	BaseTotebotUnit.server_onCreate( self )

	self.target = nil
	self.waterTarget = nil
	self.previousTarget = nil
	self.lastTargetPosition = nil
	self.ambushPosition = nil
	self.predictedVelocity = sm.vec3.new( 0, 0, 0 )
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.stats == nil then
		self.saved.stats = { hp = 60, maxhp = 60 }
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

	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Idle / Roam Swimming
	self.idleRoamSwimState = IdleRoamSwimState()
	self.idleRoamSwimState:sv_onCreate( self.unit, self.homePosition )
	self.idleRoamSwimState.debugName = "idleRoamSwimState"

	-- Idle / Roam Land
	self.idleRoamState = IdleRoamState()
	self.idleRoamState:sv_onCreate( self.unit, self.homePosition )
	self.idleRoamState.debugName = "idleRoamState"
	self.idleRoamState.roamState.waterAvoidance = false
	self.idleRoamState.roamState.cliffAvoidance = false
	self.idleRoamState.roamState.roamCenterOffset = 0.0

	self.idleRoamState.idleState.randomEventCooldownMin = 3.0 -- tweak here dev values
	self.idleRoamState.idleState.randomEventCooldownMax = 8.0 -- tweak here dev values
	self.idleRoamState.idleState.randomEvents = { { name = "idlespecial01", chance = 0.3, interruptible = true, time = 5.0 },
										{ name = "idlespecial02", chance = 0.3, interruptible = true, time = 4.66 } }

	-- Torpedo attack
	self.torpedoAttackState = TorpedoAttackState()
	self.torpedoAttackState:sv_onCreate( self.unit )
	self.torpedoAttackState.debugName = "torpedoAttackState"

	-- Land charge attack
	self.totebotBlueChargeState = TotebotBlueChargeState()
	self.totebotBlueChargeState:sv_onCreate( self.unit )
	self.totebotBlueChargeState.debugName = "totebotBlueChargeState"

	-- Pathing
	self.pathingState = PathingState()
	self.pathingState:sv_onCreate( self.unit )
	self.pathingState:sv_setTolerance( 1.0 )
	self.pathingState:sv_setMovementType( "walk" )
	self.pathingState:sv_setWaterAvoidance( false )
	self.pathingState:sv_setCliffAvoidance( false )
	self.pathingState.debugName = "pathingState"

	-- Attacks
	self.attackState01 = self.unit:createState( "meleeAttack" )
	self.attackState01.meleeType = melee_totebotattack
	self.attackState01.event = "melee"
	self.attackState01.damage = 20
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
	self.combatApproachState.movementType = "walk"
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

	-- Hit stun state
	self.hitStunState = self.unit:createState( "wait" )
	self.hitStunState.debugName = "hitStunState"
	self.hitStunState.name = "jump"
	self.hitStunState.time = HitStunDuration
	self.hitStunState.interruptible = false

	-- Tumble
	initTumble( self )

	-- Crushing
	initCrushing( self, DEFAULT_CRUSH_TICK_TIME )

	self.voxelBreachCooldownTicks = 0
	self.lastKnockTick = 0
	self.lastHitTick = 0
	self.torpedoDrillActive = false

	self.currentState = self.idleRoamSwimState
	self.currentState:start()
end

function TotebotBlueUnit.server_onDestroy( self )
	BaseTotebotUnit.server_onDestroy( self )
	if DEBUG_AI_STATES then
		sm.debugDraw.removeText( "unit_state_" .. self.unit.id )
	end
end

function TotebotBlueUnit.server_onRefresh( self )
end

function TotebotBlueUnit.server_onFixedUpdate( self, dt )
	BaseUnit.server_onFixedUpdate( self )

	self.stateTicker:tick()

	if updateCrushing( self ) then
		self:sv_onDeath( sm.vec3.new( 0, 0, 0 ) )
	end

	updateTumble( self )
	local inImmuneState = isAnyOf( self.currentState, { self.torpedoAttackState } )
	if inImmuneState or self.isInCombat then
		self.airTicks = 0
	else
		updateAirTumble( self, self.idleRoamSwimState )
	end

	if self.currentState then
		if self.target and not sm.exists( self.target ) then
			self.target = nil
		end
		if self.waterTarget and not sm.exists( self.waterTarget ) then
			self.waterTarget = nil
		end

		self.currentState:onFixedUpdate( dt )
		self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		self.unit:setMovementType( self.currentState:getMovementType() )
		self.unit:setFacingDirection( self.currentState:getFacingDirection() )
		self.unit:setWantsJump( self.currentState:getWantsJump() )

		if self.isInCombat then
			self.combatTimer:tick()
		end

		self.impactCooldownTicks = math.max( self.impactCooldownTicks - 1, 0 )
		self.voxelBreachCooldownTicks = math.max( self.voxelBreachCooldownTicks - 1, 0 )

		-- Sync torpedo drill state to the character for the drill effect
		local torpedoDrillActive = self.currentState == self.torpedoAttackState and self.torpedoAttackState.currentState == self.torpedoAttackState.torpedoState
		if torpedoDrillActive ~= self.torpedoDrillActive then
			self.torpedoDrillActive = torpedoDrillActive
			if sm.exists( self.unit.character ) then
				sm.event.sendToCharacter( self.unit.character, "sv_e_setTorpedoActive", torpedoDrillActive, sm.event.types.instant )
			end
		end
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

function TotebotBlueUnit.server_onCharacterChangedColor( self, color )
	if self.saved.color ~= color then
		self.saved.color = color
		self.storage:save( self.saved )
	end
end

function TotebotBlueUnit.sv_updateWaterTarget( self )
	if not sm.game.getEnableAggro() then
		self.waterTarget = nil
		return
	end
	if not sm.exists( self.target ) and not sm.exists( self.waterTarget ) and self.unit.character:isSwimming() then
		local underwaterSenseRadius = 60
		local selfCharacterPosition = self.unit.character.worldPosition
		local contacts = sm.physics.getSphereContacts( selfCharacterPosition, underwaterSenseRadius )
		local closestTarget = nil
		local closestDistance2 = math.huge
		local terrainMask = sm.physics.filter.terrainSurface + sm.physics.filter.terrainAsset
		for _, character in ipairs( contacts.characters ) do
			if sm.exists( character ) and self.unit.character ~= character then
				local validTargetCharacter = character:isPlayer() and not character:isDowned() and character:isSwimming()
				if validTargetCharacter then
					local targetCharacterPosition = character.worldPosition
					local fromToCharacter = targetCharacterPosition - selfCharacterPosition
					local distance2 = fromToCharacter:length2()
					if distance2 < closestDistance2 then
						local blocked, _ = sm.physics.raycast( selfCharacterPosition, targetCharacterPosition, nil, terrainMask )
						if not blocked then
							closestTarget = character
							closestDistance2 = distance2
						end
					end
				end
			end
		end
		self.waterTarget = closestTarget
	end

	if self.waterTarget then
		if not sm.exists( self.waterTarget ) or self.waterTarget:isDowned() or not self.waterTarget:isSwimming() then
			self.waterTarget = nil
		else
			-- Forget the target if terrain now blocks the line of sight
			local terrainMask = sm.physics.filter.terrainSurface + sm.physics.filter.terrainAsset
			local blocked = sm.physics.raycast( self.unit.character.worldPosition, self.waterTarget.worldPosition, nil, terrainMask )
			if blocked then
				self.waterTarget = nil
			end
		end
	end
	if self.target == nil and self.waterTarget then
		self.lastTargetPosition = self.waterTarget.worldPosition
	end
end

function TotebotBlueUnit.server_onUnitUpdate( self, dt )
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
	self:sv_updateWaterTarget()

	-- Raiders without a target search for shapes to destroy
	if self.saved.raidPosition and not self.target and sm.exists( self.unit.character ) then
		local raidSpots = RaidManager.Sv_GetPlantLocations( self.unit.character:getWorld().id, self.saved.raidKey )
		if #raidSpots > 0 and ( self.saved.randomPlotTarget == nil or self.saved.randomPlotTarget > #raidSpots ) then
			self.saved.randomPlotTarget = math.random( #raidSpots )
			self.isDirty = true
			local closestSpot = raidSpots[self.saved.randomPlotTarget]
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

	-- Update land based attacks
	local inCombatApproachRange = false
	local inCombatAttackRange = false
	local targetIsPlayer = self.target and type( self.target ) == "Character" and self.target:isPlayer()
	if targetIsPlayer and not self.target:isDowned() then
		self.totebotBlueChargeState:sv_setTarget( self.target )
	elseif self.currentState == self.totebotBlueChargeState then
		self.totebotBlueChargeState:sv_setTarget( nil )
	end
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
			nextTargetPosition = self.unit.character.worldPosition + self.unit.character.direction
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
			breachDestination = nextTargetPosition + flatFromToNextTarget:safeNormalize( sm.vec3.zero() ) * breachDepth
		end

		-- Voxel breach check
		if not breachDestination and self.voxelBreachCooldownTicks <= 0 then
			local voxelBlocked, voxelHitPos = GetVoxelBreachPosition( self.unit.character, nextTargetPosition )
			if voxelBlocked then
				voxelBreachDestination = nextTargetPosition
			end
		end
	end

	-- Update torpedoAttackState destination
	if self.currentState == self.torpedoAttackState then
		if self.waterTarget then
			self.torpedoAttackState:sv_setTarget( self.waterTarget )
		elseif self.lastTargetPosition then
			self.torpedoAttackState:sv_setTargetPosition( self.lastTargetPosition )
		else
			self.torpedoAttackState:sv_setTargetPosition( nil )
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

	local isSwimming = self.unit.character:isSwimming()
	local restartState = false
	local done, result = self.currentState:isDone()
	-- Check if pathing state should abort to allow charge windup
	local abortPathingForCharge = false
	if self.currentState == self.pathingState and targetIsPlayer and not isSwimming and self.lastTargetPosition then
		local targetRadius = self.target:getRadius()
		local distanceToTarget = ( self.lastTargetPosition - self.unit.character.worldPosition ):length() - targetRadius - self.unit.character:getRadius()
		if distanceToTarget <= ChargeSetupRange then
			abortPathingForCharge = true
		end
	end
		local abortState = ( self.currentState ~= self.combatAttackState ) and
						( self.currentState ~= self.avoidState ) and
						( self.currentState ~= self.hitStunState ) and
						(
							( not targetIsPlayer and self.currentState == self.pathingState and ( inCombatApproachRange or inCombatAttackRange ) and self.isInCombat ) or
							( prevInCombat and self.combatTimer:done() ) or
							( self.currentState == self.lookAtState and self.isInCombat ) or
							( isAnyOf( self.currentState, { self.idleRoamSwimState, self.idleRoamState } ) and ( heardNoise or self.isInCombat ) ) or
							( isAnyOf( self.currentState, { self.pathingState, self.idleRoamState, self.totebotBlueChargeState } ) and isSwimming ) or
							( isAnyOf( self.currentState, { self.torpedoAttackState, self.idleRoamSwimState } ) and not isSwimming ) or
							( self.currentState == self.pathingState and breachDestination ) or
							( self.currentState == self.pathingState and voxelBreachDestination ) or
								( self.currentState == self.breachState and directPath ) or
								( abortPathingForCharge )
						)

	if ( done or abortState ) then
		-- Select state
		if self.currentState == self.hitStunState or ( self.currentState == self.totebotBlueChargeState and result == "lost" )then
			if self.isInCombat then
				if self.lastTargetPosition then
					self.currentState = self.pathingState
					self.pathingState:sv_setDestination( self.lastTargetPosition )
				else
					self.isInCombat = false
				end
			else
				if isSwimming then
					self.currentState = self.idleRoamSwimState
				else
					self.currentState = self.idleRoamState
				end
			end
		elseif abortPathingForCharge then
			-- Abort pathing to begin charge windup
			self.currentState = self.totebotBlueChargeState
		elseif self.currentState == self.combatApproachState and done then
			-- Attack towards the approached target
			self.currentState = self.combatAttackState
		elseif breachDestination then
			-- Start breaching path obstacle
			if isSwimming then
				self.torpedoAttackState:sv_setTargetPosition( breachDestination )
				self.currentState = self.torpedoAttackState
			else
				self.breachState:sv_setDestination( breachDestination )
				self.currentState = self.breachState
			end
		elseif voxelBreachDestination then
			if isSwimming then
				-- Swimming: torpedo through voxel terrain
				if self.waterTarget then
					self.torpedoAttackState:sv_setTarget( self.waterTarget )
				elseif self.lastTargetPosition then
					self.torpedoAttackState:sv_setTargetPosition( self.lastTargetPosition )
				end
				self.currentState = self.torpedoAttackState
			else
				-- Land: use voxel breach state
				self.voxelBreachState:sv_setDestination( voxelBreachDestination )
				self.currentState = self.voxelBreachState
			end
		elseif self.currentState == self.voxelBreachState and result == "timeout" then
			-- Voxel breach failed, cooldown before retrying
			self.voxelBreachCooldownTicks = 40 * 3
			self.currentState = self.pathingState
		elseif self.currentState == self.pathingState and result == "failed" then
			self.avoidState.desiredDirection = self.unit.character.direction
			self.avoidState.desiredPosition = self.unit.character.worldPosition - self.avoidState.desiredDirection:normalize() * 2
			self.currentState = self.avoidState
		elseif self.isInCombat then
			-- Select combat state
			if isSwimming then
				-- Swimming
				if self.waterTarget then
					self.torpedoAttackState:sv_setTarget( self.waterTarget )
				elseif self.lastTargetPosition then
					self.torpedoAttackState:sv_setTargetPosition( self.lastTargetPosition )
				end
				self.currentState = self.torpedoAttackState
				self.lastTargetPosition = nil
			elseif self.currentState == self.torpedoAttackState and not self.unit.character:isOnGround() then
				-- Remain in torpedo state until landing
				self.currentState = self.torpedoAttackState
			else
				-- On Land
				if targetIsPlayer then
					self.currentState = self.totebotBlueChargeState
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
			end
		else
			-- Select non-combat state
			if heardNoise then
				self.currentState = self.lookAtState
			else
				if isSwimming then
					self.currentState = self.idleRoamSwimState
				else
					self.currentState = self.idleRoamState
				end
			end
		end
	end

	if prevState ~= self.currentState or restartState then
		local wasRoaming = isAnyOf( prevState, { self.idleRoamState, self.idleRoamSwimState } )
		local isAlert = not isAnyOf( self.currentState, { self.idleRoamState, self.idleRoamSwimState } )
		if wasRoaming and isAlert then
			self.unit:sendCharacterEvent( "alerted" )
		elseif not wasRoaming and not isAlert then
			self.unit:sendCharacterEvent( "roaming" )
		end

		prevState:stop()
		self.currentState:start()
		if DEBUG_AI_STATES then
			print( self.currentState.debugName )
		end
	end

























end

function TotebotBlueUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
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

		local pushDirection = ComputePushbackDirection( self.unit.character, hitVelocity )
		self:sv_onHitReaction( attacker, pushDirection, false )
	end
end

function TotebotBlueUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
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
		self:sv_takeDamage( damage, impact, hitPos )

		local pushDirection = ComputePushbackDirection( self.unit.character, hitDirection )
		self:sv_onHitReaction( attacker, pushDirection, true )
	end
end

function TotebotBlueUnit.server_onExplosion( self, center, destructionLevel )
	if not sm.exists( self.unit ) then
		return
	end
	local impact = ( self.unit:getCharacter().worldPosition - center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) ) * 6
	self:sv_takeDamage( self.saved.stats.maxhp, impact, self.unit:getCharacter().worldPosition )
end

function TotebotBlueUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
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
	local hitByRailKinematic = type( other ) == "Harvestable" and sm.exists( other ) and other.publicData and other.publicData.isRailKinematic

	if self.impactCooldownTicks > 0 then
		return
	end

	local inImmuneState = isAnyOf( self.currentState, { self.torpedoAttackState, self.totebotBlueChargeState } )
	if not inImmuneState then
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
				if startTumble( self, tumbleTicks, self.idleState, tumbleVelocity ) then
					if type( other ) == "Shape" and sm.exists( other ) and other.body:isDynamic() then
						sm.physics.applyImpulse( other.body, impactReaction * other.body.mass, true, collisionPosition - other.body.worldPosition )
					end
				end
			end
		end
	end
end

function TotebotBlueUnit.server_onCollisionCrush( self )
	if not sm.exists( self.unit ) then
		return
	end
	onCrush( self )
end

function TotebotBlueUnit.sv_updateCharacterTarget( self )
	if self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_n_updateTarget", { target = self.target } )
	end
end

function TotebotBlueUnit.sv_voxelBreachResult( self, destruction, params )
	local removedAny = destruction and destruction.remDensities and #destruction.remDensities > 0
	if removedAny and self.voxelBreachState then
		self.voxelBreachState.noProgressDigCount = 0
	end
end

function TotebotBlueUnit.sv_onDeath( self, impact )
	local character = self.unit:getCharacter()
	if not self.destroyed then
		self.unit:sendCharacterEvent( "death" )
		g_unitManager:sv_addDeathMarker( character.worldPosition )
		self.saved.stats.hp = 0
		self.unit:destroy()
		self:sv_spawnParts( impact )
		if SurvivalGame then
			local loot = SelectLoot( "lootsource_totebot_blue", nil, self.saved.lootType )
			SpawnLoot( self.unit, loot )
		end
		self.destroyed = true
		BaseUnit.sv_onDeath( self )
	end
end

function TotebotBlueUnit.sv_spawnParts( self, impact )
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
			local headShape = headBody:createPart( ITEMS.obj_interactive_robotbasshead, sm.vec3.new( 0, 1, 2 ), sm.vec3.new( 0, 1, 0 ), sm.vec3.new( -1, 0, 0 ), true )
			headShape.color = color
			sm.physics.applyImpulse( headShape, impact * headShape.mass, true )
		end
	end
end

function TotebotBlueUnit.sv_onHitReaction( self, attacker, pushDirection, isMelee )
	local attackerIsPlayer = type( attacker ) == "Player"
	local tick = sm.game.getCurrentTick()
	local onLand = not self.unit.character:isSwimming()

	if attackerIsPlayer and onLand and ( tick - self.lastHitTick ) <= RetaliationHitWindow then
		-- Retaliate with instant charge instad of being stunned
		local attackerCharacter = attacker:getCharacter()
		self.target = attackerCharacter
		self.lastTargetPosition = attackerCharacter.worldPosition
		self.isInCombat = true
		self.combatTimer:reset()
		self.lastHitTick = tick

		if isMelee and self.saved.stats.hp > 0 then
			local shoveDirection = attackerCharacter.worldPosition - self.unit.character.worldPosition
			shoveDirection = sm.vec3.new( shoveDirection.x, shoveDirection.y, 0 ):safeNormalize( self.unit.character.direction )
			sm.physics.applyImpulse( attackerCharacter, shoveDirection * attackerCharacter.mass * RetaliationPushbackForce, true )
		end

		self.totebotBlueChargeState:sv_setRetaliate( attackerCharacter )
		self.currentState:stop()
		self.currentState = self.totebotBlueChargeState
		self.currentState:start()
		return
	end

	self.lastHitTick = tick
	if isMelee then
		self.currentState:stop()
		self.currentState = self.hitStunState
		self.currentState:start()
		self:ApplyDamagePushback( pushDirection )
	end
end

function TotebotBlueUnit.ApplyDamagePushback( self, pushDirection )
	local tick = sm.game.getCurrentTick()
	if tick - self.lastKnockTick >= KnockbackTickInvulnerability then
		self.lastKnockTick = tick
		sm.physics.applyImpulse( self.unit.character, ( pushDirection * self.unit.character.mass * PushbackHorizontalForce ) + ( sm.vec3.new( 0, 0, 1 ) * self.unit.character.mass * PushbackVerticalForce ), true )
	end
end


