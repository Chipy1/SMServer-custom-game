dofile "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua"
SparkstoneHarvestable = class( nil )

local CarveRadius = 2.0
local CarveTargetDensity = 255
local ExplosionDelayTicks = 60
local ExplosionDetectionTicks = 20
local ExplosionDetectionRadius = 5.0

local ExplosionBufferSize = 10
local Sv_SparkstoneExplosionBuffer = {}
local Sv_SparkstoneExplosionBufferIndex = 0
local function addExplosion( position, tick )
    Sv_SparkstoneExplosionBufferIndex = Sv_SparkstoneExplosionBufferIndex % ExplosionBufferSize + 1
    Sv_SparkstoneExplosionBuffer[Sv_SparkstoneExplosionBufferIndex] = { position = position, tick = tick }
end

function SparkstoneHarvestable.server_onCreate( self )
    self.sv = {}
    self.sv.ticksSinceIgnite = -1
    self.harvestable.publicData = { drillLevel = 1, }
    
    local worldPos = self.harvestable.worldPosition
    for i = 1, ExplosionBufferSize do
        if Sv_SparkstoneExplosionBuffer[i] then
            local distance = ( Sv_SparkstoneExplosionBuffer[i].position - worldPos ):length()
            if distance <= ExplosionDetectionRadius then
                local tickDifference = sm.game.getServerTick() - Sv_SparkstoneExplosionBuffer[i].tick
                if tickDifference <= ExplosionDetectionTicks then
                    self:sv_e_tryIgnite()
                    break
                end
            end
        end
    end
end

function SparkstoneHarvestable.server_onFixedUpdate( self, _ )
    if self.sv.ticksSinceIgnite >= 0 then
        self.sv.ticksSinceIgnite = self.sv.ticksSinceIgnite + 1
        if self.sv.ticksSinceIgnite >= ExplosionDelayTicks then
            local world = self.harvestable:getWorld()
            local position = self.harvestable.worldPosition
            sm.effect.playEffect( "Harvestable - Sparkstone_explosion01", position )

            world:sphereVoxelDensitySubtraction( position, CarveRadius, sm.world.voxelFilter.all, CarveTargetDensity )
            addExplosion( position, sm.game.getServerTick() )

            local contacts = sm.physics.getSphereContacts( position, ExplosionDetectionRadius, world, sm.physics.filter.harvestable )
            for _, nearby in ipairs( contacts.harvestables ) do
                if nearby.id ~= self.harvestable.id and nearby.uuid == self.harvestable.uuid then
                    sm.event.sendToHarvestable( nearby, "sv_e_tryIgnite" )
                end
            end

            self.harvestable:destroy()
        end
    end
end

function SparkstoneHarvestable.server_onFloating( self )
    self:sv_e_tryIgnite()
end

function SparkstoneHarvestable.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
    self:sv_e_tryIgnite()
end

function SparkstoneHarvestable.server_onExplosion( self, center, destructionLevel )
    self:sv_e_tryIgnite()
end

function SparkstoneHarvestable.sv_e_plasmaDrill( self, params )
	self:sv_e_tryIgnite()
end

function SparkstoneHarvestable.sv_e_tryIgnite( self )
    if self.sv.ticksSinceIgnite < 0 then
        self.sv.ticksSinceIgnite = math.random( 0, math.floor( ExplosionDelayTicks * 0.5 ) )
        if self.data.sparkstoneHarvestable.igniteEffect then
            sm.effect.playEffect( self.data.sparkstoneHarvestable.igniteEffect, self.harvestable.worldPosition )
        end
    end
end

function SparkstoneHarvestable.client_onCreate( self )
    if self.data.sparkstoneHarvestable.persistentEffect then
        sm.effect.playHostedEffect( self.data.sparkstoneHarvestable.persistentEffect, self.harvestable )
    end
end
