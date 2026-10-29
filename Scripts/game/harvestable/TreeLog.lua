-- TreeLog.lua --
dofile("$SURVIVAL_DATA/Scripts/game/survival_shapes.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/managers/AttachedFireManager.lua" )

TreeLog = class( nil )

local LogHealth = 100
local DamagerPerHit = math.ceil( LogHealth / TREE_LOG_HITS )
local SawDamagePerHit = 5
local SawDamagePerHitHalfLog = 4

function TreeLog.server_onCreate( self )
	self:server_init()
end

function TreeLog.server_onRefresh( self )
	self:server_init()
end

function TreeLog.server_init( self )
	self.health = LogHealth
	self.interactable.publicData = { drillLevel = 1 }
end

function TreeLog.server_onMelee( self, position, attacker, damage, power, hitDirection )
	self:sv_onHit( DamagerPerHit )
end

function TreeLog.sv_onHit( self, damage, type )
	local fireDamage = type == "fire"
	if self.health > 0 then
		self.health = self.health - damage
		if self.health <= 0 then
			local worldPosition = self.shape.worldPosition
			if self.data then
				if self.data.treeType then
					if self.data.treeType == "small" then
						if fireDamage then
							if SurvivalGame then
								local lootList = { { uuid = obj_resource_ember, quantity = 1 } }
								SpawnLoot( self.shape, lootList, self.shape.worldPosition )
							end
						else
							local shapeOffset = sm.item.getShapeOffset( obj_harvest_wood )
							local rotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), self.shape.at )
							sm.shape.createPart( obj_harvest_wood, worldPosition - rotation * shapeOffset, rotation )
						end
						sm.effect.playEffect( "Tree - BreakTrunk Birch", worldPosition, nil, self.shape.worldRotation )
					elseif self.data.treeType == "medium" then
						if fireDamage then
							if SurvivalGame then
								local lootList = { { uuid = obj_resource_ember, quantity = 1 } }
								SpawnLoot( self.shape, lootList, self.shape.worldPosition )
							end
						else
							local shapeOffset = sm.item.getShapeOffset( obj_harvest_wood )
							local rotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), self.shape.at )
							sm.shape.createPart( obj_harvest_wood, worldPosition - rotation * shapeOffset, rotation )
						end
						sm.effect.playEffect( "Tree - BreakTrunk SpruceHalf", worldPosition, nil, self.shape.worldRotation )
					elseif self.data.treeType == "large" then
						if self.data.size then
							if self.data.size == "half" then
								sm.effect.playEffect( "Tree - BreakTrunk PineHalf", worldPosition, nil, self.shape.worldRotation )
								if fireDamage then
									if SurvivalGame then
										local lootList = { { uuid = obj_resource_ember, quantity = 1 } }
										SpawnLoot( self.shape, lootList, self.shape.worldPosition )
									end
								else
									local shapeOffsetA = sm.item.getShapeOffset( obj_harvest_log_l02a )
									local halfOffsetA = sm.vec3.new( 0, 0, shapeOffsetA.z )
									local shapeOffsetB = sm.item.getShapeOffset( obj_harvest_log_l02b )
									local halfOffsetB = sm.vec3.new( 0, 0, shapeOffsetB.z )
									local rotation = self.shape.worldRotation
									local halfTurn = sm.vec3.getRotation( sm.vec3.new( 1, 0, 0 ), sm.vec3.new( 0, 0, -1 ) )
									sm.shape.createPart( obj_harvest_log_l02a, worldPosition - rotation * shapeOffsetA + rotation * halfOffsetA, rotation )
									sm.shape.createPart( obj_harvest_log_l02b, worldPosition - ( rotation * halfTurn ) * shapeOffsetB - rotation * halfOffsetB, rotation * halfTurn )
								end
								sm.effect.playEffect( "Tree - BreakTrunk PineHalf", worldPosition, nil, self.shape.worldRotation )
							elseif self.data.size == "quarter" then
								if fireDamage then
									if SurvivalGame then
										local lootList = { { uuid = obj_resource_ember, quantity = 1 } }
										SpawnLoot( self.shape, lootList, self.shape.worldPosition )
									end
								else
									local shapeOffset = sm.item.getShapeOffset( obj_harvest_wood2 )
									local rotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), self.shape.at )
									sm.shape.createPart( obj_harvest_wood2, worldPosition - rotation * shapeOffset, rotation )
								end
								sm.effect.playEffect( "Tree - BreakTrunk PineQuarter", worldPosition, nil, self.shape.worldRotation )
							end
						end
					end
				end
			end
			sm.shape.destroyPart(self.shape)
		end
	end
end

function TreeLog.server_onExplosion( self, center, destructionLevel )
	self:sv_onHit( destructionLevel * DamagerPerHit )
end


function TreeLog.sawDamage( self )
	if self.data.size and self.data.size == "half" then
		return SawDamagePerHitHalfLog
	end
	return SawDamagePerHit
end

function TreeLog.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if type( other ) == "Shape" and sm.exists( other ) then
		if other.shapeUuid == obj_powertools_sawblade then
			local angularVelocity = other.body.angularVelocity
			if angularVelocity:length() > SPINNER_ANGULAR_THRESHOLD then
				self:sv_onHit( self:sawDamage() )
			end
		end
	end
end
function TreeLog.sv_e_receiveDamage( self, params )
	self:sv_onHit( params.damage, params.type  )
end

function TreeLog.sv_e_plasmaDrill( self )
	if not self.shape:getBurning() then
		self.shape:setBurning( true )
	end
end

function TreeLog.client_onMelee( self, hitPos, attacker, damage, power, hitDirection, hitNormal )
	if type( attacker ) == "Player" then
		local rotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), hitNormal )
		if self.data and self.data.treeType == "small" then
			sm.effect.playEffect( "Tree - BirchHit", hitPos, nil, rotation )
		else
			sm.effect.playEffect( "Tree - DefaultHit", hitPos, nil, rotation )
		end
	end
end