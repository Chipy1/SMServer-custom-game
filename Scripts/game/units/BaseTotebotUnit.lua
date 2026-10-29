dofile "$SURVIVAL_DATA/Scripts/game/units/BaseUnit.lua"

BaseTotebotUnit = class( BaseUnit )

function BaseTotebotUnit.server_onCreate( self )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.ProjectileHit, "sv_m_projectileHit" )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.ProjectileFire, "sv_m_projectileFire" )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.Collision, "sv_m_collision" )
end

function BaseTotebotUnit.sv_takeDamage( self, damage, impact, hitPos, source )
	if self.saved.stats.hp > 0 and damage > 0 then
		local effectRotation = sm.quat.identity()
		if hitPos and impact and impact:length() >= FLT_EPSILON then
			effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -impact:normalize() )
		
			self:sv_onDamaged( damage, impact )
		end
		if self.saved.stats.hp > 0 then
			local currentTick = sm.game.getCurrentTick()
			if source ~= "plasma" or not self.lastPlasmaDrillEffectTick or currentTick - self.lastPlasmaDrillEffectTick >= PLASMA_BOT_HIT_EFFECT_TICK_THRESHOLD then
				self.lastPlasmaDrillEffectTick = currentTick
				sm.effect.playEffect( "ToteBot - Hit", hitPos, nil, effectRotation )
			end
		end
	end
end

function BaseTotebotUnit.sv_onDamaged( self, damage, impact )
	self.saved.stats.hp = self.saved.stats.hp - damage
	self.saved.stats.hp = math.max( self.saved.stats.hp, 0 )
	if self.saved.stats.hp <= 0 then
		self:sv_onDeath( impact )
	else
		self.storage:save( self.saved )
	end
end