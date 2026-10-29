dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_items.lua"

TrashBallUnit = class( nil )
TrashBallUnit.isSaveObject = false

local InitialImpulseAngle = math.rad( -30 )
local InitialImpulsePower = 20000
local DefaultCircleRadius = 16.0
local DefaultClockwiseRotation = true
local DefaultGrowthPerSecond = 0.0
local DefaultMaxRadius = 50.0

function TrashBallUnit.server_onCreate( self )
	self.circleCenter = self.unit.character.worldPosition
	self.circleRadius = DefaultCircleRadius
	self.clockwiseRotation = DefaultClockwiseRotation
	self.circleGrowth = DefaultGrowthPerSecond
	self.maxRadius = DefaultMaxRadius
	if self.params then
		self.circleCenter = self.params.circleCenter and self.params.circleCenter or self.circleCenter
		self.circleRadius = self.params.circleRadius and self.params.circleRadius or self.circleRadius
		if self.params.clockwiseRotation ~= nil then
			self.clockwiseRotation = self.params.clockwiseRotation
		end
		self.circleGrowth = self.params.circleGrowth and self.params.circleGrowth or self.circleGrowth
		self.maxRadius = self.params.maxRadius and self.params.maxRadius or self.maxRadius
	end
	self.direction = self.unit.character.direction

	self.aliveTimer = Timer()
	self.aliveTimer:start( 40 * 30 )

	self.stuckTimer = Timer()
	self.stuckTimer:start( 40 * 0.25 )

	self.sprintTimer = Timer()
	self.sprintTimer:start( 40 * 0.4 )

	self.performedInitialImpulse = false

	sm.message.subscribe( MESSAGE_TYPES.GENERAL.TrashbotDefeated, "sv_m_trashbotDefeated" )
end

function TrashBallUnit.server_onRefresh( self )
end

function TrashBallUnit.server_onDestroy( self )
end

function TrashBallUnit.server_onFixedUpdate( self, dt )
	if self.destroyed then
		return
	end
	self.sprintTimer:tick()

	local currentPosition = self.unit.character.worldPosition
	local centerToCharacter = currentPosition - self.circleCenter
	local outwardsDirection = centerToCharacter:safeNormalize( self.unit.character.direction )
	local currentCircleRadius = centerToCharacter:length()
	local t = currentCircleRadius / self.circleRadius
	self.circleRadius = math.min( self.circleRadius + self.circleGrowth * dt, self.maxRadius )
	local integral, fractional = math.modf( t )
	if integral > 0 then
		local clampedFractional = integral > 1 and 1 or fractional
		local desiredAngle = math.rad( sm.util.lerp( 90, 180, clampedFractional ) )
		local curveDirection = self.clockwiseRotation and outwardsDirection:rotateZ( -desiredAngle ) or outwardsDirection:rotateZ( desiredAngle )
		self.direction = curveDirection
	else
		local desiredAngle = math.rad( sm.util.lerp( 0, 90, fractional ) )
		local curveDirection = self.clockwiseRotation and outwardsDirection:rotateZ( -desiredAngle ) or outwardsDirection:rotateZ( desiredAngle )
		self.direction = curveDirection
	end

	self.unit:setMovementDirection( self.direction )
	self.unit:setFacingDirection( sm.vec3.new( 0, 1, 0 ) )

	if self.sprintTimer:done() then
		self.unit:setMovementType( "sprint" )
	else
		self.unit:setMovementType( "run" )
	end

	self.aliveTimer:tick()
	if self.aliveTimer:done() then
		self:sv_onDeath()
	end
	if self.unit.character.velocity:length() < 1.0 then
		self.stuckTimer:tick()
		if self.stuckTimer:done() then
			self:sv_onDeath()
		end
	end

	if not self.performedInitialImpulse then
		if sm.exists( self.unit.character ) then
			self.performedInitialImpulse = true
			local right =  self.direction:cross( sm.vec3.new( 0, 0, 1 ) )
			local impulseDirection = self.direction:rotate( InitialImpulseAngle, right )
			ApplyCharacterImpulse( self.unit.character, impulseDirection, InitialImpulsePower )
		end
	end
end

function TrashBallUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if not sm.exists( self.unit ) then
		return
	end
	if type( attacker ) == "Player" or type( attacker ) == "Shape" then
		self:sv_onDeath( true )
	end
end

function TrashBallUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if not sm.exists( self.unit ) then
		return
	end
	if type( attacker ) == "Player" then
		self:sv_onDeath( true )
	end
end

function TrashBallUnit.server_onExplosion( self, center, destructionLevel )
	if not sm.exists( self.unit ) then
		return
	end
	self:sv_onDeath()
end

function TrashBallUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if not sm.exists( self.unit ) then
		return
	end

	if type( other ) == "Character" then
		if not sm.exists( other ) then
			return
		end
		if other:isPlayer() then
			self:sv_onDeath()
		end
	elseif type( other ) == "Shape" then
		if not sm.exists( other ) then
			return
		end
		self:sv_onDeath()
	elseif type( other ) == "Lift" then
		if sm.exists( other ) then
			local bottomPos = other.worldPosition
			sm.effect.playEffect( "ToteBot - DestroyedParts", bottomPos, nil, nil, nil, { Color = sm.color.new( 1, 1, 0 ) } )
			for i = 0, other.level do
				local topOffset = ( 1 + i ) * 0.25 + 0.125
				local topPos = bottomPos + sm.vec3.new( 0, 0, topOffset )
				if i == other.level then
					sm.effect.playEffect( "ToteBot - DestroyedParts", topPos, nil, nil, nil, { Color = sm.color.new( 1, 1, 0 ) } )
				else
					sm.effect.playEffect( "Farmbot - Hit", topPos )
				end
			end
			other:destroy()
		end
	elseif type( other ) == "nil" then
		if sm.vec3.dot( sm.vec3.new( 0.0, 0.0, -1.0 ), collisionNormal ) >-0.5 then
			self:sv_onDeath()
		end
	end

end

function TrashBallUnit.sv_onDeath( self, spawnLoot )
	local character = self.unit:getCharacter()
	if not self.destroyed then
		self.unit:destroy()
		if self.clockwiseRotation then
			sm.physics.explode( character.worldPosition, 2, 2, 2, 25, "Trashball - HitGreen", nil, nil, nil, 20 )
		else
			sm.physics.explode( character.worldPosition, 2, 2, 2, 25, "Trashball - HitPurple", nil, nil, nil, 20 )
		end
		self.destroyed = true
	end
end

function TrashBallUnit.sv_e_receiveTarget( self, params ) end

function TrashBallUnit.sv_m_trashbotDefeated( self )
	self:sv_onDeath()
 end