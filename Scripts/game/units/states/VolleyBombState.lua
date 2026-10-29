dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

VolleyBombState = class( BaseState )
local TerrainCollisionMask = bit.bor( sm.physics.filter.terrainSurface, sm.physics.filter.terrainAsset )

local ProjectileDamage = 0
local StartupDelay = math.floor( 40 * 0.4 )
local VolleysPerAttack = 1
local BombWarningTickTime = 40 * 3
--local MaxOffsetRange = 3.0
--local GoldenRatio = ( math.sqrt( 5 ) + 1 ) / 2
--local Smoothness = 2.0

local VelocityModifier = 1.1
local MaxRange = 47.0

function VolleyBombState.sv_onCreate( self, unit, isRightSide )
    self.unit = unit
    self.lookDirection = sm.vec3.new( 0, 1, 0 )
    self.worldPosition = sm.vec3.zero()
    self.stageIndex = 1
    self.isRightSide = isRightSide

    self.projectileUuid = projectile_trashbomb_green
    if not self.isRightSide then
        self.projectileUuid = projectile_trashbomb_purple
    end

    self.waitState = self.unit:createState( "wait" )
    self.waitState.debugName = "waitState"
    self.waitState.time = 1.0
    self.waitState.interruptible = false

    self.fireTimer = Timer()
    self.timesFired = 0
end

function VolleyBombState.refresh( self ) end

function VolleyBombState.sv_setLookDirection( self, lookDirection )
    self.lookDirection = lookDirection
end

function VolleyBombState.sv_setPosition( self, worldPosition )
    self.worldPosition = worldPosition
end

function VolleyBombState.sv_setTarget( self, target )
    self.target = target
    self.target = sm.exists( self.target ) and self.target or nil
end

function VolleyBombState.sv_setStage( self, stageIndex )
    self.stageIndex = stageIndex
end


function VolleyBombState.sv_updateVolleyBombardment( self )
    if self.timesFired < VolleysPerAttack then
        self.fireTimer:tick()
        if self.fireTimer:done() then
            self.fireTimer:stop()
            local deathTick = sm.game.getCurrentTick() + BombWarningTickTime
            local bombWarnings = {}
            for i = 1, VolleysPerAttack do
                -- Spawn bomb warnings through the trashbot character
                
                local targetPosition = self.target.worldPosition
                local fromToTarget = targetPosition - self.worldPosition
                local fromToTargetNorm = fromToTarget:safeNormalize( self.lookDirection )
                local distanceToTarget = fromToTarget:length()
                if distanceToTarget > MaxRange then
                    targetPosition = self.worldPosition + fromToTargetNorm * MaxRange
                    fromToTarget = targetPosition - self.worldPosition
                end
                -- sunflower pattern
                --local boundaryPoints = round( Smoothness * math.sqrt( VolleysPerAttack ) )
                --local radius = MaxOffsetRange
                --if i <= VolleysPerAttack - boundaryPoints then
                --    radius = ( math.sqrt( i - 1 / 2 ) / math.sqrt( VolleysPerAttack - ( boundaryPoints + 1 ) / 2 ) ) * MaxOffsetRange
                --end
                --local theta = 2 * math.pi * i / GoldenRatio ^ 2
                --local volleyOffset = sm.vec3.new( radius * math.cos( theta ), radius * math.sin( theta ), 0.0 )
                local attackPoint = targetPosition-- + volleyOffset
                local traceOrigin = sm.vec3.new( attackPoint.x, attackPoint.y,attackPoint.z + 2 )
                local traceEnd = sm.vec3.new( attackPoint.x, attackPoint.y,attackPoint.z - 20 )
                local hit, result = sm.physics.raycast( traceOrigin, traceEnd, nil, TerrainCollisionMask )
                if hit then
                    targetPosition = result.pointWorld
                end
                bombWarnings[#bombWarnings+1] = { position = targetPosition, deathTick = deathTick }
    
                -- Calculate projectile velocity needed to hit the target
                
                local aimDot = math.max( fromToTargetNorm:dot( sm.vec3.new( 0, 0, 1 ) ), 0 )
                local velocityExtremeVertical = math.sqrt( sm.vec3.new( 0, 0, fromToTarget.z ):length() * 10 * 2 )
                local velocityExtremeHorizontal = math.sqrt( sm.vec3.new( fromToTarget.x, fromToTarget.y, 0 ):length() * 10 )
                local projectileVelocity = velocityExtremeHorizontal * math.sqrt( 1.0 -  aimDot ) + velocityExtremeVertical * math.sqrt( aimDot )
    
                -- Fire bombs in an arc
                local _, highAngleVector = sm.projectile.solveBallisticArc( self.worldPosition, targetPosition, projectileVelocity * VelocityModifier, GRAVITY )
                if highAngleVector then
                    sm.projectile.projectileAttack( self.projectileUuid, ProjectileDamage, self.worldPosition, highAngleVector, self.unit )
                    self.timesFired = self.timesFired + 1
                end
            end
        end
    end
end

--[[API functions]]

function VolleyBombState.start( self )
    self.unit:sendCharacterEvent( self.isRightSide and "volleyRight" or "volleyLeft" )
    self.waitState:start()
    self.fireTimer:start( StartupDelay )
    self.timesFired = 0
end

function VolleyBombState.stop( self )
    self.waitState:stop()
end

function VolleyBombState.onFixedUpdate( self, dt )
    self.target = sm.exists( self.target ) and self.target or nil
    self.waitState:onFixedUpdate( dt )
    if self.target then
        self:sv_updateVolleyBombardment()
    end
end

function VolleyBombState.onUnitUpdate( self, dt )
    self.waitState:onUnitUpdate( dt )
end

function VolleyBombState.isDone( self )
    return self.waitState:isDone()
end