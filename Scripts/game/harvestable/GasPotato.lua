-- GasPotato.lua --
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

GasPotato = class( nil )
GasPotato.poseWeightCount = 1

local DefaultExplosionDelay = 120 -- ticks (3 seconds at 40 ticks/sec)
local InstantExplosionDelay = 5
local DefaultDestructionLevel = 4
local DefaultDestructionRadius = 5.0
local DefaultImpulseRadius = 12.0
local DefaultImpulseMagnitude = 400.0
local DefaultExplosionEffect = "Gas_potato - SmallExplosion_explosion"
local DefaultInitiateEffect = "Gas_potato - SmallExplosion_initiate"

function GasPotato.server_onCreate( self )
	self.sv = {}
	self.harvestable.publicData = { drillLevel = 1 }
end

function GasPotato.server_onFixedUpdate( self, timeStep )
	if self.sv.countdown then
		self.sv.countdown = self.sv.countdown - 1
		if self.sv.countdown <= 0 then
			self:sv_explode()
		end
	end
end

function GasPotato.sv_explode( self )
	if not sm.exists( self.harvestable ) then
		return
	end

	local position = self.harvestable.worldPosition
	local destructionLevel = self.data.destructionLevel or DefaultDestructionLevel
	local destructionRadius = self.data.destructionRadius or DefaultDestructionRadius
	local impulseRadius = self.data.impulseRadius or DefaultImpulseRadius
	local impulseMagnitude = self.data.impulseMagnitude or DefaultImpulseMagnitude
	local explosionEffect = self.data.explosionEffect or DefaultExplosionEffect
	sm.physics.explode( position, destructionLevel, destructionRadius, impulseRadius, impulseMagnitude, explosionEffect )
	self.harvestable:destroy()
end

function GasPotato.sv_e_plasmaDrill( self, params )
	if not self.sv.countdown then
		self.sv.countdown = self.data.explosionDelay or DefaultExplosionDelay
		self.network:sendToClients( "cl_onTriggered", self.sv.countdown )
	end
end

function GasPotato.server_onExplosion( self, center, destructionLevel )
	if not self.sv.countdown or self.sv.countdown > InstantExplosionDelay then
		self.sv.countdown = InstantExplosionDelay
		self.network:sendToClients( "cl_onTriggered", self.sv.countdown )
	end
end

function GasPotato.server_onFloating( self, center, destructionLevel )
	if not self.sv.countdown or self.sv.countdown > InstantExplosionDelay then
		self.sv.countdown = InstantExplosionDelay
		self.network:sendToClients( "cl_onTriggered", self.sv.countdown )
	end
end

function GasPotato.server_onProjectile( self,hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )








	if not self.sv.countdown and projectileUuid == projectile_flame then
		self.sv.countdown = self.data.explosionDelay or DefaultExplosionDelay
		self.network:sendToClients( "cl_onTriggered", self.sv.countdown )
	end
end

-- Client

function GasPotato.client_onCreate( self )
	self.cl = {}
end

function GasPotato.client_onDestroy( self )
	if self.cl.activateEffect then
		self.cl.activateEffect:stopImmediate()
	end
end

function GasPotato.client_onUpdate( self, dt )
	if self.cl.explodeProgress then
		self.cl.explodeProgress = self.cl.explodeProgress + dt
		local sine = math.sin( self.cl.explodeProgress * math.pi * 11 / self.cl.explodeTime )
			* math.sin( self.cl.explodeProgress * math.pi * 17 / self.cl.explodeTime )
			* math.sin( self.cl.explodeProgress * math.pi * 23 / self.cl.explodeTime )
		local p = self.cl.explodeProgress / self.cl.explodeTime
		local poseWeight = sm.util.easing( sm.util.easingFunctionIds.easeOutCirc, p )
		self.harvestable:setPoseWeight( 0, poseWeight * 0.90 + clamp( sine * 0.25, -0.1, 0.1 ) * p )
	end
end

function GasPotato.cl_onTriggered( self, countdown )
	if not self.cl.activateEffect then
		self.cl.activateEffect = sm.effect.createEffect( self.data.initiateEffect or DefaultInitiateEffect, self.harvestable )
		self.cl.activateEffect:start()
	end

	local newExplodeTime = math.max( countdown, 1 ) / 40.0
	if self.cl.explodeProgress and self.cl.explodeTime then
		-- Keep the progress relative to explodeTime
		local p = self.cl.explodeProgress / self.cl.explodeTime
		self.cl.explodeProgress = p * newExplodeTime
	else
		self.cl.explodeProgress = 0
	end
	self.cl.explodeTime = newExplodeTime
end
