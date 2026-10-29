dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/interactables/PackingStationScreen.lua" )

MininghubSmelterDeposit = class( PackingStationScreen )
local MaxFillCount = 50
local Ore_dataset = {
	["t1"] = { inputUuid = ITEMS.obj_nugget_t1, projectileUuid = projectile_T1, fullAmount = MaxFillCount, shape = ITEMS.obj_moltenorb_t1, effect = "Packingstation - Tomatocrate" },
	["t2"] = { inputUuid = ITEMS.obj_nugget_t2, projectileUuid = projectile_T2, fullAmount = MaxFillCount, shape = ITEMS.obj_moltenorb_t2, effect = "Packingstation - Carrotcrate" },
	["t3"] = { inputUuid = ITEMS.obj_nugget_t3, projectileUuid = projectile_T3, fullAmount = MaxFillCount, shape = ITEMS.obj_moltenorb_t3, effect = "Packingstation - Redbeetcrate" },
	["t4"] = { inputUuid = ITEMS.obj_nugget_t4, projectileUuid = projectile_T4, fullAmount = MaxFillCount, shape = ITEMS.obj_moltenorb_t4, effect = "Packingstation - Brocolicrate" },
	["t5"] = { inputUuid = ITEMS.obj_nugget_t5, projectileUuid = projectile_T5, fullAmount = MaxFillCount, shape = ITEMS.obj_moltenorb_t5, effect = "Packingstation - Brocolicrate" }
}
local offsetPosition = sm.vec3.new( 0.0, -4, 2 )

function MininghubSmelterDeposit.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.count = 0
		self.sv.saved.type = self.params.type or "t1"
		self.sv.saved.isPowered = false
		self.storage:save( self.sv.saved )
	end
	self.sv.externalOpen = false
	self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
	
	self:createAreaTrigger( offsetPosition )
	self.projectileAreaTrigger:setShapeDetection( true )
	self.projectileAreaTrigger:bindOnProjectile( "sv_t_onProjectile" )
	self:sv_alertPacker( self.sv.saved.count )
	self.network:setClientData( { type = self.sv.saved.type, count = self.sv.saved.count, externalOpen = self.sv.externalOpen }, 1 )
	self.network:setClientData( { activated = self.sv.saved.isPowered }, 2 )

	local publicData = {
		state = self.sv.saved.isPowered and "filling" or "off",
		inputUuid = self:sv_getDataSet().inputUuid,
		projectileAreaTrigger = self.projectileAreaTrigger
	}

	self.interactable:setPublicData( publicData )
end

function MininghubSmelterDeposit.server_onFixedUpdate( self )
	if not self.sv.saved.isPowered then
		if TileStorageManager.Sv_SyncedGetValueInSubTable( self.sv.tileStorageKey, TILESTORAGE_FLAGS_TABLE, "minehub:smelter.activated" ) then
			self.sv.saved.isPowered = true
			self.storage:save( self.sv.saved )
			self.network:setClientData( { activated = self.sv.saved.isPowered }, 2 )
			local publicData = self.interactable:getPublicData()
			publicData.state = "filling"
			self.interactable:setPublicData( publicData )
		end
		return
	end
	local externalOpen = false
	local areaTriggerCenter = self.projectileAreaTrigger:getWorldMin() + (self.projectileAreaTrigger:getWorldMax() - self.projectileAreaTrigger:getWorldMin()) * 0.5
	if self.sv.saved.count < MaxFillCount then
		for _, shapeData in ipairs( self.projectileAreaTrigger:getShapes() ) do
			if shapeData.shape:getShapeUuid() == ITEMS.obj_pneumatic_pump and not shapeData.shape.interactable:isActive() then
				if (shapeData.shape:getWorldPosition() - areaTriggerCenter):length() < 1.5 then
					local publicData = shapeData.shape:getInteractable():getPublicData()
					assert( publicData )

					publicData.packingStationTick = sm.game.getCurrentTick()
					publicData.packingStationProjectileUuid = self:sv_getDataSet().projectileUuid
					if publicData.requestExternalOpen then
						externalOpen = true
					end
				end
			end
		end
	end
	local dirty = false
	if self.sv.externalOpen ~= externalOpen then
		dirty = true
	end
	if dirty then
		self:sv_alertPacker( self.sv.saved.count, externalOpen )
	end
end

