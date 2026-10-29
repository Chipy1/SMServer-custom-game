-- Crystal.lua --
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" )

Crystal = class( nil )

local MaxHealth = 100
local NudgeTicks = 30
local PlasmaDrillDamagePerHit = 2

local function IsPointingUp( shape )
	return ( shape.worldRotation * sm.vec3.new( 0, 1, 0 ) ):dot( sm.vec3.new( 0, 0, 1 ) ) > 0.8
end

function Crystal.server_onCreate( self )
	self.sv = {}
	self.sv.health = MaxHealth
	self.sv.nudgeTicks = 0
	self.sv.bodyShapeCount = 0
	self.sv.isPointingUp = IsPointingUp( self.shape )

	if self.params and self.params.inheritedDamage then
		self:sv_onHit( self.params.inheritedDamage )
	end

	self.interactable.publicData = { drillLevel = 1 }
	assert( self.data, "Crystal missing data" )
end

function Crystal.server_onFixedUpdate( self, dt )
	if self.sv.isPointingUp then
		local bodyShapeCount = 0
		local allBodies = self.shape:getBody():getCreationBodies()
		for _, body in ipairs( allBodies ) do
			bodyShapeCount = bodyShapeCount + #body:getShapes()
		end

		if self.sv.bodyShapeCount ~= bodyShapeCount then
			self.sv.nudgeTicks = NudgeTicks
			self.sv.bodyShapeCount = bodyShapeCount
		end
	
		if self.sv.nudgeTicks > 0 then
			local isHighest = true
			local myZ = self.shape.worldPosition.z
			local allBodies = self.shape:getBody():getCreationBodies()
			for _, body in ipairs( allBodies ) do
				for _, shape in ipairs( body:getShapes() ) do
					if shape ~= self.shape and shape.worldPosition.z > myZ then
						isHighest = false
						break
					end
				end
			end
	
			if isHighest then
				local nudgeAngle = math.rad( ( ( self.shape.id * 37 ) % 360 ) )
				local nudgeDir = sm.vec3.new( 1, 0, 0 ):rotateZ( nudgeAngle )
				local topOffset = self.shape.worldRotation * sm.vec3.new( 0, self.shape:getBoundingBox().y * 0.5, 0 )

				sm.physics.applyImpulse( self.shape, nudgeDir * self.shape:getBody().mass * 0.03, true, topOffset )
				self.sv.nudgeTicks = self.sv.nudgeTicks - 1
			end
		end
		
		self.sv.isPointingUp = IsPointingUp( self.shape )
	end
end

function Crystal.server_onExplosion( self, center, destructionLevel )
	self:sv_onHit( MaxHealth )
end









function Crystal.sv_e_plasmaDrill( self, params )
	self:sv_onHit( PlasmaDrillDamagePerHit )
end

function Crystal.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if type( other ) ~= "Character" then
		local impactVelocity = ( selfPointVelocity - otherPointVelocity ):length() * 15
		self:sv_onHit( impactVelocity )
	end
end

function Crystal.sv_onHit( self, damage )
	if sm.exists( self.shape ) and self.sv.health > 0 then
		self.sv.health = self.sv.health - damage
		if self.sv.health <= 0 then
			local worldPosition = self.shape.worldPosition
			local localUp = self.shape.worldRotation:inverse() * sm.vec3.new( 0, 0, 1 )
			SpawnLoot( self.shape, SelectLoot( "lootsource_mineral_05" ), worldPosition, math.pi / 10, nil, localUp )
			sm.effect.playEffect( self.data.stump and "CrystalTree - BreakCrystalLog Stump" or "CrystalTree - BreakCrystalLog LargeHalf", worldPosition )
			sm.shape.destroyPart( self.shape )
		end
	end
end
