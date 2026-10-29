dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/KinematicBase.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )

KinematicDrillSpawner = class( KinematicBase )

local TravelSpeed = 1.5
local ActivationTickDelay = 17.0 * 40
local SpawnIntervalTicks = 0.5 * 40
local MaxSpawns = 20
local PodSpreadDegrees = 90.0
local SelfdestructTickDelay = 7.0 * 40
local ProjectileVelocity = 12
local DebrisCeiling = 32.0
local WheelRotationOffset = sm.vec3.new( 0.0, 30.5, 0.0 )
local WheelPositionOffset = sm.vec3.new( 2.0, 0.45, 0.0 )

local WheelRotationOffsetOne = sm.quat.fromEuler( WheelRotationOffset )
local WheelRotationOffsetTwo = sm.quat.fromEuler( WheelRotationOffset + sm.vec3.new( 0.0, 120.0, 0.0 ) )
local WheelRotationOffsetThree = sm.quat.fromEuler( WheelRotationOffset + sm.vec3.new( 0.0, 240.0, 0.0 ) )
local WheelPositionOffsetOne = WheelRotationOffsetOne * WheelPositionOffset
local WheelPositionOffsetTwo = WheelRotationOffsetTwo * WheelPositionOffset
local WheelPositionOffsetThree = WheelRotationOffsetThree * WheelPositionOffset

local UnitToProjectile = {
	[tostring( unit_totebot_green )] = projectile_spawnerpod_totebot,
	[tostring( unit_haybot )] = projectile_spawnerpod_haybot,
	[tostring( unit_tapebot_green_1 )] = projectile_spawnerpod_tapebot,
	[tostring( unit_tapebot_green_2 )] = projectile_spawnerpod_tapebot,
	[tostring( unit_tapebot_green_3 )] = projectile_spawnerpod_tapebot,
	[tostring( unit_farmbot )] = projectile_spawnerpod_farmbot,
}

function KinematicDrillSpawner.server_onCreate( self )
	self.sv = {}

	if self.params then
		self.sv.destination = self.params.destination
		self.sv.units = self.params.units
		self.sv.handler = self.params.handler
	end
	if not self.sv.destination  then
		self.sv.destination = self.harvestable.initialPosition + sm.vec3.new( 0, 0, 10 )
	end

	local toDestination =  self.sv.destination - self.harvestable.initialPosition
	self.sv.ticksToDestination = math.ceil( ( toDestination:length() / TravelSpeed ) / 0.025 )
	self.sv.initialTick = sm.game.getCurrentTick()
	self.sv.forward = toDestination:safeNormalize( sm.vec3.new( 0, 0, 1 ) )
	local rotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), self.sv.forward )
	self.harvestable:setRotation( rotation )

	self.sv.arrived = false
	self.sv.activationDelayTickCount = 0
	self.sv.spawnTimer = Timer()
	self.sv.spawnTimer:start( SpawnIntervalTicks )
	self.sv.spawnCount = 0
	self.sv.selfdestructDelayTickCount = 0

	self.network:setClientData( { destination = self.sv.destination, initialTick = self.sv.initialTick, ticksToDestination = self.sv.ticksToDestination }, 1 )
end

function KinematicDrillSpawner.sv_destroy( self )
	if sm.exists( self.harvestable ) and not self.sv.destroyed then
		self.sv.destroyed = true
		sm.effect.playEffect( "Drillspawner - Destruction", self.harvestable.worldPosition, nil, self.harvestable.worldRotation )
		self.harvestable:destroy()
	end
end

