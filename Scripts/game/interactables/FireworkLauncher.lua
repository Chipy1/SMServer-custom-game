dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

FireworkLauncher = class()
FireworkLauncher.poseWeightCount = 1

local DESTROY_DELAY = 1.0 -- ticks (1 seconds)
local LIFETIME = 40.0 * 16.0 -- ticks (2 seconds)
local DELAY = 120.0 -- ticks (3 seconds)
local COUNT = 12.0
local SPREAD = 6.0 -- degrees
local MIN_MAX_FORCE = { 41.0, 45.0 }
local UP = sm.vec3.new( 0, 1, 0 )

local PROJECTILE_MAP = {
	[0] = sm.uuid.new( "953b363a-309f-4b27-94e0-35bba25edf5b" ),
	[1] = sm.uuid.new( "6ff3f5ec-047b-48cf-86a3-99b4f6dc29db" ),
	[2] = sm.uuid.new( "4a04268b-b9bc-4e73-8c37-5c4879da51b6" ),
	[3] = sm.uuid.new( "b32792a2-fa5f-4a48-ba74-a90e57dcbf8e" ),
	[4] = sm.uuid.new( "6442e998-67c6-4da0-bd83-388274b1e88c" ),
	[5] = sm.uuid.new( "e838c904-721c-46e1-b13e-db5f8284c783" ),
	[6] = sm.uuid.new( "3b95791c-9059-4468-bc13-96ba837aba0b" ),
	[7] = sm.uuid.new( "fdbfed8a-efe5-4fc1-a0ff-0730327c5b8e" ),
	[8] = sm.uuid.new( "bf9c3983-374d-42ad-b831-1ec104a11dee" ),
	[9] = sm.uuid.new( "92b31c48-3b48-4d6c-85e8-ca072cadad8d" ),
	[10] = sm.uuid.new( "930ff92a-3d55-4bee-b02d-3920c32094bc" )
}

function FireworkLauncher.server_onCreate( self )
	self:server_init()
end

function FireworkLauncher.server_onRefresh( self )
	self:server_init()
end

