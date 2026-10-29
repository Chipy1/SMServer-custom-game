dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"

DrillbotUnit = class( nil )
DrillbotUnit.isSaveObject = false

function DrillbotUnit.server_onCreate( self )

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"
	self.currentState = self.idleState
end

function DrillbotUnit.server_onFixedUpdate( self, dt )
	self.currentState:onFixedUpdate( dt )
	self.unit:setMovementType( self.currentState:getMovementType() )
	self.unit:setMovementDirection( self.currentState:getMovementDirection() )
	self.unit:setFacingDirection( self.currentState:getFacingDirection() )
	self.unit:setWantsJump( self.currentState:getWantsJump() )
	self.unit:setWantsCrouch( self.currentState:getWantsCrouch() )
end

function DrillbotUnit.server_onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function DrillbotUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid ) end

function DrillbotUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection ) end

function DrillbotUnit.server_onExplosion( self, center, destructionLevel ) end

function DrillbotUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal ) end

function DrillbotUnit.server_onCollisionCrush( self ) end

function DrillbotUnit.sv_e_receiveTarget( self, params ) end