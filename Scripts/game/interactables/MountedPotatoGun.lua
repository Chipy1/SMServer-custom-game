dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

MountedPotatoGun = class()
MountedPotatoGun.maxParentCount = 2
MountedPotatoGun.maxChildCount = 0
MountedPotatoGun.connectionInput = bit.bor( sm.interactable.connectionType.logic, sm.interactable.connectionType.ammo )
MountedPotatoGun.connectionOutput = sm.interactable.connectionType.none
MountedPotatoGun.colorNormal = sm.color.new( 0xcb0a00ff )
MountedPotatoGun.colorHighlight = sm.color.new( 0xcb0a00ff )
MountedPotatoGun.connectIcon = "ammo"
MountedPotatoGun.connectIconScale = 0.75

MountedPotatoGun.poseWeightCount = 1


local FireDelay = 8 --ticks
local MinForce = 125.0
local MaxForce = 135.0
local SpreadDeg = 1.0
local Damage = 35


--[[ Server ]]

-- (Event) Called upon creation on server
function MountedPotatoGun.server_onCreate( self )
	self.sv = {}
	self.sv.fireDelayProgress = 0
	self.sv.canFire = true
	self.sv.parentActive = false
	self:sv_checkParentState()
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = { automatic = false }
		self.storage:save( self.sv.saved )
	end
	self.network:setClientData( self.sv.saved.automatic )
end

function MountedPotatoGun.sv_checkParentState( self )
	local logicInteractable, _ = self:getInputs()
	if logicInteractable then
		self.sv.parentActive = logicInteractable:isActive()
	end
end

-- (Event) Called upon game tick. (40 times a second)
function MountedPotatoGun.server_onFixedUpdate( self, timeStep )
	if not self.sv.canFire then
		self.sv.fireDelayProgress = self.sv.fireDelayProgress + 1
		if self.sv.fireDelayProgress >= FireDelay then
			self.sv.fireDelayProgress = 0
			self.sv.canFire = true
		end
	end
	self:sv_tryFire()
	self:sv_checkParentState()
end

-- Attempt to fire a projectile
function MountedPotatoGun.sv_tryFire( self )
	local logicInteractable, ammoInteractable = self:getInputs()
	local active = logicInteractable and logicInteractable:isActive() or false
	local triggered = ( self.sv.saved.automatic and active ) or ( active and not self.sv.parentActive )
	if triggered and self.sv.canFire then
		local ammoContainer = ammoInteractable and ammoInteractable:getContainer( 0 ) or nil
		local freeFire = not sm.game.getEnableAmmoConsumption() and not ammoContainer
		if freeFire or TryConsumePowerResource( self.interactable, ITEMS.obj_plantables_potato, sm.interactable.connectionType.ammo ) == PowerConsumeType.resource then
			self:sv_fire()
		end
	end
end

function MountedPotatoGun.sv_fire( self )
	self.sv.canFire = false
	local firePos = sm.vec3.new( 0.0, 0.0, 0.375 )
	local fireForce = math.random( MinForce, MaxForce )

	-- Add random spread
	local dir = sm.noise.gunSpread( sm.vec3.new( 0.0, 0.0, 1.0 ), SpreadDeg )

	-- Fire projectile from the shape
	sm.projectile.shapeProjectileAttack( projectile_potato, Damage, firePos, dir * fireForce, self.shape )

	self.network:sendToClients( "cl_onShoot" )
end


--[[ Client ]]

-- (Event) Called upon creation on client
function MountedPotatoGun.client_onCreate( self )
	self.cl = {}
	self.cl.boltValue = 0.0
	self.cl.changeFireMode = 0.0
	self.cl.shootEffect = sm.effect.createEffect( "MountedPotatoRifle - Shoot", self.interactable )
end

-- (Event) Called upon every frame. (Same as fps)
function MountedPotatoGun.client_onUpdate( self, dt )
	if self.cl.changeFireMode > 0.0 then
		self.cl.changeFireMode = math.max( self.cl.changeFireMode - dt * 5, 0.0 )
		if self.cl.changeFireMode == 0.0 then
			self.cl.boltValue = 0.0
		else
			self.cl.boltValue = 1.0
		end
	else
		if self.cl.boltValue > 0.0 then
			self.cl.boltValue = math.max( self.cl.boltValue - dt * 10, 0.0 )
		end
	end
	if self.cl.boltValue ~= self.cl.prevBoltValue then
		self.interactable:setPoseWeight( 0, self.cl.boltValue ) --Clamping inside
		self.cl.prevBoltValue = self.cl.boltValue
	end
end

function MountedPotatoGun.client_getAvailableParentConnectionCount( self, connectionType )
	if bit.band( connectionType, sm.interactable.connectionType.logic ) ~= 0 then
		return 1 - #self.interactable:getParents( sm.interactable.connectionType.logic )
	end
	if bit.band( connectionType, sm.interactable.connectionType.ammo ) ~= 0 then
		return 1 - #self.interactable:getParents( sm.interactable.connectionType.ammo )
	end
	return 0
end

-- Called from server upon the gun shooting
function MountedPotatoGun.cl_onShoot( self )
	self.cl.boltValue = 1.0
	self.cl.shootEffect:start()
	local impulse = sm.vec3.new( 0, 0, -1 ) * 500
	sm.physics.applyImpulse( self.shape, impulse )
end

function MountedPotatoGun.getInputs( self )
	local logicInteractable = nil
	local ammoInteractable = nil
	local parents = self.interactable:getParents()
	if parents[2] then
		if parents[2]:hasOutputType( sm.interactable.connectionType.logic ) then
			logicInteractable = parents[2]
		elseif parents[2]:hasOutputType( sm.interactable.connectionType.ammo ) then
			ammoInteractable = parents[2]
		end
	end
	if parents[1] then
		if parents[1]:hasOutputType( sm.interactable.connectionType.logic ) then
			logicInteractable = parents[1]
		elseif parents[1]:hasOutputType( sm.interactable.connectionType.ammo ) then
			ammoInteractable = parents[1]
		end
	end

	return logicInteractable, ammoInteractable
end

function MountedPotatoGun.client_canInteract( self )
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), self.cl.automatic and "#{INTERACTION_SWITCH_TO_SEMI-AUTOMATIC}" or "#{INTERACTION_SWITCH_TO_AUTOMATIC}" )
	return true
end

function MountedPotatoGun.client_onInteract( self, character, state )
	if state == true then
		self.cl.changeFireMode = 1.0
		self.network:sendToServer( "sv_n_changeFireMode" )
	end
end

function MountedPotatoGun.sv_n_changeFireMode( self )
	self.sv.saved.automatic = not self.sv.saved.automatic
	self.storage:save( self.sv.saved )
	self.network:setClientData( self.sv.saved.automatic )
end

function MountedPotatoGun.client_onClientDataUpdate( self, automatic )
	self.cl.automatic = automatic
end