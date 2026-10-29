dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/BaseUnit.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_items.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/BabyWocFollowerState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/managers/BabyWocManager.lua"

BabyWocUnit = class( BaseUnit )

local FleeTimeMin = 3
local FleeTimeMax = 6
local NudgeTime = 0.5

function BabyWocUnit.server_onCreate(self)

    self.baguetteContainer = self.unit:getContainer( BABYWOC_BAGUETTE_CONTAINER_INDEX )
	if not self.baguetteContainer then
		self.baguetteContainer = self.unit:addContainer( BABYWOC_BAGUETTE_CONTAINER_INDEX, 1, 1 )
	end
    self.baguetteContainer:setFilters( { ITEMS.obj_consumable_longsandwich } )

    self.glowstickContainer = self.unit:getContainer( BABYWOC_GLOWSTICK_CONTAINER_INDEX )
	if not self.glowstickContainer then
		self.glowstickContainer = self.unit:addContainer( BABYWOC_GLOWSTICK_CONTAINER_INDEX, 1, 1 )
	end
    self.glowstickContainer:setFilters( { ITEMS.obj_consumable_glowstick } )

    self.saved = self.storage:load()
    if self.saved == nil then
        self.saved = {}
    end
    if LogEntryManager.Sv_HasLog( LOGS.log_babywoc ) then
        if self.params then
            if self.params.playerToFollow then
                self.saved.playerToFollow = self.params.playerToFollow
            end
            if self.params.spawnEffect then
                sm.effect.playEffect( "Babywoc - Spawn", self.unit.character.worldPosition )
            end
        end
        if self.saved.playerToFollow then
            BabyWocManager.Sv_RegisterFollower( self.unit, self.saved.playerToFollow )
        end
    end

    self.storage:save( self.saved )

    self.unit:setWhiskerData( 3, 60 * math.pi / 180, 1.5, 5.0 )
    self.impactCooldownTicks = 0

    -- HangingIdle
    self.hangingIdleState = self.unit:createState( "idle" )
    self.hangingIdleState.debugName = "hangingIdleState"

    -- Idle
    self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

    -- Flee
    self.fleeState = self.unit:createState( "flee" )
    self.fleeState.movementAngleThreshold = math.rad( 180 )

    -- Follower
    self.followerState = BabyWocFollowerState()
    self.followerState:sv_onCreate( self.unit )
    self.followerState.debugName = "followerState"

    -- Tumble
    initTumble( self )

    -- Crushing
    initCrushing( self, DEFAULT_CRUSH_TICK_TIME )

    if LogEntryManager.Sv_HasLog( LOGS.log_babywoc ) then
        self.currentState = self.idleState
    else
        self.currentState = self.hangingIdleState
    end
    self.currentState:start()
end

function BabyWocUnit.server_onRefresh( self )
end

function BabyWocUnit.server_onFixedUpdate( self, dt )

    if updateCrushing( self ) then
        startTumble( self, MEDIUM_TUMBLE_TICK_TIME, self.idleState )
    end

    updateTumble(self)
    updateAirTumble(self, self.idleState)

    if self.currentState then
        self.currentState:onFixedUpdate(dt)
        self.unit:setMovementDirection(self.currentState:getMovementDirection())
        self.unit:setMovementType(self.currentState:getMovementType())
        self.unit:setFacingDirection(self.currentState:getFacingDirection())

        self.impactCooldownTicks = math.max(self.impactCooldownTicks - 1, 0)
    end
end

function BabyWocUnit.server_onUnitUpdate(self, dt)
    if not sm.exists(self.unit) then
        return
    end
    if not LogEntryManager.Sv_HasLog( LOGS.log_babywoc ) then
        return
    end

    if self.currentState then
        self.currentState:onUnitUpdate(dt)
    end

    if self.unit.character:isTumbling() then
        return
    end

    local playerToFollow = BabyWocManager.Sv_GetPlayerToFollow()

    -- Check if need baguette revival
    if sm.exists( playerToFollow ) then
        local characterToFollow = sm.exists( playerToFollow.character ) and playerToFollow.character or nil
        if characterToFollow  and characterToFollow:isDowned() then
            local params = { foodUuid = ITEMS.obj_consumable_longsandwich, playerInventory = self.baguetteContainer }
            sm.event.sendToPlayer( playerToFollow, "sv_e_feed", params )
            sm.achievement.seti("63192fc7-41ae-4a7c-8d1e-294012bcdf32",1,{playerToFollow:getId()})
        end
    end

    local prevState = self.currentState
    local done, result = self.currentState:isDone()
    local abortState = ( self.fleeFrom or self.nudgeFrom ) and self.currentState ~= self.fleeState

    if ( done or abortState ) then
        -- Select state
        if self.fleeFrom or self.nudgeFrom then
            if self.fleeFrom then
                self:sv_flee( self.fleeFrom, true )
            else
                self:sv_flee( self.nudgeFrom, false )
            end
            prevState = self.currentState
            self.fleeFrom = nil
            self.nudgeFrom = nil
        elseif self.currentState == self.fleeState then
            self.currentState = self.idleState
        elseif playerToFollow and sm.exists( playerToFollow.character ) then
            self.currentState = self.followerState
        else
            self.currentState = self.idleState
        end
    end

    if prevState ~= self.currentState then
        prevState:stop()
        self.currentState:start()
    end
