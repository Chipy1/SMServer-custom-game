dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/ScannerbotMoveAttackState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/managers/ScannerbotManager.lua"

ScannerbotUnit = class( nil )
ScannerbotUnit.isSaveObject = false

function ScannerbotUnit.server_onCreate( self )
	print( "-- ScannerbotUnit created --" )

	-- Scannerbot moving attack state
	self.scannerbotMoveAttackState = ScannerbotMoveAttackState()
	self.scannerbotMoveAttackState:sv_onCreate( self.unit )
	self.scannerbotMoveAttackState.debugName = "scannerbotMoveAttackState"
	local desiredPosition = ScannerbotManager.Sv_GetDesiredPostion()
	if desiredPosition then
		self.scannerbotMoveAttackState:sv_setDestination( desiredPosition )
	end
end

function ScannerbotUnit.server_onRefresh( self )
	print( "-- ScannerbotUnit refreshed --" )
end

function ScannerbotUnit.server_onDestroy( self )
	print( "-- ScannerbotUnit terminated --" )
end

function ScannerbotUnit.server_onFixedUpdate( self, dt )
	self.scannerbotMoveAttackState:onFixedUpdate( dt )
	self.unit:setMovementType( self.scannerbotMoveAttackState:getMovementType() )
	self.unit:setMovementDirection( self.scannerbotMoveAttackState:getMovementDirection() )
	self.unit:setFacingDirection( self.scannerbotMoveAttackState:getFacingDirection() )
	self.unit:setWantsJump( self.scannerbotMoveAttackState:getWantsJump() )
	self.unit:setWantsCrouch( self.scannerbotMoveAttackState:getWantsCrouch() )
end

function ScannerbotUnit.server_onUnitUpdate( self, dt )

	self.scannerbotMoveAttackState:onUnitUpdate( dt )
	local desiredPosition = ScannerbotManager.Sv_GetDesiredPostion()
	if desiredPosition then
		self.scannerbotMoveAttackState:sv_setDestination( desiredPosition )
	end
end

function ScannerbotUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	local up = sm.vec3.new( 0, 0, 1 )
	local effectRotation = sm.vec3.getRotation( up, -hitVelocity:safeNormalize( up ) )
	sm.effect.playEffect( "Sledgehammer - NoProgress", hitPos, nil, effectRotation )
end

function ScannerbotUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	local effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -hitDirection )
	sm.effect.playEffect( "Sledgehammer - NoProgress", hitPos, nil, effectRotation )
end

function ScannerbotUnit.server_onExplosion( self, center, destructionLevel ) end

function ScannerbotUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal ) end

function ScannerbotUnit.server_onCollisionCrush( self ) end

function ScannerbotUnit.sv_e_receiveTarget( self, params ) end