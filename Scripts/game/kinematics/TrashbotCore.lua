dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

TrashbotCore = class()

local DamageCooldownTickTime = 40 * 0.125

function TrashbotCore.server_onCreate( self )
	self.sv = {}
	self.sv.damageCooldownTicks = 0
	if self.params.final then
		self.sv.hitBox = sm.areaTrigger.createAttachedBox( self.harvestable, sm.vec3.new( 2, 2, 2 ), nil, nil, sm.areaTrigger.filter.projectile )
		self.sv.hitBox:bindOnProjectile( "sv_t_onProjectile", self )
	end
end

function TrashbotCore.server_onDestroy( self )
	if self.sv.hitBox then
		self.sv.hitBox:destroy()
		self.sv.hitBox = nil
	end
end

function TrashbotCore.server_onFixedUpdate( self, dt )
	self.sv.damageCooldownTicks = math.max( self.sv.damageCooldownTicks - 1, 0 )
	if not ( self.params and self.params.trashbot and sm.exists( self.params.trashbot ) ) then
		self.harvestable:destroy()
	end
end

function TrashbotCore.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if type( attacker ) == "Player" then
		self:sv_onHit()
	end
end

function TrashbotCore.sv_t_onProjectile( self, trigger, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if type( attacker ) == "Player" then
		local up = sm.vec3.new( 0, 0, 1 )
		self:sv_onHit( { hitPos = hitPos, direction = sm.vec3.getRotation( up, -hitVelocity:safeNormalize( sm.vec3.new( 1, 0, 0 ) ) ), hitVelocity = hitVelocity, projectileType = projectileUuid } )
		return true
	end
end

function TrashbotCore.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if self.params.final then
		if type( attacker ) == "Player" then
			local up = sm.vec3.new( 0, 0, 1 )
			self:sv_onHit( { hitPos = hitPos, direction = sm.vec3.getRotation( up, -hitVelocity:safeNormalize( sm.vec3.new( 1, 0, 0 ) ) ), hitVelocity = hitVelocity, projectileType = projectileUuid } )
		end
	else
		local effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -hitVelocity )
		sm.effect.playEffect( "Sledgehammer - NoProgress", hitPos, nil, effectRotation )
	end
end

function TrashbotCore.sv_onHit( self, params )
	if self.sv.damageCooldownTicks <= 0 then
		if self.params and self.params.trashbot and sm.exists( self.params.trashbot ) then
			sm.event.sendToUnit( self.params.trashbot, "sv_e_coreDamaged", params, sm.event.types.instant )
		end
		self.sv.damageCooldownTicks = DamageCooldownTickTime
	end
end