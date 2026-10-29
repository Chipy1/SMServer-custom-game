dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

VolleyBombLoopState = class( BaseState )
local TerrainCollisionMask = bit.bor( sm.physics.filter.terrainSurface, sm.physics.filter.terrainAsset )

local ProjectileDamage = 15
local FireInterval = math.floor( 40 * 0.50 )
local BombWarningTickTime = 40 * 3
local GunSpreadDegrees = 0.01
local InitialFireDelay = math.floor( 40 * 0.47 )
local ShotsPerInstance = 10
local NearDistance = 8.0
local FarDistance = 60.0
local InitialDirection = sm.vec3.new( 1, 0, 0 )

local VolleyInDuration = 1.0
local VolleyLoopDuration = 10.0
local VolleyOutDuration = 1.0

function VolleyBombLoopState.sv_onCreate( self, unit )
    self.unit = unit
    self.lookDirection = sm.vec3.new( 0, 1, 0 )
    self.leftPosition = sm.vec3.zero()
    self.rightPosition = sm.vec3.zero()
    self.stageIndex = 1
    self.fightType = 1

    self.shootLeft = true

    self.fireTimer = Timer()

    self.volleyInState = self.unit:createState( "wait" )
	self.volleyInState.debugName = "volleyInState"
	self.volleyInState.name = "volley_in"
	self.volleyInState.time = VolleyInDuration
	self.volleyInState.interruptible = false

	self.volleyLoopState = self.unit:createState( "wait" )
	self.volleyLoopState.debugName = "volleyLoopState"
	self.volleyLoopState.name = "volley_loop"
	self.volleyLoopState.time = VolleyLoopDuration
	self.volleyLoopState.interruptible = false

	self.volleyOutState = self.unit:createState( "wait" )
	self.volleyOutState.debugName = "volleyOutState"
	self.volleyOutState.name = "volley_out"
	self.volleyOutState.time = VolleyOutDuration
	self.volleyOutState.interruptible = false

    self.position = self.unit.character.worldPosition

    self.currentState = self.volleyInState
end

function VolleyBombLoopState.refresh( self ) end

function VolleyBombLoopState.sv_setLookDirection( self, lookDirection )
    self.lookDirection = lookDirection
end

function VolleyBombLoopState.sv_setPosition( self, worldPosition )
end

function VolleyBombLoopState.sv_setTarget( self, target )
    local hadTarget = self.target ~= nil
    self.target = target
    self.target = sm.exists( self.target ) and self.target or nil
    if self.target and not hadTarget then
        local offsetAngle = math.random() * 360
		local offsetRange = math.max(math.random() * 10, 5)
        local direction = sm.vec3.new(math.cos(offsetAngle), math.sin(offsetAngle),0)
        self.offsetTargetPosition = self.target.worldPosition + direction * offsetRange
    end
end

function VolleyBombLoopState.sv_setStage( self, stageIndex )
    self.stageIndex = stageIndex
end

function VolleyBombLoopState.setFightType( self, fightType )
    self.fightType = fightType
end


