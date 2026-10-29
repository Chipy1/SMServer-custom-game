dofile("$SURVIVAL_DATA/Scripts/game/survival_constants.lua")

Fence = class( nil )

local KnockbackPower = 5

function Fence.server_onCreate( self )
	self.sv = {}
	
	local min, max = self.harvestable:getLocalAabb()
	local bounds = sm.vec3.new( math.abs( max.x - min.x ), math.abs( max.y - min.y ), math.abs( max.z - min.z ) )
	local centerPos = min + bounds * 0.5
	self.sv.areaTrigger = sm.areaTrigger.createBox( bounds * 0.5, self.harvestable:transformLocalPoint( centerPos ), self.harvestable:getRotation(), sm.areaTrigger.filter.dynamicBody )
	self.sv.areaTrigger:bindOnEnter( "trigger_onEnter" )
	
    self.harvestable.publicData = { drillLevel = 1 }
end

function Fence.server_onDestroy( self )
	if self.sv.areaTrigger then
		sm.areaTrigger.destroy( self.sv.areaTrigger )
		self.sv.areaTrigger = nil
	end
end

function Fence.sv_onHit( self, impactVelocity )
	if sm.exists( self.harvestable ) and not self.destroyed then
		local harvestablePosition = sm.harvestable.getPosition( self.harvestable )
		local harvestableRotation = sm.harvestable.getRotation( self.harvestable )
		
		if self.data.effectName and self.data.effectName ~= "" then
			harvestableRotation = harvestableRotation * sm.quat.new( -0.70710678118, 0, 0, 0.70710678118 )
			harvestablePosition = harvestablePosition + harvestableRotation * sm.vec3.new( 0, 0, 0.75 )
			
			sm.effect.playEffect( self.data.effectName, harvestablePosition, nil, harvestableRotation, nil, { Color = self.harvestable:getColor(), startVelocity = impactVelocity } )
		end
		sm.harvestable.destroy( self.harvestable )
		self.destroyed = true
	end
end

function Fence.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if damage > 0 then
		self:sv_onHit( hitVelocity:safeNormalize( sm.vec3.new( 0,0,1 ) ) * KnockbackPower )
	end
end

function Fence.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	self:sv_onHit( hitDirection * KnockbackPower )
end

function Fence.server_onExplosion( self, center, destructionLevel )
	if sm.exists( self.harvestable ) and not self.destroyed then
		local harvestablePosition = sm.harvestable.getPosition( self.harvestable )
		self:sv_onHit( ( harvestablePosition - center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) ) * KnockbackPower )
	end
end

function Fence.trigger_onEnter( self, trigger, results )
	for _, result in ipairs( results ) do
		if sm.exists( result ) then
			if type( result ) == "Body" then
				self:sv_onHit( result:getVelocity() )
			end
		end
	end
end

function Fence.server_onFloating( self )
	self:sv_onHit( sm.vec3.zero() )
end

function Fence.sv_e_plasmaDrill( self, params )
	self:sv_onHit( params.direction * KnockbackPower )
end
