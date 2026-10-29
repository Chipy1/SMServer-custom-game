dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_spawns.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/BaseUnit.lua"

WocUnit = class( BaseUnit )

local RoamStartTimeMin = 40 * 10 -- 10 seconds
local RoamStartTimeMax = 40 * 25 -- 25 seconds
local FleeTimeMin = 40 * 14 -- 14 seconds
local FleeTimeMax = 40 * 20 -- 20 seconds
local EdibleSearchRadius = 6.0
local EdibleReach = 1.75
local CornPerMilk = 5

function WocUnit.server_onCreate( self )

	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.stats == nil then
		self.saved.stats = { hp = 200, maxhp = 200, cornEaten = 0 }
	end

	if self.params then
		if self.params.tetherPoint then
			self.saved.tetherPoint = self.params.tetherPoint
		end
		if self.params.deathTick then
			self.saved.deathTickTimestamp = self.params.deathTick
		end
	end
	if not self.saved.tetherPoint then
		self.saved.tetherPoint = self.unit.character.worldPosition - sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 )
	end
	self.homePosition = self.saved.tetherPoint + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 )

	self.storage:save( self.saved )

	self.unit:setWhiskerData( 3, 60 * math.pi / 180, 1.5, 5.0 )
	self.impactCooldownTicks = 0

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.randomEvents = { { name = "eat", chance = 0.27, interruptible = false, time = 3.66 },
									{ name = "idlespecial01", chance = 0.30, interruptible = false, time = 6.66 },
							   		{ name = "moo", chance = 0.4 },
									{ name = "idlespecial02", chance = 0.03, interruptible = false, time = 29 } }
	self.idleState.debugName = "idleState"

	-- Roam
	self.roamTimer = Timer()
	self.roamTimer:start( math.random( RoamStartTimeMin, RoamStartTimeMax ) )
	self.roamState = self.unit:createState( "flockingRoam" )
	self.roamState.tetherPosition = self.homePosition
	self.roamState.roamCenterOffset = 0.0
	
	-- Flee
	self.fleeState = self.unit:createState( "flee" )
	self.fleeState.movementAngleThreshold = math.rad( 180 )
	self.fleeState.waterAvoidance = false
	
	-- Pathing
	self.pathingState = PathingState()
	self.pathingState:sv_onCreate( self.unit )
	self.pathingState:sv_setTolerance( EdibleReach )
	self.pathingState:sv_setMovementType( "walk" )
	self.pathingState:sv_setWaterAvoidance( false )
	self.pathingState:sv_setWhiskerAvoidance( false )
	self.pathingState.debugName = "pathingState"

	-- Turn
	self.turnState = self.unit:createState( "positioning" )
	self.turnState.debugName = "turnState"
	self.turnState.timeout = 1
	
	-- Eat
	self.eatEventState = self.unit:createState( "wait" )
	self.eatEventState.debugName = "eatEventState"
	self.eatEventState.time = 4.0
	self.eatEventState.interruptible = false
	self.eatEventState.name = "eat"

	-- Tumble
	initTumble( self )
	
	-- Crushing
	initCrushing( self, DEFAULT_CRUSH_TICK_TIME )
	
	self.currentState = self.idleState
	self.currentState:start()
end

function WocUnit.server_onRefresh( self )
end

function WocUnit.server_onFixedUpdate( self, dt )
	if self.saved.isCattle and self.saved.deathTickTimestamp and sm.game.getCurrentTick() >= self.saved.deathTickTimestamp then
		self:sv_onDeath()
	end

	if self.unit.character:isSwimming() then
		self.roamState.waterAvoidance = false
		self.roamState.cliffAvoidance = false
		self.pathingState:sv_setCliffAvoidance( false )
	else
		self.roamState.waterAvoidance = true
		self.roamState.cliffAvoidance = true
		self.pathingState:sv_setCliffAvoidance( true )
	end

	if updateCrushing( self ) then
		self:sv_takeDamage( self.saved.stats.maxhp )
	end
	
	updateTumble( self )
	updateAirTumble( self, self.idleState )

	if self.currentState then
		self.currentState:onFixedUpdate( dt )
		self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		self.unit:setMovementType( self.currentState:getMovementType() )
		self.unit:setFacingDirection( self.currentState:getFacingDirection() )
		
		-- Random roaming during idle
		if self.currentState == self.idleState then
			self.roamTimer:tick()
		end
		self.impactCooldownTicks = math.max( self.impactCooldownTicks - 1, 0 )
	end

	if self.saved.stats.cornEaten >= CornPerMilk then
		self.saved.stats.cornEaten = self.saved.stats.cornEaten - CornPerMilk
		self.saved.stats.hp = self.saved.stats.maxhp
		if SurvivalGame then
			local loot = SelectLoot( "lootsource_woc_milk" )
			SpawnLoot( self.unit, loot )
		end
		self.storage:save( self.saved )
	end
