MininghubCaster = class( nil )

local AreaTriggerOffset = sm.vec3.new( 0, -35.5, 0 )
local AreaTriggerDimensions = sm.vec3.new( 0.5, 1, 0.5 )
local TargetOffset = sm.vec3.new( 0, 0, -38 )
local CollectionTime = 0.4
local CastAnimationName = "cast"
local RestAnimationName = "rest"
local CraftTickTime = 54 * 40

local CastingOreUuids = {
	ITEMS.obj_moltenorb_t1,
	ITEMS.obj_moltenorb_t2,
	ITEMS.obj_moltenorb_t3,
	ITEMS.obj_moltenorb_t4,
	ITEMS.obj_moltenorb_t5,
}

local DispenserUuids = {
	[tostring(ITEMS.obj_moltenorb_t1)] = { item = ITEMS.obj_castedpart_t1, count = 5 },
	[tostring(ITEMS.obj_moltenorb_t2)] = { item = ITEMS.obj_castedpart_t2, count = 5 },
	[tostring(ITEMS.obj_moltenorb_t3)] = { item = ITEMS.obj_castedpart_t3, count = 5 },
	[tostring(ITEMS.obj_moltenorb_t4)] = { item = ITEMS.obj_castedpart_t4, count = 5 },
	[tostring(ITEMS.obj_moltenorb_t5)] = { item = ITEMS.obj_castedpart_t5, count = 5 }
}

function MininghubCaster.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.casterQueue = {}
		self.sv.saved.isActivated = false
		self.sv.saved.animStartTick = 0
		self:sv_save()
	end

	local shouldSave = false
	self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
	if not self.sv.saved.isActivated then
		if TileStorageManager.Sv_SyncedGetValueInSubTable( self.sv.tileStorageKey, TILESTORAGE_FLAGS_TABLE, "minehub:caster.activated" ) then
			self.sv.saved.isActivated = true
			shouldSave = true
		end
	end

	if self.sv.saved.isActivated then
		self:sv_createAreaTrigger()
	end

	if not IsEmptyTable( self.sv.saved.casterQueue ) then
		if sm.game.getServerTick() - self.sv.saved.animStartTick > CraftTickTime then
			self:sv_n_castingFinished() -- fast forward
		else
			self.sv.saved.animStartTick = sm.game.getCurrentTick()
			self.network:setClientData( self.sv.saved.animStartTick )
			shouldSave = true
		end
	end

	if shouldSave then
		self:sv_save()
	end
end

function MininghubCaster.sv_save( self )
	self.storage:save( self.sv.saved )
end

