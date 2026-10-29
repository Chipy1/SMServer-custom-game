-- Shared
dofile( "$SURVIVAL_DATA/Scripts/game/util/Curve.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

PackingStationScreen = class( nil )
PackingStationScreen.poseWeightCount = 3
local ChangeColorDelay = 0.15
local MaxDisplayCount = 20
local AreaTriggerOffsetPosition = sm.vec3.new( 0.0, -2.3, 2 )
local veggie_dataset = {
	{ inputUuid = ITEMS.obj_plantables_tomato,   projectileUuid = projectile_tomato,   fullAmount = 20, shape = ITEMS.obj_crates_tomato,   effect = "Packingstation - Tomatocrate" },
	{ inputUuid = ITEMS.obj_plantables_carrot,   projectileUuid = projectile_carrot,   fullAmount = 20, shape = ITEMS.obj_crates_carrot,   effect = "Packingstation - Carrotcrate" },
	{ inputUuid = ITEMS.obj_plantables_redbeet,  projectileUuid = projectile_redbeet,  fullAmount = 20, shape = ITEMS.obj_crates_redbeet,  effect = "Packingstation - Redbeetcrate" },
	{ inputUuid = ITEMS.obj_plantables_broccoli, projectileUuid = projectile_broccoli, fullAmount = 20, shape = ITEMS.obj_crates_broccoli, effect = "Packingstation - Brocolicrate" }
}

local fruit_dataset = {
	{ inputUuid = ITEMS.obj_plantables_banana,    projectileUuid = projectile_banana,    fullAmount = 20, shape = ITEMS.obj_crates_banana,    effect = "Packingstation - Bananacrate" },
	{ inputUuid = ITEMS.obj_plantables_blueberry, projectileUuid = projectile_blueberry, fullAmount = 20, shape = ITEMS.obj_crates_blueberry, effect = "Packingstation - Blueberrycrate" },
	{ inputUuid = ITEMS.obj_plantables_orange,    projectileUuid = projectile_orange,    fullAmount = 20, shape = ITEMS.obj_crates_orange,    effect = "Packingstation - Orange" },
	{ inputUuid = ITEMS.obj_plantables_pineapple, projectileUuid = projectile_pineapple, fullAmount = 20, shape = ITEMS.obj_crates_pineapple, effect = "Packingstation - Pineapplecrate" }
}

PackingStationScreen.Datasets = { VEGGIE = veggie_dataset, FRUIT = fruit_dataset }

function PackingStationScreen.createAreaTrigger( self,position )
	if self.projectileAreaTrigger then return end

	local projectileBoxSize = sm.vec3.new( 0.75, 0.75, 0.1 )
	local filter = sm.areaTrigger.filter.staticBody + sm.areaTrigger.filter.dynamicBody

	self.projectileAreaTrigger = sm.areaTrigger.createAttachedBox( self.interactable, projectileBoxSize, position, sm.quat.identity(), filter )
end

-- Server

function PackingStationScreen.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()

	if self.sv.saved == nil then
		if not self.params then
			sm.log.info( "Patching missing PackingStationScreen params" )
			local x, y = getCell( self.shape:getWorldPosition().x, self.shape:getWorldPosition().y )
			self.params = {}
			self.params.packingStation = {}
			self.params.packingStation.mid = FindFirstInteractableWithinCell( tostring( obj_packingstation_mid ), x, y )
			local screens = {}
			concat( screens, FindInteractablesWithinCell( tostring( obj_packingstation_screen_fruit ), x, y ) )
			concat( screens, FindInteractablesWithinCell( tostring( obj_packingstation_screen_veggie ), x, y ) )
			for idx, interactable in ipairs( screens ) do
				if self.shape:getId() == interactable:getShape():getId() then
					self.params.index = idx
				end
			end
		end

		self.sv.saved = {}
		self.sv.saved.index = self.params.index
		self.sv.saved.mid = self.params.packingStation.mid
		self.sv.saved.count = 0
		self.storage:save( self.sv.saved )
	end

	self.sv.publicData = {}

	self:createAreaTrigger(AreaTriggerOffsetPosition);
	self.projectileAreaTrigger:bindOnProjectile( "sv_t_onProjectile" )
	self:sv_updateClientData( self.sv.saved.count )
end

function PackingStationScreen.sv_updateClientData( self, count )
	self.sv.saved.count = count

	self.storage:save( self.sv.saved )

	local dataset = PackingStationScreen.Datasets[self.data.type][self.sv.saved.index]

	local publicData = {
		state = "filling",
		count = count,
		fullAmount = dataset.fullAmount,
		shape = dataset.shape,
		effect = dataset.effect,
		inputUuid = dataset.inputUuid,
		projectileAreaTrigger = self.projectileAreaTrigger

	}

	if self.sv.saved.count >= dataset.fullAmount then
		publicData.state = "waiting_for_pickup"
	end

	self.sv.publicData = publicData;
	self.interactable:setPublicData( self.sv.publicData )
	self.network:setClientData( { index = self.sv.saved.index, count = self.sv.saved.count,state = publicData.state  } )
end

function PackingStationScreen.sv_t_onProjectile( self, trigger, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	local dataset = self:sv_getDataSet()

	if self.sv.saved.count >= dataset.fullAmount then
		return false
	end

	if dataset.projectileUuid == projectileUuid then
		self:sv_updateClientData( self.sv.saved.count + 1 )
		local x = math.floor( self.shape.worldPosition.x / 64 )
		local y = math.floor( self.shape.worldPosition.y / 64 )
		local cellKey = CellKey( x, y )
		PackingStationManager.Sv_SetStationLoads( self.sv.saved.count, cellKey, tostring( dataset.inputUuid ) )
		QuestManager.Sv_SendEvent( QuestEvent.PackingStationDeposit, { depositUuid = dataset.inputUuid } )
	end

	return false; -- client callback will absorb the projectile
end

function PackingStationScreen.server_onFixedUpdate( self )
	local dataset = PackingStationScreen.Datasets[self.data.type][self.sv.saved.index]
	local data = self.interactable:getPublicData();
	local state = "filling"
	if data and data.state then
		state = data.state
	end

	local dirty = false
	local count = self.sv.saved.count

	if self.sv.saved.count >= dataset.fullAmount and state and state == "picked_up" then
		dirty = true
		count = 0
	end

	if dirty then
		self:sv_updateClientData( count )
	end
end



function PackingStationScreen.sv_getDataSet( self )
	return PackingStationScreen.Datasets[self.data.type][self.sv.saved.index]
end

function PackingStationScreen.sv_onTransactionSuccess( self, params )
	self:sv_updateClientData( self.sv.saved.count + 1 )
	local x = math.floor( self.shape.worldPosition.x / 64 )
	local y = math.floor( self.shape.worldPosition.y / 64 )
	local cellKey = CellKey( x, y )
	PackingStationManager.Sv_SetStationLoads( self.sv.saved.count, cellKey, tostring( params.item ) )
	QuestManager.Sv_SendEvent( QuestEvent.PackingStationDeposit, { depositUuid = params.item } )
	self.network:sendToClients( "cl_n_triggerLoading" )
end

-- Client
function PackingStationScreen.cl_getDataSet( self )
	return PackingStationScreen.Datasets[self.data.type][self.cl.index]
end

function PackingStationScreen.client_onCreate( self )
	self.cl = {}
	self.cl.index = 0
	self.cl.count = 0
	self.cl.currentDisplayCount = 0
	self.cl.previousDisplayCount = 0
	self.interactable:setGlowMultiplier( 1 )
	self.cl.open = false
	self.cl.pumpCurvePose0 = Curve()
	self.cl.pumpCurvePose1 = Curve()
	self.cl.pumpCurvePose0:init( { { v = 0.0, t = 0.0 }, { v = 1.0, t = 0.05 }, { v = 0.0, t = 0.15 }, { v = 0.0, t = 0.2 }, { v = 0.0, t = 0.45 } } )
	self.cl.pumpCurvePose1:init( { { v = 0.0, t = 0.0 }, { v = 0.0, t = 0.05 }, { v = 0.0, t = 0.15 }, { v = 0.65, t = 0.2 }, { v = 0.0, t = 0.45 } } )
	self.cl.pumpTimer = 0.0
	self.cl.interfaceTimer = 0.0
	self.cl.changeColorTimer = 0.0
	self.cl.lastConnectionType = nil
	self.cl.maxDisplayCount = MaxDisplayCount -- Modified by inheriting MininghubSmelterDeposit
	local offsetRotation = sm.quat.fromEuler( sm.vec3.new( -90, 0, 0 ) )
	self:createAreaTrigger(AreaTriggerOffsetPosition);
	self.projectileAreaTrigger:bindOnProjectile( "cl_t_onProjectile" )
	local effectPosition = sm.vec3.new( 0.0, -2.35, 1.8 )
	self:cl_createEffects( effectPosition, offsetRotation )
end

function PackingStationScreen.cl_createEffects( self,offsetPosition, offsetRotation )
	
	self.cl.connectEffect = sm.effect.createEffect( "Packingstation - Lights_connected_blue", self.shape )
	self.cl.connectEffect:setOffsetPosition( offsetPosition )
	self.cl.connectEffect:setOffsetRotation( offsetRotation )

	self.cl.connectEffectFade = sm.effect.createEffect( "Packingstation - Lights_connected_fadeout_blue", self.shape )
	self.cl.connectEffectFade:setOffsetPosition( offsetPosition )
	self.cl.connectEffectFade:setOffsetRotation( offsetRotation )

	self.cl.approvecEffect = sm.effect.createEffect( "Packingstation - Lights_resourcesapproved_green", self.shape )
	self.cl.approvecEffect:setOffsetPosition( offsetPosition )
	self.cl.approvecEffect:setOffsetRotation( offsetRotation )

	self.cl.approvecEffectFade = sm.effect.createEffect( "Packingstation - Lights_resourcesapproved_fadeout_green", self.shape )
	self.cl.approvecEffectFade:setOffsetPosition( offsetPosition )
	self.cl.approvecEffectFade:setOffsetRotation( offsetRotation )
end

function PackingStationScreen.client_onDestroy( self )
	if self.cl.connectEffect then
		self.cl.connectEffect:destroy()
		self.cl.connectEffect = nil
	end
	if self.cl.connectEffectFade then
		self.cl.connectEffectFade:destroy()
		self.cl.connectEffectFade = nil
	end
	if self.cl.approvecEffect then
		self.cl.approvecEffect:destroy()
		self.cl.approvecEffect = nil
	end
	if self.cl.approvecEffectFade then
		self.cl.approvecEffectFade:destroy()
		self.cl.approvecEffectFade = nil
	end
end

function PackingStationScreen.cl_t_onProjectile( self, trigger, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	return self:cl_handleProjectile( hitVelocity, projectileUuid )
end

function PackingStationScreen.cl_handleProjectile( self, hitVelocity, projectileUuid )

	local dataset = self:cl_getDataSet()
	if self.cl.count >= dataset.fullAmount then
		return false
	end

	if dataset.projectileUuid == projectileUuid then
		self.cl.pumpTimer = 0.0
		sm.effect.playEffect( "Packingstation - Load", self.shape.worldPosition )
		return true; -- absorb
	end
	return false
end

function PackingStationScreen.client_onClientDataUpdate( self, data )
	self.cl.index = data.index
	if self.cl.index == 1 then
		self.interactable:setSubMeshVisible( "icon_01", true )
		self.interactable:setSubMeshVisible( "icon_02", false )
		self.interactable:setSubMeshVisible( "icon_03", false )
		self.interactable:setSubMeshVisible( "icon_04", false )
	elseif self.cl.index == 2 then
		self.interactable:setSubMeshVisible( "icon_01", false )
		self.interactable:setSubMeshVisible( "icon_02", true )
		self.interactable:setSubMeshVisible( "icon_03", false )
		self.interactable:setSubMeshVisible( "icon_04", false )
	elseif self.cl.index == 3 then
		self.interactable:setSubMeshVisible( "icon_01", false )
		self.interactable:setSubMeshVisible( "icon_02", false )
		self.interactable:setSubMeshVisible( "icon_03", true )
		self.interactable:setSubMeshVisible( "icon_04", false )
	elseif self.cl.index == 4 then
		self.interactable:setSubMeshVisible( "icon_01", false )
		self.interactable:setSubMeshVisible( "icon_02", false )
		self.interactable:setSubMeshVisible( "icon_03", false )
		self.interactable:setSubMeshVisible( "icon_04", true )
	end

	local prevData = self.interactable.clientPublicData
	self.interactable.clientPublicData = {
		inputUuid = PackingStationScreen.Datasets[self.data.type][self.cl.index].inputUuid,
		projectileAreaTrigger = self.projectileAreaTrigger,
		state = data.state,
		connectionType = prevData and prevData.connectionType or nil,
		lastConnectedTick = prevData and prevData.lastConnectedTick or nil,
	}
	self:cl_updateCount( data.count )
end

function PackingStationScreen.cl_updateCount( self, count )
	self.cl.count = count

	local dataset = self:cl_getDataSet()
	if dataset then
		local fullAmount = dataset.fullAmount

		local count = math.floor( (self.cl.count / fullAmount ) * self.cl.maxDisplayCount )

		if count ~= self.cl.previousDisplayCount and count > 0 then
			local soundIndex = clamp( math.ceil( (count / self.cl.maxDisplayCount) * 10 ), 1, 10 )
			sm.effect.playEffect( "audio:event:/props/installations/packingstation/meter"..tostring( soundIndex ), self.shape.worldPosition )
		end
		self.cl.previousDisplayCount = count
	end
end

function PackingStationScreen.client_onUpdate( self, dt )
	local dataset = self:cl_getDataSet()
	--print(dataset)
	if dataset then
		
		local fullAmount = dataset.fullAmount
		if self.cl.count == 0 then
			self.cl.currentDisplayCount = easeIn( self.cl.currentDisplayCount, self.cl.count, dt, 0.9 )
		elseif self.cl.count == fullAmount then
			self.cl.currentDisplayCount = self.cl.maxDisplayCount
		else
			self.cl.currentDisplayCount = math.floor( (self.cl.count / fullAmount ) * self.cl.maxDisplayCount )
		end
		
		self.interactable:setUvFrameIndex( self.cl.currentDisplayCount )
		
		if self.cl.pumpTimer < self.cl.pumpCurvePose1:duration() then
			self.cl.pumpTimer = self.cl.pumpTimer + dt
		end
		
		if self.cl.open then
			if self.cl.interfaceTimer < 1.0 then
				self.cl.interfaceTimer = self.cl.interfaceTimer + dt * 5
			end
		else
			if self.cl.interfaceTimer > 0.0 then
				self.cl.interfaceTimer = self.cl.interfaceTimer - dt * 5
			end
		end
		
		
		self:cl_acceptConnectionType( fullAmount, dt )
		
		self.interactable:setPoseWeight( 0, self.cl.pumpCurvePose0:getValue( self.cl.pumpTimer ) + self.cl.interfaceTimer )
		self.interactable:setPoseWeight( 1, self.cl.pumpCurvePose1:getValue( self.cl.pumpTimer ) )
	end
end

function PackingStationScreen.cl_n_triggerLoading( self )
	self.cl.pumpTimer = 0.0
	sm.effect.playEffect( "Packingstation - Load", self.shape.worldPosition )
end

function PackingStationScreen.cl_acceptConnectionType( self, fillCount, dt )
	if self.interactable.clientPublicData then
		--disconnect
		local lastConnected = self.interactable.clientPublicData.lastConnectedTick 
		if lastConnected and (sm.game.getCurrentTick() - lastConnected) > 5 then
			self.cl.open = false
			self.interactable.clientPublicData.connectionType = nil
			self.interactable.clientPublicData.lastConnectedTick = nil
			self.cl.lastConnectionType = nil
			self.interactable:setPoseWeight( 2, 0 )
			self.cl.changeColorTimer = ChangeColorDelay
			if self.cl.connectEffect:isPlaying() then
				self.cl.connectEffect:stop()
				self.cl.connectEffectFade:start()
			end
			if self.cl.approvecEffect:isPlaying() then
				self.cl.approvecEffect:stop()
				self.cl.approvecEffectFade:start()
			end
		end
		if self.interactable.clientPublicData.connectionType ~= nil then
			if self.cl.currentDisplayCount >= fillCount then
				self.interactable.clientPublicData.connectionType = "connected"
			end
			if self.cl.lastConnectionType ~= self.interactable.clientPublicData.connectionType then
				self.cl.changeColorTimer = self.cl.changeColorTimer + dt
				if self.cl.changeColorTimer >= ChangeColorDelay then
					self.cl.changeColorTimer = 0.0
					self.cl.lastConnectionType = self.interactable.clientPublicData.connectionType
					if self.interactable.clientPublicData.connectionType == "connected" then
						self.cl.open = false
						self.interactable:setPoseWeight( 2, 0 )
						if not self.cl.connectEffect:isPlaying() then
							self.cl.connectEffect:start()
						end
						if self.cl.approvecEffect:isPlaying() then
							self.cl.approvecEffect:stop()
							self.cl.approvecEffectFade:start()
						end
					elseif self.interactable.clientPublicData.connectionType == "approved" then
						self.cl.open = true
						self.interactable:setPoseWeight( 2, 1 )
						if not self.cl.approvecEffect:isPlaying() then
							self.cl.approvecEffect:start()
						end
						if self.cl.connectEffect:isPlaying() then
							self.cl.connectEffect:stop()
							self.cl.connectEffectFade:start()
						end
					end
				end
			end
		end
	end
end