end

function WocUnit.server_onUnitUpdate( self, dt )

	if not sm.exists( self.unit ) then
		return
	end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end

	if self.unit.character:isTumbling() then
		return
	end

	-- Find corn
	local targetCorn, cornInRange = FindNearbyEdible( self.unit.character, obj_resource_corn, EdibleSearchRadius, EdibleReach )

	local prevState = self.currentState
	local done, result = self.currentState:isDone()
	local abortState = 	(
							( self.fleeFrom ) or
							( ( self.currentState == self.pathingState or self.currentState == self.roamState ) and cornInRange )
						)

	if ( done or abortState ) then
		-- Select state
		if self.fleeFrom then
			self:sv_flee( self.fleeFrom )
			prevState = self.currentState
			self.fleeFrom = nil
		elseif self.currentState == self.fleeState or self.currentState == self.eatEventState then
			self.currentState = self.idleState
		elseif targetCorn then
			if cornInRange then
				local eatFacingDirection = ( targetCorn.worldPosition - self.unit.character.worldPosition ):safeNormalize( self.currentState:getFacingDirection() )
				local facingDirection = self.currentState:getFacingDirection()
				local facingXY = sm.vec3.new( facingDirection.x, facingDirection.y, 0 ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
				local eatFacingXY = sm.vec3.new( eatFacingDirection.x, eatFacingDirection.y, 0 ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
				if self.currentState == self.turnState or facingXY:dot( eatFacingXY ) > math.cos( math.rad( 10 ) ) then
					self.currentState = self.eatEventState
					self.saved.stats.cornEaten = self.saved.stats.cornEaten + 1
					self.saved.deathTickTimestamp = sm.game.getCurrentTick() + DaysInTicks( 30 ) -- Neglected Wocs die after 30 days
					if not self.saved.isCattle then
						local x = math.floor( self.saved.tetherPoint.x / CELL_SIZE )
						local y = math.floor( self.saved.tetherPoint.y / CELL_SIZE )
						local worldId = self.unit:getCharacter():getWorld():getId()
						UntrackUnitRespawn( { x = x, y = y, worldId = worldId }, "WOC", self.unit )
					end
					self.saved.tetherPoint = self.unit.character.worldPosition -- Stay where fed
					self.saved.isCattle = true
					targetCorn:destroyShape()
					self.storage:save( self.saved )
				else
					self.turnState.desiredPosition = self.unit.character.worldPosition
					self.turnState.desiredDirection = eatFacingDirection
					self.currentState = self.turnState
				end
			else
				self.pathingState:sv_setDestination( targetCorn.worldPosition )
				self.currentState = self.pathingState
			end
		elseif self.currentState == self.turnState then
			self.currentState = self.idleState
		elseif self.roamTimer:done() and not ( self.currentState == self.idleState and result == "started" ) then
			self.roamTimer:start( math.random( RoamStartTimeMin, RoamStartTimeMax ) )
			self.currentState = self.roamState
		elseif not ( self.currentState == self.roamState and result == "roaming" ) then
			self.currentState = self.idleState
		end
	end

	if prevState ~= self.currentState then
		prevState:stop()
		self.currentState:start()
		if DEBUG_AI_STATES then
			print( self.currentState.debugName )
		end
	end
end

function WocUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if not sm.exists( self.unit ) or not sm.exists( attacker ) then
		return
	end
	if damage > 0 then
		if self.fleeFrom == nil then
			self.fleeFrom = attacker
			self.unit:sendCharacterEvent( "hit" )
		end
	end

	self:sv_takeDamage( damage )
end

function WocUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if not sm.exists( self.unit ) or not sm.exists( attacker ) then
		return
	end
	if self.fleeFrom == nil then
		self.fleeFrom = attacker
		self.unit:sendCharacterEvent( "hit" )
	end

	startTumble( self, SMALL_TUMBLE_TICK_TIME, self.idleState, hitDirection * 5 )
	self:sv_takeDamage( damage )
	ApplyKnockback( self.unit.character, hitDirection, power )
end

function WocUnit.server_onExplosion( self, center, destructionLevel, radius, uDamage, src, srcTypeUid)
	if not sm.exists( self.unit ) then
		return
	end
	local hitDirection = ( self.unit.character.worldPosition - center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) )
	if self.fleeFrom == nil then
		self.fleeFrom = center
		self.unit:sendCharacterEvent( "hit" )
	end
	startTumble( self, SMALL_TUMBLE_TICK_TIME, self.idleState, hitDirection * destructionLevel * 2 )
	self:sv_takeDamage( self.saved.stats.maxhp * ( destructionLevel / 10 ) )
	ApplyKnockback( self.unit.character, hitDirection, destructionLevel * 1000 )
	if self.saved.stats.hp <= 0 then
		if srcTypeUid == ITEMS.obj_interactive_propanetank_large or srcTypeUid == ITEMS.obj_interactive_propanetank_small then
			local allPlayers = {}
			for i, player in ipairs( sm.player.getAllPlayers() ) do
				table.insert( allPlayers, player.id )
			end
			sm.achievement.seti( "c0046451-4cac-4483-aafd-dbc1bb075c81", 1, allPlayers )
		end
	end
end

function WocUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if not sm.exists( self.unit ) then
		return
	end

	if self.impactCooldownTicks > 0 then
		return
	end

	local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision( self.unit.character, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, self.saved.stats.maxhp, nil, self.velocityBuffer, self.velocityBufferIndex )
	if damage > 0 or tumbleTicks > 0 then
		self.impactCooldownTicks = 6
	end
	if damage > 0 then
		self:sv_takeDamage( damage )
		if self.saved.stats.hp <= 0 or self.crushUpdate then
			RoadRageAchievementCheck( other )
		end
	end
	if tumbleTicks > 0 then
		if startTumble( self, tumbleTicks, self.idleState, tumbleVelocity ) then
			if type( other ) == "Shape" and sm.exists( other ) and other.body:isDynamic() then
				sm.physics.applyImpulse( other.body, impactReaction * other.body.mass, true, collisionPosition - other.body.worldPosition )
			end
		end
	end
end

function WocUnit.server_onCollisionCrush( self )
	if not sm.exists( self.unit ) then
		return
	end
	onCrush( self )
end

function WocUnit.sv_flee( self, from )
	self.currentState:stop()
	self.currentState = self.fleeState
	if sm.exists( from ) then
		self.fleeState.fleeFrom = from
	else
		self.fleeState.fleeFrom = nil
	end
	self.fleeState.maxFleeTime = math.random( FleeTimeMin, FleeTimeMax ) / 40
	self.fleeState.maxDeviation = 45 * math.pi / 180
	self.currentState:start()
end

function WocUnit.sv_e_receiveDamage( self, damageData )
	if self.fleeFrom == nil then
		self.fleeFrom = damageData.hitPos
		self.unit:sendCharacterEvent( "hit" )
	end
	self:sv_takeDamage( damageData.damage )
end

function WocUnit.sv_takeDamage( self, damage )
	if self.saved.stats.hp > 0 then
		self.saved.stats.hp = self.saved.stats.hp - damage
		self.saved.stats.hp = math.max( self.saved.stats.hp, 0 )

		if self.saved.stats.hp <= 0 then
			self:sv_onDeath()
			sm.effect.playEffect( "Woc - Destruct", self.unit.character.worldPosition )
		else
			self.storage:save( self.saved )
			sm.effect.playEffect( "Woc - Panic", self.unit.character.worldPosition )
		end
	end
end

function WocUnit.sv_onDeath( self )
	if not self.destroyed then
		self.saved.stats.hp = 0
		self.unit:destroy()
		if SurvivalGame then
			local loot = SelectLoot( "lootsource_woc" )
			SpawnLoot( self.unit, loot )
		end
		self.destroyed = true
	end
end

function WocUnit.sv_e_receiveTarget( self, params )
end