function FireworkLauncher.server_init( self )
	self.sv = {}
	self.sv.destroyTimer = -1
	self.sv.ticksSinceIgnition = -1

	self.sv.launchTimeIdx = 0
	self.sv.launchTimes = {}
	self.sv.launchTimes[ 0 ] = 0

	-- Stratified random sampling of explosion times. Makes sure they are somewhat evenly spread out, but still random!
	local slice = LIFETIME / COUNT
	for i = 1, COUNT - 1 do
		local t0 = i * slice
		local t1 = ( i + 1 ) * slice
		self.sv.launchTimes[#self.sv.launchTimes + 1] = math.floor( t0 + math.random() * ( t1 - t0 ) )
	end
end

function FireworkLauncher.server_onFixedUpdate( self, _ )
	if self.sv.destroyTimer >= 0 then
		self.sv.destroyTimer = self.sv.destroyTimer - 1
		if self.sv.destroyTimer == 0 then
			sm.effect.playEffect( "Fireworks - Firework_finnished", self.shape.worldPosition, nil, nil, nil, { Color = self.shape:getColor() } )
			sm.shape.destroyShape( self.shape )
		end
	elseif self.sv.ticksSinceIgnition >= 0 then
		local shouldFire = self.sv.ticksSinceIgnition >= self.sv.launchTimes[self.sv.launchTimeIdx] + DELAY
		self.sv.ticksSinceIgnition = self.sv.ticksSinceIgnition + 1
		if shouldFire then
			local dir = sm.noise.gunSpread( UP, SPREAD )
			local speed = math.random( MIN_MAX_FORCE[1], MIN_MAX_FORCE[2] )
			local ticksToApex = dir.y * speed / ( GRAVITY / SERVER_TICKS_PER_SECOND )

			local projectileIdx = 10
			local shapeColor = self.shape:getColor()
			if shapeColor ~= sm.item.getShapeDefaultColor( self.shape.uuid ) then
				local c = shapeColor:getUintRgba()
				projectileIdx = sm.tool.findPaintToolPaletteColumnIndex( c )
			end

			sm.projectile.shapeCustomProjectileAttack(
				{ },
				PROJECTILE_MAP[math.min(projectileIdx, #PROJECTILE_MAP)],
				0,
				sm.vec3.new( 0, 0, 0 ),
				dir * speed,
				self.shape,
				nil, nil, ticksToApex
			)

			local offsetInWorldSpace = self.shape.worldRotation * sm.vec3.new( 0, 0.4, 0 )
			sm.effect.playEffect( "Fireworks - Firework_launch", self.shape.worldPosition + offsetInWorldSpace, sm.vec3.zero(), self.shape.worldRotation * sm.quat.rotNegX90() )

			self.sv.launchTimeIdx = self.sv.launchTimeIdx + 1
			local allFired = self.sv.launchTimeIdx > #self.sv.launchTimes
			if allFired then self.sv.destroyTimer = DESTROY_DELAY end
		end
	end
end

function FireworkLauncher.server_tryIgnite( self )
	if self.sv.ticksSinceIgnition == -1 then
		self.sv.ticksSinceIgnition = 0
		self.network:sendToClients( "client_ignite" )
	end
end

function FireworkLauncher.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	self:server_tryIgnite()
end

function FireworkLauncher.server_onMelee( self, hitPos, attackingCharacter, damage, power, hitDirection )
	self:server_tryIgnite()
end

function FireworkLauncher.server_onExplosion( self, center, destructionLevel )
	self:server_tryIgnite()
end

function FireworkLauncher.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if type( other ) ~= "Character" or not other:isPlayer() then
		self:server_tryIgnite()
	end
end

function FireworkLauncher.client_onCreate( self )
	self.cl = {}
	self.cl.poseScaleTimer = -1
	self.cl.color = self.shape:getColor()
	self.cl.fired = false

	self.interactable:setSubMeshVisible( "m_fireworks_colored", false )
	self.interactable:setSubMeshVisible( "m_fireworks_uncolored", true )
end

function FireworkLauncher.client_canErase( self )
	if self.cl.fired then
		NotificationManager.Cl_AddGenericNotification( "#{INFO_BUSY}", BUSY_NOTIFICATION_DURATION )
	end
	return not self.cl.fired
end

function FireworkLauncher.client_ignite( self )
	self.cl.poseScaleTimer = 0
	sm.effect.playEffect( "Fireworks - Firework_activate", self.shape.worldPosition )
end

function FireworkLauncher.client_onUpdate( self, dt )
	if self.cl.poseScaleTimer >= 0 then
		local duration = DELAY / SERVER_TICKS_PER_SECOND
		self.cl.poseScaleTimer = self.cl.poseScaleTimer + dt
		if self.cl.poseScaleTimer < duration then
			self.interactable:setPoseWeight( 0, ScaleAndVibrate( self.cl.poseScaleTimer, duration, 0.1, 0.3, 250 ) )
		else
			self.cl.poseScaleTimer = -1
			self.interactable:setPoseWeight( 0, 0 )
			self.interactable:setSubMeshVisible( "m_fireworks_colored", false )
			self.interactable:setSubMeshVisible( "m_fireworks_uncolored", false )
			self.cl.fired = true

			local color = self.shape:getColor()
			local hasDefaultColor = color == sm.item.getShapeDefaultColor( self.shape.uuid )
			local effectName = hasDefaultColor and "Fireworks - Rocket_submeshes_uncolored" or "Fireworks - Rocket_submeshes_colored"
			sm.effect.playHostedEffect( effectName, self.interactable, nil, { Color = color }, nil, nil, nil, sm.quat.rotNegX90(), sm.vec3.one() )
		end
	end

	if not self.cl.fired then
		local color = self.shape:getColor()
		if color ~= self.cl.color then
			local hasDefaultColor = color == sm.item.getShapeDefaultColor( self.shape.uuid )
			self.interactable:setSubMeshVisible( "m_fireworks_colored", not hasDefaultColor )
			self.interactable:setSubMeshVisible( "m_fireworks_uncolored", hasDefaultColor )
			self.cl.color = color
		end
	end
end
