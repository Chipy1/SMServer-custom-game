dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/KinematicBase.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

KinematicSpinDoorRelease = class( KinematicBase )

local CounterSpin = 5.0
local MaxAngularSpeed = 20.0
local MinAngularSpeed = -20.0
local MeleeImpulse = 40.0
local ProjectileImpulse = 30.0
local TurnsToUnlock = 0.25

function KinematicSpinDoorRelease.server_onCreate( self )
	self.sv = {}
	self.sv.spinAxis = ( sm.quat.getRight( self.harvestable.worldRotation ) ):normalize()
	self.sv.angularRotation = 0
	self.sv.angularSpeed = 0
	self.sv.wasHit = false
	if self.data then
		MeleeImpulse = self.data.meleeImpulse
		ProjectileImpulse = self.data.projectileImpulse
	end
	self.network:setClientData( { angularRotation = self.sv.angularRotation, angularSpeed = self.sv.angularSpeed } )

	if g_tileStorageManager then
		self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
	end
end

function KinematicSpinDoorRelease.server_onRefresh( self )
    if self.data then
		self.sv.spinAxis = ( sm.quat.getRight( self.harvestable.worldRotation ) ):normalize()
		MeleeImpulse = self.data.meleeImpulse
		ProjectileImpulse = self.data.projectileImpulse
	end
end

function KinematicSpinDoorRelease.server_onFixedUpdate( self, timeStep )
	if self.sv == nil or not self.sv.wasHit then
		return
	end

    local angularRotation, angularSpeed = self:spinUpdate( timeStep, self.sv.angularRotation, self.sv.angularSpeed, self.sv.spinAxis )
    self.sv.angularRotation = angularRotation
    self.sv.angularSpeed = angularSpeed
	local progress = math.abs( self.sv.angularRotation / ( TurnsToUnlock * ( math.pi * 2 ) ) )

	if progress == 0.0 then
		self.sv.wasHit = false
	end

	if g_tileStorageManager and self.sv.tileStorageKey and progress == 1 then
        local group = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_SPINNER_DOOR_TABLE, self.params.keyTag )
		if self.params.kinematicEventTrigger and self.params.kinematicEventTrigger ~= "" then
			KinematicManager.Sv_Activate( self.sv.tileStorageKey, self.params.kinematicEventTrigger )
		end
		if SafeGetExist( group, "spinner" ) then
			sm.event.sendToHarvestable( group.spinner, "sv_e_release" )
		end
	end
end

function KinematicSpinDoorRelease.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if attacker.character then
		self:sv_addTorque( hitPos, hitDirection * MeleeImpulse, self.sv.spinAxis )
	end
end

function KinematicSpinDoorRelease.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if damage > 0 then
		self:sv_addTorque( hitPos, hitVelocity:safeNormalize( sm.vec3.new( 0, 0, 0 ) ) * ProjectileImpulse, self.sv.spinAxis )
	end
end

function KinematicSpinDoorRelease.client_onCreate( self )
	KinematicBase.client_onCreate( self )
	self.cl = {}
	self.cl.angularRotation = 0
	self.cl.angularSpeed = 0
	self.cl.spinAxis = ( sm.quat.getRight( self.harvestable.worldRotation ) ):normalize()
    if self.data then
		MeleeImpulse = self.data.meleeImpulse
		ProjectileImpulse = self.data.projectileImpulse
	end
end

function KinematicSpinDoorRelease.client_onRefresh( self )
    if self.data then
		self.cl.spinAxis = ( sm.quat.getRight( self.harvestable.worldRotation ) ):normalize()
		MeleeImpulse = self.data.meleeImpulse
		ProjectileImpulse = self.data.projectileImpulse
	end
end

function KinematicSpinDoorRelease.client_onClientDataUpdate( self, clientData )
	if self.cl == nil then
		self.cl = {}
	end

	self.cl.angularRotation = clientData.angularRotation
	self.cl.angularSpeed = clientData.angularSpeed
end

function KinematicSpinDoorRelease.client_onFixedUpdate( self, timeStep )
	if sm.isHost then
		return
	end

	local angularRotation, angularSpeed = self:spinUpdate( timeStep, self.cl.angularRotation, self.cl.angularSpeed, self.cl.spinAxis )
	self.cl.angularRotation = angularRotation
	self.cl.angularSpeed = angularSpeed
end

function KinematicSpinDoorRelease.spinUpdate( self, time, angularRotation, angularSpeed, spinAxis )

    if angularRotation == 0.0 and angularSpeed == 0.0 then
        return angularRotation, angularSpeed
    end

    local positiveRotation = nil
    if angularRotation ~= 0.0 then
        positiveRotation = angularRotation > 0
    end

	angularRotation = angularRotation + angularSpeed * time
	local progress =  angularRotation / ( TurnsToUnlock * ( math.pi * 2 ) )
	angularRotation = math.max( math.min( angularRotation, TurnsToUnlock * math.pi * 2 ), -( TurnsToUnlock * math.pi * 2 ) )
    if angularRotation > 0 then
        angularSpeed = angularSpeed - CounterSpin * time
    else
        angularSpeed = angularSpeed + CounterSpin * time
    end
	angularSpeed = math.max( math.min( angularSpeed, MaxAngularSpeed ), MinAngularSpeed )
	if progress > 1.0 or progress < -1.0 then
		angularSpeed = 0.0
	end

    if positiveRotation ~= nil and positiveRotation ~= ( angularRotation > 0 ) then
        angularRotation = 0.0
        angularSpeed = 0.0
    end

	local worldRotation = sm.quat.angleAxis( angularRotation, spinAxis ) * self.harvestable.initialRotation
	self.harvestable:setRotation( worldRotation )

	return angularRotation, angularSpeed
end

function KinematicSpinDoorRelease.sv_addTorque( self, position, impulse, spinAxis )
	local relativePosition = position - self.harvestable.worldPosition
	local torqueImpulse = relativePosition:cross( impulse )

	sm.effect.playEffect( "Growlab - Kinematicspindoorlatch", self.harvestable.worldPosition )

	local scale = self.harvestable:getScale()
	local scaleVolumeMultiplier = 0.25 / ( ( scale.x * scale.y * scale.z ) ^ ( 1 / 3 ) )
	torqueImpulse = torqueImpulse * scaleVolumeMultiplier

	-- Extract only the angular impulse around the SpinAxis
	local projectedTorqueImpulse = spinAxis * spinAxis:dot( torqueImpulse )
	local directionalSign = spinAxis:dot( projectedTorqueImpulse:safeNormalize( sm.vec3.new( 0, 0, 0 ) ) )
	local angularImpulse = projectedTorqueImpulse:length() * directionalSign

	self.sv.angularSpeed = self.sv.angularSpeed + angularImpulse
	self.sv.angularSpeed = math.max( math.min( self.sv.angularSpeed, MaxAngularSpeed ), MinAngularSpeed )

	self.sv.wasHit = true

	self.network:setClientData( { angularRotation = self.sv.angularRotation, angularSpeed = self.sv.angularSpeed } )
end