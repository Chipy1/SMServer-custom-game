dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/KinematicBase.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DrillbotManager.lua" )

DrillbotFace = class( KinematicBase )

local DamageCooldownTickTime = 40 * 0.125

function DrillbotFace.server_onCreate( self )
	self.sv = {}
	self.sv.lastDamageTick = nil
end

function DrillbotFace.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if type( attacker ) == "Player" then
		local currentTick = sm.game.getCurrentTick()
		if self.sv.lastDamageTick == nil or self.sv.lastDamageTick + DamageCooldownTickTime <= currentTick then
			self.sv.lastDamageTick = currentTick
			DrillbotManager.Sv_HitFace( true, hitPos - hitDirection, sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -hitDirection ) )
		end
	end
end

function DrillbotFace.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if type( attacker ) == "Player" then
		local currentTick = sm.game.getCurrentTick()
		if self.sv.lastDamageTick == nil or self.sv.lastDamageTick + DamageCooldownTickTime <= currentTick then
			self.sv.lastDamageTick = currentTick
			DrillbotManager.Sv_HitFace( false, hitPos, nil )
		end
	end
end