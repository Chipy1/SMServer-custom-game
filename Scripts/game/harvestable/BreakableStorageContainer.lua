
BreakableStorageContainer = class( nil )

local DamagingProjectiles = {
    [projectile_trashbomb_green] = true,
    [projectile_trashbomb_purple] = true,
    [projectile_trashbomb_mass_green] = true,
    [projectile_trashbomb_mass_purple] = true,
    [projectile_trashchargedbullet_green] = true,
    [projectile_trashchargedbullet_purple] = true
}

function BreakableStorageContainer.server_onExplosion( self, center, destructionLevel )
    if destructionLevel >= 5 and self.destroyed == nil then
        self.destroyed = true
        self:sv_destroyContainer()
    end
end

function BreakableStorageContainer.server_onProjectile( self, position, airTime, velocity, projectileName, shooter, damage, customData, normal, projectileUuid )
    if DamagingProjectiles[projectileUuid] and self.destroyed == nil then
        self.destroyed = true
        self:sv_destroyContainer()
    end
end

function BreakableStorageContainer.sv_destroyContainer( self )
    sm.effect.playEffect( self.data.destructionEffect, self.harvestable.worldPosition, sm.vec3.zero(), self.harvestable.worldRotation )
    self.harvestable:destroy()
end