end

function BabyWocUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
    if not sm.exists(self.unit) or not sm.exists(attacker) then
        return
    end
    if not LogEntryManager.Sv_HasLog( LOGS.log_babywoc ) then
        return
    end
    if damage > 0 then
        if self.fleeFrom == nil then
            self.fleeFrom = attacker
            self.unit:sendCharacterEvent("hit")
        end
    end
end

function BabyWocUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
    if not sm.exists(self.unit) or not sm.exists(attacker) then
        return
    end
    if not LogEntryManager.Sv_HasLog( LOGS.log_babywoc ) then
        return
    end
    if self.fleeFrom == nil then
        self.fleeFrom = attacker
        self.unit:sendCharacterEvent("hit")
    end

    startTumble(self, SMALL_TUMBLE_TICK_TIME, self.idleState)
    ApplyKnockback(self.unit.character, hitDirection, power)
end

function BabyWocUnit.server_onExplosion(self, center, destructionLevel)
    if not sm.exists(self.unit) then
        return
    end
    if not LogEntryManager.Sv_HasLog( LOGS.log_babywoc ) then
        return
    end
    if self.fleeFrom == nil then
        self.fleeFrom = center
        self.unit:sendCharacterEvent("hit")
    end

    startTumble(self, SMALL_TUMBLE_TICK_TIME, self.idleState)
end

function BabyWocUnit.server_onCollision(self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal)
    if not sm.exists(self.unit) then
        return
    end
    if not LogEntryManager.Sv_HasLog( LOGS.log_babywoc ) then
        return
    end

    -- Nudge away when player walks into the baby woc
    if type( other ) == "Character" and sm.exists( other ) and other:isPlayer() then
        if self.fleeFrom == nil and not self.unit.character:isTumbling() then
            self:sv_flee( other:getPlayer(), false )
        end
    end

    if self.impactCooldownTicks > 0 then
        return
    end

    local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision(self.unit.character, other,
        collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, nil, nil, self.velocityBuffer, self.velocityBufferIndex )
    if damage > 0 or tumbleTicks > 0 then
        self.impactCooldownTicks = 6
    end
    if tumbleTicks > 0 then
        if startTumble(self, tumbleTicks, self.idleState, tumbleVelocity) then
            if type(other) == "Shape" and sm.exists(other) and other.body:isDynamic() then
                sm.physics.applyImpulse(other.body, impactReaction * other.body.mass, true,
                    collisionPosition - other.body.worldPosition)
            end
        end
    end
end

function BabyWocUnit.server_onCollisionCrush(self)
    if not sm.exists(self.unit) then
        return
    end
    if not LogEntryManager.Sv_HasLog( LOGS.log_babywoc ) then
        return
    end
    onCrush(self)
end

function BabyWocUnit.sv_flee( self, from, panic )
    if panic then
        sm.effect.playEffect( "Babywoc - Panic", self.unit.character.worldPosition )
    end
    self.currentState:stop()
    self.currentState = self.fleeState
    if sm.exists(from) then
        self.fleeState.fleeFrom = from
    else
        self.fleeState.fleeFrom = nil
    end
    if panic then
        self.fleeState.maxFleeTime = FleeTimeMin + math.random() * ( FleeTimeMax - FleeTimeMin )
    else
        self.fleeState.maxFleeTime = NudgeTime
    end
    self.fleeState.maxDeviation = 45 * math.pi / 180
    self.currentState:start()
end

function BabyWocUnit.sv_e_receiveDamage(self, damageData)
    if self.fleeFrom == nil then
        self.fleeFrom = damageData.hitPos
        self.unit:sendCharacterEvent("hit")
    end
end
