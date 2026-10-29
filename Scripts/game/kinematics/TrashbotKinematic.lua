
TrashbotKinematic = class( nil )

local ProjectileRicochetEffects = {
	[tostring( projectile_potato )] = "Trashbot - Hitimpactnodamage_ricochet",
	[tostring( projectile_smallpotato )] = "Trashbot - Hitimpactnodamage_ricochet_smallpotato",
	[tostring( projectile_fries )] = "Trashbot - Hitimpactnodamage_ricochet", -- replace with fries version
}

function TrashbotKinematic.client_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
    if projectileUuid == projectile_potato or projectileUuid == projectile_smallpotato then
		local effectName = ProjectileRicochetEffects[tostring( projectileUuid )] or "Trashbot - Hitimpactnodamage_ricochet"
        sm.effect.playEffect( effectName, hitPos )
        sm.effect.playEffect( "Trashbot - Hitimpactnodamage", hitPos )
    end
    return true
end

function TrashbotKinematic.client_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	local effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -hitDirection )
	sm.effect.playEffect( "Sledgehammer - NoProgress", hitPos, nil, effectRotation )
end