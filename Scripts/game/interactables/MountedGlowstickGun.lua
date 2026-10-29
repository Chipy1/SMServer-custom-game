dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

MountedGlowstickGun = class()
MountedGlowstickGun.maxParentCount = 1
MountedGlowstickGun.maxChildCount = 0
MountedGlowstickGun.connectionInput = bit.bor( sm.interactable.connectionType.logic )
MountedGlowstickGun.connectionOutput = sm.interactable.connectionType.none
MountedGlowstickGun.colorNormal = sm.color.new( 0xf8eb96ff )
MountedGlowstickGun.colorHighlight = sm.color.new( 0xf8eb96ff )
MountedGlowstickGun.poseWeightCount = 1

local FireDelay = 8 --ticks
local MinForce = 125.0
local MaxForce = 135.0
local SpreadDeg = 1.0
local Damage = 34

local ContainerSize = 5
local StackSize = 100

--[[ Server ]]

-- (Event) Called upon creation on server
function MountedGlowstickGun.server_onCreate( self )
	local container = self.shape.interactable:getContainer( 0 )
	if not container then
		container = self.shape:getInteractable():addContainer( 0, ContainerSize, StackSize )
	end
	container:setFilters( { ITEMS.obj_consumable_glowstick } )
	self.sv = {}
	self.sv.container = container
	self.sv.fireDelayProgress = 0
	self.sv.canFire = true
	self.sv.parentActive = false
	self:sv_checkParentState()
	self.sv.saved = self.storage:load()
end

function MountedGlowstickGun.sv_checkParentState( self )
	local logicInteractable, _ = self:getInputs()
	if logicInteractable then
		self.sv.parentActive = logicInteractable:isActive()
	end
end

-- (Event) Called upon game tick. (40 times a second)
function MountedGlowstickGun.server_onFixedUpdate( self, timeStep )
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
function MountedGlowstickGun.sv_tryFire( self )
	local logicInteractable = self:getInputs()
	local active = logicInteractable and logicInteractable:isActive() or false
	local freeFire = not sm.game.getEnableAmmoConsumption() and not self.sv.container

	local triggered = active and ( not self.sv.parentActive ) and self.sv.canFire
	if freeFire then
		if triggered then
			self:sv_fire()
		end
	else
		if triggered and self.sv.container then
			sm.container.beginTransaction()
			sm.container.spend( self.sv.container, ITEMS.obj_consumable_glowstick, 1 )
			if sm.container.endTransaction() then
				self:sv_fire()
			end
		end
	end
end

function MountedGlowstickGun.sv_fire( self )
	self.sv.canFire = false
	local firePos = sm.vec3.new( 0.0, 0.0, 0.375 )
	local fireForce = math.random( MinForce, MaxForce )

	-- Add random spread
	local dir = sm.noise.gunSpread( sm.vec3.new( 0.0, 0.0, 1.0 ), SpreadDeg )

	-- Fire projectile from the shape
	sm.projectile.shapeProjectileAttack( projectile_glowstick, Damage, firePos, dir * fireForce, self.shape )

	self.network:sendToClients( "cl_onShoot" )
end


--[[ Client ]]

-- (Event) Called upon creation on client
function MountedGlowstickGun.client_onCreate( self )
	self.cl = {}
	self.cl.boltValue = 0.0
	self.cl.shootEffect = sm.effect.createEffect( "MountedPotatoRifle - Shoot", self.interactable )
end

function MountedGlowstickGun.client_onDestroy( self )
	if self.gui and self.gui:isActive() then
		self.gui:close()
		self.gui:destroy()
	end
end

function MountedGlowstickGun.client_canCarry( self )
	if self.cl.container == nil then
		self.cl.container = self.shape.interactable:getContainer( 0 )
	end
	if self.cl.container and sm.exists( self.cl.container ) then
		return not self.cl.container:isEmpty()
	end
	return false
end

function MountedGlowstickGun.cl_e_onClose( self )
	self.gui = nil
end

-- (Event) Called upon every frame. (Same as fps)
function MountedGlowstickGun.client_onUpdate( self, dt )
	if self.cl.boltValue > 0.0 then
		self.cl.boltValue = math.max( self.cl.boltValue - dt * 10, 0.0 )
	end
	if self.cl.boltValue ~= self.cl.prevBoltValue then
		self.interactable:setPoseWeight( 0, self.cl.boltValue ) --Clamping inside
		self.cl.prevBoltValue = self.cl.boltValue
	end
end

function MountedGlowstickGun.client_getAvailableParentConnectionCount( self, connectionType )
	if bit.band( connectionType, sm.interactable.connectionType.logic ) ~= 0 then
		return 1 - #self.interactable:getParents( sm.interactable.connectionType.logic )
	end
	if bit.band( connectionType, sm.interactable.connectionType.ammo ) ~= 0 then
		return 1 - #self.interactable:getParents( sm.interactable.connectionType.ammo )
	end
	return 0
end

-- Called from server upon the gun shooting
function MountedGlowstickGun.cl_onShoot( self )
	self.cl.boltValue = 1.0
	self.cl.shootEffect:start()
	local impulse = sm.vec3.new( 0, 0, -1 ) * 500
	sm.physics.applyImpulse( self.shape, impulse )
end

function MountedGlowstickGun.getInputs( self )
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

function MountedGlowstickGun.client_onInteract( self, character, state )
	if state == true then
		local container = self.shape.interactable:getContainer( 0 )
		if container then
			self.gui = nil

			self.gui = sm.gui.createGlowstickContainerGui( true )

			if self.gui == nil then
				self.gui = sm.gui.createContainerGui( true )
			end

			self.gui:setContainer( "UpperGrid", container )
			self.gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
			self.gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
			self.gui:setOnCloseCallback( "cl_e_onClose" )
			self.gui:open()
		end
	end
end
