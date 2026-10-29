dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

MagmaBall = class()

local BoxDestructionSimulatedVelocity = sm.vec3.new( 0, 20, 0 )

local HitSphereRadius = 4.25

-- Explosion
local ExplosionRadius = 5.75
local PlayerDamage = 35
local UnitDamage = 100
local KnockbackPower = 6000
local LandingDelayTickTime = 14
local CartTravelTickTime = 40 * 1.2
local SelfdestructTickTime = 40 * 1.7
local TravelDistance = DRILLBOT_ARENA_LENGTH

function MagmaBall.server_onCreate( self )
	self.sv = {}

	self.sv.spawnPosition = self.params.spawnPosition
	self.sv.cartLandingPosition = self.params.cartLandingPosition
	self.sv.cartEndingPosition = self.sv.cartLandingPosition + sm.vec3.new( 0, TravelDistance, 0 )
	self.sv.createTick = sm.game.getCurrentTick()
	self.sv.hitCharacters = {}

	self.sv.worldPosition = self.sv.spawnPosition

	self.network:setClientData( { spawnPosition = self.params.spawnPosition, cartLandingPosition = self.params.cartLandingPosition, createTick = self.sv.createTick }, 1 )
end

function MagmaBall.server_onDestroy( self )
	if self.sv.trigger and sm.exists( self.sv.trigger ) then
		sm.areaTrigger.destroy( self.sv.trigger )
		self.sv.trigger = nil
	end
end

function MagmaBall.server_onRefresh( self )
	self.scriptableObject:destroy()
end

function MagmaBall.server_onFixedUpdate( self, deltaTime )
	local currentTick = sm.game.getCurrentTick()

	if self.sv.trigger == nil and currentTick >= self.sv.createTick + LandingDelayTickTime then
		-- Create collision trigger after landing
		local filter = sm.areaTrigger.filter.character + sm.areaTrigger.filter.dynamicBody
		self.sv.trigger = sm.areaTrigger.createSphere( HitSphereRadius, self.sv.worldPosition, nil, filter )
		self.sv.trigger:setShapeDetection( true )
		self.sv.trigger:setCharacterDetection( true )
	end

	local elapsedTicks = math.max( currentTick - self.sv.createTick, 0 )

	-- Update Position
	if currentTick < self.sv.createTick + LandingDelayTickTime then
		-- Landing
		local landingFraction = elapsedTicks / LandingDelayTickTime
		self.sv.worldPosition = sm.vec3.lerp( self.sv.spawnPosition, self.sv.cartLandingPosition, landingFraction )
	else
		-- Go forward
		local elapsedTravelTicks = math.max( elapsedTicks - LandingDelayTickTime, 0 )
		local travelFraction = elapsedTravelTicks / CartTravelTickTime
		self.sv.worldPosition = sm.vec3.lerp( self.sv.cartLandingPosition, self.sv.cartEndingPosition, travelFraction )
	end


	-- Selfdestruct or update the trigger
	if currentTick >= self.sv.createTick + SelfdestructTickTime then
		self:sv_destroy()
	else
		if self.sv.trigger then
			self.sv.trigger:setWorldPosition( self.sv.worldPosition )
			self:sv_detectCollisions()
		end
	end
end

function MagmaBall.sv_detectCollisions( self )
	if self.sv.trigger then
		-- Destroy boxes
		local shapeCollisions = self.sv.trigger:getShapes()
		for _, shapeCollision in ipairs( shapeCollisions ) do
			if isAnyOf( shapeCollision.shape.uuid, g_drillbot_loot_crates ) then
				sm.event.sendToInteractable( shapeCollision.shape:getInteractable(), "sv_e_destroy", BoxDestructionSimulatedVelocity )
			end
		end

		local characterCollisions = self.sv.trigger:getCharacters()
		for _, characterCollision in ipairs( characterCollisions ) do
			local hitCharacter = characterCollision.character
			if sm.exists( hitCharacter ) and not self.sv.hitCharacters[hitCharacter.id] then
				self.sv.hitCharacters[hitCharacter.id] = true
				self:sv_onHitCharacter( hitCharacter )
			end
		end
	end
end