function KinematicDrillSpawner.server_onFixedUpdate( self )
	if not self.sv.arrived then
		local ticks = clamp( sm.game.getCurrentTick() - self.sv.initialTick, 0, self.sv.ticksToDestination )
		local position = sm.vec3.lerp( self.harvestable.initialPosition, self.sv.destination, ticks / self.sv.ticksToDestination )
		self.harvestable:setPosition( position )
		self.sv.arrived = ticks >= self.sv.ticksToDestination

		-- Terrain destruction
		local forward = self.harvestable.worldRotation * sm.vec3.new( 0, 1, 0 )
		local DestructionSphereRadius = 2.5
		local destructionSpherePosition = self.harvestable.worldPosition + forward * 3
		local drillWorld = self.harvestable:getWorld()
		if drillWorld and sm.exists( drillWorld ) then
			drillWorld:sphereVoxelDensitySubtraction( destructionSpherePosition, DestructionSphereRadius, nil, 10 )
		end
	elseif self.sv.spawnCount < MaxSpawns then
		self.sv.activationDelayTickCount = math.min( self.sv.activationDelayTickCount + 1, ActivationTickDelay )
		if self.sv.activationDelayTickCount >= ActivationTickDelay then
			-- Start spawning
			self.sv.spawnTimer:tick()
			if self.sv.spawnTimer:done() then
				self.sv.spawnTimer:reset()
				self.sv.spawnCount = self.sv.spawnCount + 1

				local unit = self.sv.units and self.sv.units[self.sv.spawnCount] or nil
				if unit then
					local forward = self.harvestable.worldRotation * sm.vec3.new( 0, 1, 0 )
					local firePosition = self.harvestable.worldPosition + forward * 1
					local fireDirection = sm.noise.gunSpread( forward, PodSpreadDegrees )
					local fireVelocity = fireDirection * ProjectileVelocity
					local projectile = UnitToProjectile[tostring( unit )] or projectile_spawnerpod
					sm.projectile.harvestableCustomProjectileAttack( { unit = unit }, projectile, 0, firePosition, fireVelocity, self.harvestable, 0 )
					local effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), forward )
					sm.effect.playEffect( "Drillspawner - Shootingpods", firePosition, nil, effectRotation )
				else
					self.sv.spawnCount = MaxSpawns
				end
				if self.sv.spawnCount == MaxSpawns then
					if self.sv.handler and sm.exists( self.sv.handler ) then
						sm.event.sendToScriptableObject( self.sv.handler, "sv_e_onDrillSpawnerCompleted", self.harvestable )
					end
				end
			end
		end
	else
		self.sv.selfdestructDelayTickCount = math.min( self.sv.selfdestructDelayTickCount + 1, SelfdestructTickDelay )
		if self.sv.selfdestructDelayTickCount >= SelfdestructTickDelay then
			self:sv_destroy()
		end
	end
end

function KinematicDrillSpawner.client_onCreate( self )
	KinematicBase.client_onCreate( self )
	self.cl = {}
	if not self.cl.destination then self.cl.destination = self.harvestable.initialPosition + sm.vec3.new( 0, 0, 10 ) end
	if not self.cl.initialTick then	self.cl.initialTick = sm.game.getCurrentTick() end

	local toDestination =  self.cl.destination - self.harvestable.initialPosition
	self.cl.ticksToDestination = math.ceil( ( toDestination:length() / TravelSpeed ) / 0.025 )

	self.cl.forward = ( self.cl.destination - self.harvestable.initialPosition ):safeNormalize( sm.vec3.new( 0, 0, 1 ) )
	local rotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), self.cl.forward )
	self.harvestable:setRotation( rotation )

	self.cl.arrived = false

	self.cl.wheelOneEffect = sm.effect.createEffect( "Drillspawner - WheelspinOne", self.harvestable )
	self.cl.wheelOneEffect:setOffsetPosition( WheelPositionOffsetOne )
	self.cl.wheelOneEffect:setOffsetRotation( WheelRotationOffsetOne )
	self.cl.wheelOneEffect:start()

	self.cl.wheelTwoEffect = sm.effect.createEffect( "Drillspawner - WheelspinTwo", self.harvestable )
	self.cl.wheelTwoEffect:setOffsetPosition( WheelPositionOffsetTwo )
	self.cl.wheelTwoEffect:setOffsetRotation( WheelRotationOffsetTwo )
	self.cl.wheelTwoEffect:start()

	self.cl.wheelThreeEffect = sm.effect.createEffect( "Drillspawner - WheelspinThree", self.harvestable )
	self.cl.wheelThreeEffect:setOffsetPosition( WheelPositionOffsetThree )
	self.cl.wheelThreeEffect:setOffsetRotation( WheelRotationOffsetThree )
	self.cl.wheelThreeEffect:start()

	self.cl.drillingEffect = sm.effect.createEffect( "Drillspawner - Drilling", self.harvestable )
	local offsetRotationDrilling = sm.quat.fromEuler( sm.vec3.new( 270, 0, 0 ) )
	self.cl.drillingEffect:setOffsetRotation( offsetRotationDrilling )
	self.cl.drillingEffect:start()

	self.cl.drillSoundEffect = sm.effect.createEffect( "Drillspawner - DrillSound", self.harvestable )

	self.cl.drillGrindSoundEffect = sm.effect.createEffect( "Drillspawner - DrillGrindSound", self.harvestable )

	self.cl.groundshakeSmallEffect = sm.effect.createEffect( "Drillspawner - GroundshakeSmall", self.harvestable )
	self.cl.groundshakeLargeEffect = sm.effect.createEffect( "Drillspawner - GroundshakeLarge", self.harvestable )
	self.cl.emergingEffect = sm.effect.createEffect( "Drillspawner - Emerging" )
	self.cl.debrisEffect = sm.effect.createEffect( "Drillspawner - Fallingdebris" )
