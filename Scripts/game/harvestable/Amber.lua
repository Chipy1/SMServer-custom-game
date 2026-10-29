dofile("$SURVIVAL_DATA/Scripts/game/survival_constants.lua")

Amber = class( nil )

function Amber.server_onCreate( self )
	self.sv = {}
	self.sv.hits = self.storage:load() or 0
	if self.sv.hits > 0 then
		self.network:setClientData( self.sv.hits )
	end
end

function Amber.sv_onHit( self, impactVelocity )
	if sm.exists( self.harvestable ) and not self.destroyed then
		self.sv.hits = self.sv.hits + 1
		if self.sv.hits < #self.data.amber.stages and math.random( 2 ) == 1 then
			self.storage:save( self.sv.hits )
			self.network:setClientData( self.sv.hits )
		else
			if self.data.amber.loot then
				local lootList = SelectLoot( self.data.amber.loot )
				SpawnLoot( self.harvestable, lootList )
			end
			self.harvestable:destroy()
			self.destroyed = true
		end
	end
end

function Amber.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if damage > 0 then
		self:sv_onHit( hitVelocity:safeNormalize( sm.vec3.new( 0, 0, 1 ) ) * 5 )
	end
end

function Amber.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	self:sv_onHit( hitDirection * 5 )
end

function Amber.server_onExplosion( self, center, destructionLevel )
	local harvestablePosition = sm.harvestable.getPosition( self.harvestable )
	self:sv_onHit( ( harvestablePosition - center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) ) * 5 )
end

function Amber.server_onFloating( self )
	self:sv_onHit( sm.vec3.zero() )
end

function Amber.client_onCreate( self )
	self.cl = {}
	self.cl.hits = 0
	self:cl_updateVisibleSubmeshes()

	if self.data.amber.effect then
		self.cl.effect = sm.effect.createEffect( self.data.amber.effect.name, self.harvestable )
		if self.data.amber.effect.params then
			for k,v in pairs( self.data.amber.effect.params ) do
				if k == "color" and type(v) == "table" then
					v = sm.color.new( v[1], v[2], v[3], v[4] ) -- Could be solved with template
				end
				self.cl.effect:setParameter( k, v )
			end
		end
		self.cl.effect:start()
	end

end

function Amber.client_onClientDataUpdate( self, data )
	self.cl.hits = data
	self:cl_updateVisibleSubmeshes()
end

function Amber.cl_updateVisibleSubmeshes( self )
	local stage = math.min( self.cl.hits + 1, #self.data.amber.stages )
	for i = 1, #self.data.amber.stages do
		self.harvestable:setSubMeshVisible( self.data.amber.stages[i], stage == i )
	end
end