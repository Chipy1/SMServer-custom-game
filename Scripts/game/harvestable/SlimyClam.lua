SlimyClam = class()

function SlimyClam.server_onCreate( self )
	self.harvestable.publicData = { drillLevel = 1 }
end

function SlimyClam.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if damage > 0 then
		self:sv_onHit( attacker )
	end
end

function SlimyClam.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	self:sv_onHit( attacker )
end

function SlimyClam.server_onExplosion( self, center, destructionLevel )
	self:sv_onHit()
end

function SlimyClam.sv_e_plasmaDrill( self, params )
	self:sv_onHit()
end

function SlimyClam.sv_onHit( self, attacker )
	if not self.harvested and sm.exists( self.harvestable ) then
		sm.effect.playEffect("SlimyClam - Destruct", self.harvestable.worldPosition, nil, self.harvestable.worldRotation )
		sm.harvestable.createHarvestable( hvs_farmables_slimyclam_broken, self.harvestable.worldPosition, self.harvestable.worldRotation )
		sm.harvestable.destroy( self.harvestable )
		self.harvested = true

		-- If a player (or their character) broke the clam, restore their breath to max
		if type( attacker ) == "Player" and sm.exists( attacker ) then
			local playerCharacter = attacker:getCharacter()
			if sm.exists( playerCharacter ) and playerCharacter:isDiving() then
				-- Restore player's breath to max via SurvivalPlayer handler
				sm.event.sendToPlayer( attacker, "sv_e_restoreBreath" )
			end
		end
	end
end

function SlimyClam.client_onCreate( self )
	self.cl = {}
	self.cl.bubbleEffect = sm.effect.createEffect( "SlimyClam - Bubbles" )
	self.cl.bubbleEffect:setPosition( self.harvestable.worldPosition )
	self.cl.bubbleEffect:setRotation( self.harvestable.worldRotation )
	self.cl.bubbleEffect:setWorld( self.harvestable:getWorld() )
	self.cl.bubbleEffect:setAutoPlay( true )
	self.cl.bubbleAmbienceEffect = sm.effect.createEffect( "SlimyClam - BubblesAmbience" )
	self.cl.bubbleAmbienceEffect:setPosition( self.harvestable.worldPosition )
	self.cl.bubbleAmbienceEffect:setRotation( self.harvestable.worldRotation )
	self.cl.bubbleAmbienceEffect:setWorld( self.harvestable:getWorld() )
	self.cl.bubbleAmbienceEffect:setAutoPlay( true )
end

function SlimyClam.client_onDestroy( self )
	self.cl.bubbleEffect:destroy()
	self.cl.bubbleAmbienceEffect:destroy()
end