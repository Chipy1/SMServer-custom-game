--dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
--dofile "$SURVIVAL_DATA/Scripts/util.lua"
--dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
--dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
--dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"

DrillbotLegsUnit = class( nil )
DrillbotLegsUnit.isSaveObject = false

function DrillbotLegsUnit.server_onCreate( self )

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	self.currentState = self.idleState
end

function DrillbotLegsUnit.server_onFixedUpdate( self, dt )
	self.currentState:onFixedUpdate( dt )
	self.unit:setMovementType( self.currentState:getMovementType() )
	self.unit:setMovementDirection( self.currentState:getMovementDirection() )
	self.unit:setFacingDirection( self.currentState:getFacingDirection() )
	self.unit:setWantsJump( self.currentState:getWantsJump() )
	self.unit:setWantsCrouch( self.currentState:getWantsCrouch() )
end

function DrillbotLegsUnit.server_onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function DrillbotLegsUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid ) end

function DrillbotLegsUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection ) end

function DrillbotLegsUnit.server_onExplosion( self, center, destructionLevel ) end

function DrillbotLegsUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal ) end

function DrillbotLegsUnit.server_onCollisionCrush( self ) end

function DrillbotLegsUnit.sv_e_receiveTarget( self, params ) end