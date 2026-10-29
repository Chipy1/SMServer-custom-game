MinerbotThruster = class()

local MinDestructionTickTime = 40 * 3
local MaxDestructionTickTime = 40 * 4

local ThrusterForce = 500

local ExplosionBreachLevel = 1
local ExplosionDestructionRadius = 2.0
local ExplosionImpulseRadius = 6.0
local ExplosionImpulseMagnitude = 25

function MinerbotThruster.server_onCreate( self )
	local currentTick = sm.game.getCurrentTick()
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.destructionTickTimestamp = sm.game.getCurrentTick() + math.random( MinDestructionTickTime, MaxDestructionTickTime )
	end

	if currentTick >= self.sv.saved.destructionTickTimestamp then
		self.shape:destroyShape()
	else
		self.storage:save( self.sv.saved )
	end
end

function MinerbotThruster.server_onFixedUpdate( self, timeStep )
	local currentTick = sm.game.getCurrentTick()
	if currentTick >= self.sv.saved.destructionTickTimestamp then
		self.shape:destroyShape()
		sm.physics.explode( self.shape.worldPosition, ExplosionBreachLevel, ExplosionDestructionRadius, ExplosionImpulseRadius, ExplosionImpulseMagnitude, "Minerbot - ThrusterExplode", nil, { Color = self.shape:getColor() }, nil, 35, self.shape, self.shape:getShapeUuid() )
	end
end

function MinerbotThruster.client_onCreate( self )
	self.cl = {}
	self.cl.thrusterEffect = sm.effect.createEffect( "Minerbot - Thruster03", self.shape )
	self.cl.thrusterEffect:setOffsetRotation( sm.quat.new( 0, 1, 0, 0 ) )
	self.cl.thrusterEffect:start()
end

function MinerbotThruster.client_onFixedUpdate( self, timeStep )
	local impulseDirection = -self.shape:getUp()
	local impulse = impulseDirection * ThrusterForce
	sm.physics.applyImpulse( self.shape, impulse, true )
end