function MagmaBall.sv_destroy( self )
	if not self.destroyed and sm.exists( self.scriptableObject ) then
		sm.effect.playEffect( "Drillbot - Lavaball_hit", self.sv.worldPosition )

		-- Damage nearby characters
		local contacts = sm.physics.getSphereContacts( self.sv.worldPosition, ExplosionRadius )
		for _, character in ipairs( contacts.characters ) do
			if sm.exists( character ) and not self.sv.hitCharacters[character.id] then
				self.sv.hitCharacters[character.id] = true
				self:sv_onHitCharacter( character )
			end
		end

		self.scriptableObject:destroy()
		self.destroyed = true
	end
end

function MagmaBall.sv_onHitCharacter( self, character )
	local fromToCharacter = character.worldPosition - self.sv.worldPosition
	local knockbackDirection = sm.vec3.new( fromToCharacter.x, fromToCharacter.y, 0 ):safeNormalize( -character.direction )

	if character:isPlayer() then
		local player = character:getPlayer()
		if sm.exists( player ) then
			sm.event.sendToPlayer( player, "sv_e_receiveDamage", { damage = PlayerDamage, source = "shock" } )
		end
	else
		local unit = character:getUnit()
		if sm.exists( unit ) then
			print( "Hit enemy unit, applying damage" )
			sm.event.sendToUnit( unit, "sv_e_receiveDamage", { damage = UnitDamage, impact = knockbackDirection, hitPos = self.sv.worldPosition } )
		end
	end

	ApplyKnockback( character, knockbackDirection, KnockbackPower )
end

function MagmaBall.client_onCreate( self )
	self.cl = {}
	self.cl.interpolationTime = 0.0
end

function MagmaBall.client_onDestroy( self )
	if self.cl.effect then
		self.cl.effect:destroy()
		self.cl.effect = nil
	end
	if self.cl.trailEffect then
		self.cl.trailEffect:destroy()
		self.cl.trailEffect = nil
	end
end

function MagmaBall.client_onClientDataUpdate( self, clientData, channel )
	if channel == 1 then
		self.cl.spawnPosition = clientData.spawnPosition
		self.cl.cartLandingPosition = clientData.cartLandingPosition
		self.cl.cartEndingPosition = clientData.cartLandingPosition + sm.vec3.new( 0, TravelDistance, 0 )
		self.cl.createTick = clientData.createTick

		self.cl.worldPosition = clientData.spawnPosition
		self.cl.previousWorldPosition = clientData.spawnPosition
	end

	if self.cl.effect == nil then
		self.cl.effect = sm.effect.createEffect( "eff_drillbot_lavaball" )
		self.cl.effect:setPosition( self.cl.worldPosition )
		self.cl.effect:start()
	end
	if self.cl.trailEffect == nil then
		self.cl.trailEffect = sm.effect.createEffect( "Drillbot - Lavaball_trail" )
		self.cl.trailEffect:setPosition( self.cl.worldPosition )
		self.cl.trailEffect:start()
	end
end

function MagmaBall.client_onUpdate( self, deltaTime )
	self.cl.interpolationTime = self.cl.interpolationTime + deltaTime
	local p = self.cl.interpolationTime / 0.025
	local interpolatedWorldPosition = sm.vec3.lerp( self.cl.previousWorldPosition, self.cl.worldPosition, p )
	self.cl.effect:setPosition( interpolatedWorldPosition )
	self.cl.trailEffect:setPosition( interpolatedWorldPosition )
end

function MagmaBall.client_onFixedUpdate( self, deltaTime )
	local serverTick = sm.game.getServerTick()

	local elapsedTicks = math.max( serverTick - self.cl.createTick, 0 )

	-- Update Position
	self.cl.previousWorldPosition = self.cl.worldPosition
	if serverTick < self.cl.createTick + LandingDelayTickTime then
		-- Landing
		local landingFraction = elapsedTicks / LandingDelayTickTime
		self.cl.worldPosition = sm.vec3.lerp( self.cl.spawnPosition, self.cl.cartLandingPosition, landingFraction )
	else
		-- Go forward
		local elapsedTravelTicks = math.max( elapsedTicks - LandingDelayTickTime, 0 )
		local travelFraction = elapsedTravelTicks / CartTravelTickTime
		self.cl.worldPosition = sm.vec3.lerp( self.cl.cartLandingPosition, self.cl.cartEndingPosition, travelFraction )
	end
	self.cl.interpolationTime = 0.0
end