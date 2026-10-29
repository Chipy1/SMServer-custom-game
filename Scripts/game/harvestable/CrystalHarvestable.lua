-- CrystalHarvestable.lua --
dofile("$SURVIVAL_DATA/Scripts/game/survival_constants.lua")
dofile("$SURVIVAL_DATA/Scripts/game/survival_shapes.lua")

CrystalHarvestable = class( nil )

local MaxHealth = 100
local PlasmaDrillDamagePerHit = 2

function CrystalHarvestable.server_onCreate( self )
	self:sv_init()
end

function CrystalHarvestable.server_onRefresh( self )
	self:sv_init()
end

function CrystalHarvestable.sv_init( self )
	self.harvestable.publicData = { drillLevel = 1 }
	self.health = MaxHealth
	self.hits = {}
end









function CrystalHarvestable.server_onFloating( self )
	self:sv_onHit( MaxHealth, nil )
end

function CrystalHarvestable.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if type( other ) ~= "Character" then
		local impactVelocity = ( selfPointVelocity - otherPointVelocity ):length() * 15
		self:sv_onHit( impactVelocity, collisionPosition )
	end
end

function CrystalHarvestable.server_onExplosion( self, center, destructionLevel )
	self:sv_onHit( MaxHealth, center )
end

function CrystalHarvestable.sv_e_plasmaDrill( self, params )
	self:sv_onHit( PlasmaDrillDamagePerHit, params.position )
end

function CrystalHarvestable.sv_onHit( self, damage, position )
	if sm.exists( self.harvestable ) and self.health > 0 then
		self.health = self.health - damage
		if self.health <= 0 then
			local color = self.harvestable:getColor()
			local harvestablePosition = self.harvestable.worldPosition
			local harvestableRotation = self.harvestable.worldRotation
			local placementOffset = harvestableRotation * sm.vec3.new( self.data.offset.x, self.data.offset.y, self.data.offset.z )
			local blueprint = position and self.data.blueprint or self.data.blueprint:gsub( "%.blueprint", "_dyn.blueprint" )
			local bodies = sm.creation.importFromFile( nil, blueprint, harvestablePosition + placementOffset, harvestableRotation )
			
			if position then
				local closestToAttack = nil
				local closestHitDistance = math.huge
				for _, currentBody in ipairs( bodies ) do
					local shapes = currentBody:getShapes()
					for _, currentShape in ipairs( shapes ) do
						currentShape:setColor( color )
						local shapePos = currentShape:getWorldPosition()
						local distance = ( shapePos - position ):length()
						if distance < closestHitDistance then
							closestToAttack = currentShape
							closestHitDistance = distance
						end
					end
				end
				
				assert( closestToAttack, "No shapes found in Crystal Harvestable blueprint" )
				closestToAttack.interactable:setParams( { inheritedDamage = 100 } )
			end
			
			sm.effect.playEffect( "CrystalTree - BreakCrystalTree", harvestablePosition )
			sm.harvestable.destroy( self.harvestable )
		end
	end
end

function CrystalHarvestable.client_onCreate( self )
	sm.effect.playHostedEffect( "CrystalTree - Resonance", self.harvestable )
end
