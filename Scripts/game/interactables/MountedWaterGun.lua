dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

MountedWaterGun = class()
MountedWaterGun.maxParentCount = 2
MountedWaterGun.maxChildCount = 0
MountedWaterGun.connectionInput = bit.bor( sm.interactable.connectionType.logic, sm.interactable.connectionType.water )
MountedWaterGun.connectionOutput = sm.interactable.connectionType.none
MountedWaterGun.colorNormal = sm.color.new( 0x00acfcff )
MountedWaterGun.colorHighlight = sm.color.new( 0x00acfcff )
MountedWaterGun.connectIcon = "water"
MountedWaterGun.connectIconScale = 0.75

MountedWaterGun.poseWeightCount = 1

local FireDelay = 8 --ticks
local Force = 10.0

--[[ Server ]]

-- (Event) Called upon creation on server
function MountedWaterGun.server_onCreate( self )
	self:sv_init()
end

-- (Event) Called when script is refreshed (in [-dev])
function MountedWaterGun.server_onRefresh( self )
	self:sv_init()
end

-- Initialize mounted gun
function MountedWaterGun.sv_init( self )
	self.sv = {}
	self.sv.fireDelayProgress = 0
	self.sv.canFire = true
	self.sv.parentActive = false
	self:sv_checkParentState()

	local container = self.interactable:getContainer( 0 )
	if not container then
		container = self.shape:getInteractable():addContainer( 0, 1, 20 )
	end
	container:setFilters( { ITEMS.obj_consumable_water } )
end

function MountedWaterGun.sv_checkParentState( self )
	local logicInteractable, _ = self:getInputs()
	if logicInteractable then
		self.sv.parentActive = logicInteractable:isActive()
	end
end

-- (Event) Called upon game tick. (40 times a second)
function MountedWaterGun.server_onFixedUpdate( self, timeStep )
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
function MountedWaterGun.sv_tryFire( self )
	local logicInteractable, waterInteractable = self:getInputs()
	local active = logicInteractable and logicInteractable:isActive() or false
	if active and not self.sv.parentActive and self.sv.canFire then
		local waterContainer = waterInteractable and waterInteractable:getContainer( 0 ) or nil
		local freeFire = not sm.game.getEnableAmmoConsumption() and not waterContainer
		if freeFire or TryConsumePowerResource( self.interactable, ITEMS.obj_consumable_water, sm.interactable.connectionType.water ) == PowerConsumeType.resource then
			self:sv_fire()
		end
	end
end

function MountedWaterGun.sv_fire( self )
	self.sv.canFire = false
	local firePos = sm.vec3.new( 0.0, 0.0, 0.375 )

	-- Fire projectile from the shape
	sm.projectile.shapeFire( self.shape, projectile_water, firePos, sm.vec3.new( 0, 0, 1 ) * Force, 0 )

	self.network:sendToClients( "cl_onShoot" )
end


--[[ Client ]]

-- (Event) Called upon creation on client
function MountedWaterGun.client_onCreate( self )
	self.cl = {}
	self.cl.boltValue = 0.0
	self.cl.shootEffect = sm.effect.createEffect( "Mountedwatercanon - Shoot", self.interactable )
end

-- (Event) Called upon every frame. (Same as fps)
function MountedWaterGun.client_onUpdate( self, dt )
	if self.cl.boltValue > 0.0 then
		self.cl.boltValue = self.cl.boltValue - dt * 10
	end
	if self.cl.boltValue ~= self.cl.prevBoltValue then
		self.interactable:setPoseWeight( 0, self.cl.boltValue ) --Clamping inside
		self.cl.prevBoltValue = self.cl.boltValue
	end
end

function MountedWaterGun.client_getAvailableParentConnectionCount( self, connectionType )
	if bit.band( connectionType, sm.interactable.connectionType.logic ) ~= 0 then
		return 1 - #self.interactable:getParents( sm.interactable.connectionType.logic )
	end
	if bit.band( connectionType, sm.interactable.connectionType.water ) ~= 0 then
		return 1 - #self.interactable:getParents( sm.interactable.connectionType.water )
	end
	return 0
end

-- Called from server upon the gun shooting
function MountedWaterGun.cl_onShoot( self )
	self.cl.boltValue = 1.0
	self.cl.shootEffect:start()
	local impulse = sm.vec3.new( 0, 0, -1 ) * 500
	sm.physics.applyImpulse( self.shape, impulse )
end

function MountedWaterGun.getInputs( self )
	local logicInteractable = nil
	local waterInteractable = nil
	local parents = self.interactable:getParents()
	if parents[2] then
		if parents[2]:hasOutputType( sm.interactable.connectionType.logic ) then
			logicInteractable = parents[2]
		elseif parents[2]:hasOutputType( sm.interactable.connectionType.water ) then
			waterInteractable = parents[2]
		end
	end
	if parents[1] then
		if parents[1]:hasOutputType( sm.interactable.connectionType.logic ) then
			logicInteractable = parents[1]
		elseif parents[1]:hasOutputType( sm.interactable.connectionType.water ) then
			waterInteractable = parents[1]
		end
	end

	return logicInteractable, waterInteractable
end

function MountedWaterGun.client_canInteract( self )
	return true
end

function MountedWaterGun.client_onInteract( self, character, state )
	if state == true then
		local container = self.interactable:getContainer( 0 )
		if container then
			self.cl.gui = sm.gui.createWaterContainerGui( true )
			self.cl.gui:setContainer( "UpperGrid", container )
			self.cl.gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
			self.cl.gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
			self.cl.gui:open()
		end
	end
end