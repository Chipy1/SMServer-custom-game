
dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/Kinematic.lua" )

SimpleKinematic = class( Kinematic )

local AcceptedDistanceSquared = 0.5

function SimpleKinematic.server_onCreate( self )
    Kinematic.server_onCreate( self )
    self.sv.resetTickCounter = 0
    if self.data and self.data.TriggerOffsets then
        self.sv.triggerPoint1 = sm.vec3.new( self.data.TriggerOffsets[1].x, self.data.TriggerOffsets[1].y, self.data.TriggerOffsets[1].z  )
        self.sv.triggerPoint2 = sm.vec3.new( self.data.TriggerOffsets[2].x, self.data.TriggerOffsets[2].y, self.data.TriggerOffsets[2].z  )
    end
end

function SimpleKinematic.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
    if type( attacker ) == "Player" and damage > 0 then
        self:sv_projectileHitTrigger( hitPos )
    end
end

function SimpleKinematic.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
    if type( attacker ) == "Player" then
        Kinematic.sv_activate( self )
    end
end

function SimpleKinematic.sv_projectileHitTrigger( self, hitpos )
    if not self.data.TriggerOffsets then
        return
    end

    local dist1 = sm.vec3.getDistanceSquared( hitpos, self.harvestable.worldPosition + self.harvestable.worldRotation * self.sv.triggerPoint1 )
    local dist2 = sm.vec3.getDistanceSquared( hitpos, self.harvestable.worldPosition + self.harvestable.worldRotation * self.sv.triggerPoint2 )

    if dist1 <= AcceptedDistanceSquared or dist2 <= AcceptedDistanceSquared then
        Kinematic.sv_activate( self )
    end
end

function SimpleKinematic.server_onUnload( self )
    --override to not save position
end