end

function KinematicDrillSpawner.client_onDestroy( self )
	if self.cl.wheelOneEffect then
		self.cl.wheelOneEffect:stopImmediate()
		self.cl.wheelOneEffect:destroy()
		self.cl.wheelOneEffect = nil
	end
	if self.cl.wheelTwoEffect then
		self.cl.wheelTwoEffect:stopImmediate()
		self.cl.wheelTwoEffect:destroy()
		self.cl.wheelTwoEffect = nil
	end
	if self.cl.wheelThreeEffect then
		self.cl.wheelThreeEffect:stopImmediate()
		self.cl.wheelThreeEffect:destroy()
		self.cl.wheelThreeEffect = nil
	end
	if self.cl.drillingEffect then
		self.cl.drillingEffect:stopImmediate()
		self.cl.drillingEffect:destroy()
		self.cl.drillingEffect = nil
	end
	if self.cl.drillSoundEffect then
		self.cl.drillSoundEffect:stopImmediate()
		self.cl.drillSoundEffect:destroy()
		self.cl.drillSoundEffect = nil
	end
	if self.cl.groundshakeSmallEffect then
		self.cl.groundshakeSmallEffect:stopImmediate()
		self.cl.groundshakeSmallEffect:destroy()
		self.cl.groundshakeSmallEffect = nil
	end
	if self.cl.groundshakeLargeEffect then
		self.cl.groundshakeLargeEffect:stopImmediate()
		self.cl.groundshakeLargeEffect:destroy()
		self.cl.groundshakeLargeEffect = nil
	end
	if self.cl.emergingEffect then
		self.cl.emergingEffect:stopImmediate()
		self.cl.emergingEffect:destroy()
		self.cl.emergingEffect = nil
	end
	if self.cl.debrisEffect then
		self.cl.debrisEffect:stopImmediate()
		self.cl.debrisEffect:destroy()
		self.cl.debrisEffect = nil
	end
end

function KinematicDrillSpawner.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.initialTick = data.initialTick
		self.cl.destination = data.destination
		self.cl.ticksToDestination = data.ticksToDestination
		self.cl.forward = ( self.cl.destination - self.harvestable.initialPosition ):safeNormalize( sm.vec3.new( 0, 0, 1 ) )
		local rotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), self.cl.forward )
		self.harvestable:setRotation( rotation )
	end
end