function MininghubSmelterDeposit.sv_alertPacker( self, count, externalOpen )
	self.sv.saved.count = count

	if self.sv.saved.count >= self:sv_getDataSet().fullAmount then
		local value = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, MININGHUB_CRAFTERS_TABLE,
			"smelter" ) or {}
		value[#value + 1] = self:sv_getDataSet().shape
		TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, MININGHUB_CRAFTERS_TABLE, "smelter", value )
		self.sv.saved.count = 0
		sm.effect.playEffect("Smelter - Input_pipeglow",self.shape:getWorldPosition())
	end
	self.sv.externalOpen = externalOpen
	self.storage:save( self.sv.saved )
	self.network:setClientData( { type = self.sv.saved.type, count = self.sv.saved.count, externalOpen = self.sv.externalOpen }, 1 )
end

function MininghubSmelterDeposit.sv_t_onProjectile( self, _, _, _, hitVelocity, _, _, _, _, _, projectileUuid )
	if not self.sv.saved.isPowered then
		return false
	end
	if self.sv.saved.count >= self:sv_getDataSet().fullAmount then
		return false
	end

	if self:sv_getDataSet().projectileUuid == projectileUuid then
		self:sv_alertPacker( self.sv.saved.count + 1 )
	end
	return false
end

function MininghubSmelterDeposit.sv_getDataSet( self )
	return Ore_dataset[self.sv.saved.type]
end

function MininghubSmelterDeposit.sv_onTransactionSuccess( self )
	self:sv_alertPacker( self.sv.saved.count + 1 )
	self.network:sendToClients( "cl_n_triggerLoading" )
end

-- Client

function MininghubSmelterDeposit.cl_getDataSet( self )
	return Ore_dataset[self.cl.type]
end

function MininghubSmelterDeposit.client_onCreate( self )
	self.cl = {}
	self.cl.index = 0
	self.cl.count = 0
	self.cl.displayCount = 0
	self.cl.currentDisplayCount = 0
	self.cl.glow = 0
	self.cl.open = false
	self.cl.type = ""
	self.cl.pumpCurvePose0 = Curve()
	self.cl.pumpCurvePose1 = Curve()
	self.cl.pumpCurvePose0:init( { { v = 0.0, t = 0.0 }, { v = 1.0, t = 0.05 }, { v = 0.0, t = 0.15 }, { v = 0.0, t = 0.2 }, { v = 0.0, t = 0.45 } } )
	self.cl.pumpCurvePose1:init( { { v = 0.0, t = 0.0 }, { v = 0.0, t = 0.05 }, { v = 0.0, t = 0.15 }, { v = 0.65, t = 0.2 }, { v = 0.0, t = 0.45 } } )
	self.cl.pumpTimer = 0.0
	self.cl.interfaceTimer = 0.0
	self.cl.changeColorTimer = 0.0
	self.cl.maxDisplayCount = MaxFillCount
	self.cl.lastConnectionType = nil
	local rotation = sm.quat.angleAxis( math.pi / 2, sm.vec3.new( 1, 0, 0 ) )
	rotation = rotation * sm.quat.angleAxis( math.pi / 2, sm.vec3.new( 0, 1, 0 ) )

	local offsetRotation = sm.quat.fromEuler( sm.vec3.new( -90, 0, 0 ) )
	self:createAreaTrigger(offsetPosition)
	self.projectileAreaTrigger:bindOnProjectile( "cl_t_onProjectile" )
	self:cl_createEffects(offsetPosition + sm.vec3.new(0,-0.05,-0.2), offsetRotation)
end

function MininghubSmelterDeposit.cl_t_onProjectile( self, _, _, _, hitVelocity, _, _, _, _, _, projectileUuid )
	if not self.cl.activated then
		return
	end
	return PackingStationScreen.cl_handleProjectile( self, hitVelocity, projectileUuid )
end

function MininghubSmelterDeposit.client_onDestroy( self )
	PackingStationScreen.client_onDestroy( self )
end

function MininghubSmelterDeposit.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.type = data.type
		self.cl.open = data.externalOpen
		self:cl_updateCount( data.count )
	elseif channel == 2 then
		self.cl.activated = data.activated
	end
	local prevData = self.interactable.clientPublicData

	self.interactable.clientPublicData = { 
		state = self.cl.activated and "filling" or "off",
		inputUuid = self:cl_getDataSet().inputUuid,
		projectileAreaTrigger = self.projectileAreaTrigger,
		connectionType = prevData and prevData.connectionType or nil,
		lastConnectedTick = prevData and prevData.lastConnectedTick or nil,
	 }
end