function MininghubCaster.sv_n_castingFinished( self )
	local queue = TileStorageManager.Sv_GetValue( self.sv.tileStorageKey, "caster" ) or {} -- todo put into own subtable
	for _, uuid in ipairs( self.sv.saved.casterQueue ) do
		local dispenserData = DispenserUuids[tostring( uuid )]
		for i = 1, dispenserData.count do
			queue[#queue + 1] = dispenserData.item
		end
	end

	TileStorageManager.Sv_SetValue( self.sv.tileStorageKey, "caster", queue )
	TileStorageManager.Sv_Save()

	self.sv.saved.casterQueue = {}
	self:sv_save()
end

function MininghubCaster.sv_createAreaTrigger( self )
	local filter = sm.areaTrigger.filter.staticBody + sm.areaTrigger.filter.dynamicBody
	self.sv.areaTrigger = sm.areaTrigger.createAttachedBox( self.interactable, AreaTriggerDimensions, AreaTriggerOffset, sm.quat.identity(), filter )
	self.sv.areaTrigger:setShapeDetection( true )
end

function MininghubCaster.server_onDestroy( self )
	if self.sv.areaTrigger then
		self.sv.areaTrigger:destroy()
		self.sv.areaTrigger = nil
	end
end

function MininghubCaster.server_onFixedUpdate( self )
	if self.sv.saved.isActivated then
		local newEffects = {}
		for _, shapeData in ipairs( self.sv.areaTrigger:getShapes() ) do
			if sm.exists( shapeData.shape ) then
				local shapeUuid = shapeData.shape:getShapeUuid()
				if isAnyOf( shapeUuid, CastingOreUuids ) then
					if IsEmptyTable( self.sv.saved.casterQueue ) then
						self.sv.saved.animStartTick = sm.game.getCurrentTick()
						self.network:setClientData( self.sv.saved.animStartTick )
					end
					self.sv.saved.casterQueue[#self.sv.saved.casterQueue+1] = shapeUuid
					newEffects[#newEffects+1] = { uuid = shapeUuid, pos = shapeData.shape.worldPosition, rot = shapeData.shape.worldRotation }
					sm.shape.destroyShape( shapeData.shape )
				end
			end
		end
		if not IsEmptyTable( newEffects ) then
			self.network:sendToClients( "cl_n_triggerEffects", newEffects )
			self:sv_save()
		end
	else
		if TileStorageManager.Sv_SyncedGetValueInSubTable( self.sv.tileStorageKey, TILESTORAGE_FLAGS_TABLE, "minehub:caster.activated" ) then
			self.sv.saved.isActivated = true
			self:sv_createAreaTrigger()
			self:sv_save()
		end
	end
end

function MininghubCaster.client_onCreate( self )
	self.cl =  {}
	self.cl.loadEffects = {}
	self.cl.activatedEffect = sm.effect.createEffect( "Castermechanics - Activate", self.interactable )
	self.cl.castAnimDuration = self.interactable:getAnimDuration( CastAnimationName )
	self.cl.castAnimProgress = -1
	self.interactable:setAnimEnabled( RestAnimationName, true )
	self.interactable:setAnimProgress( RestAnimationName, 0.5 )
end

function MininghubCaster.cl_n_triggerEffects( self, effectsData )
	for _,effectData in ipairs( effectsData ) do
		local effect = sm.effect.createEffect( "ShapeRenderable" )
		effect:setParameter( "uuid", effectData.uuid )
		effect:setPosition( effectData.pos )
		effect:setRotation( effectData.rot )
		effect:setScale( sm.vec3.new( 0.25, 0.25, 0.25 ) )
		effect:start()
		local newEffectData = {}
		newEffectData.effect = effect
		newEffectData.fromPos = effectData.pos
		newEffectData.elapsedTime = 0.0
		self.cl.loadEffects[#self.cl.loadEffects+1] = newEffectData
	end
end

function MininghubCaster.client_onClientDataUpdate( self, animStartTick )
	if self.cl.castAnimProgress < 0 then
		local timeDiff = ( sm.game.getServerTick() - animStartTick ) / 40
		if timeDiff < 5.0 then -- Only play animation if we're within 5 seconds of delay from when the server started the animiation, otherwise we just consider the client as 'missed the bus'.
			self.interactable:setAnimEnabled( RestAnimationName, false )
			self.interactable:setAnimEnabled( CastAnimationName, true )
			self.interactable:setAnimProgress( CastAnimationName, 0.0 )
			self.cl.castAnimProgress = 0.0
			self.cl.activatedEffect:start()
		end
	end
end

function MininghubCaster.client_onUpdate( self, dt )
	if not IsEmptyTable( self.cl.loadEffects ) then
		local finishedEffectIndexes = {}
		for i,effectData in ipairs( self.cl.loadEffects ) do
			effectData.elapsedTime = effectData.elapsedTime + dt
            local progress = math.min(effectData.elapsedTime / CollectionTime, 1.0 )
			local toPos = self.interactable.shape.worldPosition + TargetOffset
			effectData.effect:setPosition( sm.vec3.lerp( effectData.fromPos, toPos, progress ) )
			if progress >= 1.0 then
				effectData.effect:stop()
				finishedEffectIndexes[#finishedEffectIndexes+1] = i
			end
		end
		if not IsEmptyTable( finishedEffectIndexes ) then
			for _, index in reverse_ipairs( finishedEffectIndexes ) do
				table.remove( self.cl.loadEffects, index )
			end
		end
	end

	if self.cl.castAnimProgress >= 0 then
		self.cl.castAnimProgress = self.cl.castAnimProgress + dt / self.cl.castAnimDuration
		self.interactable:setAnimProgress( CastAnimationName, self.cl.castAnimProgress )
		if self.cl.castAnimProgress > 1.0 then
			self.cl.castAnimProgress = -1
			self.interactable:setAnimEnabled( CastAnimationName, false )
			self.interactable:setAnimEnabled( RestAnimationName, true )
			self.interactable:setAnimProgress( RestAnimationName, 0.5 )
			self.cl.activatedEffect:stopBreakSustain()
			if sm.isHost then
				self.network:sendToServer( "sv_n_castingFinished" )
			end
		end
	end
end