function KinematicDrillSpawner.client_onFixedUpdate( self )
	if not self.cl.arrived then
		local ticks = clamp( sm.game.getCurrentTick() - self.cl.initialTick, 0, self.cl.ticksToDestination )
		local position = sm.vec3.lerp( self.harvestable.initialPosition, self.cl.destination, ticks / self.cl.ticksToDestination )
		self.harvestable:setPosition( position )

		if not self.cl.groundshakeSmallEffect:isPlaying() then
			self.cl.groundshakeSmallEffect:start()
		end
		if not self.cl.groundshakeLargeEffect:isPlaying() then
			self.cl.groundshakeLargeEffect:start()
		end
		local drillTopPosition = self.harvestable.worldPosition + self.harvestable.worldRotation * sm.vec3.new( 0, 4.5, 0 )
		local groundFilter = sm.physics.filter.terrainSurface + sm.physics.filter.terrainAsset + sm.physics.filter.voxelTerrain
		-- Find emerging point
		local success, result = sm.physics.spherecast( self.cl.destination, self.harvestable.initialPosition, 0.01, self.harvestable, groundFilter )
		if success then
			self.cl.emergingEffect:setPosition( result.pointWorld )
			self.cl.emergingEffect:setRotation( sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), result.normalWorld ) )
			if not self.cl.emergingEffect:isPlaying() then
				self.cl.emergingEffect:start()
			end
			if not self.cl.drillGrindSoundEffect:isPlaying() then
				self.cl.drillGrindSoundEffect:start()
			end
			if drillTopPosition.z >= result.pointWorld.z then
				-- Start above surface drilling sound
				if not self.cl.drillSoundEffect:isPlaying() then
					self.cl.drillSoundEffect:start()
				end
			end
		else
			if self.cl.emergingEffect:isPlaying() then
				self.cl.emergingEffect:stop()
			end
			if self.cl.drillGrindSoundEffect:isPlaying() then
				self.cl.drillGrindSoundEffect:stopBreakSustain()
			end
		end

		local isOverworld = self.harvestable:getWorld().id == 1
		if isOverworld then
			local toCeiling = self.cl.destination + sm.vec3.new( 0, 0, DebrisCeiling )
			local success, result = sm.physics.spherecast( self.cl.destination, toCeiling, 0.01, self.harvestable, groundFilter )
			if success then
				self.cl.debrisEffect:setPosition( result.pointWorld )
			else
				self.cl.debrisEffect:setPosition( toCeiling )
			end
			if not self.cl.debrisEffect:isPlaying() then
				self.cl.debrisEffect:start()
			end
		end

		local arrived = ticks >= self.cl.ticksToDestination
		if not self.cl.arrived and arrived then
			if self.cl.wheelOneEffect:isPlaying() then
				self.cl.wheelOneEffect:stop()
			end
			if self.cl.wheelTwoEffect:isPlaying() then
				self.cl.wheelTwoEffect:stop()
			end
			if self.cl.wheelThreeEffect:isPlaying() then
				self.cl.wheelThreeEffect:stop()
			end
			if self.cl.drillingEffect:isPlaying() then
				self.cl.drillingEffect:stopImmediate()
			end
			if self.cl.drillSoundEffect:isPlaying() then
				self.cl.drillSoundEffect:stopBreakSustain()
			end
			if self.cl.drillGrindSoundEffect:isPlaying() then
				self.cl.drillGrindSoundEffect:stopBreakSustain()
			end
			if self.cl.groundshakeSmallEffect:isPlaying() then
				self.cl.groundshakeSmallEffect:stop()
			end
			if self.cl.groundshakeLargeEffect:isPlaying() then
				self.cl.groundshakeLargeEffect:stop()
			end
			if self.cl.emergingEffect:isPlaying() then
				self.cl.emergingEffect:stop()
			end
			if self.cl.debrisEffect:isPlaying() then
				self.cl.debrisEffect:stop()
			end

			sm.effect.playHostedEffect( "Drillspawner - Blowingthetop", self.harvestable )
			sm.effect.playHostedEffect( "Drillspawner - Blowingthetop Drillbit", self.harvestable )
		end
		self.cl.arrived = arrived
	end
end