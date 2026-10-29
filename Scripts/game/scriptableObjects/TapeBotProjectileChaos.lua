dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

TapeBotProjectileChaos = class( nil )
TapeBotProjectileChaos.isSaveObject = false

local MinTicksBetweenShots = 10
local MaxTicksBetweenShots = 15
local LifeTimeTicks = 40 * 20
local SpreadAngleDeg = 45

--[[ Server ]]
function TapeBotProjectileChaos.server_onCreate( self )
	self.sv = {}
	self.sv.lifetime = LifeTimeTicks
	self.sv.projectileSpawnerNodes = self.params.projectileNodes or {}

	if self.scriptableObject.world == nil then
		self.scriptableObject:destroy()
	end
end

function TapeBotProjectileChaos.server_onFixedUpdate( self )
	self.sv.lifetime = self.sv.lifetime - 1
	if self.sv.lifetime <= 0 then
		self.scriptableObject:destroy()
		return
	end
		
	local world = self.scriptableObject.world
	for i, _ in ipairs( self.sv.projectileSpawnerNodes ) do
		local node = self.sv.projectileSpawnerNodes[i]
		if not node.cooldown then
			node.cooldown = math.random( MinTicksBetweenShots, MaxTicksBetweenShots )
		end
		if node.cooldown <= 0 then
			local randomDirection = math.random() * 2 * math.pi
			local randomAngle = math.random() * DegToRad( SpreadAngleDeg )
			local randomRotation = sm.quat.angleAxis( randomDirection, sm.quat.getAt( node.rotation ) ) * sm.quat.angleAxis( randomAngle, sm.quat.getRight( node.rotation ) )
			sm.projectile.customProjectileAttack( nil, projectile_tape, 0, node.position, randomRotation * sm.quat.getAt( node.rotation ) * 40, world )
			sm.effect.playEffect( "Botconverter - Tapebot_muzzleflash", node.position, nil, randomRotation * node.rotation )
			node.cooldown = math.random( MinTicksBetweenShots, MaxTicksBetweenShots )
		else
			node.cooldown = node.cooldown - 1
		end
	end
end


