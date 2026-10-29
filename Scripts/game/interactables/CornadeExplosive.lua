CornadeExplosive = class( nil )


function CornadeExplosive.server_onCreate( self )
	self.sv = {}
	self.sv.tickCounter = 0
	self.sv.destroyed = false
	if self.params then
		self.sv.tickBeforeExplosion = CORNADE_LIFETIME - (self.params.lifetime * 40)
	end
end

function CornadeExplosive.server_onFixedUpdate( self )
	self.sv.tickCounter = self.sv.tickCounter + 1
	if self.sv.tickCounter >= self.sv.tickBeforeExplosion and not self.sv.destroyed then
		self.sv.destroyed = true
		self.shape:destroyShape()
		sm.physics.explode( self.shape:getWorldPosition(), 5, 3.0, 6.0, 25.0, "Cornnade - Explosion", nil, nil, nil, 35, nil, EXPLOSIONS.explosion_cornade )
	end
end

function CornadeExplosive.client_onCreate( self )
	self.cl = {}

	if self.params then
		sm.physics.applyImpulse( self.shape, self.params.hitVelocity * self.shape:getBody().mass * 0.4, true )
	end
end

function CornadeExplosive.client_onDestroy( self )
	if self.cl.effect then
		self.cl.effect:destroy()
	end
end