function VolleyBombLoopState.sv_updateVolleyBombardment( self )
    self.fireTimer:tick()
    if self.fireTimer:done() then
        self.fireTimer:start( FireInterval )

        -- Spawn bomb warnings through the trashbot character
        local deathTick = sm.game.getCurrentTick() + BombWarningTickTime

        for _ = 1, ShotsPerInstance do
            local DistanceRange = math.random( NearDistance, FarDistance )
            local RotationRange = math.rad( math.random() * 360 )

            local direction = sm.vec3.rotateZ( InitialDirection, RotationRange )
            local targetPosition = self.position + direction * DistanceRange
            local hit, result = sm.physics.raycast( targetPosition + sm.vec3.new( 0, 0, 50 ), targetPosition - sm.vec3.new( 0, 0, 50 ), nil, TerrainCollisionMask )
            if hit then
                targetPosition = result.pointWorld
            end
            local bombWarnings = { { position = targetPosition, deathTick = deathTick } }
    
            -- Calculate projectile velocity needed to hit the target
            local currentPos = self.shootLeft and self.leftPosition or self.rightPosition
    
            local fromToTarget = targetPosition - currentPos
            local fromToTargetNorm = fromToTarget:safeNormalize( self.lookDirection )
            local aimDot = math.max( fromToTargetNorm:dot( sm.vec3.new( 0, 0, 1 ) ), 0 )
            local velocityExtremeVertical = math.sqrt( sm.vec3.new( 0, 0, fromToTarget.z ):length() * 10 * 2 )
            local velocityExtremeHorizontal = math.sqrt( sm.vec3.new( fromToTarget.x, fromToTarget.y, 0 ):length() * 10 )
            local projectileVelocity = velocityExtremeHorizontal * math.sqrt( 1.0 -  aimDot ) + velocityExtremeVertical * math.sqrt( aimDot )
    
            -- Fire bombs in an arc
            local _, highAngleVector = sm.projectile.solveBallisticArc( currentPos, targetPosition, projectileVelocity, GRAVITY )
            if highAngleVector then
                -- Calculate the spread for both axes
                local horizontalSpreadDegrees = GunSpreadDegrees  -- Adjust as needed
                local verticalSpreadDegrees = GunSpreadDegrees    -- Adjust as needed
    
                -- Generate a random angle for both horizontal and vertical spread
                local randomHorizontalAngle = math.random() * 2 * math.pi
                local randomVerticalAngle = math.random() * 2 * math.pi
    
                -- Calculate the spread vectors for both axes
                local horizontalSpreadVector = sm.vec3.new( math.cos( randomHorizontalAngle ), math.sin( randomHorizontalAngle ), 0 )
                local verticalSpreadVector = sm.vec3.new( math.cos( randomVerticalAngle ), math.sin( randomVerticalAngle ), 0 )
    
                -- Combine the spread vectors to get the final spread vector
                local combinedSpreadVector = horizontalSpreadVector * horizontalSpreadDegrees + verticalSpreadVector * verticalSpreadDegrees
    
                -- Apply the spread to the high angle vector
                local spreadMagnitude = combinedSpreadVector:length()
                local spreadDirection = combinedSpreadVector:safeNormalize( sm.vec3.new( 1.0, 0.0, 0.0 ))
                local highAngleVectorWithSpread = highAngleVector + spreadDirection * spreadMagnitude
                local projectileUuid = projectile_trashbomb_mass_green
                if self.shootLeft then
                    projectileUuid = projectile_trashbomb_mass_purple
                end

                sm.projectile.projectileAttack( projectileUuid, ProjectileDamage, currentPos, highAngleVectorWithSpread, self.unit )
                self.timesFired = self.timesFired + 1
            end
        end
        self.shootLeft = not self.shootLeft
    end
end

--[[API functions]]

function VolleyBombLoopState.start( self )
    self.currentState:stop()
    self.currentState = self.volleyInState
    self.currentState:start()
    self.shootLeft = true

    self.fireTimer:start( InitialFireDelay )
    self.timesFired = 0
    if self.fightType == 1 then
        DialogManager.Sv_PlayShoutDialog( dialog_trashbot_fight, "Volley", nil, DialogSpeakerName.Lorenzo, nil, 60 )
    end
end

function VolleyBombLoopState.stop( self )
    if self.currentState then
        self.currentState:stop()
        self.unit:sendCharacterEvent( "volley_out" )
    end
end

function VolleyBombLoopState.onFixedUpdate( self, dt )
    self.currentState:onFixedUpdate( dt )
		local done, _ = self.currentState:isDone()
		if done then
            if self.currentState.name == "volley_in" then
                self.currentState = self.volleyLoopState
                self.currentState:start()
            elseif self.currentState.name == "volley_loop" then
                self.currentState = self.volleyOutState
                self.currentState:start()
            end
	    end

    self.target = sm.exists( self.target ) and self.target or nil
    if self.target and self.currentState.name == "volley_loop" then
        self:sv_updateVolleyBombardment()
    end
end

function VolleyBombLoopState.onUnitUpdate( self, dt )
    self.currentState:onUnitUpdate( dt )
end

function VolleyBombLoopState.isDone( self )
    if self.currentState == self.volleyOutState then
		local done, _ = self.currentState:isDone()
		return done, "finished"
	elseif self.currentState == self.volleyInState or self.currentState == self.volleyLoopState then
		return false, "sprayGround"
	end
	return true, "unknown state"
end

function VolleyBombLoopState.setLoopDuration( self, loopDuration )
	self.volleyLoopState.time = loopDuration
end

function VolleyBombLoopState.sv_setRightPosition( self, position )
    self.rightPosition = position
end

function VolleyBombLoopState.sv_setLeftPosition( self, position )
    self.leftPosition = position
end