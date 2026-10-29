dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_meleeattacks.lua" )

DrillAttack = class( nil )

local DefaultDamage = 10
local DefaultKnockbackForce = 2000

local DefaultMeleeName = melee_totebot_charge
local DefaultMeleeReach = 2.0
local DefaultMeleeTickCooldown = 5

-- Voxel terrain digging
local DefaultDigRadius = 1.5
local DefaultDigDistance = 3.0
local DefaultDigStrength = 0.75 -- Set to 0 to disable voxel digging




function DrillAttack.sv_onCreate( self, unit, params )
	params = params or {}
	self.unit = unit
	self.damage = params.damage or DefaultDamage
	self.knockbackForce = params.knockbackForce or DefaultKnockbackForce

	self.meleeName = params.meleeName or DefaultMeleeName
	self.meleeReach = params.meleeReach or DefaultMeleeReach
	self.meleeTickCooldown = params.meleeTickCooldown or DefaultMeleeTickCooldown

	self.digRadius = params.digRadius or DefaultDigRadius
	self.digDistance = params.digDistance or DefaultDigDistance
	self.digStrength = params.digStrength or DefaultDigStrength

	self.active = false
	self.lastMeleeTick = 0
end

function DrillAttack.sv_setActive( self, active )
	self.active = active
end

function DrillAttack.sv_onFixedUpdate( self, dt )
	if not self.active or not sm.exists( self.unit.character ) then
		return
	end

	local currentTick = sm.game.getCurrentTick()
	local world = self.unit.character:getWorld()

	if currentTick - self.lastMeleeTick >= self.meleeTickCooldown then
		self.lastMeleeTick = currentTick
		local meleeDirectionRange = self.unit.character.direction * self.meleeReach
		sm.melee.meleeAttack( self.meleeName, self.damage, self.unit.character.worldPosition, meleeDirectionRange, self.unit, 0, self.knockbackForce, { self.unit.character } )
	end

	if self.digStrength > 0 then
		local botPosition = self.unit.character.worldPosition
		local moveDir = self.unit.character.velocity:safeNormalize( self.unit.character.direction )
		local digRayEnd = botPosition + moveDir * self.digDistance
		local hit, digResult = sm.physics.spherecast( botPosition, digRayEnd, self.unit.character:getRadius(), self.unit.character, sm.physics.filter.voxelTerrain )
		if hit and digResult then
			local hitPosition = botPosition + ( digRayEnd - botPosition ) * digResult.fraction
			local digPosition = hitPosition + moveDir * self.digRadius * 0.5
			if DrillDebug then
				sm.debugDraw.flashSphere( digPosition, self.digRadius, sm.color.new( 1, 0, 1, 0.8 ), 0.1 )
			end
			world:sphereVoxelDensitySubtraction( digPosition, self.digRadius, sm.world.voxelFilter.material0, self.digStrength )
		end
	end
end
